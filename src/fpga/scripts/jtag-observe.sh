#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || ( $1 != program && $1 != probe ) || ! $3 =~ ^[1-9][0-9]*$ ]]; then
    echo 'Usage: bash scripts/jtag-observe.sh program|probe <cable-name> <device-index>' >&2
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

if [[ $1 == program ]]; then
    cd -- "$project/build/jtag-probe"
    [[ -f jtag_probe.sof && ! -L jtag_probe.sof ]] || {
        echo 'Build the trusted jtag_probe project first' >&2
        exit 1
    }
    exec timeout --kill-after=2s 30s quartus_pgm -c "$2" -m JTAG -o "p;jtag_probe.sof@$3"
fi
exec timeout --kill-after=2s 30s quartus_stp -t "$project/scripts/jtag-observe.tcl" "$@"
