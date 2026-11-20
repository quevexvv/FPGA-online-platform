#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
check() { jq -e --arg kind "$1" -f scripts/contract.jq "$2" >/dev/null; }
root=examples/lab2
check manifest "$root/manifest_valid.json"
if check manifest "$root/manifest_invalid.json"; then
    echo 'FAIL: manifest without run_id accepted' >&2
    exit 1
fi
check result "$root/result_passed.json"
check result "$root/mock_lab2_running_led.json"
jq -e 'type == "array" and length == 3 and
  (map(.vector_index) == [0,1,2]) and all(.[];
    (.reset_before | type == "boolean") and
    (.steps | type == "number" and floor == . and . >= 0 and . <= 65535) and
    (.din | test("^0x[0-3][0-9a-f]{2}$")) and
    all(.expected_dout,.mask; test("^0x[0-3][0-9a-f]{4}$")))' \
    "$root/lab2_running_led.json" >/dev/null
for file in result_passed mock_lab2_running_led; do
    jq -e --slurpfile vectors "$root/lab2_running_led.json" '
      .summary == {planned:3,executed:3,passed:3,failed:0} and
      (.observations | map({vector_index,din,steps,expected_dout,mask})) ==
      ($vectors[0] | map({vector_index,din,steps,expected_dout,mask}))' \
        "$root/$file.json" >/dev/null
done
echo 'PASS: analyst lab2 contract examples'
