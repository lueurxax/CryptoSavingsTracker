# CloudKit Phase 1 Worktree Execution Plan

> Execution plan for Phase 0, Phase 1, and Phase 1.5 of the CloudKit migration program.

| Metadata | Value |
|----------|-------|
| Status | 📋 Planned |
| Last Updated | 2026-03-16 |
| Platform | iOS |
| Audience | Developers |

---

## Objective

Deliver an iPhone app that:
- migrates an existing local SwiftData store into CloudKit safely,
- runs stably on CloudKit as the primary persistence runtime,
- removes local-runtime backward compatibility after the CloudKit cutover is proven stable,
- keeps the Phase 2 QR/Multipeer bridge out of scope until the app is already CloudKit-only.

This execution plan covers:
- **Phase 0**: CloudKit readiness and prerequisites
- **Phase 1**: local-to-CloudKit cutover
- **Phase 1.5**: hard cutover cleanup to CloudKit-only runtime

This execution plan does **not** cover:
- QR pairing
- Multipeer transport
- Mac bridge editing/import flows
- any second sync method

---

## Current Baseline

The current repo already has two partial foundational slices in progress:
- runtime persistence ownership via [ios/CryptoSavingsTracker/Utilities/PersistenceController.swift](../ios/CryptoSavingsTracker/Utilities/PersistenceController.swift)
- runtime write-boundary cleanup via [ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift](../ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift)

Those slices should be treated as the start of the foundation wave, not re-designed from scratch.

The authoritative model constraints and CloudKit-specific prerequisites remain in:
- [CLOUDKIT_MIGRATION_PLAN.md](CLOUDKIT_MIGRATION_PLAN.md)

---

## Worktree Topology

Use one integration branch as the merge target for the phase:
- `codex/cloudkit-phase1-integration`

Create worktrees from that integration branch with the following branch names:

| ID | Branch | Goal | Primary Ownership | Depends On |
|----|--------|------|-------------------|------------|
| WT-01 | `codex/cloudkit-schema-readiness` | Finish CloudKit-safe model contract and logical dedupe rules | `Models/`, repository/query nil-safe reads | none |
| WT-02 | `codex/cloudkit-persistence-foundation` | Finish two-store topology and runtime-owned persistence controller | `PersistenceController`, app root container wiring, migration diagnostics | none |
| WT-03 | `codex/cloudkit-write-pipeline` | Finish service-owned mutation boundary for runtime writes | mutation services, runtime views/view models/navigation | none |
| WT-04 | `codex/cloudkit-cutover-engine` | Implement local-to-CloudKit migration coordinator and relaunch semantics | cutover coordinator, store switching, copy/verify flow | WT-01, WT-02, WT-03 |
| WT-05 | `codex/cloudkit-runtime-stability` | Make CloudKit runtime resilient to account/network/schema failures | account health, sync health, graceful failure handling | WT-04 |
| WT-06 | `codex/cloudkit-migration-ui` | Ship user-facing migration controls and progress/status UI | Settings migration flow, progress, result/error states | WT-04 |
| WT-07 | `codex/cloudkit-test-ci-evidence` | Lock correctness and operational gates in tests/CI/docs | tests, scripts, workflows, runbooks | WT-04, WT-05, WT-06 |
| WT-08 | `codex/cloudkit-cloudonly-cleanup` | Remove local-runtime backward compatibility from active code | CloudKit-only runtime cleanup and docs | WT-05, WT-06, WT-07 |

---

## Worktree Details

### WT-01 — Schema Readiness

**Branch:** `codex/cloudkit-schema-readiness`

**Owns:**
- [ios/CryptoSavingsTracker/Models](../ios/CryptoSavingsTracker/Models)
- [ios/CryptoSavingsTracker/Utilities/SwiftDataQueries.swift](../ios/CryptoSavingsTracker/Utilities/SwiftDataQueries.swift)
- [ios/CryptoSavingsTracker/Repositories/GoalRepository.swift](../ios/CryptoSavingsTracker/Repositories/GoalRepository.swift)
- narrowly scoped relationship-safe read paths in services

**Purpose:**
- close the remaining model-level compatibility items from [CLOUDKIT_MIGRATION_PLAN.md](CLOUDKIT_MIGRATION_PLAN.md)
- finish explicit inverse relationships and declaration-time defaults
- formalize application-level logical matching and dedupe policy now that unique constraints are gone

**Done when:**
- all models are CloudKit-compatible by declaration contract
- development schema deploy succeeds
- logical duplicate detection rules are explicit and testable
- repository/query paths tolerate optional relationships and orphan windows

### WT-02 — Persistence Foundation

**Branch:** `codex/cloudkit-persistence-foundation`

**Owns:**
- [ios/CryptoSavingsTracker/Utilities/PersistenceController.swift](../ios/CryptoSavingsTracker/Utilities/PersistenceController.swift)
- [ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift](../ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift)
- [ios/CryptoSavingsTracker/Utilities/CloudKitMigrationStatus.swift](../ios/CryptoSavingsTracker/Utilities/CloudKitMigrationStatus.swift)
- [ios/CryptoSavingsTracker/Views/Settings/CloudKitMigrationStatusView.swift](../ios/CryptoSavingsTracker/Views/Settings/CloudKitMigrationStatusView.swift)

**Purpose:**
- finish the two-store topology
- make `PersistenceController` the only runtime owner of the active `ModelContainer`
- expose real runtime/store diagnostics while still keeping runtime `localOnly`

**Done when:**
- active runtime no longer depends on `sharedModelContainer`
- local and future cloud store descriptors are explicit
- storage mode registry and runtime snapshot are wired into diagnostics
- CloudKit activation is still blocked, but block reasons are real, not placeholder text

### WT-03 — Write Pipeline

**Branch:** `codex/cloudkit-write-pipeline`

**Owns:**
- [ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift](../ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift)
- [ios/CryptoSavingsTracker/Services/Protocols/ServiceProtocols.swift](../ios/CryptoSavingsTracker/Services/Protocols/ServiceProtocols.swift)
- [ios/CryptoSavingsTracker/ViewModels](../ios/CryptoSavingsTracker/ViewModels)
- [ios/CryptoSavingsTracker/Views](../ios/CryptoSavingsTracker/Views)
- [ios/CryptoSavingsTracker/Navigation](../ios/CryptoSavingsTracker/Navigation)

**Purpose:**
- finish moving runtime writes behind services before CloudKit cutover work starts
- ensure views/view models/navigation own orchestration only, not persistence mutations

**Done when:**
- active runtime code does not call `modelContext.insert/delete/save`
- mutation side effects stay in services/repositories
- the SwiftData write-boundary check is green in CI

### WT-04 — Cutover Engine

**Branch:** `codex/cloudkit-cutover-engine`

**Owns:**
- new cutover services/coordinators under `ios/CryptoSavingsTracker/Services/`
- [ios/CryptoSavingsTracker/Utilities/PersistenceController.swift](../ios/CryptoSavingsTracker/Utilities/PersistenceController.swift)
- [ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift](../ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift)
- any storage-mode transition plumbing needed for relaunch semantics

**Purpose:**
- implement the actual migration from the current local store into the future cloud primary store
- validate copied data before switching modes
- persist selected storage mode and relaunch into the CloudKit runtime cleanly

**Done when:**
- an existing local install can migrate to the cloud-backed store without data loss
- migration creates a backup/snapshot before cutover
- the app restarts in CloudKit mode deterministically after successful cutover
- migration failure never corrupts the original local dataset

### WT-05 — Runtime Stability

**Branch:** `codex/cloudkit-runtime-stability`

**Owns:**
- new account/sync health utilities
- CloudKit availability and operator-visible runtime state
- safe failure handling around save/fetch/sync conditions
- any remaining wipe-on-failure removal work tied to CloudKit activation

**Purpose:**
- make the CloudKit runtime operationally safe under real failure modes
- ensure the app degrades visibly and safely when CloudKit or the iCloud account is unavailable

**Done when:**
- no CloudKit failure path wipes the user’s data
- sign-out, sign-in, account switch, schema propagation lag, and offline edits are handled explicitly
- runtime health states are surfaced deterministically to the operator/user

### WT-06 — Migration UI

**Branch:** `codex/cloudkit-migration-ui`

**Owns:**
- [ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift](../ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift)
- [ios/CryptoSavingsTracker/Views/Settings/CloudKitMigrationStatusView.swift](../ios/CryptoSavingsTracker/Views/Settings/CloudKitMigrationStatusView.swift)
- new migration progress/result views

**Purpose:**
- make the migration visible and operable in the product surface
- keep the bridge UI out of scope

**Done when:**
- Settings exposes readiness, migration start, progress, and result states
- blocked migration states are actionable and accurate
- successful migration visibly lands the user in CloudKit primary mode

### WT-07 — Test, CI, and Evidence

**Branch:** `codex/cloudkit-test-ci-evidence`

**Owns:**
- [ios/CryptoSavingsTrackerTests](../ios/CryptoSavingsTrackerTests)
- [ios/CryptoSavingsTrackerUITests](../ios/CryptoSavingsTrackerUITests)
- [scripts](../scripts)
- [.github/workflows](../.github/workflows)
- CloudKit runbooks and release evidence docs

**Purpose:**
- encode the first-stage acceptance contract in automated checks
- ensure migration and CloudKit runtime regressions block merges/releases

**Done when:**
- tests cover migration, dedupe, relaunch, CloudKit unavailability, and account edge cases
- CI blocks regressions in schema readiness, runtime ownership, write boundary, and migration evidence
- release/runbook docs explain how to certify CloudKit cutover readiness

### WT-08 — CloudKit-Only Cleanup

**Branch:** `codex/cloudkit-cloudonly-cleanup`

**Owns:**
- [ios/CryptoSavingsTracker/Utilities/PersistenceController.swift](../ios/CryptoSavingsTracker/Utilities/PersistenceController.swift)
- [ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift](../ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift)
- active diagnostics and governance docs that still describe local-runtime compatibility

**Purpose:**
- complete Phase 1.5
- remove local-runtime backward compatibility from active code after CloudKit runtime is proven stable

**Done when:**
- CloudKit is the only active runtime persistence path
- local fallback logic is removed from production code
- Phase 2 bridge remains blocked, but its prerequisite of "CloudKit-only runtime" is finally true

---

## Parallel Waves

### Wave A — Foundation

Run in parallel:
- WT-01 `cloudkit-schema-readiness`
- WT-02 `cloudkit-persistence-foundation`
- WT-03 `cloudkit-write-pipeline`

**Wave exit gate:**
- all three branches merged into `codex/cloudkit-phase1-integration`
- app still boots locally
- schema/build/tests stay green

### Wave B — Cutover

Run after Wave A merge:
- WT-04 `cloudkit-cutover-engine`
- WT-05 `cloudkit-runtime-stability`
- WT-06 `cloudkit-migration-ui`

**Wave exit gate:**
- a real local store migrates successfully into the CloudKit-backed runtime
- CloudKit mode is stable on development container
- Settings flow can drive and report the cutover

### Wave C — Validation

Run after Wave B APIs stabilize:
- WT-07 `cloudkit-test-ci-evidence`

**Wave exit gate:**
- automated and operational checks prove the cutover is safe

### Wave D — Hard Cutover

Run last:
- WT-08 `cloudkit-cloudonly-cleanup`

**Wave exit gate:**
- local compatibility removed from active runtime
- the app is now operationally CloudKit-only

---

## Hotspot Ownership Rules

These files must have a **single owner per wave**:
- [ios/CryptoSavingsTracker/Utilities/PersistenceController.swift](../ios/CryptoSavingsTracker/Utilities/PersistenceController.swift)
- [ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift](../ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift)
- [ios/CryptoSavingsTracker/Utilities/DIContainer.swift](../ios/CryptoSavingsTracker/Utilities/DIContainer.swift)
- [ios/CryptoSavingsTracker/Utilities/CloudKitMigrationStatus.swift](../ios/CryptoSavingsTracker/Utilities/CloudKitMigrationStatus.swift)
- [ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift](../ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift)
- [.github/workflows/navigation-policy-gates.yml](../.github/workflows/navigation-policy-gates.yml)

Recommended ownership:
- Wave A: WT-02 owns `PersistenceController` and `CryptoSavingsTrackerApp`
- Wave B: WT-04 owns the same core files, WT-06 owns `SettingsView`
- Wave C: WT-07 owns workflows/scripts
- Wave D: WT-08 owns final cleanup in core runtime files

---

## Merge Strategy

1. Create `codex/cloudkit-phase1-integration`.
2. Create Wave A worktrees from that branch.
3. Merge WT-01, WT-02, WT-03 into the integration branch.
4. Rebase Wave B worktrees onto the merged integration branch.
5. Merge WT-04 first, then WT-05 and WT-06.
6. Rebase WT-07 onto the post-Wave-B integration branch and merge it.
7. Run a CloudKit soak cycle in the development container.
8. Open WT-08 from the latest integration branch and merge it only after the soak is clean.

---

## Creation Template

Example commands:

```bash
git checkout -b codex/cloudkit-phase1-integration
git worktree add ../cst-cloudkit-schema -b codex/cloudkit-schema-readiness
git worktree add ../cst-cloudkit-persistence -b codex/cloudkit-persistence-foundation
git worktree add ../cst-cloudkit-write-pipeline -b codex/cloudkit-write-pipeline
```

Repeat the same pattern for later waves after the earlier wave is merged and rebased.

---

## Final Exit Criteria

This first-stage program is complete only when all of the following are true:
- the current local app can migrate user data into CloudKit safely
- the app runs stably on CloudKit after migration
- no wipe-on-failure behavior remains in the CloudKit runtime
- CI and tests prove migration, relaunch, dedupe, and failure handling
- local-runtime backward compatibility has been removed from active production code
- Phase 2 bridge work remains disabled until after this state is reached

When those conditions are true, the codebase is ready to start the separate QR/Multipeer bridge phase.
