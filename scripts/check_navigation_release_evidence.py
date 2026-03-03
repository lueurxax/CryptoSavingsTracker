#!/usr/bin/env python3
"""Validate navigation release-evidence package and telemetry schema contract."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

REQUIRED_RELEASE_FILES = [
    "README.md",
    "guardrails-metrics-report.json",
    "hard-cutover-report.json",
    "go-no-go.md",
    "mod02-diff-report.json",
    "rollback-drill.md",
    "parity-matrix-report.json",
    "policy-report.json",
]

REQUIRED_EVENTS: dict[str, list[str]] = {
    "nav_flow_started": ["journey_id", "platform", "entry_point"],
    "nav_flow_completed": ["journey_id", "platform", "duration_ms", "result"],
    "nav_cancelled": ["journey_id", "platform", "is_dirty", "cancel_stage"],
    "nav_discard_confirmed": ["journey_id", "platform", "form_type"],
    "nav_recovery_completed": ["journey_id", "platform", "recovery_path", "success"],
}


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def validate_release_files(release_dir: Path) -> list[str]:
    issues: list[str] = []
    for rel in REQUIRED_RELEASE_FILES:
        if not (release_dir / rel).is_file():
            issues.append(f"missing required release artifact: {release_dir / rel}")
    return issues


def validate_telemetry_schema(schema: dict[str, Any]) -> list[str]:
    issues: list[str] = []

    raw_events = schema.get("events")
    if not isinstance(raw_events, list):
        return ["telemetry schema: events must be a list"]

    events_by_name: dict[str, dict[str, Any]] = {}
    for idx, event in enumerate(raw_events):
        if not isinstance(event, dict):
            issues.append(f"telemetry schema: events[{idx}] must be an object")
            continue
        name = event.get("name")
        if not isinstance(name, str) or not name:
            issues.append(f"telemetry schema: events[{idx}].name must be non-empty string")
            continue
        events_by_name[name] = event

    for event_name, required_fields in REQUIRED_EVENTS.items():
        event = events_by_name.get(event_name)
        if event is None:
            issues.append(f"telemetry schema: missing event {event_name}")
            continue

        props = event.get("requiredProperties")
        if not isinstance(props, list):
            issues.append(f"telemetry schema: {event_name}.requiredProperties must be a list")
            continue

        prop_set = {p for p in props if isinstance(p, str)}
        missing = [f for f in required_fields if f not in prop_set]
        if missing:
            issues.append(
                f"telemetry schema: {event_name} missing required properties: {', '.join(missing)}"
            )

    top_journeys = schema.get("topJourneys")
    if not isinstance(top_journeys, list) or len(top_journeys) < 5:
        issues.append("telemetry schema: topJourneys must include at least 5 journey ids")

    return issues


def validate_policy_report(report: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    if report.get("passed") is not True:
        issues.append("policy-report.json: passed must be true")
    if report.get("issueCount") != 0:
        issues.append("policy-report.json: issueCount must be 0")
    if report.get("changedOnly") is not False:
        issues.append("policy-report.json: changedOnly must be false in release evidence")

    scanned_file_count = report.get("scannedFileCount")
    if not isinstance(scanned_file_count, int) or scanned_file_count <= 0:
        issues.append("policy-report.json: scannedFileCount must be > 0 in release evidence")
    return issues


def validate_parity_report(report: dict[str, Any], schema: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    if report.get("passed") is not True:
        issues.append("parity-matrix-report.json: passed must be true")
    if report.get("issueCount") != 0:
        issues.append("parity-matrix-report.json: issueCount must be 0")

    schema_journeys = schema.get("topJourneys")
    parity_required = report.get("requiredJourneyIds")
    if isinstance(schema_journeys, list) and isinstance(parity_required, list):
        missing = sorted(set(schema_journeys) - set(parity_required))
        if missing:
            issues.append(
                "parity-matrix-report.json: requiredJourneyIds missing telemetry topJourneys: "
                + ", ".join(missing)
            )
    return issues


def validate_guardrails_report(report: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    if report.get("overallStatus") != "pass":
        issues.append("guardrails-metrics-report.json: overallStatus must be pass")

    metrics = report.get("metrics")
    required = [
        "completion_rate",
        "cancel_to_retry_rate",
        "time_to_success_p50",
        "recovery_success_rate",
    ]
    if not isinstance(metrics, dict):
        return ["guardrails-metrics-report.json: metrics must be an object"]

    for metric in required:
        if metric not in metrics:
            issues.append(f"guardrails-metrics-report.json: missing metric {metric}")
            continue
        entry = metrics[metric]
        if not isinstance(entry, dict):
            issues.append(f"guardrails-metrics-report.json: metric {metric} must be object")
            continue
        if entry.get("status") != "pass":
            issues.append(f"guardrails-metrics-report.json: metric {metric} status must be pass")

    return issues


def validate_mod02_report(report: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    scenarios = report.get("scenarios")
    if not isinstance(scenarios, list) or len(scenarios) == 0:
        return ["mod02-diff-report.json: scenarios must be a non-empty list"]

    max_allowed = report.get("maxAllowedDiffRatio")
    if not isinstance(max_allowed, (int, float)):
        issues.append("mod02-diff-report.json: maxAllowedDiffRatio must be numeric")
        max_allowed = 1.0

    for index, scenario in enumerate(scenarios):
        if not isinstance(scenario, dict):
            issues.append(f"mod02-diff-report.json: scenarios[{index}] must be object")
            continue
        status = scenario.get("status")
        if status != "pass":
            scenario_id = scenario.get("id", f"#{index}")
            issues.append(f"mod02-diff-report.json: scenario {scenario_id} status must be pass")
        ratio = scenario.get("diffRatio")
        if not isinstance(ratio, (int, float)):
            issues.append(f"mod02-diff-report.json: scenarios[{index}].diffRatio must be numeric")
            continue
        if ratio > float(max_allowed):
            scenario_id = scenario.get("id", f"#{index}")
            issues.append(
                f"mod02-diff-report.json: scenario {scenario_id} diffRatio {ratio} exceeds maxAllowedDiffRatio {max_allowed}"
            )

    return issues


def validate_hard_cutover_report(report: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    if report.get("passed") is not True:
        issues.append("hard-cutover-report.json: passed must be true")
    if report.get("issueCount") != 0:
        issues.append("hard-cutover-report.json: issueCount must be 0")

    scanned_file_count = report.get("scannedFileCount")
    if not isinstance(scanned_file_count, int) or scanned_file_count <= 0:
        issues.append("hard-cutover-report.json: scannedFileCount must be > 0")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--release-dir",
        default="docs/release/navigation/latest",
        help="Path to navigation release evidence package",
    )
    parser.add_argument(
        "--schema",
        default="docs/testing/navigation-telemetry-schema.v1.json",
        help="Path to telemetry schema JSON",
    )
    parser.add_argument(
        "--report-out",
        default="artifacts/navigation/release-evidence-report.json",
        help="Output path for machine-readable report",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    release_dir = repo_root / args.release_dir
    schema_path = repo_root / args.schema

    issues: list[str] = []

    if not release_dir.is_dir():
        issues.append(f"release evidence directory not found: {release_dir}")
    else:
        issues.extend(validate_release_files(release_dir))

    if not schema_path.is_file():
        issues.append(f"telemetry schema not found: {schema_path}")
        schema: dict[str, Any] = {}
    else:
        schema = load_json(schema_path)
        issues.extend(validate_telemetry_schema(schema))

    if release_dir.is_dir():
        policy_path = release_dir / "policy-report.json"
        parity_path = release_dir / "parity-matrix-report.json"
        guardrails_path = release_dir / "guardrails-metrics-report.json"
        hard_cutover_path = release_dir / "hard-cutover-report.json"
        mod02_path = release_dir / "mod02-diff-report.json"

        if policy_path.is_file():
            issues.extend(validate_policy_report(load_json(policy_path)))
        if parity_path.is_file():
            issues.extend(validate_parity_report(load_json(parity_path), schema))
        if guardrails_path.is_file():
            issues.extend(validate_guardrails_report(load_json(guardrails_path)))
        if hard_cutover_path.is_file():
            issues.extend(validate_hard_cutover_report(load_json(hard_cutover_path)))
        if mod02_path.is_file():
            issues.extend(validate_mod02_report(load_json(mod02_path)))

    report = {
        "releaseDir": args.release_dir,
        "schemaPath": args.schema,
        "passed": len(issues) == 0,
        "issueCount": len(issues),
        "issues": issues,
        "requiredReleaseFiles": REQUIRED_RELEASE_FILES,
        "requiredEvents": REQUIRED_EVENTS,
    }

    out_path = repo_root / args.report_out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("navigation release evidence validation failed:")
        for issue in issues:
            print(f"- {issue}")
        print(f"report: {out_path}")
        return 1

    print("navigation release evidence validation passed")
    print(f"report: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
