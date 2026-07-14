#!/bin/bash
set -euo pipefail

TOOLCHAIN_BIN="/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin"
export PATH="${TOOLCHAIN_BIN}:${PATH}"
export CHIPLAB_HOME="/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab"

SOC_DIR=/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/soc
cd "${SOC_DIR}"

PERF_TESTS="bitcount bubble_sort coremark crc32 dhrystone quick_sort select_sort sha stream_copy stringsearch fireye_A0 fireye_B2 fireye_C0 fireye_D1 fireye_I2 inner_product lookup_table loop_induction my_memcmp minmax_sequence"

echo "=== Building all performance tests ==="
python3 scripts/build_tests.py -j 4 -t ${PERF_TESTS} 2>&1 | grep -E "ok|FAIL|build|Error" | tail -30

echo "=== Moving .mem files ==="
mkdir -p sw/tests
for f in soc/sw/tests/perf_*.mem soc/sw/tests/func.mem; do
    if [ -f "$f" ]; then
        base=$(basename "$f")
        cp "$f" "sw/tests/${base}"
        echo "Copied: ${base}"
    fi
done 2>/dev/null || true

echo "=== .mem count ==="
ls sw/tests/perf_*.mem 2>/dev/null | wc -l
echo "perf mem files ready"

echo "=== BUILD DONE ==="
