#!/bin/bash
set -euo pipefail

CHIPLAB_HOME=/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab
TOOLCHAIN_DIR=loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0

export PATH="${CHIPLAB_HOME}/toolchains/${TOOLCHAIN_DIR}/bin:${PATH}"
export CHIPLAB_HOME

echo "=== Toolchain check ==="
loongarch32r-linux-gnusf-gcc --version 2>&1 | head -1
echo "CHIPLAB_HOME=${CHIPLAB_HOME}"

SOC_DIR=/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/soc
cd "${SOC_DIR}"

echo "=== Building nscscc_func ==="
python3 scripts/build_tests.py -j 4 -t nscscc_func

echo "=== Running nscscc_func ==="
python3 scripts/run_tests.py -t nscscc_func -s verilator

echo "=== Done ==="
