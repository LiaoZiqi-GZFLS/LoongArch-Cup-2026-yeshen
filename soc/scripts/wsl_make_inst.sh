#!/bin/bash
set -euo pipefail
export PATH="/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin:$PATH"

DIR=/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/func/func_src/inst
cd "$DIR"

# Clean
rm -f ../obj/*.o ../obj/*.s ../obj/libinst.a

# Test single file compile
echo "=== Testing single .S -> .s ==="
loongarch32r-linux-gnusf-gcc \
    -I../include -nostdinc -nostdlib -D_KERNEL -fno-builtin -D__loongarch32 \
    -DMEMSTART=0x10000000 -DMEMSIZE=0x04000 -DCPU_COUNT_PER_US=1000 -DGUEST -DEXP=16 \
    -S n1_lu12i_w.S -o ../obj/n1_lu12i_w.s 2>&1
echo "Exit code: $?"
wc -c ../obj/n1_lu12i_w.s
head -3 ../obj/n1_lu12i_w.s

echo "=== Testing single .s -> .o ==="
loongarch32r-linux-gnusf-as -mabi=ilp32 -o ../obj/n1_lu12i_w.o ../obj/n1_lu12i_w.s 2>&1
echo "Exit code: $?"
loongarch32r-linux-gnusf-size ../obj/n1_lu12i_w.o

echo "=== Full make ==="
make clean 2>&1 || true
make EXP=16 libinst.a 2>&1
echo "Make exit: $?"

echo "=== Check .o after make ==="
loongarch32r-linux-gnusf-size ../obj/n1_lu12i_w.o
