#!/bin/bash
export PATH="/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin:$PATH"
DIR=/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/func/func_src

echo "=== start.o ==="
loongarch32r-linux-gnusf-size "${DIR}/obj/start.o" 2>&1
loongarch32r-linux-gnusf-objdump -h "${DIR}/obj/start.o" 2>&1 | grep -E "\.text|Idx|Size"

echo "=== n1_lu12i_w.o ==="
loongarch32r-linux-gnusf-size "${DIR}/obj/n1_lu12i_w.o" 2>&1
loongarch32r-linux-gnusf-objdump -h "${DIR}/obj/n1_lu12i_w.o" 2>&1 | grep -E "\.text|Idx|Size"

echo "=== n10_nor.o ==="
loongarch32r-linux-gnusf-size "${DIR}/obj/n10_nor.o" 2>&1
loongarch32r-linux-gnusf-objdump -h "${DIR}/obj/n10_nor.o" 2>&1 | grep -E "\.text|Idx|Size"

echo "=== libinst.a check ==="
loongarch32r-linux-gnusf-ar t "${DIR}/obj/libinst.a" 2>&1 | head -5

echo "=== start.s ==="
wc -c "${DIR}/obj/start.s" 2>&1
head -5 "${DIR}/obj/start.s" 2>&1

echo "=== init.s ==="
wc -c "/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/nscscc_func/obj/init.s" 2>&1
head -5 "/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/nscscc_func/obj/init.s" 2>&1
