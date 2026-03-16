#!/usr/bin/env python3
"""Regression tests for runtime persistence-controller checker."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class RuntimePersistenceControllerCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[2]
        cls.checker = cls.repo_root / "scripts" / "check_runtime_persistence_controller.py"

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

    def test_checker_passes_for_persistence_controller_runtime_code(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            runtime_root = temp / "ios"
            runtime_root.mkdir(parents=True)

            (runtime_root / "DashboardView.swift").write_text(
                "let container = PersistenceController.shared.activeContainer\n",
                encoding="utf-8",
            )
            (runtime_root / "DashboardViewPreview.swift").write_text(
                "let container = CryptoSavingsTrackerApp.sharedModelContainer\n",
                encoding="utf-8",
            )

            result = self._run_checker(
                roots=[runtime_root],
                report_out=temp / "runtime-persistence-controller-report.json",
            )
            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def test_checker_fails_on_runtime_shared_model_container_reference(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            runtime_root = temp / "ios"
            runtime_root.mkdir(parents=True)

            (runtime_root / "DashboardView.swift").write_text(
                "let context = CryptoSavingsTrackerApp.sharedModelContainer.mainContext\n",
                encoding="utf-8",
            )

            result = self._run_checker(
                roots=[runtime_root],
                report_out=temp / "runtime-persistence-controller-report.json",
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("sharedModelContainer", result.stdout)


if __name__ == "__main__":
    unittest.main()
