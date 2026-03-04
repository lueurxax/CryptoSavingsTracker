#!/usr/bin/env python3
"""Deterministic accessibility gate entrypoint for visual system proposal."""

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

REQUIRED_STATUS_ROLES = ("status.success", "status.warning", "status.error")
REQUIRED_RELEASE_FLOWS = ("planning", "dashboard", "settings")
REQUIRED_RUNTIME_ASSERTIONS = (
    "screenReaderLabels",
    "focusOrder",
    "contrast",
    "reducedMotion",
    "nonColorSemantics",
)
RUNBOOK_TEMPLATE_MARKERS = (
    "## Incident Communication Templates",
    "### SEV1 User Communication Template",
    "### SEV2 User Communication Template",
)
INCIDENT_TEMPLATE_MARKERS = (
    "name: Visual System Rollback",
    "id: severity",
    "sev1",
    "sev2",
    "id: user_communication",
    "In-app banner",
    "Support macro",
    "Release notes",
)


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def run_state_validator(repo_root: Path, phase: str, require_artifact_files: bool) -> tuple[int, str]:
    cmd = [
        sys.executable,
        "scripts/validate_visual_state_matrix.py",
        "--phase",
        phase,
    ]
    if require_artifact_files:
        cmd.append("--require-artifact-files")
    result = subprocess.run(
        cmd,
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
    )
    output = "\n".join(x for x in [result.stdout.strip(), result.stderr.strip()] if x)
    return result.returncode, output


def check_non_color_cues(tokens: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    roles = tokens.get("roles", {})
    for role in REQUIRED_STATUS_ROLES:
        role_cfg = roles.get(role)
        if role_cfg is None:
            issues.append(f"missing required role: {role}")
            continue
        for platform in ("ios", "android"):
            spec = role_cfg.get(platform, {}).get("spec", {})
            if spec.get("nonColorCueRequired") is not True:
                issues.append(
                    f"{role}.{platform}.spec.nonColorCueRequired must be true for accessibility semantics"
                )
    return issues


def check_error_recovery_presence(matrix: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    components = matrix.get("components", {})
    release_components = matrix.get("releaseBlockingComponents", [])

    for component in release_components:
        component_cfg = components.get(component, {})
        for platform in ("ios", "android"):
            platform_cfg = component_cfg.get(platform, {})
            for state in ("error", "recovery"):
                if state not in platform_cfg:
                    issues.append(f"{component}.{platform}: missing required accessibility state '{state}'")
    return issues


def check_runbook_templates(runbook_path: Path) -> list[str]:
    if not runbook_path.exists():
        return [f"runbook not found: {runbook_path}"]

    text = runbook_path.read_text(encoding="utf-8")
    issues: list[str] = []
    for marker in RUNBOOK_TEMPLATE_MARKERS:
        if marker not in text:
            issues.append(f"runbook missing marker: {marker}")
    return issues


def check_motion_checklist(path: Path) -> list[str]:
    if path.exists():
        return []
    return [f"motion accessibility checklist not found: {path}"]


def check_runtime_assertions(path: Path, mode: str) -> tuple[list[str], dict[str, Any]]:
    if not path.exists():
        if mode == "release":
            return [f"runtime accessibility assertions artifact not found: {path}"], {}
        return [], {}

    payload = load_json(path)
    issues: list[str] = []

    if payload.get("evidenceType") != "runtime-assertions":
        issues.append("runtime assertions artifact must set evidenceType='runtime-assertions'")

    source_payload = payload.get("source", {})
    source_summary: dict[str, Any] = {}
    if isinstance(source_payload, dict):
        test_results_path = str(source_payload.get("testResultsPath", "")).strip()
        source_mode = str(source_payload.get("sourceMode", "")).strip()
        test_mode = str(source_payload.get("testMode", "")).strip()
        required_test_mode = str(source_payload.get("requiredTestMode", "")).strip()
        executed_tests_payload = source_payload.get("executedTests", {})
        suite_ids_payload = source_payload.get("suiteIds", {})
        executed_tests_summary: dict[str, int] = {"ios": 0, "android": 0, "total": 0}
        suite_ids_summary: dict[str, str] = {"ios": "", "android": ""}
        if mode == "release":
            if not test_results_path:
                issues.append("runtime assertions source.testResultsPath is required in release mode")
            if source_mode not in {"test-run", "fixture"}:
                issues.append("runtime assertions source.sourceMode must be 'test-run' or 'fixture'")
            if os.getenv("GITHUB_ACTIONS", "").lower() == "true" and source_mode != "test-run":
                issues.append("runtime assertions source.sourceMode must be 'test-run' in CI release mode")
            if test_mode not in {"smoke", "full"}:
                issues.append("runtime assertions source.testMode must be 'smoke' or 'full'")
            if required_test_mode not in {"smoke", "full"}:
                issues.append("runtime assertions source.requiredTestMode must be 'smoke' or 'full'")
            if test_mode and required_test_mode and test_mode != required_test_mode:
                issues.append("runtime assertions source.testMode must match source.requiredTestMode")
            if os.getenv("GITHUB_ACTIONS", "").lower() == "true" and test_mode != "full":
                issues.append("runtime assertions source.testMode must be 'full' in CI release mode")
            if os.getenv("GITHUB_ACTIONS", "").lower() == "true" and required_test_mode != "full":
                issues.append(
                    "runtime assertions source.requiredTestMode must be 'full' in CI release mode"
                )

            if not isinstance(executed_tests_payload, dict):
                issues.append("runtime assertions source.executedTests must be an object")
            else:
                for platform_key in ("ios", "android", "total"):
                    value = executed_tests_payload.get(platform_key)
                    if not isinstance(value, int):
                        issues.append(
                            f"runtime assertions source.executedTests.{platform_key} must be integer"
                        )
                        continue
                    executed_tests_summary[platform_key] = value
                if executed_tests_summary["total"] <= 0:
                    issues.append("runtime assertions source.executedTests.total must be > 0")
                if (
                    executed_tests_summary["ios"] > 0
                    and executed_tests_summary["android"] > 0
                    and executed_tests_summary["total"]
                    != executed_tests_summary["ios"] + executed_tests_summary["android"]
                ):
                    issues.append(
                        "runtime assertions source.executedTests.total must equal ios + android"
                    )
            if not isinstance(suite_ids_payload, dict):
                issues.append("runtime assertions source.suiteIds must be an object")
            else:
                for platform_key in ("ios", "android"):
                    value = str(suite_ids_payload.get(platform_key, "")).strip()
                    if not value:
                        issues.append(
                            f"runtime assertions source.suiteIds.{platform_key} is required in release mode"
                        )
                    suite_ids_summary[platform_key] = value
            if test_results_path:
                test_results_file = Path(test_results_path)
                if not test_results_file.is_absolute():
                    repo_root = Path(__file__).resolve().parent.parent
                    test_results_file = repo_root / test_results_file
                if not test_results_file.exists():
                    issues.append(
                        f"runtime assertions source.testResultsPath file not found: {test_results_path}"
                    )
        source_summary = {
            "testResultsPath": test_results_path,
            "sourceMode": source_mode,
            "testMode": test_mode,
            "requiredTestMode": required_test_mode,
            "executedTests": executed_tests_summary,
            "suiteIds": suite_ids_summary,
        }
    elif mode == "release":
        issues.append("runtime assertions source must be an object in release mode")

    provenance = payload.get("provenance", {})
    provenance_summary: dict[str, Any] = {}
    if not isinstance(provenance, dict):
        issues.append("runtime assertions provenance must be an object")
    else:
        commit_sha = str(provenance.get("commitSha", ""))
        ci_job_id = str(provenance.get("ciJobId", ""))
        captured_at_raw = str(provenance.get("capturedAt", ""))
        test_bundle_hash = str(provenance.get("testBundleHash", ""))

        if not re.fullmatch(r"[0-9a-f]{7,40}", commit_sha):
            issues.append("runtime assertions provenance.commitSha must be a lowercase hex SHA")
        if not ci_job_id:
            issues.append("runtime assertions provenance.ciJobId is required")
        if not re.fullmatch(r"[0-9a-f]{32,128}", test_bundle_hash):
            issues.append(
                "runtime assertions provenance.testBundleHash must be lowercase hex (32-128 chars)"
            )
        try:
            captured_at = datetime.fromisoformat(captured_at_raw.replace("Z", "+00:00"))
            now_utc = datetime.now(timezone.utc)
            if captured_at.tzinfo is None:
                issues.append("runtime assertions provenance.capturedAt must include timezone")
            elif captured_at > now_utc:
                issues.append("runtime assertions provenance.capturedAt cannot be in the future")
        except ValueError:
            issues.append("runtime assertions provenance.capturedAt must be ISO-8601 timestamp")

        expected_sha = os.getenv("GITHUB_SHA", "").strip().lower()
        if mode == "release" and expected_sha:
            if commit_sha != expected_sha and commit_sha != expected_sha[: len(commit_sha)]:
                issues.append(
                    "runtime assertions provenance.commitSha does not match current GITHUB_SHA"
                )

        expected_run_id = os.getenv("GITHUB_RUN_ID", "").strip()
        if mode == "release" and expected_run_id:
            if expected_run_id not in ci_job_id:
                issues.append(
                    "runtime assertions provenance.ciJobId must include current GITHUB_RUN_ID"
                )

        provenance_summary = {
            "commitSha": commit_sha,
            "ciJobId": ci_job_id,
            "capturedAt": captured_at_raw,
            "testBundleHash": test_bundle_hash,
        }

    platforms = payload.get("platforms", {})
    summary: dict[str, Any] = {"source": source_summary, "provenance": provenance_summary, "platforms": {}}
    required_runners = {
        "ios": "xctest-ui",
        "android": "android-instrumentation",
    }
    for platform in ("ios", "android"):
        platform_payload = platforms.get(platform)
        if not isinstance(platform_payload, dict):
            issues.append(f"runtime assertions missing platform: {platform}")
            continue

        runner = platform_payload.get("runner")
        if runner != required_runners[platform]:
            issues.append(
                f"runtime assertions {platform}.runner must be '{required_runners[platform]}'"
            )

        scenarios = platform_payload.get("scenarios", [])
        scenario_map = {
            scenario.get("flowId"): scenario for scenario in scenarios if isinstance(scenario, dict)
        }
        flow_summary: dict[str, Any] = {}
        for flow_id in REQUIRED_RELEASE_FLOWS:
            scenario = scenario_map.get(flow_id)
            flow_issues: list[str] = []
            if scenario is None:
                flow_issues.append("missing flow scenario")
            else:
                if scenario.get("passed") is not True:
                    flow_issues.append("scenario did not pass")
                assertions = scenario.get("assertions", {})
                for assertion_name in REQUIRED_RUNTIME_ASSERTIONS:
                    if assertions.get(assertion_name) is not True:
                        flow_issues.append(f"assertion failed or missing: {assertion_name}")
            if flow_issues:
                issues.extend([f"{platform}.{flow_id}: {item}" for item in flow_issues])
            flow_summary[flow_id] = {"passed": len(flow_issues) == 0, "issues": flow_issues}

        summary["platforms"][platform] = {
            "runner": runner,
            "flows": flow_summary,
        }

    return issues, summary


def check_incident_template(path: Path, mode: str) -> list[str]:
    if not path.exists():
        return [f"incident issue template not found: {path}"]

    text = path.read_text(encoding="utf-8")
    issues: list[str] = []
    for marker in INCIDENT_TEMPLATE_MARKERS:
        if marker not in text:
            issues.append(f"incident template missing marker: {marker}")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tokens", default="docs/design/visual-tokens.v1.json")
    parser.add_argument("--matrix", default="docs/design/visual-state-matrix.v1.json")
    parser.add_argument("--runbook", default="docs/runbooks/visual-system-rollback.md")
    parser.add_argument(
        "--runtime-assertions",
        default="artifacts/visual-system/runtime-accessibility-assertions.json",
    )
    parser.add_argument(
        "--incident-template",
        default=".github/ISSUE_TEMPLATE/visual-system-rollback.yml",
    )
    parser.add_argument(
        "--motion-checklist",
        default="docs/testing/visual-motion-accessibility-checklist.md",
    )
    parser.add_argument("--mode", choices=("pr", "release"), default="pr")
    parser.add_argument(
        "--report-out",
        default="artifacts/visual-system/accessibility-report.json",
        help="Path to write JSON report",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent

    tokens_path = repo_root / args.tokens
    matrix_path = repo_root / args.matrix
    runbook_path = repo_root / args.runbook
    runtime_assertions_path = repo_root / args.runtime_assertions
    incident_template_path = repo_root / args.incident_template
    motion_checklist_path = repo_root / args.motion_checklist

    missing = [
        p for p in (tokens_path, matrix_path) if not p.exists()
    ]
    if missing:
        for path in missing:
            print(f"error: required file not found: {path}")
        return 2

    tokens = load_json(tokens_path)
    matrix = load_json(matrix_path)

    issues: list[str] = []
    issues.extend(check_non_color_cues(tokens))
    issues.extend(check_error_recovery_presence(matrix))
    issues.extend(check_runbook_templates(runbook_path))
    issues.extend(check_motion_checklist(motion_checklist_path))
    issues.extend(check_incident_template(path=incident_template_path, mode=args.mode))

    runtime_issues, runtime_summary = check_runtime_assertions(
        path=runtime_assertions_path,
        mode=args.mode,
    )
    issues.extend(runtime_issues)

    phase = "design-complete" if args.mode == "pr" else "release-candidate"
    require_artifact_files = args.mode == "release"
    validator_code, validator_output = run_state_validator(
        repo_root=repo_root,
        phase=phase,
        require_artifact_files=require_artifact_files,
    )
    validator_lines = [line for line in validator_output.splitlines() if line]
    if validator_code != 0:
        issues.append(f"state-matrix-validator failed for phase '{phase}'")
        issues.extend([f"validator: {line}" for line in validator_lines])

    report = {
        "mode": args.mode,
        "phase": phase,
        "tokensPath": args.tokens,
        "matrixPath": args.matrix,
        "runbookPath": args.runbook,
        "runtimeAssertionsPath": args.runtime_assertions,
        "incidentTemplatePath": args.incident_template,
        "motionChecklistPath": args.motion_checklist,
        "passed": len(issues) == 0,
        "issueCount": len(issues),
        "runtimeAssertionsSummary": runtime_summary,
        "validatorOutput": validator_lines,
        "issues": issues,
    }

    report_path = repo_root / args.report_out
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("visual accessibility checks failed:")
        for issue in issues:
            print(f"- {issue}")
        print(f"report: {report_path}")
        return 1

    print("visual accessibility checks passed")
    print(f"report: {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
