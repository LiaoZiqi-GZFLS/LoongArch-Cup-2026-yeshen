#!/bin/bash
set -euo pipefail

TOOLCHAIN_BIN="/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin"
export PATH="${TOOLCHAIN_BIN}:${PATH}"
export CHIPLAB_HOME="/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab"

# Deep clean: remove ALL stale .s and .o and .mem files
echo "=== Deep clean ==="
rm -f /mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/func/func_src/obj/*.o
rm -f /mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/func/func_src/obj/*.s
rm -f /mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/func/func_src/obj/*.a
rm -f /mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/nscscc_func/obj/*.o
rm -f /mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/nscscc_func/obj/*.s
rm -f /mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/nscscc_func/obj/*.elf
rm -f /mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/nscscc_func/obj/*.bin
rm -f /mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/nscscc_func/obj/*.coe
rm -f /mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/soc/sw/tests/*.mem

SOC_DIR=/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/soc
cd "${SOC_DIR}"

echo "=== Python version ==="
python3 --version

echo "=== Building nscscc_func ==="
python3 scripts/build_tests.py -j 1 -t nscscc_func 2>&1

echo "=== Checking output ==="
ls -la sw/tests/nscscc_func.mem 2>&1 || echo "No nscscc_func.mem found"
ls -la sw/tests/func.mem 2>&1 || echo "No func.mem found"

echo "=== BUILD DONE ==="
