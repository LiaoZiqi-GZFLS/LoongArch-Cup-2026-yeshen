#!/usr/bin/env python3
"""Convert a LoongArch binary image to the .mem format used by axi_mem_soc.

Usage:
    python bin2mem.py input.bin output.mem
    python bin2mem.py input.elf output.mem --elf
    loongarch32r-linux-gnusf-objcopy -O binary input.elf input.bin
    python bin2mem.py input.bin output.mem

Output format:
    One 32-bit little-endian word per line, as 8 hex digits.
    Word 0 maps to reset PC 0x1c000000.
    The file is zero-padded to a multiple of 4 bytes.
"""

import argparse
import struct
import sys
from pathlib import Path


def bin_to_mem(input_path: Path, output_path: Path, width: int = 32) -> dict:
    """Convert a raw binary file to little-endian word .mem format.

    Parameters
    ----------
    input_path : Path
        Raw binary image (e.g. from objcopy -O binary).
    output_path : Path
        Destination .mem file.
    width : int
        Word width in bits. Currently only 32 is supported.

    Returns
    -------
    dict with conversion metadata (bytes_in, words_out, padding).
    """
    if width != 32:
        raise ValueError("only 32-bit words are supported")

    data = input_path.read_bytes()
    bytes_in = len(data)
    padding = (-bytes_in) % 4
    if padding:
        data += b"\x00" * padding

    words_out = len(data) // 4
    with output_path.open("w", newline="\n") as f:
        for i in range(0, len(data), 4):
            word = struct.unpack("<I", data[i:i + 4])[0]
            f.write(f"{word:08x}\n")

    return {
        "bytes_in": bytes_in,
        "words_out": words_out,
        "padding": padding,
    }


def elf_to_mem(input_path: Path, output_path: Path, width: int = 32) -> dict:
    """Convert an ELF file to a .mem image using each LOAD segment's p_paddr.

    ChipLab performance-test binaries contain a startup routine that copies the
    data segment from its load address (p_paddr) to its virtual address (p_vaddr).
    A bare-metal SoC BRAM therefore needs the segment data at p_paddr.  This
    function builds a byte image spanning from the lowest p_paddr to the highest
    p_paddr+p_memsz and writes it as little-endian words.
    """
    if width != 32:
        raise ValueError("only 32-bit words are supported")

    data = input_path.read_bytes()
    if data[:4] != b"\x7fELF":
        raise ValueError("input is not an ELF file")
    if data[4] != 1:
        raise ValueError("only 32-bit ELF is supported")

    phoff = struct.unpack("<I", data[28:32])[0]
    phentsize = struct.unpack("<H", data[42:44])[0]
    phnum = struct.unpack("<H", data[44:46])[0]

    segments = []
    for i in range(phnum):
        off = phoff + i * phentsize
        p_type = struct.unpack("<I", data[off:off + 4])[0]
        if p_type != 1:  # PT_LOAD
            continue
        p_offset = struct.unpack("<I", data[off + 4:off + 8])[0]
        p_paddr = struct.unpack("<I", data[off + 12:off + 16])[0]
        p_filesz = struct.unpack("<I", data[off + 16:off + 20])[0]
        p_memsz = struct.unpack("<I", data[off + 20:off + 24])[0]
        if p_memsz:
            segments.append((p_offset, p_paddr, p_filesz, p_memsz))

    if not segments:
        raise ValueError("no PT_LOAD segments found")

    base = min(s[1] for s in segments)
    max_addr = max(s[1] + s[3] for s in segments)
    image = bytearray(max_addr - base)
    for p_offset, p_paddr, p_filesz, p_memsz in segments:
        dest = p_paddr - base
        if p_filesz:
            image[dest:dest + p_filesz] = data[p_offset:p_offset + p_filesz]
        # p_memsz > p_filesz area is already zero-initialized

    padding = (-len(image)) % 4
    if padding:
        image += b"\x00" * padding

    words_out = len(image) // 4
    with output_path.open("w", newline="\n") as f:
        for i in range(0, len(image), 4):
            word = struct.unpack("<I", image[i:i + 4])[0]
            f.write(f"{word:08x}\n")

    return {
        "bytes_in": len(data),
        "words_out": words_out,
        "padding": padding,
        "base_addr": base,
        "segments": len(segments),
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert a LoongArch binary to axi_mem_soc .mem format"
    )
    parser.add_argument("input", type=Path, help="input binary file")
    parser.add_argument("output", type=Path, help="output .mem file")
    parser.add_argument(
        "--width",
        type=int,
        default=32,
        choices=[32],
        help="word width (default: 32)",
    )
    parser.add_argument(
        "--elf",
        action="store_true",
        help="input is an ELF file; build .mem from PT_LOAD p_paddr segments",
    )
    parser.add_argument(
        "--bin",
        action="store_true",
        help="input is a raw binary image (default if --elf not given)",
    )
    args = parser.parse_args(argv)

    if not args.input.exists():
        print(f"ERROR: input file not found: {args.input}", file=sys.stderr)
        return 1

    if args.elf:
        stats = elf_to_mem(args.input, args.output, args.width)
    else:
        stats = bin_to_mem(args.input, args.output, args.width)

    print(f"Wrote {args.output}")
    print(f"  bytes in : {stats['bytes_in']}")
    print(f"  words out: {stats['words_out']}")
    print(f"  padding  : {stats['padding']} bytes")
    if 'base_addr' in stats:
        print(f"  base addr: 0x{stats['base_addr']:08x}")
        print(f"  segments : {stats['segments']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
