#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || ! $1 =~ ^(program|program-sram-check|probe|snapshot|lab3-trace|sram-check)$ || ! $3 =~ ^[1-9][0-9]*$ ]]; then
    echo 'Usage: bash scripts/jtag-observe.sh program|program-sram-check|probe|snapshot|lab3-trace|sram-check <cable-name> <device-index>' >&2
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

if [[ $1 == program || $1 == program-sram-check ]]; then
    artifact=jtag-probe/jtag_probe.sof
    if [[ $1 == program-sram-check ]]; then artifact=sram-check/sram_check.sof; fi
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

# Keep stdout reserved for the snapshot. Publish only after quartus_stp succeeds.
snapshot=$(timeout --kill-after=2s 30s quartus_stp -t "$project/scripts/jtag-observe.tcl" "$@" |
    awk '/^SNAPSHOT / {print substr($0, 10); next} {print > "/dev/stderr"}') || exit "$?"
if [[ -z $snapshot || $snapshot == *$'\n'* ]]; then
    echo 'Expected exactly one JTAG snapshot' >&2
    exit 1
fi
printf '%s\n' "$snapshot"
