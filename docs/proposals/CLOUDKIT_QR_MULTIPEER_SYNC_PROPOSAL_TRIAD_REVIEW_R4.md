# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `full-review`, downgraded to `Evidence Gap Review` fallback because the minimum runtime screenshot gate was not met.
- Evidence completeness: `Partial`
- Documents / repo inputs reviewed:
  - [cloudkit_qr_multipeer_sync_proposal.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md)
  - [CLOUDKIT_QR_MULTIPEER_SYNC_PROPOSAL_EVIDENCE_PACK_R4.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/CLOUDKIT_QR_MULTIPEER_SYNC_PROPOSAL_EVIDENCE_PACK_R4.md)
- External sources reviewed:
  - None required; this review stayed local to proposal, code, build, and simulator evidence.
- Build/run attempts:
  - [build.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r4/logs/build.log): `BUILD SUCCEEDED`
  - [presentation-screenshot-uitest.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r4/logs/presentation-screenshot-uitest.log): screenshot harness failed before capture
  - [settings-row-uitest.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r4/logs/settings-row-uitest.log): Settings row test passed
  - [applescript-gui-attempt.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r4/logs/applescript-gui-attempt.log): host GUI fallback blocked by missing Assistive Access
- Screenshots captured:
  - [home-current.png](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r4/screenshots/home-current.png)
- Code areas inspected:
  - [SettingsView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift)
  - [LocalBridgeSyncView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift)
  - [BridgeImportReviewView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift)
  - [BridgeImportReviewModels.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge/BridgeImportReviewModels.swift)
  - [LocalBridgeModels.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift)
  - [LocalBridgeImportValidationService.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift)
  - [LocalBridgeSnapshotExportService.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSnapshotExportService.swift)
  - [LocalBridgeImportApplyService.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportApplyService.swift)
  - [LocalBridgeSyncController.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift)
- Remaining assumptions:
  - The main review target for this turn is the iPhone Phase 2A bridge surface.
  - The proposal is trying to describe both currently shipped bridge baseline and the remaining target contract.
- Remaining blockers:
  - No fresh live screenshot of `LocalBridgeSyncView` or import-review non-happy states
  - Built-in screenshot UITest is currently broken for this flow
  - Host GUI scripting fallback is blocked

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `Medium`
- Release blockers:
  - The proposal currently overstates the implemented CloudKit checkpoint contract.
  - The proposal's current-state framing overstates the implemented import-review interaction boundary.
  - Canonical schema examples remain out of sync with the live bridge payload shape.
- Top risks:
  1. The document promises stronger export/apply safety than the bridge code currently enforces around CloudKit reconciliation.
  2. The document describes a blocking full-screen review boundary, but the runtime exposes a navigable and dismissible review path.
  3. The proposal's early schema examples can produce package shapes and fingerprints that differ from the current implementation.
- Top opportunities:
  1. The Settings entry point and signed-file bridge baseline are real now, so the proposal can stop speaking about them as purely future-state.
  2. The bridge already has signature, trust, drift, and diff plumbing; aligning the document to the actual operator contract is tractable.
  3. A small amount of bridge-specific UI coverage would close the main evidence gap quickly.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | Amber | Medium | Partial | 0 | 0 | 1 | 0 |
| UX | Amber | Medium | Partial | 0 | 1 | 1 | 0 |
| iOS Architecture | Amber | Medium | Partial | 0 | 1 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Findings
- Finding ID: `F-UI-01`
  Severity: `Medium`
  Evidence IDs: `DOC-02`, `DOC-07`, `CODE-02`, `CODE-03`, `RUN-04`
  Why it matters:
  The proposal requires a dedicated blocking full-screen `Import Review` flow before apply, but the current bridge UI opens review through a `NavigationLink` inside `LocalBridgeSyncView` and also exposes an explicit `Dismiss Review` action from the parent surface. That is a materially different operator boundary.
  Recommended fix:
  Either change the proposal's current-state wording to say the current build has a navigated review surface and keep the blocking full-screen boundary as remaining work, or update the runtime to a modal/blocking review before calling that boundary implemented.
  Acceptance criteria:
  The current-state section, Phase 2A minimums, and live interaction model all describe the same review boundary.
  Confidence:
  `Medium`

### 3.2 UX Findings
- Finding ID: `F-UX-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `DOC-02`, `DOC-06`, `DOC-07`, `CODE-03`, `CODE-04`, `CODE-05`
  Why it matters:
  The proposal says the current implementation already includes structural import-review validation and defines an operator-facing `ImportReviewSummary` with typed `goalDiffs`, `allocationDiffs`, `transactionDiffs`, and `monthlyPlanDiffs`. The live runtime is narrower: `BridgeImportReviewSummaryDTO` exposes generic `entityDeltas` plus `concreteDiffs`, and transaction/allocation/monthly-plan summaries still compress money-impact into technical strings and IDs. That makes it unclear whether the rich finance-grade review is already shipped or is still target-state.
  Recommended fix:
  Split "implemented baseline" from "target operator contract" explicitly. If the typed diff schema is still target-state, move it out of the current-implementation framing. If it is supposed to be current, align the DTO and UI copy to that contract.
  Acceptance criteria:
  The current-state section, JSON schema examples, and live review UI all describe the same operator-visible diff contract.
  Confidence:
  `Medium`

- Finding ID: `F-UX-02`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `DOC-06`, `CODE-05`
  Why it matters:
  The code does generate concrete diffs for the required entity families, but transaction/allocation/monthly-plan summaries still lean on UUIDs, asset IDs, and compressed technical text rather than the human-readable before/after copy shown in the proposal example. For a money-impacting review boundary, that is a meaningful gap in operator explainability.
  Recommended fix:
  Either soften the current-state claim, or uplift live summaries to named assets/goals and explicit before/after amounts so the runtime matches the proposal's operator language.
  Acceptance criteria:
  An operator can explain imported money-impact from the review surface without reading raw IDs.
  Confidence:
  `Medium`

### 3.3 iOS Architecture Findings
- Finding ID: `F-ARCH-01`
  Severity: `High`
  Evidence IDs: `DOC-03`, `DOC-07`, `CODE-07`, `CODE-08`, `CODE-09`, `DATA-01`
  Why it matters:
  The proposal defines a foreground CloudKit reconciliation checkpoint before export and again immediately before apply, including unresolved obligation checks. The live bridge path currently proves only that the CloudKit-backed runtime is active and re-exports current local data for drift validation; `LocalBridgeSyncController` also stamps `.reconciled` optimistically across several transitions. That is weaker than the checkpoint contract described in the proposal.
  Recommended fix:
  Describe the current implementation honestly as `CloudKit-primary + drift revalidation`, or wire bridge export/apply to a concrete reconciliation barrier / health monitor before calling the full checkpoint contract implemented.
  Acceptance criteria:
  Bridge export/apply gate on the same reconciliation source of truth the proposal names, rather than on controller-local state plus active-mode checks.
  Confidence:
  `High`

- Finding ID: `F-ARCH-02`
  Severity: `Medium`
  Evidence IDs: `DOC-04`, `CODE-06`
  Why it matters:
  The proposal's `SnapshotManifest` example still models `entityCounts` as an object map, but the live `SnapshotManifest` DTO uses `[BridgeEntityCount]`. That makes the proposal's package example misleading for anyone trying to validate or generate artifacts against the current code.
  Recommended fix:
  Update the example to the real wire shape, or mark the map form as illustrative and explicitly non-canonical.
  Acceptance criteria:
  The proposal example decodes against the current manifest DTO without adapter logic.
  Confidence:
  `High`

- Finding ID: `F-ARCH-03`
  Severity: `Medium`
  Evidence IDs: `DOC-05`, `DOC-07`, `CODE-06`, `CODE-08`
  Why it matters:
  The early `SnapshotEnvelope` example and canonical root-order text enumerate only seven top-level arrays, but the live exported and fingerprinted envelope also includes `completedExecutions`, `executionSnapshots`, and `completionEvents`. The same proposal later defines matching and ordering rules for those entities, so the document is internally inconsistent and out of sync with code. An implementer who follows the earlier schema literally can produce incompatible fingerprints.
  Recommended fix:
  Make the full root schema explicit in the first `SnapshotEnvelope` example and keep the canonical root-order text aligned with the implementation.
  Acceptance criteria:
  The proposal's first schema example, appendix order rules, and implementation enumerate the same top-level fields in the same order.
  Confidence:
  `High`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict:
  The proposal is trying to document both the currently shipped bridge baseline and the stronger target operator contract in the same sections.
- Tradeoff:
  A single merged narrative is faster to maintain, but readers lose clarity about what is already live versus what remains target-state.
- Decision:
  Split current-state baseline from target-state contract. Only call behavior "implemented" when UI, DTO/schema, and runtime enforcement all agree.
- Owner:
  Proposal author + iOS implementation owner

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P1 | Separate implemented baseline from target contract in the proposal; fix full-screen review wording and CloudKit checkpoint claims | UI / UX / Architecture | Proposal author | Now | None | Current-state sections stop over-claiming relative to the live runtime | `F-UI-01`, `F-UX-01`, `F-ARCH-01` |
| P1 | Align `SnapshotManifest` and `SnapshotEnvelope` examples with the live wire shape | Architecture | Proposal author | Now | None | Proposal examples decode and fingerprint against the current bridge schema | `F-ARCH-02`, `F-ARCH-03` |
| P2 | Decide whether Phase 2A baseline is the current generic diff surface or the richer typed diff contract, then align the proposal and runtime accordingly | UX | Product + iOS | Next | P1 framing cleanup | Review DTO, UI copy, and proposal examples all describe the same operator contract | `F-UX-01`, `F-UX-02` |
| P2 | Add bridge-specific UI coverage and capture fresh `LocalBridgeSyncView` / import-review non-happy path screenshots | UI / QA | iOS | Next | Screenshot harness repair or alternative automation | Full-review screenshot gate can be completed without manual host scripting | `RUN-03`, `RUN-05`, `BASE-03` |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Review boundary | Whether `Import Review` is modal/blocking or intentionally navigable | Fresh simulator screenshots and bridge UI tests | Proposal wording must match actual interaction model | Before the next proposal revision is approved | Hold if the proposal still says "blocking full-screen" while the runtime remains navigable |
| CloudKit gating | Whether export/apply use a real reconciliation barrier versus controller-local flags | A test that forces unresolved CloudKit state and verifies export/apply blocking | No optimistic `.reconciled` status without the same barrier source of truth named in the doc | Before Phase 2A is called implemented in docs | Hold if active-mode checks remain the only hard gate |
| Snapshot schema | Whether proposal examples match current canonical DTOs and fingerprints | Fixture decode/fingerprint check against the live model types | No adapter-only compatibility for proposal examples | During proposal refresh | Hold if proposal examples still omit live canonical fields |
| Operator diff copy | Whether the review surface is operator-readable without raw IDs | UI tests or snapshots for goal/transaction/allocation/monthly-plan diffs | Avoid UUID-heavy summaries if the proposal keeps finance-grade wording | Before next UX signoff | Hold if proposal examples remain richer than the runtime copy |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- GAP-01: No fresh live screenshot of `LocalBridgeSyncView` or import-review non-happy states was captured. The only fresh app screenshot is [home-current.png](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r4/screenshots/home-current.png).
- GAP-02: [presentation-screenshot-uitest.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r4/logs/presentation-screenshot-uitest.log) shows the built-in screenshot test fails before capture because `PRESENTATION_SCREENSHOT_OUTPUT_DIR` is empty during the test run.
- GAP-03: Existing UI coverage in [FamilySharingUITests.swift:110](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift#L110) verifies the Settings row only; it does not open the bridge destination or exercise import review / drift / rejection states.

### Open Questions
- QUESTION-01: Do you want the proposal to freeze the currently shipped generic review DTO as the official Phase 2A baseline, or keep the richer typed diff schema as the baseline and treat the runtime as still incomplete?
- QUESTION-02: Is the blocking full-screen `Import Review` still a hard requirement, or is the current navigated review acceptable?

## Evidence Gap Review Fallback
- What was attempted:
  - Read the current proposal end to end and compared it against the live bridge implementation.
  - Built the current iOS app successfully on the iPhone 15 iOS 18.0 simulator.
  - Launched the app in simulator and captured a fresh runtime baseline screenshot.
  - Ran the existing Settings-row UI test successfully to confirm the live `Local Bridge Sync` entry.
  - Tried the repo's screenshot UITest harness and host GUI scripting fallback for deeper capture.
- What is missing:
  - Fresh screenshots of the live `LocalBridgeSyncView`
  - Fresh screenshots of `Import Review` and at least one important non-happy path
  - Live macOS bridge-session evidence for the transient workspace side
- Blockers:
  - The built-in screenshot UITest fails before capture because `PRESENTATION_SCREENSHOT_OUTPUT_DIR` is empty inside the test run.
  - Host GUI scripting is blocked by missing Assistive Access.
  - No existing UI test drives the bridge destination itself.
- Confidence:
  - `Medium` on the proposal/code conflict findings above
  - `Low` on any claim that would require visual confirmation of the final live bridge surface
- What can still be said with partial confidence:
  - The Settings entry point is already implemented and visible.
  - The current review surface is navigable/dismissible, not clearly the blocking full-screen boundary the proposal names.
  - The current bridge path does drift revalidation, but not the stronger reconciliation-checkpoint contract the proposal describes.
  - The proposal's manifest/envelope examples are stale relative to the live canonical payload shape.
- What evidence is required to finish the full review:
  - A repaired screenshot harness or new bridge UI test that opens `LocalBridgeSyncView`
  - Fresh simulator screenshots for `LocalBridgeSyncView`, `Import Review`, and at least one rejected or blocked import state
  - Optional but valuable: a fresh macOS transient-workspace capture to validate the other half of Phase 2A
