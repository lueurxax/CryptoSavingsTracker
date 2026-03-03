# Latest Navigation Release Evidence

This folder is the canonical release-gate package for navigation migration.

Required files:

1. `guardrails-metrics-report.json`
2. `hard-cutover-report.json`
3. `go-no-go.md`
4. `mod02-diff-report.json`
5. `rollback-drill.md`
6. `parity-matrix-report.json`
7. `policy-report.json`

Telemetry schema source of truth:

- `docs/testing/navigation-telemetry-schema.v1.json`

Dry-run package:

- Wave: `planning`
- Dry-run id: `nav-dry-run-2026-03-03-r2`
- Dry-run date: `2026-03-03`
- Runbook: `docs/runbooks/navigation-release-governance.md`
- Operational hold status: `docs/release/navigation/latest/operational-hold-status.md`
- Dirty-dismiss checklist: `docs/testing/navigation-dirty-dismiss-integration-checklist.md`
- Hard-cutover policy report: `docs/release/navigation/latest/hard-cutover-report.json`
