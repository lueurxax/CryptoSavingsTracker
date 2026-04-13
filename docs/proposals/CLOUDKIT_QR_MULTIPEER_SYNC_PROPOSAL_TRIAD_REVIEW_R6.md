# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `full-review` with fresh `R6` iPhone runtime evidence because the scoped bridge code changed after `R5`.
- Evidence completeness: `Partial`
- Documents / repo inputs reviewed:
  - [cloudkit_qr_multipeer_sync_proposal.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md)
  - [CLOUDKIT_QR_MULTIPEER_SYNC_PROPOSAL_EVIDENCE_PACK_R6.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/CLOUDKIT_QR_MULTIPEER_SYNC_PROPOSAL_EVIDENCE_PACK_R6.md)
  - [proposal-diff.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r6/logs/proposal-diff.log)
- External sources reviewed:
  - None required
- Build/run attempts:
  - Fresh `R6` app build via [build.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r6/logs/build.log)
  - Fresh targeted bridge UI run via [local-bridge-uitests.log](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r6/logs/local-bridge-uitests.log)
- Screenshots captured:
  - Fresh simulator still for pairing-required state: [pairing_required_local_bridge.png](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r6/screenshots/pairing_required_local_bridge.png)
  - Fresh simulator still for review-ready state: [review_ready_import_review.png](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/cloudkit-qr-multipeer-sync-r6/screenshots/review_ready_import_review.png)
- Code areas inspected:
  - [LocalBridgeSyncView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift)
  - [BridgeImportReviewView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift)
  - [LocalBridgeModels.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeModels.swift)
  - [LocalBridgeImportValidationService.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/Bridge/LocalBridgeImportValidationService.swift)
  - [LocalBridgeSyncUITests.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift)
- Remaining assumptions:
  - The current review is scoped to the iPhone bridge flow and proposal/runtime alignment for the recently edited areas.
  - The updated `ImportReviewSummary` section is meant to describe current shipped baseline behavior.
- Remaining blockers:
  - No fresh macOS runtime evidence for the transient workspace path in this round
  - The dedicated bridge UI suite is currently red on 2 of 3 seeded scenarios

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `Medium`
- Release blockers:
  - The proposal is materially closer to the shipped bridge baseline than `R5`, but it still carries one stale summary-row label and one stale post-validation contract.
  - The strongest trust-critical claim in the doc still says the operator sees concrete review evidence before mutation, while the shipped review UI keeps approval controls above the diff section.
  - Fresh regression coverage for the changed bridge baseline is unstable: 2 of 3 dedicated `LocalBridgeSyncUITests` scenarios are currently failing.
- Top risks:
  1. Proposal wording can still drive the wrong Settings-row copy and accessibility assertions because it uses `Review Required` where the current pending-action string is `Review Import`.
  2. The review contract still overstates how safely the operator is forced through diff evidence before approval.
  3. Current baseline claims are only partially protected by automation after the latest changes.
- Top opportunities:
  1. The major `R5` drift around `packageID`, `entityDeltas` / `concreteDiffs`, and softened CloudKit reconciliation language is now materially closed.
  2. The remaining issues are narrow and mostly concentrated in operator-facing wording and review presentation order.
  3. Fixing the red bridge UI tests would make the next repeat review much cheaper and more defensible.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | Amber | High | Partial | 0 | 0 | 1 | 0 |
| UX | Amber | High | Partial | 0 | 1 | 1 | 0 |
| iOS Architecture | Amber | Medium | Partial | 0 | 0 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Findings
- Finding ID: `F-UI-01`
  Severity: `Medium`
  Evidence IDs: `DOC-02`, `CODE-01`, `TEST-01`, `SCR-01`
  Why it matters:
  The proposal's top-level Settings-row section still describes the pending action as `Review Required`, but the shipped pending-action value is `Review Import`. `Review Required` belongs to availability state, not pending action. That keeps the document one label behind the live accessibility/value contract and makes regression back to the wrong copy more likely.
  Recommended fix:
  Change the summary-row pending-action example to `Review Import`, or explicitly separate availability-state wording from pending-action wording in that section.
  Acceptance criteria:
  No proposal text describes `Review Required` as the pending-action string when the current runtime exposes `Review Import`.
  Confidence:
  `High`

### 3.2 UX Findings
- Finding ID: `F-UX-01`
  Severity: `High`
  Evidence IDs: `DOC-03`, `DOC-06`, `CODE-02`, `SCR-02`
  Why it matters:
  The proposal says `Import Review` shows concrete diff evidence before mutation and that the operator can explain what will change before committing apply, but the shipped review layout still places `Approve & Apply to CloudKit`, `Reject`, and `Reset to Pending` above `Concrete Diffs`. In a finance-grade review step, that weakens the proposed trust boundary because the destructive CTA is reachable before the detailed evidence section.
  Recommended fix:
  Either move `Concrete Diffs` above `Operator Actions` in the shipped view, or weaken the proposal's current-baseline wording so it no longer implies a stronger review fence than the current layout provides.
  Acceptance criteria:
  Either the review UI presents diff evidence before the approval controls, or the proposal explicitly describes the current order and reserves a stricter review fence for target-state hardening.
  Confidence:
  `High`

- Finding ID: `F-UX-02`
  Severity: `Medium`
  Evidence IDs: `DOC-05`, `CODE-03`
  Why it matters:
  The proposal still defines `ImportValidationResult` as an operator-visible `snapshotID` / `status` / `reason` payload, but the actual `LocalBridgeSyncView` surface shows drift status, operator decision, summary text, warnings, and changed-entity counts. That leaves a stale operator contract inside a draft that otherwise now tries to be literal about the shipped baseline.
  Recommended fix:
  Rewrite `ImportValidationResult` to match the visible bridge surface, or explicitly mark that JSON block as a future/internal schema rather than current operator-facing UI.
  Acceptance criteria:
  The `ImportValidationResult` section unambiguously maps to the actual operator-visible bridge surface or is clearly marked out of the current UI baseline.
  Confidence:
  `High`

### 3.3 iOS Architecture Findings
- Finding ID: `F-ARCH-01`
  Severity: `Medium`
  Evidence IDs: `RUN-02`, `RUN-03`, `TEST-01`
  Why it matters:
  The proposal now leans on a "current implemented baseline" for bridge behavior, but the dedicated bridge regression suite is currently unstable after the recent changes: 2 of the 3 seeded `LocalBridgeSyncUITests` scenarios failed in `R6`. That does not invalidate the fresh screenshots, but it does mean the exact baseline states called out by the proposal are only partially defended by automation.
  Recommended fix:
  Repair the current bridge UI tests for `pairing_required` and `review_ready`, then keep the proposal's baseline language tied to those stable assertions.
  Acceptance criteria:
  [LocalBridgeSyncUITests.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/LocalBridgeSyncUITests.swift) passes all three seeded bridge scenarios on the documented simulator target.
  Confidence:
  `High`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict:
  The draft is trying to be honest about the shipped generic bridge baseline while still preserving a stronger trust-oriented review story.
  Tradeoff:
  That closes most of the old schema/runtime drift, but the remaining stale labels and review-order wording still make the current operator experience look slightly more settled and safer than it is.
  Decision:
  Keep the new baseline-versus-hardening split, but make every "current implemented" clause brutally literal and avoid stronger review guarantees until the UI and tests actually enforce them.
  Owner:
  Proposal author + iOS bridge owner

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P1 | Fix the summary-row terminology so pending action uses `Review Import` and availability keeps `Review Required` only where appropriate | UI | Proposal author | Now | None | No proposal row/state example mislabels the shipped pending action | `F-UI-01` |
| P1 | Align the current review-boundary claim with the shipped layout, either by moving `Concrete Diffs` above the approval CTA or by weakening the current-baseline wording | UX / UI | iOS bridge owner + proposal author | Now | None | Review evidence and proposal wording agree on whether the operator reaches diffs before approval | `F-UX-01` |
| P1 | Repair `LocalBridgeSyncUITests` for `pairing_required` and `review_ready` so the current baseline is regression-defended again | iOS Architecture / QA | iOS | Now | None | All three seeded bridge UI tests pass on iPhone 15 iOS 18.0 | `F-ARCH-01` |
| P2 | Rewrite or re-scope `ImportValidationResult` so it no longer describes a stale operator-facing contract | UX | Proposal author | Next | P1 baseline cleanup | The validation-result section maps cleanly to current UI or is clearly labeled future/internal | `F-UX-02` |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Summary-row terminology | Whether proposal wording matches the shipped Settings-row value contract | Proposal text diff against `LocalBridgePendingAction.displayTitle` and UI-test assertions | Do not reuse availability labels as pending-action labels | Before the next repeat review | Hold if `Review Required` still appears as a pending action example |
| Import-review boundary | Whether the operator sees and can inspect diff evidence before approval semantics are claimed | View hierarchy order, screenshots, and acceptance wording | Do not claim a stronger review fence than the current UI actually enforces | Before the next proposal signoff | Hold if proposal still says "before mutation" while actions remain above diffs |
| Validation-result contract | Whether the post-validation section maps to the actual operator-visible surface | Field-by-field comparison between proposal block and `LocalBridgeSyncView` | No operator-visible JSON contract without a real UI home | Before the next bridge docs refresh | Hold if `snapshotID` / `status` / `reason` remains presented as current UI |
| Regression stability | Whether seeded bridge states remain reproducible and green in automation | `LocalBridgeSyncUITests` pass rate and preserved xcresult attachments | No proposal should lean on "current implemented" baseline if the dedicated coverage is red | Before claiming the bridge baseline is stable | Hold if the bridge UI suite still fails on seeded current states |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- GAP-01: `R6` still has no fresh macOS runtime evidence for the transient workspace and export surface, so the review remains strongest on the iPhone slice.
- GAP-02: The fresh iPhone evidence is good enough for a full review, but current baseline automation is still red on 2 of 3 bridge scenarios.

### Open Questions
- QUESTION-01: Is [cloudkit_qr_multipeer_sync_proposal.md:511](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L511) supposed to remain operator-facing, or should it move to an internal/result-schema appendix?
- QUESTION-02: Does product want the stronger trust guarantee that diff evidence must appear above the approval CTA, or is "same review surface, lower in the scroll" sufficient for Phase 2A?
