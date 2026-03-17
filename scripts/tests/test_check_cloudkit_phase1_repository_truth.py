#!/usr/bin/env python3
"""Regression tests for CloudKit Phase 1 repository-truth checker."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class CloudKitPhase1RepositoryTruthTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[2]
        cls.checker = cls.repo_root / "scripts" / "check_cloudkit_phase1_repository_truth.py"

    def _run_checker(self, cwd: Path, report_out: Path) -> subprocess.CompletedProcess[str]:
        cmd = [sys.executable, str(self.checker), "--repo-root", str(cwd), "--report-out", str(report_out)]
        return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, check=False)

    def _seed_docs(self, root: Path, include_release_template: bool = True) -> None:
        for rel in [
            "docs/README.md",
            "docs/ARCHITECTURE.md",
            "docs/CLOUDKIT_MIGRATION_PLAN.md",
            "docs/CLOUDKIT_PHASE1_WORKTREE_EXECUTION_PLAN.md",
            "docs/proposals/cloudkit_qr_multipeer_sync_proposal.md",
            "docs/design/ADR-CK-CUTOVER-001.md",
            "docs/testing/cloudkit-phase1-evidence-checklist.md",
            "docs/runbooks/cloudkit-cutover-release-gate.md",
        ]:
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("", encoding="utf-8")

        (root / "docs/README.md").write_text(
            "CLOUDKIT_MIGRATION_PLAN.md\n"
            "CLOUDKIT_PHASE1_WORKTREE_EXECUTION_PLAN.md\n"
            "design/ADR-CK-CUTOVER-001.md\n"
            "testing/cloudkit-phase1-evidence-checklist.md\n"
            "runbooks/cloudkit-cutover-release-gate.md\n",
            encoding="utf-8",
        )
        (root / "docs/ARCHITECTURE.md").write_text(
            "ADR-CK-CUTOVER-001\nCloudKit Cutover Release Gate Runbook\nCloudKit Phase 1 Evidence Checklist\n",
            encoding="utf-8",
        )
        (root / "docs/CLOUDKIT_MIGRATION_PLAN.md").write_text(
            "ADR-CK-CUTOVER-001\n"
            "testing/cloudkit-phase1-evidence-checklist.md\n"
            "runbooks/cloudkit-cutover-release-gate.md\n"
            "cloud-primary-staging\nrelaunch\ncloudkit-migration-gates.yml\n",
            encoding="utf-8",
        )
        (root / "docs/proposals/cloudkit_qr_multipeer_sync_proposal.md").write_text(
            "CloudKit-disabled staging store\ncloudKitPrimary\napp relaunch\nPhase 1.5\n",
            encoding="utf-8",
        )
        (root / "docs/testing/cloudkit-phase1-evidence-checklist.md").write_text(
            "backup -> diagnostics/repair -> staging copy -> validation -> promotion -> persist mode -> relaunch\n"
            "docs/release/cloudkit/<release-id>/\n",
            encoding="utf-8",
        )
        (root / "docs/runbooks/cloudkit-cutover-release-gate.md").write_text(
            "ADR-CK-CUTOVER-001\ndocs/release/cloudkit/<release-id>/\nPhase 1.5 Readiness Gate\n",
            encoding="utf-8",
        )
        if include_release_template:
            template = root / "docs/release/cloudkit/templates/README.md"
            template.parent.mkdir(parents=True, exist_ok=True)
            template.write_text(
                "go-no-go.md\n"
                "cloudkit-cutover-test-report.md\n"
                "device-migration-log.txt\n"
                "diagnostics-report.json\n"
                "cleanup-verification.md\n",
                encoding="utf-8",
            )

    def test_checker_passes_when_repository_truth_is_wired(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            self._seed_docs(temp)
            result = self._run_checker(temp, temp / "report.json")
            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def test_checker_fails_when_template_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            self._seed_docs(temp, include_release_template=False)
            result = self._run_checker(temp, temp / "report.json")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing required file", result.stdout)


if __name__ == "__main__":
    unittest.main()
