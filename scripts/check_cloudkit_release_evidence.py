#!/usr/bin/env python3
"""Validate CloudKit Phase 1 release evidence package."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

REQUIRED_RELEASE_FILES = [
    "README.md",
    "go-no-go.md",
    "cloudkit-cutover-test-report.md",
    "device-migration-log.txt",
    "diagnostics-report.json",
    "cleanup-verification.md",
]

COMMIT_SHA_PATTERN = re.compile(r"\b[0-9a-f]{7,40}\b", re.IGNORECASE)


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(load_text(path))


def validate_release_files(release_dir: Path) -> list[str]:
    issues: list[str] = []
    for rel in REQUIRED_RELEASE_FILES:
        if not (release_dir / rel).is_file():
            issues.append(f"missing required release artifact: {release_dir / rel}")
    return issues


def validate_readme(path: Path) -> list[str]:
    text = load_text(path)
    issues: list[str] = []
    for snippet in [
        "ADR-CK-CUTOVER-001",
        "CloudKit Phase 1 Evidence Checklist",
        "CloudKit Cutover Release Gate Runbook",
    ]:
        if snippet not in text:
            issues.append(f"README.md: missing reference {snippet}")
    return issues


def validate_go_no_go(path: Path) -> list[str]:
    text = load_text(path)
    issues: list[str] = []
    for snippet in [
        "Preflight fail-closed is confirmed",
        "Staging copy + validation + promotion flow is confirmed",
        "Relaunch activates cloud runtime deterministically",
        "No sqlite API-violation warnings",
    ]:
        if snippet not in text:
            issues.append(f"go-no-go.md: missing checklist item {snippet}")
    if not COMMIT_SHA_PATTERN.search(text):
        issues.append("go-no-go.md: missing commit SHA reference")
    return issues


def validate_device_log(path: Path) -> list[str]:
    text = load_text(path)
    issues: list[str] = []
    for snippet in [
        "Validation passed: all",
        "CloudKit migration completed successfully",
    ]:
        if snippet not in text:
            issues.append(f"device-migration-log.txt: missing runtime evidence {snippet}")
    return issues


def validate_cleanup_report(path: Path) -> list[str]:
    text = load_text(path)
    issues: list[str] = []
    for snippet in [
        "cloud-primary",
        "cloud-primary-staging",
        "No sqlite API-violation warnings",
    ]:
        if snippet not in text:
            issues.append(f"cleanup-verification.md: missing cleanup evidence {snippet}")
    return issues


def validate_diagnostics_report(path: Path) -> list[str]:
    report = load_json(path)
    issues: list[str] = []
    if not isinstance(report.get("isReady"), bool):
        issues.append("diagnostics-report.json: isReady must be boolean")
    entity_counts = report.get("entityCounts")
    if not isinstance(entity_counts, list) or not entity_counts:
        issues.append("diagnostics-report.json: entityCounts must be non-empty list")
    allocation_history = report.get("allocationHistory")
    if not isinstance(allocation_history, dict):
        issues.append("diagnostics-report.json: allocationHistory must be object")
    blocker_summary = report.get("blockerSummary")
    if not isinstance(blocker_summary, list):
        issues.append("diagnostics-report.json: blockerSummary must be list")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--release-dir",
        default="docs/release/cloudkit/latest",
        help="Path to CloudKit release evidence package",
    )
    parser.add_argument(
        "--repo-root",
        default=None,
        help="Override repository root for fixture/testing use",
    )
    parser.add_argument(
        "--report-out",
        default="artifacts/cloudkit/release-evidence-report.json",
        help="Output path for machine-readable report",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve() if args.repo_root else Path(__file__).resolve().parent.parent
    release_dir = repo_root / args.release_dir
    issues: list[str] = []

    if not release_dir.is_dir():
        issues.append(f"release evidence directory does not exist: {release_dir}")
    else:
        issues.extend(validate_release_files(release_dir))
        if not issues:
            issues.extend(validate_readme(release_dir / "README.md"))
            issues.extend(validate_go_no_go(release_dir / "go-no-go.md"))
            issues.extend(validate_device_log(release_dir / "device-migration-log.txt"))
            issues.extend(validate_cleanup_report(release_dir / "cleanup-verification.md"))
            issues.extend(validate_diagnostics_report(release_dir / "diagnostics-report.json"))

    report = {
        "passed": len(issues) == 0,
        "releaseDir": args.release_dir,
        "issueCount": len(issues),
        "issues": issues,
    }

    out_path = repo_root / args.report_out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("cloudkit release-evidence check failed:")
        for issue in issues:
            print(f"- {issue}")
        print(f"report: {out_path}")
        return 1

    print("cloudkit release-evidence check passed")
    print(f"report: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
