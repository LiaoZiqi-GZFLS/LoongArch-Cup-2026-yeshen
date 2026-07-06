#!/usr/bin/env python3
"""Print a one-line CI status from the latest JSON report."""
import json
import sys
from pathlib import Path

REPORTS = Path(__file__).resolve().parents[2] / "sw" / "tests" / "reports"


def main():
    files = sorted(REPORTS.glob("run-*.json"))
    if not files:
        print("NO_REPORT")
        return 1
    report = json.loads(files[-1].read_text(encoding="utf-8"))
    results = report.get("results", {})
    passed = sum(1 for r in results.values() if r.get("status") == "PASS")
    total = len(results)
    failed = [n for n, r in results.items() if r.get("status") != "PASS"]
    print(f"STATUS={'PASS' if not failed else 'FAIL'}  {passed}/{total} passed")
    if failed:
        print("FAILED:", ", ".join(failed))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
