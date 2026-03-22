# SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL Implementation Audit R5

| Field | Value |
|---|---|
| Proposal | `docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md` |
| Repository Root | `.` |
| Git SHA | `644ba70` |
| Working Tree | `dirty (25 modified, 58 untracked)` |
| Audited At | `2026-03-22T12:49:21+0200` |
| Proposal State | `Active` |
| Overall Status | `Not Implemented` |

## Verdict

The implementation is clearly ahead of `R4`: the initial share flow now enters the auto-republish coordinator instead of publishing directly, `fetchActiveGoals()` no longer returns an empty array, the payload builder now computes real rate snapshots and includes real participant IDs in `contentHash`, the rate-drift evaluator is instantiated in production, the list freshness header now prefers `projectionServerTimestamp`, and the family-sharing test slice now includes passing invitee-ordering and coordinator tests. The proposal still is not implemented end to end. One contract-level blocker remains: not all publish-triggering actions actually route through the coordinator yet, because `.participantChange` still has no live trigger path and the rate-drift evaluator is started with empty tracked inputs and is never updated from owner truth. Several important paths also remain partial: the auto-republish rebuild still uses cached `lastSharedGoals` rather than authoritative datastore fetches, the invitee refresh scheduler still does not own manual/visibility/result flows, and the detail freshness card still does not use the canonical server-backed publish timestamp.

## Proposal Contract

### Scope

- owner-side freshness maintenance through foreground rate refresh, drift evaluation, dirty tracking, and automatic republish
- canonical projection rebuild from current owner truth using `GoalProgressCalculator`
- additive freshness metadata in payload/cache/CloudKit plus the documented three-phase invitee ordering contract
- invitee refresh scheduling and per-namespace freshness UI in list and detail surfaces
- rollout, telemetry, migration safety, and explicit verification coverage

### Locked Decisions

- `projectionVersion` remains the atomic publish token; `contentHash` is the primary semantic dedup signal and `projectionServerTimestamp` is only the pre-migration fallback
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

- targeted unit coverage for calculator, materiality, freshness policy/label, dirty-state persistence, barrier, debounce/coalescing, scheduler, and ordering
- integration coverage for publish/fetch loop, rate-drift pipeline, and offline recovery
- UI/accessibility coverage for list/detail freshness surfaces
- runnable build/test evidence, not code inspection alone

### Explicit Exclusions

- this audit does not modify proposal or implementation code
- CloudKit multi-device correctness is not claimed without direct runtime evidence
- inference alone is not enough to mark a requirement `Implemented`

## Requirement Summary

| Status | Count |
|---|---:|
| Implemented | 5 |
| Partially Implemented | 6 |
| Missing | 1 |
| Not Verifiable | 1 |

## Requirement Audit

### REQ-001 Exchange-rate refresh prerequisite exists
- Proposal Source: Section `5.5 Foreground Rate-Refresh Driver and Periodic Guard`, Section `7.0.1 ExchangeRateService Changes` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:255-265`, `:760-792`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/Protocols/ServiceProtocols.swift:47-49`
  - `ios/CryptoSavingsTracker/Services/ExchangeRateService.swift:398-427`
  - `ios/CryptoSavingsTracker/Utilities/NotificationNames.swift:19-23`
- Gap / Note: The service-level API and notification surface are present. Live orchestration is evaluated separately in REQ-006 and REQ-007.

### REQ-002 Shared-goal mutation notifications are normalized at the service layer
- Proposal Source: Section `7.0.2 PersistenceMutationServices Notification Normalization`, Section `7.2.1 Complete Trigger Inventory` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:794-805`, `:957-977`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/NotificationNames.swift:23`
  - `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:68`, `:200`, `:213`, `:298`, `:317`
  - `ios/CryptoSavingsTracker/Services/AllocationService.swift:114`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionMutationObserver.swift:55-64`
- Gap / Note: Compared with `R4`, the observer now distinguishes `goalMutation`, `assetMutation`, and `transactionMutation`. Participant and owner-metadata mutations are still not wired and are called out under REQ-007.

### REQ-003 Canonical freshness primitives are extracted into reusable domain code
- Proposal Source: Section `5.3.1 Materiality Policy`, Section `6.6 Projection Metadata and Canonical Freshness Model`, Section `7.0.3 Pure Domain Calculator Extraction` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:222-241`, `:503-567`, `:807-844`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/GoalProgressCalculator.swift:11`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareMaterialityPolicy.swift:9`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift:10`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r5 test -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareMaterialityPolicyTests -only-testing:CryptoSavingsTrackerTests/GoalProgressCalculatorTests` → passed on 2026-03-22
- Gap / Note: The pure freshness primitives are now well-supported by passing targeted tests. Remaining gaps are in orchestration and data ownership.

### REQ-004 Live freshness schema and payload preservation are in place
- Proposal Source: Section `6.8.2 Version and Ordering Contract`, Section `7.0.4 Projection Cache Schema Migration` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:664-709`, `:846-859`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift:317-326`, `:423-430`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:464-500`, `:571-588`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1531-1545`, `:1612-1626`, `:2148-2185`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:637-644`
- Gap / Note: Additive fields (`rateSnapshotTimestamp`, `projectionServerTimestamp`, `contentHash`) now round-trip through payload/cache/CloudKit and survive rewrite paths. Migration is still shallow: `ensureCompatible()` still only bumps `schemaVersion` and does not materialize the proposal's conservative defaults for pre-freshness cached payloads.

### REQ-005 Canonical projection rebuild uses current owner truth rather than cached placeholders
- Proposal Source: Section `5.3 Exchange Rate Drift as Republish Trigger`, Section `6.1 Owner-Side Automatic Projection Republish`, Section `7.3 Canonical Projection Rebuild` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:204-220`, `:292-322`, `:1001-1012`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:948-952`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1000-1008`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1837-1854`, `:1896-1906`
- Gap / Note: This is materially improved from `R4`: the rebuild no longer starts from `[]`, it now fetches exchange rates for active currency pairs, and `contentHash` now includes real participant IDs. The rebuild still is not authoritative current owner truth because `fetchActiveGoals()` only returns cached `lastSharedGoals` from the latest `shareAllGoals()` call. That cache can miss newly created goals, deleted goals, and other datastore changes that were never in the last shared snapshot.

### REQ-006 Owner-side freshness orchestration primitives exist and are bootstrapped in production
- Proposal Source: Section `5.4 Owner Foreground Rate Refresh Pipeline`, Section `5.5 Foreground Rate-Refresh Driver and Periodic Guard`, Section `6.5 Rate-Aware Republish Pipeline`, Section `6.9 Offline Mutation Queue and Durable Dirty-State Persistence` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:243-265`, `:475-500`, `:712-749`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:914-997`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:42`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareForegroundRateRefreshDriver.swift:29-87`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift:189-212`
- Gap / Note: Compared with `R4`, production now instantiates and starts `FamilyShareRateDriftEvaluator` as well as the rest of the pipeline. The runtime path is still incomplete: the evaluator is started with `goalInputs: []` and `lastPublished: [:]`, `updateTrackedGoals()` has no production call sites, and the reconciliation barrier is still always called with `lastKnownRemoteChangeDate: nil`, so the publish fence still trivially passes.

### REQ-007 All publish triggers route through a per-namespace auto-republish coordinator with no trigger gaps
- Proposal Source: Section `6.1.1 Per-Namespace Executor Composition`, Section `7.2.1 Complete Trigger Inventory`, Section `7.2.2 Deprecated Direct Callers` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:304-322`, `:957-987`)
- Status: `Missing`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1189-1193`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:985-988`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1236-1267`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionMutationObserver.swift:55-64`
  - Repository search during this audit found no production call sites for `updateTrackedGoals(` and no `markDirty(reason: .participantChange)`
- Gap / Note: `R4`'s initial-share direct bypass is fixed: `shareAllGoals()` now enters the coordinator with `.manualRefresh`. The trigger-inventory contract is still not satisfied end to end. `.participantChange` still has no live ingress, and the rate-drift evaluator is started without tracked goals or last-published amounts, so its `.rateDrift` pathway is not yet connected to real owner data.

### REQ-008 Invitee three-phase ordering and semantic dedup logic are implemented
- Proposal Source: Section `6.8.2 Version and Ordering Contract` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:664-709`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1470-1497`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeOrderingTests.swift`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r5 test -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeOrderingTests` → passed on 2026-03-22
- Gap / Note: This is stronger than `R4`: the ordering logic is now both present in the live refresh path and covered by a dedicated test file for version floor, content-hash dedup, and pre-migration timestamp fallback.

### REQ-009 Invitee refresh scheduler owns foreground, visibility, and manual refresh behavior
- Proposal Source: Section `6.3 Invitee Refresh Contract`, Section `6.4.3 Stale-Cause and Recovery Substates`, Section `7.4 Invitee Refresh Scheduler` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:361-377`, `:447-474`, `:1022-1033`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1015-1017`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1279-1292`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareInviteeRefreshScheduler.swift:45-107`
- Gap / Note: This improved from `R4`: `refreshAllState()` now routes namespace keys through `inviteeRefreshScheduler.onForegroundEntry(...)`. The scheduler still does not own first-visibility, manual-refresh, or refresh-result reporting. `handlePrimaryAction(for:)` still calls `refreshNamespace()` directly, and there are still no production call sites for `onFirstVisibility`, `onManualRefresh`, or `reportRefreshResult`.

### REQ-010 Invitee freshness UI exists and receives projection-level metadata on the live mapping path
- Proposal Source: Section `6.6 Projection Metadata and Canonical Freshness Model`, Section `8.2 Invitee UX` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:503-567`, `:1051-1183`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:750-774`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:87-97`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift:104-115`
- Gap / Note: The live invitee mapping now carries `publishedAt`, `rateSnapshotTimestamp`, and section-level `projectionServerTimestamp`, and both list/detail freshness UI paths are present. Canonical server-time correctness for the detail path remains a separate gap under REQ-011.

### REQ-011 Canonical server-time freshness source is propagated back and used by visible freshness semantics
- Proposal Source: Section `6.6.1 Canonical Clock Source and Skew Handling`, Section `6.8.2 Version and Ordering Contract` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:510-536`, `:664-709`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:190-198`, `:469-500`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:952-967`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:88-97`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift:108-113`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:390-397`, `:442-444`
- Gap / Note: This is improved from `R4`: the list header now prefers `projectionServerTimestamp` over device-local `publishedAt`. The detail path still does not. `FamilyShareInviteeGoalProjection` has no `projectionServerTimestamp`, `SharedGoalDetailView` still builds the card from `goal.lastUpdatedAt`, and `makeProjectionPayload()` still stamps a local `publishedAt = Date()` before server metadata arrives.

### REQ-012 Proposal-required verification coverage exists and is runnable
- Proposal Source: Section `13) Test Plan` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1522-1719`)
- Status: `Partially Implemented`
- Evidence Type: `tests-run, tests-found`
- Evidence:
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r5 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareContentHasherTests -only-testing:CryptoSavingsTrackerTests/FamilyShareDirtyStateStoreTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeOrderingTests -only-testing:CryptoSavingsTrackerTests/FamilyShareMaterialityPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareProjectionAutoRepublishCoordinatorTests -only-testing:CryptoSavingsTrackerTests/GoalProgressCalculatorTests` → passed (`67` tests, `0` failures) on 2026-03-22
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeOrderingTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareProjectionAutoRepublishCoordinatorTests.swift`
- Gap / Note: Verification is stronger than `R4`, but it is still not complete against the proposal. There are still no dedicated tests for `FamilyShareRateDriftEvaluator`, `FamilyShareInviteeRefreshScheduler`, `FamilyShareReconciliationBarrier`, or the proposal's UI/accessibility freshness surfaces.

### REQ-013 Runtime evidence exists for multi-device ordering, compact layout, and accessibility behavior
- Proposal Source: Section `11) Delivery Plan`, Section `13) Test Plan` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1326-1463`, `:1522-1719`)
- Status: `Not Verifiable`
- Evidence Type: `inference`
- Evidence:
  - Targeted family-sharing test slice succeeded during this audit
- Gap / Note: This audit still did not launch the app to capture live freshness renders, multi-device ordering behavior, compact layout, dark mode, or VoiceOver behavior. Those runtime claims remain unproven.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
- `git rev-parse --short HEAD`
- `git status --short | awk 'BEGIN{m=0;u=0} {if ($1=="??") u++; else m++} END{printf("dirty (%d modified, %d untracked)\n", m, u)}'`
- `date +%Y-%m-%dT%H:%M:%S%z`
- `rg -n -i "superseded|deprecated|replaced by|obsolete" docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md docs/proposals`
- `rg -n "fetchActiveGoals\\(|return \\[\\]|participantIDs: \\[\\]|publishedAt = Date\\(|rateSnapshot = RateSnapshot\\(rates: \\[:\\]" ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift`
- `rg -n "shareAllGoals\\(|publishCoordinator\\.publish\\(|cloudSync\\?\\.publishProjection\\(|return try await publisher\\.publish\\(" ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift`
- `rg -n "FamilyShareRateDriftEvaluator\\(|onDirtyEvent\\?\\(.rateDrift|ratesDidRefresh|exchangeRatesDidRefresh|rateRefreshDriver\\?\\.start\\(|onForegroundEntry\\(|onFirstVisibility\\(|onManualRefresh\\(|reportRefreshResult\\(" ios/CryptoSavingsTracker`
- `rg -n "updateTrackedGoals\\(" ios/CryptoSavingsTracker`
- `find ios/CryptoSavingsTrackerTests -maxdepth 2 -type f \( -name '*FamilyShare*Tests.swift' -o -name 'GoalProgressCalculatorTests.swift' \) | sort`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r5 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareContentHasherTests -only-testing:CryptoSavingsTrackerTests/FamilyShareDirtyStateStoreTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeOrderingTests -only-testing:CryptoSavingsTrackerTests/FamilyShareMaterialityPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareProjectionAutoRepublishCoordinatorTests -only-testing:CryptoSavingsTrackerTests/GoalProgressCalculatorTests`

## Recommended Next Actions

- Replace `lastSharedGoals`-based rebuilds with authoritative owner datastore fetches so auto-republish sees newly created, deleted, and mutated goals.
- Wire real tracked goal inputs and last-published amounts into `FamilyShareRateDriftEvaluator`, and update them whenever projection content changes.
- Add a real `.participantChange` ingress for owner display-name and participant-list mutations.
- Route invitee manual refresh, first visibility, and refresh-result reporting through `FamilyShareInviteeRefreshScheduler` instead of calling `refreshNamespace()` directly.
- Propagate `projectionServerTimestamp` into the goal-level detail path so the Freshness card uses the same canonical publish clock as the list header.
