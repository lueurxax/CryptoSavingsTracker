# CloudKit-Only Signed File Bridge for Mac Snapshot Sync Implementation Audit R1

| Field | Value |
|---|---|
| Proposal | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` |
| Repository Root | `.` |
| Git SHA | `be1c961` |
| Working Tree | `dirty` |
| Audited At | `2026-03-22T22:55:56+02:00` |
| Proposal State | `Active (Draft)` |
| Overall Status | `Not Implemented` |

## Verdict

The current repository contains a substantial Phase 2A bridge baseline: CloudKit-only authority, a dedicated `Local Bridge Sync` surface, Keychain-backed trust records, signed file artifacts, transient macOS workspace storage, import validation, and controlled apply all exist. The proposal is still **not implemented** as written because the mandatory appendix contract is not implemented exactly, Phase 2B QR/Multipeer runtime is still absent, and the review-ready UI acceptance path currently fails in simulator verification.

## Proposal Contract

### Scope

- Keep CloudKit as the only durable authority and layer bridge import/export around that runtime.
- Ship a dedicated `Local Bridge Sync` surface with pairing, trust management, manual sync, import review, validation status, and revocation.
- Use a signed file-based manual bridge for Phase 2A and an isolated transient macOS workspace.
- Reserve QR pairing and `MultipeerConnectivity` for Phase 2B hardening.
- Treat the canonical snapshot schema appendix as mandatory for hashing, replay, matching, dedupe, and apply semantics.

### Locked Decisions

- CloudKit is the only durable source of truth; there is no supported local-primary fallback.
- iPhone is the only authority allowed to apply imported data into the authoritative dataset.
- macOS edits only an isolated transient snapshot workspace and must not mutate the live store before iPhone acceptance.
- Drift is reject-and-re-export, not merge.
- Phase 2A is manual and foreground-only; richer review UX and stricter reconciliation barriers are future hardening, not baseline.
- Trust records must be Keychain-backed.

### Acceptance Criteria

- Export produces a signed file artifact while keeping the macOS snapshot isolated from the live store.
- Loading a signed package on iPhone verifies signature and opens review with concrete diffs visible before apply.
- Replay of an already-applied package returns `acceptedAlreadyApplied` with no duplicate write.
- Drift, schema mismatch, ambiguous matches, and orphan references reject safely.
- Reject, reset-to-pending, and dismiss-review are all no-ops against the authoritative dataset.
- Apply failures roll back without mutating the authoritative dataset.
- QR pairing must work when camera permission is granted and fail gracefully with manual fallback when denied.
- Deterministic fingerprinting and duplicate-prevention rules must hold.

### Test / Evidence Requirements

- Deterministic fingerprint validation for the same semantic dataset.
- Runtime/operator-visible proof for review, blocked apply, and pairing states.
- Validation of replay idempotency, duplicate prevention, and orphan rejection.
- Evidence that the bridge stays foreground-only and does not create a second sync authority.

### Explicit Exclusions

- No second sync engine parallel to CloudKit.
- No background bridge sync or auto reconnect.
- No per-record merge/conflict queue.
- No separate Mac companion distribution artifact.
- No fallback to the retired local-only authoritative runtime.

## Requirement Summary

| Status | Count |
|---|---:|
| Implemented | 7 |
| Partially Implemented | 2 |
| Missing | 2 |
| Not Verifiable | 1 |

## Requirement Audit

### REQ-001 CloudKit-only authority with no supported local-primary fallback
- Proposal Source: `Current State` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:22-33`), `Product Requirements` (`:72-82`), `Authority Model` (`:83-99`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:34-39`
  - `ios/CryptoSavingsTracker/Utilities/PersistenceController.swift:12-19`
  - `ios/CryptoSavingsTracker/Utilities/PersistenceController.swift:497-526`
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:95-121`
- Gap / Note: The runtime is explicitly reconciled to `cloudKitPrimary`, and retired local-primary store files are deleted on launch.

### REQ-002 Dedicated `Local Bridge Sync` entry point and operator surface exist in Settings
- Proposal Source: `Product Surface` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:135-171`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:95-121`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:17-223`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:29-42`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:99-110`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-uitests.cRtitM -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests test` executed; entry/navigation and pairing-required coverage passed.
- Gap / Note: The bridge destination and minimum top-level controls are present on iPhone.

### REQ-003 Trust records are Keychain-backed and revocation invalidates pending packages
- Proposal Source: `Secure Storage` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:281-295`), `Flow 3` (`:240-245`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/BridgeTrustStore.swift:12-83`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeArtifactStore.swift:107-140`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:696-724`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:140-200`
- Gap / Note: Trust is persisted in Keychain rather than `UserDefaults`, and revocation purges matching import artifacts before forcing re-pair.

### REQ-004 Manual bootstrap fallback, capability manifest, and update-required baseline behavior exist
- Proposal Source: `Camera Permission and Pairing Fallback` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:297-304`), `Protocol Evolution Policy` (`:306-323`), `BridgeCapabilityManifest` (`:523-534`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:160-191`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeIdentityStore.swift:85-116`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:166-236`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:53-99`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:449-466`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift:104-112`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeFoundationTests.swift:206-220`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:136-153`
- Gap / Note: Manual token generation/import and update-required compatibility blocking are implemented. QR-specific runtime is audited separately in `REQ-011`.

### REQ-005 Signed file artifacts and isolated transient macOS workspace exist
- Proposal Source: `macOS Snapshot Workspace Boundary` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:173-180`), `Flow 2` (`:228-238`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeArtifactStore.swift:54-89`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeTransientWorkspaceStore.swift:29-70`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:369-466`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:375-445`
- Gap / Note: The repository clearly separates transient workspace storage from authoritative persistence. This audit did not run macOS UI/runtime flows, but the code path is present.

### REQ-006 Import review is presented before apply and exposes safe operator actions
- Proposal Source: `iPhone Import Review Boundary` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:182-206`), `Flow 2` (`:233-237`), `Acceptance Criteria` (`:729-740`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:310-366`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:505-593`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift:679-694`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:269-372`
  - `ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift:11-197`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:113-133`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-uitests.cRtitM -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests test` failed 1/3 because `testReviewScenarioShowsDistinctOperatorActionsAndDismissPath` could not find `Concrete Diffs`.
- Gap / Note: The navigated review surface, reject/reset/dismiss semantics, and action CTAs exist, but the seeded review-ready runtime no longer proves the required diff evidence path end-to-end.

### REQ-007 Validation and apply pipeline enforces signature, drift, replay, and all-or-nothing apply
- Proposal Source: `Import Validation` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:610-635`), `Failure Handling` (`:636-662`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift:90-227`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift:229-276`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:157-252`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:254-381`
  - `ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift:9-154`
  - `ios/CryptoSavingsTrackerTests/BridgeImportValidationServiceTests.swift:233-260`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:202-313`
  - `ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift:136-153`
- Gap / Note: The baseline validation/apply pipeline exists. Exact appendix bytes and hashing semantics are still divergent and are captured in `REQ-008` and `REQ-009`.

### REQ-008 The mandatory canonical schema, fingerprint, and package-body contract is implemented exactly
- Proposal Source: `Normative Snapshot Schema Appendix` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:536-607`)
- Status: `Missing`
- Evidence Type: `code`, `inference`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:275-367`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:472-477`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:575-600`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSnapshotExportService.swift:64-159`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift:42-56`
- Gap / Note: The appendix is mandatory, but the implementation does not match it. Snapshot DTOs omit `recordState`, optional keys rely on default `Codable` omission behavior rather than explicit `null`, numeric fields remain native JSON numbers instead of canonical decimal strings, several array sort orders are simpler than the appendix order, and `packageID` / `baseDatasetFingerprint` / `editedDatasetFingerprint` are not built from the specified canonical package body contract.

### REQ-009 Appendix matching, dedupe, and delete semantics are honored
- Proposal Source: `Per-Entity Matching and Dedupe Policy` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:575-607`), `Import Validation` (`:619-621`)
- Status: `Partially Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:254-381`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:906-947`
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift:964-993`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:367-415`
  - `ios/CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests.swift:461-507`
- Gap / Note: The implementation already rejects duplicate logical keys, orphan references, and conflicting ID/logical-key matches, but it still applies delete-by-omission (`deleteMissing`) and cannot implement `recordState`-driven delete rules because the exported schema has no `recordState` field.

### REQ-010 Foreground-only transport declarations and constraints are present
- Proposal Source: `Transport Layer` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:325-349`), `Phase 2B` (`:715-724`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Info.plist:7-18`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:468-470`
- Gap / Note: Privacy strings, Bonjour service type, and a foreground-only background-mode profile are present. This does not prove the actual transport runtime, which is audited separately.

### REQ-011 QR pairing and `MultipeerConnectivity` runtime hardening exist
- Proposal Source: `Flow 4` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:247-252`), `Transport Layer` (`:325-341`), `Acceptance Criteria` (`:741-742`)
- Status: `Missing`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift:160-167`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:53-99`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:503-529`
  - `ios/CryptoSavingsTracker/Info.plist:7-18`
  - `rg -n "MultipeerConnectivity|MCSession|MCNearbyService|AVCapture|QRCode|QR code" ios/CryptoSavingsTracker ios/CryptoSavingsTrackerTests ios/CryptoSavingsTrackerUITests` returned only `Info.plist` declarations.
- Gap / Note: The repo contains declarations and a `scanQR` enum label, but no scanner UI, no camera-on-tap flow, no `MCSession` manager/browser/advertiser, and no transport handshake/runtime.

### REQ-012 Bootstrap secret redaction and observability hygiene are enforced
- Proposal Source: `Pairing Token` (`docs/proposals/cloudkit_qr_multipeer_sync_proposal.md:255-270`)
- Status: `Not Verifiable`
- Evidence Type: `code`, `inference`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeIdentityStore.swift:85-97`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:79-95`
  - `rg -n "oneTimeSecretReference|redact|analytics|debug logging" ios/CryptoSavingsTracker ios/CryptoSavingsTrackerTests ios/CryptoSavingsTrackerUITests`
- Gap / Note: The code clearly creates `oneTimeSecretReference`, but this audit found no bridge-specific redaction guardrails for logs/analytics/docs-screenshot workflows. The current manual-pairing UI also renders the full bootstrap token, so the proposal’s observability-hygiene claim is not provable from the repository.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md`
- `git rev-parse --show-toplevel`
- `git rev-parse --short HEAD`
- `git status --short`
- `rg -n "superseded|deprecated|replaced by|obsolete|Implementation Audit|TRIAD_REVIEW|EVIDENCE_PACK" docs/proposals/cloudkit_qr_multipeer_sync_proposal.md docs/proposals`
- Focused proposal reads with `nl -ba docs/proposals/cloudkit_qr_multipeer_sync_proposal.md | sed -n '1,820p'`
- Focused bridge/runtime searches with `rg -n` across `ios/CryptoSavingsTracker`, `ios/CryptoSavingsTrackerTests`, and `ios/CryptoSavingsTrackerUITests`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-build.kmJCAP build` — passed
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-tests.XXXXXX -only-testing:CryptoSavingsTrackerTests/LocalBridgeFoundationTests -only-testing:CryptoSavingsTrackerTests/BridgeImportValidationServiceTests -only-testing:CryptoSavingsTrackerTests/LocalBridgeImportApplyServiceTests test` — failed immediately because scheme `CryptoSavingsTracker` is not configured for the test action
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.0' -derivedDataPath /var/folders/fj/v77kf6rs4dz1ybsm1_1_qhb00000gn/T/proposal-audit-bridge-uitests.cRtitM -only-testing:CryptoSavingsTrackerUITests/LocalBridgeSyncUITests test` — executed 3 tests; 2 passed, 1 failed (`testReviewScenarioShowsDistinctOperatorActionsAndDismissPath`)

## Recommended Next Actions

- Align the runtime bytes with the mandatory appendix: add `recordState`, encode explicit `null` optionals, implement appendix sort rules, canonicalize numeric encoding, and compute `packageID` / base-vs-edited fingerprints from the specified canonical payloads.
- Finish or explicitly de-scope Phase 2B runtime. Right now the proposal includes QR pairing and `MultipeerConnectivity`, but the repo only has declarations and manual-token pairing.
- Fix the review-ready UI regression so `Concrete Diffs` and the dismiss/reopen flow pass `LocalBridgeSyncUITests`, then enable bridge unit tests under a scheme that actually supports the test action.
