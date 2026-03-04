# Latest Release Gate Inputs

This folder is the published mirror of the latest promoted wave bundle.

Source of truth is `docs/release/visual-system/wave1/` for the current rollout.
Canonical run outputs are produced under `artifacts/visual-system/` and then synced by:

1. `scripts/publish_visual_wave_bundle.py` (`artifacts -> wave1 -> latest`)
2. `scripts/run_visual_system_release_gates.sh` (orchestration)

Required files:

1. `runtime-accessibility-assertions.json`
2. `runtime-accessibility-test-results.json`
3. `ux-metrics-report.json`
4. `release-certification-report.json`
5. `release-certification-freshness-report.json`
6. `release-certification-summary.md`
7. `literal-baseline-burndown-report.json`
8. `performance-report.json`
9. `rollback-drill-report.json`
10. `wave-bundle-validation-report.json`

Update process per promoted wave:

1. Produce and validate wave artifacts under `docs/release/visual-system/<wave>/`.
2. Run `bash scripts/run_visual_system_release_gates.sh` with `VISUAL_SYSTEM_WAVE=<wave>`.
3. Keep source inputs (`runtime-accessibility-test-results.json`, `ux-metrics-report.json`, `performance-report.json`, `rollback-drill-report.json`) aligned with approved wave revision.
