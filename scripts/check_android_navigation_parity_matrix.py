#!/usr/bin/env python3
"""Validate top-journey navigation parity matrix with Android presentation coverage."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


REQUIRED_JOURNEY_IDS = [
    "goal-create-edit",
    "monthly-budget-adjust",
    "destructive-delete-confirmation",
    "goal-contribution-edit-cancel",
    "planning-flow-cancel-recovery",
]
REQUIRED_STEPS = ["entry", "action", "cancel", "validationError", "recovery", "confirmation"]
ANDROID_REF_RE = re.compile(r"^android/app/src/main/java/.+/presentation/.+\.kt$")
IOS_REF_RE = re.compile(r"^ios/CryptoSavingsTracker/.+\.swift$")


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def validate_matrix(matrix: dict[str, Any], repo_root: Path) -> list[str]:
    issues: list[str] = []
    raw_journeys = matrix.get("journeys")
    if not isinstance(raw_journeys, list):
        return ["journeys must be a list"]

    by_id: dict[str, dict[str, Any]] = {}
    for idx, journey in enumerate(raw_journeys):
        if not isinstance(journey, dict):
            issues.append(f"journeys[{idx}] must be an object")
            continue
        journey_id = journey.get("id")
        if not isinstance(journey_id, str) or not journey_id:
            issues.append(f"journeys[{idx}].id must be a non-empty string")
            continue
        if journey_id in by_id:
            issues.append(f"duplicate journey id: {journey_id}")
            continue
        by_id[journey_id] = journey

    for journey_id in REQUIRED_JOURNEY_IDS:
        if journey_id not in by_id:
            issues.append(f"missing required journey id: {journey_id}")
            continue

        journey = by_id[journey_id]
        coverage = journey.get("coverage")
        if not isinstance(coverage, dict):
            issues.append(f"{journey_id}: coverage must be an object")
        else:
            for step in REQUIRED_STEPS:
                if coverage.get(step) is not True:
                    issues.append(f"{journey_id}: coverage.{step} must be true")

        ios_refs = journey.get("iosRefs")
        if not isinstance(ios_refs, list) or not ios_refs:
            issues.append(f"{journey_id}: iosRefs must be a non-empty list")
        else:
            for ref in ios_refs:
                if not isinstance(ref, str):
                    issues.append(f"{journey_id}: iosRefs entries must be strings")
                    continue
                if not IOS_REF_RE.match(ref):
                    issues.append(f"{journey_id}: invalid iOS ref path: {ref}")
                    continue
                if not (repo_root / ref).is_file():
                    issues.append(f"{journey_id}: iOS ref file not found: {ref}")

        android_refs = journey.get("androidPresentationRefs")
        if not isinstance(android_refs, list) or not android_refs:
            issues.append(f"{journey_id}: androidPresentationRefs must be a non-empty list")
        else:
            for ref in android_refs:
                if not isinstance(ref, str):
                    issues.append(f"{journey_id}: androidPresentationRefs entries must be strings")
                    continue
                if not ANDROID_REF_RE.match(ref):
                    issues.append(
                        f"{journey_id}: invalid Android presentation ref path (expected presentation/**): {ref}"
                    )
                    continue
                if not (repo_root / ref).is_file():
                    issues.append(f"{journey_id}: Android ref file not found: {ref}")

    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--matrix",
        default="docs/testing/navigation-parity-matrix.v1.json",
        help="Path to navigation parity matrix JSON file",
    )
    parser.add_argument(
        "--report-out",
        default="artifacts/navigation/android-parity-matrix-report.json",
        help="Output path for machine-readable report",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    matrix_path = repo_root / args.matrix
    if not matrix_path.is_file():
        print(f"error: matrix file not found: {matrix_path}")
        return 2

    matrix = load_json(matrix_path)
    issues = validate_matrix(matrix, repo_root)
    report = {
        "matrixPath": args.matrix,
        "requiredJourneyIds": REQUIRED_JOURNEY_IDS,
        "requiredSteps": REQUIRED_STEPS,
        "passed": len(issues) == 0,
        "issueCount": len(issues),
        "issues": issues,
    }

    report_path = repo_root / args.report_out
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("android parity matrix validation failed:")
        for issue in issues:
            print(f"- {issue}")
        print(f"report: {report_path}")
        return 1

    print("android parity matrix validation passed")
    print(f"report: {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
