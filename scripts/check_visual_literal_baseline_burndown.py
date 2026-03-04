#!/usr/bin/env python3
"""Validate wave-level baseline literal debt budgets."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

DEFAULT_TARGETS = "docs/design/visual-literal-baseline-targets.v1.json"
DEFAULT_IOS_BASELINE = "docs/design/baselines/ios-visual-literals-baseline.txt"
DEFAULT_ANDROID_BASELINE = "docs/design/baselines/android-visual-literals-baseline.txt"
DEFAULT_REPORT_OUT = "artifacts/visual-system/literal-baseline-burndown-report.json"


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def count_lines(path: Path) -> int:
    return len(path.read_text(encoding="utf-8").splitlines())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wave", default="wave1")
    parser.add_argument("--targets", default=DEFAULT_TARGETS)
    parser.add_argument("--ios-baseline", default=DEFAULT_IOS_BASELINE)
    parser.add_argument("--android-baseline", default=DEFAULT_ANDROID_BASELINE)
    parser.add_argument("--report-out", default=DEFAULT_REPORT_OUT)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    targets_path = repo_root / args.targets
    ios_path = repo_root / args.ios_baseline
    android_path = repo_root / args.android_baseline

    issues: list[str] = []
    if not targets_path.exists():
        issues.append(f"targets file not found: {targets_path}")
    if not ios_path.exists():
        issues.append(f"iOS baseline file not found: {ios_path}")
    if not android_path.exists():
        issues.append(f"Android baseline file not found: {android_path}")

    payload: dict[str, Any] = {}
    if not issues:
        payload = load_json(targets_path)
        waves = payload.get("waves", {})
        if args.wave not in waves:
            issues.append(f"wave '{args.wave}' not defined in targets file")

    ios_count = count_lines(ios_path) if ios_path.exists() else 0
    android_count = count_lines(android_path) if android_path.exists() else 0

    ios_max = None
    android_max = None
    if not issues:
        wave_cfg = payload["waves"][args.wave]
        ios_max = int(wave_cfg.get("iosMax", -1))
        android_max = int(wave_cfg.get("androidMax", -1))
        if ios_count > ios_max:
            issues.append(f"iOS baseline count {ios_count} exceeds wave budget {ios_max}")
        if android_count > android_max:
            issues.append(f"Android baseline count {android_count} exceeds wave budget {android_max}")

    report = {
        "passed": len(issues) == 0,
        "issueCount": len(issues),
        "issues": issues,
        "wave": args.wave,
        "targetsPath": args.targets,
        "iosBaselinePath": args.ios_baseline,
        "androidBaselinePath": args.android_baseline,
        "counts": {
            "ios": ios_count,
            "android": android_count,
        },
        "limits": {
            "iosMax": ios_max,
            "androidMax": android_max,
        },
    }

    report_path = repo_root / args.report_out
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if report["passed"]:
        print("visual literal baseline burndown check passed")
        print(f"report: {report_path}")
        return 0

    print("visual literal baseline burndown check failed")
    for issue in issues:
        print(f"- {issue}")
    print(f"report: {report_path}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
