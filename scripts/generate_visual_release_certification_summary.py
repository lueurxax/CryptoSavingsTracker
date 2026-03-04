#!/usr/bin/env python3
"""Generate human-readable release certification summary from JSON artifacts."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

DEFAULT_CERT = "artifacts/visual-system/release-certification-report.json"
DEFAULT_FRESH = "artifacts/visual-system/release-certification-freshness-report.json"
DEFAULT_OUT = "artifacts/visual-system/release-certification-summary.md"
DEFAULT_RUNTIME_TEST_RESULTS = "artifacts/visual-system/runtime-accessibility-test-results.json"


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cert", default=DEFAULT_CERT)
    parser.add_argument("--freshness", default=DEFAULT_FRESH)
    parser.add_argument("--runtime-test-results", default=DEFAULT_RUNTIME_TEST_RESULTS)
    parser.add_argument(
        "--required-test-mode",
        choices=("smoke", "full"),
        default="full",
    )
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    cert_path = repo_root / args.cert
    fresh_path = repo_root / args.freshness
    runtime_test_results_path = repo_root / args.runtime_test_results

    if not cert_path.exists():
        print(f"error: certification report not found: {cert_path}")
        return 2
    if not fresh_path.exists():
        print(f"error: freshness report not found: {fresh_path}")
        return 2

    cert = load_json(cert_path)
    fresh = load_json(fresh_path)

    release_certifiable = bool(cert.get("releaseCertifiable"))
    freshness_passed = bool(fresh.get("passed"))
    failed_steps = cert.get("failedSteps", [])
    failed_reports = cert.get("failedReports", [])
    generated_at = cert.get("generatedAt", "unknown")
    source_commit = cert.get("sourceCommitSha", "unknown")
    source_run = cert.get("sourceCiRunId", "unknown")
    age_hours = fresh.get("summary", {}).get("ageHours", "unknown")
    evidence_quality = {
        "available": False,
        "testMode": "unknown",
        "requiredTestMode": args.required_test_mode,
        "sourceMode": "unknown",
        "executedTests": {"ios": 0, "android": 0, "total": 0},
        "suiteIds": {"ios": "unknown", "android": "unknown"},
        "policyPassed": False,
    }
    if runtime_test_results_path.exists():
        runtime_payload = load_json(runtime_test_results_path)
        evidence_quality["available"] = True
        evidence_quality["testMode"] = str(runtime_payload.get("testMode", "unknown"))
        evidence_quality["requiredTestMode"] = str(
            runtime_payload.get("requiredTestMode", args.required_test_mode)
        )
        evidence_quality["sourceMode"] = str(runtime_payload.get("sourceMode", "unknown"))
        executed = runtime_payload.get("executedTests", {})
        if isinstance(executed, dict):
            for key in ("ios", "android", "total"):
                value = executed.get(key)
                if isinstance(value, int):
                    evidence_quality["executedTests"][key] = value
        platforms = runtime_payload.get("platforms", {})
        if isinstance(platforms, dict):
            for key in ("ios", "android"):
                section = platforms.get(key, {})
                if isinstance(section, dict):
                    suite_id = str(section.get("suiteId", "")).strip()
                    if suite_id:
                        evidence_quality["suiteIds"][key] = suite_id
        evidence_quality["policyPassed"] = (
            evidence_quality["testMode"] == evidence_quality["requiredTestMode"]
            and evidence_quality["sourceMode"] == "test-run"
            and evidence_quality["executedTests"]["total"] > 0
        )

    status_line = "PASS" if (release_certifiable and freshness_passed) else "FAIL"

    lines = [
        "# Visual Release Certification Summary",
        "",
        f"- Overall status: **{status_line}**",
        f"- Release certifiable: `{str(release_certifiable).lower()}`",
        f"- Freshness passed: `{str(freshness_passed).lower()}`",
        f"- Generated at: `{generated_at}`",
        f"- Source commit: `{source_commit}`",
        f"- Source CI run: `{source_run}`",
        f"- Freshness age hours: `{age_hours}`",
        "",
        "## Failed Steps",
    ]

    if failed_steps:
        lines.extend([f"- `{step}`" for step in failed_steps])
    else:
        lines.append("- none")

    lines.append("")
    lines.append("## Failed Reports")
    if failed_reports:
        lines.extend([f"- `{report}`" for report in failed_reports])
    else:
        lines.append("- none")

    lines.append("")
    lines.append("## Evidence Quality")
    if evidence_quality["available"]:
        lines.extend(
            [
                f"- Policy passed: `{str(evidence_quality['policyPassed']).lower()}`",
                f"- Test mode: `{evidence_quality['testMode']}`",
                f"- Required test mode: `{evidence_quality['requiredTestMode']}`",
                f"- Source mode: `{evidence_quality['sourceMode']}`",
                (
                    "- Executed tests (ios/android/total): "
                    f"`{evidence_quality['executedTests']['ios']}/"
                    f"{evidence_quality['executedTests']['android']}/"
                    f"{evidence_quality['executedTests']['total']}`"
                ),
                (
                    "- Suite IDs (ios/android): "
                    f"`{evidence_quality['suiteIds']['ios']}` / "
                    f"`{evidence_quality['suiteIds']['android']}`"
                ),
                f"- Runtime test-results artifact: `{args.runtime_test_results}`",
            ]
        )
    else:
        lines.append("- runtime test-results artifact not found")

    output_path = repo_root / args.out
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"release certification summary written: {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
