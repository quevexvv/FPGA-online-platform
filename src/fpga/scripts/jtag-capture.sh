#!/usr/bin/env bash
# The caller holds the stand lock for the complete hardware operation.
capture_jtag_json() {
    local snapshot
    snapshot=$(timeout --kill-after=2s 30s quartus_stp -t "$1" "${@:2}" |
        awk '/^SNAPSHOT / {print substr($0, 10); next} {print > "/dev/stderr"}') || return
    if [[ -z $snapshot || $snapshot == *$'\n'* ]]; then
        echo 'Expected exactly one JTAG snapshot' >&2
        return 1
    fi
    printf '%s\n' "$snapshot"
}
