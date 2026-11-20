#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

uart_report() { printf '{"schema_version":1,"uart_status":"%s"}\n' "$1"; }

if [[ $# == 2 && $1 == uart ]]; then
    port=$2
    # shellcheck source=scripts/stand-lock.sh
    source "$project/scripts/stand-lock.sh"
    if ! open_hardware_stand_lock; then
        printf '%s\n' "$hardware_lock_error" >&2
        exit 1
    fi
    flock -n -E 75 "$stand_lock"
    stimulus=$project/build/fpga-uart-stimulus
    [[ -x $stimulus ]] || { echo 'Run make all first' >&2; exit 2; }
    check_reply() {
        local parity=$1 input=$2 expected=$3 observed
        if ! observed=$("$stimulus" "$port" "$parity" "$input" "$(( ${#expected} / 2 ))"); then
            uart_report board_error
            exit 0
        fi
        if [[ $observed != "$expected" ]]; then
            printf 'Unexpected UART reply %s (expected %s)\n' "$observed" "$expected" >&2
            uart_report mismatch
            exit 0
        fi
    }
    check_reply even 313233343536 313233343536
    sleep 4.3
    check_reply odd 39 25
    sleep 4.3
    check_reply even 0d 1b5b324a1b5b48
    uart_report passed
elif [[ $# == 4 && $1 == jtag ]]; then
    if [[ $(jq -er .uart_status "$2") == passed ]]; then
        trace=$(bash "$project/scripts/jtag-observe.sh" lab3-trace "$3" "$4") || trace=null
    else
        trace=null
    fi
    jq --slurpfile uart "$2" -f "$project/scripts/lab3-result.jq" <<< "$trace"
else
    echo 'Usage: lab3-evaluate.sh uart <port> | jtag <uart-report> <cable-name> <device-index>' >&2
    exit 2
fi
