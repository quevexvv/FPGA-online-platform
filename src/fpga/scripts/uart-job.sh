#!/usr/bin/env bash
set -euo pipefail

uart=$1
port=$2
timeout=$3

case "$4" in
    probe)
        # The stage watchdog bounds the wait for the device to appear.
        while [[ ! -c $port ]]; do
            if [[ -e $port ]]; then echo 'UART path is not a character device' >&2; exit 2; fi
            sleep .1
        done
        # A fresh serial_open flushes stale bytes. Require both reply types
        # from the current protocol without advancing the student clock.
        printf '%s\n' read 'step 0000' read | "$uart" "$port" "$timeout"
        ;;
    *) exit 2 ;;
esac
