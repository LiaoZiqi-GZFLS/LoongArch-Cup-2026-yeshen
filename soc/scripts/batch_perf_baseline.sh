#!/bin/bash
# Batch run all 20 perf tests using Verilator on MSYS2/Windows
# Each test: compile Verilator with its .mem file, run with 500M cycle timeout
# Output: soc/sw/tests/perf_baseline.csv

set -euo pipefail

SOC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SOC_DIR"

export TMP=$(cygpath -m "$TMP")
export TEMP=$(cygpath -m "$TEMP")
export TMPDIR=$(cygpath -m "${TMPDIR:-$TMP}")

PERL=/c/Strawberry/perl/bin/perl.exe
VERILATOR=/c/App/verilator-install/bin/verilator
GPP=/c/msys64/mingw64/bin/g++.exe
TIMEOUT_CYCLES=500000000
REPORT="sw/tests/perf_baseline.csv"

PERF_TESTS="bitcount bubble_sort coremark crc32 dhrystone quick_sort select_sort sha stream_copy stringsearch fireye_A0 fireye_B2 fireye_C0 fireye_D1 fireye_I2 inner_product lookup_table loop_induction my_memcmp minmax_sequence"

echo "test,cycles,status,elapsed_s" | tee "$REPORT"

for t in $PERF_TESTS; do
    memfile="sw/tests/perf_${t}.mem"
    if [ ! -f "$memfile" ]; then
        echo "${t},0,NO_MEMFILE,0" | tee -a "$REPORT"
        continue
    fi

    OBJ="obj_dir_${t}"
    rm -rf "$OBJ"

    echo "=== Compiling ${t} ==="
    "$PERL" "$VERILATOR" --main --timing +incdir+rtl/core \
        --top-module tb_soc_generic -f build/generic_files.f \
        -Wno-fatal -Mdir "$OBJ" -GINIT_FILE="\"$memfile\"" 2>&1 | tail -1

    mingw32-make -C "$OBJ" -f "Vtb_soc_generic.mk" \
        CFG_CXXFLAGS_PCH_I=-include CFG_CXXFLAGS_COROUTINES=-fcoroutines 2>&1 | tail -1

    "$GPP" -std=c++20 -fcoroutines -DVL_TIME_CONTEXT \
        -I"$OBJ" -IC:/App/verilator-install/include \
        "$OBJ/Vtb_soc_generic__ALL.a" "$OBJ/libverilated.a" \
        -o "$OBJ/Vtb_soc_generic.exe" -lpthread 2>&1

    echo "=== Running ${t} ==="
    START_TIME=$(date +%s)
    result=$("$OBJ/Vtb_soc_generic.exe" "+TIMEOUT_CYCLES=${TIMEOUT_CYCLES}" 2>&1)
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    if echo "$result" | grep -q "TIMEOUT"; then
        echo "${t},0,TIMEOUT,${ELAPSED}" | tee -a "$REPORT"
    elif echo "$result" | grep -q "PASS"; then
        nd=$(echo "$result" | grep -oP 'num_data=\K[0-9a-fA-Fx]+' | head -1)
        echo "${t},${nd},PASS,${ELAPSED}" | tee -a "$REPORT"
    else
        echo "${t},0,UNKNOWN,${ELAPSED}" | tee -a "$REPORT"
    fi
done

echo "=== BATCH COMPLETE ==="
echo "Report: ${REPORT}"
cat "$REPORT"
