#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

root=$(mktemp -d)
trap 'chmod -R u+w -- "$root"; rm -rf -- "$root"' EXIT
export FPGA_JOBS_ROOT=$root/jobs FPGA_DISPATCH_LAUNCH=manual
mkdir -p -- "$FPGA_JOBS_ROOT/incoming"

submit() {
    local id
    id=$(bash scripts/demo-submit.sh "$1" | jq -er 'select(.disposition == "accepted") | .run_id')
    run=$FPGA_JOBS_ROOT/runs/$id
}

submit hardware
jq -e '.mode == "hardware" and .state == "starting"' "$run/output/status.json" >/dev/null
submit invalid-hdl
jq -e '.mode == "hardware" and .status == "invalid_input" and .error.code == "hdl_invalid"' \
    "$run/output/result.json" >/dev/null

submit mock-uart-timeout
bin/fpga-run --job "$run/input" --output "$run/output" --mode mock
jq -e '.mode == "mock" and .hardware_verified == false and .status == "board_error" and
       .error.code == "mock_uart_timeout"' "$run/output/result.json" >/dev/null
submit mock
bin/fpga-run --job "$run/input" --output "$run/output" --mode mock
jq -e '.mode == "mock" and .hardware_verified == false and .status == "passed" and
       .observations[0].dout == "0x00003"' "$run/output/result.json" >/dev/null
echo 'PASS: demo registration, invalid HDL, simulated UART timeout and new mock run'
