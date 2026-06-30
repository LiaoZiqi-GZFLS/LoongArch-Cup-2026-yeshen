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
    """Convert a binary file to little-endian word .mem format.

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
        help="input is an ELF file; call objcopy first (requires toolchain in PATH)",
    )
    parser.add_argument(
        "--objcopy",
        default="loongarch32r-linux-gnusf-objcopy",
        help="objcopy executable name/path (default: loongarch32r-linux-gnusf-objcopy)",
    )
    args = parser.parse_args(argv)

    if not args.input.exists():
        print(f"ERROR: input file not found: {args.input}", file=sys.stderr)
        return 1

    if args.elf:
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            bin_path = Path(tmpdir) / "image.bin"
            cmd = [args.objcopy, "-O", "binary", str(args.input), str(bin_path)]
            print(f"Running: {' '.join(cmd)}")
            subprocess.run(cmd, check=True)
            stats = bin_to_mem(bin_path, args.output, args.width)
    else:
        stats = bin_to_mem(args.input, args.output, args.width)

    print(f"Wrote {args.output}")
    print(f"  bytes in : {stats['bytes_in']}")
    print(f"  words out: {stats['words_out']}")
    print(f"  padding  : {stats['padding']} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
