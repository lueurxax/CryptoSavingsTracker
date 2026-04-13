# CloudKit-Only Signed File Bridge for Mac Snapshot Sync Implementation Audit R4

| Field | Value |
|---|---|
| Proposal | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` |
| Repository Root | `.` |
| Git SHA | `be1c961` |
| Working Tree | `dirty` |
| Audited At | `2026-03-23T08:40:52+0200` |
| Proposal State | `Active (Draft)` |
| Overall Status | `Partial` |

## Verdict

The repository still audits as **partial**. Since `R3`, the working tree changed in the exact bridge surfaces that previously failed fresh verification, especially `LocalBridgeImportApplyService.swift`, `LocalBridgeSyncController.swift`, and related UI/test files. Those changes materially move the implementation toward the proposal contract: apply now normalizes incoming envelopes against the current authoritative snapshot, delete paths are explicit in the apply plan, import review state handling is clearer, trust revocation invalidates loaded packages, and the UI test controller now seeds dedicated pairing/review scenarios. However, the fresh `R4` verification reruns could not re-establish those previously failing scenarios because both targeted test runs died in simulator/test-runner infrastructure before functional assertions completed. Phase 2B also remains only partially implemented from code inspection: foreground Multipeer transfer and progress reporting exist, but resumable transfer and the proposal's richer diagnostics / scanability hardening are still not evidenced.

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
| Implemented | 6 |
| Partially Implemented | 1 |
| Missing | 0 |
| Not Verifiable | 3 |

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
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:98-220`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:99-167`
- Gap / Note: The dedicated destination exists and test coverage exists for seeded bridge states. Fresh UI verification for changed review/pairing scenarios is tracked separately under `REQ-008` and `REQ-009` because the `R4` rerun crashed before assertions completed.

### REQ-003 Trust records are Keychain-backed and revocation invalidates pending packages
- Proposal Source: `Flow 3: Trust Bootstrap` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:240-245`), `Secure Storage` (`:281-295`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/BridgeTrustStore.swift:12-83`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeArtifactStore.swift:107-145`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:637-645`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:706-735`
- Gap / Note: Revocation now purges pending import artifacts for the revoked peer and clears any currently loaded package that matches the revoked signing identity.

### REQ-004 Compatibility negotiation and `Update Required` blocking exist before snapshot import/apply
- Proposal Source: `Protocol Evolution Policy` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:306-323`), `Phase 2 Test Matrix and Acceptance Criteria` (`:732`, `:739`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift:112-158`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:341-371`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift:206`
  - `ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift:71`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:167`
- Gap / Note: The compatibility gate is implemented in code and has direct test coverage. I did not get a fresh passing `R4` execution for those tests because the targeted UI rerun exited before the runner finished bootstrapping.

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
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:415`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:418`
- Gap / Note: The appendix-shape canonical encoder now drives package body generation, signing payload generation, and deterministic snapshot hashing. Relevant proof tests exist, but I did not rerun them in `R4`.

### REQ-007 Import/apply semantics reject drift safely and preserve replay/delete/omission safety
- Proposal Source: `Current State` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:29-33`), `Import / Validation Flow` (`:613-617`), `Phase 2 Test Matrix and Acceptance Criteria` (`:731`, `:734-740`, `:744`)
- Status: `Not Verifiable`
- Evidence Type: `code`, `tests-found`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:220-238`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:258-360`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:489-595`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:622-837`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:10`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:444`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:528`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r4-unit.zVlL9i -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests/controllerLoadsPackageAndApprovesReview -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests/deletedGoalSnapshotRemovesOnlyMatchedGoal -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests/omittedGoalSnapshotDoesNotDeleteAuthoritativeGoal test`
- Gap / Note: The changed code strongly suggests the `R3` apply-path regressions were addressed: apply now normalizes incoming envelopes against the current authoritative snapshot, shape validation ignores deleted records, and explicit delete planning exists for goals, assets, monthly execution records, and monthly plans. I cannot promote this to `Implemented` because the fresh targeted rerun failed at test-runner launch with `NSMachErrorDomain Code=-308` before proving those cases.

### REQ-008 Operator-visible import review, approve/reject/reset, and dismiss-review lifecycle is complete
- Proposal Source: `Phase 2 Product Surface` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:138-140`, `:196`, `:213`), `Phase 2 Test Matrix and Acceptance Criteria` (`:730`, `:736-740`)
- Status: `Not Verifiable`
- Evidence Type: `code`, `tests-found`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift:9-215`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:341-371`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:576-703`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:756-980`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:144`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:167`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r4-ui.fp2dbA -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testReviewScenarioShowsDistinctOperatorActionsAndDismissPath -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testBlockedReviewScenarioShowsUpdateRequiredAndDisablesApply test`
- Gap / Note: The shipped review UI, operator actions, blocked-review copy, and test-only seeding hooks are now present. Since the controller and seeding code changed after `R3`, the old `R3` failures are stale for this area. Fresh proof is still missing because the targeted UI rerun failed before the runner established a connection.

### REQ-009 QR pairing, camera fallback, and manual pairing-code flow are operator-complete
- Proposal Source: `Pairing Token` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:255-270`), `Camera Permission and Pairing Fallback` (`:297-304`), `Phase 2 Test Matrix and Acceptance Criteria` (`:741-742`)
- Status: `Not Verifiable`
- Evidence Type: `code`, `tests-found`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:228-245`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:199-210`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:98-152`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:154-220`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:651-680`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:818-840`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeQRScannerView.swift:70-88`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift:216`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift:231`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift:242`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:113`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:131`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r4-ui.fp2dbA -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testPairingRequiredScenarioKeepsBootstrapTokenHiddenAndShowsTransportFallbacks -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testReadyScenarioKeepsBootstrapTokenHiddenUntilExplicitReveal test`
- Gap / Note: The codebase now has a short pairing code, full-token fallback, QR permission failure messaging, and nearby token transfer controls. I am leaving this `Not Verifiable` because the exact operator-visible pairing scenarios that mattered in `R3` were rerun in `R4`, but the UITest runner crashed before proving them.

### REQ-010 Phase 2B transport hardening is complete
- Proposal Source: `Transport Layer` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:325-349`), `Phase 2B: Transport Hardening` (`:715-724`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `inference`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransportCoordinator.swift:8-168`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransportCoordinator.swift:269-298`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:154-220`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeQRScannerView.swift:70-88`
- Gap / Note: Foreground advertiser/browser/session runtime exists, real artifact transfer uses `sendResource`, and both incoming and outgoing transfer progress are surfaced. I still do not find explicit resumable transfer or code that clearly closes the proposal's broader promises around richer diagnostics, trust-review UX hardening, and scanability improvements for the financial diff surface.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md`
- `git rev-parse --show-toplevel`
- `git rev-parse --short HEAD`
- `git status --short /Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift`
- `date '+%Y-%m-%dT%H:%M:%S%z'`
- `rg -n "superseded|deprecated|replaced by|obsolete" docs/proposals/cloudkit_qr_multipeer_sync_proposal.md docs/proposals`
- Focused proposal reads with `nl -ba docs/proposals/cloudkit_qr_multipeer_sync_proposal.md | sed -n '20,350p;700,760p'`
- Proposal section targeting with `rg -n "canonical|fingerprint|duplicate-prevention|acceptedAlreadyApplied|idempot|drift" docs/proposals/cloudkit_qr_multipeer_sync_proposal.md`
- Focused code reads across `PersistenceController`, `LocalBridgeImportValidationService`, `LocalBridgeImportApplyService`, `LocalBridgeSyncController`, `LocalBridgeCanonicalEncoding`, `LocalBridgeModels`, `LocalBridgeTransientWorkspaceStore`, `LocalBridgeArtifactStore`, `LocalBridgePackageStore`, `LocalBridgeTransportCoordinator`, `SettingsView`, `LocalBridgeSyncView`, and `BridgeImportReviewView`
- Focused test discovery with:
  - `rg -n "canonical|fingerprint|packageID|acceptedAlreadyApplied|duplicate" ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift`
  - `rg -n "update required|compatib|blocked review|schema mismatch|trust revoked" ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift`
  - `rg -n "pairing code|bootstrap token|Scan QR|Enter Pairing Code|review scenario|PairingRequired|ReadyScenario|ReviewScenario" ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r4-unit.zVlL9i -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests/controllerLoadsPackageAndApprovesReview -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests/deletedGoalSnapshotRemovesOnlyMatchedGoal -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests/omittedGoalSnapshotDoesNotDeleteAuthoritativeGoal test`  
  Result: build reached `Testing started`, then failed before functional proof with `Failed to launch app with identifier: xax.CryptoSavingsTracker` and `NSMachErrorDomain Code=-308 "(ipc/mig) server died"`. `xcresult`: `/var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r4-unit.zVlL9i/Logs/Test/Test-CryptoSavingsTrackerTests-2026.03.23_08-35-07-+0200.xcresult`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r4-ui.fp2dbA -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testPairingRequiredScenarioKeepsBootstrapTokenHiddenAndShowsTransportFallbacks -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testReadyScenarioKeepsBootstrapTokenHiddenUntilExplicitReveal -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests/testReviewScenarioShowsDistinctOperatorActionsAndDismissPath test`  
  Result: build reached `Testing started`, then the runner exited early with simulator service-hub failures and `Early unexpected exit, operation never finished bootstrapping - no restart will be attempted`. `xcresult`: `/var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-r4-ui.fp2dbA/Logs/Test/Test-CryptoSavingsTrackerUITests-2026.03.23_08-35-07-+0200.xcresult`

## Recommended Next Actions

- Re-run the targeted bridge unit and UI commands from this report on a stable simulator host before changing the requirement verdicts for `REQ-007`, `REQ-008`, and `REQ-009`.
- If those reruns pass, promote the three `Not Verifiable` requirements directly; the current code changes are already aligned with the proposal areas that failed in `R3`.
- Decide whether the proposal should keep promising resumable transfer and richer Phase 2B diagnostics now, or narrow that scope to the Multipeer transfer/runtime already evidenced in code.
