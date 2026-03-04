#!/usr/bin/env python3
"""Validate wave UX metrics artifact for visual system promotion gates."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def check_thresholds(report: dict[str, Any]) -> tuple[list[str], dict[str, Any]]:
    issues: list[str] = []

    sample = report.get("sample", {})
    participants = int(sample.get("participants", 0))
    scenario_tasks = int(sample.get("scenarioTasks", 0))
    if participants < 12:
        issues.append(f"sample.participants must be >= 12 (got {participants})")
    if scenario_tasks < 60:
        issues.append(f"sample.scenarioTasks must be >= 60 (got {scenario_tasks})")

    confidence = report.get("confidence", {})
    confidence_level = float(confidence.get("levelPercent", 0))
    if confidence_level < 95:
        issues.append(f"confidence.levelPercent must be >= 95 (got {confidence_level})")

    metrics = report.get("metrics", {})
    comprehension = metrics.get("statusComprehensionTime", {})
    comprehension_p50 = float(comprehension.get("p50Seconds", 0))
    comprehension_improvement = float(comprehension.get("improvementVsBaselinePercent", 0))
    if comprehension_p50 > 12:
        issues.append(
            f"metrics.statusComprehensionTime.p50Seconds must be <= 12 (got {comprehension_p50})"
        )
    if comprehension_improvement < 15:
        issues.append(
            "metrics.statusComprehensionTime.improvementVsBaselinePercent "
            f"must be >= 15 (got {comprehension_improvement})"
        )

    shortfall = metrics.get("shortfallActionAccuracy", {})
    shortfall_accuracy = float(shortfall.get("percent", 0))
    shortfall_wilson = shortfall.get("wilsonInterval95", {})
    if shortfall_accuracy < 95:
        issues.append(f"metrics.shortfallActionAccuracy.percent must be >= 95 (got {shortfall_accuracy})")
    if "low" not in shortfall_wilson or "high" not in shortfall_wilson:
        issues.append("metrics.shortfallActionAccuracy.wilsonInterval95.{low,high} is required")

    misinterpretation = metrics.get("warningMisinterpretationRate", {})
    misinterpretation_rate = float(misinterpretation.get("percent", 100))
    misinterpretation_wilson = misinterpretation.get("wilsonInterval95", {})
    if misinterpretation_rate > 5:
        issues.append(
            "metrics.warningMisinterpretationRate.percent must be <= 5 "
            f"(got {misinterpretation_rate})"
        )
    if "low" not in misinterpretation_wilson or "high" not in misinterpretation_wilson:
        issues.append("metrics.warningMisinterpretationRate.wilsonInterval95.{low,high} is required")

    summary = {
        "wave": report.get("wave"),
        "evaluatedAt": report.get("evaluatedAt"),
        "sample": {
            "participants": participants,
            "scenarioTasks": scenario_tasks,
        },
        "confidenceLevelPercent": confidence_level,
        "metrics": {
            "statusComprehensionTime": {
                "p50Seconds": comprehension_p50,
                "improvementVsBaselinePercent": comprehension_improvement,
            },
            "shortfallActionAccuracy": {
                "percent": shortfall_accuracy,
                "wilsonInterval95": shortfall_wilson,
            },
            "warningMisinterpretationRate": {
                "percent": misinterpretation_rate,
                "wilsonInterval95": misinterpretation_wilson,
            },
        },
    }
    return issues, summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--report",
        default="artifacts/visual-system/ux-metrics-report.json",
        help="Path to wave UX metrics artifact JSON",
    )
    parser.add_argument(
        "--report-out",
        default="artifacts/visual-system/ux-metrics-validation-report.json",
        help="Path to write validator report",
    )
    args = parser.parse_args()

    report_path = Path(args.report)
    if not report_path.exists():
        print(f"error: UX metrics report not found: {report_path}")
        return 2

    payload = load_json(report_path)
    issues, summary = check_thresholds(payload)

    output = {
        "reportPath": str(report_path),
        "passed": len(issues) == 0,
        "issueCount": len(issues),
        "summary": summary,
        "issues": issues,
    }

    report_out_path = Path(args.report_out)
    report_out_path.parent.mkdir(parents=True, exist_ok=True)
    report_out_path.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("visual UX metrics validation failed:")
        for issue in issues:
            print(f"- {issue}")
        print(f"report: {report_out_path}")
        return 1

    print("visual UX metrics validation passed")
    print(f"report: {report_out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
