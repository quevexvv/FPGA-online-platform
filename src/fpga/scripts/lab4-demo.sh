#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

if [[ $# != 3 || ! $2 =~ ^[1-9][0-9]*$ || $3 != /dev/* ]]; then
    echo 'Usage: fpga-dispatch lab4-demo <cable-name> <device-index> <uart-device>' >&2
    exit 2
fi
cable=$1 index=$2 port=$3
stimulus=$project/build/fpga-uart-stimulus
artifact=$project/build/lab4-evaluation/lab4_evaluation.sof
[[ -x $stimulus && -s $artifact && ! -L $artifact ]] || {
    echo 'Run make all build-lab4-evaluation first' >&2
    exit 2
}

observations='[]'
finish() {
    jq -cn --arg status "$1" --arg code "$2" --argjson observations "$observations" \
        '{schema_version:1, mode:"hardware", status:$status, hardware_verified:($status=="passed"),
          code:($code | select(length>0) // null), observations:$observations}'
    exit 0
}
# shellcheck source=scripts/stand-lock.sh
source "$project/scripts/stand-lock.sh"
open_hardware_stand_lock || finish board_error stand_lock_failed
lock_status=0
flock -n -E 75 "$stand_lock" || lock_status=$?
if ((lock_status == 75)); then finish busy stand_busy; fi
if ((lock_status != 0)); then finish board_error stand_lock_failed; fi
[[ -c $port && -r $port && -w $port ]] || finish board_error uart_not_ready
# shellcheck source=scripts/jtag-capture.sh
source "$project/scripts/jtag-capture.sh"
cd -- "$(dirname -- "$artifact")"
timeout --kill-after=2s 30s quartus_pgm -c "$cable" -m JTAG \
    -o "p;lab4_evaluation.sof@$index" >&2 || finish board_error program_failed

uart() {
    local parity=$1 input=$2 expected=$3 reply
    reply=$(timeout --kill-after=1s 5s "$stimulus" "$port" "$parity" "$input" "$((${#expected}/2))") ||
        finish board_error uart_exchange_failed
    [[ $reply == "$expected" ]] || finish mismatch uart_reply
}
frame() {
    local phase=$1 expected=$2 snapshot value
    snapshot=$(capture_jtag_json "$project/scripts/jtag-observe.tcl" lab4-frame "$cable" "$index") ||
        finish board_error jtag_snapshot_failed
    value=$(jq -er '.frame | select(type=="number" and floor==. and .>=0 and .<268435456)' <<< "$snapshot") ||
        finish board_error jtag_snapshot_invalid
    observations=$(jq -c --arg phase "$phase" --argjson frame "$value" --argjson expected "$expected" \
        '. + [{phase:$phase, frame:$frame, expected_frame:$expected}]' <<< "$observations")
    [[ $value == "$expected" ]] || finish mismatch "$phase"
}

first=$((6*128**3 + 91*128**2 + 79*128 + 102))
second=$((111*128**3 + 127*128**2 + 7*128 + 125))
frame reset 0
uart even 31323334 31323334
uart odd 35 25
frame first_before_enter 0
uart even 0d 1b5b324a1b5b48
frame first_after_enter "$first"
uart even 39383736 39383736
frame overwrite_before_enter "$first"
uart even 0d 1b5b324a1b5b48
frame overwrite_after_enter "$second"
finish passed ''
