#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
mkdir -p build
"${IVERILOG:-iverilog}" -g2001 -Wall -s tb_simulator -o build/simulator tests/tb_simulator.v
"${VVP:-vvp}" build/simulator
"${IVERILOG:-iverilog}" -g2001 -Wall -DNEGATIVE_TEST -s tb_simulator \
    -o build/simulator-negative tests/tb_simulator.v
if "${VVP:-vvp}" build/simulator-negative; then
    echo 'FAIL: simulator accepted the intentionally wrong result' >&2
    exit 1
else
    code=$?
    [[ $code == 1 ]] || { echo "FAIL: unexpected exit $code" >&2; exit 1; }
fi
echo 'PASS: intentional assertion failure returns 1'
