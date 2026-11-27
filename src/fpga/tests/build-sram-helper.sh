#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
mkdir -p -- "$root"/{build,hdl,scripts,quartus,src/runner}
cp -- Makefile "$root/"
cp -- src/runner/stage.c "$root/src/runner/"
cp -- scripts/{build-sram-helper,hdl-source}.sh "$root/scripts/"
cp -- hdl/{sram_check,c5g_sram_word,jtag_snapshot}.v "$root/hdl/"
cp -- quartus/{sram_helper_check.qpf,sram_helper_check.qsf,sram_check.qsf,c5g-sram.qsf,c5g-sram.sdc} "$root/quartus/"
cp -- build/fpga-stage "$root/build/"
student="$root/student\"sample\$ref.v"
cp -- examples/lab4/student_sram_helper.v "$student"
image=$root/build/sram-helper-check/sram_helper_check.sof

cat > "$root/quartus_sh" <<'FAKE'
#!/bin/bash
set -euo pipefail
[[ -z ${SRAM_HELPER_ENV_MARKER+x} && $HOME == "${PWD%/quartus}/home" &&
   $TMPDIR == "${PWD%/quartus}/tmp" && $* == '--flow compile sram_helper_check' ]]
[[ -s ../build/sram-helper-source/student_sram_helper.v && ! -L ../build/sram-helper-source/student_sram_helper.v ]]
mkdir -p ../build/sram-helper-check
printf 'Fresh image\n' > ../build/sram-helper-check/sram_helper_check.sof
FAKE
chmod +x -- "$root/quartus_sh"
export SRAM_HELPER_ENV_MARKER=must_stay_in_parent
build() { make -sC "$root" build-sram-helper-check "LAB4_HELPER=$1" "QUARTUS_SH=$2"; }

build "$student" "$root/quartus_sh"
[[ $(<"$image") == 'Fresh image' ]]
printf '`include "outside.v"\n' > "$root/invalid.v"
if build "$root/invalid.v" "$root/quartus_sh" 2>/dev/null || [[ -e $image ]]; then
    echo 'Forbidden HDL was built or a stale image survived' >&2
    exit 1
fi
build "$student" "$root/quartus_sh"
if build "$student" false 2>/dev/null || [[ -e $image ]]; then
    echo 'A stale image survived compiler failure' >&2
    exit 1
fi
echo 'PASS: isolated SRAM helper build, external reference rejection and stale image invalidation'
