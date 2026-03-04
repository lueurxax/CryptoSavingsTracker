#!/usr/bin/env python3
"""Validate freshness and commit provenance of release certification report."""

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

DEFAULT_REPORT = "artifacts/visual-system/release-certification-report.json"
DEFAULT_REPORT_OUT = "artifacts/visual-system/release-certification-freshness-report.json"


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def resolve_expected_commit(cli_value: str) -> str:
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


def parse_iso8601(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", default=DEFAULT_REPORT)
    parser.add_argument("--expected-commit", default="")
    parser.add_argument("--max-age-hours", type=float, default=24.0)
    parser.add_argument("--report-out", default=DEFAULT_REPORT_OUT)
    args = parser.parse_args()

    report_path = Path(args.report)
    issues: list[str] = []
    summary: dict[str, Any] = {
        "reportPath": str(report_path),
        "expectedCommit": "",
        "sourceCommitSha": "",
        "generatedAt": "",
        "ageHours": None,
        "maxAgeHours": args.max_age_hours,
    }

    if not report_path.exists():
        issues.append(f"release certification report not found: {report_path}")
    else:
        try:
            payload = load_json(report_path)
        except (json.JSONDecodeError, OSError) as exc:
            issues.append(f"release certification report is invalid JSON: {exc}")
            payload = {}

        source_commit = str(payload.get("sourceCommitSha", "")).lower()
        generated_at = str(payload.get("generatedAt", ""))
        summary["sourceCommitSha"] = source_commit
        summary["generatedAt"] = generated_at

        if not re.fullmatch(r"[0-9a-f]{7,40}", source_commit):
            issues.append("sourceCommitSha must be a lowercase hex SHA (7-40 chars)")

        if not generated_at:
            issues.append("generatedAt is required")
        else:
            try:
                generated_dt = parse_iso8601(generated_at)
                if generated_dt.tzinfo is None:
                    issues.append("generatedAt must include timezone")
                else:
                    now_utc = datetime.now(timezone.utc)
                    age_hours = (now_utc - generated_dt).total_seconds() / 3600.0
                    summary["ageHours"] = round(age_hours, 4)
                    if age_hours < 0:
                        issues.append("generatedAt cannot be in the future")
                    elif age_hours > args.max_age_hours:
                        issues.append(
                            f"generatedAt age {age_hours:.2f}h exceeds max age {args.max_age_hours:.2f}h"
                        )
            except ValueError:
                issues.append("generatedAt must be ISO-8601 timestamp")

    expected_commit = resolve_expected_commit(args.expected_commit)
    summary["expectedCommit"] = expected_commit
    if expected_commit:
        source_commit = summary.get("sourceCommitSha", "")
        if source_commit and source_commit != expected_commit and source_commit != expected_commit[: len(source_commit)]:
            issues.append("sourceCommitSha does not match expected commit")

    passed = len(issues) == 0
    report_out = Path(args.report_out)
    report_out.parent.mkdir(parents=True, exist_ok=True)
    report_out.write_text(
        json.dumps(
            {
                "passed": passed,
                "issueCount": len(issues),
                "issues": issues,
                "summary": summary,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    if passed:
        print("release certification freshness check passed")
        print(f"report: {report_out}")
        return 0

    print("release certification freshness check failed")
    for issue in issues:
        print(f"- {issue}")
    print(f"report: {report_out}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
