# SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL Implementation Audit R4

| Field | Value |
|---|---|
| Proposal | `docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md` |
| Repository Root | `.` |
| Git SHA | `644ba70` |
| Working Tree | `dirty (25 modified, 55 untracked)` |
| Audited At | `2026-03-22T12:26:56+0200` |
| Proposal State | `Active` |
| Overall Status | `Not Implemented` |

## Verdict

The implementation moved materially since `R3`: the app now instantiates and starts the freshness pipeline in production, invitee refresh now contains the proposal's three-phase ordering gate, the invitee projection mapping carries `publishedAt` and `rateSnapshotTimestamp`, and the targeted family-sharing test slice now builds and passes. It still does not satisfy the proposal end to end. The remaining blockers are structural: the auto-republish publish action still rebuilds from placeholder owner data (`fetchActiveGoals()` returns `[]`), the initial share flow still bypasses the auto-republish coordinator, rate-drift evaluation and invitee refresh scheduling are still not wired to real production triggers, and freshness rendering still depends on device-authored `publishedAt` rather than the server-backed publish timestamp required by the proposal.

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
| Partially Implemented | 4 |
| Missing | 3 |
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
- Gap / Note: The service-level API and notification surface are present. Live orchestration of those events is evaluated separately in REQ-006.

### REQ-002 Shared-goal mutation notifications are normalized at the service layer
- Proposal Source: Section `7.0.2 PersistenceMutationServices Notification Normalization`, Section `7.2.1 Complete Trigger Inventory` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:794-805`, `:957-977`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/NotificationNames.swift:23`
  - `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:68`, `:200`, `:213`, `:298`, `:317`
  - `ios/CryptoSavingsTracker/Services/AllocationService.swift:114`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionMutationObserver.swift:21-31`
- Gap / Note: Normalized notifications exist. The observer's incomplete reason mapping is a separate trigger-routing gap under REQ-007.

### REQ-003 Canonical freshness primitives are extracted into reusable domain code
- Proposal Source: Section `5.3.1 Materiality Policy`, Section `6.6 Projection Metadata and Canonical Freshness Model`, Section `7.0.3 Pure Domain Calculator Extraction` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:222-241`, `:503-567`, `:807-844`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/GoalProgressCalculator.swift:11`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareMaterialityPolicy.swift:9`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift:10`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r4b test -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/GoalProgressCalculatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareMaterialityPolicyTests` → passed on 2026-03-22
- Gap / Note: These domain primitives are now backed by passing targeted tests. Remaining gaps are in orchestration and data sourcing, not in the pure calculations themselves.

### REQ-004 Live freshness schema and payload preservation are in place
- Proposal Source: Section `6.8.2 Version and Ordering Contract`, Section `7.0.4 Projection Cache Schema Migration` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:664-709`, `:846-859`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift:317-326`, `:423-430`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:464-500`, `:571-588`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1509-1531`, `:1590-1612`, `:2100-2150`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:637-644`
- Gap / Note: Additive fields now round-trip through payload/cache/CloudKit and are preserved across state rewrites. Migration is still shallow: `ensureCompatible()` only bumps `schemaVersion` and does not materialize the proposal's conservative freshness defaults for older cached payloads.

### REQ-005 Canonical projection rebuild uses current owner truth rather than placeholder inputs
- Proposal Source: Section `5.3 Exchange Rate Drift as Republish Trigger`, Section `6.1 Owner-Side Automatic Projection Republish`, Section `7.3 Canonical Projection Rebuild` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:204-220`, `:292-322`, `:1001-1012`)
- Status: `Missing`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:946-950`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:987-990`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1791-1910`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareContentHasher.swift:26-63`
- Gap / Note: The live auto-republish publish action still rebuilds from `fetchActiveGoals()`, and that method currently returns `[]`. The payload builder also still uses an empty `RateSnapshot(rates: [:])`, stamps `publishedAt = Date()`, and computes `contentHash` with `participantIDs: []`, so participant-list changes still do not alter the hash as the proposal requires.

### REQ-006 Owner-side freshness orchestration primitives exist and are bootstrapped in production
- Proposal Source: Section `5.4 Owner Foreground Rate Refresh Pipeline`, Section `5.5 Foreground Rate-Refresh Driver and Periodic Guard`, Section `6.5 Rate-Aware Republish Pipeline`, Section `6.9 Offline Mutation Queue and Durable Dirty-State Persistence` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:243-265`, `:475-500`, `:712-749`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:913-983`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:42`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareForegroundRateRefreshDriver.swift:29-87`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift:65-176`
- Gap / Note: This is a real upgrade from `R3`: coordinator, mutation observer, invitee scheduler, and rate refresh driver are now instantiated, `setPublishAction()` is called, dirty-state rehydration runs, and the rate driver starts. The pipeline is still incomplete because there is no production instantiation of `FamilyShareRateDriftEvaluator`, and the reconciliation barrier is always invoked with `lastKnownRemoteChangeDate: nil`, which trivially satisfies the publish fence.

### REQ-007 All publish triggers route through a per-namespace auto-republish coordinator with no direct bypasses
- Proposal Source: Section `6.1.1 Per-Namespace Executor Composition`, Section `7.2.1 Complete Trigger Inventory`, Section `7.2.2 Deprecated Direct Callers` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:304-322`, `:957-987`)
- Status: `Missing`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1163-1179`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionMutationObserver.swift:45-57`
  - Repository search during this audit found no production instantiation of `FamilyShareRateDriftEvaluator(`
- Gap / Note: `shareAllGoals()` still calls `publishCoordinator.publish(payload)` directly before notifying the coordinator, so the initial share path still bypasses the proposal's sole-ingress contract. Trigger coverage is also incomplete: the mutation observer currently emits only `.goalMutation`, and there is still no live `.rateDrift` or `.participantChange` trigger path into the coordinator.

### REQ-008 Invitee three-phase ordering and semantic dedup logic are implemented
- Proposal Source: Section `6.8.2 Version and Ordering Contract` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:664-709`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1456-1481`
- Gap / Note: The live invitee refresh path now enforces the proposal's three-phase ordering: atomic version floor, `contentHash` no-op dedup, and `projectionServerTimestamp` fallback only for pre-migration payloads with missing hashes. Dedicated ordering tests are still absent and are called out under REQ-012.

### REQ-009 Invitee refresh scheduler owns foreground, visibility, and manual refresh behavior
- Proposal Source: Section `6.3 Invitee Refresh Contract`, Section `6.4.3 Stale-Cause and Recovery Substates`, Section `7.4 Invitee Refresh Scheduler` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:361-377`, `:447-474`, `:1022-1033`)
- Status: `Missing`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareInviteeRefreshScheduler.swift:45-140`
  - Repository search during this audit found no production call sites for `onForegroundEntry`, `onFirstVisibility`, `onManualRefresh`, or `reportRefreshResult`
- Gap / Note: The scheduler object exists, but it still owns only an internal state machine. The proposal-required trigger wiring from app lifecycle, visibility, manual refresh UI, and fetch result reporting is still not connected.

### REQ-010 Invitee freshness UI exists and receives projection-level metadata on the live mapping path
- Proposal Source: Section `6.6 Projection Metadata and Canonical Freshness Model`, Section `8.2 Invitee UX` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:503-567`, `:1051-1183`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:736-770`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:89-92`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift:105-112`
- Gap / Note: This is materially better than `R3`. The live projection mapping now passes projection-level `publishedAt` and `rateSnapshotTimestamp` into section and detail freshness surfaces. Server-time correctness is still a separate gap under REQ-011.

### REQ-011 Canonical server-time freshness source is propagated back and actually supports freshness semantics
- Proposal Source: Section `6.6.1 Canonical Clock Source and Skew Handling`, Section `6.8.2 Version and Ordering Contract` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:510-536`, `:664-709`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:190-198`, `:469-500`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:950-966`, `:1168-1171`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:746-769`
- Gap / Note: The CloudKit store now captures `CKRecord.modificationDate`, and both share paths write the returned `projectionServerTimestamp` back into cached payload state. The freshness surfaces still render `publishedAt`, which is built locally in `makeProjectionPayload()`, so the proposal's canonical server-backed publish clock still is not the timestamp driving visible freshness.

### REQ-012 Proposal-required verification coverage exists and is runnable
- Proposal Source: Section `13) Test Plan` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1522-1719`)
- Status: `Partially Implemented`
- Evidence Type: `tests-run, tests-found`
- Evidence:
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-build-r4b build` → passed on 2026-03-22
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r4b test -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/GoalProgressCalculatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareMaterialityPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareContentHasherTests -only-testing:CryptoSavingsTrackerTests/FamilyShareDirtyStateStoreTests -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests` → passed (`58` tests, `0` failures) on 2026-03-22
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift`
- Gap / Note: Runnable verification is substantially better than `R3`, but proposal-specific coverage is still missing for the new coordinator, rate-drift evaluator, invitee refresh scheduler, reconciliation barrier, three-phase ordering, and UI/accessibility surfaces.

### REQ-013 Runtime evidence exists for multi-device ordering, compact layout, and accessibility behavior
- Proposal Source: Section `11) Delivery Plan`, Section `13) Test Plan` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1326-1463`, `:1522-1719`)
- Status: `Not Verifiable`
- Evidence Type: `inference`
- Evidence:
  - `xcodebuild` build and targeted tests succeeded during this audit
- Gap / Note: This audit did not launch the app to capture live freshness renders, multi-device ordering behavior, compact layout, dark mode, or VoiceOver behavior. Those claims remain unproven.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
- `git rev-parse HEAD`
- `git status --short | awk 'BEGIN{m=0;u=0} {if ($1=="??") u++; else m++} END{printf("dirty (%d modified, %d untracked)\n", m, u)}'`
- `date +%Y-%m-%dT%H:%M:%S%z`
- `rg -n -i "superseded|deprecated|replaced by|obsolete" docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md docs/proposals`
- `rg -n "^#|^##|^###" docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
- `rg -n "FamilyShareProjectionAutoRepublishCoordinator\\(|setPublishAction\\(|FamilyShareForegroundRateRefreshDriver\\(|FamilyShareInviteeRefreshScheduler\\(|FamilyShareRateDriftEvaluator\\(|startObservingImports\\(" ios/CryptoSavingsTracker`
- `rg -n "inviteeRefreshScheduler\\.|onForegroundEntry\\(|onFirstVisibility\\(|onManualRefresh\\(|reportRefreshResult\\(|rateRefreshDriver\\.|start\\(\\)" ios/CryptoSavingsTracker`
- `rg -n "contentHash.*cached|cached.*contentHash|activeProjectionVersion.*cached|cached.*activeProjectionVersion|projectionServerTimestamp.*cached|cached.*projectionServerTimestamp" ios/CryptoSavingsTracker/Services/FamilySharing ios/CryptoSavingsTracker/Views/FamilySharing ios/CryptoSavingsTracker/Models/FamilySharing`
- `rg --files ios/CryptoSavingsTrackerTests | rg 'FamilyShare(ForegroundRateRefreshDriver|InviteeRefreshScheduler|ProjectionAutoRepublishCoordinator|ReconciliationBarrier)Tests\\.swift$'`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -list`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-build-r4b build`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath /tmp/proposal-audit-tests-r4b test -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/GoalProgressCalculatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareMaterialityPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareContentHasherTests -only-testing:CryptoSavingsTrackerTests/FamilyShareDirtyStateStoreTests -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests`

## Recommended Next Actions

- Replace the placeholder auto-republish snapshot path: implement `fetchActiveGoals()`, build a real rate snapshot, and include real participant identifiers in `contentHash`.
- Remove the remaining initial-share direct publish bypass so all publish-triggering actions enter through the auto-republish coordinator.
- Wire `FamilyShareRateDriftEvaluator` and `FamilyShareInviteeRefreshScheduler` into production lifecycle and refresh execution paths.
- Make visible freshness use the server-backed publish timestamp semantics required by Section `6.6.1`, not the locally stamped `publishedAt`.
- Add the missing proposal-specific tests for coordinator behavior, barrier waiting, rate-drift triggers, invitee ordering, and UI/accessibility freshness surfaces.
