#!/usr/bin/env python3
# Minimal LA32R disassembler based on id_stage decode logic

def sext(val, bits):
    sign = 1 << (bits - 1)
    return (val ^ sign) - sign

def decode(inst, pc=None):
    op = (inst >> 26) & 0x3f
    op_25_22 = (inst >> 22) & 0xf
    op_21_20 = (inst >> 20) & 0x3
    op_19_15 = (inst >> 15) & 0x1f
    rd = inst & 0x1f
    rj = (inst >> 5) & 0x1f
    rk = (inst >> 10) & 0x1f
    i5 = rk
    i12 = (inst >> 10) & 0xfff
    si12 = sext(i12, 12)
    i14 = (inst >> 10) & 0x3fff
    si14 = sext(i14, 14)
    i16 = (inst >> 10) & 0xffff
    si16 = sext(i16, 16)
    i20 = (inst >> 5) & 0xfffff
    si20 = sext(i20, 20)
    i26 = ((inst & 0x3ff) << 16) | ((inst >> 10) & 0xffff)
    si26 = sext(i26, 26)
    csr_num = (inst >> 10) & 0x3fff

    op_31_26_d = [op == i for i in range(64)]
    op_25_22_d = [op_25_22 == i for i in range(16)]
    op_21_20_d = [op_21_20 == i for i in range(4)]
    op_19_15_d = [op_19_15 == i for i in range(32)]

    def op_is(*args):
        return all(args)

    inst_add_w = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[0])
    inst_sub_w = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[2])
    inst_slt   = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[4])
    inst_sltu  = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[5])
    inst_nor   = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[8])
    inst_and   = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[9])
    inst_or    = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[10])
    inst_xor   = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[11])
    inst_orn   = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[12])
    inst_andn  = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[13])
    inst_sll_w = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[14])
    inst_srl_w = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[15])
    inst_sra_w = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[16])
    inst_mul_w = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[24])
    inst_mulh_w= op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[25])
    inst_mulh_wu=op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[1], op_19_15_d[26])
    inst_div_w = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[2], op_19_15_d[0])
    inst_mod_w = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[2], op_19_15_d[1])
    inst_div_wu= op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[2], op_19_15_d[2])
    inst_mod_wu= op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[2], op_19_15_d[3])
    inst_break = op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[2], op_19_15_d[20])
    inst_syscall=op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[2], op_19_15_d[22])
    inst_slli_w= op_is(op_31_26_d[0], op_25_22_d[1], op_21_20_d[0], op_19_15_d[1])
    inst_srli_w= op_is(op_31_26_d[0], op_25_22_d[1], op_21_20_d[0], op_19_15_d[9])
    inst_srai_w= op_is(op_31_26_d[0], op_25_22_d[1], op_21_20_d[0], op_19_15_d[17])
    inst_idle  = op_is(op_31_26_d[1], op_25_22_d[9], op_21_20_d[0], op_19_15_d[17])
    inst_dbar  = op_is(op_31_26_d[14], op_25_22_d[1], op_21_20_d[3], op_19_15_d[4])
    inst_ibar  = op_is(op_31_26_d[14], op_25_22_d[1], op_21_20_d[3], op_19_15_d[5])
    inst_slti  = op_is(op_31_26_d[0], op_25_22_d[8])
    inst_sltui = op_is(op_31_26_d[0], op_25_22_d[9])
    inst_addi_w= op_is(op_31_26_d[0], op_25_22_d[10])
    inst_andi  = op_is(op_31_26_d[0], op_25_22_d[13])
    inst_ori   = op_is(op_31_26_d[0], op_25_22_d[14])
    inst_xori  = op_is(op_31_26_d[0], op_25_22_d[15])
    inst_ld_b  = op_is(op_31_26_d[10], op_25_22_d[0])
    inst_ld_h  = op_is(op_31_26_d[10], op_25_22_d[1])
    inst_ld_w  = op_is(op_31_26_d[10], op_25_22_d[2])
    inst_st_b  = op_is(op_31_26_d[10], op_25_22_d[4])
    inst_st_h  = op_is(op_31_26_d[10], op_25_22_d[5])
    inst_st_w  = op_is(op_31_26_d[10], op_25_22_d[6])
    inst_ld_bu = op_is(op_31_26_d[10], op_25_22_d[8])
    inst_ld_hu = op_is(op_31_26_d[10], op_25_22_d[9])
    inst_jirl  = op_31_26_d[19]
    inst_b     = op_31_26_d[20]
    inst_bl    = op_31_26_d[21]
    inst_beq   = op_31_26_d[22]
    inst_bne   = op_31_26_d[23]
    inst_blt   = op_31_26_d[24]
    inst_bge   = op_31_26_d[25]
    inst_bltu  = op_31_26_d[26]
    inst_bgeu  = op_31_26_d[27]
    inst_lu12i_w=op_is(op_31_26_d[5], not (inst >> 25) & 1)
    inst_pcaddi=op_is(op_31_26_d[6], not (inst >> 25) & 1)
    inst_pcaddu12i=op_is(op_31_26_d[7], not (inst >> 25) & 1)
    inst_csrrd =op_is(op_31_26_d[1], not (inst >> 25) & 1, not (inst >> 24) & 1, rj == 0)
    inst_csrwr =op_is(op_31_26_d[1], not (inst >> 25) & 1, not (inst >> 24) & 1, rj == 1)
    inst_csrxchg=op_is(op_31_26_d[1], not (inst >> 25) & 1, not (inst >> 24) & 1, rj not in (0,1))
    inst_ll_w  =op_is(op_31_26_d[8], not (inst >> 25) & 1, not (inst >> 24) & 1)
    inst_sc_w  =op_is(op_31_26_d[8], not (inst >> 25) & 1, (inst >> 24) & 1)
    inst_rdcntid_w=op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[0], op_19_15_d[0], rk == 24, rd == 0)
    inst_rdcntvl_w=op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[0], op_19_15_d[0], rk == 24, rj == 0, rd != 0)
    inst_rdcntvh_w=op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[0], op_19_15_d[0], rk == 25, rj == 0)
    inst_ertn  =op_is(op_31_26_d[1], op_25_22_d[9], op_21_20_d[0], op_19_15_d[16], rk == 14, rj == 0, rd == 0)
    inst_cpucfg=op_is(op_31_26_d[0], op_25_22_d[0], op_21_20_d[0], op_19_15_d[0], rk == 27)

    def t26():
        off = si26 << 2
        return f"0x{((pc if pc else 0) + off) & 0xffffffff:08x}" if pc else f"off={off}"
    def t16():
        off = si16 << 2
        return f"0x{((pc if pc else 0) + off) & 0xffffffff:08x}" if pc else f"off={off}"

    if inst_add_w:   return f"add.w    r{rd}, r{rj}, r{rk}"
    if inst_sub_w:   return f"sub.w    r{rd}, r{rj}, r{rk}"
    if inst_slt:     return f"slt      r{rd}, r{rj}, r{rk}"
    if inst_sltu:    return f"sltu     r{rd}, r{rj}, r{rk}"
    if inst_nor:     return f"nor      r{rd}, r{rj}, r{rk}"
    if inst_and:     return f"and      r{rd}, r{rj}, r{rk}"
    if inst_or:      return f"or       r{rd}, r{rj}, r{rk}"
    if inst_xor:     return f"xor      r{rd}, r{rj}, r{rk}"
    if inst_orn:     return f"orn      r{rd}, r{rj}, r{rk}"
    if inst_andn:    return f"andn     r{rd}, r{rj}, r{rk}"
    if inst_sll_w:   return f"sll.w    r{rd}, r{rj}, r{rk}"
    if inst_srl_w:   return f"srl.w    r{rd}, r{rj}, r{rk}"
    if inst_sra_w:   return f"sra.w    r{rd}, r{rj}, r{rk}"
    if inst_mul_w:   return f"mul.w    r{rd}, r{rj}, r{rk}"
    if inst_mulh_w:  return f"mulh.w   r{rd}, r{rj}, r{rk}"
    if inst_mulh_wu: return f"mulh.wu  r{rd}, r{rj}, r{rk}"
    if inst_div_w:   return f"div.w    r{rd}, r{rj}, r{rk}"
    if inst_mod_w:   return f"mod.w    r{rd}, r{rj}, r{rk}"
    if inst_div_wu:  return f"div.wu   r{rd}, r{rj}, r{rk}"
    if inst_mod_wu:  return f"mod.wu   r{rd}, r{rj}, r{rk}"
    if inst_slli_w:  return f"slli.w   r{rd}, r{rj}, {i5}"
    if inst_srli_w:  return f"srli.w   r{rd}, r{rj}, {i5}"
    if inst_srai_w:  return f"srai.w   r{rd}, r{rj}, {i5}"
    if inst_addi_w:  return f"addi.w   r{rd}, r{rj}, {si12}"
    if inst_slti:    return f"slti     r{rd}, r{rj}, {si12}"
    if inst_sltui:   return f"sltui    r{rd}, r{rj}, {si12}"
    if inst_andi:    return f"andi     r{rd}, r{rj}, {i12}"
    if inst_ori:     return f"ori      r{rd}, r{rj}, {i12}"
    if inst_xori:    return f"xori     r{rd}, r{rj}, {i12}"
    if inst_lu12i_w: return f"lu12i.w  r{rd}, {si20}"
    if inst_pcaddi:  return f"pcaddi   r{rd}, {si20}"
    if inst_pcaddu12i: return f"pcaddu12i r{rd}, {si20}"
    if inst_ld_b:    return f"ld.b     r{rd}, r{rj}, {si12}"
    if inst_ld_h:    return f"ld.h     r{rd}, r{rj}, {si12}"
    if inst_ld_w:    return f"ld.w     r{rd}, r{rj}, {si12}"
    if inst_st_b:    return f"st.b     r{rd}, r{rj}, {si12}"
    if inst_st_h:    return f"st.h     r{rd}, r{rj}, {si12}"
    if inst_st_w:    return f"st.w     r{rd}, r{rj}, {si12}"
    if inst_ld_bu:   return f"ld.bu    r{rd}, r{rj}, {si12}"
    if inst_ld_hu:   return f"ld.hu    r{rd}, r{rj}, {si12}"
    if inst_jirl:    return f"jirl     r{rd}, r{rj}, {si16}"
    if inst_b:       return f"b        {t26()}"
    if inst_bl:      return f"bl       {t26()}"
    if inst_beq:     return f"beq      r{rj}, r{rd}, {t16()}"
    if inst_bne:     return f"bne      r{rj}, r{rd}, {t16()}"
    if inst_blt:     return f"blt      r{rj}, r{rd}, {t16()}"
    if inst_bge:     return f"bge      r{rj}, r{rd}, {t16()}"
    if inst_bltu:    return f"bltu     r{rj}, r{rd}, {t16()}"
    if inst_bgeu:    return f"bgeu     r{rj}, r{rd}, {t16()}"
    if inst_csrrd:   return f"csrrd    r{rd}, csr{csr_num}"
    if inst_csrwr:   return f"csrwr    r{rd}, csr{csr_num}"
    if inst_csrxchg: return f"csrxchg  r{rd}, r{rj}, csr{csr_num}"
    if inst_ll_w:    return f"ll.w     r{rd}, r{rj}, {si14}"
    if inst_sc_w:    return f"sc.w     r{rd}, r{rj}, {si14}"
    if inst_rdcntid_w: return f"rdcntid.w r{rd}"
    if inst_rdcntvl_w: return f"rdcntvl.w r{rd}"
    if inst_rdcntvh_w: return f"rdcntvh.w r{rd}"
    if inst_ertn:    return f"ertn"
    if inst_syscall: return f"syscall  {i12}"
    if inst_break:   return f"break    {i12}"
    if inst_dbar:    return f"dbar     {i12 & 0x7fff}"
    if inst_ibar:    return f"ibar     {i12 & 0x7fff}"
    if inst_idle:    return f"idle     {i12}"
    if inst_cpucfg:  return f"cpucfg   r{rd}, r{rj}"
    return f"unknown  0x{inst:08x} (op={op:02x})"

if __name__ == '__main__':
    import sys
    base = 0x1c000000
    mem = {}
    path = sys.argv[1] if len(sys.argv) > 1 else 'sw/perf_bitcount.mem'
    with open(path, 'r') as f:
        idx = 0
        for line in f:
            line = line.strip()
            if not line:
                continue
            mem[base + idx*4] = int(line, 16)
            idx += 1

    addrs = sorted(mem.keys())
    if len(sys.argv) > 2:
        # range mode: start end
        start = int(sys.argv[2], 0)
        end = int(sys.argv[3], 0)
        addrs = [a for a in addrs if start <= a <= end]
    for a in addrs:
        print(f"0x{a:08x}: 0x{mem[a]:08x}  {decode(mem[a], a)}")
