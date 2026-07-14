#!/bin/bash
export PATH="/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin:$PATH"
DIR=/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/func/func_src/inst
OBJ=/mnt/e/code/Vivado/LoongArch-Cup-2026-yeshen/chiplab/software/examples/func/func_src/obj
cd "$DIR"

# Clean
rm -f ${OBJ}/n1_lu12i_w.s ${OBJ}/n1_lu12i_w.o 2>/dev/null

# Test: use redirect (matching Makefile)
echo "=== Test: gcc -S > file ==="
loongarch32r-linux-gnusf-gcc \
    -I../include -nostdinc -nostdlib -D_KERNEL -fno-builtin -D__loongarch32 \
    -DMEMSTART=0x10000000 -DMEMSIZE=0x04000 -DCPU_COUNT_PER_US=1000 -DGUEST -DEXP=16 \
    -S n1_lu12i_w.S > ${OBJ}/n1_lu12i_w.s 2>/tmp/gcc_err.txt
echo "Exit: $?"
wc -c ${OBJ}/n1_lu12i_w.s
echo "First 3 lines:"
head -3 ${OBJ}/n1_lu12i_w.s
echo "Stderr:"
cat /tmp/gcc_err.txt

# Now assemble it
echo "=== Test: as ==="
loongarch32r-linux-gnusf-as -mabi=ilp32 -o ${OBJ}/n1_lu12i_w.o ${OBJ}/n1_lu12i_w.s 2>&1
echo "Exit: $?"
loongarch32r-linux-gnusf-size ${OBJ}/n1_lu12i_w.o

# Now run full make clean + make
echo "=== Full make test ==="
make clean 2>&1
make EXP=16 libinst.a 2>&1
echo "Make exit: $?"
loongarch32r-linux-gnusf-size ${OBJ}/n1_lu12i_w.o
