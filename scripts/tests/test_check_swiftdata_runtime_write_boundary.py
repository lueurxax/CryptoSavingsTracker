#!/usr/bin/env python3
"""Regression tests for SwiftData runtime write-boundary checker."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class SwiftDataRuntimeWriteBoundaryCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[2]
        cls.checker = cls.repo_root / "scripts" / "check_swiftdata_runtime_write_boundary.py"

    def _run_checker(self, roots: list[Path], report_out: Path) -> subprocess.CompletedProcess[str]:
        cmd = [
            sys.executable,
            str(self.checker),
            "--roots",
            *[str(root) for root in roots],
            "--report-out",
            str(report_out),
        ]
        return subprocess.run(cmd, cwd=self.repo_root, text=True, capture_output=True, check=False)

    def test_checker_passes_for_service_calls_and_preview_exclusion(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            views_root = temp / "Views"
            views_root.mkdir(parents=True)

            (views_root / "AddGoalView.swift").write_text(
                "struct AddGoalView { func save() { try? service.createGoal(goal) } }\n",
                encoding="utf-8",
            )
            (views_root / "AddGoalViewPreview.swift").write_text(
                "struct Preview { func seed() { modelContext.insert(goal) } }\n",
                encoding="utf-8",
            )

            result = self._run_checker(
                roots=[views_root],
                report_out=temp / "swiftdata-write-boundary-report.json",
            )
            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def test_checker_fails_on_runtime_modelcontext_save(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            viewmodels_root = temp / "ViewModels"
            viewmodels_root.mkdir(parents=True)

            (viewmodels_root / "GoalEditViewModel.swift").write_text(
                "final class GoalEditViewModel { func save() { try modelContext.save() } }\n",
                encoding="utf-8",
            )

            result = self._run_checker(
                roots=[viewmodels_root],
                report_out=temp / "swiftdata-write-boundary-report.json",
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("GoalEditViewModel.swift", result.stdout)
            self.assertIn("modelContext.save()", result.stdout)


if __name__ == "__main__":
    unittest.main()
