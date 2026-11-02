#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

for entry in bin/fpga-dispatch bin/fpga-run; do
    help=$("$entry" --help)
    [[ $help == *Usage:* && $help == *'ещё не реализован'* ]]

    for argument in '' --unknown submit status cleanup; do
        args=()
        [[ -z $argument ]] || args+=("$argument")
        code=0
        output=$("$entry" "${args[@]}" 2>&1) || code=$?
        [[ $code -eq 2 && $output == *'ещё не реализован'* ]]
    done
    code=0
    "$entry" --help unexpected >/dev/null 2>&1 || code=$?
    [[ $code -eq 2 ]]
done

for directory in scripts src/uart hdl quartus testsets examples tests config deploy docs; do
    [[ -d $directory ]]
done
printf '%s\n' 'PASS: справка, отказ неготовых команд и структура каркаса.'
