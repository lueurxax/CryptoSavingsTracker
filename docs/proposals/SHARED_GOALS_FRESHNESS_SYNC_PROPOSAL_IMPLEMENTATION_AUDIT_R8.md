# SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL Implementation Audit R8

| Field | Value |
|---|---|
| Proposal | `docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md` |
| Repository Root | `.` |
| Git SHA | `644ba70` |
| Working Tree | `dirty (33 modified, 67 untracked)` |
| Audited At | `2026-03-22T16:17:17+0200` |
| Proposal State | `Active` |
| Overall Status | `Partial` |

## Verdict

This revision is materially ahead of `R7`. The trigger-inventory contract is no longer the blocking hole it was before: initial sharing now publishes through `FamilyShareProjectionAutoRepublishCoordinator.publishNow(...)`, `.participantChange` has live production ingress, the reconciliation barrier now receives a remote-change provider, and the repository now contains proposal-specific unit/UI coverage for the rate-refresh driver, rate-drift evaluator, invitee refresh scheduler, reconciliation barrier, and freshness surfaces. The proposal is still only partially implemented. Cache migration still only bumps `schemaVersion` for older payloads, the owner-side 15-minute safety-net refresh is currently red in a fresh targeted test, clock-skew telemetry from `FamilyShareFreshnessLabel` is currently red in a fresh targeted test, and runtime proof for multi-device/accessibility behavior is still missing.

## Proposal Contract

### Scope

- owner-side freshness maintenance through foreground rate refresh, drift evaluation, dirty tracking, and automatic republish
- canonical projection rebuild from current owner truth using `GoalProgressCalculator`
- additive freshness metadata in payload/cache/CloudKit plus the documented three-phase invitee ordering contract
- invitee refresh scheduling and per-namespace freshness UI in list and detail surfaces
- rollout, telemetry, migration safety, and explicit verification coverage

### Locked Decisions

- `projectionVersion` remains the atomic publish token; `contentHash` is the semantic dedup key and `projectionServerTimestamp` is the pre-migration fallback
- `currentAmount` must come from `GoalProgressCalculator`, not `goal.manualTotal`
- all publish-triggering actions route through a per-namespace auto-republish coordinator
- list and detail surfaces share a single canonical freshness model, `FamilyShareFreshnessLabel`
- detail freshness provenance is derived from projection-level publish/rate metadata, not goal-local edit timestamps

### Acceptance Criteria

- owner edits and rate drift republish shared projections without manual share UI workarounds
- freshness is composite (`max(publishAge, rateAge)`) and rendered per namespace
- no direct publish bypass survives outside the coordinator / namespace actor boundary
- schema migration remains additive and rollback-safe
- invitee ordering follows the proposal's atomic-version + contentHash + server-timestamp fallback rules

### Test / Evidence Requirements

- targeted unit coverage for calculator, materiality, freshness policy/label, dirty-state persistence, barrier, debounce/coalescing, scheduler, ordering, and foreground rate refresh
- integration/acceptance coverage for publish/fetch loop, rate-drift pipeline, invitee refresh behavior, and offline recovery
- UI/accessibility coverage for list/detail freshness surfaces
- runnable build/test evidence, not code inspection alone

### Explicit Exclusions

- this audit does not modify proposal or implementation code
- CloudKit multi-device correctness is not claimed without direct runtime evidence
- inference alone is not enough to mark a requirement `Implemented`

## Requirement Summary

| Status | Count |
|---|---:|
| Implemented | 8 |
| Partially Implemented | 4 |
| Missing | 0 |
| Not Verifiable | 1 |

## Requirement Audit

### REQ-001 Exchange-rate refresh prerequisite exists
- Proposal Source: Section `5.5 Foreground Rate-Refresh Driver and Periodic Guard`, Section `7.0.1 ExchangeRateService Changes` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:255-265`, `:760-792`)
- Status: `Implemented`
- Evidence Type: `code, tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/Protocols/ServiceProtocols.swift`
  - `ios/CryptoSavingsTracker/Services/ExchangeRateService.swift`
  - `ios/CryptoSavingsTracker/Utilities/NotificationNames.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareForegroundRateRefreshDriver.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/NotificationCenterRateRefreshSourceTests.swift`
- Gap / Note: The service/API surface and refresh-notification seam exist. Owner-side orchestration quality is assessed separately in REQ-006.

### REQ-002 Shared-goal mutation notifications are normalized at the service layer
- Proposal Source: Section `7.0.2 PersistenceMutationServices Notification Normalization`, Section `7.2.1 Complete Trigger Inventory` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:794-805`, `:957-977`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/NotificationNames.swift`
  - `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift`
  - `ios/CryptoSavingsTracker/Services/AllocationService.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionMutationObserver.swift`
- Gap / Note: Goal, asset, transaction, allocation, and import/backfill mutations are normalized into the family-sharing pipeline. Participant/share-sheet lifecycle triggers are assessed separately in REQ-007.

### REQ-003 Canonical freshness primitives are extracted into reusable domain code
- Proposal Source: Section `5.3.1 Materiality Policy`, Section `6.6 Projection Metadata and Canonical Freshness Model`, Section `7.0.3 Pure Domain Calculator Extraction` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:222-241`, `:503-567`, `:807-844`)
- Status: `Implemented`
- Evidence Type: `code, tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/GoalProgressCalculator.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareMaterialityPolicy.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessPolicy.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/GoalProgressCalculatorTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareMaterialityPolicyTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessPolicyTests.swift`
- Gap / Note: The domain seams are in place and proposal-specific tests exist. Clock-skew telemetry correctness is not folded into this requirement; it is evaluated in REQ-011.

### REQ-004 Live freshness schema and payload preservation are in place
- Proposal Source: Section `6.8.2 Version and Ordering Contract`, Section `7.0.4 Projection Cache Schema Migration` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:664-709`, `:846-859`)
- Status: `Partially Implemented`
- Evidence Type: `code, tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:464-500`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:565-588`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:547-660`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift`
- Gap / Note: Additive fields (`rateSnapshotTimestamp`, `projectionServerTimestamp`, `contentHash`) round-trip through payload/cache/CloudKit and future-schema quarantine coverage exists. The migration path is still shallow: `ensureCompatible()` only rewrites `schemaVersion` for older payloads and does not materialize conservative freshness defaults for legacy cached projections.

### REQ-005 Canonical projection rebuild uses current owner truth rather than cached placeholders
- Proposal Source: Section `5.3 Exchange Rate Drift as Republish Trigger`, Section `6.1 Owner-Side Automatic Projection Republish`, Section `7.3 Canonical Projection Rebuild` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:204-220`, `:292-322`, `:1001-1021`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:847`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:904-906`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1009-1020`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1603-1614`
- Gap / Note: `fetchActiveGoals()` now prefers authoritative SwiftData reads via `activeGoalsProvider`, falls back to `lastSharedGoals` only on fetch failure, and post-publish bookkeeping feeds the published state back into the pipeline.

### REQ-006 Owner-side freshness orchestration primitives exist and are bootstrapped in production
- Proposal Source: Section `5.4 Owner Foreground Rate Refresh Pipeline`, Section `5.5 Foreground Rate-Refresh Driver and Periodic Guard`, Section `6.5 Rate-Aware Republish Pipeline`, Section `6.9 Offline Mutation Queue and Durable Dirty-State Persistence` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:243-265`, `:475-500`, `:712-749`)
- Status: `Partially Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:933-999`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1007-1011`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareForegroundRateRefreshDriver.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift:142-147`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift:285-317`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:42-43`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareForegroundRateRefreshDriverTests.swift:72-97`
- Gap / Note: The pipeline is substantially closer than `R7`: the driver is instantiated in production, the rate-drift evaluator is warmed from real published state, the auto-republish coordinator persists dirty state, and the reconciliation barrier now receives a live remote-change provider. It is still not closed because the fresh targeted test `testGuardTimerRefreshesWhenPrimaryRefreshWasMissed` is currently red: the safety-net guard did not force the second refresh promised by the proposal.

### REQ-007 All publish triggers route through a per-namespace auto-republish coordinator with no direct publish bypass
- Proposal Source: Section `6.1.1 Per-Namespace Executor Composition`, Section `7.2.1 Complete Trigger Inventory`, Section `7.2.2 Deprecated Direct Callers`, Section `7.2.3 New Dirty Reason: .participantChange` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:304-322`, `:957-999`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:954-971`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1002-1007`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1217-1235`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1308-1314`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1322-1330`
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:195-203`
  - Repository search during this audit found no production caller that invokes `publishProjectionImmediately(...)` outside the coordinator-owned publish action
- Gap / Note: This is the major closure relative to `R7`. Initial sharing now goes through `publishNow(reason: .participantChange)` before `prepareShare(...)`, manual owner refresh uses `publishNow(reason: .manualRefresh)`, mutation/rate-drift paths still enter through `markDirty(...)`, and `.participantChange` has live production ingress.

### REQ-008 Invitee three-phase ordering and semantic dedup logic are implemented
- Proposal Source: Section `6.8.2 Version and Ordering Contract` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:664-709`)
- Status: `Implemented`
- Evidence Type: `code, tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1684-1707`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeOrderingTests.swift`
- Gap / Note: The live reconciliation path still applies version-floor rejection, semantic content-hash dedup, and pre-migration server-timestamp fallback.

### REQ-009 Invitee refresh scheduler owns foreground, visibility, and manual refresh behavior
- Proposal Source: Section `6.3 Invitee Refresh Contract`, Section `6.4.3 Stale-Cause and Recovery Substates`, Section `7.4 Invitee Refresh Scheduler` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:361-377`, `:447-474`, `:1022-1033`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:956-964`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1291-1296`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1362-1380`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareInviteeRefreshScheduler.swift:49-84`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareInviteeRefreshScheduler.swift:150-165`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeRefreshSchedulerTests.swift`
- Gap / Note: Manual refresh, first visibility, and scene-phase foreground entry are all wired through the scheduler, and the dedicated scheduler suite passed in the fresh targeted run.

### REQ-010 Invitee freshness UI exists and receives projection-level metadata on the live mapping path
- Proposal Source: Section `6.6 Projection Metadata and Canonical Freshness Model`, Section `8.2 Invitee UX` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:503-567`, `:1051-1183`)
- Status: `Implemented`
- Evidence Type: `code, tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:742-777`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilyShareFreshnessHeaderView.swift`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilyShareFreshnessCardView.swift`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift`
- Gap / Note: The live invitee mapping still carries projection-level publish/rate/server-time metadata into both list and detail surfaces, and dedicated UI coverage now exists for stale headers, detail freshness cards, empty/unavailable namespaces, and AX timestamp collapse.

### REQ-011 Canonical server-time freshness source and skew handling are propagated to visible behavior
- Proposal Source: Section `6.6.1 Canonical Clock Source and Skew Handling`, Section `6.8.2 Version and Ordering Contract` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:510-536`, `:664-709`)
- Status: `Partially Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:190-199`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:464-500`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1603-1606`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift:41-84`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessLabelTests.swift:116-132`
- Gap / Note: Server-assigned timestamps are still propagated back into payload/cache and continue to drive visible freshness semantics. The skew-handling contract is not fully closed because the fresh targeted test `testClockSkewTelemetry_emitsWhenTimestampFarInFuture` is currently red, so the promised clock-skew telemetry path is not behaving reliably.

### REQ-012 Proposal-required verification coverage exists and is runnable
- Proposal Source: Section `13) Test Plan` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1522-1719`)
- Status: `Partially Implemented`
- Evidence Type: `tests-run, tests-found`
- Evidence:
  - `xcodebuild -project /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r8 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareContentHasherTests -only-testing:CryptoSavingsTrackerTests/FamilyShareDirtyStateStoreTests -only-testing:CryptoSavingsTrackerTests/FamilyShareForegroundRateRefreshDriverTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeOrderingTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeRefreshSchedulerTests -only-testing:CryptoSavingsTrackerTests/FamilyShareMaterialityPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareProjectionAutoRepublishCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareRateDriftEvaluatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareReconciliationBarrierTests -only-testing:CryptoSavingsTrackerTests/GoalProgressCalculatorTests -only-testing:CryptoSavingsTrackerTests/NotificationCenterRateRefreshSourceTests`
  - Fresh failures observed in:
    - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareForegroundRateRefreshDriverTests.swift:97`
    - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessLabelTests.swift:132`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareForegroundRateRefreshDriverTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareRateDriftEvaluatorTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeRefreshSchedulerTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareReconciliationBarrierTests.swift`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift`
- Gap / Note: Coverage is meaningfully better than `R7` and now includes the missing proposal-specific suites. The verification story is still not green: the fresh targeted unit slice surfaced at least two regressions, and the `xcodebuild` process had to be terminated after those failures, leaving an incomplete `.xcresult` bundle in `/tmp/proposal-audit-tests-r8/Logs/Test/`.

### REQ-013 Runtime evidence exists for multi-device ordering, compact layout, and accessibility behavior
- Proposal Source: Section `11) Delivery Plan`, Section `13) Test Plan` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1326-1463`, `:1522-1719`)
- Status: `Not Verifiable`
- Evidence Type: `inference`
- Evidence:
  - Proposal-specific UI tests now exist in `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift`
- Gap / Note: This audit did not execute the UI suite or capture fresh live evidence for multi-device ordering, compact layout, dark mode, or VoiceOver behavior. Those runtime claims remain unproven.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
- `git -C /Users/user/Documents/CryptoSavingsTracker rev-parse --short HEAD`
- `git -C /Users/user/Documents/CryptoSavingsTracker status --short | awk 'BEGIN{m=0;u=0} {if ($1=="??") u++; else m++} END{printf("dirty (%d modified, %d untracked)\n", m, u)}'`
- `date +%Y-%m-%dT%H:%M:%S%z`
- `rg -n -i "superseded|deprecated|replaced by|obsolete" /Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md /Users/user/Documents/CryptoSavingsTracker/docs/proposals`
- `rg -n "publishProjectionImmediately\(|publishNow\(|publishCoordinator\.publish\(|markDirty\(|participantChange|manualRefresh|prepareShare\(" ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionMutationObserver.swift ios/CryptoSavingsTracker/Views/FamilySharing ios/CryptoSavingsTracker/ViewModels`
- `rg -n "checkBarrier\(|lastKnownRemoteChangeDate|setRemoteChangeDateProvider|remoteChangeDateProvider" ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareReconciliationBarrier.swift ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift`
- `rg -n "FamilyShareRateDriftEvaluator|FamilyShareInviteeRefreshScheduler|FamilyShareReconciliationBarrier|SharedGoalDetailView|SharedGoalsSectionView|accessibility|VoiceOver" ios/CryptoSavingsTrackerTests ios/CryptoSavingsTrackerUITests`
- `find /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/FamilySharing -maxdepth 1 -type f | sort`
- `xcodebuild -project /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r8 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareContentHasherTests -only-testing:CryptoSavingsTrackerTests/FamilyShareDirtyStateStoreTests -only-testing:CryptoSavingsTrackerTests/FamilyShareForegroundRateRefreshDriverTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeOrderingTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeRefreshSchedulerTests -only-testing:CryptoSavingsTrackerTests/FamilyShareMaterialityPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareProjectionAutoRepublishCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareRateDriftEvaluatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareReconciliationBarrierTests -only-testing:CryptoSavingsTrackerTests/GoalProgressCalculatorTests -only-testing:CryptoSavingsTrackerTests/NotificationCenterRateRefreshSourceTests`

## Recommended Next Actions

- Fix `FamilyShareForegroundRateRefreshDriver.performGuardCheck()` so the 15-minute guard reliably forces a refresh when the primary 5-minute cadence is missed, then re-run the targeted unit slice.
- Fix `FamilyShareFreshnessLabel` clock-skew telemetry emission so `clockSkewDetected` is deterministically emitted for future timestamps beyond the proposal tolerance.
- Deepen `FamilyShareCacheMigrationCoordinator.ensureCompatible()` so legacy caches receive conservative freshness defaults instead of a schema-version bump only.
- Re-run the now-expanded family-sharing unit slice to green, then execute `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift` and capture fresh runtime evidence for accessibility and multi-device ordering.
