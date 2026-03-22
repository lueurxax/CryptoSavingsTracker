# SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL Implementation Audit R1

- Proposal: `docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
- Repository Root: `.`
- Git SHA: `644ba70`
- Working Tree: `dirty (15 modified, 46 untracked)`
- Audited At: `2026-03-22T11:17:25+0200`
- Proposal State: `Active`
- Overall Status: `Not Implemented`

## Verdict

The proposal is not implemented end to end. The repository contains meaningful Phase 1 style scaffolding for freshness notifications, calculator extraction, dirty-state persistence, and new freshness-specific helper types, but the live shared-goals pipeline still uses the pre-proposal payload/schema shape, still builds projections from legacy values, and still renders the old invitee UI. Several critical primitives are also present only as placeholders, including the auto-republish publish path and the reconciliation barrier. As a result, the codebase does not yet satisfy the proposal's locked data-contract, ordering, UI, or verification requirements.

## Audit Method

1. Read the proposal and checked for supersession/deprecation markers.
2. Built the app with `xcodebuild` against the iPhone 15 iOS simulator destination by device ID. The build succeeded.
3. Audited the live family-sharing implementation, schema models, UI surfaces, and tests against the proposal contract.
4. Classified each requirement as `Implemented`, `Partially Implemented`, `Missing`, or `Not Verifiable`.

## Proposal Contract

### Scope

The proposal requires a full freshness pipeline for shared goals that includes:

- owner-side stale-rate refresh and republish triggers
- deterministic projection rebuilding from canonical holdings plus rate snapshots
- new root payload fields for semantic freshness and dedup ordering
- invitee-side refresh scheduling and reconciliation safety
- new invitee freshness UI in list and detail surfaces
- rollout gates, telemetry, and explicit validation coverage

### Locked Decisions

The current proposal revision treats these as normative, not optional:

- `projectionVersion` remains an `Int`; semantic ordering is carried by `projectionServerTimestamp`
- root payloads/caches include freshness fields such as `contentHash`, `projectionServerTimestamp`, and `rateSnapshotTimestamp`
- progress math is rebuilt via an extracted pure calculator rather than legacy precomputed totals
- owner-side mutations and rate drift feed a republish pipeline with durable dirty replay
- invitee UI uses the proposal's freshness header/detail-card copy, not the legacy banner-era grammar

### Acceptance Criteria

The proposal's acceptance sections require:

- the migrated payload/schema to be live in CloudKit and local caches
- freshness state to be visible in shared-goal list and detail UI
- stale-rate and mutation events to trigger the new publish path
- invitee refresh and reconciliation behavior to be deterministic
- dedicated test coverage for model, service, and UI behavior

### Test / Evidence Requirements

The proposal expects evidence beyond successful compilation:

- unit/integration coverage for freshness calculation, ordering, republish, and scheduling paths
- UI coverage for the new freshness list/detail contract
- multi-device or equivalent evidence for reconciliation and ordering behavior
- accessibility/visual validation for the new invitee surfaces

### Explicit Exclusions

This audit does not judge product desirability. It only checks whether repository state implements the proposal contract. Runtime behavior that depends on real CloudKit traffic or device coordination is marked `Not Verifiable` unless the repository contains direct evidence.

## Requirement Summary

| ID | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| REQ-01 | Exchange-rate service exposes stale refresh and emits refresh notification | Implemented | `ios/CryptoSavingsTracker/Services/Protocols/ServiceProtocols.swift:41-49`, `ios/CryptoSavingsTracker/Services/ExchangeRateService.swift:392-432`, `ios/CryptoSavingsTracker/Utilities/NotificationNames.swift:19-23` |
| REQ-02 | Shared-goal-affecting mutations emit a unified change notification | Implemented | `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:66-71`, `:198-203`, `:212-216`, `:296-301`, `:315-320`, `ios/CryptoSavingsTracker/Services/AllocationService.swift:113-117` |
| REQ-03 | Progress calculation is extracted into a pure freshness-safe calculator | Implemented | `ios/CryptoSavingsTracker/Services/GoalProgressCalculator.swift:1-92`, `ios/CryptoSavingsTracker/Models/FamilySharing/FamilyShareFreshnessModels.swift` |
| REQ-04 | Owner-side auto-republish pipeline is fully wired with durable dirty replay | Partially Implemented | `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift`, `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareDirtyStateStore.swift` |
| REQ-05 | Reconciliation barrier prevents stale imports from outracing local publishes | Partially Implemented | `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareReconciliationBarrier.swift` |
| REQ-06 | Invitee-side refresh scheduling actively drives fetch/reconcile work | Partially Implemented | `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareInviteeRefreshScheduler.swift` |
| REQ-07 | Live payload, cache, and CloudKit schema include proposal freshness fields | Missing | `ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift:295-315`, `:337-377`, `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:103-138`, `:446-470`, `:548-568` |
| REQ-08 | Live projection assembly rebuilds proposal data from calculator plus freshness timestamps | Missing | `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1651-1728` |
| REQ-09 | Invitee list/detail surfaces render the new freshness header/card contract | Missing | `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:29-72`, `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift:12-140`, plus unused `FamilyShareFreshnessHeaderView` / `FamilyShareFreshnessCardView` definitions |
| REQ-10 | Rollout and telemetry for freshness pipeline exist in the production path | Partially Implemented | `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareRollout.swift` |
| REQ-11 | Automated tests cover the new freshness pipeline and UI contract | Missing | No targeted matches under `ios/CryptoSavingsTrackerTests` or `ios/CryptoSavingsTrackerUITests` for the new freshness classes, notifications, or UI views |
| REQ-12 | Multi-device ordering, reconciliation, and AX evidence is present | Not Verifiable | No repository evidence proving this behavior at audit time |

## Requirement Audit

### REQ-01: Exchange-rate stale refresh and refresh notification

**Status:** Implemented

The repository now contains the basic service-level capability required by the proposal. `ExchangeRateServiceProtocol` includes `refreshRatesIfStale() async`, `ExchangeRateService` tracks fetched pairs, performs stale refreshes, and posts `.exchangeRatesDidRefresh` after successful updates. This closes a foundational API gap.

Evidence:

- `ios/CryptoSavingsTracker/Services/Protocols/ServiceProtocols.swift:41-49`
- `ios/CryptoSavingsTracker/Services/ExchangeRateService.swift:87-110`
- `ios/CryptoSavingsTracker/Services/ExchangeRateService.swift:392-432`
- `ios/CryptoSavingsTracker/Utilities/NotificationNames.swift:19-23`

### REQ-02: Shared-goal mutation notification surface

**Status:** Implemented

Goal, asset, transaction, and allocation mutations now emit `.sharedGoalDataDidChange`, and the family-sharing freshness observer listens for it. This matches the proposal's direction of converging diverse owner-side changes into a single freshness-relevant mutation stream.

Evidence:

- `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:66-71`
- `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:198-203`
- `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:212-216`
- `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:296-301`
- `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:315-320`
- `ios/CryptoSavingsTracker/Services/AllocationService.swift:113-117`
- `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionMutationObserver.swift:26`

### REQ-03: Pure goal-progress calculator extraction

**Status:** Implemented

`GoalProgressCalculator` exists as a pure, `Sendable` service using explicit value types from the family-sharing freshness model layer. This aligns with the proposal's architectural requirement to compute projections from canonical inputs rather than relying on UI- or persistence-coupled totals.

Evidence:

- `ios/CryptoSavingsTracker/Services/GoalProgressCalculator.swift:1-92`
- `ios/CryptoSavingsTracker/Models/FamilySharing/FamilyShareFreshnessModels.swift`

### REQ-04: Owner-side auto-republish coordination with durable dirty replay

**Status:** Partially Implemented

The coordinator and dirty-state store exist, but the core publish path is not complete. `FamilyShareProjectionAutoRepublishCoordinator` contains the right scaffolding for dirty tracking, retry state, and persistence, yet `performPublish()` is still a placeholder and the file explicitly notes that full integration wiring remains to be completed. Durable replay is therefore not operational end to end.

Evidence:

- `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift`
- `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareDirtyStateStore.swift`

Why this is not `Implemented`:

- the production publish operation is not present
- proposal-required guarantees cannot hold while the coordinator stops short of actually republishing

### REQ-05: Reconciliation barrier ordering

**Status:** Partially Implemented

The reconciliation barrier type exists, but the production ordering signal is not implemented. The current barrier returns `nil` for the local import fence and includes comments indicating that CloudKit-history observation is intentionally simplified. This means the proposal's cross-device anti-regression ordering logic is not yet carried by a fully implemented runtime barrier.

Evidence:

- `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareReconciliationBarrier.swift`

### REQ-06: Invitee-side refresh scheduling

**Status:** Partially Implemented

The scheduler class exists and models freshness-related state, but the actual fetch/reconcile triggering is still externalized. That means the repository has scheduling scaffolding, not a complete invitee refresh driver that demonstrably executes the proposal's polling/refresh contract in production.

Evidence:

- `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareInviteeRefreshScheduler.swift`

### REQ-07: Live payload/cache/CloudKit schema migration

**Status:** Missing

This is the largest contract gap. The live payload and persistence models still use the legacy schema shape rather than the proposal's freshness fields. `FamilyShareProjectionPayload` and `FamilySharedDatasetCache` do not include `contentHash`, `projectionServerTimestamp`, or `rateSnapshotTimestamp`, and `FamilyShareCloudKitStore` still reads/writes the old root-record structure. The proposal's ordering and freshness semantics cannot be live while the transport and cache schema remain unchanged.

Evidence:

- `ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift:295-315`
- `ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift:337-377`
- `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:103-138`
- `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:446-470`
- `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:548-568`

### REQ-08: Live projection assembly uses the proposal's canonical rebuild path

**Status:** Missing

The live projection builder still does not implement the proposal's required data path. `makeProjectionPayload()` still stamps `publishedAt = Date()` locally, uses legacy fields such as `goal.manualTotal` and `goal.targetAmount`, and does not compute or populate `contentHash`, `projectionServerTimestamp`, or `rateSnapshotTimestamp`. The pure calculator exists, but the main shared-goal payload builder is still operating in the old model.

Evidence:

- `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1651-1728`

### REQ-09: Invitee UI uses the new freshness header/detail-card contract

**Status:** Missing

The repository contains new freshness-specific view types, but the actual shared-goal list and detail screens still render the older banner-era surface. `SharedGoalsSectionView` and `SharedGoalDetailView` do not use `FamilyShareFreshnessHeaderView` or `FamilyShareFreshnessCardView`, and repository search finds definitions without live integration. The proposal's user-facing contract is therefore not shipped.

Evidence:

- `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:29-72`
- `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift:12-140`
- `ios/CryptoSavingsTracker/Views/FamilySharing/FamilyShareFreshnessHeaderView.swift`
- `ios/CryptoSavingsTracker/Views/FamilySharing/FamilyShareFreshnessCardView.swift`

### REQ-10: Rollout and telemetry

**Status:** Partially Implemented

The rollout utility contains freshness-related feature flags and telemetry event identifiers, which is real progress. However, the core freshness pipeline is not yet fully wired into the live production path, so the existence of flags and events alone does not prove the proposal's rollout/telemetry contract is operational end to end.

Evidence:

- `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareRollout.swift`

### REQ-11: Automated tests for freshness pipeline and UI

**Status:** Missing

The audit did not find targeted tests for the newly introduced freshness pipeline classes, notifications, or invitee UI components. Existing family-sharing UI tests still reflect older flows and do not enforce the proposal's freshness header/detail-card contract. This fails a direct acceptance requirement of the proposal.

Evidence:

- No targeted matches under `ios/CryptoSavingsTrackerTests` or `ios/CryptoSavingsTrackerUITests` for:
  - `FamilyShareProjectionAutoRepublishCoordinator`
  - `FamilyShareForegroundRateRefreshDriver`
  - `FamilyShareRateDriftEvaluator`
  - `FamilyShareInviteeRefreshScheduler`
  - `GoalProgressCalculator`
  - `FamilyShareFreshnessLabel`
  - `exchangeRatesDidRefresh`
  - `sharedGoalDataDidChange`
- Existing UI coverage is still centered on legacy family-sharing flows in `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift`

### REQ-12: Runtime evidence for ordering, reconciliation, and accessibility behavior

**Status:** Not Verifiable

Some proposal requirements cannot be proven from the repository alone. The audit found no preserved repository evidence demonstrating multi-device ordering correctness, CloudKit race handling, or accessibility validation for the new freshness UI. Because the new UI is not even wired into the live screens yet, this evidence gap is expected.

## Build Evidence

The app build completed successfully during the audit using `xcodebuild` with a simulator destination by device ID. This confirms the repository is buildable in its current state, but build success does not materially change the implementation verdict because the proposal's missing pieces are behavioral and contractual rather than syntactic.

## Key Gaps Blocking "Implemented"

1. Migrate the live payload, cache, and CloudKit schema to the proposal's freshness fields.
2. Replace the legacy projection builder path with canonical calculator-based assembly plus freshness timestamps and hash generation.
3. Finish the auto-republish coordinator so dirty state can produce real republish work, not only bookkeeping.
4. Finish the reconciliation barrier with a production ordering fence.
5. Wire the new freshness header/card into shared-goal list and detail surfaces.
6. Add targeted unit/integration/UI tests for the new pipeline and UI contract.
7. Produce evidence for multi-device ordering and accessibility behavior once the feature is actually wired.

## Final Assessment

The repository is in an intermediate implementation state. Core scaffolding exists and some foundational architectural work is already landed, but the proposal's defining behaviors still are not live in the production shared-goals path. The correct implementation audit result for the current repository state is `Not Implemented`.
