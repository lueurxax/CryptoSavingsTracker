#!/usr/bin/env python3
"""Publish visual-system release artifacts into wave bundle and latest mirror."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wave", required=True)
    parser.add_argument("--artifacts-dir", default="artifacts/visual-system")
    parser.add_argument("--wave-dir", default="")
    parser.add_argument("--latest-dir", default="docs/release/visual-system/latest")
    args = parser.parse_args()

    if not args.wave.startswith("wave"):
        print(f"error: invalid wave '{args.wave}'")
        return 2

    repo_root = Path(__file__).resolve().parent.parent
    artifacts_dir = repo_root / args.artifacts_dir
    wave_dir = repo_root / (args.wave_dir or f"docs/release/visual-system/{args.wave}")
    latest_dir = repo_root / args.latest_dir

    if not artifacts_dir.exists():
        print(f"error: artifacts directory not found: {artifacts_dir}")
        return 2

    artifact_files = [
        "release-certification-report.json",
        "release-certification-freshness-report.json",
        "release-certification-summary.md",
        "snapshot-report.json",
        "accessibility-report.json",
        "ux-metrics-report.json",
        "ux-metrics-validation-report.json",
        "variant-expiry-report.json",
        "state-matrix-release.json",
        "literal-baseline-burndown-report.json",
        "runtime-accessibility-test-results.json",
        "runtime-accessibility-assertions.json",
        "performance-report.json",
        "performance-report-validation.json",
        "rollback-drill-report.json",
        "rollback-drill-validation.json",
        "wave-bundle-validation-report.json",
    ]

    issues: list[str] = []
    for name in artifact_files:
        source = artifacts_dir / name
        if not source.exists():
            issues.append(f"missing source artifact: {source}")
            continue
        wave_target = wave_dir / name
        latest_target = latest_dir / name
        wave_target.parent.mkdir(parents=True, exist_ok=True)
        latest_target.parent.mkdir(parents=True, exist_ok=True)
        wave_target.write_bytes(source.read_bytes())
        latest_target.write_bytes(source.read_bytes())

    if issues:
        print("error: publish failed due to missing artifacts:")
        for issue in issues:
            print(f"- {issue}")
        return 1

    # Generate wave bundle markdown evidence pack from machine artifacts.
    token_parity_result = subprocess.run(
        [sys.executable, "scripts/check_visual_token_parity.py"],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
    )
    parity_status = "passed" if token_parity_result.returncode == 0 else "failed"
    parity_lines = [
        f"# {args.wave} Token Parity Report",
        "",
        f"- Generated at: `{datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')}`",
        f"- Status: `{parity_status}`",
        "",
        "## Command",
        "",
        "`python3 scripts/check_visual_token_parity.py`",
        "",
        "## Output",
        "",
        "```text",
        token_parity_result.stdout.strip() or "(no stdout)",
        "```",
    ]
    if token_parity_result.stderr.strip():
        parity_lines.extend(
            [
                "",
                "## STDERR",
                "",
                "```text",
                token_parity_result.stderr.strip(),
                "```",
            ]
        )
    write_text(wave_dir / "token-parity-report.md", "\n".join(parity_lines))

    state_report = load_json(artifacts_dir / "state-matrix-release.json")
    write_text(
        wave_dir / "state-coverage-report.md",
        "\n".join(
            [
                f"# {args.wave} State Coverage Report",
                "",
                f"- Passed: `{str(state_report.get('passed', False)).lower()}`",
                f"- Issue count: `{state_report.get('issueCount', 'unknown')}`",
                f"- Required states: `{', '.join(state_report.get('requiredStates', []))}`",
                (
                    "- Release components: "
                    f"`{', '.join(state_report.get('releaseBlockingComponents', []))}`"
                ),
            ]
        ),
    )

    snapshot_report = load_json(artifacts_dir / "snapshot-report.json")
    write_text(
        wave_dir / "snapshot-diff-summary.md",
        "\n".join(
            [
                f"# {args.wave} Snapshot Diff Summary",
                "",
                f"- Passed: `{str(snapshot_report.get('passed', False)).lower()}`",
                f"- Issue count: `{snapshot_report.get('issueCount', 'unknown')}`",
                (
                    "- Baseline changed artifacts: "
                    f"`{snapshot_report.get('baselineDiffSummary', {}).get('changedArtifacts', 'unknown')}`"
                ),
                (
                    "- Duplicate ratio iOS: "
                    f"`{snapshot_report.get('duplicateSummary', {}).get('platforms', {}).get('ios', {}).get('duplicateRatio', 'unknown')}`"
                ),
                (
                    "- Duplicate ratio Android: "
                    f"`{snapshot_report.get('duplicateSummary', {}).get('platforms', {}).get('android', {}).get('duplicateRatio', 'unknown')}`"
                ),
            ]
        ),
    )

    accessibility_report = load_json(artifacts_dir / "accessibility-report.json")
    write_text(
        wave_dir / "accessibility-report.md",
        "\n".join(
            [
                f"# {args.wave} Accessibility Report",
                "",
                f"- Passed: `{str(accessibility_report.get('passed', False)).lower()}`",
                f"- Issue count: `{accessibility_report.get('issueCount', 'unknown')}`",
                (
                    "- Runtime test mode: "
                    f"`{accessibility_report.get('runtimeAssertionsSummary', {}).get('source', {}).get('testMode', 'unknown')}`"
                ),
                (
                    "- Runtime required mode: "
                    f"`{accessibility_report.get('runtimeAssertionsSummary', {}).get('source', {}).get('requiredTestMode', 'unknown')}`"
                ),
            ]
        ),
    )

    ux_report = load_json(wave_dir / "ux-metrics-report.json")
    ux_validation = load_json(artifacts_dir / "ux-metrics-validation-report.json")
    write_text(
        wave_dir / "ux-metrics-report.md",
        "\n".join(
            [
                f"# {args.wave} UX Metrics Report",
                "",
                f"- Evaluated at: `{ux_report.get('evaluatedAt', 'unknown')}`",
                f"- Validation passed: `{str(ux_validation.get('passed', False)).lower()}`",
                (
                    "- Participants / tasks: "
                    f"`{ux_report.get('sample', {}).get('participants', 'unknown')}` / "
                    f"`{ux_report.get('sample', {}).get('scenarioTasks', 'unknown')}`"
                ),
            ]
        ),
    )

    performance_report = load_json(wave_dir / "performance-report.json")
    write_text(
        wave_dir / "performance-report.md",
        "\n".join(
            [
                f"# {args.wave} Performance Report",
                "",
                f"- Evaluated at: `{performance_report.get('evaluatedAt', 'unknown')}`",
                (
                    "- P95 regression (%): "
                    f"`{performance_report.get('deltas', {}).get('p95RegressionPercent', 'unknown')}`"
                ),
                (
                    "- Jank delta (pp): "
                    f"`{performance_report.get('deltas', {}).get('jankDeltaPercentagePoints', 'unknown')}`"
                ),
            ]
        ),
    )

    rollback_report = load_json(wave_dir / "rollback-drill-report.json")
    write_text(
        wave_dir / "rollback-drill-report.md",
        "\n".join(
            [
                f"# {args.wave} Rollback Drill Report",
                "",
                f"- Executed at: `{rollback_report.get('executedAt', 'unknown')}`",
                (
                    "- SLA max/actual (business days): "
                    f"`{rollback_report.get('slaBusinessDaysMax', 'unknown')}` / "
                    f"`{rollback_report.get('slaBusinessDaysActual', 'unknown')}`"
                ),
                (
                    "- Telemetry markers: "
                    f"`{rollback_report.get('telemetryMarkers', {}).get('triggeredEvent', 'unknown')}` / "
                    f"`{rollback_report.get('telemetryMarkers', {}).get('completedEvent', 'unknown')}`"
                ),
            ]
        ),
    )

    # Keep latest as mirror of wave outputs for key user-facing markdown files.
    mirror_markdown = [
        "token-parity-report.md",
        "state-coverage-report.md",
        "snapshot-diff-summary.md",
        "accessibility-report.md",
        "ux-metrics-report.md",
        "performance-report.md",
        "rollback-drill-report.md",
    ]
    for name in mirror_markdown:
        (latest_dir / name).write_bytes((wave_dir / name).read_bytes())

    print(f"published wave bundle: {wave_dir}")
    print(f"updated latest mirror: {latest_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
