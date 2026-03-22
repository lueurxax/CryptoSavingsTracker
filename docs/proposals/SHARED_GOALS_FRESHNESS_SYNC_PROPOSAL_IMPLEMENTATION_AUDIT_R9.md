# SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL Implementation Audit R9

| Field | Value |
|---|---|
| Proposal | `docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md` |
| Repository Root | `.` |
| Git SHA | `644ba70` |
| Working Tree | `dirty (35 modified, 69 untracked)` |
| Audited At | `2026-03-22T17:11:59+0200` |
| Proposal State | `Active` |
| Overall Status | `Partial` |

## Verdict

This revision closes the concrete implementation blockers called out in `R8`. Legacy cached invitee payloads are now canonicalized during freshness-schema migration, the owner-side foreground rate-refresh guard now uses an injected clock and passes a fresh targeted test, and `FamilyShareFreshnessLabel` clock-skew telemetry is now deterministic and green in the same targeted slice. The proposal remains only partially implemented because this audit did not execute the proposal-specific UI suite or capture live runtime proof for multi-device ordering, compact layout, dark mode, and accessibility behavior.

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
| Implemented | 11 |
| Partially Implemented | 1 |
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
- Gap / Note: The domain seams are in place and proposal-specific tests exist. Clock-skew telemetry correctness is evaluated separately in REQ-011.

### REQ-004 Live freshness schema and payload preservation are in place
- Proposal Source: Section `6.8.2 Version and Ordering Contract`, Section `7.0.4 Projection Cache Schema Migration` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:664-709`, `:846-859`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:464-500`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:565-588`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:639-676`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:2392-2416`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:450`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:486`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r9 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareForegroundRateRefreshDriverTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeRefreshSchedulerTests` (passed)
- Gap / Note: Legacy cache rehydration now materializes conservative freshness defaults (`rateSnapshotTimestamp ?? publishedAt`) instead of only bumping `schemaVersion`, and the acceptance slice proves the canonicalized payload survives rehydrate.

### REQ-005 Canonical projection rebuild uses current owner truth rather than cached placeholders
- Proposal Source: Section `5.3 Exchange Rate Drift as Republish Trigger`, Section `6.1 Owner-Side Automatic Projection Republish`, Section `7.3 Canonical Projection Rebuild` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:204-220`, `:292-322`, `:1001-1021`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:847`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:904-906`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1009-1020`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1603-1614`
- Gap / Note: `fetchActiveGoals()` prefers authoritative SwiftData reads via `activeGoalsProvider`, falls back to `lastSharedGoals` only on fetch failure, and post-publish bookkeeping feeds published state back into the pipeline.

### REQ-006 Owner-side freshness orchestration primitives exist and are bootstrapped in production
- Proposal Source: Section `5.4 Owner Foreground Rate Refresh Pipeline`, Section `5.5 Foreground Rate-Refresh Driver and Periodic Guard`, Section `6.5 Rate-Aware Republish Pipeline`, Section `6.9 Offline Mutation Queue and Durable Dirty-State Persistence` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:243-265`, `:475-500`, `:712-749`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:933-999`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1007-1011`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareForegroundRateRefreshDriver.swift:14-105`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift:142-147`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift:285-317`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:42-43`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareForegroundRateRefreshDriverTests.swift:90`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r9 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareForegroundRateRefreshDriverTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeRefreshSchedulerTests` (passed)
- Gap / Note: The driver is instantiated in production, the rate-drift evaluator is warmed from published state, dirty state is persisted, the reconciliation barrier receives a live remote-change provider, and the fresh targeted slice now proves the 15-minute guard fires when the primary cadence is missed.

### REQ-007 All publish triggers route through a per-namespace auto-republish coordinator with no direct publish bypass
- Proposal Source: Section `6.1.1 Per-Namespace Executor Composition`, Section `7.2.1 Complete Trigger Inventory`, Section `7.2.2 Deprecated Direct Callers`, Section `7.2.3 New Dirty Reason: .participantChange` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:304-322`, `:957-999`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1237-1268`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1346`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1355-1363`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1003`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1041`
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:195-203`
- Gap / Note: Initial sharing now goes through `publishNow(reason: .participantChange)` before `prepareShare(...)`, manual refresh uses `publishNow(reason: .manualRefresh)`, mutation/rate-drift paths still enter through `markDirty(...)`, and `.participantChange` has live production ingress.

### REQ-008 Invitee three-phase ordering and semantic dedup logic are implemented
- Proposal Source: Section `6.8.2 Version and Ordering Contract` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:664-709`)
- Status: `Implemented`
- Evidence Type: `code, tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1684-1744`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeOrderingTests.swift`
- Gap / Note: The live reconciliation path still applies version-floor rejection, semantic `contentHash` dedup, and pre-migration `projectionServerTimestamp` fallback.

### REQ-009 Invitee refresh scheduler owns foreground, visibility, and manual refresh behavior
- Proposal Source: Section `6.3 Invitee Refresh Contract`, Section `6.4.3 Stale-Cause and Recovery Substates`, Section `7.4 Invitee Refresh Scheduler` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:361-377`, `:447-474`, `:1022-1033`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:956-964`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1291-1296`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1362-1380`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareInviteeRefreshScheduler.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeRefreshSchedulerTests.swift`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r9 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareForegroundRateRefreshDriverTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeRefreshSchedulerTests` (passed)
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
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:235`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:266`
- Gap / Note: The live invitee mapping carries projection-level publish/rate/server-time metadata into both list and detail surfaces, and proposal-specific UI coverage exists for stale headers, empty namespaces, and accessibility timestamp collapse. Those UI tests were not executed in this audit.

### REQ-011 Canonical server-time freshness source and skew handling are propagated to visible behavior
- Proposal Source: Section `6.6.1 Canonical Clock Source and Skew Handling`, Section `6.8.2 Version and Ordering Contract` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:510-536`, `:664-709`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:190-199`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:464-500`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1603-1606`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift:3-15`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift:68-84`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessLabelTests.swift:28`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessLabelTests.swift:122`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r9 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareForegroundRateRefreshDriverTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeRefreshSchedulerTests` (passed)
- Gap / Note: Server-assigned timestamps still propagate back into payload/cache and continue to drive visible freshness semantics. Clock-skew telemetry is now emitted synchronously through the deduper and the dedicated future-timestamp test passes in the fresh targeted run.

### REQ-012 Proposal-required verification coverage exists and is runnable
- Proposal Source: Section `13) Test Plan` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1522-1719`)
- Status: `Partially Implemented`
- Evidence Type: `tests-run, tests-found`
- Evidence:
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r9 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareForegroundRateRefreshDriverTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeRefreshSchedulerTests` (passed)
  - `/tmp/proposal-audit-tests-r9/Logs/Test/Test-CryptoSavingsTrackerTests-2026.03.22_17-12-21-+0200.xcresult`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareForegroundRateRefreshDriverTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessLabelTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeRefreshSchedulerTests.swift`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift`
- Gap / Note: The proposal-specific unit/acceptance slice used to close the disputed `R8` gaps is now green, but this audit still did not execute the UI suite or broader proof matrix described in the proposal's test plan.

### REQ-013 Runtime evidence exists for multi-device ordering, compact layout, and accessibility behavior
- Proposal Source: Section `11) Delivery Plan`, Section `13) Test Plan` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1326-1463`, `:1522-1719`)
- Status: `Not Verifiable`
- Evidence Type: `inference`
- Evidence:
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:235`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:266`
- Gap / Note: This audit did not execute the proposal-specific UI suite or capture fresh live evidence for multi-device ordering, compact layout, dark mode, or VoiceOver behavior. Those runtime claims remain unproven.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
- `git -C /Users/user/Documents/CryptoSavingsTracker rev-parse --short HEAD`
- `git -C /Users/user/Documents/CryptoSavingsTracker status --short | awk 'BEGIN{m=0;u=0} {if ($1=="??") u++; else m++} END{printf("dirty (%d modified, %d untracked)\n", m, u)}'`
- `date +%Y-%m-%dT%H:%M:%S%z`
- `rg -n -i "superseded|deprecated|replaced by|obsolete" /Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md /Users/user/Documents/CryptoSavingsTracker/docs/proposals`
- `rg -n "clock: FamilyShareClock|performRefresh\(|performGuardCheck\(|lastRefreshAttempt = clock\.now\(|timeIntervalSince\(lastAttempt\)" ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareForegroundRateRefreshDriver.swift`
- `rg -n "TestClock|clock = TestClock|advance\(|performGuardCheck\(\)|testGuardTimerRefreshesWhenPrimaryRefreshWasMissed" ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareForegroundRateRefreshDriverTests.swift`
- `rg -n "FamilyShareClockSkewTelemetryDeduper|reset\(|telemetry\.track\(|Task \{|clockSkewDetected|NSLock" ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift`
- `rg -n "reset\(\)|testClockSkewTelemetry_emitsWhenTimestampFarInFuture|flushAsyncWork|FamilyShareClockSkewTelemetryDeduper" ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessLabelTests.swift`
- `rg -n "migratedForCurrentFreshnessSchema|schemaVersion: currentVersion|rateSnapshotTimestamp \?\? publishedAt|projectionServerTimestamp|contentHash" ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift`
- `sed -n '520,570p' ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift`
- `rg -n "shareAllGoals\(|publishNow\(reason: \.participantChange\)|noteOwnerParticipantsDidChange\(|prepareShare\(" ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift`
- `rg -n "FamilySharingUITests|FreshnessHeader|FreshnessCard|VoiceOver|AX|compact|dark mode" ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift`
- `rg -n "testInviteeStaleNamespaceShowsFreshnessHeader|testInviteeEmptyNamespaceShowsFreshnessHeaderButNoRows|testInviteeDetailFreshnessCardCollapsesExactTimestampAtAccessibilitySize" ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift`
- `rg -n "testLegacyInviteeCachePayloadIsCanonicalizedOnRehydrate|testLegacyFreshnessMigrationDefaultsMissingMetadataConservatively|testShareAllGoalsPublishesOwnerStateAndPendingShareRequest" ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift`
- `rg -n "publishNow\(reason: \.manualRefresh\)|markDirty\(|setRemoteChangeDateProvider|lastKnownRemoteChangeDate|persistDirtyState|loadDirtyState|projectionVersion" ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareReconciliationBarrier.swift ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift`
- `xcodebuild -project /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r9 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareForegroundRateRefreshDriverTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeRefreshSchedulerTests`

## Recommended Next Actions

- Execute the proposal-specific UI suite in `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift` and preserve the resulting `.xcresult`.
- Capture fresh runtime evidence for multi-device ordering, compact layout, dark mode, and VoiceOver behavior if you want the audit roll-up to move from `Partial` to `Implemented`.
