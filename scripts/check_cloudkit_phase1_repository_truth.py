#!/usr/bin/env python3
"""Validate CloudKit Phase 1 repository-truth wiring."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

REQUIRED_FILES = [
    "docs/CLOUDKIT_MIGRATION_PLAN.md",
    "docs/CLOUDKIT_PHASE1_WORKTREE_EXECUTION_PLAN.md",
    "docs/proposals/cloudkit_qr_multipeer_sync_proposal.md",
    "docs/design/ADR-CK-CUTOVER-001.md",
    "docs/testing/cloudkit-phase1-evidence-checklist.md",
    "docs/runbooks/cloudkit-cutover-release-gate.md",
    "docs/release/cloudkit/templates/README.md",
]

LINK_REQUIREMENTS = {
    "docs/README.md": [
        "CLOUDKIT_MIGRATION_PLAN.md",
        "CLOUDKIT_PHASE1_WORKTREE_EXECUTION_PLAN.md",
        "design/ADR-CK-CUTOVER-001.md",
        "testing/cloudkit-phase1-evidence-checklist.md",
        "runbooks/cloudkit-cutover-release-gate.md",
    ],
    "docs/ARCHITECTURE.md": [
        "ADR-CK-CUTOVER-001",
        "CloudKit Cutover Release Gate Runbook",
        "CloudKit Phase 1 Evidence Checklist",
    ],
    "docs/CLOUDKIT_MIGRATION_PLAN.md": [
        "ADR-CK-CUTOVER-001",
        "testing/cloudkit-phase1-evidence-checklist.md",
        "runbooks/cloudkit-cutover-release-gate.md",
        "cloud-primary-staging",
        "relaunch",
        "cloudkit-migration-gates.yml",
    ],
    "docs/proposals/cloudkit_qr_multipeer_sync_proposal.md": [
        "CloudKit-disabled staging store",
        "cloudKitPrimary",
        "app relaunch",
        "Phase 1.5",
    ],
    "docs/testing/cloudkit-phase1-evidence-checklist.md": [
        "backup -> diagnostics/repair -> staging copy -> validation -> promotion -> persist mode -> relaunch",
        "docs/release/cloudkit/<release-id>/",
    ],
    "docs/runbooks/cloudkit-cutover-release-gate.md": [
        "ADR-CK-CUTOVER-001",
        "docs/release/cloudkit/<release-id>/",
        "Phase 1.5 Readiness Gate",
    ],
    "docs/release/cloudkit/templates/README.md": [
        "go-no-go.md",
        "cloudkit-cutover-test-report.md",
        "device-migration-log.txt",
        "diagnostics-report.json",
        "cleanup-verification.md",
    ],
}


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--repo-root",
        default=None,
        help="Override repository root for fixture/testing use",
    )
    parser.add_argument(
        "--report-out",
        default="artifacts/cloudkit/repository-truth-report.json",
        help="Machine-readable report path",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve() if args.repo_root else Path(__file__).resolve().parent.parent
    issues: list[str] = []
    checks: list[dict[str, Any]] = []

    for rel in REQUIRED_FILES:
        path = repo_root / rel
        exists = path.is_file()
        checks.append({"type": "required_file", "path": rel, "passed": exists})
        if not exists:
            issues.append(f"missing required file: {rel}")

    for rel, snippets in LINK_REQUIREMENTS.items():
        path = repo_root / rel
        if not path.is_file():
            continue
        text = load_text(path)
        missing = [snippet for snippet in snippets if snippet not in text]
        checks.append(
            {
                "type": "link_wiring",
                "path": rel,
                "passed": not missing,
                "requiredSnippets": snippets,
                "missingSnippets": missing,
            }
        )
        for snippet in missing:
            issues.append(f"{rel}: missing required snippet/reference: {snippet}")

    report = {
        "passed": len(issues) == 0,
        "issueCount": len(issues),
        "issues": issues,
        "checks": checks,
    }

    out_path = repo_root / args.report_out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("cloudkit phase1 repository-truth check failed:")
        for issue in issues:
            print(f"- {issue}")
        print(f"report: {out_path}")
        return 1

    print("cloudkit phase1 repository-truth check passed")
    print(f"report: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
