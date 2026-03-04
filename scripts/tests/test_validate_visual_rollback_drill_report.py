#!/usr/bin/env python3
"""Tests for visual rollback drill validator."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class ValidateVisualRollbackDrillReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[2]
        cls.validator = cls.repo_root / "scripts" / "validate_visual_rollback_drill_report.py"
        cls.schema = cls.repo_root / "docs/design/schemas/visual-rollback-drill-report.schema.json"

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

    def test_validator_passes_with_valid_report(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            temp = Path(td)
            report = temp / "rollback-drill-report.json"
            out = temp / "out.json"
            self._write_json(
                report,
                {
                    "reportVersion": "v1",
                    "evidenceType": "visual-rollback-drill-report",
                    "wave": "wave1",
                    "executedAt": "2026-03-04",
                    "runbookPath": "docs/runbooks/visual-system-rollback.md",
                    "slaBusinessDaysMax": 1.0,
                    "slaBusinessDaysActual": 0.5,
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
                    "evidenceLinks": [
                        "docs/runbooks/visual-system-rollback.md"
                    ],
                },
            )
            result = self._run(report, out)
            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def test_validator_fails_on_wrong_events(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            temp = Path(td)
            report = temp / "rollback-drill-report.json"
            out = temp / "out.json"
            self._write_json(
                report,
                {
                    "reportVersion": "v1",
                    "evidenceType": "visual-rollback-drill-report",
                    "wave": "wave1",
                    "executedAt": "2026-03-04",
                    "runbookPath": "docs/runbooks/visual-system-rollback.md",
                    "slaBusinessDaysMax": 1.0,
                    "slaBusinessDaysActual": 1.2,
                    "checklist": {
                        "regressionConfirmed": True,
                        "flagsDisabled": True,
                        "fallbackValidated": False,
                        "communicationSent": True,
                        "postmortemPlanned": True,
                    },
                    "telemetryMarkers": {
                        "triggeredEvent": "bad_trigger",
                        "completedEvent": "bad_completed",
                        "markerTimestamp": "invalid",
                    },
                    "evidenceLinks": [],
                },
            )
            result = self._run(report, out)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("telemetryMarkers", result.stdout)


if __name__ == "__main__":
    unittest.main()
