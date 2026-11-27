#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || ! $1 =~ ^(program|program-sram-check|program-sram-helper-check|probe|snapshot|lab3-trace|sram-check)$ || ! $3 =~ ^[1-9][0-9]*$ ]]; then
    echo 'Usage: bash scripts/jtag-observe.sh <operation> <cable-name> <device-index>' >&2
    echo 'Operations: program, probe, snapshot, lab3-trace, program-sram-check, program-sram-helper-check, sram-check' >&2
    exit 2
fi

project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=scripts/stand-lock.sh
source "$project/scripts/stand-lock.sh"
if ! open_hardware_stand_lock; then
    printf '%s\n' "$hardware_lock_error" >&2
    exit 1
fi
lock_result=0
flock -n -E 75 "$stand_lock" || lock_result=$?
case "$lock_result" in
    0) ;;
    75) echo 'Stand is already in use' >&2; exit 75 ;;
    *) echo 'Cannot lock the stand' >&2; exit 1 ;;
esac

case "$1" in
    program) artifact=jtag-probe/jtag_probe.sof ;;
    program-sram-check) artifact=sram-check/sram_check.sof ;;
    program-sram-helper-check) artifact=sram-helper-check/sram_helper_check.sof ;;
    *) artifact= ;;
esac
if [[ -n $artifact ]]; then
    cd -- "$project/build"
    [[ -f $artifact && ! -L $artifact ]] || {
        echo "Build the trusted $artifact project first" >&2
        exit 1
    }
    exec timeout --kill-after=2s 30s quartus_pgm -c "$2" -m JTAG -o "p;$artifact@$3"
fi

if [[ $1 == probe ]]; then
    exec timeout --kill-after=2s 30s quartus_stp -t "$project/scripts/jtag-observe.tcl" "$@"
fi

# shellcheck source=scripts/jtag-capture.sh
source "$project/scripts/jtag-capture.sh"
capture_jtag_json "$project/scripts/jtag-observe.tcl" "$@"
