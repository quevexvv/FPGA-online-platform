#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

root=$(mktemp -d)
trap 'chmod -R u+w -- "$root"; rm -rf -- "$root"' EXIT
export FPGA_JOBS_ROOT=$root/'jobs root'
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
