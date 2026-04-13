# CloudKit-Only Signed File Bridge for Mac Snapshot Sync Implementation Audit R5

| Field | Value |
|---|---|
| Proposal | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` |
| Repository Root | `.` |
| Git SHA | `be1c961` |
| Working Tree | `dirty` |
| Audited At | `2026-03-23T08:59:45+0200` |
| Proposal State | `Active (Draft)` |
| Overall Status | `Partial` |

## Verdict

The repository still audits as **partial**, but `R5` materially improves the evidence picture over `R4`. The working tree changed again after `R4`, specifically in `LocalBridgeImportApplyService.swift`, `LocalBridgeTransportCoordinator.swift`, and `LocalBridgeSyncView.swift`. Fresh verification now proves that the authoritative apply path has recovered: the `LocalBridgeImportApplyServiceTests` suite executed 12 tests and passed, including replay idempotency, explicit delete handling, omitted-row preservation, and review gating. Phase 2B transport is also stronger than it was in `R4`: the runtime now exposes resumable outgoing nearby transfer plus operator diagnostics, and the UI surfaces both. The audit remains **partial** because operator-visible Phase 2B behavior still regresses in fresh UI proof. The blocked-review compatibility path now passes, but the pairing visibility contract still fails in both seeded pairing scenarios, and the reject action in the live review flow still does not surface the expected `Rejected` decision back to the operator-visible state.

This audit was performed against the current dirty local worktree, including uncommitted proposal, bridge, and test changes.

## Proposal Contract

### Scope

- Keep CloudKit as the only durable authority and layer the bridge around that runtime instead of introducing a second sync engine.
- Ship a dedicated `Local Bridge Sync` surface with pairing, trust management, manual sync, import review, validation status, and revocation.
- Use an isolated transient workspace and signed file artifacts as the Phase 2A baseline.
- Treat the canonical snapshot/package appendix as normative for hashing, replay, matching, dedupe, and apply semantics.
- Treat QR, camera fallback, and `MultipeerConnectivity` as Phase 2B hardening on top of the signed file bridge.

### Locked Decisions

- CloudKit remains the only durable source of truth.
- The Mac never writes directly to CloudKit.
- Every bridge session starts from a full snapshot exported from the current authoritative dataset.
- Every bridge import is validated against the current authoritative dataset before apply.
- Drift is rejected rather than merged.
- Trust is local and revocable.
- The bridge remains manual and foreground-only.

### Acceptance Criteria

- macOS exports a signed package artifact while keeping bridge edits isolated from the live store.
- iPhone verifies the signed package, opens review, and exposes concrete diffs before apply.
- Replay of an already applied package returns `acceptedAlreadyApplied` without a duplicate authoritative write.
- Schema mismatch, drift, ambiguous matches, and orphan references reject safely.
- Reject, reset-to-pending, dismiss-review, and apply failure leave the authoritative dataset unchanged.
- QR pairing works when camera permission is granted and degrades to manual entry when it is not.
- Deterministic fingerprinting and duplicate-prevention rules hold.

### Test / Evidence Requirements

- Deterministic fingerprint proof for semantically unchanged datasets.
- Runtime/operator-visible proof for pairing, review, and blocked-review states.
- Validation of replay idempotency, delete handling, duplicate prevention, and orphan rejection.
- Proof that the bridge remains foreground-only and does not create a second sync authority.

### Explicit Exclusions

- No second durable sync authority parallel to CloudKit.
- No background bridge sync or auto reconnect.
- No local-primary fallback.
- No merge queue or incremental conflict engine.
- No separate companion product.

## Requirement Summary

| Status | Count |
|---|---:|
| Implemented | 7 |
| Partially Implemented | 3 |
| Missing | 0 |
| Not Verifiable | 0 |

## Requirement Audit

### REQ-001 CloudKit remains the only durable authority and legacy local-primary fallback stays retired
- Proposal Source: `Current State` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:22-29`), `Product Requirements` (`:72-81`), `Authority Model` (`:83-99`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/PersistenceController.swift:12-19`
  - `ios/CryptoSavingsTracker/Utilities/PersistenceController.swift:497-526`
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:95-120`
- Gap / Note: The runtime still reconciles startup to `cloudKitPrimary`, removes retired local-primary store files, and exposes bridge work only as a CloudKit-adjacent manual surface.

### REQ-002 A dedicated `Local Bridge Sync` surface exists off the top-level Settings entry point
- Proposal Source: `Phase 2 Product Surface` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:135-171`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:95-117`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:98-260`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:113-170`
- Gap / Note: The dedicated destination exists and has direct UI coverage for pairing, review, and blocked-review seeded scenarios.

### REQ-003 Trust records are Keychain-backed and revocation invalidates pending packages
- Proposal Source: `Flow 3: Trust Bootstrap` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:240-245`), `Secure Storage` (`:281-295`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/BridgeTrustStore.swift:12-83`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeArtifactStore.swift:107-145`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:637-645`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:706-735`
- Gap / Note: Revocation purges pending import artifacts for the revoked peer and clears any currently loaded package that matches the revoked signing identity.

### REQ-004 Compatibility negotiation and `Update Required` blocking exist before snapshot import/apply
- Proposal Source: `Protocol Evolution Policy` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:306-323`), `Phase 2 Test Matrix and Acceptance Criteria` (`:732`, `:739`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift:112-158`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:341-371`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift:206`
  - `ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift:71`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:167-170`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r5-ui.lIa3uE -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testPairingRequiredScenarioKeepsBootstrapTokenHiddenAndShowsTransportFallbacks -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testReadyScenarioKeepsBootstrapTokenHiddenUntilExplicitReveal -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testReviewScenarioShowsDistinctOperatorActionsAndDismissPath -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testBlockedReviewScenarioShowsUpdateRequiredAndDisablesApply test`
- Gap / Note: Fresh `R5` UI execution passed `testBlockedReviewScenarioShowsUpdateRequiredAndDisablesApply`, proving the operator-visible update-required block still works after the latest controller changes.

### REQ-005 The bridge uses an isolated transient workspace and exchanges signed file artifacts
- Proposal Source: `macOS Snapshot Workspace Boundary` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:173-180`), `Phase 2A: Signed File Bridge` (`:700-713`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransientWorkspaceStore.swift:17-70`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeArtifactStore.swift:54-88`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgePackageStore.swift:17-62`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift:35-88`
- Gap / Note: The bridge persists canonical snapshot and package artifacts separately from the live store and signs packages before handoff.

### REQ-006 The canonical snapshot/package/fingerprint contract, replay idempotency, and duplicate-prevention baseline exist
- Proposal Source: `Canonical appendix` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:540-572`), `Import / Validation Flow` (`:613-617`), `Phase 2 Test Matrix and Acceptance Criteria` (`:731`, `:743-744`), `Document-level gates` (`:766-767`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeCanonicalEncoding.swift:367-398`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:955-1016`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift:35-88`
  - `ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift:181`
  - `ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift:210`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift:274`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:366`
- Gap / Note: The appendix-shape canonical encoder still drives package body generation, signing payload generation, and deterministic snapshot hashing.

### REQ-007 Import/apply semantics reject drift safely and preserve replay/delete/omission safety
- Proposal Source: `Current State` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:29-33`), `Import / Validation Flow` (`:613-617`), `Phase 2 Test Matrix and Acceptance Criteria` (`:731`, `:734-740`, `:744`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:220-239`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:259-360`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:515-646`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:673-900`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:366`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:443`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:527`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:605`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r5-unit-class.LHWbtS -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests test`
- Gap / Note: `R5` now has fresh proof instead of inference. The current apply service computes an expected authoritative post-apply envelope, preserves omitted authoritative rows unless deletion is explicit, and passed a full `LocalBridgeImportApplyServiceTests` suite with 12 tests, including replay no-op, delete-only-when-unique, omitted-row preservation, and review gating.

### REQ-008 Operator-visible import review, approve/reject/reset, and dismiss-review lifecycle is complete
- Proposal Source: `Phase 2 Product Surface` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:138-140`, `:196`, `:213`), `Phase 2 Test Matrix and Acceptance Criteria` (`:730`, `:736-740`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift:9-215`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:576-703`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:76`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:144-165`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:167-170`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r5-ui.lIa3uE -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testPairingRequiredScenarioKeepsBootstrapTokenHiddenAndShowsTransportFallbacks -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testReadyScenarioKeepsBootstrapTokenHiddenUntilExplicitReveal -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testReviewScenarioShowsDistinctOperatorActionsAndDismissPath -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testBlockedReviewScenarioShowsUpdateRequiredAndDisablesApply test`
- Gap / Note: The review surface, actions, and controller transitions exist, and the unit suite now proves the reject path returns the controller to a safe non-mutating state. The live operator contract is still incomplete because `testReviewScenarioShowsDistinctOperatorActionsAndDismissPath` still fails at `LocalBridgeSyncUITests.swift:164`: after tapping Reject, the UI does not surface `Rejected` back through `localBridge.importReview.operatorDecision`.

### REQ-009 QR pairing, camera fallback, and manual pairing-code flow are operator-complete
- Proposal Source: `Pairing Token` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:255-270`), `Camera Permission and Pairing Fallback` (`:297-304`), `Phase 2 Test Matrix and Acceptance Criteria` (`:741-742`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:228-245`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:199-210`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:98-152`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:154-223`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:665-690`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:832-860`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeQRScannerView.swift:70-88`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift:216`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift:231`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:113-129`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:131-141`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r5-ui.lIa3uE -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testPairingRequiredScenarioKeepsBootstrapTokenHiddenAndShowsTransportFallbacks -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testReadyScenarioKeepsBootstrapTokenHiddenUntilExplicitReveal -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testReviewScenarioShowsDistinctOperatorActionsAndDismissPath -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testBlockedReviewScenarioShowsUpdateRequiredAndDisablesApply test`
- Gap / Note: The codebase has short pairing codes, QR failure fallback, and manual entry UI. Fresh `R5` UI proof still fails both pairing visibility scenarios at `LocalBridgeSyncUITests.swift:119` and `:136`, where the seeded screens do not expose `localBridge.pairingCode` as required by the operator contract.

### REQ-010 Phase 2B transport hardening is complete
- Proposal Source: `Transport Layer` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:325-349`), `Phase 2B: Transport Hardening` (`:715-724`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `tests-run`, `inference`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransportCoordinator.swift:42-49`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransportCoordinator.swift:119-164`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransportCoordinator.swift:178-196`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransportCoordinator.swift:269-334`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:219-255`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:113-123`
- Gap / Note: This area moved forward in `R5`. The runtime now records resumable outgoing artifact state, exposes `Resume Nearby Transfer`, and surfaces explicit transfer diagnostics in the UI. It is still not complete against the proposal because the broader Phase 2B promise includes stronger trust-review UX and scanability improvements for the financial diff presentation, and the live Phase 2B UI proof still fails in pairing-related scenarios.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md`
- `git rev-parse --short HEAD`
- `date '+%Y-%m-%dT%H:%M:%S%z'`
- `git status --short /Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift`
- `stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S%z' /Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal_IMPLEMENTATION_AUDIT_R4.md`
- `find /Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift -type f -newer /Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal_IMPLEMENTATION_AUDIT_R4.md`
- `rg -n "superseded|deprecated|replaced by|obsolete" docs/proposals/cloudkit_qr_multipeer_sync_proposal.md docs/proposals`
- Focused proposal reads with `nl -ba docs/proposals/cloudkit_qr_multipeer_sync_proposal.md | sed -n '20,350p;700,760p'`
- Focused implementation reads across `LocalBridgeImportApplyService`, `LocalBridgeSyncView`, `LocalBridgeTransportCoordinator`, `LocalBridgeSyncController`, `BridgeImportReviewView`, and related tests
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r5-unit.QKihvm -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests/controllerLoadsPackageAndApprovesReview -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests/deletedGoalSnapshotRemovesOnlyMatchedGoal -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests/omittedGoalSnapshotDoesNotDeleteAuthoritativeGoal test`  
  Result: command succeeded but the XCTest summary executed `0 tests`; not used as functional proof.
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r5-unit-class.LHWbtS -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests test`  
  Result: Swift Testing executed `12` tests in `LocalBridgeImportApplyServiceTests`; suite passed.
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r5-ui.lIa3uE -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testPairingRequiredScenarioKeepsBootstrapTokenHiddenAndShowsTransportFallbacks -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testReadyScenarioKeepsBootstrapTokenHiddenUntilExplicitReveal -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testReviewScenarioShowsDistinctOperatorActionsAndDismissPath -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testBlockedReviewScenarioShowsUpdateRequiredAndDisablesApply test`  
  Result: executed `4` tests; `1` passed and `3` failed. Passing scenario: `testBlockedReviewScenarioShowsUpdateRequiredAndDisablesApply`. Failing scenarios: `testPairingRequiredScenarioKeepsBootstrapTokenHiddenAndShowsTransportFallbacks`, `testReadyScenarioKeepsBootstrapTokenHiddenUntilExplicitReveal`, `testReviewScenarioShowsDistinctOperatorActionsAndDismissPath`.

## Recommended Next Actions

- Fix the two pairing visibility regressions first: `localBridge.pairingCode` still is not discoverable in the seeded `pairing_required` and `ready` scenarios.
- Fix the reject-state UI feedback path so that the operator-visible review surface reflects `Rejected` after tapping Reject.
- After those UI fixes, rerun the same targeted `LocalBridgeSyncUITests` command from this report. The apply path now has fresh passing proof and no longer blocks an `Implemented` verdict there.
