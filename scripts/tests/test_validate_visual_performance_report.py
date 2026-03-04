#!/usr/bin/env python3
"""Tests for visual performance report validator."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class ValidateVisualPerformanceReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[2]
        cls.validator = cls.repo_root / "scripts" / "validate_visual_performance_report.py"
        cls.schema = cls.repo_root / "docs/design/schemas/visual-performance-report.schema.json"

    def _write_json(self, path: Path, payload: object) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    def _run(self, report: Path, out: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(self.validator),
                "--report",
                str(report),
                "--schema",
                str(self.schema),
                "--report-out",
                str(out),
            ],
            cwd=self.repo_root,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_validator_passes_with_valid_thresholds(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            temp = Path(td)
            (temp / "ios16e.txt").write_text("ok\n", encoding="utf-8")
            (temp / "ios17pm.txt").write_text("ok\n", encoding="utf-8")
            (temp / "pixel8.txt").write_text("ok\n", encoding="utf-8")
            report = temp / "performance-report.json"
            out = temp / "out.json"
            self._write_json(
                report,
                {
                    "reportVersion": "v1",
                    "evidenceType": "visual-performance-report",
                    "wave": "wave1",
                    "evaluatedAt": "2026-03-04",
                    "baseline": {"p95FrameTimeMs": 20.0, "jankRatePercent": 2.0},
                    "current": {"p95FrameTimeMs": 21.0, "jankRatePercent": 3.5},
                    "deltas": {
                        "p95RegressionPercent": 5.0,
                        "jankDeltaPercentagePoints": 1.5,
                    },
                    "thresholds": {
                        "p95RegressionMaxPercent": 10.0,
                        "jankDeltaMaxPercentagePoints": 2.0,
                    },
                    "traces": [
                        {
                            "platform": "ios",
                            "device": "iPhone 16e",
                            "tool": "Instruments",
                            "artifactRef": str(temp / "ios16e.txt"),
                        },
                        {
                            "platform": "ios",
                            "device": "iPhone 17 Pro Max",
                            "tool": "Instruments",
                            "artifactRef": str(temp / "ios17pm.txt"),
                        },
                        {
                            "platform": "android",
                            "device": "Pixel 8",
                            "tool": "Macrobenchmark",
                            "artifactRef": str(temp / "pixel8.txt"),
                        },
                    ],
                },
            )
            result = self._run(report, out)
            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def test_validator_fails_on_threshold_breach(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            temp = Path(td)
            (temp / "ios16e.txt").write_text("ok\n", encoding="utf-8")
            (temp / "ios17pm.txt").write_text("ok\n", encoding="utf-8")
            (temp / "pixel8.txt").write_text("ok\n", encoding="utf-8")
            report = temp / "performance-report.json"
            out = temp / "out.json"
            self._write_json(
                report,
                {
                    "reportVersion": "v1",
                    "evidenceType": "visual-performance-report",
                    "wave": "wave1",
                    "evaluatedAt": "2026-03-04",
                    "baseline": {"p95FrameTimeMs": 20.0, "jankRatePercent": 1.0},
                    "current": {"p95FrameTimeMs": 24.0, "jankRatePercent": 4.1},
                    "deltas": {
                        "p95RegressionPercent": 20.0,
                        "jankDeltaPercentagePoints": 3.1,
                    },
                    "thresholds": {
                        "p95RegressionMaxPercent": 10.0,
                        "jankDeltaMaxPercentagePoints": 2.0,
                    },
                    "traces": [
                        {
                            "platform": "ios",
                            "device": "iPhone 16e",
                            "tool": "Instruments",
                            "artifactRef": str(temp / "ios16e.txt"),
                        },
                        {
                            "platform": "ios",
                            "device": "iPhone 17 Pro Max",
                            "tool": "Instruments",
                            "artifactRef": str(temp / "ios17pm.txt"),
                        },
                        {
                            "platform": "android",
                            "device": "Pixel 8",
                            "tool": "Macrobenchmark",
                            "artifactRef": str(temp / "pixel8.txt"),
                        },
                    ],
                },
            )
            result = self._run(report, out)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("threshold breached", result.stdout)


if __name__ == "__main__":
    unittest.main()
