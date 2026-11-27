#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
output=$project/build/sram-helper-check
[[ ! -L $output ]] || exit 1
mkdir -p -- "$output"
exec {build_lock}< "$output"
flock -x "$build_lock"
rm -f -- "$output/sram_helper_check.sof"

if [[ $# != 2 || ! -f $1 || -L $1 ]] || (( $(stat -c %s -- "$1") > 65536 )); then
    echo 'Provide one regular HDL source file of up to 64 KiB' >&2
    exit 2
fi
quartus=$(command -v -- "$2")
quartus=$(realpath -e -- "$quartus")
work=$(mktemp -d -- "$project/build/sram-helper.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p -- "$work"/{home,tmp,hdl,quartus,build/sram-helper-source}
input=$work/build/sram-helper-source/student_sram_helper.v
cp --no-dereference -- "$1" "$input"
[[ -f $input && ! -L $input ]] && (( $(stat -c %s -- "$input") <= 65536 )) || exit 2
# shellcheck source=scripts/hdl-source.sh
source "$project/scripts/hdl-source.sh"
check_hdl_source "$input" || {
    source_status=$?
    if ((source_status == 3)); then echo 'External HDL file references are unsupported' >&2; fi
    exit "$source_status"
}
cp -- "$project"/hdl/{sram_check,c5g_sram_word,jtag_snapshot}.v "$work/hdl/"
cp -- "$project"/quartus/{sram_helper_check.qpf,sram_helper_check.qsf,sram_check.qsf,c5g-sram.qsf,c5g-sram.sdc} "$work/quartus/"

(
    cd -- "$work/quartus"
    env -i PATH=/usr/bin:/bin LC_ALL=C HOME="$work/home" TMPDIR="$work/tmp" \
        "$project/build/fpga-stage" 120000 262144 "$work/quartus.log" -- "$quartus" --flow compile sram_helper_check
) || {
    build_status=$?
    if [[ -f $work/quartus.log ]]; then cat -- "$work/quartus.log" >&2; fi
    exit "$build_status"
}
artifact=$work/build/sram-helper-check/sram_helper_check.sof
[[ -f $artifact && -s $artifact && ! -L $artifact ]] || {
    echo 'Quartus did not create a fresh SRAM helper image' >&2
    exit 1
}
mv -T -- "$artifact" "$output/sram_helper_check.sof"
echo 'Built SRAM helper check image'
