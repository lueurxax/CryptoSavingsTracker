# CloudKit-Only Signed File Bridge for Mac Snapshot Sync Implementation Audit R3

| Field | Value |
|---|---|
| Proposal | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` |
| Repository Root | `.` |
| Git SHA | `be1c961` |
| Working Tree | `dirty` |
| Audited At | `2026-03-23T07:54:38+0200` |
| Proposal State | `Active (Draft)` |
| Overall Status | `Partial` |

## Verdict

The repository now covers most of the Phase 2A signed bridge baseline and more of Phase 2B than it did in `R2`. The canonical package contract has been tightened to the proposal appendix shape, pairing-code/manual-entry flow now exists, `MultipeerConnectivity` can transfer real artifacts with progress reporting, and the bridge-focused test target no longer fails at compile time. The implementation is still only **partial** because fresh targeted verification now finds real regressions in both the operator-visible acceptance layer and the apply path: `LocalBridgeSyncUITests` executed 5 scenarios and failed 3, and the targeted bridge unit run executed 33 tests in 3 suites and failed 3 `LocalBridgeImportApplyServiceTests` cases. The proposal's broader Phase 2B hardening also still overreaches the proved runtime on resumability and richer diagnostics/trust-review UX.

This audit was performed against the current dirty local worktree, including uncommitted bridge, test, and proposal changes.

## Proposal Contract

### Scope

- Keep CloudKit as the only durable authority and layer the bridge around that runtime rather than around a second sync engine.
- Ship a dedicated `Local Bridge Sync` surface with pairing, trust management, manual sync, import review, validation status, and revocation.
- Use an isolated transient macOS snapshot workspace and signed file artifacts as the Phase 2A baseline.
- Treat the canonical snapshot/package appendix as normative for hashing, replay, matching, dedupe, and apply semantics.
- Treat QR, camera fallback, and `MultipeerConnectivity` as Phase 2B foreground hardening on top of the signed file bridge.

### Locked Decisions

- CloudKit remains the only durable source of truth.
- The Mac never writes directly to CloudKit.
- Every bridge session starts from a full authoritative snapshot and rejects drift rather than merging.
- The iPhone validates and reviews the package before any authoritative mutation.
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
| Implemented | 6 |
| Partially Implemented | 4 |
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
- Gap / Note: Runtime boot reconciliation still forces `cloudKitPrimary`, removes retired local-primary store files, and exposes the bridge as a CloudKit-adjacent manual workflow rather than a second authority.

### REQ-002 A dedicated `Local Bridge Sync` surface exists off the top-level Settings row
- Proposal Source: `Phase 2 Product Surface` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:135-171`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:95-117`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:90-220`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-uitests-r3.Tlee7p -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests test` executed and navigated into the dedicated bridge surface in all 5 scenarios.
- Gap / Note: The dedicated bridge destination exists and is exercised by the UI test target. Operator-surface failures are tracked separately in `REQ-008` and `REQ-009`.

### REQ-003 Trust records are Keychain-backed and revocation invalidates pending packages
- Proposal Source: `Flow 3: Trust Bootstrap` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:240-245`), `Secure Storage` (`:281-295`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/BridgeTrustStore.swift:12-83`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeArtifactStore.swift:107-145`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:706-726`
- Gap / Note: Trust is stored in Keychain, and revocation both removes trust and invalidates/import-clears pending packages from the revoked device.

### REQ-004 Compatibility negotiation and `Update Required` blocking exist before snapshot import/apply
- Proposal Source: `Protocol Evolution Policy` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:306-323`), `Phase 2 Test Matrix and Acceptance Criteria` (`:732`, `:739`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:187-207`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift:112-124`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:167-184`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-uitests-r3.Tlee7p -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests test` executed; `testBlockedReviewScenarioShowsUpdateRequiredAndDisablesApply` passed.
- Gap / Note: The current negotiation range is still narrow, but incompatible schema/canonical versions are blocked and surfaced in the UI as required.

### REQ-005 The bridge uses an isolated transient workspace and exchanges signed file artifacts
- Proposal Source: `macOS Snapshot Workspace Boundary` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:173-180`), `Phase 2A: Signed File Bridge` (`:700-713`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransientWorkspaceStore.swift:17-70`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeArtifactStore.swift:54-88`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgePackageStore.swift:17-62`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:379-466`
- Gap / Note: The workspace is file-backed and isolated under app support, and signed artifacts are persisted as explicit outbound/inbound bridge files instead of touching the live CloudKit-backed store.

### REQ-006 The mandatory canonical package and fingerprint contract matches the proposal appendix
- Proposal Source: `Canonical Encoding Rules` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:544-553`), `Canonical Ordering Rules` (`:554-566`), `Fingerprint and Replay Rules` (`:567-574`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeCanonicalEncoding.swift:367-398`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:955-1016`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift:43-76`
  - `ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift:180-206`
  - `ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift:209-240`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-tests-r3c.2ZxLkT -only-testing:CryptoSavingsTrackerTests/LocalBridgeFoundationTests -only-testing:CryptoSavingsTrackerTests/BridgeImportValidationServiceTests -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests test`
- Gap / Note: This closes the main `R2` appendix drift. The canonical package body/signing payload now omit `signingAlgorithm` and `signerPublicKeyRepresentation`, while still storing them as compatibility metadata on the runtime model. The fresh targeted bridge test run completed; its failures were confined to `LocalBridgeImportApplyServiceTests`, not to the canonical encoding / validation test surfaces cited here.

### REQ-007 Import validation/apply semantics enforce review-before-apply, replay no-op, and all-or-nothing safety rules
- Proposal Source: `Import Validation` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:610-635`), `Apply Rules` (`:601-608`), `Phase 2 Test Matrix and Acceptance Criteria` (`:730-740`, `:744`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:4-75`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:709-760`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:1067-1092`
  - `ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift:16-105`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:400-441`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:443-520`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-tests-r3c.2ZxLkT -only-testing:CryptoSavingsTrackerTests/LocalBridgeFoundationTests -only-testing:CryptoSavingsTrackerTests/BridgeImportValidationServiceTests -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests test`
- Gap / Note: The apply path clearly implements receipts, replay handling, delete resolution, and orphan/ambiguity checks, but fresh targeted tests now show three unresolved regressions in that contract. The run failed in `LocalBridgeImportApplyServiceTests.controllerLoadsPackageAndApprovesReview()` (`:72`, approval message expectation), `deletedGoalSnapshotRemovesOnlyMatchedGoal()` (`:513`, package becomes malformed because dependent records keep referencing the deleted goal), and `omittedGoalSnapshotDoesNotDeleteAuthoritativeGoal()` (`:593`, final authoritative fingerprint mismatches the expected edited fingerprint).

### REQ-008 Operator-visible import review acceptance behavior is fully proven in simulator runtime
- Proposal Source: `iPhone Import Review Boundary` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:182-206`), `Phase 2 Test Matrix and Acceptance Criteria` (`:730`, `:736-740`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift:10-165`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:689-703`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:144-184`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-uitests-r3.Tlee7p -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests test`
- Gap / Note: The review destination, concrete diffs, approve/reject/reset actions, and dismiss-review parent action exist. The acceptance proof is still incomplete because the targeted UI run executed 5 tests and failed 3: `testPairingRequiredScenarioKeepsBootstrapTokenHiddenAndShowsTransportFallbacks` (`LocalBridgeSyncUITests.swift:119`), `testReadyScenarioKeepsBootstrapTokenHiddenUntilExplicitReveal` (`:136`), and `testReviewScenarioShowsDistinctOperatorActionsAndDismissPath` (`:164`, operator decision remained `nil` instead of `Rejected` after tapping reject).

### REQ-009 QR pairing, camera fallback, and manual pairing-code flow are operator-complete
- Proposal Source: `Pairing Token` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:255-270`), `Camera Permission and Pairing Fallback` (`:297-304`), `Phase 2 Test Matrix and Acceptance Criteria` (`:741-742`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `tests-found`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:228-245`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:199-210`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:98-152`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:651-680`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:818-840`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeQRScannerView.swift:70-88`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift:231-240`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:113-142`
- Gap / Note: The codebase now supports a real short pairing-code format, distinct `Enter Pairing Code` copy, full-token paste, and QR camera failure messages that preserve manual pairing. The operator-visible contract is still not fully met because both pairing-related UI acceptance cases failed to discover `localBridge.pairingCode` in live seeded scenarios (`LocalBridgeSyncUITests.swift:119` and `:136`).

### REQ-010 Phase 2B transport hardening is complete
- Proposal Source: `Transport Layer` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:325-345`), `Phase 2B: Transport Hardening` (`:715-724`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `inference`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransportCoordinator.swift:8-168`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransportCoordinator.swift:269-298`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:154-220`
  - `rg -n "resum|resume|diagnostic|trust review|scanability|grouping" ios/CryptoSavingsTracker/Utilities/Bridge ios/CryptoSavingsTracker/Views/Settings ios/CryptoSavingsTrackerTests ios/CryptoSavingsTrackerUITests -g'*.swift'`
- Gap / Note: This is materially ahead of `R2`: foreground advertiser/browser/session runtime exists, real artifact transfer uses `sendResource`, and incoming/outgoing progress is surfaced. The proposal still overstates the shipped hardening level. I did not find explicit resumable transfer or retry state, nor bridge-specific implementations for the richer diagnostics / trust-review UX / scanability hardening called out in Phase 2B. The current UI-test regressions around pairing and review also argue against calling the whole hardening phase complete.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md`
- `git rev-parse --show-toplevel`
- `git rev-parse --short HEAD`
- `git status --short`
- `date '+%Y-%m-%dT%H:%M:%S%z'`
- `rg -n "superseded|deprecated|replaced by|obsolete|Implementation Audit|TRIAD_REVIEW|EVIDENCE_PACK" docs/proposals/cloudkit_qr_multipeer_sync_proposal.md docs/proposals`
- Focused proposal reads with `nl -ba docs/proposals/cloudkit_qr_multipeer_sync_proposal.md | sed -n '20,341p;523,744p'` and section-specific reads around pairing/trust/transport.
- Focused bridge/runtime reads across `ios/CryptoSavingsTracker`, `ios/CryptoSavingsTrackerTests`, and `ios/CryptoSavingsTrackerUITests`.
- `xcodebuild -list -project ios/CryptoSavingsTracker.xcodeproj`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-tests-r3.MeROWR -only-testing:CryptoSavingsTrackerTests/LocalBridgeFoundationTests -only-testing:CryptoSavingsTrackerTests/BridgeImportValidationServiceTests -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests test`  
  Result: failed after build/test launch because the local `iPhone 16` simulator device entry was stale on disk.
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-tests-r3b.IcjTb7 -only-testing:CryptoSavingsTrackerTests/LocalBridgeFoundationTests -only-testing:CryptoSavingsTrackerTests/BridgeImportValidationServiceTests -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests test`  
  Result: destination unavailable for the `CryptoSavingsTrackerTests` scheme in the local Xcode environment.
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-tests-r3c.2ZxLkT -only-testing:CryptoSavingsTrackerTests/LocalBridgeFoundationTests -only-testing:CryptoSavingsTrackerTests/BridgeImportValidationServiceTests -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests test`  
  Result: compile succeeded; the targeted bridge run executed 33 tests in 3 suites and failed with 3 issues, all in `LocalBridgeImportApplyServiceTests` (`controllerLoadsPackageAndApprovesReview`, `deletedGoalSnapshotRemovesOnlyMatchedGoal`, `omittedGoalSnapshotDoesNotDeleteAuthoritativeGoal`).
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-uitests-r3.Tlee7p -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests test`  
  Result: executed 5 tests; 2 passed and 3 failed (`testPairingRequiredScenarioKeepsBootstrapTokenHiddenAndShowsTransportFallbacks`, `testReadyScenarioKeepsBootstrapTokenHiddenUntilExplicitReveal`, `testReviewScenarioShowsDistinctOperatorActionsAndDismissPath`).

## Recommended Next Actions

- Fix the three failing `LocalBridgeSyncUITests` scenarios before claiming operator-complete rollout. The current regressions are in pairing-code visibility and review-state feedback after reject.
- Fix the three failing `LocalBridgeImportApplyServiceTests` cases. Right now the apply path still regresses approval messaging, goal-delete handling with dependents, and fingerprint stability when omitted snapshots are preserved.
- Decide whether `Phase 2B` should really promise resumable transfer and richer diagnostics/trust-review hardening yet. The runtime now transfers artifacts, but the proposal still claims more than the code and tests prove.
