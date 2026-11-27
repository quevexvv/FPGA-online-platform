#!/usr/bin/env bash

# Match prepare-job's input error codes for forbidden HDL and I/O failures.
check_hdl_source() {
    if LC_ALL=C grep -Eq '`[[:space:]]*include|[$]readmem[bh]' -- "$1"; then
        return 3
    elif [[ $? != 1 ]]; then
        return 1
    fi
}
