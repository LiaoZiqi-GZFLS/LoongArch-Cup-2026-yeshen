#!/usr/bin/env python3
"""Hand-assemble the LoongArch32R demo program -> demo.mem ($readmemh, one word/line)."""

M32 = 0xffffffff

def _u(v, bits):
    return v & ((1 << bits) - 1)

# --- instruction encoders ---
def add_w(rd, rj, rk):   return (0x00100000 | (_u(rk,5)<<10) | (_u(rj,5)<<5) | _u(rd,5)) & M32
def sub_w(rd, rj, rk):   return (0x00110000 | (_u(rk,5)<<10) | (_u(rj,5)<<5) | _u(rd,5)) & M32
def addi_w(rd, rj, si):  return (0x02800000 | (_u(si,12)<<10) | (_u(rj,5)<<5) | _u(rd,5)) & M32
def ld_w(rd, rj, si):    return (0x28800000 | (_u(si,12)<<10) | (_u(rj,5)<<5) | _u(rd,5)) & M32
def st_w(rd, rj, si):    return (0x29800000 | (_u(si,12)<<10) | (_u(rj,5)<<5) | _u(rd,5)) & M32
def lu12i_w(rd, si20):   return (0x14000000 | (_u(si20,20)<<5) | _u(rd,5)) & M32
# bne rj,rd,offs (branch if rj!=rd); offs in bytes, encoded >>2 as 16-bit
def bne(rj, rd, off):
    o = _u(off >> 2, 16)
    return (0x5c000000 | (o<<10) | (_u(rj,5)<<5) | _u(rd,5)) & M32
# b offs (offs in bytes, 26-bit)
def b(off):
    o = _u(off >> 2, 26)
    return (0x50000000 | ((o & 0xffff)<<10) | ((o>>16) & 0x3ff)) & M32

def build():
    # addresses are word-relative within program; PC base 0x1c000000
    prog = []
    def emit(w): prog.append(w & M32)
    emit(lu12i_w(5, 0x1fb00))    # 0x00
    emit(ld_w(6, 5, 0x10))       # 0x04
    emit(addi_w(7, 0, 0))        # 0x08
    emit(addi_w(8, 0, 1))        # 0x0c
    emit(addi_w(9, 0, 11))       # 0x10
    loop = len(prog)*4           # 0x14
    emit(add_w(7, 7, 8))         # 0x14
    emit(addi_w(8, 8, 1))        # 0x18
    bne_pc = len(prog)*4         # 0x1c
    emit(bne(8, 9, loop - bne_pc))   # back-branch (negative)
    emit(st_w(7, 5, 0x0))        # 0x20  seg7 <- sum
    emit(ld_w(10, 5, 0x10))      # 0x24  counter end
    emit(sub_w(11, 10, 6))       # 0x28  cycles
    emit(st_w(11, 5, 0x0))       # 0x2c  seg7 <- cycles
    done_pc = len(prog)*4        # 0x30
    emit(b(done_pc - done_pc))   # b . (offset 0 -> infinite loop)
    return prog

if __name__ == "__main__":
    words = build()
    with open("demo.mem", "w") as f:
        for w in words:
            f.write(f"{w:08x}\n")
    print(f"wrote demo.mem ({len(words)} words)")
