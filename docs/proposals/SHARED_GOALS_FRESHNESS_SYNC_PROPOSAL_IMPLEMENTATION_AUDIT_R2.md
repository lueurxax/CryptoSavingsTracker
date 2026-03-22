# SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL Implementation Audit R2

| Field | Value |
|---|---|
| Proposal | `docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md` |
| Repository Root | `.` |
| Git SHA | `644ba70` |
| Working Tree | `dirty (21 modified, 53 untracked)` |
| Audited At | `2026-03-22T11:35:42+0200` |
| Proposal State | `Active` |
| Overall Status | `Not Implemented` |

## Verdict

The proposal is still not implemented end to end, but the repository has moved materially beyond the previous audit. The live payload/cache/CloudKit schema now carries freshness fields, the list/detail UI now uses `FamilyShareFreshnessLabel` primitives, and several foundational unit-test files exist. The remaining blockers are in the orchestration layer: the auto-republish coordinator, rate-refresh driver, invitee scheduler, and reconciliation barrier are still not wired into the production family-sharing path; direct publish bypasses remain; server-assigned freshness timestamps are not propagated back into live state; and the detail view still cannot render the proposal's full provenance contract.

## Proposal Contract

### Scope

- owner-side freshness maintenance through rate refresh, drift evaluation, dirty tracking, and automatic republish
- canonical projection rebuild from current owner truth using `GoalProgressCalculator`
- additive payload/cache/CloudKit freshness metadata and three-phase invitee ordering
- invitee refresh scheduling plus per-namespace freshness UI in list and detail surfaces
- rollout, telemetry, migration safety, and explicit verification coverage

### Locked Decisions

- `projectionVersion` remains the atomic publish token; semantic freshness ordering is carried by `contentHash`, with `projectionServerTimestamp` as pre-migration fallback only
- `currentAmount` must come from `GoalProgressCalculator`, not `goal.manualTotal`
- all publish-triggering actions route through a per-namespace auto-republish coordinator
- list and detail surfaces share one canonical freshness string model, `FamilyShareFreshnessLabel`
- detail provenance must show both publish and rate timestamps using the canonical disclosure rule

### Acceptance Criteria

- owner edits and rate drift republish shared projections without manual sharing workarounds
- invitee freshness is composite (`max(publishAge, rateAge)`) and visible per namespace
- direct publish bypasses are removed in favor of serialized coordinator ownership
- schema migration is additive and rollback-safe
- invitee ordering uses the documented three-phase version/contentHash/server-timestamp contract

### Test / Evidence Requirements

- targeted unit coverage for calculator, materiality, debounce/coalescing, scheduler, ordering, and barrier behavior
- integration coverage for publish/fetch loop, rate-drift pipeline, offline queue, and migration
- UI/accessibility coverage for freshness headers, detail provenance, compact layout, motion, and recovery actions
- runtime evidence for multi-device ordering and freshness rendering behavior

### Explicit Exclusions

- this audit does not modify the proposal or implementation
- this audit does not treat inference alone as proof of completion
- this audit does not claim runtime CloudKit correctness without direct evidence

## Requirement Summary

| Status | Count |
|---|---:|
| Implemented | 3 |
| Partially Implemented | 5 |
| Missing | 4 |
| Not Verifiable | 1 |

## Requirement Audit

### REQ-001 Exchange-rate refresh prerequisite exists
- Proposal Source: Section `5.5 Foreground Rate-Refresh Driver and Periodic Guard`, Section `7.0.1 ExchangeRateService Changes`, Acceptance Criteria items `16` and `50` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:255-261`, `:760-792`, `:1483`, `:1517`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/Protocols/ServiceProtocols.swift:47-49`
  - `ios/CryptoSavingsTracker/Services/ExchangeRateService.swift:398-427`
  - `ios/CryptoSavingsTracker/Utilities/NotificationNames.swift:19-23`
- Gap / Note: The service-level API is present. Whether it is actively driven in production is a separate requirement and remains incomplete under REQ-006.

### REQ-002 Shared-goal mutation notifications are normalized at the service layer
- Proposal Source: Section `7.0.2 PersistenceMutationServices Notification Normalization`, Section `7.2.1 Complete Publish Trigger Inventory`, Acceptance Criteria item `17` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:794-805`, `:961-968`, `:1484`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/NotificationNames.swift:23`
  - `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:68`, `:200`, `:213`, `:298`, `:317`
  - `ios/CryptoSavingsTracker/Services/AllocationService.swift:114`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionMutationObserver.swift:26`
- Gap / Note: The normalized notification exists and is emitted by service-layer mutators. Higher-order routing through the coordinator remains incomplete under REQ-007.

### REQ-003 Canonical freshness primitives are extracted into reusable domain code
- Proposal Source: Section `7.0.3 Pure Domain Calculator Extraction`, Section `5.3.1 Materiality Policy for Non-USD Goals`, Section `6.6 Projection Metadata and Canonical Freshness Model`, Acceptance Criteria items `21`, `24`, and `51` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:807-844`, `:222-241`, `:503-567`, `:1488`, `:1491`, `:1518`)
- Status: `Implemented`
- Evidence Type: `code, tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/GoalProgressCalculator.swift:11`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareMaterialityPolicy.swift:9`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift:10`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/GoalProgressCalculatorTests.swift:10`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareMaterialityPolicyTests.swift:10`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessLabelTests.swift:15`
- Gap / Note: These foundational pieces exist and have targeted test files, but production wiring is evaluated separately below.

### REQ-004 Live payload/cache/CloudKit schema carries freshness metadata without dropping it on migration/update paths
- Proposal Source: Section `6.8.2 Version and Ordering Contract`, Section `7.0.4 Projection Cache Schema Migration`, Acceptance Criteria items `36` and `47` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:676-701`, `:846-859`, `:1503`, `:1514`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift:317-326`, `:423-430`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:451-490`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:566-578`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1960-2005`
- Gap / Note: The new fields now exist in live models and CloudKit serialization, but several payload rewrite helpers still drop them entirely. `updatingSchemaVersion`, `updatingLifecycleState`, and the invitee refresh/error-state payload rebuilds at `FamilyShareServices.swift:1375-1395` and `:1453-1473` reconstruct `FamilyShareProjectionPayload` without `rateSnapshotTimestamp`, `projectionServerTimestamp`, or `contentHash`. The migration coordinator also only bumps `schemaVersion`; it does not materialize the proposal's conservative defaults or preserve metadata through transformed states.

### REQ-005 Canonical projection rebuild uses proposal semantics, not legacy placeholders
- Proposal Source: Section `5.3 Exchange Rate Drift as Republish Trigger`, Section `6.1 Owner-Side Automatic Projection Republish`, Section `7.3 Canonical Projection Rebuild`, Acceptance Criteria items `4`, `36`, and `38` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:204-220`, `:292-322`, `:1001-1012`, `:1471`, `:1503`, `:1505`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1665-1770`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareContentHasher.swift:12-41`
- Gap / Note: `makeProjectionPayload()` now uses `GoalProgressCalculator` and computes `contentHash`, but the live rebuild still uses a placeholder `RateSnapshot(rates: [:])`, falls back to `goal.manualTotal` when calculator output is absent, hashes with `participantIDs: []`, and stamps `publishedAt` from local device time while leaving `projectionServerTimestamp` as `nil`. That is materially closer to the proposal than the previous audit, but it is not yet the proposal's canonical rebuild path.

### REQ-006 Owner-side freshness orchestration primitives exist for rate refresh, drift evaluation, and durable dirty replay
- Proposal Source: Section `5.4 Owner Foreground Rate Refresh Pipeline`, Section `5.5 Foreground Rate-Refresh Driver and Periodic Guard`, Section `6.5 Rate-Aware Republish Pipeline`, Section `6.9 Offline Mutation Queue and Durable Dirty-State Persistence`, Acceptance Criteria items `49` and `50` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:243-265`, `:475-500`, `:712-749`, `:1516-1518`)
- Status: `Partially Implemented`
- Evidence Type: `code, tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareForegroundRateRefreshDriver.swift:1-85`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareRateDriftEvaluator.swift:1-107`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift:1-250`
  - `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareDirtyStateStore.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareDirtyStateStoreTests.swift:1-52`
- Gap / Note: The repository now has most of the owner-side pieces as concrete types, but a repository-wide search found no production instantiation of `FamilyShareForegroundRateRefreshDriver`, `FamilyShareRateDriftEvaluator`, or `FamilyShareProjectionAutoRepublishCoordinator`. The coordinator file itself still says the "full integration ... requires wiring into `FamilyShareServices.swift`" and `publishAction` is never configured anywhere outside the file.

### REQ-007 All publish triggers route through a per-namespace auto-republish coordinator with no direct bypasses
- Proposal Source: Section `6.1.1 Per-Namespace Executor Composition`, Section `7.2.1 Complete Publish Trigger Inventory`, Section `7.2.2 Deprecated Direct Callers`, Acceptance Criteria items `34`, `35`, and `46` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:304-322`, `:961-987`, `:1501-1502`, `:1513`)
- Status: `Missing`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1073-1074`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift:14-16`
  - Repository search during this audit found no call sites for `FamilyShareProjectionAutoRepublishCoordinator(` or `setPublishAction(` outside the coordinator definition.
- Gap / Note: The production owner flow still performs a direct `_ = try await publishCoordinator.publish(payload)` from `shareAllGoals()`. That is the exact class of bypass the proposal forbids. Because the per-namespace coordinator is not instantiated and no publish action is injected, the required serialized coordinator ownership model is not active.

### REQ-008 Reconciliation barrier, three-phase invitee ordering, and server-timestamp propagation are live
- Proposal Source: Section `6.8.1 Pre-Publish Reconciliation Barrier`, Section `6.8.2 Version and Ordering Contract`, Acceptance Criteria items `20`, `36`, `37`, `41`, and `42` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:629-710`, `:1487`, `:1503-1504`, `:1508-1509`)
- Status: `Missing`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareReconciliationBarrier.swift:45-105`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift:189-216`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:165-186`
  - Repository search during this audit found no live invitee ordering logic that compares cached vs incoming `contentHash` or applies the documented `projectionServerTimestamp` fallback.
- Gap / Note: The barrier type exists, but the coordinator calls it with `lastKnownRemoteChangeDate: nil`, which makes the check trivially succeed. `startObservingImports()` has no production call site. The CloudKit publish path returns `Void`, not a server timestamp receipt, so `projectionServerTimestamp` is never populated after a successful publish. The codebase also has no live implementation of the invitee's three-phase ordering contract; only fields and comments exist.

### REQ-009 Invitee refresh scheduling owns foreground/visibility/manual refresh behavior
- Proposal Source: Section `6.3 Invitee Refresh Contract`, Section `6.4.3 Stale-Cause and Recovery Substates`, Section `7.4 Invitee Refresh Scheduler`, Acceptance Criteria items `28` and `52` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:361-377`, `:447-474`, `:1022-1033`, `:1495`, `:1519`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareInviteeRefreshScheduler.swift:1-151`
- Gap / Note: The scheduler state machine exists, but a repository-wide search found no production call sites for `onForegroundEntry`, `onFirstVisibility`, `onManualRefresh`, or `reportRefreshResult`. The file explicitly states that "the actual fetch is triggered externally", so the scheduler is not yet the single owning policy component required by the proposal.

### REQ-010 List and detail surfaces use the canonical freshness model and provenance contract
- Proposal Source: Section `6.6 Projection Metadata and Canonical Freshness Model`, Section `8.2 Invitee UX`, Acceptance Criteria items `24`, `29`, `31`, `48`, `52`, and `53` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:503-567`, `:1055-1165`, `:1491`, `:1496-1499`, `:1515`, `:1519-1520`)
- Status: `Partially Implemented`
- Evidence Type: `code, tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:36-45`, `:87-93`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift:105-115`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilyShareFreshnessHeaderView.swift`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilyShareFreshnessCardView.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessLabelTests.swift:15-97`
- Gap / Note: The list now renders `FamilyShareFreshnessHeaderView` from namespace freshness metadata, and the detail view does show a Freshness card. But the detail screen still keeps a legacy `"Updated"` metric pill at `SharedGoalDetailView.swift:100`, builds the Freshness card from `goal.lastUpdatedAt` instead of projection-level publish time, and passes `rateSnapshotAt: nil`, so it cannot satisfy the proposal's requirement to show both provenance rows with correct rate-governed semantics.

### REQ-011 Freshness timestamps come from the canonical server clock source, with post-publish propagation back into state
- Proposal Source: Section `6.6.1 Canonical Clock Source and Skew Handling`, Section `6.8.2 Version and Ordering Contract`, Acceptance Criteria item `38` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:510-536`, `:676-681`, `:1505`)
- Status: `Missing`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1663-1667`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1753-1769`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:165-186`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:361-417`
- Gap / Note: The live publish path still uses local `Date()` for `publishedAt` and `rateTimestamp`, returns `FamilySharePublicationResult.publishedAt` from the payload, and never captures the root record's `CKRecord.modificationDate` back into the published payload. `FamilyShareFreshnessPolicy` has clock-skew helpers, but the canonical server-timestamp source is not wired through the production publish flow.

### REQ-012 Proposal-required verification coverage exists and is runnable
- Proposal Source: Section `13) Test Plan` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1526-1696`)
- Status: `Missing`
- Evidence Type: `tests-found, inference`
- Evidence:
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessPolicyTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessLabelTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/GoalProgressCalculatorTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareMaterialityPolicyTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareContentHasherTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareDirtyStateStoreTests.swift`
- Gap / Note: The repository now has targeted unit-test files for several foundational primitives, but the audit did not find corresponding tests for the coordinator, scheduler, rate-drift evaluator, reconciliation barrier, or freshness UI behavior required by the proposal. A targeted `xcodebuild ... test` run for the family-sharing test classes also failed because scheme `CryptoSavingsTracker` is not configured for the `test` action, so even existing tests were not runnable through the main app scheme during this audit.

### REQ-013 Runtime evidence exists for multi-device ordering, compact layout, and accessibility behavior
- Proposal Source: Section `11) Rollout Plan and Validation`, Section `13) Test Plan` items covering accessibility, compact layout, barrier, and detail provenance (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1396-1411`, `:1592-1696`)
- Status: `Not Verifiable`
- Evidence Type: `inference`
- Evidence:
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination 'id=B344C46C-FC72-47F0-B150-A7F3478F09B2' -derivedDataPath "$DERIVED_DATA" build` passed during this audit
- Gap / Note: This audit did not run the app in the simulator, produce new screenshots, or validate multi-device CloudKit behavior. The repository state alone is insufficient to prove compact-layout compliance, accessibility disclosure behavior, or cross-device ordering correctness.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
- `git rev-parse --short HEAD`
- `git status --short | awk 'BEGIN{m=0;u=0} {if ($1=="??") u++; else m++} END{printf("dirty (%d modified, %d untracked)\n", m, u)}'`
- `rg -n -i "superseded|deprecated|replaced by|obsolete" docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md docs/proposals`
- `rg -n "contentHash|projectionServerTimestamp|rateSnapshotTimestamp" ios/CryptoSavingsTracker/...`
- `rg -n "FamilyShareProjectionAutoRepublishCoordinator\\(|setPublishAction\\(|FamilyShareForegroundRateRefreshDriver\\(|FamilyShareInviteeRefreshScheduler\\(" ios/CryptoSavingsTracker`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination 'id=B344C46C-FC72-47F0-B150-A7F3478F09B2' -derivedDataPath "$DERIVED_DATA" build` → passed
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination 'id=B344C46C-FC72-47F0-B150-A7F3478F09B2' -derivedDataPath "$DERIVED_DATA" test -only-testing:CryptoSavingsTrackerTests/...` → failed: `Scheme CryptoSavingsTracker is not currently configured for the test action`

## Recommended Next Actions

- Instantiate the per-namespace auto-republish coordinator inside `FamilyShareNamespaceActor`, inject `publishAction`, and remove direct publish calls from `FamilyShareServices`.
- Propagate `CKRecord.modificationDate` back into the published payload as `projectionServerTimestamp` and implement the invitee's three-phase `contentHash` ordering logic.
- Wire `FamilyShareForegroundRateRefreshDriver`, `FamilyShareRateDriftEvaluator`, `FamilyShareInviteeRefreshScheduler`, and `FamilyShareReconciliationBarrier.startObservingImports()` into the live family-sharing lifecycle.
- Preserve freshness metadata in every payload rewrite helper and make the detail Freshness card consume real projection-level `publishedAt` and `rateSnapshotTimestamp`.
- Add runnable orchestration/UI tests or expose a test-enabled scheme so the proposal's verification contract can be executed rather than inferred.
