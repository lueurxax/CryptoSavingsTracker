#!/usr/bin/env python3
"""Gate compact MOD-02 snapshot diff artifacts for changed modal flows."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


def run_git(repo_root: Path, args: list[str]) -> tuple[int, str, str]:
    proc = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
    )
    return proc.returncode, proc.stdout, proc.stderr


def list_changed_files(repo_root: Path, base_ref: str | None) -> set[str]:
    diff_args = ["diff", "--name-only", "--diff-filter=ACMR"]
    if base_ref:
        diff_args.append(f"{base_ref}...HEAD")
    code, out, _ = run_git(repo_root, diff_args)
    if code != 0 and base_ref:
        code, out, _ = run_git(repo_root, ["diff", "--name-only", "--diff-filter=ACMR"])
    changed = {line.strip() for line in out.splitlines() if line.strip()}

    if not base_ref:
        code, out, _ = run_git(repo_root, ["ls-files", "--others", "--exclude-standard"])
        if code == 0:
            changed.update(line.strip() for line in out.splitlines() if line.strip())

    return changed


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def path_to_rel(repo_root: Path, path_value: str) -> str:
    path = Path(path_value)
    if path.is_absolute():
        return path.relative_to(repo_root).as_posix()
    return path.as_posix()


def validate_manifest(manifest: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    file_map = manifest.get("mod02FileMap")
    scenarios = manifest.get("requiredCompactScenarios")

    if not isinstance(file_map, list) or not file_map:
        issues.append("mod02FileMap must be a non-empty list")
    if not isinstance(scenarios, list) or not scenarios:
        issues.append("requiredCompactScenarios must be a non-empty list")

    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest",
        default="docs/testing/navigation-mod02-compact-manifest.v1.json",
        help="Path to MOD-02 compact artifact manifest",
    )
    parser.add_argument(
        "--diff-report",
        default="docs/screenshots/review-navigation-presentation-r3/compact/mod02-diff-report.json",
        help="Path to compact snapshot diff report",
    )
    parser.add_argument(
        "--changed-only",
        action="store_true",
        help="Gate only when changed files intersect MOD-02 mapped files",
    )
    parser.add_argument("--base-ref", default=None, help="Git base ref for changed-only mode")
    parser.add_argument(
        "--max-diff-ratio",
        type=float,
        default=0.02,
        help="Maximum allowed diff ratio per required scenario",
    )
    parser.add_argument(
        "--report-out",
        default="artifacts/navigation/mod02-compact-gate-report.json",
        help="Output path for machine-readable report",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    manifest_path = repo_root / args.manifest
    diff_report_path = repo_root / args.diff_report
    issues: list[str] = []

    if not manifest_path.is_file():
        print(f"error: manifest file not found: {manifest_path}")
        return 2

    manifest = load_json(manifest_path)
    issues.extend(validate_manifest(manifest))

    file_map = manifest.get("mod02FileMap", [])
    scenarios = manifest.get("requiredCompactScenarios", [])

    changed_files: set[str] = set()
    if args.changed_only:
        changed_files = list_changed_files(repo_root, args.base_ref)

    impacted_entries: list[dict[str, Any]] = []
    if args.changed_only:
        impacted_entries = [
            entry
            for entry in file_map
            if isinstance(entry, dict)
            and isinstance(entry.get("path"), str)
            and entry["path"] in changed_files
        ]
    else:
        impacted_entries = [entry for entry in file_map if isinstance(entry, dict)]

    impacted_files = sorted({entry.get("path", "") for entry in impacted_entries if entry.get("path")})
    impacted_journeys = sorted(
        {
            journey
            for entry in impacted_entries
            for journey in entry.get("journeys", [])
            if isinstance(journey, str) and journey
        }
    )

    gate_required = len(impacted_entries) > 0
    required_scenarios: list[dict[str, Any]] = []
    if gate_required:
        for scenario in scenarios:
            if not isinstance(scenario, dict):
                continue
            scenario_journeys = scenario.get("journeys", [])
            if not isinstance(scenario_journeys, list):
                continue
            if impacted_journeys and not any(j in impacted_journeys for j in scenario_journeys):
                continue
            required_scenarios.append(scenario)

    if gate_required and args.changed_only:
        diff_report_rel = path_to_rel(repo_root, args.diff_report)
        if diff_report_rel not in changed_files:
            issues.append(
                f"MOD-02 flow changed but diff report was not updated in this PR: {diff_report_rel}"
            )

    for scenario in required_scenarios:
        baseline_artifact = scenario.get("baselineArtifact")
        scenario_id = scenario.get("id", "<unknown>")
        if not isinstance(baseline_artifact, str) or not baseline_artifact:
            issues.append(f"{scenario_id}: baselineArtifact is missing")
            continue
        baseline_path = repo_root / baseline_artifact
        if not baseline_path.is_file():
            issues.append(f"{scenario_id}: baseline artifact file not found: {baseline_artifact}")

    diff_report: dict[str, Any] = {}
    if gate_required:
        if not diff_report_path.is_file():
            issues.append(f"diff report file not found: {args.diff_report}")
        else:
            diff_report = load_json(diff_report_path)
            raw_scenarios = diff_report.get("scenarios")
            if not isinstance(raw_scenarios, list):
                issues.append("diff report: scenarios must be a list")
                raw_scenarios = []

            by_id: dict[str, dict[str, Any]] = {}
            for item in raw_scenarios:
                if not isinstance(item, dict):
                    continue
                scenario_id = item.get("id")
                if isinstance(scenario_id, str) and scenario_id:
                    by_id[scenario_id] = item

            for required in required_scenarios:
                scenario_id = required.get("id", "")
                if scenario_id not in by_id:
                    issues.append(f"diff report missing required scenario id: {scenario_id}")
                    continue
                found = by_id[scenario_id]
                status = found.get("status")
                if status != "pass":
                    issues.append(f"{scenario_id}: status must be 'pass' (got '{status}')")
                diff_ratio = found.get("diffRatio")
                if not isinstance(diff_ratio, (int, float)):
                    issues.append(f"{scenario_id}: diffRatio must be numeric")
                elif float(diff_ratio) > args.max_diff_ratio:
                    issues.append(
                        f"{scenario_id}: diffRatio {float(diff_ratio):.4f} exceeds max {args.max_diff_ratio:.4f}"
                    )
                candidate = found.get("candidateArtifact")
                if not isinstance(candidate, str) or not candidate:
                    issues.append(f"{scenario_id}: candidateArtifact must be a non-empty path")
                elif not (repo_root / candidate).is_file():
                    issues.append(f"{scenario_id}: candidate artifact file not found: {candidate}")

    passed = len(issues) == 0
    report = {
        "manifestPath": args.manifest,
        "diffReportPath": args.diff_report,
        "changedOnly": args.changed_only,
        "baseRef": args.base_ref,
        "gateRequired": gate_required,
        "impactedFiles": impacted_files,
        "impactedJourneys": impacted_journeys,
        "requiredScenarioIds": [scenario.get("id") for scenario in required_scenarios],
        "maxDiffRatio": args.max_diff_ratio,
        "passed": passed,
        "issueCount": len(issues),
        "issues": issues,
    }

    out_path = repo_root / args.report_out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if not gate_required and args.changed_only:
        print("MOD-02 compact gate skipped (no mapped MOD-02 files changed)")
        print(f"report: {out_path}")
        return 0

    if issues:
        print("MOD-02 compact artifact gate failed:")
        for issue in issues:
            print(f"- {issue}")
        print(f"report: {out_path}")
        return 1

    print("MOD-02 compact artifact gate passed")
    print(f"report: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
