#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -c $1 ]]; then
    echo 'Set UART_PORT to the serial device for the programmed C5G counter.' >&2
    exit 2
fi

commands() {
    printf '%s\n' reset 'input 0001' 'step 0000' read 'step 0001' read
    printf '%s\n' 'step 0007' read 'step ffff' 'step 0002' read
    sleep 1 || return
    printf '%s\n' read reset read 'step 0003' read
}

actual=$(commands | ./build/fpga-uart "$1" 1000)
printf '%s\n' "$actual"
diff -u <(printf '%s\n' K K K 'D 0x00000' K 'D 0x00001' K 'D 0x00008' \
    K K 'D 0x10009' 'D 0x10009' K 'D 0x00000' K 'D 0x00003') <(printf '%s\n' "$actual")
echo 'PASS: C5G counter STEP and UART acceptance'
