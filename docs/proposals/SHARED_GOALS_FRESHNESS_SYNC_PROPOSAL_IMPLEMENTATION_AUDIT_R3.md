# SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL Implementation Audit R3

| Field | Value |
|---|---|
| Proposal | `docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md` |
| Repository Root | `.` |
| Git SHA | `644ba70` |
| Working Tree | `dirty (22 modified, 54 untracked)` |
| Audited At | `2026-03-22T11:52:22+0200` |
| Proposal State | `Active` |
| Overall Status | `Not Implemented` |

## Verdict

The implementation has advanced again since `R2`, but it still does not satisfy the proposal end to end. The main improvements are real: the app now starts the reconciliation-barrier import observer on launch, the CloudKit store captures `CKRecord.modificationDate` after publish, the publication result now carries `projectionServerTimestamp`, payload rewrite helpers preserve the new freshness fields, and the detail view removed the legacy `Updated` pill while beginning to pass `rateSnapshotTimestamp` into the Freshness card. The remaining blockers are still structural: the per-namespace auto-republish coordinator is not wired into the production publish path, direct publish bypasses remain, the invitee three-phase ordering logic still is not implemented, freshness metadata still is not propagated through the canonical invitee projection mapping, and the test target currently fails to build because several mocks no longer conform to the expanded `ExchangeRateServiceProtocol`.

## Proposal Contract

### Scope

- owner-side freshness maintenance through foreground rate refresh, drift evaluation, dirty tracking, and automatic republish
- canonical projection rebuild from current owner truth using `GoalProgressCalculator`
- additive freshness metadata in payload/cache/CloudKit plus the documented three-phase invitee ordering contract
- invitee refresh scheduling and per-namespace freshness UI in list and detail surfaces
- rollout, telemetry, migration safety, and explicit verification coverage

### Locked Decisions

- `projectionVersion` remains the atomic publish token; semantic freshness ordering is driven by `contentHash`, with `projectionServerTimestamp` only as pre-migration fallback
- `currentAmount` must come from `GoalProgressCalculator`, not `goal.manualTotal`
- all publish-triggering actions route through a per-namespace auto-republish coordinator
- list and detail surfaces share a single canonical freshness model, `FamilyShareFreshnessLabel`
- detail provenance uses projection-level publish and rate timestamps, not goal-local edit timestamps

### Acceptance Criteria

- owner edits and rate drift republish shared projections without manual share UI workarounds
- freshness is composite (`max(publishAge, rateAge)`) and rendered per namespace
- no direct publish bypass survives outside the coordinator / namespace actor boundary
- schema migration is additive and rollback-safe
- invitee ordering follows the proposal's atomic-version + contentHash + server-timestamp fallback rules

### Test / Evidence Requirements

- targeted unit coverage for calculator, materiality, scheduler, barrier, debounce/coalescing, and ordering
- integration coverage for publish/fetch loop, rate-drift pipeline, and offline recovery
- UI/accessibility coverage for freshness list/detail surfaces
- runnable build/test evidence, not code inspection alone

### Explicit Exclusions

- this audit does not modify code or proposal text
- runtime CloudKit correctness is not claimed without direct evidence
- inference alone is not enough to mark a requirement `Implemented`

## Requirement Summary

| Status | Count |
|---|---:|
| Implemented | 3 |
| Partially Implemented | 6 |
| Missing | 3 |
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
- Gap / Note: The service-level API and notification surface are present. Production ownership of those events is evaluated under REQ-006 and REQ-009.

### REQ-002 Shared-goal mutation notifications are normalized at the service layer
- Proposal Source: Section `7.0.2 PersistenceMutationServices Notification Normalization`, Section `7.2.1 Complete Publish Trigger Inventory`, Acceptance Criteria item `17` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:794-805`, `:961-968`, `:1484`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/NotificationNames.swift:23`
  - `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:68`, `:200`, `:213`, `:298`, `:317`
  - `ios/CryptoSavingsTracker/Services/AllocationService.swift:114`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionMutationObserver.swift:26`
- Gap / Note: Notification normalization is present. Full coordinator ownership of those dirty events remains incomplete under REQ-007.

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
- Gap / Note: These primitives exist and have dedicated test files. Production orchestration around them is still incomplete.

### REQ-004 Live freshness schema and payload preservation are in place
- Proposal Source: Section `6.8.2 Version and Ordering Contract`, Section `7.0.4 Projection Cache Schema Migration`, Acceptance Criteria items `36` and `47` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:676-701`, `:846-859`, `:1503`, `:1514`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift:317-326`, `:423-430`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:499`, `:587`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1403-1405`, `:1484-1486`, `:1995-1997`, `:2022-2024`
- Gap / Note: This is improved from `R2`: payload rewrite helpers now preserve `rateSnapshotTimestamp`, `projectionServerTimestamp`, and `contentHash`. The remaining gap is that cache migration still only bumps `schemaVersion` and does not materialize the proposal's conservative freshness defaults or explicitly migrate canonical invitee projections to carry the new metadata through the UI mapping path.

### REQ-005 Canonical projection rebuild uses proposal semantics rather than fallback placeholders
- Proposal Source: Section `5.3 Exchange Rate Drift as Republish Trigger`, Section `6.1 Owner-Side Automatic Projection Republish`, Section `7.3 Canonical Projection Rebuild`, Acceptance Criteria items `4`, `36`, and `38` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:204-220`, `:292-322`, `:1001-1012`, `:1471`, `:1503`, `:1505`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1677-1783`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareContentHasher.swift`
- Gap / Note: `makeProjectionPayload()` still stamps `publishedAt = Date()`, uses an empty `RateSnapshot(rates: [:])`, and still falls back to `goal.manualTotal` when calculator output is absent. `contentHash` is computed, but participant IDs remain empty and `projectionServerTimestamp` stays `nil` until some later publish-layer handling. This is closer than `R2`, but still not the proposal's canonical rebuild.

### REQ-006 Owner-side freshness orchestration primitives exist and barrier observation is bootstrapped
- Proposal Source: Section `5.4 Owner Foreground Rate Refresh Pipeline`, Section `5.5 Foreground Rate-Refresh Driver and Periodic Guard`, Section `6.5 Rate-Aware Republish Pipeline`, Section `6.9 Offline Mutation Queue and Durable Dirty-State Persistence`, Acceptance Criteria items `41`, `49`, and `50` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:243-265`, `:475-500`, `:598-662`, `:712-749`, `:1508`, `:1516-1517`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:41-42`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareForegroundRateRefreshDriver.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareRateDriftEvaluator.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareReconciliationBarrier.swift:45-105`
- Gap / Note: The app now starts `FamilyShareReconciliationBarrier.startObservingImports()` at launch, which is real progress. But repository search still finds no production instantiation of `FamilyShareForegroundRateRefreshDriver`, `FamilyShareRateDriftEvaluator`, or `FamilyShareProjectionAutoRepublishCoordinator`, and the coordinator's `publishAction` still is not wired anywhere outside its own file.

### REQ-007 All publish triggers route through a per-namespace auto-republish coordinator with no direct bypasses
- Proposal Source: Section `6.1.1 Per-Namespace Executor Composition`, Section `7.2.1 Complete Publish Trigger Inventory`, Section `7.2.2 Deprecated Direct Callers`, Acceptance Criteria items `34`, `35`, and `46` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:304-322`, `:961-987`, `:1501-1502`, `:1513`)
- Status: `Missing`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1081-1082`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift:180-209`
  - Repository search during this audit found no production call site for `setPublishAction(` and no live instantiation of `FamilyShareProjectionAutoRepublishCoordinator(`
- Gap / Note: The owner flow still does `_ = try await publishCoordinator.publish(payload)` directly from `shareAllGoals()`. That remains a proposal-level contract break because the coordinator/namespace-actor boundary still does not own all publish ingress.

### REQ-008 Invitee three-phase ordering and semantic dedup logic are implemented
- Proposal Source: Section `6.8.2 Version and Ordering Contract`, Acceptance Criteria items `20`, `36`, and `37` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:683-709`, `:1487`, `:1503-1504`)
- Status: `Missing`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift:214-216`
  - Repository search during this audit found no live code comparing cached vs incoming `contentHash`, no active `activeProjectionVersion` gate against cached projections, and no `projectionServerTimestamp` fallback ordering implementation.
- Gap / Note: The data fields now exist and `projectionServerTimestamp` is beginning to propagate, but the actual invitee accept/reject logic described in the proposal still is not present in the production code path.

### REQ-009 Invitee refresh scheduler owns foreground, visibility, and manual refresh behavior
- Proposal Source: Section `6.3 Invitee Refresh Contract`, Section `6.4.3 Stale-Cause and Recovery Substates`, Section `7.4 Invitee Refresh Scheduler`, Acceptance Criteria items `28` and `52` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:361-377`, `:447-474`, `:1022-1033`, `:1495`, `:1519`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareInviteeRefreshScheduler.swift`
  - Repository search during this audit found no production call sites for `onForegroundEntry`, `onFirstVisibility`, `onManualRefresh`, or `reportRefreshResult`
- Gap / Note: The scheduler still exists mostly as a state machine with no live ownership of refresh execution in the app.

### REQ-010 Invitee freshness UI exists and receives the right metadata on the live mapping path
- Proposal Source: Section `6.6 Projection Metadata and Canonical Freshness Model`, Section `8.2 Invitee UX`, Acceptance Criteria items `24`, `29`, `31`, `48`, `52`, and `53` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:503-567`, `:1055-1165`, `:1491`, `:1496-1499`, `:1515`, `:1519-1520`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:36-45`, `:87-93`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift:96-115`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:736-766`
- Gap / Note: This improved since `R2`: the detail screen removed the legacy `Updated` pill and now passes `goal.rateSnapshotTimestamp` into the Freshness card. But the canonical invitee projection mapping still does not populate `publishedAt` or `rateSnapshotTimestamp` on `FamilyShareInviteeSectionProjection`, and it still builds `FamilyShareInviteeGoalProjection` with `lastUpdatedAt: goal.lastUpdatedAt` rather than projection-level freshness timestamps. That means the UI scaffolding exists, but the live mapping path still does not deliver the full proposal contract.

### REQ-011 Canonical server-time freshness source is propagated back into published state
- Proposal Source: Section `6.6.1 Canonical Clock Source and Skew Handling`, Section `6.8.2 Version and Ordering Contract`, Acceptance Criteria item `38` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:510-536`, `:676-681`, `:1505`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:188-199`, `:621-635`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:417-427`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1767-1783`
- Gap / Note: This is a real improvement from `R2`. The CloudKit store now captures the root record's `modificationDate`, and `FamilySharePublicationResult` now carries `projectionServerTimestamp`. But the live payload still originates with local `publishedAt: Date()`, and the code shown in this audit does not update the stored `FamilyShareProjectionPayload` with the captured server timestamp after publish. So the server-backed freshness source is only partially wired through.

### REQ-012 Proposal-required verification coverage exists and is runnable
- Proposal Source: Section `13) Test Plan` (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1526-1696`)
- Status: `Missing`
- Evidence Type: `tests-found, tests-run`
- Evidence:
  - Found targeted unit-test files for freshness primitives in `ios/CryptoSavingsTrackerTests/FamilySharing/`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath "$DERIVED_DATA" test -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests -only-testing:CryptoSavingsTrackerTests/GoalProgressCalculatorTests -only-testing:CryptoSavingsTrackerTests/FamilyShareMaterialityPolicyTests -only-testing:CryptoSavingsTrackerTests/FamilyShareContentHasherTests -only-testing:CryptoSavingsTrackerTests/FamilyShareDirtyStateStoreTests` was executed during this audit
- Gap / Note: The separate test scheme is runnable, which is better than `R2`, but the test target currently fails to build because several unrelated mocks still do not conform to the expanded `ExchangeRateServiceProtocol` after `refreshRatesIfStale()` was added: `ExecutionContributionCalculatorTests.MockRates`, `ExecutionProgressCalculatorTests.MockExchangeRateService`, and `TestHelpers.MockExchangeRateService`. The audit also still found no UI/integration tests covering freshness header/card rendering, invitee ordering, scheduler behavior, or auto-republish coordination.

### REQ-013 Runtime evidence exists for multi-device ordering, compact layout, and accessibility behavior
- Proposal Source: Section `11) Rollout Plan and Validation`, Section `13) Test Plan` items covering accessibility, compact layout, barrier, and detail provenance (`docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1396-1411`, `:1592-1696`)
- Status: `Not Verifiable`
- Evidence Type: `inference`
- Evidence:
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination 'id=B344C46C-FC72-47F0-B150-A7F3478F09B2' -derivedDataPath "$DERIVED_DATA" build` passed during this audit
- Gap / Note: This audit did not run the app in the simulator or produce new runtime captures, so multi-device ordering, accessibility behavior, compact layout, and live refresh transitions remain unproven.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
- `git rev-parse --short HEAD`
- `git status --short | awk 'BEGIN{m=0;u=0} {if ($1=="??") u++; else m++} END{printf("dirty (%d modified, %d untracked)\n", m, u)}'`
- `rg -n -i "superseded|deprecated|replaced by|obsolete" docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md docs/proposals`
- `rg -n "FamilyShareProjectionAutoRepublishCoordinator\\(|setPublishAction\\(|FamilyShareForegroundRateRefreshDriver\\(|FamilyShareInviteeRefreshScheduler\\(|FamilyShareRateDriftEvaluator\\(|startObservingImports\\(" ios/CryptoSavingsTracker`
- `rg -n "contentHash.*compare|contentHash.*cached|activeProjectionVersion.*cached|projectionServerTimestamp.*cached" ios/CryptoSavingsTracker/Services/FamilySharing ios/CryptoSavingsTracker/Views/FamilySharing`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -list`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination 'id=B344C46C-FC72-47F0-B150-A7F3478F09B2' -derivedDataPath "$DERIVED_DATA" build` → passed
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination 'id=B344C46C-FC72-47F0-B150-A7F3478F09B2' -derivedDataPath "$DERIVED_DATA" test ...` → failed: main app scheme still has no `test` action
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' -derivedDataPath "$DERIVED_DATA" test -only-testing:CryptoSavingsTrackerTests/...` → test target build failed because several mocks no longer conform to `ExchangeRateServiceProtocol`

## Recommended Next Actions

- Wire the per-namespace auto-republish coordinator into the production family-sharing path and remove direct `publishCoordinator.publish(...)` bypasses.
- Implement the invitee three-phase ordering path using cached/incoming `activeProjectionVersion`, `contentHash`, and `projectionServerTimestamp`.
- Propagate projection-level freshness metadata into `canonicalInviteeProjection` so list headers and detail cards receive real `publishedAt` / `rateSnapshotTimestamp` values.
- Replace the remaining local-time freshness source in the published payload/state with the captured CloudKit server timestamp flow.
- Fix test mocks to conform to `ExchangeRateServiceProtocol` and add the missing orchestration/UI coverage required by the proposal.
