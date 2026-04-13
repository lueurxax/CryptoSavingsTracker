# CloudKit-Only Signed File Bridge for Mac Snapshot Sync Implementation Audit R2

| Field | Value |
|---|---|
| Proposal | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` |
| Repository Root | `.` |
| Git SHA | `be1c961` |
| Working Tree | `dirty` |
| Audited At | `2026-03-23T00:21:25+0200` |
| Proposal State | `Active (Draft)` |
| Overall Status | `Partial` |

## Verdict

The repository now implements most of the Phase 2A bridge baseline and part of the Phase 2B transport hardening. Canonical snapshot encoding, deterministic fingerprinting, receipt-backed replay handling, `recordState`-driven deletes, QR scanner runtime, and foreground `MultipeerConnectivity` discovery all now exist. The proposal is still only **partially implemented** because the mandatory appendix is not matched exactly at the `SignedImportPackage` shape level, the bridge-focused unit test target currently fails to compile, and the targeted `LocalBridgeSyncUITests` run still fails two operator-visible acceptance scenarios.

This audit was performed against the current dirty local worktree, including uncommitted bridge and proposal changes.

## Proposal Contract

### Scope

- Keep CloudKit as the only durable authority and layer bridge import/export around that runtime.
- Ship a dedicated `Local Bridge Sync` surface with pairing, trust management, manual sync, import review, validation status, and revocation.
- Use a signed file-based bridge with an isolated transient macOS workspace for the Phase 2A baseline.
- Treat the canonical snapshot schema appendix as mandatory for hashing, replay, matching, dedupe, and apply semantics.
- Add QR and `MultipeerConnectivity` transport hardening only as Phase 2B foreground enhancements.

### Locked Decisions

- CloudKit remains the only durable source of truth; there is no supported local-primary fallback.
- The Mac never writes directly to CloudKit.
- Every bridge session starts from a full authoritative snapshot and is validated against a fresh authoritative re-export before apply.
- Drift is reject-and-re-export, not merge.
- Trust records are Keychain-backed.
- The bridge remains manual and foreground-only.

### Acceptance Criteria

- Export produces a signed package artifact while keeping the macOS snapshot isolated from the live store.
- Loading a signed package on iPhone verifies signature and opens review with concrete diffs visible before apply.
- Replay of an already-applied package returns `acceptedAlreadyApplied` with no duplicate write.
- Drift, schema mismatch, ambiguous matches, and orphan references reject safely.
- Reject, reset-to-pending, and dismiss-review do not mutate the authoritative dataset.
- Apply failures roll back without mutating the authoritative dataset.
- QR pairing succeeds with camera permission and degrades gracefully to manual pairing when permission is denied or unavailable.
- Deterministic fingerprinting and duplicate-prevention rules hold.

### Test / Evidence Requirements

- Deterministic fingerprint proof for unchanged semantic datasets.
- Runtime/operator-visible proof for pairing, review, and blocked-review states.
- Validation of replay idempotency, duplicate prevention, orphan rejection, and delete handling.
- Proof that the bridge remains manual/foreground-only and does not become a second sync authority.

### Explicit Exclusions

- No second sync engine parallel to CloudKit.
- No background bridge sync or auto reconnect.
- No local-primary authoritative fallback.
- No per-record merge queue.
- No companion-product split from the existing app surface.

## Requirement Summary

| Status | Count |
|---|---:|
| Implemented | 6 |
| Partially Implemented | 4 |
| Missing | 0 |
| Not Verifiable | 0 |

## Requirement Audit

### REQ-001 CloudKit remains the only durable authority and local-primary fallback stays retired
- Proposal Source: `Current State` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:22-29`), `Product Requirements` (`:72-81`), `Authority Model` (`:83-123`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/PersistenceController.swift:12-19`
  - `ios/CryptoSavingsTracker/Utilities/PersistenceController.swift:497-526`
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:95-121`
- Gap / Note: The runtime still reconciles startup into `cloudKitPrimary`, removes retired local-primary store files, and exposes the bridge as a CloudKit-adjacent workflow rather than a second authority.

### REQ-002 A dedicated `Local Bridge Sync` surface exists off the top-level Settings row
- Proposal Source: `Phase 2 Product Surface` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:135-171`), `Flow 1` (`:223-226`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:95-121`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:72-176`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-uitests-r2.BCRh1Q -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests test` executed; `testPairingRequiredScenarioShowsPairMacAndEmptyTrustedDevices` and `testBlockedReviewScenarioShowsUpdateRequiredAndDisablesApply` passed.
- Gap / Note: The dedicated destination is present. Operator-surface acceptance gaps are tracked separately in `REQ-008`.

### REQ-003 Trust records are Keychain-backed and revocation invalidates pending packages
- Proposal Source: `Secure Storage` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:281-295`), `Flow 3` (`:240-245`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/BridgeTrustStore.swift:12-83`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeArtifactStore.swift:107-140`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:696-724`
- Gap / Note: Trust is persisted through Keychain, and revocation purges unconsumed import packages plus clears any currently loaded package from the same revoked device.

### REQ-004 Compatibility negotiation and `Update Required` blocking exist in the baseline
- Proposal Source: `Protocol Evolution Policy` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:306-323`), `BridgeCapabilityManifest` (`:523-534`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:187-207`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift:112-120`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:155-172`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-uitests-r2.BCRh1Q -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests test` executed; blocked-review/update-required scenario passed.
- Gap / Note: The current baseline negotiates only `bridge-snapshot-v1` / schema `1`, but it does enforce rejection outside that range.

### REQ-005 The bridge uses an isolated transient workspace and exports signed file artifacts
- Proposal Source: `macOS Snapshot Workspace Boundary` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:173-180`), `Flow 2` (`:228-238`), `Phase 2A` (`:700-713`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransientWorkspaceStore.swift:29-70`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:369-466`
- Gap / Note: Workspace save/load/clear is file-backed and separate from the live store, and exported artifacts are generated only from that transient snapshot.

### REQ-006 Validation, replay idempotency, duplicate prevention, and `recordState`-driven delete/apply semantics exist
- Proposal Source: `Fingerprint and Replay Rules` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:567-573`), `Per-Entity Matching and Dedupe Policy` (`:575-607`), `Import Validation` (`:610-617`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:176-250`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:279-288`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:420-518`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:366-415`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:443-520`
- Gap / Note: Receipt-backed replay handling, orphan validation, and delete-by-`recordState` matching are all present in code. The related tests exist, but they were not executed because the broader `CryptoSavingsTrackerTests` target currently fails to compile in another bridge test file.

### REQ-007 The mandatory appendix canonical encoding and package-body contract matches the proposal exactly
- Proposal Source: `Normative Snapshot Schema Appendix` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:536-607`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeCanonicalEncoding.swift:47-98`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeCanonicalEncoding.swift:347-400`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:728-735`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:754-971`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSnapshotExportService.swift:49-326`
  - `ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift:205-233`
- Gap / Note: The implementation now covers canonical ordering, explicit `null`, lowercase UUIDs, epoch-millisecond dates, decimal-string numerics, and canonical package hashing. It still does not match the appendix exactly because the proposal’s `SignedImportPackage` shape only defines `packageID`, `snapshotID`, `canonicalEncodingVersion`, `baseDatasetFingerprint`, `editedDatasetFingerprint`, `snapshotEnvelope`, `signingKeyID`, `signedAt`, and `signature` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:408-422`), while the runtime canonical package body also includes `signingAlgorithm` and `signerPublicKeyRepresentation` (`ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeCanonicalEncoding.swift:391-394`, `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:910-913`). Proof is further weakened because the targeted unit test action failed to compile in `ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift:214`, `:220`, and `:228-232`.

### REQ-008 The operator-visible pairing and review acceptance surfaces are proven in simulator behavior
- Proposal Source: `iPhone Import Review Boundary` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:182-206`), `Phase 2 Test Matrix and Acceptance Criteria` (`:729-744`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift:24-197`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:688-693`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:113-129`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:132-152`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-uitests-r2.BCRh1Q -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests test` failed with 2/4 tests failing.
- Gap / Note: The runtime exposes the review surface, package summary, reject/reset actions, and dismiss-review path. The current simulator proof is still incomplete: `testPairingRequiredScenarioKeepsBootstrapTokenHiddenAndShowsTransportFallbacks` failed at `LocalBridgeSyncUITests.swift:118`, and `testReviewScenarioShowsDistinctOperatorActionsAndDismissPath` failed at `:148` when validating the concrete review surface.

### REQ-009 QR scanning, manual fallback, and bootstrap-token observability hygiene exist
- Proposal Source: `Pairing Token` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:255-270`), `Camera Permission and Pairing Fallback` (`:297-304`), `Acceptance Criteria` (`:741-742`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `tests-found`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:176-184`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeQRScannerView.swift:70-88`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:80-124`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:584-637`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:739-809`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift:231-242`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-uitests-r2.BCRh1Q -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests test` failed in the pairing/fallback acceptance case.
- Gap / Note: Camera permission is requested only when the scanner opens, denial explicitly falls back to manual pairing, and the default rendered token is redacted with `.privacySensitive()`. The operator-visible fallback path is still not fully proven because the seeded pairing UI test cannot reliably discover the hidden-token surface, and the current `Enter Code Manually` flow still opens the same bootstrap-token entry sheet used for full-token paste rather than a distinct short-code UX.

### REQ-010 Phase 2B foreground transport hardening is complete
- Proposal Source: `Transport Layer` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:325-341`), `Phase 2B: Transport Hardening` (`:715-724`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `inference`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransportCoordinator.swift:8-199`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransportCoordinator.swift:200-220`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:126-176`
  - `rg -n "resum|diagnostic|typed diff|goalDiffs|allocationDiffs|transactionDiffs|monthlyPlanDiffs|sendResource|didStartReceivingResource|didFinishReceivingResource" ios/CryptoSavingsTracker ios/CryptoSavingsTrackerTests ios/CryptoSavingsTrackerUITests`
- Gap / Note: Foreground advertiser/browser/session runtime now exists and can exchange bootstrap tokens over `MCSession`. The rest of Phase 2B hardening is still incomplete: there is no actual package/resource transfer path, no resumable foreground transfer, the resource callbacks are empty, and the richer operator diagnostics / review scanability hardening listed in the proposal were not found in the bridge runtime.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md`
- `git rev-parse --show-toplevel`
- `git rev-parse --short HEAD`
- `git status --short`
- `date '+%Y-%m-%dT%H:%M:%S%z'`
- `rg -n "superseded|deprecated|replaced by|obsolete|Implementation Audit|TRIAD_REVIEW|EVIDENCE_PACK" docs/proposals/cloudkit_qr_multipeer_sync_proposal.md docs/proposals`
- Focused proposal reads with `nl -ba docs/proposals/cloudkit_qr_multipeer_sync_proposal.md | sed -n ...`
- Focused bridge/runtime searches with `rg -n` across `ios/CryptoSavingsTracker`, `ios/CryptoSavingsTrackerTests`, and `ios/CryptoSavingsTrackerUITests`
- `xcodebuild -list -project ios/CryptoSavingsTracker.xcodeproj`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-tests-r2.wMwqdt -only-testing:CryptoSavingsTrackerTests/LocalBridgeFoundationTests -only-testing:CryptoSavingsTrackerTests/BridgeImportValidationServiceTests -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests test`  
  Result: failed immediately because that destination was unavailable for the scheme in the local Xcode environment.
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-tests-r2b.GUnCoZ -only-testing:CryptoSavingsTrackerTests/LocalBridgeFoundationTests -only-testing:CryptoSavingsTrackerTests/BridgeImportValidationServiceTests -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests test`  
  Result: build failed in `BridgeImportValidationServiceTests.swift` with compile-time errors before any selected bridge unit tests could run.
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-uitests-r2.BCRh1Q -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests test`  
  Result: executed 4 tests; 2 passed and 2 failed (`testPairingRequiredScenarioKeepsBootstrapTokenHiddenAndShowsTransportFallbacks`, `testReviewScenarioShowsDistinctOperatorActionsAndDismissPath`).

## Recommended Next Actions

- Align the mandatory appendix with the runtime or vice versa: either remove extra canonical package fields from `SignedImportPackage`, or update the proposal appendix to define them explicitly.
- Fix `ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift` so the targeted bridge unit suite compiles and can actually prove the new canonical-contract behavior.
- Repair the failing UI acceptance paths in `LocalBridgeSyncUITests`: the hidden bootstrap token/fallback surface and the review surface’s concrete-diff / approval discoverability are still not proven.
- Finish or explicitly de-scope the remaining Phase 2B hardening items: actual package transfer over Multipeer, resumable foreground transfer, and richer diagnostics / review scanability.
