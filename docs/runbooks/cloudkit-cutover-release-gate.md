# CloudKit Cutover Release Gate Runbook

Runbook ID: `RUNBOOK-CK-CUTOVER-001`

## Normative References

- [ADR-CK-CUTOVER-001](../design/ADR-CK-CUTOVER-001.md)
- [CloudKit Migration Plan](../CLOUDKIT_MIGRATION_PLAN.md)
- [CloudKit Phase 1 Evidence Checklist](../testing/cloudkit-phase1-evidence-checklist.md)

## Scope

Go/no-go governance for completed Phase 1/1.5 CloudKit cutover, plus regression gating before and during Phase 2 bridge-surface rollout.

## Required Inputs

1. Migration architecture contract:
- `docs/design/ADR-CK-CUTOVER-001.md`
- `docs/CLOUDKIT_MIGRATION_PLAN.md`

2. Test evidence:
- targeted `CloudKitCutoverTests` results
- targeted `PersistenceControllerTests` results

3. Diagnostics evidence:
- `Migration Diagnostics` JSON output from a real migrated dataset
- blocker classifications and repair/export artifacts (if any)

4. Device run evidence:
- migration attempt logs proving staging validation and promotion
- relaunch log proving cloud runtime activation

5. Cleanup evidence:
- deferred cleanup logs for pending cloud/staging markers
- no sqlite API-violation warnings

## Go/No-Go Checklist

1. Preflight fail-closed is confirmed.
2. Source integrity duplicate-ID blocking is confirmed.
3. Staging copy + validation + promotion flow is confirmed.
4. Successful cutover persists mode and ends in relaunch-required state.
5. Relaunch activates cloud runtime deterministically.
6. Deferred cleanup works for both cloud and staging markers.
7. Retry from failed attempts does not accumulate target records.
8. No wipe-on-failure behavior exists in active runtime paths.

## Approval Ceremony

Required approvers:

- iOS Tech Lead
- Mobile Platform Team
- Engineering Manager

Escalation:

- unresolved data-repair policy decisions (`ambiguous` vs `unrecoverable`) block release
- unresolved runtime ownership ambiguity blocks Phase 1.5 promotion

## Evidence Archive

Archive each release package under:

- `docs/release/cloudkit/<release-id>/`

Minimum files:

1. `go-no-go.md`
2. `cloudkit-cutover-test-report.md`
3. `device-migration-log.txt`
4. `diagnostics-report.json`
5. `cleanup-verification.md`

Repository-truth rule:
- The archived package must reference the exact commit SHA and the completed checklist/runbook versions used for approval.

## Phase 1.5 Readiness Gate

Phase 1.5 is considered complete only when the production runtime is CloudKit-only for authoritative data, legacy local-primary residue is removed on launch, and the normal Settings surface no longer exposes transitional migration controls.

## Phase 2 Opening Gate (Post-Cutover)

Bridge-surface implementation is permitted only when all are true:

1. CloudKit runtime activation is deterministic after relaunch.
2. Transitional migration/repair UI can be scoped for retirement.
3. Local backward compatibility removal plan is accepted.
4. Release evidence demonstrates stable CloudKit-only runtime behavior in production-like conditions.

Current state (2026-03-17): this gate is satisfied and serves as an ongoing regression guard.
