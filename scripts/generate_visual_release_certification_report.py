#!/usr/bin/env python3
"""Build consolidated visual release certification report."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REQUIRED_STEP_KEYS = (
    "validateTokens",
    "tokenParity",
    "variantExpiry",
    "stateMatrix",
    "iosLiteralGuard",
    "androidLiteralGuard",
    "literalBaselineBudget",
    "snapshot",
    "runtimeAccessibilityTests",
    "accessibility",
    "uxMetrics",
    "performanceBudget",
    "rollbackDrill",
    "waveBundle",
    "certificationFreshness",
)


def resolve_source_commit(cli_value: str) -> str:
    value = cli_value.strip().lower()
    if value:
        return value

    env_sha = os.getenv("GITHUB_SHA", "").strip().lower()
    if env_sha:
        return env_sha

    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode == 0:
        return result.stdout.strip().lower()
    return ""


def resolve_source_run_id(cli_value: str) -> str:
    value = cli_value.strip()
    if value:
        return value

    run_id = os.getenv("GITHUB_RUN_ID", "").strip()
    run_attempt = os.getenv("GITHUB_RUN_ATTEMPT", "").strip()
    if run_id:
        if run_attempt:
            return f"github-run-{run_id}:attempt-{run_attempt}"
        return f"github-run-{run_id}"
    return "local-run"


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def parse_step_status(pairs: list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for pair in pairs:
        if "=" not in pair:
            raise ValueError(f"invalid --step-status value: '{pair}' (expected key=passed|failed)")
        key, value = pair.split("=", 1)
        key = key.strip()
        value = value.strip().lower()
        if key not in REQUIRED_STEP_KEYS:
            raise ValueError(f"unknown step key: '{key}'")
        if value not in {"passed", "failed"}:
            raise ValueError(f"invalid step status '{value}' for '{key}'")
        result[key] = value

    missing = [key for key in REQUIRED_STEP_KEYS if key not in result]
    if missing:
        raise ValueError(f"missing step statuses: {', '.join(missing)}")
    return result


def report_passed(path: Path, field: str = "passed") -> tuple[bool, str]:
    if not path.exists():
        return False, f"missing report: {path}"
    try:
        payload = load_json(path)
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid report: {path} ({exc})"

    value = payload.get(field)
    if value is True:
        return True, "ok"
    if value is False:
        issue_count = payload.get("issueCount")
        suffix = f" issueCount={issue_count}" if issue_count is not None else ""
        return False, f"{path} indicates failed{suffix}"
    return False, f"{path} missing boolean field '{field}'"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--step-status", action="append", default=[])
    parser.add_argument(
        "--snapshot-report",
        default="artifacts/visual-system/snapshot-report.json",
    )
    parser.add_argument(
        "--accessibility-report",
        default="artifacts/visual-system/accessibility-report.json",
    )
    parser.add_argument(
        "--ux-report",
        default="artifacts/visual-system/ux-metrics-validation-report.json",
    )
    parser.add_argument(
        "--variant-expiry-report",
        default="artifacts/visual-system/variant-expiry-report.json",
    )
    parser.add_argument(
        "--state-matrix-report",
        default="artifacts/visual-system/state-matrix-release.json",
    )
    parser.add_argument(
        "--report-out",
        default="artifacts/visual-system/release-certification-report.json",
    )
    parser.add_argument(
        "--performance-report",
        default="artifacts/visual-system/performance-report-validation.json",
    )
    parser.add_argument(
        "--rollback-drill-report",
        default="artifacts/visual-system/rollback-drill-validation.json",
    )
    parser.add_argument(
        "--wave-bundle-report",
        default="artifacts/visual-system/wave-bundle-validation-report.json",
    )
    parser.add_argument("--source-commit", default="")
    parser.add_argument("--source-ci-run-id", default="")
    parser.add_argument("--generated-at", default="")
    args = parser.parse_args()

    try:
        step_status = parse_step_status(args.step_status)
    except ValueError as exc:
        print(f"error: {exc}")
        return 2

    snapshot_ok, snapshot_msg = report_passed(Path(args.snapshot_report))
    accessibility_ok, accessibility_msg = report_passed(Path(args.accessibility_report))
    ux_ok, ux_msg = report_passed(Path(args.ux_report))
    variant_ok, variant_msg = report_passed(Path(args.variant_expiry_report))
    state_matrix_ok, state_matrix_msg = report_passed(Path(args.state_matrix_report))
    performance_ok, performance_msg = report_passed(Path(args.performance_report))
    rollback_ok, rollback_msg = report_passed(Path(args.rollback_drill_report))
    wave_bundle_ok, wave_bundle_msg = report_passed(Path(args.wave_bundle_report))

    checks = {
        "stepStatus": {key: (value == "passed") for key, value in step_status.items()},
        "reports": {
            "snapshot": {"passed": snapshot_ok, "message": snapshot_msg},
            "accessibility": {"passed": accessibility_ok, "message": accessibility_msg},
            "uxMetrics": {"passed": ux_ok, "message": ux_msg},
            "variantExpiry": {"passed": variant_ok, "message": variant_msg},
            "stateMatrix": {"passed": state_matrix_ok, "message": state_matrix_msg},
            "performanceBudget": {"passed": performance_ok, "message": performance_msg},
            "rollbackDrill": {"passed": rollback_ok, "message": rollback_msg},
            "waveBundle": {"passed": wave_bundle_ok, "message": wave_bundle_msg},
        },
    }

    failed_steps = [key for key, passed in checks["stepStatus"].items() if not passed]
    failed_reports = [
        name for name, report in checks["reports"].items() if not report["passed"]
    ]

    source_commit_sha = resolve_source_commit(args.source_commit)
    if not re.fullmatch(r"[0-9a-f]{7,40}", source_commit_sha):
        print("error: unable to resolve valid source commit SHA")
        return 2
    source_ci_run_id = resolve_source_run_id(args.source_ci_run_id)
    generated_at = args.generated_at.strip() or datetime.now(timezone.utc).isoformat().replace(
        "+00:00", "Z"
    )

    release_certifiable = not failed_steps and not failed_reports

    output = {
        "reportVersion": "v1",
        "generatedAt": generated_at,
        "sourceCommitSha": source_commit_sha,
        "sourceCiRunId": source_ci_run_id,
        "releaseCertifiable": release_certifiable,
        "failedSteps": failed_steps,
        "failedReports": failed_reports,
        "checks": checks,
    }

    report_out = Path(args.report_out)
    report_out.parent.mkdir(parents=True, exist_ok=True)
    report_out.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")

    if release_certifiable:
        print("visual release certification passed")
        print(f"report: {report_out}")
        return 0

    print("visual release certification failed")
    if failed_steps:
        print(f"- failed steps: {', '.join(failed_steps)}")
    if failed_reports:
        print(f"- failed reports: {', '.join(failed_reports)}")
    print(f"report: {report_out}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
