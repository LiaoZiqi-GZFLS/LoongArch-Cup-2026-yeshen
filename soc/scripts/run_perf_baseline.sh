#!/bin/bash
set -euo pipefail

SOC_DIR="/e/code/Vivado/LoongArch-Cup-2026-yeshen/soc"
cd "$SOC_DIR"

export TMP=$(cygpath -m "$TMP")
export TEMP=$(cygpath -m "$TEMP")
export TMPDIR=$(cygpath -m "${TMPDIR:-$TMP}")

OBJ="obj_dir_perf"
rm -rf "$OBJ"

echo "=== Compiling Verilator (once) ==="
/c/Strawberry/perl/bin/perl.exe /c/App/verilator-install/bin/verilator \
    --main --timing +incdir+rtl/core --top-module tb_soc_generic \
    -f build/generic_files.f -Wno-fatal -Mdir "$OBJ"

mingw32-make -C "$OBJ" -f Vtb_soc_generic.mk \
    CFG_CXXFLAGS_PCH_I=-include CFG_CXXFLAGS_COROUTINES=-fcoroutines

/c/msys64/mingw64/bin/g++.exe -std=c++20 -fcoroutines -DVL_TIME_CONTEXT \
    -I"$OBJ" -IC:/App/verilator-install/include \
    "$OBJ/Vtb_soc_generic__ALL.a" "$OBJ/libverilated.a" \
    -o "$OBJ/Vtb_soc_generic.exe" -lpthread

echo "=== Compilation done, running tests ==="

PERF_TESTS="bitcount bubble_sort coremark crc32 dhrystone quick_sort select_sort sha stream_copy stringsearch fireye_A0 fireye_B2 fireye_C0 fireye_D1 fireye_I2 inner_product lookup_table loop_induction my_memcmp minmax_sequence"

echo "test_name,num_data,status"
for t in $PERF_TESTS; do
    memfile="sw/tests/perf_${t}.mem"
    if [ ! -f "$memfile" ]; then
        echo "${t},0,NO_MEMFILE"
        continue
    fi

    result=$("$OBJ/Vtb_soc_generic.exe" +INIT_FILE="$memfile" 2>&1)

    if echo "$result" | grep -q "TIMEOUT"; then
        echo "${t},0,TIMEOUT"
    elif echo "$result" | grep -q "PASS"; then
        nd=$(echo "$result" | grep -oP 'num_data=\K[0-9a-fA-Fx]+' | head -1)
        echo "${t},${nd},PASS"
    else
        echo "${t},0,UNKNOWN"
    fi
done

echo "=== BASELINE DONE ==="
