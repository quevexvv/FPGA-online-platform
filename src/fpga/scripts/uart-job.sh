#!/usr/bin/env bash
set -euo pipefail

uart=$1
port=$2
timeout=$3

case "$4" in
    probe)
        # udev can set the owner and mode after the device node appears.
        # The stage watchdog bounds both waits.
        while [[ ! -c $port || ! -r $port || ! -w $port ]]; do
            if [[ -e $port && ! -c $port ]]; then echo 'UART path is not a character device' >&2; exit 2; fi
            sleep .1
        done
        # A fresh serial_open flushes stale bytes. Require both reply types
        # from the current protocol without advancing the student clock.
        printf '%s\n' read 'step 0000' read | "$uart" "$port" "$timeout"
        ;;
    vectors)
        "$uart" "$port" "$timeout" < "$5" | tee -- "$6"
        ;;
    *) exit 2 ;;
esac
