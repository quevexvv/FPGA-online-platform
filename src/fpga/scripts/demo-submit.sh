#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

usage() {
    echo 'Usage: FPGA_JOBS_ROOT=/absolute/demo/jobs bash scripts/demo-submit.sh hardware|mock|invalid-hdl|mock-uart-timeout' >&2
}

if [[ $# != 1 ]]; then usage; exit 2; fi
mode=hardware
test_set=counter-v1
case "$1" in
    hardware|invalid-hdl) ;;
    mock) mode=mock ;;
    mock-uart-timeout) mode=mock; test_set=mock-uart-error-v1 ;;
    *) usage; exit 2 ;;
esac

if [[ ${FPGA_JOBS_ROOT:-} != /* || ! -d $FPGA_JOBS_ROOT/incoming ||
      -L $FPGA_JOBS_ROOT || -L $FPGA_JOBS_ROOT/incoming ]]; then
    echo 'Set FPGA_JOBS_ROOT to an absolute demo jobs root with an incoming directory.' >&2
    exit 2
fi

read -r id < /proc/sys/kernel/random/uuid
upload=$FPGA_JOBS_ROOT/incoming/$id
mkdir -m 700 -- "$upload" "$upload/src"
jq --arg id "$id" --arg test_set "$test_set" \
    '.run_id = $id | .test_set = $test_set' examples/manifest.json > "$upload/manifest.json"
if [[ $1 == invalid-hdl ]]; then
    printf 'module student_top(\n' > "$upload/src/student_top.v"
else
    cp -- examples/counter/student_top.v "$upload/src/student_top.v"
fi
printf 'Demo run ID: %s\n' "$id" >&2
exec bin/fpga-dispatch submit --run-id "$id" --mode "$mode"
