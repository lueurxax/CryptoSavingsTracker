#!/usr/bin/env python3
"""Regression tests for navigation release evidence validator."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class NavigationReleaseEvidenceValidatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[2]
        cls.validator = cls.repo_root / "scripts" / "check_navigation_release_evidence.py"

    def _write_text(self, path: Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def _write_json(self, path: Path, payload: object) -> None:
        self._write_text(path, json.dumps(payload, indent=2) + "\n")

    def _build_schema(self, schema_path: Path) -> None:
        self._write_json(
            schema_path,
            {
                "version": 1,
                "topJourneys": [
                    "goal-create-edit",
                    "monthly-budget-adjust",
                    "destructive-delete-confirmation",
                    "goal-contribution-edit-cancel",
                    "planning-flow-cancel-recovery",
                ],
                "events": [
                    {
                        "name": "nav_flow_started",
                        "requiredProperties": ["journey_id", "platform", "entry_point"],
                    },
                    {
                        "name": "nav_flow_completed",
                        "requiredProperties": ["journey_id", "platform", "duration_ms", "result"],
                    },
                    {
                        "name": "nav_cancelled",
                        "requiredProperties": ["journey_id", "platform", "is_dirty", "cancel_stage"],
                    },
                    {
                        "name": "nav_discard_confirmed",
                        "requiredProperties": ["journey_id", "platform", "form_type"],
                    },
                    {
                        "name": "nav_recovery_completed",
                        "requiredProperties": ["journey_id", "platform", "recovery_path", "success"],
                    },
                ],
            },
        )

    def _build_release_package(
        self,
        release_dir: Path,
        *,
        changed_only: bool = False,
        scanned_count: int = 42,
        include_mod02: bool = True,
        include_hard_cutover: bool = True,
    ) -> None:
        self._write_text(release_dir / "README.md", "# Release\n")
        self._write_text(release_dir / "go-no-go.md", "# Go\n")
        self._write_text(release_dir / "rollback-drill.md", "# Rollback\n")

        if include_mod02:
            self._write_json(
                release_dir / "mod02-diff-report.json",
                {
                    "maxAllowedDiffRatio": 0.02,
                    "scenarios": [
                        {
                            "id": "monthly-budget-adjust-compact",
                            "status": "pass",
                            "diffRatio": 0.0,
                        }
                    ],
                },
            )

        self._write_json(
            release_dir / "policy-report.json",
            {
                "passed": True,
                "issueCount": 0,
                "changedOnly": changed_only,
                "scannedFileCount": scanned_count,
            },
        )
        self._write_json(
            release_dir / "parity-matrix-report.json",
            {
                "passed": True,
                "issueCount": 0,
                "requiredJourneyIds": [
                    "goal-create-edit",
                    "monthly-budget-adjust",
                    "destructive-delete-confirmation",
                    "goal-contribution-edit-cancel",
                    "planning-flow-cancel-recovery",
                ],
            },
        )
        self._write_json(
            release_dir / "guardrails-metrics-report.json",
            {
                "overallStatus": "pass",
                "metrics": {
                    "completion_rate": {"status": "pass"},
                    "cancel_to_retry_rate": {"status": "pass"},
                    "time_to_success_p50": {"status": "pass"},
                    "recovery_success_rate": {"status": "pass"},
                },
            },
        )

        if include_hard_cutover:
            self._write_json(
                release_dir / "hard-cutover-report.json",
                {
                    "passed": True,
                    "issueCount": 0,
                    "scannedFileCount": 128,
                },
            )

    def _run_validator(self, release_dir: Path, schema_path: Path) -> subprocess.CompletedProcess[str]:
        report_out = release_dir / "validator-report.json"
        cmd = [
            sys.executable,
            str(self.validator),
            "--release-dir",
            str(release_dir),
            "--schema",
            str(schema_path),
            "--report-out",
            str(report_out),
        ]
        return subprocess.run(cmd, cwd=self.repo_root, text=True, capture_output=True, check=False)

    def test_validator_passes_with_strict_release_package(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            release_dir = temp / "release"
            schema_path = temp / "schema.json"
            self._build_schema(schema_path)
            self._build_release_package(release_dir)

            result = self._run_validator(release_dir, schema_path)
            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def test_validator_fails_when_policy_report_is_changed_only(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            release_dir = temp / "release"
            schema_path = temp / "schema.json"
            self._build_schema(schema_path)
            self._build_release_package(release_dir, changed_only=True)

            result = self._run_validator(release_dir, schema_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("changedOnly must be false", result.stdout)

    def test_validator_fails_when_scanned_file_count_is_zero(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            release_dir = temp / "release"
            schema_path = temp / "schema.json"
            self._build_schema(schema_path)
            self._build_release_package(release_dir, scanned_count=0)

            result = self._run_validator(release_dir, schema_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("scannedFileCount must be > 0", result.stdout)

    def test_validator_fails_when_mod02_diff_report_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            release_dir = temp / "release"
            schema_path = temp / "schema.json"
            self._build_schema(schema_path)
            self._build_release_package(release_dir, include_mod02=False)

            result = self._run_validator(release_dir, schema_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("mod02-diff-report.json", result.stdout)

    def test_validator_fails_when_hard_cutover_report_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            release_dir = temp / "release"
            schema_path = temp / "schema.json"
            self._build_schema(schema_path)
            self._build_release_package(release_dir, include_hard_cutover=False)

            result = self._run_validator(release_dir, schema_path)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("hard-cutover-report.json", result.stdout)


if __name__ == "__main__":
    unittest.main()
