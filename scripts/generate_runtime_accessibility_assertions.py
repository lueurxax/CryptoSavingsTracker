#!/usr/bin/env python3
"""Generate runtime accessibility assertions from executed accessibility test-results artifact."""

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

DEFAULT_TEST_RESULTS = "artifacts/visual-system/runtime-accessibility-test-results.json"
DEFAULT_OUTPUT = "artifacts/visual-system/runtime-accessibility-assertions.json"


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def resolve_commit_sha(cli_value: str) -> str:
    if cli_value:
        return cli_value.strip().lower()

    env_sha = os.getenv("GITHUB_SHA", "").strip().lower()
    if env_sha:
        return env_sha

    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode == 0:
        return result.stdout.strip().lower()
    return ""


def resolve_ci_job_id(cli_value: str) -> str:
    if cli_value:
        return cli_value.strip()

    run_id = os.getenv("GITHUB_RUN_ID", "").strip()
    run_attempt = os.getenv("GITHUB_RUN_ATTEMPT", "").strip()
    job_name = os.getenv("GITHUB_JOB", "").strip()

    if run_id:
        parts = [f"github-run-{run_id}"]
        if run_attempt:
            parts.append(f"attempt-{run_attempt}")
        if job_name:
            parts.append(f"job-{job_name}")
        return ":".join(parts)

    return "local-run"


def resolve_captured_at(cli_value: str) -> str:
    if cli_value:
        return cli_value.strip()
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def validate_test_results(payload: dict[str, Any], mode: str, allow_fixture: bool) -> list[str]:
    issues: list[str] = []
    if payload.get("evidenceType") != "runtime-accessibility-test-results":
        issues.append("test-results evidenceType must be 'runtime-accessibility-test-results'")

    test_mode = str(payload.get("testMode", "")).strip()
    if test_mode not in {"smoke", "full"}:
        issues.append("test-results testMode must be 'smoke' or 'full'")
    required_test_mode = str(payload.get("requiredTestMode", "")).strip()
    if required_test_mode not in {"smoke", "full"}:
        issues.append("test-results requiredTestMode must be 'smoke' or 'full'")

    source_mode = str(payload.get("sourceMode", "")).strip()
    if source_mode not in {"test-run", "fixture"}:
        issues.append("test-results sourceMode must be 'test-run' or 'fixture'")

    in_ci = os.getenv("GITHUB_ACTIONS", "").lower() == "true"
    if mode == "release" and source_mode != "test-run":
        issues.append("release mode requires sourceMode='test-run'")
    if mode == "release" and test_mode != "full":
        issues.append("release mode requires testMode='full'")
    if mode == "release" and required_test_mode != "full":
        issues.append("release mode requires requiredTestMode='full'")
    if mode == "release" and in_ci and source_mode != "test-run" and not allow_fixture:
        issues.append("release mode in CI requires sourceMode='test-run'")
    if mode == "release" and in_ci and test_mode != "full":
        issues.append("release mode in CI requires testMode='full'")
    if required_test_mode and test_mode and test_mode != required_test_mode:
        issues.append("test-results testMode must match requiredTestMode")

    executed_tests = payload.get("executedTests", {})
    if not isinstance(executed_tests, dict):
        issues.append("test-results executedTests must be an object")
    else:
        for key in ("ios", "android", "total"):
            if not isinstance(executed_tests.get(key), int):
                issues.append(f"test-results executedTests.{key} must be an integer")
        total = executed_tests.get("total")
        if isinstance(total, int) and total <= 0:
            issues.append("test-results executedTests.total must be > 0")

    platforms = payload.get("platforms")
    if not isinstance(platforms, dict):
        issues.append("test-results platforms must be an object")
        return issues

    expected_runners = {"ios": "xctest-ui", "android": "android-instrumentation"}
    required_flows = ("planning", "dashboard", "settings")
    required_assertions = (
        "screenReaderLabels",
        "focusOrder",
        "contrast",
        "reducedMotion",
        "nonColorSemantics",
    )

    for platform, runner in expected_runners.items():
        section = platforms.get(platform)
        if not isinstance(section, dict):
            issues.append(f"test-results missing platform section: {platform}")
            continue

        if section.get("runner") != runner:
            issues.append(f"test-results {platform}.runner must be '{runner}'")
        if not str(section.get("testCommand", "")).strip():
            issues.append(f"test-results {platform}.testCommand is required")
        if not str(section.get("suiteId", "")).strip():
            issues.append(f"test-results {platform}.suiteId is required")
        expected_suite_id = (
            "visual-accessibility-full-ios"
            if platform == "ios" and test_mode == "full"
            else "visual-accessibility-full-android"
            if platform == "android" and test_mode == "full"
            else "visual-accessibility-smoke-ios"
            if platform == "ios"
            else "visual-accessibility-smoke-android"
        )
        if str(section.get("suiteId", "")).strip() != expected_suite_id:
            issues.append(
                f"test-results {platform}.suiteId must be '{expected_suite_id}' for testMode='{test_mode}'"
            )
        executed_count = section.get("executedTestCount")
        if not isinstance(executed_count, int) or executed_count <= 0:
            issues.append(f"test-results {platform}.executedTestCount must be > 0 integer")

        scenarios = section.get("scenarios")
        if not isinstance(scenarios, list):
            issues.append(f"test-results {platform}.scenarios must be an array")
            continue

        flow_map = {
            scenario.get("flowId"): scenario for scenario in scenarios if isinstance(scenario, dict)
        }
        for flow_id in required_flows:
            scenario = flow_map.get(flow_id)
            if scenario is None:
                issues.append(f"test-results {platform}.scenarios missing flow '{flow_id}'")
                continue
            assertions = scenario.get("assertions", {})
            for assertion_name in required_assertions:
                if assertion_name not in assertions:
                    issues.append(
                        f"test-results {platform}.{flow_id}.assertions missing '{assertion_name}'"
                    )

    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("pr", "release"), default="release")
    parser.add_argument("--test-results", default=DEFAULT_TEST_RESULTS)
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--commit-sha", default="")
    parser.add_argument("--ci-job-id", default="")
    parser.add_argument("--captured-at", default="")
    parser.add_argument("--allow-fixture", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    test_results_path = repo_root / args.test_results
    if not test_results_path.exists():
        print(f"error: runtime accessibility test-results file not found: {test_results_path}")
        return 2

    test_results_payload = load_json(test_results_path)
    issues = validate_test_results(
        payload=test_results_payload,
        mode=args.mode,
        allow_fixture=args.allow_fixture,
    )
    if issues:
        print("error: runtime accessibility test-results validation failed")
        for issue in issues:
            print(f"- {issue}")
        return 2

    commit_sha = resolve_commit_sha(args.commit_sha)
    if not re.fullmatch(r"[0-9a-f]{7,40}", commit_sha):
        print("error: resolved commit SHA is missing or invalid")
        return 2

    ci_job_id = resolve_ci_job_id(args.ci_job_id)
    captured_at = resolve_captured_at(args.captured_at)
    try:
        captured_dt = datetime.fromisoformat(captured_at.replace("Z", "+00:00"))
    except ValueError:
        print("error: capturedAt must be ISO-8601 timestamp")
        return 2

    source_provenance = test_results_payload.get("provenance", {})
    source_commit_sha = str(source_provenance.get("commitSha", "")).lower()
    if source_commit_sha and source_commit_sha != commit_sha and source_commit_sha != commit_sha[: len(source_commit_sha)]:
        print("error: runtime test-results commitSha does not match current commit")
        return 2

    platforms = test_results_payload["platforms"]
    assertions_platforms = {
        "ios": {
            "runner": platforms["ios"]["runner"],
            "scenarios": platforms["ios"]["scenarios"],
        },
        "android": {
            "runner": platforms["android"]["runner"],
            "scenarios": platforms["android"]["scenarios"],
        },
    }

    output_payload = {
        "reportVersion": "v1",
        "evidenceType": "runtime-assertions",
        "generatedAt": captured_dt.date().isoformat(),
        "provenance": {
            "commitSha": commit_sha,
            "ciJobId": ci_job_id,
            "capturedAt": captured_at,
            "testBundleHash": str(source_provenance.get("testBundleHash", "")),
        },
        "source": {
            "testResultsPath": args.test_results,
            "sourceMode": test_results_payload.get("sourceMode", "fixture"),
            "testMode": test_results_payload.get("testMode", ""),
            "requiredTestMode": test_results_payload.get("requiredTestMode", ""),
            "executedTests": test_results_payload.get("executedTests", {}),
            "suiteIds": {
                "ios": str(platforms["ios"].get("suiteId", "")),
                "android": str(platforms["android"].get("suiteId", "")),
            },
        },
        "platforms": assertions_platforms,
    }

    output_path = repo_root / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output_payload, indent=2) + "\n", encoding="utf-8")

    print(f"runtime accessibility assertions generated: {output_path}")
    print(f"- source test-results: {test_results_path}")
    print(f"- commitSha: {commit_sha}")
    print(f"- ciJobId: {ci_job_id}")
    print(f"- capturedAt: {captured_at}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
