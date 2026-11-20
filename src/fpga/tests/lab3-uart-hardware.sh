#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

if [[ $# != 1 || -z $1 ]]; then
    echo 'Set UART_PORT to the FT232R device for the Lab 3 probe' >&2
    exit 2
fi
port=$1

check_reply() {
    local parity=$1 request=$2 expected=$3 reply
    reply=$(build/fpga-uart-stimulus "$port" "$parity" "$request" "$(( ${#expected} / 2 ))")
    if [[ $reply != "$expected" ]]; then
        printf 'Unexpected %s reply for %s: %s (expected %s)\n' "$parity" "$request" "$reply" "$expected" >&2
        exit 3
    fi
}

# Clear any line left in the probe by an earlier invocation.
initial=$(build/fpga-uart-stimulus "$port" even 0d 1)
[[ $initial =~ ^3[0-4]$ ]] || { echo 'Unexpected Lab 3 probe initialization reply' >&2; exit 3; }
check_reply even 41424344450d 414243442134
check_reply even 5a 5a
check_reply odd 41430d 252525
check_reply even 0d0d41430d 3130414332
echo 'PASS: FT232R 8E1, intentional 8O1, Enter and line limit'
