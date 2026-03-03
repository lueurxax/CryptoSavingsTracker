#!/usr/bin/env python3
"""Regression tests for hard-cutover checker."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class NavigationHardCutoverCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[2]
        cls.checker = cls.repo_root / "scripts" / "check_navigation_hard_cutover.py"

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

    def test_checker_passes_without_legacy_patterns(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            ios_root = temp / "ios"
            android_root = temp / "android"
            ios_root.mkdir(parents=True)
            android_root.mkdir(parents=True)

            (ios_root / "ContentView.swift").write_text(
                "struct ContentView { let title = \"Navigation\" }\n",
                encoding="utf-8",
            )
            (android_root / "Dashboard.kt").write_text(
                "fun dashboard() { println(\"ok\") }\n",
                encoding="utf-8",
            )

            result = self._run_checker(
                roots=[ios_root, android_root],
                report_out=temp / "hard-cutover-report.json",
            )
            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def test_checker_fails_on_migration_enabled_branching(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            src_root = temp / "src"
            src_root.mkdir(parents=True)
            (src_root / "MonthlyPlanningScreen.kt").write_text(
                "if (migrationEnabled) { println(\"legacy\") }\n",
                encoding="utf-8",
            )

            result = self._run_checker(
                roots=[src_root],
                report_out=temp / "hard-cutover-report.json",
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("migrationEnabled", result.stdout)


if __name__ == "__main__":
    unittest.main()
