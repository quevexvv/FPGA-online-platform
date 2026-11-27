#!/usr/bin/env bash
set -euo pipefail

project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=scripts/hdl-source.sh
source "$project/scripts/hdl-source.sh"
input=$1
work=$2
run_id=$3
mode=${4:-hardware}

invalid() {
    printf 'invalid_input: %s\n' "$1" >&2
    exit 2
}

invalid_hdl() {
    printf 'invalid_input: %s\n' "$1" >&2
    exit 3
}

# The dispatcher owns this directory after the backend closes the upload.
[[ -d $input && ! -L $input ]] || invalid 'expected an upload directory'
unsafe=$(find -P "$input" ! -type d ! \( -type f -links 1 \) -printf x -quit)
[[ -z $unsafe ]] || invalid 'upload contains a link or a special file'
[[ -f $input/manifest.json ]] || invalid 'manifest.json is missing'
manifest_bytes=$(stat -c %s -- "$input/manifest.json")
(( manifest_bytes <= 4096 )) || invalid 'manifest exceeds 4096 bytes'
manifest=$(jq -ces 'select(length == 1) | .[0]' "$input/manifest.json") ||
    invalid 'expected one JSON manifest'
jq -e --arg kind manifest --arg run_id "$run_id" -f "$project/scripts/contract.jq" \
    <<< "$manifest" >/dev/null || invalid 'manifest does not match the contract'

test_set=$(jq -r '.test_set' <<< "$manifest")
kind=$(jq -r '.kind' <<< "$manifest")
vectors=$project/testsets/$test_set.json
if [[ $mode == mock ]]; then
    case "$test_set:$kind" in
        counter-v1:sequential|combinational-v1:combinational) ;;
        mock-uart-error-v1:sequential) vectors=$project/testsets/counter-v1.json ;;
        *) invalid 'unknown or incompatible mock model' ;;
    esac
fi
[[ -f $vectors && ! -L $vectors ]] || invalid 'unknown test set'
if ! jq -es -f "$project/scripts/test-set.jq" "$vectors" >/dev/null; then
    echo 'prepare-job: installed test set is malformed' >&2
    exit 1
fi
if [[ $kind == combinational ]] && ! jq -e 'all(.[]; .steps == 0)' "$vectors" >/dev/null; then
    invalid 'combinational jobs require zero-step vectors'
fi

source_list=$(jq -r '.sources[]' <<< "$manifest")
mapfile -t sources <<< "$source_list"
(( ${#sources[@]} <= 16 )) || invalid 'more than 16 source files'
source_files=()
total_bytes=0
for path in "${sources[@]}"; do
    [[ -f $input/$path ]] || invalid "missing source: $path"
    source_bytes=$(stat -c %s -- "$input/$path")
    total_bytes=$((total_bytes + source_bytes))
    (( total_bytes <= 65536 )) || invalid 'sources exceed 65536 bytes in total'
    check_hdl_source "$input/$path" || {
        [[ $? == 3 ]] && invalid_hdl "external file references are unsupported: $path"
        exit 1
    }
    source_files+=("$input/$path")
done
file_count=$(find -P "$input" -type f -printf x | wc -c)
[[ $file_count -eq $((${#sources[@]} + 1)) ]] || invalid 'upload contains undeclared files'

if [[ $mode == mock ]]; then
    cp -- "$vectors" "$work/test-set.json"
    exit 0
fi

wrapper=(fpga_wrapper dut_control clock_burst uart_service uart_commands uart_rx uart_tx)
wrapper_files=()
for module in "${wrapper[@]}"; do
    wrapper_files+=("$project/hdl/$module.v")
done
compiler=${IVERILOG:-iverilog}
command -v "$compiler" >/dev/null || { echo 'prepare-job: Icarus Verilog is missing' >&2; exit 1; }
# Read the elaborated port declarations. Keep the generated program as data.
netlist=$(mktemp -- "$work/.ports.XXXXXXXX")
trap 'rm -f -- "$netlist"' EXIT
compile_status=0
(
    ulimit -f 16384
    exec env -i PATH="$PATH" LC_ALL=C timeout -k 2s 10s "$compiler" \
        -g2001 -DSYNTHESIS -t vvp -o "$netlist" -s fpga_wrapper \
        "${wrapper_files[@]}" "${source_files[@]}" >/dev/null 2>&1
) || compile_status=$?
case "$compile_status" in
    0) ;;
    125|126|127)
        echo 'prepare-job: cannot invoke Icarus Verilog' >&2
        exit 1
        ;;
    *)
        invalid_hdl 'HDL does not elaborate against the student_top interface'
        ;;
esac
if ! awk '
    BEGIN {
        expected["\"clk\";"] = "/INPUT 1"
        expected["\"reset\";"] = "/INPUT 1"
        expected["\"din\";"] = "/INPUT 10"
        expected["\"dout\";"] = "/OUTPUT 18"
    }
    $2 == ".scope" {
        if ($3 == "module," && $4 == "\"fpga_wrapper\"" && $5 == "\"fpga_wrapper\"" &&
            wrapper == "") wrapper = $1
        student = wrapper != "" && $3 == "module," && $4 == "\"student\"" &&
            $5 == "\"student_top\"" && $NF == wrapper ";"
    }
    student && $1 == ".port_info" {
        if (!($5 in expected) || expected[$5] != $3 " " $4 || seen[$5]++) invalid = 1
        count++
    }
    END { exit(invalid || count != 4) }
' "$netlist"; then
    invalid_hdl 'student_top has incorrect ports'
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
