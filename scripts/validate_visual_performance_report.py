#!/usr/bin/env python3
"""Validate visual performance budget evidence for release gating."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

DEFAULT_REPORT = "artifacts/visual-system/performance-report.json"
DEFAULT_SCHEMA = "docs/design/schemas/visual-performance-report.schema.json"
DEFAULT_REPORT_OUT = "artifacts/visual-system/performance-report-validation.json"
REQUIRED_IOS_DEVICES = {"iphone 16e", "iphone 17 pro max"}
REQUIRED_ANDROID_DEVICES = {"pixel 8"}
MAX_P95_REGRESSION_PERCENT = 10.0
MAX_JANK_DELTA_PERCENTAGE_POINTS = 2.0


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


def normalize_device_name(value: str) -> str:
    return " ".join(value.lower().split())


def validate_thresholds(
    payload: dict[str, Any],
    repo_root: Path,
) -> tuple[list[str], dict[str, Any]]:
    issues: list[str] = []
    baseline = payload.get("baseline", {})
    current = payload.get("current", {})
    deltas = payload.get("deltas", {})
    thresholds = payload.get("thresholds", {})
    traces = payload.get("traces", [])

    baseline_p95 = float(baseline.get("p95FrameTimeMs", 0))
    baseline_jank = float(baseline.get("jankRatePercent", 0))
    current_p95 = float(current.get("p95FrameTimeMs", 0))
    current_jank = float(current.get("jankRatePercent", 0))

    if baseline_p95 <= 0:
        issues.append("baseline.p95FrameTimeMs must be > 0")
        computed_p95_regression = math.inf
    else:
        computed_p95_regression = ((current_p95 - baseline_p95) / baseline_p95) * 100.0
    computed_jank_delta = current_jank - baseline_jank

    declared_p95 = float(deltas.get("p95RegressionPercent", 0))
    declared_jank = float(deltas.get("jankDeltaPercentagePoints", 0))
    if abs(declared_p95 - computed_p95_regression) > 0.2:
        issues.append(
            "deltas.p95RegressionPercent does not match baseline/current calculation "
            f"(declared={declared_p95:.3f}, computed={computed_p95_regression:.3f})"
        )
    if abs(declared_jank - computed_jank_delta) > 0.2:
        issues.append(
            "deltas.jankDeltaPercentagePoints does not match baseline/current calculation "
            f"(declared={declared_jank:.3f}, computed={computed_jank_delta:.3f})"
        )

    threshold_p95 = float(thresholds.get("p95RegressionMaxPercent", 0))
    threshold_jank = float(thresholds.get("jankDeltaMaxPercentagePoints", 0))
    if threshold_p95 > MAX_P95_REGRESSION_PERCENT:
        issues.append(
            "thresholds.p95RegressionMaxPercent must be <= 10 per proposal "
            f"(got {threshold_p95})"
        )
    if threshold_jank > MAX_JANK_DELTA_PERCENTAGE_POINTS:
        issues.append(
            "thresholds.jankDeltaMaxPercentagePoints must be <= 2 per proposal "
            f"(got {threshold_jank})"
        )
    if declared_p95 > threshold_p95:
        issues.append(
            f"p95 regression threshold breached: {declared_p95:.3f} > {threshold_p95:.3f}"
        )
    if declared_jank > threshold_jank:
        issues.append(
            f"jank delta threshold breached: {declared_jank:.3f} > {threshold_jank:.3f}"
        )

    trace_rows: list[dict[str, str]] = []
    ios_devices: set[str] = set()
    android_devices: set[str] = set()
    if not isinstance(traces, list) or not traces:
        issues.append("traces must be a non-empty array")
    else:
        for idx, trace in enumerate(traces):
            if not isinstance(trace, dict):
                issues.append(f"traces[{idx}] must be an object")
                continue
            platform = str(trace.get("platform", "")).strip().lower()
            device = str(trace.get("device", "")).strip()
            tool = str(trace.get("tool", "")).strip()
            artifact_ref = str(trace.get("artifactRef", "")).strip()
            if platform not in {"ios", "android"}:
                issues.append(f"traces[{idx}].platform must be ios/android")
            if not device:
                issues.append(f"traces[{idx}].device is required")
            if not tool:
                issues.append(f"traces[{idx}].tool is required")
            if not artifact_ref:
                issues.append(f"traces[{idx}].artifactRef is required")
            else:
                artifact_path = Path(artifact_ref)
                if not artifact_path.is_absolute():
                    artifact_path = repo_root / artifact_path
                if not artifact_path.exists():
                    issues.append(f"traces[{idx}].artifactRef file not found: {artifact_ref}")

            normalized_device = normalize_device_name(device)
            if platform == "ios":
                ios_devices.add(normalized_device)
            elif platform == "android":
                android_devices.add(normalized_device)

            trace_rows.append(
                {
                    "platform": platform,
                    "device": device,
                    "tool": tool,
                    "artifactRef": artifact_ref,
                }
            )

    missing_ios = sorted(REQUIRED_IOS_DEVICES - ios_devices)
    missing_android = sorted(REQUIRED_ANDROID_DEVICES - android_devices)
    if missing_ios:
        issues.append(
            "missing mandatory iOS performance traces for devices: "
            + ", ".join(missing_ios)
        )
    if missing_android:
        issues.append(
            "missing mandatory Android performance traces for devices: "
            + ", ".join(missing_android)
        )

    summary = {
        "wave": payload.get("wave"),
        "evaluatedAt": payload.get("evaluatedAt"),
        "baseline": {
            "p95FrameTimeMs": baseline_p95,
            "jankRatePercent": baseline_jank,
        },
        "current": {
            "p95FrameTimeMs": current_p95,
            "jankRatePercent": current_jank,
        },
        "deltas": {
            "declaredP95RegressionPercent": declared_p95,
            "computedP95RegressionPercent": computed_p95_regression,
            "declaredJankDeltaPercentagePoints": declared_jank,
            "computedJankDeltaPercentagePoints": computed_jank_delta,
        },
        "thresholds": {
            "p95RegressionMaxPercent": threshold_p95,
            "jankDeltaMaxPercentagePoints": threshold_jank,
        },
        "traceCount": len(trace_rows),
        "traces": trace_rows,
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
    report_out = repo_root / args.report_out

    if not report_path.exists():
        print(f"error: performance report not found: {report_path}")
        return 2

    payload = load_json(report_path)
    issues = maybe_validate_schema(payload, schema_path)
    threshold_issues, summary = validate_thresholds(payload, repo_root=repo_root)
    issues.extend(threshold_issues)

    output = {
        "reportPath": args.report,
        "schemaPath": args.schema,
        "passed": len(issues) == 0,
        "issueCount": len(issues),
        "summary": summary,
        "issues": issues,
    }

    report_out.parent.mkdir(parents=True, exist_ok=True)
    report_out.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("visual performance report validation failed:")
        for issue in issues:
            print(f"- {issue}")
        print(f"report: {report_out}")
        return 1

    print("visual performance report validation passed")
    print(f"report: {report_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
