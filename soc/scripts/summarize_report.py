#!/usr/bin/env python3
"""Print a one-line CI status from the latest JSON report."""
import argparse
import json
import sys
from pathlib import Path

REPORTS = Path(__file__).resolve().parents[1] / "sw" / "tests" / "reports"


def main():
    parser = argparse.ArgumentParser(description="Print CI status from a report")
    parser.add_argument("--report", type=Path, help="specific report JSON to summarize")
    args = parser.parse_args()

    if args.report:
        report_file = args.report
    else:
        files = sorted(REPORTS.glob("run-*.json"))
        if not files:
            print("NO_REPORT")
            return 1
        report_file = files[-1]

    report = json.loads(report_file.read_text(encoding="utf-8"))
    # The runner writes either a dict keyed by test name or a list under "tests".
    raw_results = report.get("results")
    tests = report.get("tests", [])
    if raw_results is None and not tests:
        print("NO_RESULTS")
        return 1

    if raw_results is not None:
        results = [
            {"name": name, **r}
            for name, r in raw_results.items()
        ]
    else:
        results = tests

    passed = sum(1 for r in results if r.get("status") == "PASS")
    total = len(results)
    failed = [r["name"] for r in results if r.get("status") != "PASS"]
    print(f"STATUS={'PASS' if not failed else 'FAIL'}  {passed}/{total} passed")
    if failed:
        print("FAILED:", ", ".join(failed))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
