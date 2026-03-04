#!/usr/bin/env python3
"""Execute runtime accessibility test command and materialize canonical test-results artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DEFAULT_OUTPUT = "artifacts/visual-system/runtime-accessibility-test-results.json"
DEFAULT_FIXTURE = "docs/testing/visual-runtime-accessibility-test-results.example.json"
REQUIRED_FLOWS = ("planning", "dashboard", "settings")
REQUIRED_RUNNERS = {"ios": "xctest-ui", "android": "android-instrumentation"}
REQUIRED_ASSERTIONS = (
    "screenReaderLabels",
    "focusOrder",
    "contrast",
    "reducedMotion",
    "nonColorSemantics",
)


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


def compute_test_bundle_hash(platforms: dict[str, Any], commit_sha: str, ci_job_id: str) -> str:
    payload = json.dumps(platforms, sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256()
    digest.update(payload.encode("utf-8"))
    digest.update(commit_sha.encode("utf-8"))
    digest.update(ci_job_id.encode("utf-8"))
    return digest.hexdigest()


def resolve_required_test_mode(mode: str, cli_value: str) -> str:
    value = cli_value.strip().lower()
    if value:
        return value
    return "full" if mode == "release" else "smoke"


def run_test_command(command: str, cwd: Path, output_path: Path) -> int:
    rendered = command.replace("{output}", str(output_path))
    print(f"running runtime accessibility test command: {rendered}")
    result = subprocess.run(rendered, cwd=cwd, shell=True, check=False)
    return result.returncode


def validate_payload(
    payload: dict[str, Any],
    mode: str,
    required_test_mode: str,
    allow_fixture: bool,
    allow_smoke_release: bool,
) -> tuple[list[str], dict[str, int]]:
    issues: list[str] = []
    executed_tests = {"ios": 0, "android": 0, "total": 0}
    if payload.get("evidenceType") != "runtime-accessibility-test-results":
        issues.append("evidenceType must be 'runtime-accessibility-test-results'")

    source_mode = str(payload.get("sourceMode", "")).strip()
    if source_mode not in {"test-run", "fixture"}:
        issues.append("sourceMode must be 'test-run' or 'fixture'")

    test_mode = str(payload.get("testMode", "")).strip()
    if test_mode not in {"smoke", "full"}:
        issues.append("testMode must be 'smoke' or 'full'")
    payload_required_test_mode = str(payload.get("requiredTestMode", "")).strip()
    if payload_required_test_mode and payload_required_test_mode not in {"smoke", "full"}:
        issues.append("requiredTestMode must be 'smoke' or 'full' when provided")

    in_ci = os.getenv("GITHUB_ACTIONS", "").lower() == "true"
    if mode == "release" and source_mode != "test-run" and not allow_fixture:
        issues.append("release mode requires sourceMode='test-run' unless --allow-fixture is set")
    if mode == "release" and in_ci and source_mode != "test-run":
        issues.append("release mode in CI requires sourceMode='test-run'")

    if payload_required_test_mode and payload_required_test_mode != required_test_mode:
        if not (
            mode == "release"
            and required_test_mode == "full"
            and payload_required_test_mode == "smoke"
            and allow_smoke_release
        ):
            issues.append(
                "requiredTestMode in payload must match run policy "
                f"(payload='{payload_required_test_mode}', policy='{required_test_mode}')"
            )

    if test_mode and test_mode != required_test_mode:
        if not (mode == "release" and required_test_mode == "full" and test_mode == "smoke" and allow_smoke_release):
            issues.append(
                f"testMode must be '{required_test_mode}' for this run (got '{test_mode}')"
            )
    if mode == "release" and in_ci and required_test_mode == "full" and test_mode != "full":
        issues.append("release mode in CI requires testMode='full'")

    platforms = payload.get("platforms")
    if not isinstance(platforms, dict):
        issues.append("platforms must be an object")
        return issues, executed_tests

    for platform, runner in REQUIRED_RUNNERS.items():
        section = platforms.get(platform)
        if not isinstance(section, dict):
            issues.append(f"platforms.{platform} is required")
            continue

        if section.get("runner") != runner:
            issues.append(f"platforms.{platform}.runner must be '{runner}'")
        test_command = str(section.get("testCommand", "")).strip()
        if not test_command:
            issues.append(f"platforms.{platform}.testCommand is required")
        suite_id = str(section.get("suiteId", "")).strip()
        if not suite_id:
            issues.append(f"platforms.{platform}.suiteId is required")
        executed_count_raw = section.get("executedTestCount")
        if not isinstance(executed_count_raw, int):
            issues.append(f"platforms.{platform}.executedTestCount must be an integer")
            executed_count = 0
        else:
            executed_count = executed_count_raw
        if executed_count <= 0:
            issues.append(f"platforms.{platform}.executedTestCount must be > 0")
        executed_tests[platform] = max(executed_count, 0)

        if test_mode == "full" and "run_visual_accessibility_runtime_test_smoke.py" in test_command:
            issues.append(f"platforms.{platform}.testCommand must not reference smoke runner in full mode")

        scenarios = section.get("scenarios")
        if not isinstance(scenarios, list) or len(scenarios) < 3:
            issues.append(f"platforms.{platform}.scenarios must contain at least 3 entries")
            continue

        flow_ids = {scenario.get("flowId") for scenario in scenarios if isinstance(scenario, dict)}
        for flow in REQUIRED_FLOWS:
            if flow not in flow_ids:
                issues.append(f"platforms.{platform}.scenarios missing flowId '{flow}'")
        scenario_pass_values: list[bool] = []
        for scenario in scenarios:
            if not isinstance(scenario, dict):
                issues.append(f"platforms.{platform}.scenarios entries must be objects")
                continue
            passed = scenario.get("passed")
            if not isinstance(passed, bool):
                issues.append(
                    f"platforms.{platform}.{scenario.get('flowId', 'unknown')}.passed must be boolean"
                )
                continue
            scenario_pass_values.append(passed)
            assertions = scenario.get("assertions", {})
            if not isinstance(assertions, dict):
                issues.append(
                    f"platforms.{platform}.{scenario.get('flowId', 'unknown')}.assertions must be an object"
                )
                continue
            for assertion_name in REQUIRED_ASSERTIONS:
                value = assertions.get(assertion_name)
                if not isinstance(value, bool):
                    issues.append(
                        f"platforms.{platform}.{scenario.get('flowId', 'unknown')}.assertions.{assertion_name} "
                        "must be boolean"
                    )
        all_passed = section.get("allPassed")
        if not isinstance(all_passed, bool):
            issues.append(f"platforms.{platform}.allPassed must be boolean")
        elif scenario_pass_values and all_passed != all(scenario_pass_values):
            issues.append(
                f"platforms.{platform}.allPassed must equal all scenario passed states"
            )

    executed_tests["total"] = executed_tests["ios"] + executed_tests["android"]
    if executed_tests["total"] <= 0:
        issues.append("executed test count total must be > 0")

    return issues, executed_tests


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("pr", "release"), default="release")
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--source", default="")
    parser.add_argument("--fixture", default=DEFAULT_FIXTURE)
    parser.add_argument("--test-command", default="")
    parser.add_argument("--allow-fixture", action="store_true")
    parser.add_argument(
        "--required-test-mode",
        choices=("smoke", "full"),
        default="",
        help="Required evidence quality mode (defaults: pr=smoke, release=full)",
    )
    parser.add_argument(
        "--allow-smoke-release",
        action="store_true",
        help="Allow smoke mode in release for local rehearsals (ignored in CI)",
    )
    parser.add_argument("--commit-sha", default="")
    parser.add_argument("--ci-job-id", default="")
    parser.add_argument("--captured-at", default="")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    output_path = repo_root / args.output
    source_path = repo_root / args.source if args.source else None
    fixture_path = repo_root / args.fixture
    required_test_mode = resolve_required_test_mode(args.mode, args.required_test_mode)

    if args.test_command.strip():
        if source_path is None and output_path.exists():
            output_path.unlink()
        rc = run_test_command(args.test_command.strip(), cwd=repo_root, output_path=output_path)
        if rc != 0:
            print("error: runtime accessibility test command failed")
            return rc

    if source_path is None:
        if output_path.exists():
            source_path = output_path
        elif args.allow_fixture:
            source_path = fixture_path
        else:
            print("error: runtime test results source is required (set --source or --allow-fixture)")
            return 2

    if not source_path.exists():
        print(f"error: runtime test results source file not found: {source_path}")
        return 2

    payload = load_json(source_path)
    source_mode = str(payload.get("sourceMode", "fixture"))
    if source_mode not in {"test-run", "fixture"}:
        print("error: sourceMode must be 'test-run' or 'fixture'")
        return 2

    issues, executed_tests = validate_payload(
        payload=payload,
        mode=args.mode,
        required_test_mode=required_test_mode,
        allow_fixture=args.allow_fixture,
        allow_smoke_release=args.allow_smoke_release,
    )
    if issues:
        print("error: runtime test results payload is invalid")
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

    in_ci = os.getenv("GITHUB_ACTIONS", "").lower() == "true"
    if args.mode == "release" and in_ci and required_test_mode != "full":
        print("error: release mode in CI requires --required-test-mode full")
        return 2
    if args.mode == "release" and in_ci and args.allow_smoke_release:
        print("error: --allow-smoke-release cannot be used in CI")
        return 2

    platforms = payload["platforms"]
    test_mode = str(payload.get("testMode", "")).strip()
    normalized = {
        "reportVersion": str(payload.get("reportVersion", "v1")),
        "evidenceType": "runtime-accessibility-test-results",
        "sourceMode": source_mode,
        "testMode": test_mode,
        "requiredTestMode": required_test_mode,
        "generatedAt": captured_dt.isoformat().replace("+00:00", "Z"),
        "provenance": {
            "commitSha": commit_sha,
            "ciJobId": ci_job_id,
            "capturedAt": captured_at,
            "testBundleHash": compute_test_bundle_hash(platforms, commit_sha, ci_job_id),
        },
        "executedTests": executed_tests,
        "platforms": platforms,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(normalized, indent=2) + "\n", encoding="utf-8")

    print(f"runtime accessibility test results generated: {output_path}")
    print(f"- requiredTestMode: {required_test_mode}")
    print(f"- testMode: {test_mode}")
    print(f"- sourceMode: {source_mode}")
    print(f"- executedTests.total: {executed_tests['total']}")
    print(f"- commitSha: {commit_sha}")
    print(f"- ciJobId: {ci_job_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
