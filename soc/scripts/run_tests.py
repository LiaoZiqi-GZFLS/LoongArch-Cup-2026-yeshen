#!/usr/bin/env python3
"""Parameterized test runner for the LoongArch SoC functional/performance suite.

Reads soc/scripts/test_manifest.yaml, builds per-test simulation wrappers,
executes the selected simulator, and writes a JSON report.
"""

import argparse
import json
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    print(
        "Error: PyYAML is required but not installed.\n"
        "Install it with: pip install pyyaml",
        file=sys.stderr,
    )
    sys.exit(1)


def repo_root() -> Path:
    """Return repository root computed from this script's location."""
    return Path(__file__).resolve().parents[2]


def parse_const(s: str) -> int:
    """Parse a Verilog-style constant: 0b..., 0x..., or decimal."""
    s = s.strip().replace("_", "")
    if s.startswith("0b") or s.startswith("0B"):
        return int(s[2:], 2)
    if s.startswith("0x") or s.startswith("0X"):
        return int(s[2:], 16)
    return int(s, 10)


def load_manifest(path: Path) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return data


def flatten_tests(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    """Flatten functional + performance lists and add a category field."""
    tests: list[dict[str, Any]] = []
    for category in ("functional", "performance"):
        for entry in manifest.get(category, []) or []:
            test = dict(entry)
            test["category"] = category
            tests.append(test)
    return tests


def select_tests(
    items: list[dict[str, Any]], category: str, names: list[str] | None
) -> list[dict[str, Any]]:
    """Select tests by category and optional name list."""
    if category != "all":
        items = [t for t in items if t.get("category") == category]
    if names:
        items = [t for t in items if t.get("name") in names]
    return items


def vfmt_int(value: int, width: int = 32) -> str:
    """Format an integer as a Verilog hex literal (e.g. 32'h3a00003a)."""
    return f"{width}'h{value & ((1 << width) - 1):0{width // 4}x}"


def generate_wrapper(workdir: Path, test: dict[str, Any], mem_file: Path) -> Path:
    """Create workdir/tb_run.v instantiating tb_soc_generic for this test."""
    workdir.mkdir(parents=True, exist_ok=True)
    wrapper = workdir / "tb_run.v"

    expect = test.get("expect") or {}

    params: list[tuple[str, str]] = [
        ("INIT_FILE", f'"{mem_file.as_posix()}"'),
        ("TIMEOUT_CYCLES", str(test["timeout_cycles"])),
        ("STABLE_CYCLES", str(test["stable_cycles"])),
    ]

    if "num_data" in expect:
        params.append(("EXPECT_NUM_DATA", vfmt_int(parse_const(expect["num_data"]), 32)))
    if "led_rg0" in expect:
        params.append(("EXPECT_LED_RG0", vfmt_int(parse_const(expect["led_rg0"]), 2)))
    if "led_rg1" in expect:
        params.append(("EXPECT_LED_RG1", vfmt_int(parse_const(expect["led_rg1"]), 2)))

    params.append(
        (
            "REQUIRE_NUM_DATA_NONZERO",
            "1'b1" if expect.get("num_data_nonzero") else "1'b0",
        )
    )

    if test.get("category") == "performance":
        params.append(("ENABLE_DIAG", "1'b1"))
        params.append(("DUMP_HANG", "1'b1"))
    else:
        params.append(("ENABLE_DIAG", "1'b0"))
        params.append(("DUMP_HANG", "1'b0"))

    param_lines = ",\n    ".join(f".{name}({value})" for name, value in params)

    text = f"""`timescale 1ns/1ps
// Auto-generated test wrapper for {test['name']}
module tb_run;
  tb_soc_generic #(
    {param_lines}
  ) u_tb ();
endmodule
"""

    with open(wrapper, "w", encoding="utf-8") as f:
        f.write(text)
    return wrapper


def parse_result(returncode: int, log: str, elapsed: float) -> dict[str, Any]:
    """Infer PASS/FAIL/TIMEOUT from the simulator log."""
    status = "FAIL"
    if re.search(r"\bPASS\b", log, re.IGNORECASE):
        status = "PASS"
    elif re.search(r"\bTIMEOUT\b", log, re.IGNORECASE):
        status = "TIMEOUT"
    elif re.search(r"\bFAIL\b", log, re.IGNORECASE):
        status = "FAIL"
    elif returncode != 0:
        status = "FAIL"

    num_data: int | None = None
    m = re.search(r"num_data=0x([0-9a-fA-F]+)", log)
    if m:
        num_data = int(m.group(1), 16)

    return {
        "status": status,
        "log": log,
        "elapsed_sec": round(elapsed, 3),
        "num_data": num_data,
    }


def run_verilator(
    test: dict[str, Any], mem_file: Path, workdir: Path
) -> dict[str, Any]:
    """Run the generic Verilator flow for a single test."""
    generate_wrapper(workdir, test, mem_file)
    script = repo_root() / "soc" / "build" / "run_verilator_generic.sh"
    start = time.perf_counter()
    proc = subprocess.run(
        [str(script), str(workdir), "tb_run.v"],
        capture_output=True,
        text=True,
    )
    elapsed = time.perf_counter() - start
    log = proc.stdout + proc.stderr
    return parse_result(proc.returncode, log, elapsed)


def run_xsim(test: dict[str, Any], mem_file: Path, workdir: Path) -> dict[str, Any]:
    """Run the generic Vivado xsim flow for a single test."""
    generate_wrapper(workdir, test, mem_file)
    script = repo_root() / "soc" / "build" / "xsim_generic.tcl"
    run_ns = test["timeout_cycles"] * 12
    start = time.perf_counter()
    proc = subprocess.run(
        [
            "vivado",
            "-mode",
            "batch",
            "-source",
            str(script),
            "-tclargs",
            "tb_run.v",
            str(run_ns),
            str(workdir),
        ],
        capture_output=True,
        text=True,
    )
    elapsed = time.perf_counter() - start
    log = proc.stdout + proc.stderr
    return parse_result(proc.returncode, log, elapsed)


def run_one(test: dict[str, Any], simulator: str) -> dict[str, Any]:
    """Prepare, execute, and log one test."""
    root = repo_root()
    manifest = load_manifest(root / "soc" / "scripts" / "test_manifest.yaml")
    settings = manifest.get("settings", {})
    mem_output_dir = root / settings.get("mem_output_dir", "soc/sw/tests")

    mem_file = mem_output_dir / f"{test['mem_name']}.mem"
    if not mem_file.exists():
        return {
            "status": "FAIL",
            "log": f"Memory file not found: {mem_file}",
            "elapsed_sec": 0.0,
            "num_data": None,
        }

    workdir = mem_output_dir / "reports" / f"run_{test['name']}"
    workdir.mkdir(parents=True, exist_ok=True)

    if simulator == "verilator":
        result = run_verilator(test, mem_file, workdir)
    elif simulator == "xsim":
        result = run_xsim(test, mem_file, workdir)
    else:
        result = {
            "status": "FAIL",
            "log": f"Unknown simulator: {simulator}",
            "elapsed_sec": 0.0,
            "num_data": None,
        }

    log_path = workdir / "sim.log"
    with open(log_path, "w", encoding="utf-8") as f:
        f.write(result["log"])

    result["workdir"] = str(workdir)
    result["log_path"] = str(log_path)
    return result


def print_summary(results: list[dict[str, Any]]) -> None:
    """Print a terminal summary table."""
    header = f"{'NAME':<24} {'CATEGORY':<12} {'SIM':<10} {'STATUS':<8} {'TIME(s)':>10}"
    print(header)
    print("-" * len(header))
    for r in results:
        print(
            f"{r['name']:<24} {r['category']:<12} {r['simulator']:<10} "
            f"{r['status']:<8} {r['elapsed_sec']:>10.3f}"
        )
    print("-" * len(header))
    total = len(results)
    passed = sum(1 for r in results if r["status"] == "PASS")
    print(f"TOTAL: {total}  PASS: {passed}  FAIL: {total - passed}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Run LoongArch SoC functional/performance tests."
    )
    parser.add_argument(
        "-c",
        "--category",
        choices=["functional", "performance", "all"],
        default="functional",
        help="Test category to run (default: functional).",
    )
    parser.add_argument(
        "-t",
        "--tests",
        nargs="+",
        default=None,
        help="Run only these named tests.",
    )
    parser.add_argument(
        "-s",
        "--simulator",
        choices=["verilator", "xsim"],
        default="verilator",
        help="Simulator backend (default: verilator).",
    )
    parser.add_argument(
        "-o",
        "--report",
        default=None,
        help="Path for the JSON report.",
    )
    args = parser.parse_args(argv)

    root = repo_root()
    manifest_path = root / "soc" / "scripts" / "test_manifest.yaml"
    manifest = load_manifest(manifest_path)
    settings = manifest.get("settings", {})
    simulator = args.simulator or settings.get("default_simulator", "verilator")

    tests = flatten_tests(manifest)
    selected = select_tests(tests, args.category, args.tests)

    if not selected:
        print("No tests selected.", file=sys.stderr)
        return 1

    results: list[dict[str, Any]] = []
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")

    for test in selected:
        name = test["name"]
        print(f"\n=== Running {name} ({test['category']}) with {simulator} ===")
        result = run_one(test, simulator)
        result["name"] = name
        result["category"] = test["category"]
        result["simulator"] = simulator
        results.append(result)
        print(f"Result: {result['status']} ({result['elapsed_sec']:.3f}s)")
        if result["status"] != "PASS":
            tail = "\n".join(result["log"].splitlines()[-20:])
            print(tail)

    print_summary(results)

    if args.report:
        report_path = Path(args.report)
    else:
        report_dir = root / "soc" / "sw" / "tests" / "reports"
        report_dir.mkdir(parents=True, exist_ok=True)
        report_path = report_dir / f"run-{timestamp}.json"

    report = {
        "timestamp": timestamp,
        "simulator": simulator,
        "category": args.category,
        "tests": results,
    }
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"\nReport written to: {report_path}")

    return 0 if all(r["status"] == "PASS" for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
