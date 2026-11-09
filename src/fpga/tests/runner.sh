#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

root=$(mktemp -d)
active=
cleanup() {
    if [[ -n $active ]]; then
        kill -TERM "$active" 2>/dev/null || :
        wait "$active" || :
    fi
    chmod -R u+w -- "$root"
    rm -rf -- "$root"
}
trap cleanup EXIT
export FPGA_JOBS_ROOT=$root/'jobs root'
unset FPGA_RUN_CONFIG
mkdir -p -- "$FPGA_JOBS_ROOT/incoming"
runs=$FPGA_JOBS_ROOT/runs
first=aaaaaaaa-bbbb-cccc-dddd-000000000001
second=aaaaaaaa-bbbb-cccc-dddd-000000000002
third=aaaaaaaa-bbbb-cccc-dddd-000000000003

register() {
    local id=$1 upload=$FPGA_JOBS_ROOT/incoming/$1
    mkdir -p -- "$upload/src"
    jq --arg id "$id" '.run_id=$id' examples/manifest.json > "$upload/manifest.json"
    cp -- examples/counter/student_top.v "$upload/src/student_top.v"
    bin/fpga-dispatch submit --run-id "$id" --mode hardware >/dev/null
}
run() {
    local job=$runs/$1
    bin/fpga-run --job "$job/input" --output "$job/output" --mode "$2"
}
reject() {
    local code=0
    "$@" > "$root/rejected.json" 2> "$root/rejected.log" || code=$?
    [[ $code == 2 && ! -s $root/rejected.json ]]
}
check_result() {
    local id=$1 result=$2 output=$runs/$1/output
    jq -e --arg kind result -f scripts/contract.jq "$output/result.json" >/dev/null
    jq -e --arg kind status -f scripts/contract.jq "$output/status.json" >/dev/null
    jq -e --arg result "$result" '.status == $result' "$output/result.json" >/dev/null
    jq -e --arg result "$result" '.state == "finished" and .result_status == $result' \
        "$output/status.json" >/dev/null
}

reject run "$first" hardware
register "$first"
register "$second"
reject run "$first" mock
reject bin/fpga-run --job "$runs/$first/input" --output "$runs/$second/output" --mode hardware
[[ ! -e $runs/$first/control/started ]]

# Hold a lock with another open file description, outside the runner.
exec {held}>> "$runs/.stand.lock"
flock -x "$held"
run "$first" hardware
run "$second" hardware
check_result "$first" busy
check_result "$second" busy
jq -e '.started_at == null and .error.stage == "locking"' "$runs/$first/output/result.json" >/dev/null
flock -u "$held"
exec {held}>&-
reject run "$first" hardware

register "$third"
run "$third" hardware
check_result "$third" internal_error
flock -n "$runs/.stand.lock" true
echo 'PASS: executor registration, busy result and lock release'

tool=$root/'fake quartus'
programmer=$root/'fake programmer'
export FPGA_RUN_CONFIG=$root/config.json
export FPGA_TEST_PRIVATE='must not reach the stage'
cat > "$tool" <<'QUARTUS'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 3 && $1 == --flow && $2 == compile && $3 == job && ! -v FPGA_TEST_PRIVATE ]]
[[ -d $HOME && -d $TMPDIR && -f job.qpf ]]
echo 'quartus started'
case $(< scenario) in
    ok)
        mkdir output_files
        echo 'test artifact' > output_files/job.sof
        ;;
    fail) exit 9 ;;
    missing) mkdir output_files ;;
    linked)
        mkdir output_files
        ln -s ../job.qpf output_files/job.sof
        ;;
    hold)
        trap '' TERM
        setsid /bin/bash -c 'trap "" TERM; echo "$$" > escaped; exec sleep 30' &
        wait
        ;;
esac
QUARTUS
chmod +x -- "$tool"
cat > "$programmer" <<'PROGRAMMER'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 6 && $1 == -c && $2 == 'USB-Blaster [test]' && $3 == -m && $4 == JTAG &&
   $5 == -o && $6 == 'p;output_files/job.sof@1' && -s output_files/job.sof ]]
[[ ! -v FPGA_TEST_PRIVATE ]]
echo 'programmer started'
[[ ! -f program-fail ]]
PROGRAMMER
chmod +x -- "$programmer"

config() {
    jq -cn --arg executable "$tool" --arg programmer "$programmer" \
        --argjson timeout "$1" --arg port "${2:-/dev/null}" '
        {quartus_sh:$executable,quartus_pgm:$programmer,jtag_cable:"USB-Blaster [test]",
         jtag_device_index:1,uart_device:$port,build_timeout_ms:$timeout,program_timeout_ms:2000,
         uart_ready_timeout_ms:300,uart_timeout_ms:100,max_log_bytes:2048}
    ' > "$FPGA_RUN_CONFIG"
}
prepare_build() {
    id=aaaaaaaa-bbbb-cccc-dddd-0000000000$1
    register "$id"
    project=$runs/$id/work/quartus
    printf '%s\n' "$2" > "$project/scenario"
}
check_code() {
    jq -e --arg code "$2" '.error.code == $code and .hardware_verified == false' \
        "$runs/$1/output/result.json" >/dev/null
}

config 10000
prepare_build 10 hold
holding=$id
running_project=$project
bin/fpga-run --job "$runs/$id/input" --output "$runs/$id/output" --mode hardware &
active=$!
for _ in {1..200}; do
    [[ -s $running_project/escaped ]] && break
    sleep .01
done
[[ -s $running_project/escaped ]]
bin/fpga-dispatch status --run-id "$holding" |
    jq -e '.state == "running" and .stage == "building"' >/dev/null
prepare_build 11 ok
run "$id" hardware
check_result "$id" busy
[[ ! -e $runs/$id/output/logs/build.log ]]
kill -TERM "$active"
wait "$active"
active=
check_result "$holding" internal_error
check_code "$holding" interrupted
! kill -0 "$(<"$running_project/escaped")" 2>/dev/null || exit 1
flock -n "$runs/.stand.lock" true

prepare_build 12 ok
run "$id" hardware
check_result "$id" board_error
check_code "$id" uart_not_ready
[[ -s $project/output_files/job.sof ]]
grep -Fxq 'quartus started' "$runs/$id/output/logs/build.log"
grep -Fxq 'programmer started' "$runs/$id/output/logs/program.log"
grep -q 'transport:open' "$runs/$id/output/logs/uart.log"

for scenario in fail missing linked; do
    case "$scenario" in
        fail) prepare_build 13 "$scenario"; code=quartus_failed ;;
        missing) prepare_build 14 "$scenario"; code=missing_sof ;;
        linked) prepare_build 15 "$scenario"; code=missing_sof ;;
    esac
    run "$id" hardware
    check_result "$id" build_error
    check_code "$id" "$code"
    grep -Fxq 'quartus started' "$runs/$id/output/logs/build.log"
done
prepare_build 16 ok
mkdir -- "$project/output_files"
echo 'stale' > "$project/output_files/job.sof"
run "$id" hardware
check_result "$id" build_error
check_code "$id" output_exists
grep -Fxq 'stale' "$project/output_files/job.sof"
[[ ! -e $runs/$id/output/logs/build.log ]]

config 1000
prepare_build 17 hold
run "$id" hardware
check_result "$id" build_error
check_code "$id" build_timeout
[[ -s $project/escaped ]]
! kill -0 "$(<"$project/escaped")" 2>/dev/null || exit 1
flock -n "$runs/.stand.lock" true
echo 'PASS: Quartus stage, active stand lock, failure, timeout and stale artifact'

config 2000
prepare_build 18 ok
touch -- "$project/program-fail"
run "$id" hardware
check_result "$id" board_error
check_code "$id" program_failed
[[ ! -e $runs/$id/output/logs/uart.log ]]

config 2000 "$root/missing-port"
prepare_build 19 ok
run "$id" hardware
check_result "$id" board_error
check_code "$id" uart_not_ready
[[ -f $runs/$id/output/logs/uart.log ]]
echo 'PASS: programmer arguments, programming failure and absent UART'
