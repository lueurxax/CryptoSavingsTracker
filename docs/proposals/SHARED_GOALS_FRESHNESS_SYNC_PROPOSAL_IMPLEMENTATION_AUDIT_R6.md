# SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL Implementation Audit R6

| Field | Value |
|---|---|
| Proposal | `docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md` |
| Repository Root | `.` |
| Git SHA | `644ba70` |
| Working Tree | `dirty (25 modified, 59 untracked)` |
| Audited At | `2026-03-22T13:36:31+0200` |
| Proposal State | `Active` |
| Overall Status | `Not Implemented` |

## Verdict

The implementation is meaningfully closer than `R5`. Owner share now updates the rate-drift evaluator with real goal inputs and last-published amounts, and both list and detail freshness surfaces now prefer `projectionServerTimestamp`. The proposal still is not implemented end to end. One contract-level blocker remains: the publish-trigger inventory is still incomplete because `.participantChange` has no live production ingress, so not every publish-triggering action is serialized through the coordinator. Several areas also remain partial: auto-republish still rebuilds from cached `lastSharedGoals` instead of authoritative owner truth, the reconciliation barrier still runs with `lastKnownRemoteChangeDate: nil`, invitee manual/visibility/result flows still bypass the scheduler, cache migration is still schema-bump-only, and the proposal-mandated verification matrix remains incomplete.

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
| Implemented | 6 |
| Partially Implemented | 5 |
| Missing | 1 |
| Not Verifiable | 1 |

## Requirement Audit

### REQ-001 Exchange-rate refresh prerequisite exists
- Proposal Source: Section `5.5 Foreground Rate-Refresh Driver and Periodic Guard`, Section `7.0.1 ExchangeRateService Changes` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:255-265`, `:760-792`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/Protocols/ServiceProtocols.swift`
  - `ios/CryptoSavingsTracker/Services/ExchangeRateService.swift`
  - `ios/CryptoSavingsTracker/Utilities/NotificationNames.swift`
- Gap / Note: The service-level API and notification surface are present. Active owner-side orchestration is evaluated separately in REQ-006.

### REQ-002 Shared-goal mutation notifications are normalized at the service layer
- Proposal Source: Section `7.0.2 PersistenceMutationServices Notification Normalization`, Section `7.2.1 Complete Trigger Inventory` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:794-805`, `:957-977`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/NotificationNames.swift`
  - `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift`
  - `ios/CryptoSavingsTracker/Services/AllocationService.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionMutationObserver.swift`
- Gap / Note: Goal, asset, transaction, allocation, and import/backfill mutations are normalized. Participant and owner-metadata changes remain a separate trigger-gap problem under REQ-007.

### REQ-003 Canonical freshness primitives are extracted into reusable domain code
- Proposal Source: Section `5.3.1 Materiality Policy`, Section `6.6 Projection Metadata and Canonical Freshness Model`, Section `7.0.3 Pure Domain Calculator Extraction` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:222-241`, `:503-567`, `:807-844`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/GoalProgressCalculator.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareMaterialityPolicy.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r6 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareContentHasherTests -only-testing:CryptoSavingsTrackerTests/FamilyShareDirtyStateStoreTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeOrderingTests -only-testing:CryptoSavingsTrackerTests/FamilyShareMaterialityPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareProjectionAutoRepublishCoordinatorTests -only-testing:CryptoSavingsTrackerTests/GoalProgressCalculatorTests` → passed on 2026-03-22 (`67` tests, `0` failures)
- Gap / Note: The core calculator/materiality/freshness primitives remain solid and are supported by a passing targeted test slice.

### REQ-004 Live freshness schema and payload preservation are in place
- Proposal Source: Section `6.8.2 Version and Ordering Contract`, Section `7.0.4 Projection Cache Schema Migration` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:664-709`, `:846-859`)
- Status: `Partially Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:464-500`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:565-588`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:546-654`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift`
- Gap / Note: Additive fields (`rateSnapshotTimestamp`, `projectionServerTimestamp`, `contentHash`) round-trip through payload/cache/CloudKit, and the targeted test slice now includes legacy-cache and future-schema cases. The migration itself is still shallow: `ensureCompatible()` only rewrites `schemaVersion` (`ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:637-644`) and does not materialize the proposal's conservative defaults for pre-freshness cached payloads.

### REQ-005 Canonical projection rebuild uses current owner truth rather than cached placeholders
- Proposal Source: Section `5.3 Exchange Rate Drift as Republish Trigger`, Section `6.1 Owner-Side Automatic Projection Republish`, Section `7.3 Canonical Projection Rebuild` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:204-220`, `:292-322`, `:1001-1021`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:948-952`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1000-1014`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1837-1924`
- Gap / Note: The rebuild computes real rate snapshots and hashes real invitee-visible metadata, but it still is not authoritative owner truth. `fetchActiveGoals()` still returns cached `lastSharedGoals` only (`ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1007-1008`), and repository search during this audit found no production call sites for `updateSharedGoalsCache(` beyond its definition.

### REQ-006 Owner-side freshness orchestration primitives exist and are bootstrapped in production
- Proposal Source: Section `5.4 Owner Foreground Rate Refresh Pipeline`, Section `5.5 Foreground Rate-Refresh Driver and Periodic Guard`, Section `6.5 Rate-Aware Republish Pipeline`, Section `6.9 Offline Mutation Queue and Durable Dirty-State Persistence` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:243-265`, `:475-500`, `:712-749`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:943-997`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1195-1208`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareRateDriftEvaluator.swift:40-64`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift:189-212`
- Gap / Note: This area improved versus `R5`: the rate-drift evaluator is no longer permanently empty and now receives real goal inputs plus last-published amounts during `shareAllGoals()`. The pipeline is still incomplete. Those tracked inputs are not refreshed on later owner mutations, and the reconciliation barrier still always runs as `checkBarrier(lastKnownRemoteChangeDate: nil)`, so the publish fence still has no real remote-change signal.

### REQ-007 All publish triggers route through a per-namespace auto-republish coordinator with no trigger gaps
- Proposal Source: Section `6.1.1 Per-Namespace Executor Composition`, Section `7.2.1 Complete Trigger Inventory`, Section `7.2.2 Deprecated Direct Callers`, Section `7.2.3 New Dirty Reason: .participantChange` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:304-322`, `:957-999`)
- Status: `Missing`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:973-978`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1210-1211`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1254-1282`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionMutationObserver.swift`
  - Repository search during this audit found no production call sites for `markDirty(reason: .participantChange)`
- Gap / Note: The earlier direct initial-share bypass remains fixed, but the trigger-inventory contract is still not satisfied. `manageParticipants()` still only prepares the CloudKit share sheet (`ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1254-1282`), and there is still no live ingress for participant add/remove or owner display-name changes to emit `.participantChange`.

### REQ-008 Invitee three-phase ordering and semantic dedup logic are implemented
- Proposal Source: Section `6.8.2 Version and Ordering Contract` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:664-709`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1490-1513`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeOrderingTests.swift`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r6 test -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeOrderingTests` → passed on 2026-03-22
- Gap / Note: The live refresh path and dedicated tests now cover version-floor rejection, content-hash dedup, and pre-migration timestamp fallback.

### REQ-009 Invitee refresh scheduler owns foreground, visibility, and manual refresh behavior
- Proposal Source: Section `6.3 Invitee Refresh Contract`, Section `6.4.3 Stale-Cause and Recovery Substates`, Section `7.4 Invitee Refresh Scheduler` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:361-377`, `:447-474`, `:1022-1033`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1021-1023`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1297-1303`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareInviteeRefreshScheduler.swift:45-72`
  - Repository search during this audit found no production call sites for `onFirstVisibility(`, `onManualRefresh(`, or `reportRefreshResult(`
- Gap / Note: The scheduler owns foreground-entry state changes, but manual refresh and result reporting still bypass it. `handlePrimaryAction(for:)` still calls `refreshNamespace()` directly instead of routing through scheduler-owned trigger/result handling.

### REQ-010 Invitee freshness UI exists and receives projection-level metadata on the live mapping path
- Proposal Source: Section `6.6 Projection Metadata and Canonical Freshness Model`, Section `8.2 Invitee UX` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:503-567`, `:1051-1183`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:734-777`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:87-97`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift:104-116`
- Gap / Note: The live invitee mapping carries `publishedAt`, `rateSnapshotTimestamp`, and `projectionServerTimestamp` into both list and detail freshness UI paths.

### REQ-011 Canonical server-time freshness source is propagated back and used by visible freshness semantics
- Proposal Source: Section `6.6.1 Canonical Clock Source and Skew Handling`, Section `6.8.2 Version and Ordering Contract` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:510-536`, `:664-709`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:190-199`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:464-500`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:565-588`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:953-968`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:395-399`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:742-777`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:87-97`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift:104-116`
- Gap / Note: Compared with `R5`, the detail path now matches the list path: both surfaces prefer server-assigned `projectionServerTimestamp`, and the payload/cache/CloudKit plumbing persists that field end to end.

### REQ-012 Proposal-required verification coverage exists and is runnable
- Proposal Source: Section `13) Test Plan` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1522-1719`)
- Status: `Partially Implemented`
- Evidence Type: `tests-run, tests-found`
- Evidence:
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r6 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareContentHasherTests -only-testing:CryptoSavingsTrackerTests/FamilyShareDirtyStateStoreTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeOrderingTests -only-testing:CryptoSavingsTrackerTests/FamilyShareMaterialityPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareProjectionAutoRepublishCoordinatorTests -only-testing:CryptoSavingsTrackerTests/GoalProgressCalculatorTests` → passed (`67` tests, `0` failures) on 2026-03-22
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareContentHasherTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareDirtyStateStoreTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessLabelTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessPolicyTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeOrderingTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareMaterialityPolicyTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareProjectionAutoRepublishCoordinatorTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/GoalProgressCalculatorTests.swift`
- Gap / Note: Coverage is stronger than `R5`, including current migration acceptance cases and the R7 non-USD materiality contract. It is still incomplete against the proposal. Repository search during this audit found no dedicated tests for `FamilyShareRateDriftEvaluator`, `FamilyShareInviteeRefreshScheduler`, `FamilyShareReconciliationBarrier`, or the proposal's freshness UI/accessibility surfaces.

### REQ-013 Runtime evidence exists for multi-device ordering, compact layout, and accessibility behavior
- Proposal Source: Section `11) Delivery Plan`, Section `13) Test Plan` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1326-1463`, `:1522-1719`)
- Status: `Not Verifiable`
- Evidence Type: `inference`
- Evidence:
  - Targeted family-sharing test slice succeeded during this audit
- Gap / Note: This audit did not launch the app to capture live freshness renders, multi-device ordering behavior, compact layout, dark mode, or VoiceOver behavior. Those runtime claims remain unproven.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
- `git rev-parse --short HEAD`
- `git status --short | awk 'BEGIN{m=0;u=0} {if ($1=="??") u++; else m++} END{printf("dirty (%d modified, %d untracked)\n", m, u)}'`
- `date +%Y-%m-%dT%H:%M:%S%z`
- `rg -n -i "superseded|deprecated|replaced by|obsolete" docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md docs/proposals`
- `rg -n "markDirty\\(|participantChange|updateTrackedGoals\\(|onFirstVisibility\\(|onManualRefresh\\(|reportRefreshResult\\(|projectionServerTimestamp|fetchActiveGoals\\(|lastSharedGoals|checkBarrier\\(lastKnownRemoteChangeDate: nil\\)" ios/CryptoSavingsTracker`
- `rg -n "participantChange|manageParticipants\\(|ownerDisplayName|displayName" ios/CryptoSavingsTracker/Services/FamilySharing ios/CryptoSavingsTracker/ViewModels ios/CryptoSavingsTracker/Views/FamilySharing`
- `rg -n "FamilyShareRateDriftEvaluator|FamilyShareInviteeRefreshScheduler|FamilyShareReconciliationBarrier|FreshnessHeader|FreshnessCard|VoiceOver|accessibility" ios/CryptoSavingsTrackerTests ios/CryptoSavingsTrackerUITests`
- `find ios/CryptoSavingsTrackerTests/FamilySharing -maxdepth 1 -type f | sort`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 15' -derivedDataPath /tmp/proposal-audit-tests-r6 test ...` → failed locally because no `iPhone 15` simulator is installed
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r6 test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareContentHasherTests -only-testing:CryptoSavingsTrackerTests/FamilyShareDirtyStateStoreTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareInviteeOrderingTests -only-testing:CryptoSavingsTrackerTests/FamilyShareMaterialityPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareProjectionAutoRepublishCoordinatorTests -only-testing:CryptoSavingsTrackerTests/GoalProgressCalculatorTests`

## Recommended Next Actions

- Add a live `.participantChange` ingress for participant add/remove and owner display-name changes so the trigger inventory is actually complete.
- Replace `lastSharedGoals`-based rebuilds with authoritative owner datastore snapshots, and refresh tracked rate-drift inputs whenever owner-side goal data changes.
- Feed real remote-change metadata into `FamilyShareReconciliationBarrier` instead of always calling it with `lastKnownRemoteChangeDate: nil`.
- Route invitee manual refresh, first visibility, and refresh-result reporting through `FamilyShareInviteeRefreshScheduler` rather than calling `refreshNamespace()` directly.
- Add the missing proposal-mandated tests for `FamilyShareRateDriftEvaluator`, `FamilyShareInviteeRefreshScheduler`, `FamilyShareReconciliationBarrier`, and freshness UI/accessibility surfaces, then capture runtime evidence for multi-device ordering and accessibility behavior.
