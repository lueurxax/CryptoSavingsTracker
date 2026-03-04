#!/usr/bin/env python3
"""Deterministic snapshot/state gate entrypoint for visual system proposal."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

VALID_IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}
REQUIRED_PRODUCTION_FLOWS = ("planning", "dashboard", "settings")
REQUIRED_PRODUCTION_STATES = ("default", "error", "recovery")
DEFAULT_BASELINE_PATH = "docs/design/visual-snapshot-baseline.v1.json"
DEFAULT_PRODUCTION_MANIFEST_PATH = "docs/screenshots/review-visual-system-unification-r4/production/manifest.v1.json"
DEFAULT_DUPLICATE_THRESHOLD = 0.20
COMPONENT_POLICY_REQUIREMENTS = {
    "planning.header_card": {"surfaceRole": "surface.base", "elevationRole": "elevation.card"},
    "planning.goal_row": {"surfaceRole": "surface.base"},
    "dashboard.summary_card": {"surfaceRole": "surface.base", "elevationRole": "elevation.card"},
    "settings.section_row": {"surfaceRole": "surface.base"},
}


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


def sha256_for_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def collect_captured_artifacts(
    matrix: dict[str, Any],
    repo_root: Path,
) -> list[dict[str, Any]]:
    artifacts: list[dict[str, Any]] = []
    components = matrix.get("components", {})
    release_components = matrix.get("releaseBlockingComponents", [])
    required_states = matrix.get("requiredStates", [])

    for component in release_components:
        component_cfg = components.get(component, {})
        for platform in ("ios", "android"):
            platform_cfg = component_cfg.get(platform, {})
            for state in required_states:
                state_cfg = platform_cfg.get(state, {})
                if state_cfg.get("status") != "captured":
                    continue
                artifact_ref = state_cfg.get("artifactRef", "")
                artifact_path = Path(artifact_ref)
                if not artifact_path.is_absolute():
                    artifact_path = repo_root / artifact_path
                artifacts.append(
                    {
                        "component": component,
                        "platform": platform,
                        "state": state,
                        "artifactRef": artifact_ref,
                        "artifactPath": artifact_path,
                    }
                )
    return artifacts


def collect_snapshot_issues(matrix: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    components = matrix.get("components", {})
    release_components = matrix.get("releaseBlockingComponents", [])
    required_states = matrix.get("requiredStates", [])

    for component in release_components:
        component_cfg = components.get(component, {})
        for platform in ("ios", "android"):
            platform_cfg = component_cfg.get(platform, {})
            for state in required_states:
                state_cfg = platform_cfg.get(state, {})
                status = state_cfg.get("status")
                artifact_ref = state_cfg.get("artifactRef", "")
                if status != "captured":
                    continue
                if artifact_ref.startswith("planned://"):
                    issues.append(
                        f"{component}.{platform}.{state}: captured status cannot use planned artifactRef"
                    )
                    continue
                suffix = Path(artifact_ref).suffix.lower()
                if suffix and suffix not in VALID_IMAGE_EXTENSIONS:
                    issues.append(
                        f"{component}.{platform}.{state}: unsupported captured artifact extension '{suffix}'"
                    )

    return issues


def count_statuses(matrix: dict[str, Any]) -> dict[str, int]:
    counts = {"planned": 0, "captured": 0}
    components = matrix.get("components", {})
    release_components = matrix.get("releaseBlockingComponents", [])
    required_states = matrix.get("requiredStates", [])

    for component in release_components:
        component_cfg = components.get(component, {})
        for platform in ("ios", "android"):
            platform_cfg = component_cfg.get(platform, {})
            for state in required_states:
                status = platform_cfg.get(state, {}).get("status")
                if status in counts:
                    counts[status] += 1
    return counts


def write_baseline(
    artifacts: list[dict[str, Any]],
    baseline_path: Path,
) -> None:
    payload = {
        "baselineVersion": "v1",
        "generatedAt": date.today().isoformat(),
        "artifactCount": len(artifacts),
        "artifacts": sorted(
            [
                {
                    "component": item["component"],
                    "platform": item["platform"],
                    "state": item["state"],
                    "artifactRef": item["artifactRef"],
                    "sha256": sha256_for_file(item["artifactPath"]),
                }
                for item in artifacts
            ],
            key=lambda x: x["artifactRef"],
        ),
    }
    baseline_path.parent.mkdir(parents=True, exist_ok=True)
    baseline_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def check_baseline_diff(
    artifacts: list[dict[str, Any]],
    baseline_path: Path,
) -> tuple[list[str], dict[str, Any]]:
    if not baseline_path.exists():
        return [f"snapshot baseline file not found: {baseline_path}"], {}

    baseline_payload = load_json(baseline_path)
    baseline_entries = baseline_payload.get("artifacts", [])
    baseline_hashes = {entry.get("artifactRef"): entry.get("sha256") for entry in baseline_entries}

    issues: list[str] = []
    changed: list[str] = []
    missing_in_baseline: list[str] = []
    checked = 0
    for item in artifacts:
        artifact_ref = item["artifactRef"]
        artifact_path = item["artifactPath"]
        expected = baseline_hashes.get(artifact_ref)
        if expected is None:
            missing_in_baseline.append(artifact_ref)
            continue
        if not artifact_path.exists():
            issues.append(f"snapshot artifact missing during baseline diff: {artifact_ref}")
            continue
        checked += 1
        actual = sha256_for_file(artifact_path)
        if actual != expected:
            changed.append(artifact_ref)

    if missing_in_baseline:
        issues.append(
            f"baseline missing {len(missing_in_baseline)} captured artifacts (example: {missing_in_baseline[0]})"
        )
    if changed:
        issues.append(
            f"baseline diff detected {len(changed)} changed artifacts (example: {changed[0]})"
        )

    summary = {
        "checkedArtifacts": checked,
        "changedArtifacts": len(changed),
        "missingInBaseline": len(missing_in_baseline),
        "changedArtifactRefs": changed,
        "missingArtifactRefs": missing_in_baseline,
    }
    return issues, summary


def check_duplicate_ratio(
    artifacts: list[dict[str, Any]],
    threshold: float,
) -> tuple[list[str], dict[str, Any]]:
    issues: list[str] = []
    by_platform: dict[str, list[dict[str, Any]]] = {"ios": [], "android": []}
    for item in artifacts:
        by_platform.setdefault(item["platform"], []).append(item)

    summary: dict[str, Any] = {"threshold": threshold, "platforms": {}}
    for platform, items in by_platform.items():
        if not items:
            summary["platforms"][platform] = {
                "totalFiles": 0,
                "uniqueHashes": 0,
                "duplicateFiles": 0,
                "duplicateRatio": 0.0,
                "largestDuplicateGroup": 0,
            }
            continue

        groups: dict[str, list[str]] = {}
        for item in items:
            digest = sha256_for_file(item["artifactPath"])
            groups.setdefault(digest, []).append(item["artifactRef"])

        total = len(items)
        unique = len(groups)
        duplicate_files = total - unique
        ratio = duplicate_files / total if total else 0.0
        largest_group = max((len(v) for v in groups.values()), default=0)
        summary["platforms"][platform] = {
            "totalFiles": total,
            "uniqueHashes": unique,
            "duplicateFiles": duplicate_files,
            "duplicateRatio": ratio,
            "largestDuplicateGroup": largest_group,
        }
        if ratio > threshold:
            issues.append(
                f"{platform} snapshot duplicate ratio {ratio:.3f} exceeds threshold {threshold:.3f}"
            )
    return issues, summary


def check_policy_conformance(
    matrix: dict[str, Any],
    tokens: dict[str, Any],
) -> tuple[list[str], dict[str, Any]]:
    issues: list[str] = []
    roles = tokens.get("roles", {})
    release_components = matrix.get("releaseBlockingComponents", [])

    component_summary: dict[str, Any] = {}
    for component in release_components:
        req = COMPONENT_POLICY_REQUIREMENTS.get(component, {})
        component_issues: list[str] = []
        checks: dict[str, Any] = {}

        surface_role = req.get("surfaceRole")
        if surface_role:
            role_cfg = roles.get(surface_role)
            ok = bool(role_cfg and component in role_cfg.get("componentScope", []))
            checks["surfaceRole"] = {"required": surface_role, "passed": ok}
            if not ok:
                component_issues.append(
                    f"{component}: required surface role '{surface_role}' missing component scope"
                )

        elevation_role = req.get("elevationRole")
        if elevation_role:
            role_cfg = roles.get(elevation_role)
            ok = bool(role_cfg and component in role_cfg.get("componentScope", []))
            checks["elevationRole"] = {"required": elevation_role, "passed": ok}
            if not ok:
                component_issues.append(
                    f"{component}: required elevation role '{elevation_role}' missing component scope"
                )

        if component_issues:
            issues.extend(component_issues)
        component_summary[component] = {
            "passed": len(component_issues) == 0,
            "checks": checks,
            "issues": component_issues,
        }

    return issues, component_summary


def check_production_evidence_manifest(
    repo_root: Path,
    manifest_path: Path,
    max_age_hours: float,
) -> tuple[list[str], dict[str, Any]]:
    if not manifest_path.exists():
        return [f"production evidence manifest not found: {manifest_path}"], {}

    manifest = load_json(manifest_path)
    issues: list[str] = []
    if manifest.get("captureMode") != "production-flow":
        issues.append("production manifest captureMode must be 'production-flow'")

    evidence_commit_sha = str(manifest.get("evidenceCommitSha", "")).strip().lower()
    captured_at_raw = str(manifest.get("capturedAt", "")).strip()
    captured_age_hours: float | None = None
    if not evidence_commit_sha:
        issues.append("production manifest evidenceCommitSha is required")
    elif not re.fullmatch(r"[0-9a-f]{7,40}", evidence_commit_sha):
        issues.append("production manifest evidenceCommitSha must be lowercase hex SHA")
    if not captured_at_raw:
        issues.append("production manifest capturedAt is required")

    if captured_at_raw:
        try:
            captured_at = datetime.fromisoformat(captured_at_raw.replace("Z", "+00:00"))
            if captured_at.tzinfo is None:
                issues.append("production manifest capturedAt must include timezone")
            else:
                now_utc = datetime.now(timezone.utc)
                if captured_at > now_utc:
                    issues.append("production manifest capturedAt cannot be in the future")
                else:
                    captured_age_hours = (now_utc - captured_at).total_seconds() / 3600.0
                    if max_age_hours > 0 and captured_age_hours > max_age_hours:
                        issues.append(
                            "production manifest capturedAt is stale: "
                            f"{captured_age_hours:.2f}h > max {max_age_hours:.2f}h"
                        )
        except ValueError:
            issues.append("production manifest capturedAt must be ISO-8601 timestamp")

    expected_sha = os.getenv("GITHUB_SHA", "").strip().lower()
    if expected_sha and evidence_commit_sha:
        if evidence_commit_sha != expected_sha and evidence_commit_sha != expected_sha[: len(evidence_commit_sha)]:
            issues.append("production manifest evidenceCommitSha does not match current GITHUB_SHA")

    flow_entries = manifest.get("requiredFlows", [])
    flow_map = {entry.get("flowId"): entry for entry in flow_entries if isinstance(entry, dict)}

    summary: dict[str, Any] = {
        "flowCount": len(flow_map),
        "requiredStates": list(REQUIRED_PRODUCTION_STATES),
        "evidenceCommitSha": evidence_commit_sha,
        "capturedAt": captured_at_raw,
        "capturedAgeHours": captured_age_hours,
        "maxAllowedAgeHours": max_age_hours,
        "flows": {},
    }
    for flow_id in REQUIRED_PRODUCTION_FLOWS:
        entry = flow_map.get(flow_id)
        if entry is None:
            issues.append(f"production manifest missing required flow: {flow_id}")
            continue

        route_id = entry.get("routeId", "")
        required_states = entry.get("requiredStates", [])
        state_entries = entry.get("states", [])
        state_map = {
            state_entry.get("stateId"): state_entry
            for state_entry in state_entries
            if isinstance(state_entry, dict)
        }

        flow_issues: list[str] = []
        if not route_id:
            flow_issues.append("routeId is required")
        if list(required_states) != list(REQUIRED_PRODUCTION_STATES):
            flow_issues.append(
                f"requiredStates must exactly match {list(REQUIRED_PRODUCTION_STATES)}"
            )

        for state_id in REQUIRED_PRODUCTION_STATES:
            state_entry = state_map.get(state_id)
            if state_entry is None:
                flow_issues.append(f"missing state entry: {state_id}")
                continue
            for platform in ("ios", "android"):
                artifact_ref = state_entry.get(f"{platform}Artifact", "")
                if not artifact_ref:
                    flow_issues.append(f"{state_id}.{platform}Artifact is required")
                    continue
                suffix = Path(artifact_ref).suffix.lower()
                if suffix not in VALID_IMAGE_EXTENSIONS:
                    flow_issues.append(
                        f"{state_id}.{platform}Artifact has unsupported extension '{suffix}'"
                    )
                    continue
                artifact_path = Path(artifact_ref)
                if not artifact_path.is_absolute():
                    artifact_path = repo_root / artifact_path
                if not artifact_path.exists():
                    flow_issues.append(f"{state_id}.{platform}Artifact file not found: {artifact_ref}")

        if flow_issues:
            issues.extend([f"{flow_id}: {issue}" for issue in flow_issues])
        summary["flows"][flow_id] = {"passed": len(flow_issues) == 0, "issues": flow_issues}

    return issues, summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", default="docs/design/visual-state-matrix.v1.json")
    parser.add_argument("--tokens", default="docs/design/visual-tokens.v1.json")
    parser.add_argument("--mode", choices=("pr", "release"), default="pr")
    parser.add_argument("--baseline", default=DEFAULT_BASELINE_PATH)
    parser.add_argument("--production-manifest", default=DEFAULT_PRODUCTION_MANIFEST_PATH)
    parser.add_argument(
        "--duplicate-threshold",
        type=float,
        default=DEFAULT_DUPLICATE_THRESHOLD,
        help="Fail when duplicate image ratio exceeds this threshold in release mode",
    )
    parser.add_argument(
        "--update-baseline",
        action="store_true",
        help="Rewrite snapshot baseline hashes from current captured artifacts",
    )
    parser.add_argument(
        "--report-out",
        default="artifacts/visual-system/snapshot-report.json",
        help="Path to write JSON report",
    )
    parser.add_argument(
        "--production-max-age-hours",
        type=float,
        default=24.0,
        help="Maximum allowed age of production manifest capturedAt in release mode (<=0 disables).",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    matrix_path = repo_root / args.matrix
    tokens_path = repo_root / args.tokens
    baseline_path = repo_root / args.baseline
    production_manifest_path = repo_root / args.production_manifest
    if not matrix_path.exists():
        print(f"error: matrix file not found: {matrix_path}")
        return 2

    matrix = load_json(matrix_path)
    phase = "design-complete" if args.mode == "pr" else "release-candidate"
    require_artifact_files = args.mode == "release"

    issues: list[str] = []
    validator_code, validator_output = run_state_validator(
        repo_root=repo_root,
        phase=phase,
        require_artifact_files=require_artifact_files,
    )
    validator_lines = [line for line in validator_output.splitlines() if line]
    if validator_code != 0:
        issues.append(f"state-matrix-validator failed for phase '{phase}'")
        issues.extend([f"validator: {line}" for line in validator_lines])

    issues.extend(collect_snapshot_issues(matrix))
    counts = count_statuses(matrix)
    artifacts = collect_captured_artifacts(matrix=matrix, repo_root=repo_root)

    if not tokens_path.exists():
        issues.append(f"token contract file not found: {tokens_path}")
        policy_issues: list[str] = []
        policy_summary: dict[str, Any] = {}
    else:
        tokens = load_json(tokens_path)
        policy_issues, policy_summary = check_policy_conformance(matrix=matrix, tokens=tokens)
        issues.extend(policy_issues)

    if args.update_baseline:
        write_baseline(artifacts=artifacts, baseline_path=baseline_path)

    baseline_summary: dict[str, Any] = {}
    duplicate_summary: dict[str, Any] = {}
    production_summary: dict[str, Any] = {}

    if args.mode == "release":
        baseline_issues, baseline_summary = check_baseline_diff(artifacts=artifacts, baseline_path=baseline_path)
        duplicate_issues, duplicate_summary = check_duplicate_ratio(
            artifacts=artifacts,
            threshold=args.duplicate_threshold,
        )
        production_issues, production_summary = check_production_evidence_manifest(
            repo_root=repo_root,
            manifest_path=production_manifest_path,
            max_age_hours=args.production_max_age_hours,
        )
        issues.extend(baseline_issues)
        issues.extend(duplicate_issues)
        issues.extend(production_issues)

    report = {
        "mode": args.mode,
        "phase": phase,
        "matrixPath": args.matrix,
        "tokensPath": args.tokens,
        "baselinePath": args.baseline,
        "productionManifestPath": args.production_manifest,
        "baselineUpdated": args.update_baseline,
        "passed": len(issues) == 0,
        "issueCount": len(issues),
        "statusCounts": counts,
        "capturedArtifactCount": len(artifacts),
        "validatorOutput": validator_lines,
        "policyConformance": policy_summary,
        "baselineDiffSummary": baseline_summary,
        "duplicateSummary": duplicate_summary,
        "productionEvidenceSummary": production_summary,
        "issues": issues,
    }

    report_path = repo_root / args.report_out
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("visual snapshot checks failed:")
        for issue in issues:
            print(f"- {issue}")
        print(f"report: {report_path}")
        return 1

    print("visual snapshot checks passed")
    if args.update_baseline:
        print(f"baseline updated: {baseline_path}")
    print(f"report: {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
