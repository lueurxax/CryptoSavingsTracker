#!/usr/bin/env python3
"""Validate state coverage matrix for release-blocking visual components."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


REQUIRED_STATES = [
    "default",
    "pressed",
    "disabled",
    "error",
    "loading",
    "empty",
    "stale",
    "recovery",
]
REQUIRED_PLATFORMS = ["ios", "android"]
VALID_STATUS = {"planned", "captured"}
PHASES = ("design-complete", "qa-complete", "release-candidate")
PHASE_CAPTURE_STATES = {
    "design-complete": [],
    "qa-complete": ["default", "error", "loading", "recovery"],
    "release-candidate": REQUIRED_STATES,
}


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def resolve_phase(strict: bool, phase: str | None) -> str:
    if strict:
        if phase is not None and phase != "release-candidate":
            raise ValueError("--strict cannot be combined with --phase other than release-candidate")
        return "release-candidate"
    if phase is None:
        return "design-complete"
    return phase


def validate_matrix(
    matrix: dict[str, Any],
    phase: str,
    require_artifact_files: bool,
    repo_root: Path,
) -> list[str]:
    issues: list[str] = []

    if matrix.get("requiredStates") != REQUIRED_STATES:
        issues.append("requiredStates must exactly match canonical state list")

    components = matrix.get("components", {})
    release_blocking = matrix.get("releaseBlockingComponents", [])

    required_capture_states = set(PHASE_CAPTURE_STATES[phase])

    for component in release_blocking:
        if component not in components:
            issues.append(f"missing component definition: {component}")
            continue

        component_cfg = components[component]
        for platform in REQUIRED_PLATFORMS:
            if platform not in component_cfg:
                issues.append(f"{component}: missing platform {platform}")
                continue

            platform_cfg = component_cfg[platform]
            for state in REQUIRED_STATES:
                if state not in platform_cfg:
                    issues.append(f"{component}.{platform}: missing state {state}")
                    continue

                state_cfg = platform_cfg[state]
                status = state_cfg.get("status")
                artifact = state_cfg.get("artifactRef", "")

                if status not in VALID_STATUS:
                    issues.append(f"{component}.{platform}.{state}: invalid status '{status}'")
                if not artifact:
                    issues.append(f"{component}.{platform}.{state}: empty artifactRef")
                    continue

                if state in required_capture_states and status != "captured":
                    issues.append(
                        f"{component}.{platform}.{state}: phase '{phase}' requires captured status"
                    )

                if status == "captured" and artifact.startswith("planned://"):
                    issues.append(
                        f"{component}.{platform}.{state}: captured status cannot use planned artifactRef"
                    )

                if require_artifact_files and status == "captured":
                    artifact_path = Path(artifact)
                    if not artifact_path.is_absolute():
                        artifact_path = repo_root / artifact_path
                    if not artifact_path.exists():
                        issues.append(
                            f"{component}.{platform}.{state}: captured artifact file not found: {artifact}"
                        )
                    elif not artifact_path.is_file():
                        issues.append(
                            f"{component}.{platform}.{state}: captured artifact path is not a file: {artifact}"
                        )

    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--matrix",
        default="docs/design/visual-state-matrix.v1.json",
        help="Path to state matrix JSON",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Deprecated alias for --phase release-candidate",
    )
    parser.add_argument(
        "--phase",
        choices=PHASES,
        help=(
            "Validation phase: design-complete (structure), qa-complete (core states captured), "
            "release-candidate (all states captured)"
        ),
    )
    parser.add_argument(
        "--require-artifact-files",
        action="store_true",
        help="Require captured artifactRef paths to exist as files in the repository",
    )
    parser.add_argument(
        "--report-out",
        help="Optional JSON report output path",
    )
    args = parser.parse_args()

    matrix_path = Path(args.matrix)
    if not matrix_path.exists():
        print(f"error: matrix file not found: {matrix_path}")
        return 2

    try:
        phase = resolve_phase(strict=args.strict, phase=args.phase)
    except ValueError as exc:
        print(f"error: {exc}")
        return 2

    repo_root = Path(__file__).resolve().parent.parent
    matrix = load_json(matrix_path)
    issues = validate_matrix(
        matrix,
        phase=phase,
        require_artifact_files=args.require_artifact_files,
        repo_root=repo_root,
    )

    if args.report_out:
        report_path = Path(args.report_out)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report = {
            "matrixPath": str(matrix_path),
            "phase": phase,
            "requireArtifactFiles": args.require_artifact_files,
            "passed": len(issues) == 0,
            "issueCount": len(issues),
            "issues": issues,
        }
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if issues:
        print("visual state matrix validation failed:")
        for issue in issues:
            print(f"- {issue}")
        return 1

    print(f"visual state matrix validation passed (phase: {phase})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
