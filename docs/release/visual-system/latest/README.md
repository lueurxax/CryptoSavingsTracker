# Latest Release Gate Inputs

This folder is the published mirror of the latest release-gate outputs.

Canonical run outputs are produced under `artifacts/visual-system/` and then synced here by `scripts/run_visual_system_release_gates.sh`.

Required files:

1. `runtime-accessibility-assertions.json`
2. `runtime-accessibility-test-results.json`
3. `ux-metrics-report.json`
4. `release-certification-report.json`
5. `release-certification-freshness-report.json`
6. `release-certification-summary.md`
7. `literal-baseline-burndown-report.json`

Update process per promoted wave:

1. Produce wave artifacts under `docs/release/visual-system/<wave>/`.
2. Run `bash scripts/run_visual_system_release_gates.sh` to regenerate and sync canonical outputs.
3. Keep source inputs (`runtime-accessibility-test-results.json`, `ux-metrics-report.json`) aligned with approved wave revision.
