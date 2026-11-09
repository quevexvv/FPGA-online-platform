#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
id=$(jq -r '.run_id' examples/manifest.json)

upload() {
    input=$root/$1/input
    work=$root/$1/work
    mkdir -p -- "$input/src" "$work"
    cp -- examples/manifest.json "$input/manifest.json"
    cp -- examples/counter/student_top.v "$input/src/student_top.v"
}

reject() {
    local code=0 message
    message=$(bash scripts/prepare-job.sh "$input" "$work" "$id" 2>&1) || code=$?
    if [[ $code != 2 || $message != *"invalid_input: $1"* || -e $work/quartus ]]; then
        printf 'FAIL: expected invalid_input for %s, got %s: %s\n' "$input" "$code" "$message" >&2
        exit 1
    fi
}

upload valid
bash scripts/prepare-job.sh "$input" "$work" "$id"
cmp quartus/wrapper_base.qsf "$work/quartus/wrapper_base.qsf"
cmp quartus/wrapper.sdc "$work/quartus/wrapper.sdc"
cmp testsets/counter-v1.json "$work/test-set.json"
grep -Fxq 'set_global_assignment -name VERILOG_FILE ../../input/src/student_top.v' "$work/quartus/job.qsf"

upload combinational
jq '.kind="combinational" | .test_set="combinational-v1"' examples/manifest.json > "$input/manifest.json"
cp -- examples/combinational/student_top.v "$input/src/student_top.v"
bash scripts/prepare-job.sh "$input" "$work" "$id"
cmp testsets/combinational-v1.json "$work/test-set.json"

case_number=0
for filter in '.sources=["../escape.v"]' '.sources=["/absolute.v"]' '.sources=["src/./student_top.v"]' \
    '.sources=["src/student_top.v\n"]' '.sources += .sources' '.sources=["src/project.qsf"]' \
    '.schema_version="1"' '.top="fpga_wrapper"' '.uart_device="/dev/null"' \
    '.run_id="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"' '.test_set="counter-v1\n"'; do
    upload "invalid-$case_number"
    jq "$filter" examples/manifest.json > "$input/manifest.json"
    reject 'manifest does not match the contract'
    case_number=$((case_number + 1))
done

upload multiple
cat examples/manifest.json >> "$input/manifest.json"
reject 'expected one JSON manifest'
upload unknown
jq '.test_set="unknown"' examples/manifest.json > "$input/manifest.json"
reject 'unknown test set'
upload wrong-kind
jq '.kind="combinational"' examples/manifest.json > "$input/manifest.json"
reject 'combinational jobs require zero-step vectors'
upload missing
mv -- "$input/src/student_top.v" "$root/missing.v"
reject 'missing source'
upload symlink
ln -s -- "$root/missing.v" "$input/src/outside.v"
reject 'upload contains a link'
upload directory-link
mv -- "$input/src" "$root/outside"
ln -s -- "$root/outside" "$input/src"
reject 'upload contains a link'
upload hardlink
ln -- "$root/missing.v" "$input/src/outside.v"
reject 'upload contains a link'
upload extra
touch -- "$input/wrapper_base.qsf"
reject 'upload contains undeclared files'
upload include
printf '\140include "/outside.v"\n' >> "$input/src/student_top.v"
reject 'external file references'
upload duplicate-module
cat hdl/fpga_wrapper.v >> "$input/src/student_top.v"
reject 'HDL does not elaborate'
upload port-width
sed 's/\[9:0\]/[8:0]/' examples/counter/student_top.v > "$input/src/student_top.v"
reject 'HDL does not elaborate'
echo 'PASS: upload validation and trusted Quartus workspace'
