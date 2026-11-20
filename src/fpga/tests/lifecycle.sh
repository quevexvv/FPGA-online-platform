#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

root=$(mktemp -d)
runner=
gate=
trap 'if [[ -n $runner ]]; then kill -KILL "$runner" "$gate" 2>/dev/null || :; wait "$runner" 2>/dev/null || :; fi
      chmod -R u+w -- "$root"; rm -rf -- "$root"' EXIT
export FPGA_JOBS_ROOT=$root/jobs FPGA_DISPATCH_LAUNCH=manual
mkdir -p -- "$FPGA_JOBS_ROOT/incoming" "$root/bin"
export PATH=$root/bin:$PATH
export TEST_LIFECYCLE_ROOT=$root
mkfifo -- "$root/pause"

cat > "$root/bin/mv" <<'MOVE'
#!/usr/bin/env bash
set -euo pipefail
case "${FAIL_MOVE:-}:${!#}" in
    marker:*/control/cleaned.json) echo 'No space left on device' >&2; exit 1 ;;
    result:*/output/result.json) block=true ;;
    finished:*/output/status.json)
        if jq -e '.state == "finished"' "${@: -2:1}" >/dev/null; then block=true; fi ;;
esac
if [[ ${block:-false} == true ]]; then
    printf '%s\n' "$$" > "$TEST_LIFECYCLE_ROOT/gate"
    exec 9<> "$TEST_LIFECYCLE_ROOT/pause"
    read -r -t 10 -u 9 _
fi
exec /usr/bin/mv "$@"
MOVE
cat > "$root/bin/rm" <<'REMOVE'
#!/usr/bin/env bash
[[ ${FAIL_REMOVE:-} != 1 || ${!#} != */output ]] || exit 1
exec /usr/bin/rm "$@"
REMOVE
cat > "$root/bin/systemctl" <<'MANAGER'
#!/usr/bin/env bash
[[ $# == 5 && $1 == --user && $2 == show && $3 == --property=ActiveState && $4 == --value ]] || exit 2
printf '%s\n' inactive
MANAGER
chmod +x -- "$root/bin/"{mv,rm,systemctl}

runs=$FPGA_JOBS_ROOT/runs
incoming=$FPGA_JOBS_ROOT/incoming
prepare() {
    id=aaaaaaaa-bbbb-cccc-dddd-00000000000$1
    job=$runs/$id
    output=$job/output
    local upload=$incoming/$id
    mkdir -p -- "$upload/src"
    jq --arg id "$id" '.run_id=$id' examples/manifest.json > "$upload/manifest.json"
    cp -- examples/counter/student_top.v "$upload/src/student_top.v"
}
dispatch() { bin/fpga-dispatch "$1" --run-id "$id" "${@:2}"; }
submit() { dispatch submit --mode mock | jq -e '.disposition == "accepted"' >/dev/null; }
run() { bin/fpga-run --job "$job/input" --output "$output" --mode mock; }
reject() {
    local expected=$1 code=0
    shift
    "$@" > "$root/rejected.json" 2> "$root/rejected.log" || code=$?
    [[ $code == "$expected" && ! -s $root/rejected.json ]]
}
expect_error() {
    dispatch status | jq -e '.state == "finished" and .result_status == "internal_error"' >/dev/null
    jq -e --arg code "$1" '.error.code == $code and .hardware_verified == false' "$output/result.json" >/dev/null
}
set_launch() {
    jq "$1" "$job/control/launch.json" > "$root/launch.json"
    mv -- "$root/launch.json" "$job/control/launch.json"
}

prepare 1
mkdir -p -- "$runs/.$id.pending/ready"
mv -- "$incoming/$id" "$runs/.$id.pending/upload"
reject 2 dispatch status
[[ -f $incoming/$id/manifest.json && ! -e $runs/.$id.pending ]]
submit
reject 2 dispatch cleanup
set_launch '.launch = "systemd"'
expect_error service_start_failed
reject 2 run

prepare 2
submit
set_launch '.boot_id = "00000000-0000-0000-0000-000000000000"'
expect_error host_restarted
reject 2 run

kill_during_publish() {
    rm -f -- "$root/gate"
    FAIL_MOVE=$1 bin/fpga-run --job "$job/input" --output "$output" --mode mock &
    runner=$!
    for _ in {1..200}; do
        [[ ! -s $root/gate ]] || break
        sleep .01
    done
    gate=$(<"$root/gate")
    dispatch status | jq -e '.state == "running"' >/dev/null
    reject 2 dispatch cleanup
    kill -KILL "$runner" "$gate"
    wait "$runner" 2>/dev/null || [[ $? == 137 ]]
    runner=
    gate=
    flock -w 2 "$job/control/activity.lock" true
}

prepare 3
submit
kill_during_publish result
expect_error interrupted
[[ ! -e $job/work ]]
dispatch submit --mode mock | jq -e '.disposition == "existing"' >/dev/null
reject 2 run

prepare 4
submit
kill_during_publish finished
cp -- "$output/result.json" "$root/result"
dispatch status | jq -e '.state == "finished" and .result_status == "passed"' >/dev/null
cmp -- "$root/result" "$output/result.json"
[[ ! -e $job/work ]]
for damage in '.finished_at = "2000-01-01T00:00:00Z"' '.stage = "testing"'; do
    jq "$damage" "$output/status.json" > "$root/broken-status.json"
    mv -- "$root/broken-status.json" "$output/status.json"
    dispatch status | jq -e --slurpfile result "$root/result" '
        .state == "finished" and .stage == "finalizing" and
        .result_status == $result[0].status and .started_at == $result[0].started_at and
        .finished_at == $result[0].finished_at and .updated_at == $result[0].finished_at
    ' >/dev/null
    cmp -- "$root/result" "$output/result.json"
done
rm -- "$output/result.json"
reject 1 dispatch cleanup
expect_error result_missing

prepare 7
submit
run
jq '.observations[0] |= (
    .mask = "0x3ffff" |
    .expected_dout = (if .dout == "0x00000" then "0x00001" else "0x00000" end)
)' "$output/result.json" > "$root/broken-result.json"
mv -- "$root/broken-result.json" "$output/result.json"
reject 1 dispatch cleanup
expect_error result_invalid
echo 'PASS: pending registration, host restart, killed process, result recovery and missing or invalid result'

prepare 5
submit
run
[[ ! -e $job/work && -f $output/result.json && -f $job/input/src/student_top.v ]]
mkdir -p -- "$root/outside"
touch -- "$root/outside/keep"
ln -s -- "$root/outside" "$job/work"
reject 1 dispatch cleanup
[[ -L $job/work && -f $root/outside/keep && ! -e $job/control/cleaned.json ]]
unlink -- "$job/work"
ln -s -- "$root/outside" "$output/link"
FAIL_MOVE=marker reject 1 dispatch cleanup
[[ -f $job/input/src/student_top.v && -f $output/result.json ]]
FAIL_REMOVE=1 reject 1 dispatch cleanup
[[ -f $job/control/cleaned.json && -f $output/result.json ]]
dispatch status > "$root/status.json" & reader=$!
dispatch cleanup > "$root/cleanup.json"
wait "$reader"
cmp -- "$root/status.json" "$root/cleanup.json"
jq -e --arg id "$id" '. == {schema_version:1,run_id:$id,state:"cleaned"}' "$root/cleanup.json" >/dev/null
[[ ! -e $job/input && ! -e $output && ! -e $job/work && -f $root/outside/keep ]]
[[ $(find "$job/control" -mindepth 1 -maxdepth 1 -printf '%f\n') == cleaned.json ]]
dispatch cleanup | cmp -- "$root/cleanup.json" -
dispatch submit --mode hardware | jq -e '.disposition == "existing"' >/dev/null
reject 2 bin/fpga-dispatch cleanup --run-id ../outside
prepare 6
ln -s -- "$root/outside" "$job"
reject 1 dispatch cleanup
[[ -L $job && -f $root/outside/keep ]]
echo 'PASS: cleanup marker, failed writes and deletions, retries, concurrent status and path containment'
