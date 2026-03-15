# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed:
  - `/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md`
  - `/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/CLOUDKIT_QR_MULTIPEER_SYNC_PROPOSAL_TRIAD_REVIEW_R2.md`
  - `/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/CLOUDKIT_MIGRATION_PLAN.md`
  - `/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift`
  - `/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift`
  - `/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/ContentView.swift`
- Internet sources reviewed:
  - Apple `CKSyncEngine` documentation and WWDC23 sync guidance
  - Apple local network privacy guidance
  - Apple camera usage-description requirements
- Xcode screenshots captured:
  - `/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r3/settings-surface-current.png`
  - `/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r3/macos-main-surface-current.png`
- Remaining assumptions:
  - The bridge still targets the existing macOS target in this repo.
  - The proposal remains a future-state document; runtime CloudKit is still not enabled today.

## 1. Executive Summary
- Overall readiness: `Green`
- Top 3 risks:
  1. `ImportReviewSummary` still does not fully match the stronger review contract because transactions and monthly plans are still represented as summaries rather than concrete diffs.
  2. `Phase 2B` wording about “richer financial diff presentation” can be misread as postponing part of the minimum review contract unless `Phase 2A` is made explicit enough.
  3. No additional material UI or architecture gaps remain at proposal level.
- Top 3 opportunities:
  1. The `R2` gaps around `allocationDiffs` and manifest version semantics are now closed.
  2. Fresh Xcode Preview evidence now renders again, so the review no longer depends on blocked visual validation.
  3. The remaining issue is narrow and easy to close before implementation.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 9 | 0 | 0 | 0 | 0 |
| UX (Financial) | 8 | 0 | 0 | 1 | 0 |
| iOS Architecture | 9 | 0 | 0 | 0 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- No material UI findings.
  - Evidence:
    - `DOC-01`: [cloudkit_qr_multipeer_sync_proposal.md:102](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L102)
    - `SCR-01`: [settings-surface-current.png](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r3/settings-surface-current.png)
    - `SCR-02`: [macos-main-surface-current.png](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r3/macos-main-surface-current.png)
  - Why it matters:
    - The document keeps bridge operations inside a dedicated destination rather than trying to overload the existing Settings surface. That remains the correct direction for a high-trust workflow.
  - Recommended fix:
    - None required at proposal level.
  - Acceptance criteria:
    - Preserve the dedicated bridge destination model in implementation and do not collapse pairing or import review back into inline Settings rows.

### 3.2 UX Review Findings
- [Medium] `ImportReviewSummary` is still internally inconsistent with the review contract for transactions and monthly plans.
  - Evidence:
    - `DOC-02`: [cloudkit_qr_multipeer_sync_proposal.md:149](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L149)
    - `DOC-03`: [cloudkit_qr_multipeer_sync_proposal.md:392](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L392)
    - `DOC-04`: [cloudkit_qr_multipeer_sync_proposal.md:428](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L428)
    - `DOC-05`: [cloudkit_qr_multipeer_sync_proposal.md:437](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L437)
    - `DOC-06`: [cloudkit_qr_multipeer_sync_proposal.md:664](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L664)
  - Why it matters:
    - The proposal now clearly says `Import Review` must show concrete money-impacting diffs for changed goals, transactions, allocations, and monthly plans, and the acceptance matrix repeats that expectation. But the actual `ImportReviewSummary` schema still gives concrete diffs only for goals and allocations. Transactions are still collapsed into `transactionDeltaSummary`, and monthly plans into `monthlyPlanReplacementSummary`. For a finance workflow, that means the operator contract is still stronger than the machine-readable review payload.
  - Recommended fix:
    - Align the schema with the contract in one of two ways:
      - preferred: add explicit `transactionDiffs` and `monthlyPlanDiffs` sections with concrete before/after values and delete markers where relevant;
      - fallback: if summaries are intentional, weaken both the review-boundary language and the acceptance criteria so the document stops overpromising.
    - Also make `Phase 2A` versus `Phase 2B` wording explicit so “richer financial diff presentation” does not read like deferring minimum trust requirements.
  - Acceptance criteria:
    - `ImportReviewSummary` and the test matrix express the same operator-visible contract.
    - For each money-impacting category named in the review boundary, the document either defines concrete diff payloads or intentionally limits the requirement to summary-level review.

### 3.3 Architecture Review Findings
- No material architecture findings.
  - Evidence:
    - `DOC-07`: [cloudkit_qr_multipeer_sync_proposal.md:264](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L264)
    - `DOC-08`: [cloudkit_qr_multipeer_sync_proposal.md:321](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L321)
    - `DOC-09`: [cloudkit_qr_multipeer_sync_proposal.md:650](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L650)
  - Why it matters:
    - The previous ambiguity around manifest version semantics is now resolved, and the protocol/validation contracts are materially implementation-ready.
  - Recommended fix:
    - None required at proposal level beyond keeping the review schema aligned with the operator contract.
  - Acceptance criteria:
    - Maintain the current separation between compatibility-gating fields and diagnostic metadata during implementation.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict:
  - Compact review summary vs finance-grade operator confidence.
  - Tradeoff:
    - Aggregate summaries are easier to scan, but they are weaker than concrete diffs for high-trust import approval.
  - Decision:
    - Keep the review focused, but do not promise concrete diffs in prose unless the schema and acceptance criteria actually provide them.
  - Owner:
    - Product design + iOS/macOS implementation leads

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P1 | Align `ImportReviewSummary` with the stated transaction/monthly-plan review contract | UX | Product design | Now | Existing review-boundary language | Review schema, prose, and tests all say the same thing |

## 6. Execution Plan
- Now (0-2 weeks):
  - Decide whether `Import Review` truly requires concrete transaction and monthly-plan diffs, or only summary-level visibility.
  - Update `ImportReviewSummary`, `Phase 2B`, and the acceptance matrix so they no longer contradict each other.
- Next (2-6 weeks):
  - Carry the clarified diff contract into implementation artifacts and UI specs.
- Later (6+ weeks):
  - None proposal-critical.

## 7. Open Questions
- Do you want finance-grade `Import Review` to show per-transaction and per-monthly-plan concrete diffs, or is summary-level review sufficient for those two categories?

## Appendix A. Evidence Pack

### A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Product Surface | Bridge work remains inside a dedicated destination rather than inline Settings rows | UI hierarchy remains sound |
| DOC-02 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | iPhone Import Review Boundary | Review boundary promises concrete diffs for goals, transactions, allocations, and monthly plans | Operator contract is explicit |
| DOC-03 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | ImportReviewSummary | Review payload includes concrete `goalDiffs` and `allocationDiffs` | Part of `R2` is closed |
| DOC-04 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | ImportReviewSummary | Transactions are still represented as `transactionDeltaSummary` | Remaining mismatch |
| DOC-05 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | ImportReviewSummary | Monthly plans are still represented as `monthlyPlanReplacementSummary` | Remaining mismatch |
| DOC-06 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Phase 2 Test Matrix | Acceptance criteria still require concrete money-impacting diffs | Confirms the mismatch is not only editorial |
| DOC-07 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Protocol Evolution Policy | `appModelSchemaVersion` is now clearly non-negotiation metadata | Previous architecture issue is closed |
| DOC-08 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | SnapshotManifest | Manifest version-field semantics are now explicit | Previous architecture issue is closed |
| DOC-09 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Acceptance Criteria | Version semantics and diff expectations are now testable at document level | Proposal is near implementation-ready |

### B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | `https://developer.apple.com/documentation/CloudKit/CKSyncEngine-5sie5` and `https://developer.apple.com/videos/play/wwdc2023/10188/` | Accessed 2026-03-15 / WWDC23 | Foreground reconciliation checkpoints remain the right architectural basis around CloudKit | Confirms no regression in the sync model |
| WEB-02 | `https://developer.apple.com/la/videos/play/wwdc2020/10110/` | WWDC20 | Local network discovery still requires explicit privacy declarations | Confirms the proposal’s foreground-only bridge stance |
| WEB-03 | `https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html` and `https://developer.apple.com/library/archive/qa/qa1937/_index.html` | Accessed 2026-03-15 | Camera use still requires explicit usage-description handling and fallback thinking | Confirms pairing requirements remain correct |

### C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r3/settings-surface-current.png` | Current Settings entry surface | Existing pre-bridge state | Xcode Preview, current app | Fresh visual evidence that the live Settings surface still has no bridge UI and that the proposal remains future-state |
| SCR-02 | `docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r3/macos-main-surface-current.png` | Current macOS main surface | Existing shared macOS app state | Xcode Preview, current app | Fresh visual evidence that the bridge still belongs inside the existing macOS app surface |

### D. Assumptions and Open Questions
- ASSUMP-01: The bridge still targets the existing macOS target in this repo.
- ASSUMP-02: `Phase 2B` wording is intended as an enhancement over the minimum `Phase 2A` trust contract, not a postponement of required review visibility.
- QUESTION-01: Should the proposal define explicit `transactionDiffs` and `monthlyPlanDiffs`, or intentionally downgrade those categories to summary-level review?
