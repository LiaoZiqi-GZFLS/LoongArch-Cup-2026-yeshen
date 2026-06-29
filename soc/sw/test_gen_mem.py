import gen_mem as g

def check(name, got, want):
    assert got == want, f"{name}: got {got:#010x} want {want:#010x}"

# Known-good encodings (LoongArch32R)
check("lu12i.w r5,0x1fb00", g.lu12i_w(5, 0x1fb00), 0x143f6005)
check("addi.w r8,r0,1",     g.addi_w(8, 0, 1),     0x02800408)
check("add.w r7,r7,r8",     g.add_w(7, 7, 8),      0x001020e7)
check("st.w r7,r5,0",       g.st_w(7, 5, 0),       0x298000a7)
check("ld.w r6,r5,0x10",    g.ld_w(6, 5, 0x10),    0x288040a6)
print("PASS test_gen_mem")
