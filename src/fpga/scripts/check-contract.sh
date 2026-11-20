#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

unset FPGA_DISPATCH_LAUNCH FPGA_RUN_CONFIG
root=$(mktemp -d)
export FPGA_JOBS_ROOT="$root/jobs"
read -r id < /proc/sys/kernel/random/uuid
printf 'Reports: %s\nRun ID: %s\n' "$root" "$id"
upload="$FPGA_JOBS_ROOT/incoming/$id"
output="$FPGA_JOBS_ROOT/runs/$id/output"
mkdir -p "$upload/src"
jq --arg id "$id" '.run_id = $id' examples/manifest.json > "$upload/manifest.json"
cp examples/counter/student_top.v "$upload/src/student_top.v"
check() { jq -e --arg kind "$1" -f scripts/contract.jq "${@:2}" >/dev/null; }
check manifest "$upload/manifest.json"

submit() { bin/fpga-dispatch submit --run-id "$id" --mode mock; }
status() { bin/fpga-dispatch status --run-id "$id"; }
cleanup() { bin/fpga-dispatch cleanup --run-id "$id"; }
submit | jq -e --arg id "$id" \
    '. == {schema_version:1,run_id:$id,disposition:"accepted"}'
for ((attempt = 0; attempt < 30; attempt++)); do
    status > "$root/status.json"
    check status "$root/status.json"
    if jq -e '.state == "finished"' "$root/status.json" >/dev/null; then break; fi
    sleep 1
done
if ! jq -e --arg id "$id" \
    '.run_id == $id and .mode == "mock" and .state == "finished" and
     .result_status == "passed"' "$root/status.json" >/dev/null; then
    echo 'The mock run did not finish successfully within the polling window.' >&2
    cat -- "$root/status.json" >&2
    exit 1
fi
check result "$output/result.json"
jq -e --slurpfile status "$root/status.json" '
    $status[0] as $s |
    .run_id == $s.run_id and .mode == $s.mode and .status == $s.result_status and
    .started_at == $s.started_at and .finished_at == $s.finished_at and
    .hardware_verified == false and .observations[0].dout == "0x00003"
' "$output/result.json" >/dev/null
cp "$output/result.json" "$root/result.json"

submit | jq -e --arg id "$id" \
    '. == {schema_version:1,run_id:$id,disposition:"existing"}'
for ((attempt = 0; attempt < 5; attempt++)); do
    if cleanup > "$root/cleaned.json"; then break; fi
    sleep 1
done
jq -e --arg id "$id" '. == {schema_version:1,run_id:$id,state:"cleaned"}' "$root/cleaned.json" >/dev/null
cleanup | cmp "$root/cleaned.json" -
status | cmp "$root/cleaned.json" -
submit | jq -e --arg id "$id" \
    '. == {schema_version:1,run_id:$id,disposition:"existing"}' >/dev/null
test ! -e "$output"
echo 'PASS: mock result, repeated submit and cleanup'
