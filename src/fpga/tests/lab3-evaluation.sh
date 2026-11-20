#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
mkdir -p build

judge() {
    local uart=$1
    shift
    jq --slurpfile uart <(jq -cn --arg status "$uart" '{schema_version:1,uart_status:$status}') \
        -f scripts/lab3-result.jq "$@"
}

for ignore_enter in 0 1; do
    "${IVERILOG:-iverilog}" -g2001 -Wall -s tb_lab3_evaluation \
        -Ptb_lab3_evaluation.IGNORE_ENTER="$ignore_enter" -o build/tb_lab3_evaluation \
        tests/tb_lab3_evaluation.v hdl/lab3_evaluation.v hdl/lab3_text.v hdl/lab3_trace.v \
        hdl/jtag_snapshot.v hdl/uart_rx.v hdl/uart_tx.v
    "${VVP:-vvp}" build/tb_lab3_evaluation +trace=build/lab3-trace.json
    if [[ $ignore_enter == 0 ]]; then
        judge passed build/lab3-trace.json | jq -e '.status == "passed"' >/dev/null
        jq '.after = .before[0:4]' build/lab3-trace.json | judge passed |
            jq -e '.code == "animation_after_parity_error"' >/dev/null
    else
        judge passed build/lab3-trace.json | jq -e '.code == "display_not_cleared"' >/dev/null
    fi
done
printf 'null\n' | judge mismatch | jq -e '.code == "uart_reply"' >/dev/null
printf 'null\n' | judge board_error | jq -e '.code == "uart_exchange_failed"' >/dev/null
printf 'null\n' | judge passed | jq -e '.code == "jtag_trace_unavailable"' >/dev/null
echo 'PASS: Lab 3 animation, UART transcript, no-clear mismatch and transport errors'
