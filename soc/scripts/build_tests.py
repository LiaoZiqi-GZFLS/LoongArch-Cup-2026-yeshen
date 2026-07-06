#!/usr/bin/env python3
"""Build the chiplab functional and performance test images.

Reads soc/scripts/test_manifest.yaml and, for every entry:
  1. runs `make -C <build_dir> <build_target>` (default target for func),
  2. converts the resulting artifact to `soc/sw/tests/<mem_name>.mem`
     using soc/sw/bin2mem.py (raw binary conversion; add --elf if the
     manifest ever points at an ELF file).
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

import yaml


REPO = Path(__file__).resolve().parents[2]  # soc/scripts -> soc -> repo root
SOC = REPO / "soc"
BIN2MEM = SOC / "sw" / "bin2mem.py"
MANIFEST = SOC / "scripts" / "test_manifest.yaml"


def load_manifest():
    with MANIFEST.open() as f:
        data = yaml.safe_load(f)
    items = []
    for category in ("functional", "performance"):
        for entry in data.get(category, []):
            entry["category"] = category
            items.append(entry)
    return items, data.get("settings", {})


def build_one(entry, output_dir: Path, jobs: int):
    build_dir = REPO / entry["build_dir"]
    target = entry.get("build_target") or ""
    artifact = REPO / entry["output_artifact"]
    mem_name = entry["mem_name"]
    output = output_dir / f"{mem_name}.mem"

    if not build_dir.exists():
        raise FileNotFoundError(f"build_dir not found: {build_dir}")

    cmd = ["make", f"-C", str(build_dir)]
    if jobs > 1:
        cmd.append(f"-j{jobs}")
    if target:
        cmd.append(target)

    print(f"[build] {' '.join(cmd)}")
    subprocess.run(cmd, check=True)

    if not artifact.exists():
        raise FileNotFoundError(f"build artifact not found: {artifact}")

    output.parent.mkdir(parents=True, exist_ok=True)
    # All current artifacts are raw binaries; keep --elf support for future use.
    elf_flag = ["--elf"] if str(artifact).endswith(".elf") else []
    cmd = [sys.executable, str(BIN2MEM), str(artifact), str(output)] + elf_flag
    print(f"[convert] {' '.join(cmd)}")
    subprocess.run(cmd, check=True)
    print(f"[ok] {output}")


def main():
    parser = argparse.ArgumentParser(description="Build chiplab test images")
    parser.add_argument("-j", "--jobs", type=int, default=1,
                        help="parallel make jobs (default: 1)")
    parser.add_argument("-t", "--tests", nargs="+", metavar="NAME",
                        help="build only named tests (default: all)")
    parser.add_argument("-o", "--output-dir",
                        help="override .mem output directory")
    args = parser.parse_args()

    items, settings = load_manifest()
    output_dir = Path(args.output_dir) if args.output_dir else SOC / settings.get("mem_output_dir", "sw/tests")

    wanted = set(args.tests) if args.tests else None
    failed = []
    for item in items:
        if wanted and item["name"] not in wanted:
            continue
        try:
            build_one(item, output_dir, args.jobs)
        except Exception as e:
            print(f"[FAIL] {item['name']}: {e}", file=sys.stderr)
            failed.append(item["name"])

    if failed:
        print(f"\n{len(failed)} build(s) failed: {', '.join(failed)}", file=sys.stderr)
        return 1
    print("\nAll builds succeeded.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
