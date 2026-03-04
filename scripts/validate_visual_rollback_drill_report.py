#!/usr/bin/env python3
"""Validate visual rollback drill evidence for release gating."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

DEFAULT_REPORT = "artifacts/visual-system/rollback-drill-report.json"
DEFAULT_SCHEMA = "docs/design/schemas/visual-rollback-drill-report.schema.json"
DEFAULT_REPORT_OUT = "artifacts/visual-system/rollback-drill-validation.json"
REQUIRED_TRIGGER_EVENT = "vsu_wave_rollback_triggered"
REQUIRED_COMPLETED_EVENT = "vsu_wave_rollback_completed"
MAX_SLA_BUSINESS_DAYS = 1.0


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def maybe_validate_schema(payload: dict[str, Any], schema_path: Path) -> list[str]:
    issues: list[str] = []
    if not schema_path.exists():
        return [f"schema file not found: {schema_path}"]

    try:
        import jsonschema  # type: ignore
    except Exception:
        return issues

    try:
        schema = load_json(schema_path)
        jsonschema.validate(instance=payload, schema=schema)
    except Exception as exc:  # noqa: BLE001
        issues.append(f"schema validation failed: {exc}")
    return issues


def validate_report(payload: dict[str, Any], repo_root: Path) -> tuple[list[str], dict[str, Any]]:
    issues: list[str] = []

    runbook_path_raw = str(payload.get("runbookPath", "")).strip()
    if not runbook_path_raw:
        issues.append("runbookPath is required")
        runbook_exists = False
    else:
        runbook_path = Path(runbook_path_raw)
        if not runbook_path.is_absolute():
            runbook_path = repo_root / runbook_path
        runbook_exists = runbook_path.exists()
        if not runbook_exists:
            issues.append(f"runbookPath does not exist: {runbook_path_raw}")

    sla_max = float(payload.get("slaBusinessDaysMax", 0))
    sla_actual = float(payload.get("slaBusinessDaysActual", 0))
    if sla_max > MAX_SLA_BUSINESS_DAYS:
        issues.append(
            f"slaBusinessDaysMax must be <= {MAX_SLA_BUSINESS_DAYS:g} (got {sla_max})"
        )
    if sla_actual > sla_max:
        issues.append(
            f"slaBusinessDaysActual exceeds SLA max ({sla_actual} > {sla_max})"
        )

    checklist = payload.get("checklist", {})
    checklist_results: dict[str, bool] = {}
    if not isinstance(checklist, dict):
        issues.append("checklist must be an object")
    else:
        for key in (
            "regressionConfirmed",
            "flagsDisabled",
            "fallbackValidated",
            "communicationSent",
            "postmortemPlanned",
        ):
            value = checklist.get(key)
            if value is not True:
                issues.append(f"checklist.{key} must be true")
            checklist_results[key] = value is True

    telemetry = payload.get("telemetryMarkers", {})
    trigger_event = ""
    completed_event = ""
    marker_timestamp = ""
    if not isinstance(telemetry, dict):
        issues.append("telemetryMarkers must be an object")
    else:
        trigger_event = str(telemetry.get("triggeredEvent", "")).strip()
        completed_event = str(telemetry.get("completedEvent", "")).strip()
        marker_timestamp = str(telemetry.get("markerTimestamp", "")).strip()
        if trigger_event != REQUIRED_TRIGGER_EVENT:
            issues.append(
                f"telemetryMarkers.triggeredEvent must be '{REQUIRED_TRIGGER_EVENT}'"
            )
        if completed_event != REQUIRED_COMPLETED_EVENT:
            issues.append(
                f"telemetryMarkers.completedEvent must be '{REQUIRED_COMPLETED_EVENT}'"
            )
        if not re.match(r"^\d{4}-\d{2}-\d{2}T", marker_timestamp):
            issues.append("telemetryMarkers.markerTimestamp must be ISO-8601 datetime")

    evidence_links = payload.get("evidenceLinks", [])
    if not isinstance(evidence_links, list) or not evidence_links:
        issues.append("evidenceLinks must contain at least one entry")
        evidence_count = 0
    else:
        evidence_count = len([x for x in evidence_links if isinstance(x, str) and x.strip()])
        if evidence_count != len(evidence_links):
            issues.append("evidenceLinks entries must be non-empty strings")

    summary = {
        "wave": payload.get("wave"),
        "executedAt": payload.get("executedAt"),
        "runbookPath": runbook_path_raw,
        "runbookExists": runbook_exists,
        "slaBusinessDaysMax": sla_max,
        "slaBusinessDaysActual": sla_actual,
        "checklist": checklist_results,
        "telemetryMarkers": {
            "triggeredEvent": trigger_event,
            "completedEvent": completed_event,
            "markerTimestamp": marker_timestamp,
        },
        "evidenceLinkCount": evidence_count,
    }
    return issues, summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", default=DEFAULT_REPORT)
    parser.add_argument("--schema", default=DEFAULT_SCHEMA)
    parser.add_argument("--report-out", default=DEFAULT_REPORT_OUT)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    report_path = repo_root / args.report
    schema_path = repo_root / args.schema
    out_path = repo_root / args.report_out

    if not report_path.exists():
        print(f"error: rollback drill report not found: {report_path}")
        return 2

    payload = load_json(report_path)
    issues = maybe_validate_schema(payload, schema_path)
    validation_issues, summary = validate_report(payload, repo_root=repo_root)
    issues.extend(validation_issues)

    output = {
        "reportPath": args.report,
        "schemaPath": args.schema,
        "passed": len(issues) == 0,
        "issueCount": len(issues),
        "summary": summary,
        "issues": issues,
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("visual rollback drill report validation failed:")
        for issue in issues:
            print(f"- {issue}")
        print(f"report: {out_path}")
        return 1

    print("visual rollback drill report validation passed")
    print(f"report: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
