#!/usr/bin/env python3
"""Validate Goal Dashboard proposal contracts (schema, parity, and UI contract gates)."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from jsonschema import Draft202012Validator
except ModuleNotFoundError as exc:  # pragma: no cover
    print(f"error: missing dependency jsonschema ({exc})")
    sys.exit(2)


@dataclass
class GateResult:
    gate_id: str
    passed: bool
    details: str


REQUIRED_FIXTURE_FILES = [
    "shared-test-fixtures/goal-dashboard/schemas/goal_dashboard_scene_model.v1.schema.json",
    "shared-test-fixtures/goal-dashboard/schemas/goal_dashboard_parity.v1.schema.json",
    "shared-test-fixtures/goal-dashboard/goal_dashboard_parity.v1.json",
    "shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_scene_model.v1.json",
    "shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_wire_roundtrip.v1.json",
]

IOS_SCREEN_PATH = "ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift"
IOS_COPY_CATALOG_PATH = "ios/CryptoSavingsTracker/Utilities/GoalDashboardCopyCatalog.swift"
ANDROID_SCREEN_PATH = "android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/dashboard/GoalDashboardScreen.kt"
ANDROID_COPY_CATALOG_PATH = "android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/dashboard/GoalDashboardCopyCatalog.kt"


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def gate_file_bootstrap(repo_root: Path) -> GateResult:
    missing = [path for path in REQUIRED_FIXTURE_FILES if not (repo_root / path).exists()]
    if missing:
        return GateResult(
            gate_id="DASH-BOOTSTRAP-001",
            passed=False,
            details=f"Missing required artifacts: {', '.join(missing)}",
        )
    return GateResult(
        gate_id="DASH-BOOTSTRAP-001",
        passed=True,
        details="All normative goal-dashboard artifact files exist.",
    )


def gate_schema_validation(repo_root: Path) -> GateResult:
    try:
        scene_schema = load_json(repo_root / REQUIRED_FIXTURE_FILES[0])
        parity_schema = load_json(repo_root / REQUIRED_FIXTURE_FILES[1])
        parity = load_json(repo_root / REQUIRED_FIXTURE_FILES[2])
        scene_fixture = load_json(repo_root / REQUIRED_FIXTURE_FILES[3])
    except Exception as exc:  # pragma: no cover
        return GateResult("DASH-SCHEMA-001", False, f"Failed to load schema/fixture files: {exc}")

    issues: list[str] = []
    for label, instance, schema in [
        ("scene_fixture", scene_fixture, scene_schema),
        ("parity_artifact", parity, parity_schema),
    ]:
        validator = Draft202012Validator(schema)
        for error in sorted(validator.iter_errors(instance), key=lambda e: list(e.path)):
            path = ".".join(str(p) for p in error.path) or "<root>"
            issues.append(f"{label}:{path}:{error.message}")

    if issues:
        return GateResult("DASH-SCHEMA-001", False, " | ".join(issues))

    return GateResult(
        gate_id="DASH-SCHEMA-001",
        passed=True,
        details="Scene and parity fixtures validate against shared JSON schemas.",
    )


def gate_parity_contract(repo_root: Path) -> GateResult:
    path = repo_root / REQUIRED_FIXTURE_FILES[2]
    try:
        payload = load_json(path)
    except Exception as exc:  # pragma: no cover
        return GateResult("DASH-PARITY-001", False, f"Failed to read parity artifact: {exc}")

    issues: list[str] = []
    version = payload.get("version")
    if not isinstance(version, str) or re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) is None:
        issues.append("version must be semver major.minor.patch")

    approvals = payload.get("approvals")
    for key in ("iosLead", "androidLead", "qaLead"):
        value = approvals.get(key) if isinstance(approvals, dict) else None
        if not isinstance(value, str) or not value.strip():
            issues.append(f"approvals.{key} missing")

    for key in ("moduleIds", "stateIds", "resolverStateIds", "copyKeys", "statusChipIds"):
        values = payload.get(key)
        if not isinstance(values, list) or not values:
            issues.append(f"{key} must be a non-empty list")

    if issues:
        return GateResult("DASH-PARITY-001", False, "; ".join(issues))
    return GateResult("DASH-PARITY-001", True, "Parity artifact has valid semver, approvals metadata, and required lists.")


def gate_ui_contracts(repo_root: Path) -> list[GateResult]:
    ios_source_path = repo_root / IOS_SCREEN_PATH
    android_source_path = repo_root / ANDROID_SCREEN_PATH
    if not ios_source_path.exists():
        return [
            GateResult("DASH-LINT-001", False, f"Missing source file: {IOS_SCREEN_PATH}"),
            GateResult("DASH-LINT-002", False, f"Missing source file: {IOS_SCREEN_PATH}"),
            GateResult("DASH-A11Y-CHIP-001", False, f"Missing source file: {IOS_SCREEN_PATH}"),
            GateResult("DASH-SNAP-CHIP-001", False, f"Missing source file: {IOS_SCREEN_PATH}"),
            GateResult("DASH-MOTION-001", False, f"Missing source file: {IOS_SCREEN_PATH}"),
            GateResult("DASH-SNAP-STATE-001", False, f"Missing source file: {IOS_SCREEN_PATH}"),
        ]
    if not android_source_path.exists():
        return [
            GateResult("DASH-LINT-001", False, f"Missing source file: {ANDROID_SCREEN_PATH}"),
            GateResult("DASH-LINT-002", False, f"Missing source file: {ANDROID_SCREEN_PATH}"),
            GateResult("DASH-A11Y-CHIP-001", False, f"Missing source file: {ANDROID_SCREEN_PATH}"),
            GateResult("DASH-SNAP-CHIP-001", False, f"Missing source file: {ANDROID_SCREEN_PATH}"),
            GateResult("DASH-MOTION-001", False, f"Missing source file: {ANDROID_SCREEN_PATH}"),
            GateResult("DASH-SNAP-STATE-001", False, f"Missing source file: {ANDROID_SCREEN_PATH}"),
        ]

    ios_text = ios_source_path.read_text(encoding="utf-8")
    android_text = android_source_path.read_text(encoding="utf-8")
    results: list[GateResult] = []

    ios_required_tokens = [
        "VisualComponentTokens.dashboardCardPrimaryFill",
        "VisualComponentTokens.dashboardCardSecondaryFill",
        "VisualComponentTokens.dashboardCardEmphasisFill",
        "VisualComponentTokens.dashboardCardStroke",
    ]
    android_required_tokens = [
        "VisualComponentDefaults.goalDashboardPrimaryCardColors()",
        "VisualComponentDefaults.goalDashboardSecondaryCardColors()",
        "VisualComponentDefaults.goalDashboardEmphasisCardColors()",
        "VisualComponentDefaults.goalDashboardCardBorder()",
    ]
    ios_missing_tokens = [token for token in ios_required_tokens if token not in ios_text]
    android_missing_tokens = [token for token in android_required_tokens if token not in android_text]
    results.append(
        GateResult(
            "DASH-LINT-001",
            not ios_missing_tokens and not android_missing_tokens,
            "Token-only surfaces verified on iOS + Android."
            if not ios_missing_tokens and not android_missing_tokens
            else (
                f"iOS missing: {', '.join(ios_missing_tokens) if ios_missing_tokens else 'none'}; "
                f"Android missing: {', '.join(android_missing_tokens) if android_missing_tokens else 'none'}"
            ),
        )
    )

    forbidden = [".shadow(", ".regularMaterial"]
    ios_offenders = [item for item in forbidden if item in ios_text]
    android_offenders = [item for item in forbidden if item in android_text]
    results.append(
        GateResult(
            "DASH-LINT-002",
            not ios_offenders and not android_offenders,
            "No ad-hoc shadow/material usage in GoalDashboardScreen on iOS + Android."
            if not ios_offenders and not android_offenders
            else (
                f"iOS offenders: {', '.join(ios_offenders) if ios_offenders else 'none'}; "
                f"Android offenders: {', '.join(android_offenders) if android_offenders else 'none'}"
            ),
        )
    )

    a11y_required = [
        "On track: current pace can reach deadline",
        "At risk: current pace may miss deadline",
        "Off track: current pace will miss deadline",
    ]
    ios_missing_a11y = [item for item in a11y_required if item not in ios_text]
    android_missing_a11y = [item for item in a11y_required if item not in android_text]
    results.append(
        GateResult(
            "DASH-A11Y-CHIP-001",
            not ios_missing_a11y and not android_missing_a11y,
            "Status chip accessibility labels present on iOS + Android."
            if not ios_missing_a11y and not android_missing_a11y
            else (
                f"iOS missing a11y labels: {', '.join(ios_missing_a11y) if ios_missing_a11y else 'none'}; "
                f"Android missing a11y labels: {', '.join(android_missing_a11y) if android_missing_a11y else 'none'}"
            ),
        )
    )

    ios_chip_required = ["checkmark.circle.fill", "exclamationmark.triangle.fill", "xmark.octagon.fill", ".accessibilityLabel("]
    android_chip_required = ["checkmark.circle.fill", "exclamationmark.triangle.fill", "xmark.octagon.fill", ".semantics { contentDescription ="]
    ios_missing_chip = [item for item in ios_chip_required if item not in ios_text]
    android_missing_chip = [item for item in android_chip_required if item not in android_text]
    results.append(
        GateResult(
            "DASH-SNAP-CHIP-001",
            not ios_missing_chip and not android_missing_chip,
            "Status chip anatomy markers present (icon/text/a11y) on iOS + Android."
            if not ios_missing_chip and not android_missing_chip
            else (
                f"iOS missing chip markers: {', '.join(ios_missing_chip) if ios_missing_chip else 'none'}; "
                f"Android missing chip markers: {', '.join(android_missing_chip) if android_missing_chip else 'none'}"
            ),
        )
    )

    has_reduce_motion_ios = "@Environment(\\.accessibilityReduceMotion)" in ios_text and ".animation(sceneTransitionAnimation" in ios_text
    has_reduce_motion_android = "prefersReducedMotion()" in android_text and ".animateContentSize(" in android_text
    results.append(
        GateResult(
            "DASH-MOTION-001",
            has_reduce_motion_ios and has_reduce_motion_android,
            "Reduced-motion fallback and controlled animation are present on iOS + Android."
            if has_reduce_motion_ios and has_reduce_motion_android
            else (
                f"iOS reduced-motion gate: {'ok' if has_reduce_motion_ios else 'missing'}; "
                f"Android reduced-motion gate: {'ok' if has_reduce_motion_android else 'missing'}"
            ),
        )
    )

    ios_state_markers = [".loading", ".ready", ".empty", ".error", ".stale"]
    android_state_markers = [
        "GoalDashboardModuleState.LOADING",
        "GoalDashboardModuleState.READY",
        "GoalDashboardModuleState.EMPTY",
        "GoalDashboardModuleState.ERROR",
        "GoalDashboardModuleState.STALE",
    ]
    ios_missing_states = [marker for marker in ios_state_markers if marker not in ios_text]
    android_missing_states = [marker for marker in android_state_markers if marker not in android_text]
    results.append(
        GateResult(
            "DASH-SNAP-STATE-001",
            not ios_missing_states and not android_missing_states,
            "Module state render markers cover loading/ready/empty/error/stale on iOS + Android."
            if not ios_missing_states and not android_missing_states
            else (
                f"iOS missing state markers: {', '.join(ios_missing_states) if ios_missing_states else 'none'}; "
                f"Android missing state markers: {', '.join(android_missing_states) if android_missing_states else 'none'}"
            ),
        )
    )

    return results


def gate_copy_checklist(repo_root: Path) -> GateResult:
    ios_source_path = repo_root / IOS_COPY_CATALOG_PATH
    android_source_path = repo_root / ANDROID_COPY_CATALOG_PATH
    if not ios_source_path.exists():
        return GateResult("DASH-COPY-ERR-001", False, f"Missing source file: {IOS_COPY_CATALOG_PATH}")
    if not android_source_path.exists():
        return GateResult("DASH-COPY-ERR-001", False, f"Missing source file: {ANDROID_COPY_CATALOG_PATH}")

    ios_text = ios_source_path.read_text(encoding="utf-8")
    android_text = android_source_path.read_text(encoding="utf-8")
    issues: list[str] = []
    if "dashboard.nextAction.hardError.reason" not in ios_text:
        issues.append("missing hard-error reason copy key")
    if "dashboard.nextAction.hardError.nextStep" not in ios_text:
        issues.append("missing hard-error next-step copy key")
    if "hardErrorUserMessage" not in ios_text:
        issues.append("missing hard-error user message")
    if "dashboard.nextAction.hardError.reason" not in android_text:
        issues.append("android catalog missing hard-error reason copy key")
    if "dashboard.nextAction.hardError.nextStep" not in android_text:
        issues.append("android catalog missing hard-error next-step copy key")
    if "hardErrorUserMessage" not in android_text:
        issues.append("android catalog missing hard-error user message")
    user_message_match = re.search(r'hardErrorUserMessage\s*=\s*"([^"]+)"', ios_text)
    reason_match = re.search(r'"dashboard\.nextAction\.hardError\.reason"\s*:\s*"([^"]+)"', ios_text)
    next_step_match = re.search(r'"dashboard\.nextAction\.hardError\.nextStep"\s*:\s*"([^"]+)"', ios_text)

    user_message = user_message_match.group(1) if user_message_match else ""
    reason_copy = reason_match.group(1) if reason_match else ""
    next_step_copy = next_step_match.group(1) if next_step_match else ""

    combined = " ".join([user_message, reason_copy, next_step_copy]).lower()
    if "unknown error" in combined or "unexpected issue" in combined:
        issues.append("contains vague diagnostics wording without specificity")
    if not re.match(r"^(Retry|Verify|Check|Open|Refresh|Reconnect|Inspect)\b", next_step_copy):
        issues.append("next-step guidance must start with an action verb")
    if "func diagnosticsChecklistViolations() -> [String]" not in ios_text:
        issues.append("missing iOS checklist validator implementation")
    if "fun diagnosticsChecklistViolations()" not in android_text:
        issues.append("missing Android checklist validator implementation")

    if issues:
        return GateResult("DASH-COPY-ERR-001", False, "; ".join(issues))
    return GateResult(
        "DASH-COPY-ERR-001",
        True,
        "Diagnostics copy checklist implementation exists with hard-error reason and next-step coverage.",
    )


def write_report(path: Path, checks: list[GateResult]) -> None:
    payload = {
        "passed": all(check.passed for check in checks),
        "checks": [
            {
                "gateId": check.gate_id,
                "passed": check.passed,
                "details": check.details,
            }
            for check in checks
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Goal Dashboard contract gates")
    parser.add_argument(
        "--report-out",
        default="artifacts/goal-dashboard/goal-dashboard-contract-report.json",
        help="Output JSON report path",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent

    checks: list[GateResult] = []
    checks.append(gate_file_bootstrap(repo_root))
    checks.append(gate_schema_validation(repo_root))
    checks.append(gate_parity_contract(repo_root))
    checks.extend(gate_ui_contracts(repo_root))
    checks.append(gate_copy_checklist(repo_root))

    for check in checks:
        status = "PASS" if check.passed else "FAIL"
        print(f"[{status}] {check.gate_id}: {check.details}")

    report_path = repo_root / args.report_out
    write_report(report_path, checks)
    print(f"wrote report: {report_path}")

    return 0 if all(check.passed for check in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
