#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
export FPGA_DISPATCH_LAUNCH=manual

root=$(mktemp -d)
active=
peer=
cleanup() {
    if [[ -n $active ]]; then
        kill -TERM "$active" 2>/dev/null || :
        wait "$active" || :
    fi
    if [[ -n $peer ]]; then
        kill -TERM "$peer" 2>/dev/null || :
        wait "$peer" || :
    fi
    chmod -R u+w -- "$root"
    rm -rf -- "$root"
}
trap cleanup EXIT
export FPGA_JOBS_ROOT=$root/'jobs root'
export TEST_OPERATOR_HOME=$root/'operator home'
unset FPGA_RUN_CONFIG
mkdir -p -- "$FPGA_JOBS_ROOT/incoming" "$TEST_OPERATOR_HOME" "$root/bin"
chmod 700 -- "$TEST_OPERATOR_HOME"
# Keep the account-scoped lock fixture outside all job trees and the real home.
cat > "$root/bin/getent" <<'GETENT'
#!/usr/bin/env bash
set -eu
[[ $# -eq 2 && $1 == passwd && $2 == "$EUID" ]]
printf 'fpga-test:x:%s:0::%s:/bin/bash\n' "$EUID" "$TEST_OPERATOR_HOME"
GETENT
chmod +x -- "$root/bin/getent"
export PATH="$root/bin:$PATH"
stand_lock=$TEST_OPERATOR_HOME/.fpga-stand-lock
runs=$FPGA_JOBS_ROOT/runs
first=aaaaaaaa-bbbb-cccc-dddd-000000000001
second=aaaaaaaa-bbbb-cccc-dddd-000000000002
third=aaaaaaaa-bbbb-cccc-dddd-000000000003
fourth=aaaaaaaa-bbbb-cccc-dddd-000000000004

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
mkdir -m 700 -- "$stand_lock"
exec {held}< "$stand_lock"
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
flock -n "$stand_lock" true

register "$fourth"
mv -- "$stand_lock" "$stand_lock.real"
ln -s -- "$stand_lock.real" "$stand_lock"
run "$fourth" hardware
check_result "$fourth" internal_error
jq -e '.error.code == "stand_lock_error"' "$runs/$fourth/output/result.json" >/dev/null
rm -- "$stand_lock"
rmdir -- "$stand_lock.real"
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
scenario=$(< scenario)
case "$scenario" in
    ok|negative-slack|negative-tns|missing-timing|bad-timing|incomplete-timing)
        mkdir output_files
        echo 'test artifact' > output_files/job.sof
        if [[ $scenario == missing-timing ]]; then exit 0; fi
        slack=9.813 tns=0.000
        if [[ $scenario == negative-slack ]]; then slack=-0.100; fi
        if [[ $scenario == negative-tns ]]; then tns=-0.100; fi
        if [[ $scenario == bad-timing ]]; then slack=invalid; fi
        cat > output_files/job.sta.summary <<SUMMARY
------------------------------------------------------------
Timing Analyzer Summary
------------------------------------------------------------

Type  : Slow 1100mV 85C Model Setup 'clk'
Slack : $slack
TNS   : 0.000

Type  : Slow 1100mV 85C Model Hold 'clk'
Slack : 0.000
TNS   : $tns

Type  : Fast 1100mV 0C Model Minimum Pulse Width 'clk'
Slack : 8.555
TNS   : 0.000

------------------------------------------------------------
SUMMARY
        printf '%s\n' 'Timing Analyzer report for job' > output_files/job.sta.rpt
        if [[ $scenario != incomplete-timing ]]; then
            printf '%s\n' 'Info: Quartus Prime Timing Analyzer was successful. 0 errors, 1 warning' \
                >> output_files/job.sta.rpt
        fi
        ;;
    fail) exit 9 ;;
    missing) mkdir output_files ;;
    linked)
        mkdir output_files
        ln -s ../job.qpf output_files/job.sof
        ;;
    hold)
        trap '' TERM
        setsid /bin/bash -c 'trap "" TERM; echo "$$"; echo "$$" > escaped; exec sleep 30' &
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
        --argjson timeout "$1" --arg port "${2:-/dev/null}" --argjson log_limit "${3:-2048}" '
        {quartus_sh:$executable,quartus_pgm:$programmer,jtag_cable:"USB-Blaster [test]",
         jtag_device_index:1,uart_device:$port,build_timeout_ms:$timeout,program_timeout_ms:2000,
         uart_ready_timeout_ms:300,uart_timeout_ms:100,test_timeout_ms:2000,max_log_bytes:$log_limit}
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
escaped_pid=$(<"$running_project/escaped")
bin/fpga-dispatch status --run-id "$holding" |
    jq -e '.state == "running" and .stage == "building"' >/dev/null
check_cross_root_busy() {
    local FPGA_JOBS_ROOT=$root/'other jobs root'
    local HOME=$root/'other home' FPGA_RUN_CONFIG=$root/'other config.json'
    local runs=$FPGA_JOBS_ROOT/runs id project
    export FPGA_JOBS_ROOT HOME FPGA_RUN_CONFIG
    mkdir -p -- "$FPGA_JOBS_ROOT/incoming" "$HOME"
    config 10000
    prepare_build 11 ok
    run "$id" hardware
    check_result "$id" busy
    check_code "$id" stand_busy
    [[ ! -e $runs/$id/output/logs/build.log ]]
}
check_cross_root_busy
kill -TERM "$active"
wait "$active"
active=
check_result "$holding" internal_error
check_code "$holding" interrupted
! kill -0 "$escaped_pid" 2>/dev/null || exit 1
[[ ! -e $runs/$holding/work ]]
flock -n "$stand_lock" true

prepare_build 12 ok
run "$id" hardware
check_result "$id" board_error
check_code "$id" uart_not_ready
[[ ! -e $runs/$id/work ]]
grep -Fxq 'quartus started' "$runs/$id/output/logs/build.log"
grep -Fxq 'TimeQuest: 3 checks, minimum slack 0.000 ns, minimum TNS 0.000 ns' "$runs/$id/output/logs/timing.log"
jq -e '.logs | index("logs/timing.log") != null' "$runs/$id/output/result.json" >/dev/null
grep -Fxq 'programmer started' "$runs/$id/output/logs/program.log"
grep -q 'transport:open' "$runs/$id/output/logs/uart.log"

for scenario in negative-slack negative-tns missing-timing bad-timing incomplete-timing; do
    case "$scenario" in
        negative-slack) prepare_build 29 "$scenario"; code=timing_failed ;;
        negative-tns) prepare_build 30 "$scenario"; code=timing_failed ;;
        missing-timing) prepare_build 31 "$scenario"; code=timing_report_invalid ;;
        bad-timing) prepare_build 32 "$scenario"; code=timing_report_invalid ;;
        incomplete-timing) prepare_build 33 "$scenario"; code=timing_report_invalid ;;
    esac
    run "$id" hardware
    check_result "$id" build_error
    check_code "$id" "$code"
    [[ ! -e $runs/$id/output/logs/program.log ]]
done
config 2000 /dev/null 12
prepare_build 34 ok
run "$id" hardware
check_result "$id" board_error
check_code "$id" uart_not_ready
[[ $(wc -c < "$runs/$id/output/logs/timing.log") -eq 12 ]]
config 10000
echo 'PASS: TimeQuest gate, retained timing summary and log cap'

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
[[ ! -e $runs/$id/work ]]
[[ ! -e $runs/$id/output/logs/build.log ]]

config 1000
prepare_build 17 hold
run "$id" hardware
check_result "$id" build_error
check_code "$id" build_timeout
escaped_pid=$(sed -n '2p' "$runs/$id/output/logs/build.log")
[[ $escaped_pid =~ ^[0-9]+$ ]]
! kill -0 "$escaped_pid" 2>/dev/null || exit 1
flock -n "$stand_lock" true
echo 'PASS: Quartus stage, shared stand lock across jobs roots, failure, timeout and stale artifact'

config 2000
mkdir -- "$root/limits-bin"
cat > "$root/limits-bin/df" <<'DISK'
#!/usr/bin/env bash
printf 'Avail\n%s\n' "$TEST_AVAILABLE_KIB"
DISK
cat > "$root/limits-bin/du" <<'WORK'
#!/usr/bin/env bash
printf '%s\t%s\n' "$TEST_WORK_KIB" "${!#}"
WORK
chmod +x -- "$root/limits-bin/"{df,du}
# The five fixture logs are capped at 2048 bytes each.
required_kib=$((2176 * 1024 + 10))
prepare_build 26 ok
PATH="$root/limits-bin:$PATH" TEST_AVAILABLE_KIB=$((required_kib - 1)) run "$id" hardware
check_result "$id" internal_error
check_code "$id" disk_space_low
[[ ! -e $runs/$id/output/logs/build.log ]]
prepare_build 27 ok
PATH="$root/limits-bin:$PATH" TEST_AVAILABLE_KIB=$required_kib TEST_WORK_KIB=131073 run "$id" hardware
check_result "$id" build_error
check_code "$id" workspace_limit
[[ ! -e $runs/$id/output/logs/program.log ]]
prepare_build 28 ok
PATH="$root/limits-bin:$PATH" TEST_AVAILABLE_KIB=$required_kib TEST_WORK_KIB=131072 run "$id" hardware
check_result "$id" board_error
check_code "$id" uart_not_ready
[[ -f $runs/$id/output/logs/program.log ]]
echo 'PASS: disk reserve and Quartus workspace boundaries'

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

prepare_build 20 ok
printf '%s\n' '[{"vector_index":0,"reset_before":true,"din":"0x400","steps":0,
                    "expected_dout":"0x00000","mask":"0x3ffff"}]' > "$runs/$id/work/test-set.json"
run "$id" hardware
check_result "$id" internal_error
check_code "$id" test_set_invalid
[[ ! -e $runs/$id/output/logs/build.log ]]

vectors=examples/lab2/lab2_running_led.json
jq -ecn --slurpfile vectors "$vectors" \
    --arg replies $'K\nK\nK\nD 0x00001\nK\nK\nD 0x00008\nK\n' \
    -f scripts/observations.jq |
    jq -e '.complete == false and [.observations[].dout] == ["0x00001","0x00008"]' >/dev/null
jq -ecn --slurpfile vectors "$vectors" \
    --arg replies $'K\nK\nK\nD 0x00001\nK\nK\nD 0x00008\nK\nK\nD 0x00004\n' \
    -f scripts/observations.jq |
    jq -e '.complete == true and [.observations[].steps] == [0,3,1]' >/dev/null
echo 'PASS: vector widths and complete or partial UART observations'

run_with_peer() {
    local transcript=$1 ready=$root/$id.port peer_code=0
    ./build/test-uart-peer "$transcript" "$ready" &
    peer=$!
    for _ in {1..200}; do
        [[ -s $ready ]] && break
        sleep .01
    done
    [[ -s $ready ]]
    config 2000 "$(<"$ready")"
    run "$id" hardware
    kill -TERM "$peer"
    wait "$peer" || peer_code=$?
    peer=
    [[ $peer_code == 143 ]]
}

for bad in '2D00000' 'garbage'; do
    if [[ $bad == '2D00000' ]]; then prepare_build 21 ok; else prepare_build 22 ok; fi
    printf '1Q0000 %s\n' "$bad" > "$root/bad-frames"
    run_with_peer "$root/bad-frames"
    check_result "$id" board_error
    check_code "$id" uart_not_ready
    grep -q 'protocol:invalid_response' "$runs/$id/output/logs/uart.log"
    [[ ! -e $runs/$id/output/logs/test.log ]]
done

for scenario in passed mismatch partial; do
    case "$scenario" in
        passed) prepare_build 23 ok; last='1D00003' ;;
        mismatch) prepare_build 24 ok; last='1D00002' ;;
        partial) prepare_build 25 ok; last=- ;;
    esac
    cat > "$runs/$id/work/test-set.json" <<'VECTORS'
[
  {"vector_index":0,"reset_before":true,"din":"0x001","steps":3,"expected_dout":"0x00003","mask":"0x00003"},
  {"vector_index":1,"reset_before":false,"din":"0x002","steps":0,"expected_dout":"0x00003","mask":"0x3ffff"}
]
VECTORS
    cat > "$root/frames" <<'FRAMES'
1Q0000 1D00000
1S0000 1K00000
1Q0000 1D00000
1R0000 1K00000
1I0001 1K00000
1S0003 1K00000
1Q0000 1D00103
1I0002 1K00000
1S0000 1K00000
FRAMES
    printf '1Q0000 %s\n' "$last" >> "$root/frames"
    run_with_peer "$root/frames"
    result=$runs/$id/output/result.json
    jq -e '.observations[0].dout == "0x00103" and .observations[0].match' "$result" >/dev/null
    case "$scenario" in
        passed|mismatch)
            check_result "$id" "$scenario"
            jq -e '.hardware_verified and .summary.executed == 2 and .error == null' "$result" >/dev/null
            ;;
        partial)
            check_result "$id" board_error
            check_code "$id" uart_test_failed
            jq -e '.summary == {planned:2,executed:1,passed:1,failed:0}' "$result" >/dev/null
            ;;
    esac
done
echo 'PASS: UART probe, masked pass, full mismatch and partial board result'
