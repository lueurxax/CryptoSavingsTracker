# ADR-CK-CUTOVER-001: Staged CloudKit Cutover and Relaunch Activation

## Status

Accepted (2026-03-17, amended 2026-03-17 for Phase 1.5 hard cutover)

## Context

The original CloudKit migration plan and Phase 2 bridge proposal assumed a straightforward Phase 1 cutover: copy local data into the future CloudKit-backed store, switch runtime ownership, and continue from the same session.

Real-device migration work proved that this assumption was not operationally safe.

The implementation encountered these concrete failure modes:

1. Copying directly into a live CloudKit-backed store caused validation instability and count inflation while `NSCloudKitMirroringDelegate` was active.
2. Hot-swapping the active `ModelContainer` in-session invalidated model instances still retained by SwiftUI views and services, causing post-migration crashes.
3. Real local stores contained unresolved `AllocationHistory` references and other integrity blockers that had to be surfaced and repaired before migration, not silently guessed or dropped.
4. Deleting failed-attempt sqlite files while the store was still open produced sqlite API-violation warnings (`vnode unlinked while in use`).

These failures changed the accepted Phase 1 architecture from a simple “copy into CloudKit and switch” model into a staged migration pipeline with a relaunch boundary.

## Decision

Phase 1 CloudKit migration uses the following cutover contract:

1. Create a local backup before migration.
2. Run local-only diagnostics before opening any CloudKit-backed container.
3. Classify and block unresolved source-data issues through repair/export tooling instead of silently repairing low-confidence records.
4. Copy data into a CloudKit-disabled staging store.
5. Validate exact entity presence and migration integrity inside staging.
6. Promote the validated staging sqlite files into the final `cloud-primary` location only after validation succeeds.
7. Persist `cloudKitPrimary` for the next launch.
8. Do not hot-swap the live runtime container in-session.
9. Treat app relaunch as the activation boundary for the CloudKit-backed runtime.
10. Use deferred cleanup for stale `cloud-primary` and `cloud-primary-staging` files instead of unlinking sqlite files while a store may still hold them open.

## Non-Decision

This ADR originally described the staged Phase 1 migration contract. It is now amended by the accepted Phase 1.5 hard-cutover decision: authoritative runtime data is CloudKit-only, legacy local-primary runtime is retired, and residual legacy local-primary store files are deleted on launch.

The staged migration pipeline remains the historical explanation for how the cutover was achieved. The current production contract now additionally assumes:

- legacy local-runtime compatibility is retired for authoritative data,
- the product is CloudKit-only for durable state,
- residual local-primary store files are deleted on launch,
- Phase 2 bridge sequencing now starts from the implemented signed file-based manual bridge. CloudKit-only runtime remains a prerequisite that is already satisfied by storage policy, while QR/Multipeer transport stays as later hardening rather than a minimum bridge requirement.

## Consequences

### Positive

- Migration validation is deterministic because it happens before live CloudKit mirroring is opened.
- The app no longer relies on in-session container hot-swap, which removes a class of stale-object crashes.
- Source-data blockers are now explicit and operator-visible instead of becoming silent data loss or framework traps.
- Failed migrations no longer need destructive live-store cleanup.

### Tradeoffs

- A successful migration now ends in a relaunch-required state rather than immediate CloudKit activation in the same session.
- Transitional diagnostics and repair surfaces remain historical implementation detail, but they are no longer part of the supported steady-state product contract for migrated installs.
- Phase 2A is documented as a signed file-based manual bridge with concrete import review and apply; QR/Multipeer transport are later hardening items, not the minimum bridge contract.
- Authoritative data must remain in CloudKit-backed runtime paths; local persistence is allowed only for caches and scratch artifacts.
- Migration complexity moved from a single copy step to a multi-stage pipeline with staging, promotion, and deferred cleanup.

## Operational Requirements

- Settings and diagnostics surfaces must reflect the CloudKit-only contract for authoritative data and legacy-store cleanup policy.
- Migration success UI must clearly communicate that relaunch is required before CloudKit-backed runtime becomes active.
- Retry logic must start from clean staging and clean final-target residue.
- Tests and runbooks must treat the staged cutover path plus the hard-cutover storage policy as the authoritative repository truth for Phase 1/1.5.

## Related Documents

- [CloudKit Migration Plan](/Users/user/Documents/CryptoSavingsTracker/docs/CLOUDKIT_MIGRATION_PLAN.md)
- [CloudKit Phase 1 Worktree Execution Plan](/Users/user/Documents/CryptoSavingsTracker/docs/CLOUDKIT_PHASE1_WORKTREE_EXECUTION_PLAN.md)
- [CloudKit QR + Multipeer Sync Proposal](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md)
