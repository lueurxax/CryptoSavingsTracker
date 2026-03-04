# Navigation Release Governance Runbook

Runbook ID: `RUNBOOK-NAV-RELEASE-GATE-001`

## Scope

Go/no-go governance for navigation and presentation migration waves (`planning`, `dashboard`, `goals`).

## Required Inputs

1. Section 10 guardrail dashboard snapshot from `docs/NAVIGATION_PRESENTATION_CONSISTENCY.md`.
2. Rollback drill evidence per migrated module wave.
3. Compact `MOD-02` screenshot diff report:
   - `docs/screenshots/review-navigation-presentation-r3/compact/mod02-diff-report.json`.
4. Top-5 parity script status:
   - `artifacts/navigation/android-parity-matrix-report.json`,
   - `docs/testing/navigation-parity-matrix.v1.json`.
5. iOS policy gate artifact:
   - `artifacts/navigation/policy-report.json`.
6. Preview segregation backlog status:
   - `docs/runbooks/navigation-preview-segregation-backlog.csv`.
7. Telemetry schema contract:
   - `docs/testing/navigation-telemetry-schema.v1.json`.
8. Latest release package mirror:
   - `docs/release/navigation/latest/`.
9. Operational hold tracker (until Green transition):
   - `docs/release/navigation/latest/operational-hold-status.md`,
   - `docs/release/navigation/history/guardrail-release-streak.json`.
10. Dirty-dismiss integration checklist:
   - `docs/testing/navigation-dirty-dismiss-integration-checklist.md`.

## Approval Ceremony

Required approvers:

- Product Analytics (metrics sign-off),
- Mobile Platform Team (policy and CI sign-off),
- Engineering Manager (final tie-break and go/no-go owner).

SLA:

- Review window: 24h before RC cut.
- Unresolved blocker decision: 12h escalation window.

Escalation:

- If Product Analytics and Mobile Platform Team disagree, Engineering Manager is final decision owner.

## Go/No-Go Checklist

1. `NAV001` violations: zero in target wave.
2. `NAV002` decision-tag failures: zero for changed wave scope (PR) and zero for full scan (release).
3. `MOD-02` compact artifact gate:
   - report updated for current PR/release delta,
   - all required scenarios `status=pass`,
   - `diffRatio <= 0.02`.
4. Top-5 parity matrix gate passes with valid Android presentation references.
5. Dirty-dismiss behavior validated for impacted financial forms.
6. Hard-cutover policy verified in staging and CI (no migration runtime toggles in active code paths).
7. `NAV003` backlog trend is non-increasing per wave and owners are assigned for all open files.
8. Release evidence quality checks:
   - `policy-report.json` has `changedOnly=false`,
   - `policy-report.json` has `scannedFileCount > 0`.
9. Hard-cutover report passes (`artifacts/navigation/hard-cutover-report.json`).

Current status (2026-03-03):

- `docs/runbooks/navigation-preview-segregation-backlog.csv` has 0 open items.

## Dry-Run Requirement

At least one full rehearsal must be completed before first “Next” wave RC:

1. Run all navigation policy jobs.
2. Attach all required artifacts.
3. Execute approval ceremony with named approvers.
4. Record blockers, decisions, and remediation owners.

Dry-run evidence (completed):

- `docs/release/navigation/latest/go-no-go.md`
- `docs/release/navigation/latest/rollback-drill.md`
- `docs/release/navigation/latest/guardrails-metrics-report.json`

## Operational Hold and Green Transition

Current mode (as of 2026-03-03): `Operational Hold`.

- Engineering closure is complete.
- Final Green transition is blocked until two real consecutive production releases pass all guardrails.

Transition rule:

1. `docs/release/navigation/history/guardrail-release-streak.json` has `consecutivePassCount >= 2`.
2. Each counted release has:
   - `guardrailsOverallStatus = pass`,
   - `policyPassed = true`,
   - `parityPassed = true`.
3. No counted release has navigation policy/parity regressions.

## Evidence Archive

Store each wave package under:

- `docs/release/navigation/<wave>/`

Promoted latest package:

- `docs/release/navigation/latest/`

Minimum package files:

1. `go-no-go.md`
2. `policy-report.json`
3. `hard-cutover-report.json`
4. `mod02-diff-report.json`
5. `parity-matrix-report.json`
6. `rollback-drill.md`
7. `guardrails-metrics-report.json`
8. `operational-hold-status.md` (required until streak reaches 2 production releases)
