#!/usr/bin/env python3
"""Regression tests for CloudKit release-evidence checker."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class CloudKitReleaseEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[2]
        cls.checker = cls.repo_root / "scripts" / "check_cloudkit_release_evidence.py"

    def _run_checker(self, cwd: Path, release_dir: Path, report_out: Path) -> subprocess.CompletedProcess[str]:
        cmd = [
            sys.executable,
            str(self.checker),
            "--repo-root",
            str(cwd),
            "--release-dir",
            str(release_dir),
            "--report-out",
            str(report_out),
        ]
        return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, check=False)

    def _seed_release_dir(self, root: Path) -> Path:
        release_dir = root / "docs/release/cloudkit/latest"
        release_dir.mkdir(parents=True, exist_ok=True)
        (release_dir / "README.md").write_text(
            "ADR-CK-CUTOVER-001\nCloudKit Phase 1 Evidence Checklist\nCloudKit Cutover Release Gate Runbook\n",
            encoding="utf-8",
        )
        (release_dir / "go-no-go.md").write_text(
            "Preflight fail-closed is confirmed\n"
            "Staging copy + validation + promotion flow is confirmed\n"
            "Relaunch activates cloud runtime deterministically\n"
            "No sqlite API-violation warnings\n"
            "commit abc1234\n",
            encoding="utf-8",
        )
        (release_dir / "cloudkit-cutover-test-report.md").write_text("tests\n", encoding="utf-8")
        (release_dir / "device-migration-log.txt").write_text(
            "Validation passed: all 513 source records present in target\n"
            "CloudKit migration completed successfully\n",
            encoding="utf-8",
        )
        (release_dir / "cleanup-verification.md").write_text(
            "cloud-primary\ncloud-primary-staging\nNo sqlite API-violation warnings\n",
            encoding="utf-8",
        )
        (release_dir / "diagnostics-report.json").write_text(
            json.dumps(
                {
                    "isReady": True,
                    "entityCounts": [{"name": "Goal", "count": 1}],
                    "allocationHistory": {"total": 0},
                    "blockerSummary": [],
                }
            ) + "\n",
            encoding="utf-8",
        )
        return release_dir

    def test_checker_passes_for_valid_release_package(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            release_dir = self._seed_release_dir(temp)
            result = self._run_checker(temp, release_dir.relative_to(temp), temp / "report.json")
            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def test_checker_fails_for_missing_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            release_dir = self._seed_release_dir(temp)
            (release_dir / "cleanup-verification.md").unlink()
            result = self._run_checker(temp, release_dir.relative_to(temp), temp / "report.json")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing required release artifact", result.stdout)


if __name__ == "__main__":
    unittest.main()
