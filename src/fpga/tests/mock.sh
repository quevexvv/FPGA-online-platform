#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

FPGA_JOBS_ROOT=$(mktemp -d)
export FPGA_JOBS_ROOT
trap 'chmod -R u+w -- "$FPGA_JOBS_ROOT"; rm -rf -- "$FPGA_JOBS_ROOT"' EXIT
export IVERILOG=/no-such-iverilog
unset FPGA_RUN_CONFIG

upload() {
    id=aaaaaaaa-bbbb-cccc-dddd-00000000000$1
    job=$FPGA_JOBS_ROOT/runs/$id
    local path=$FPGA_JOBS_ROOT/incoming/$id
    mkdir -p -- "$path/src"
    jq --arg id "$id" --arg model "$2" --arg kind "$3" \
        '.run_id=$id | .test_set=$model | .kind=$kind' examples/manifest.json > "$path/manifest.json"
    echo 'intentionally not Verilog' > "$path/src/student_top.v"
}
submit() { bin/fpga-dispatch submit --run-id "$id" --mode "$1"; }
run() { bin/fpga-run --job "$job/input" --output "$job/output" --mode mock; }
check() {
    jq -e --arg kind result -f scripts/contract.jq "$job/output/result.json" >/dev/null
    jq -e --arg status "$1" '.status == $status and .mode == "mock" and
        .hardware_verified == false and .logs == []' "$job/output/result.json" >/dev/null
    [[ ! -e $job/work/quartus ]]
}

upload 1 counter-v1 sequential
submit mock >/dev/null
if submit hardware >/dev/null 2>&1; then exit 1; fi
run
check passed
jq -e '.observations[0].dout == "0x00003"' "$job/output/result.json" >/dev/null

upload 2 combinational-v1 combinational
submit mock >/dev/null
jq '.[0].expected_dout = "0x00000"' "$job/work/test-set.json" > "$job/work/altered.json"
mv -- "$job/work/altered.json" "$job/work/test-set.json"
run
check mismatch
jq -e '.observations[0].dout == "0x002aa" and .observations[0].match == false' \
    "$job/output/result.json" >/dev/null

upload 3 mock-uart-error-v1 sequential
submit mock >/dev/null
run
check board_error
jq -e '.error.code == "mock_uart_timeout" and .summary.executed == 0' \
    "$job/output/result.json" >/dev/null

upload 4 unknown sequential
code=0
submit mock >/dev/null 2>&1 || code=$?
[[ $code == 2 && ! -e $job ]]
echo 'PASS: explicit mock models, mismatch and simulated UART error'
