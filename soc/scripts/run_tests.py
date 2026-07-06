#!/usr/bin/env python3
"""Parameterized test runner for the LoongArch SoC functional/performance suite.

Reads soc/scripts/test_manifest.yaml, builds per-test simulation wrappers,
executes the selected simulator, and writes a JSON report.
"""

import argparse
import json
import os
import re
import shutil
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


REQUIRED_TEST_KEYS = ("name", "mem_name", "timeout_cycles", "stable_cycles")


def repo_root() -> Path:
    """Return repository root computed from this script's location."""
    return Path(__file__).resolve().parents[2]


def to_posix(path: Path) -> str:
    """Return an absolute POSIX-style path string for MSYS2/bash subprocesses."""
    return path.resolve().as_posix()


def find_bash() -> str | None:
    """Locate a usable bash.exe on Windows; returns None on other platforms."""
    if sys.platform != "win32":
        return None
    path = shutil.which("bash")
    if path:
        return path
    for candidate in (
        r"C:\msys64\usr\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
        r"C:\Program Files\Git\bin\bash.exe",
    ):
        if os.path.isfile(candidate):
            return candidate
    return None


def parse_const(s: str) -> int:
    """Parse a Verilog-style constant: 0b..., 0x..., or decimal."""
    s = s.strip().replace("_", "")
    if s.startswith("0b") or s.startswith("0B"):
        return int(s[2:], 2)
    if s.startswith("0x") or s.startswith("0X"):
        return int(s[2:], 16)
    return int(s, 10)


def load_manifest(path: Path) -> dict[str, Any]:
    """Load and validate the test manifest."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"Error parsing manifest {path}:\n{e}", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"Error reading manifest {path}:\n{e}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(data, dict):
        print(f"Error: manifest root must be a mapping ({path})", file=sys.stderr)
        sys.exit(1)

    for category in ("functional", "performance"):
        entries = data.get(category) or []
        if not isinstance(entries, list):
            print(
                f"Error: manifest category '{category}' must be a list",
                file=sys.stderr,
            )
            sys.exit(1)
        for idx, entry in enumerate(entries):
            if not isinstance(entry, dict):
                print(
                    f"Error: {category}[{idx}] is not a mapping",
                    file=sys.stderr,
                )
                sys.exit(1)
            missing = [k for k in REQUIRED_TEST_KEYS if k not in entry]
            if missing:
                name = entry.get("name", f"{category}[{idx}]")
                print(
                    f"Error: test '{name}' missing required keys: {missing}",
                    file=sys.stderr,
                )
                sys.exit(1)
            # Validate expect constants early so malformed values fail fast.
            expect = entry.get("expect") or {}
            for key in ("num_data", "led_rg0", "led_rg1"):
                if key in expect:
                    try:
                        parse_const(expect[key])
                    except ValueError as e:
                        print(
                            f"Error: test '{entry['name']}' expect.{key} "
                            f"is not a valid constant: {expect[key]} ({e})",
                            file=sys.stderr,
                        )
                        sys.exit(1)

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
    """Select tests by category and optional name list.

    If explicit test names are given, they take precedence and the category
    filter is ignored so that a single -t argument can target any test.
    """
    if names:
        wanted = set(names)
        return [t for t in items if t.get("name") in wanted]
    if category != "all":
        return [t for t in items if t.get("category") == category]
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

    if expect.get("num_data_nonzero"):
        params.append(("REQUIRE_NUM_DATA_NONZERO", "1'b1"))

    if test.get("category") == "performance":
        params.append(("ENABLE_DIAG", "1'b1"))
        params.append(("DUMP_HANG", "1'b1"))

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
    # A non-zero simulator exit code is always a failure, regardless of log text.
    if returncode != 0:
        status = "FAIL"
    elif re.search(r"\bPASS\b", log, re.IGNORECASE):
        status = "PASS"
    elif re.search(r"\bTIMEOUT\b", log, re.IGNORECASE):
        status = "TIMEOUT"
    else:
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


def _run_subprocess(cmd: list[str]) -> tuple[int, str, float]:
    """Run a command, returning (returncode, combined_output, elapsed_sec)."""
    start = time.perf_counter()
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, PermissionError, OSError) as e:
        return (
            -1,
            f"Failed to launch subprocess: {' '.join(cmd)}\n{e}",
            0.0,
        )
    except subprocess.TimeoutExpired as e:
        return (
            -1,
            f"Subprocess timed out: {' '.join(cmd)}\n{e}",
            time.perf_counter() - start,
        )
    elapsed = time.perf_counter() - start
    return proc.returncode, proc.stdout + proc.stderr, elapsed


def run_verilator(
    test: dict[str, Any], mem_file: Path, workdir: Path
) -> dict[str, Any]:
    """Run the generic Verilator flow for a single test."""
    wrapper = generate_wrapper(workdir, test, mem_file)
    script = repo_root() / "soc" / "build" / "run_verilator_generic.sh"
    if not script.exists():
        return {
            "status": "FAIL",
            "log": f"Verilator harness script not found: {script}",
            "elapsed_sec": 0.0,
            "num_data": None,
        }

    # On Windows, .sh files are not executable directly; run through bash.
    bash = find_bash()
    if bash:
        cmd = [bash, to_posix(script), to_posix(workdir), to_posix(wrapper)]
    else:
        cmd = [to_posix(script), to_posix(workdir), to_posix(wrapper)]

    returncode, log, elapsed = _run_subprocess(cmd)
    return parse_result(returncode, log, elapsed)


def run_xsim(test: dict[str, Any], mem_file: Path, workdir: Path) -> dict[str, Any]:
    """Run the generic Vivado xsim flow for a single test."""
    wrapper = generate_wrapper(workdir, test, mem_file)
    script = repo_root() / "soc" / "build" / "xsim_generic.tcl"
    if not script.exists():
        return {
            "status": "FAIL",
            "log": f"xsim harness script not found: {script}",
            "elapsed_sec": 0.0,
            "num_data": None,
        }

    # The testbench clock period is 10 ns. Multiply timeout_cycles by 12 to
    # give a small margin beyond the Verilog timeout.
    run_ns = test["timeout_cycles"] * 12
    cmd = [
        "vivado",
        "-mode",
        "batch",
        "-source",
        to_posix(script),
        "-tclargs",
        to_posix(wrapper),
        str(run_ns),
        to_posix(workdir),
    ]
    returncode, log, elapsed = _run_subprocess(cmd)
    return parse_result(returncode, log, elapsed)


def run_one(
    test: dict[str, Any],
    simulator: str,
    settings: dict[str, Any],
) -> dict[str, Any]:
    """Prepare, execute, and log one test."""
    root = repo_root()
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
        default=None,
        help="Simulator backend (default: manifest default_simulator or verilator).",
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
        result = run_one(test, simulator, settings)
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
