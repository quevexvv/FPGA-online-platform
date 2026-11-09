#!/usr/bin/env bash
set -euo pipefail

project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
input=$1
work=$2
run_id=$3

invalid() {
    printf 'invalid_input: %s\n' "$1" >&2
    exit 2
}

# The dispatcher owns this directory after the backend closes the upload.
[[ -d $input && ! -L $input ]] || invalid 'expected an upload directory'
unsafe=$(find -P "$input" ! -type d ! \( -type f -links 1 \) -printf x -quit)
[[ -z $unsafe ]] || invalid 'upload contains a link or a special file'
[[ -f $input/manifest.json ]] || invalid 'manifest.json is missing'
manifest=$(jq -ces 'select(length == 1) | .[0]' "$input/manifest.json") ||
    invalid 'expected one JSON manifest'
jq -e --arg kind manifest --arg run_id "$run_id" -f "$project/scripts/contract.jq" \
    <<< "$manifest" >/dev/null || invalid 'manifest does not match the contract'

test_set=$(jq -r '.test_set' <<< "$manifest")
kind=$(jq -r '.kind' <<< "$manifest")
vectors=$project/testsets/$test_set.json
[[ -f $vectors && ! -L $vectors ]] || invalid 'unknown test set'
if ! jq -es '
    length == 1 and (.[0] | type == "array" and length > 0 and
    all(to_entries[]; .key == .value.vector_index and (.value |
        (.reset_before | type == "boolean") and
        (.din | type == "string" and test("\\A0x[0-3][0-9a-f]{2}\\z")) and
        (.steps | type == "number" and . == floor and . >= 0 and . <= 65535) and
        all(.expected_dout, .mask; type == "string" and test("\\A0x[0-3][0-9a-f]{4}\\z")))))
' "$vectors" >/dev/null; then
    echo 'prepare-job: installed test set is malformed' >&2
    exit 1
fi
if [[ $kind == combinational ]] && ! jq -e 'all(.[]; .steps == 0)' "$vectors" >/dev/null; then
    invalid 'combinational jobs require zero-step vectors'
fi

source_list=$(jq -r '.sources[]' <<< "$manifest")
mapfile -t sources <<< "$source_list"
source_files=()
for path in "${sources[@]}"; do
    [[ -f $input/$path ]] || invalid "missing source: $path"
    if LC_ALL=C grep -Eq '`[[:space:]]*include|[$]readmem[bh]' "$input/$path"; then
        invalid "external file references are unsupported: $path"
    elif [[ $? -ne 1 ]]; then
        exit 1
    fi
    source_files+=("$input/$path")
done
file_count=$(find -P "$input" -type f -printf x | wc -c)
[[ $file_count -eq $((${#sources[@]} + 1)) ]] || invalid 'upload contains undeclared files'

wrapper=(fpga_wrapper dut_control clock_burst uart_service uart_commands uart_rx uart_tx)
wrapper_files=()
for module in "${wrapper[@]}"; do
    wrapper_files+=("$project/hdl/$module.v")
done
compiler=${IVERILOG:-iverilog}
command -v "$compiler" >/dev/null || { echo 'prepare-job: Icarus Verilog is missing' >&2; exit 1; }
# Elaborate only. Icarus can exit successfully after padding or pruning a port.
if ! diagnostics=$(env -i PATH="$PATH" LC_ALL=C timeout -k 2s 10s "$compiler" \
    -g2001 -DSYNTHESIS -t null -s fpga_wrapper "${wrapper_files[@]}" "${source_files[@]}" 2>&1) ||
    [[ $diagnostics == *'expects '* || $diagnostics == *'coerced to inout'* ]]; then
    invalid 'HDL does not elaborate against the student_top interface'
fi

mkdir -- "$work/hdl" "$work/quartus"
cp -- "${wrapper_files[@]}" "$work/hdl/"
cp -- "$project/quartus/wrapper_base.qsf" "$project/quartus/wrapper.sdc" "$work/quartus/"
cp -- "$vectors" "$work/test-set.json"
printf '%s\n' 'QUARTUS_VERSION = "23.1"' 'PROJECT_REVISION = "job"' > "$work/quartus/job.qpf"
{
    printf '%s\n' 'source wrapper_base.qsf' 'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files'
    for path in "${sources[@]}"; do
        printf 'set_global_assignment -name VERILOG_FILE ../../input/%s\n' "$path"
    done
} > "$work/quartus/job.qsf"
