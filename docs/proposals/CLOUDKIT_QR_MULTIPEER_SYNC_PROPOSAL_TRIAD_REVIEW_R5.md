# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `full-review`, downgraded to `Evidence Gap Review` fallback because the minimum screenshot gate is still not met.
- Evidence completeness: `Partial`
- Documents / repo inputs reviewed:
  - [cloudkit_qr_multipeer_sync_proposal.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md)
  - [CLOUDKIT_QR_MULTIPEER_SYNC_PROPOSAL_EVIDENCE_PACK_R5.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/CLOUDKIT_QR_MULTIPEER_SYNC_PROPOSAL_EVIDENCE_PACK_R5.md)
  - [proposal-diff.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r5/logs/proposal-diff.log)
- External sources reviewed:
  - None required
- Build/run attempts:
  - Reused `R4` [build.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r4/logs/build.log)
  - Reused `R4` [settings-row-uitest.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r4/logs/settings-row-uitest.log)
  - Reused `R4` [presentation-screenshot-uitest.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r4/logs/presentation-screenshot-uitest.log)
- Screenshots captured:
  - Reused `R4` [home-current.png](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r4/screenshots/home-current.png)
- Code areas inspected:
  - [BridgeImportReviewView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift)
  - [LocalBridgeSyncView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift)
  - [BridgeImportReviewModels.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge/BridgeImportReviewModels.swift)
  - [LocalBridgeImportValidationService.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift)
  - [LocalBridgeSyncController.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeSyncController.swift)
- Freshness decision:
  - [freshness-check.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r5/logs/freshness-check.log) shows only the proposal changed in the scoped files, so `R4` runtime evidence remains fresh enough for a repeat review.
- Remaining blockers:
  - No fresh `LocalBridgeSyncView` / import-review screenshots
  - Screenshot harness still fails before capture
  - Host GUI fallback still blocked

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `Medium`
- Release blockers:
  - The new draft fixes most of the `R4` proposal/runtime drift, but the current-baseline review contract still invents fields and actions that the shipped review destination does not expose.
  - The new current-baseline `ImportReviewSummary` example and acceptance wording still overstate how readable current generic diff rows are for allocations, transactions, and monthly plans.
- Top risks:
  1. The proposal can still drive the wrong operator-review tests because it compresses live `Reject` / `Dismiss Review` / `Reset to Pending` semantics into a simpler `Apply` / `Cancel` model and still mentions `snapshotID` as baseline review content.
  2. The proposal now labels its JSON example as current implemented behavior, but the example is still more human-friendly than the runtime's actual generic summaries.
  3. Evidence completeness remains partial, so visual confirmation of the updated bridge surface is still missing.
- Top opportunities:
  1. The `R4` issues around manifest shape, envelope shape, and checkpoint overstatement are materially closed in this draft.
  2. Remaining issues are now concentrated in operator-review semantics, not in the core snapshot schema.
  3. A small bridge-specific UI test expansion would let the next round graduate out of Evidence Gap Review mode.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | Amber | Medium | Partial | 0 | 0 | 1 | 0 |
| UX | Amber | Medium | Partial | 0 | 1 | 1 | 0 |
| iOS Architecture | Green | Medium | Partial | 0 | 0 | 0 | 0 |

## 3. Findings by Discipline

### 3.1 UI Findings
- Finding ID: `F-UI-01`
  Severity: `Medium`
  Evidence IDs: `DOC-02`, `CODE-02`, `CODE-03`, `CODE-04`
  Why it matters:
  The proposal's current implemented baseline still says the live review flow supports explicit `Apply` and `Cancel`, but the shipped surface is more specific: the review destination exposes `Approve & Apply`, `Reject`, and `Reset to Pending`, while `Dismiss Review` lives in the parent bridge flow and preserves the package for later reopen. That is not the same contract.
  Recommended fix:
  Rewrite the baseline in current-runtime terms: `Approve & Apply`, `Reject`, and parent-level `Dismiss Review` / reopen semantics. Only use `Cancel` if the product intentionally collapses those states.
  Acceptance criteria:
  The proposal's current-baseline action model matches the shipped button set and post-action behavior exactly.
  Confidence:
  `High`

### 3.2 UX Findings
- Finding ID: `F-UX-01`
  Severity: `High`
  Evidence IDs: `DOC-02`, `CODE-01`, `CODE-02`
  Why it matters:
  The current implemented baseline still lists `snapshotID` as part of the shipped operator contract, but the shipped generic DTO and visible review destination do not expose `snapshotID`; the operator sees `Package ID` instead. That keeps the proposal slightly ahead of the real review metadata even after the draft intentionally switched to the generic DTO baseline.
  Recommended fix:
  Either remove `snapshotID` from the current shipped baseline, or point to the specific current UI surface where `snapshotID` is actually exposed.
  Acceptance criteria:
  Every field named under the "current implemented baseline" is present in the actual shipped review DTO or visible review destination.
  Confidence:
  `High`

- Finding ID: `F-UX-02`
  Severity: `Medium`
  Evidence IDs: `DOC-03`, `DOC-04`, `CODE-05`, `CODE-06`
  Why it matters:
  The new draft correctly demotes richer typed diffs to future hardening, but its new "current implemented operator-facing summary" example and acceptance wording still overhumanize the shipped generic diff rows. The runtime still uses UUID-heavy transaction/allocation/monthly-plan summaries and does not expose the friendlier allocation or monthly-plan wording the example implies. That means the proposal can still overstate current operator explainability.
  Recommended fix:
  Make the baseline example match current emitted strings more closely, or explicitly label the friendlier wording as illustrative target UX rather than current runtime output. The same applies to the acceptance wording around allocation explainability.
  Acceptance criteria:
  The current-baseline JSON example and acceptance matrix do not promise more human-readable current diff rows than the runtime actually emits today.
  Confidence:
  `Medium`

### 3.3 iOS Architecture Findings
- No new material architecture findings in this round.
  Evidence IDs: `DOC-01`, `FRESH-01`
  Why it matters:
  The `R4` architecture/documentation mismatches around schema shape and reconciliation-checkpoint overstatement are substantially resolved in the current draft.
  Recommended fix:
  Preserve the new baseline-versus-hardening split while cleaning up the remaining operator-review wording.
  Acceptance criteria:
  Future proposal edits should not regress the manifest/envelope alignment or the softened current-baseline CloudKit safety framing.
  Confidence:
  `Medium`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict:
  The draft now tries to be honest about shipped baseline while still hinting at the desired nicer operator-review contract.
- Tradeoff:
  That honesty closes the big `R4` architecture gaps, but small overhumanized examples still make the shipped baseline look cleaner than it is.
- Decision:
  Keep the baseline/target split, but make the baseline brutally literal wherever the document says "current implemented".
- Owner:
  Proposal author + iOS bridge owner

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P1 | Fix the current-baseline review action semantics so they match `Approve & Apply`, `Reject`, `Reset to Pending`, and parent-level dismiss/reopen behavior | UI / UX | Proposal author | Now | None | No proposal text still compresses the shipped action model into `Apply` / `Cancel` | `F-UI-01` |
| P1 | Remove or substantiate `snapshotID` as a current shipped review field | UX | Proposal author | Now | None | Every named current-baseline field is visible in the shipped DTO/UI | `F-UX-01` |
| P2 | Make the "current implemented" JSON example and acceptance wording match the real generic diff readability, or explicitly mark friendlier text as target-state illustration | UX | Proposal author + iOS | Next | P1 baseline cleanup | The current-baseline example no longer implies display names/financial phrasing the runtime does not emit | `F-UX-02` |
| P2 | Extend bridge UI coverage so the next round can capture `LocalBridgeSyncView` and import-review states directly | UI / QA | iOS | Next | Screenshot harness repair or new UI test | Full-review screenshot gate becomes completable | Evidence gaps |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Review metadata contract | Whether every field named as current baseline is visible in the shipped DTO/UI | Field-by-field mapping between proposal bullets, JSON example, and review view | No "current implemented" field without a code/UI home | Before the next proposal approval | Hold if `snapshotID` or similar fields remain baseline-only fiction |
| Review action semantics | Whether `Reject`, `Dismiss`, `Reset`, and `Apply` are described distinctly | Updated proposal bullets and action tables | Do not collapse semantically different actions into `Cancel` | Before the next bridge UX signoff | Hold if the proposal still misstates current actions |
| Diff readability | Whether the current-baseline example matches the real generic diff wording | Example JSON and acceptance-copy review against live generator strings | Avoid friendly names/fields the runtime does not actually emit | Before the next repeat review | Hold if the example remains ahead of code |
| Visual evidence | Whether bridge destination and non-happy paths are captured in simulator | Passing screenshot harness or new bridge UI tests | Minimum gate still requires primary and non-happy screenshots | Before claiming a complete full review | Hold if screenshot coverage remains partial |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- GAP-01: The repeat review still reuses `R4` runtime evidence because no fresh bridge-destination screenshots were captured in `R5`.
- GAP-02: [presentation-screenshot-uitest.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r4/logs/presentation-screenshot-uitest.log) still shows the screenshot harness failing before capture.
- GAP-03: There is still no bridge-specific UI test that opens `LocalBridgeSyncView` and exercises import-review edge states.

### Open Questions
- QUESTION-01: Do you want the product contract to preserve distinct `Reject`, `Dismiss Review`, and `Reset to Pending` actions, or is the long-term goal a simpler `Cancel` model?
- QUESTION-02: Is a lightly humanized example acceptable inside a "current implemented" section, or should that section stay exact to the emitted runtime strings?

## Evidence Gap Review Fallback
- What was attempted:
  - Re-read the current proposal draft and diffed it against the previously reviewed version.
  - Freshness-checked the bridge code and confirmed only the proposal changed in the scoped files.
  - Reused the still-fresh `R4` build/run/simulator evidence for the unchanged bridge runtime.
  - Re-checked the relevant review DTO, review view, diff generator, and controller semantics against the updated draft.
- What is missing:
  - Fresh simulator screenshots of `LocalBridgeSyncView`
  - Fresh simulator screenshots of `Import Review` and important blocked/rejected states
  - Bridge-specific UI automation that reaches those states directly
- Blockers:
  - The repo's screenshot UITest still fails before capture.
  - Host GUI fallback still lacks Assistive Access.
  - No existing UI test drives the bridge destination itself.
- Confidence:
  - `Medium` on the findings above because they are anchored to proposal text + unchanged code
  - `Low` on any claim that would require new visual confirmation of the updated bridge surfaces
- What can still be said with partial confidence:
  - Most `R4` proposal/runtime drift is fixed in the new draft.
  - Remaining mismatches are concentrated in current-baseline operator-review wording, not in core bridge schema or CloudKit framing.
  - The current draft is closer to repo reality, but it still slightly overstates shipped review metadata/actions and diff readability.
- What evidence is required to finish the full review:
  - Repair the screenshot harness or add a dedicated bridge UI test
  - Capture fresh simulator evidence for `LocalBridgeSyncView`, `Import Review`, and at least one non-happy path
