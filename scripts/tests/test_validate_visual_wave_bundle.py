#!/usr/bin/env python3
"""Tests for visual wave bundle validator."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class ValidateVisualWaveBundleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[2]
        cls.validator = cls.repo_root / "scripts" / "validate_visual_wave_bundle.py"

    def _write_json(self, path: Path, payload: object) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    def _write_text(self, path: Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def _build_wave_bundle(self, wave_dir: Path) -> None:
        required_markdown = [
            "token-parity-report.md",
            "state-coverage-report.md",
            "snapshot-diff-summary.md",
            "accessibility-report.md",
            "ux-metrics-report.md",
            "performance-report.md",
            "rollback-drill-report.md",
            "release-certification-summary.md",
        ]
        for name in required_markdown:
            self._write_text(wave_dir / name, "# ok\n")

        self._write_json(
            wave_dir / "release-certification-report.json",
            {"releaseCertifiable": True},
        )
        self._write_json(
            wave_dir / "runtime-accessibility-test-results.json",
            {
                "testMode": "full",
                "requiredTestMode": "full",
                "sourceMode": "test-run",
                "executedTests": {"ios": 3, "android": 3, "total": 6},
                "platforms": {
                    "ios": {"suiteId": "visual-accessibility-full-ios"},
                    "android": {"suiteId": "visual-accessibility-full-android"},
                },
            },
        )
        self._write_json(
            wave_dir / "runtime-accessibility-assertions.json",
            {
                "source": {
                    "testResultsPath": str(wave_dir / "runtime-accessibility-test-results.json"),
                    "testMode": "full",
                    "requiredTestMode": "full",
                }
            },
        )
        self._write_json(
            wave_dir / "ux-metrics-report.json",
            {
                "wave": "wave1",
                "evaluatedAt": "2026-03-04",
                "sample": {"participants": 14, "scenarioTasks": 72},
                "confidence": {"levelPercent": 95},
                "metrics": {
                    "statusComprehensionTime": {
                        "p50Seconds": 10.0,
                        "improvementVsBaselinePercent": 20.0,
                    },
                    "shortfallActionAccuracy": {
                        "percent": 96.0,
                        "wilsonInterval95": {"low": 89.0, "high": 99.0},
                    },
                    "warningMisinterpretationRate": {
                        "percent": 3.0,
                        "wilsonInterval95": {"low": 1.0, "high": 8.0},
                    },
                },
            },
        )

        trace_ios_16e = wave_dir / "trace-ios-16e.txt"
        trace_ios_17pm = wave_dir / "trace-ios-17pm.txt"
        trace_android = wave_dir / "trace-android-pixel8.txt"
        self._write_text(trace_ios_16e, "ok\n")
        self._write_text(trace_ios_17pm, "ok\n")
        self._write_text(trace_android, "ok\n")

        self._write_json(
            wave_dir / "performance-report.json",
            {
                "reportVersion": "v1",
                "evidenceType": "visual-performance-report",
                "wave": "wave1",
                "evaluatedAt": "2026-03-04",
                "baseline": {"p95FrameTimeMs": 20.0, "jankRatePercent": 2.0},
                "current": {"p95FrameTimeMs": 21.0, "jankRatePercent": 3.0},
                "deltas": {"p95RegressionPercent": 5.0, "jankDeltaPercentagePoints": 1.0},
                "thresholds": {"p95RegressionMaxPercent": 10.0, "jankDeltaMaxPercentagePoints": 2.0},
                "traces": [
                    {
                        "platform": "ios",
                        "device": "iPhone 16e",
                        "tool": "Instruments",
                        "artifactRef": str(trace_ios_16e),
                    },
                    {
                        "platform": "ios",
                        "device": "iPhone 17 Pro Max",
                        "tool": "Instruments",
                        "artifactRef": str(trace_ios_17pm),
                    },
                    {
                        "platform": "android",
                        "device": "Pixel 8",
                        "tool": "Macrobenchmark",
                        "artifactRef": str(trace_android),
                    },
                ],
            },
        )
        self._write_json(
            wave_dir / "rollback-drill-report.json",
            {
                "reportVersion": "v1",
                "evidenceType": "visual-rollback-drill-report",
                "wave": "wave1",
                "executedAt": "2026-03-04",
                "runbookPath": "docs/runbooks/visual-system-rollback.md",
                "slaBusinessDaysMax": 1.0,
                "slaBusinessDaysActual": 0.4,
                "checklist": {
                    "regressionConfirmed": True,
                    "flagsDisabled": True,
                    "fallbackValidated": True,
                    "communicationSent": True,
                    "postmortemPlanned": True,
                },
                "telemetryMarkers": {
                    "triggeredEvent": "vsu_wave_rollback_triggered",
                    "completedEvent": "vsu_wave_rollback_completed",
                    "markerTimestamp": "2026-03-04T08:00:00Z",
                },
                "evidenceLinks": ["docs/runbooks/visual-system-rollback.md"],
            },
        )

    def _run(self, wave: str, wave_dir: Path, out: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(self.validator),
                "--wave",
                wave,
                "--wave-dir",
                str(wave_dir),
                "--report-out",
                str(out),
            ],
            cwd=self.repo_root,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_validator_passes_with_complete_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            temp = Path(td)
            wave_dir = temp / "wave1"
            out = temp / "report.json"
            self._build_wave_bundle(wave_dir)
            result = self._run("wave1", wave_dir, out)
            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def test_validator_fails_when_required_file_missing(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            temp = Path(td)
            wave_dir = temp / "wave1"
            out = temp / "report.json"
            self._build_wave_bundle(wave_dir)
            (wave_dir / "token-parity-report.md").unlink()

            result = self._run("wave1", wave_dir, out)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing required wave artifact", result.stdout)


if __name__ == "__main__":
    unittest.main()
