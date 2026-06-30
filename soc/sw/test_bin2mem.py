import bin2mem
import tempfile
from pathlib import Path


def test_bin2mem_known_words():
    """Round-trip a small binary built from the demo program words."""
    words = [
        0x143f6005,  # lu12i.w r5,0x1fb00
        0x288040a6,  # ld.w r6,r5,0x10
        0x02800007,  # addi.w r7,r0,0
        0x02800408,  # addi.w r8,r0,1
        0x02802c09,  # addi.w r9,r0,11
        0x001020e7,  # add.w r7,r7,r8
        0x02800508,  # addi.w r8,r8,1
        0x5ffff909,  # bne r8,r9,-8
        0x298000a7,  # st.w r7,r5,0
        0x288040aa,  # ld.w r10,r5,0x10
        0x0011194b,  # sub.w r11,r10,r6
        0x298000ab,  # st.w r11,r5,0
        0x50000000,  # b .
    ]
    binary = b"".join(w.to_bytes(4, "little") for w in words)

    with tempfile.TemporaryDirectory() as tmpdir:
        inp = Path(tmpdir) / "test.bin"
        out = Path(tmpdir) / "test.mem"
        inp.write_bytes(binary)
        stats = bin2mem.bin_to_mem(inp, out)
        assert stats["bytes_in"] == len(words) * 4
        assert stats["words_out"] == len(words)
        assert stats["padding"] == 0

        lines = out.read_text().splitlines()
        assert len(lines) == len(words)
        for line, w in zip(lines, words):
            assert line == f"{w:08x}"


def test_bin2mem_padding():
    """A 5-byte input is padded to 2 words."""
    binary = b"\x05\x00\x60\x3f\x14"  # partial second word
    with tempfile.TemporaryDirectory() as tmpdir:
        inp = Path(tmpdir) / "test.bin"
        out = Path(tmpdir) / "test.mem"
        inp.write_bytes(binary)
        stats = bin2mem.bin_to_mem(inp, out)
        assert stats["bytes_in"] == 5
        assert stats["words_out"] == 2
        assert stats["padding"] == 3
        lines = out.read_text().splitlines()
        assert lines[0] == "3f600005"
        assert lines[1] == "00000014"


def test_bin2mem_demo_matches_gen_mem():
    """The script should reproduce the same .mem as gen_mem.py for demo.S."""
    import gen_mem
    # Build the demo image the same way gen_mem.py does.
    words = [
        gen_mem.lu12i_w(5, 0x1fb00),
        gen_mem.ld_w(6, 5, 0x10),
        gen_mem.addi_w(7, 0, 0),
        gen_mem.addi_w(8, 0, 1),
        gen_mem.addi_w(9, 0, 11),
        gen_mem.add_w(7, 7, 8),
        gen_mem.addi_w(8, 8, 1),
        gen_mem.bne(8, 9, -8),
        gen_mem.st_w(7, 5, 0),
        gen_mem.ld_w(10, 5, 0x10),
        gen_mem.sub_w(11, 10, 6),
        gen_mem.st_w(11, 5, 0),
        gen_mem.b(0),
    ]
    binary = b"".join(w.to_bytes(4, "little") for w in words)

    with tempfile.TemporaryDirectory() as tmpdir:
        inp = Path(tmpdir) / "demo.bin"
        out = Path(tmpdir) / "demo.mem"
        inp.write_bytes(binary)
        bin2mem.bin_to_mem(inp, out)
        generated = out.read_text().splitlines()

        # Compare against the checked-in demo.mem
        checked_in = Path(__file__).with_name("demo.mem").read_text().splitlines()
        assert generated == checked_in


if __name__ == "__main__":
    test_bin2mem_known_words()
    test_bin2mem_padding()
    test_bin2mem_demo_matches_gen_mem()
    print("PASS test_bin2mem")
