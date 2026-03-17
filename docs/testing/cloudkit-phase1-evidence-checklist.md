# CloudKit Phase 1 Evidence Checklist

Date: 2026-03-17  
Owner: Mobile Platform Team

## Normative References

- [ADR-CK-CUTOVER-001](../design/ADR-CK-CUTOVER-001.md)
- [CloudKit Migration Plan](../CLOUDKIT_MIGRATION_PLAN.md)
- [CloudKit Cutover Release Gate Runbook](../runbooks/cloudkit-cutover-release-gate.md)

## Purpose

Operator checklist for proving the implemented Phase 1 contract:

`backup -> diagnostics/repair -> staging copy -> validation -> promotion -> persist mode -> relaunch`

Phase 1/1.5 cutover is complete; this checklist is now a regression and release-evidence artifact that protects the accepted CloudKit-only storage contract.

## Required Evidence

1. Cutover preflight is fail-closed
- CloudKit target probe blocks on non-empty/unknown target state.
- Source integrity check blocks duplicate IDs.
- Diagnostics report shows unresolved/ambiguous source relationships before copy.

2. Staging-based migration is used
- Logs show staging store creation and validation.
- Validation proves source/target entity parity before promotion.
- No direct bulk copy into a live CloudKit-backed store.

3. Relaunch activation contract holds
- Successful cutover persists `cloudKitPrimary`.
- Session that ran migration does not require in-session container hot-swap.
- Next launch comes up with cloud runtime as active mode.

4. Deferred cleanup contract holds
- Failed `cloud-primary` residue is cleaned on next launch.
- `cloud-primary-staging` residue is cleaned on next launch.
- No sqlite API-violation behavior from unlinking active files.

5. Retry safety
- After failed attempt, retry starts from clean target/staging residue.
- Entity counts do not inflate across retries.

## Minimum Test Coverage

- `CloudKitCutoverTests`
  - preflight fail-closed cases
  - source integrity duplicate-ID blocking
  - no in-session hot-swap after successful cutover
  - deferred cleanup for both cloud and staging markers
  - relaunch activation semantics
- `PersistenceControllerTests`
  - startup mode selection from persisted storage mode
  - snapshot/runtime store-kind consistency for cloud mode

## Device Validation Notes

Required one-device smoke sequence:

1. Run `Migration Diagnostics` and confirm actionable blocker surface.
2. Perform migration and verify success state is relaunch-required.
3. Relaunch app and verify cloud runtime status.
4. Re-open diagnostics and verify no stale staging/failed-attempt residue behavior.

## Exit Criteria

Phase 1 evidence is acceptable only when all required evidence items and minimum coverage items are green in the same release candidate.

## Repository-Truth Wiring

This checklist is a tracked release-governance artifact, not ad-hoc notes.

- It must remain indexed from [docs/README.md](../README.md).
- It must remain linked from [CLOUDKIT_MIGRATION_PLAN.md](../CLOUDKIT_MIGRATION_PLAN.md) and the runbook.
- Release evidence packages must archive completed outputs under `docs/release/cloudkit/<release-id>/`.
