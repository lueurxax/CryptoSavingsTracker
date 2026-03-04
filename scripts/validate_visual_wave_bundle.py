#!/usr/bin/env python3
"""Validate visual-system wave artifact bundle completeness and quality."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wave", required=True)
    parser.add_argument("--wave-dir", default="")
    parser.add_argument(
        "--require-release-certifiable",
        action="store_true",
        help="Require release-certification-report.json to set releaseCertifiable=true",
    )
    parser.add_argument(
        "--report-out",
        default="artifacts/visual-system/wave-bundle-validation-report.json",
    )
    args = parser.parse_args()

    if not re.fullmatch(r"wave[0-9]+", args.wave):
        print(f"error: invalid --wave value: {args.wave}")
        return 2

    repo_root = Path(__file__).resolve().parent.parent
    wave_dir = repo_root / (args.wave_dir or f"docs/release/visual-system/{args.wave}")
    if not wave_dir.exists():
        print(f"error: wave directory not found: {wave_dir}")
        return 2

    required_wave_files = [
        "token-parity-report.md",
        "state-coverage-report.md",
        "snapshot-diff-summary.md",
        "accessibility-report.md",
        "ux-metrics-report.md",
        "performance-report.md",
        "rollback-drill-report.md",
        "runtime-accessibility-assertions.json",
        "ux-metrics-report.json",
        "release-certification-report.json",
        "release-certification-summary.md",
        "runtime-accessibility-test-results.json",
        "performance-report.json",
        "rollback-drill-report.json",
    ]
    required_global_files = [
        "docs/screenshots/review-visual-system-unification-r4/manifest.md",
        "docs/screenshots/review-visual-system-unification-r4/production/manifest.v1.json",
    ]

    issues: list[str] = []
    for rel in required_wave_files:
        if not (wave_dir / rel).is_file():
            issues.append(f"missing required wave artifact: {wave_dir / rel}")
    for rel in required_global_files:
        if not (repo_root / rel).is_file():
            issues.append(f"missing required global artifact: {repo_root / rel}")

    release_cert_path = wave_dir / "release-certification-report.json"
    runtime_results_path = wave_dir / "runtime-accessibility-test-results.json"
    runtime_assertions_path = wave_dir / "runtime-accessibility-assertions.json"
    production_manifest_path = (
        repo_root / "docs/screenshots/review-visual-system-unification-r4/production/manifest.v1.json"
    )

    if release_cert_path.exists():
        cert_payload = load_json(release_cert_path)
        if args.require_release_certifiable and cert_payload.get("releaseCertifiable") is not True:
            issues.append("release-certification-report.json must set releaseCertifiable=true")
    if runtime_results_path.exists():
        runtime_payload = load_json(runtime_results_path)
        if runtime_payload.get("testMode") != "full":
            issues.append("runtime-accessibility-test-results.json must set testMode=full")
        if runtime_payload.get("requiredTestMode") != "full":
            issues.append("runtime-accessibility-test-results.json must set requiredTestMode=full")
        if runtime_payload.get("sourceMode") != "test-run":
            issues.append("runtime-accessibility-test-results.json must set sourceMode=test-run")
        executed = runtime_payload.get("executedTests", {})
        total = executed.get("total") if isinstance(executed, dict) else 0
        if not isinstance(total, int) or total <= 0:
            issues.append("runtime-accessibility-test-results.json executedTests.total must be > 0")
    if runtime_assertions_path.exists():
        assertions_payload = load_json(runtime_assertions_path)
        source = assertions_payload.get("source", {})
        if not isinstance(source, dict):
            issues.append("runtime-accessibility-assertions.json source must be object")
        else:
            test_results_path = str(source.get("testResultsPath", "")).strip()
            if not test_results_path:
                issues.append(
                    "runtime-accessibility-assertions.json source.testResultsPath is required"
                )
            if source.get("testMode") != "full":
                issues.append("runtime-accessibility-assertions.json source.testMode must be full")
            if source.get("requiredTestMode") != "full":
                issues.append(
                    "runtime-accessibility-assertions.json source.requiredTestMode must be full"
                )

    if production_manifest_path.exists():
        production_manifest = load_json(production_manifest_path)
        if not str(production_manifest.get("evidenceCommitSha", "")).strip():
            issues.append("production manifest missing evidenceCommitSha")
        if not str(production_manifest.get("capturedAt", "")).strip():
            issues.append("production manifest missing capturedAt")

    validator_runs: list[dict[str, Any]] = []
    validators = [
        (
            "uxMetrics",
            [
                sys.executable,
                "scripts/validate_visual_ux_metrics.py",
                "--report",
                str(wave_dir / "ux-metrics-report.json"),
                "--report-out",
                "artifacts/visual-system/ux-metrics-validation-wave-bundle.json",
            ],
        ),
        (
            "performanceBudget",
            [
                sys.executable,
                "scripts/validate_visual_performance_report.py",
                "--report",
                str(wave_dir / "performance-report.json"),
                "--report-out",
                "artifacts/visual-system/performance-report-validation-wave-bundle.json",
            ],
        ),
        (
            "rollbackDrill",
            [
                sys.executable,
                "scripts/validate_visual_rollback_drill_report.py",
                "--report",
                str(wave_dir / "rollback-drill-report.json"),
                "--report-out",
                "artifacts/visual-system/rollback-drill-validation-wave-bundle.json",
            ],
        ),
    ]
    for name, cmd in validators:
        result = subprocess.run(
            cmd,
            cwd=repo_root,
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            issues.append(f"{name} validator failed")
        validator_runs.append(
            {
                "name": name,
                "returnCode": result.returncode,
                "stdout": result.stdout.strip().splitlines(),
                "stderr": result.stderr.strip().splitlines(),
            }
        )

    try:
        wave_dir_display = str(wave_dir.relative_to(repo_root))
    except ValueError:
        wave_dir_display = str(wave_dir)

    report = {
        "wave": args.wave,
        "waveDir": wave_dir_display,
        "passed": len(issues) == 0,
        "issueCount": len(issues),
        "requiredWaveFiles": required_wave_files,
        "requiredGlobalFiles": required_global_files,
        "validatorRuns": validator_runs,
        "issues": issues,
    }

    out_path = repo_root / args.report_out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("visual wave bundle validation failed:")
        for issue in issues:
            print(f"- {issue}")
        print(f"report: {out_path}")
        return 1

    print("visual wave bundle validation passed")
    print(f"report: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
