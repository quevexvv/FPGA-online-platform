#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

display() {
    local source=$1
    shift
    jq -e --arg source "$source" -f scripts/display-observations.jq "$@"
}

for ((bit=0; bit<18; bit++)); do
    printf -v dout '0x%05x' "$((1 << bit))"
    jq --arg dout "$dout" '.observations[0].dout = $dout | .observations[0].mask = "0x00000"' \
        examples/result.json | display led | jq -e --argjson bit "$bit" '
        (.observations[0] | .red + .green) == [range(18) | . == $bit]' >/dev/null
done
display led examples/lab2/result_passed.json | jq -e '
    .mode == "hardware" and .hardware_verified and
    ([.observations[] | .red | index(true)] == [0,3,2])' >/dev/null
display led examples/result-mock.json | jq -e '
    .mode == "mock" and .hardware_verified == false and .observations[0].red[0:3] == [true,true,false]' >/dev/null
jq '.observations = []' examples/result.json | display led | jq -e '.observations == []' >/dev/null

# Each of the 28 bits represents one segment in one digit.
for ((digit=0; digit<4; digit++)); do
    for ((segment=0; segment<7; segment++)); do
        mask=$((1 << segment))
        frame=$((mask << (7 * digit)))
        jq -cn --argjson frame "$frame" '{schema_version:1,current:0,before:[$frame],after:[]}' |
            display lab3 | jq -e --argjson digit "$digit" --argjson mask "$mask" '
                .current == [0,0,0,0] and .after == [] and
                .before == [[range(4) | if . == $digit then $mask else 0 end]]' >/dev/null
    done
done
printf '%s\n' '{"schema_version":1,"current":0,"before":[14084070,192148333],"after":[192148333]}' |
    display lab3 | jq -e '.before == [[102,79,91,6],[109,102,79,91]] and .after == [.before[1]]' >/dev/null
if jq '.observations[0].dout = "0x40000"' examples/result.json | display led 2>/dev/null; then
    echo 'FAIL: out-of-range LED value accepted' >&2
    exit 1
fi
if printf '%s\n' '{"schema_version":1,"current":268435456,"before":[],"after":[]}' | display lab3 2>/dev/null; then
    echo 'FAIL: out-of-range Lab 3 frame accepted' >&2
    exit 1
fi
echo 'PASS: logical LED and HEX display observations'
