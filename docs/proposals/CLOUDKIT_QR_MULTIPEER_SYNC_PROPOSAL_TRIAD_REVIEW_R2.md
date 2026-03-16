# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed:
  - `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md`
  - `docs/proposals/CLOUDKIT_QR_MULTIPEER_SYNC_PROPOSAL_TRIAD_REVIEW_R1.md`
  - `docs/CLOUDKIT_MIGRATION_PLAN.md`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift`
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift`
  - `ios/CryptoSavingsTracker/Views/ContentView.swift`
- Internet sources reviewed:
  - Apple `CKSyncEngine` documentation and WWDC23 sync guidance
  - Apple local network privacy guidance
  - Apple camera usage-description requirements
- Xcode screenshots captured:
  - Reused current-surface artifacts:
    - `docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r1/settings-surface-current.png`
    - `docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r1/macos-main-surface-current.png`
  - Fresh recapture attempt was blocked by an unrelated macOS compile error in `CompactGoalRequirementRow.swift`, so no new visual findings were derived from that failure.
- Remaining assumptions:
  - The bridge still targets the existing macOS target in this repo.
  - The proposal remains a future-state document; runtime CloudKit is still not enabled today.

## 1. Executive Summary
- Overall readiness: `Green`
- Top 3 risks:
  1. `ImportReviewSummary` still does not fully match the stronger review boundary because it omits concrete allocation diffs.
  2. `SnapshotManifest` still carries two version fields with unclear separation of meaning.
  3. Fresh Xcode Preview validation is currently blocked by an unrelated macOS compile break, which is outside this proposal but reduces visual verification fidelity.
- Top 3 opportunities:
  1. The main architecture issues from `R1` are now closed.
  2. The bridge is now clearly scoped as a manual, foreground-only, no-second-sync-engine design.
  3. The canonical schema appendix and reconciliation gates are now strong enough to serve as implementation contracts.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 9 | 0 | 0 | 0 | 0 |
| UX (Financial) | 8 | 0 | 0 | 1 | 0 |
| iOS Architecture | 8 | 0 | 0 | 0 | 1 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- No material UI findings.
  - Evidence:
    - `DOC-01`: [cloudkit_qr_multipeer_sync_proposal.md:102](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L102)
    - `DOC-02`: [cloudkit_qr_multipeer_sync_proposal.md:149](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L149)
  - Why it matters:
    - The previous concerns about burying a high-trust workflow inside general Settings are now addressed. The document clearly moves bridge work into a dedicated drill-in surface and makes `Import Review` a blocking dedicated flow.
  - Recommended fix:
    - None required at proposal level.
  - Acceptance criteria:
    - Preserve the dedicated bridge destination model in implementation and do not collapse pairing/review back into inline Settings rows.

### 3.2 UX Review Findings
- [Medium] `ImportReviewSummary` still under-specifies allocation diffs even though the operator contract explicitly requires them.
  - Evidence:
    - `DOC-03`: [cloudkit_qr_multipeer_sync_proposal.md:149](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L149)
    - `DOC-04`: [cloudkit_qr_multipeer_sync_proposal.md:386](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L386)
  - Why it matters:
    - The proposal now promises “concrete money-impacting diffs for changed goals, transactions, allocations, and monthly plans,” but the example summary includes concrete goal diffs, transaction deltas, and monthly plan replacement summary only. For a finance operator, allocation changes are not secondary metadata; they can materially alter how funds are distributed across goals. Leaving them out weakens the trust contract of the review step.
  - Recommended fix:
    - Extend `ImportReviewSummary` with an explicit `allocationDiffs` section.
    - Minimum payload:
      - asset identifier or display name,
      - goal name,
      - amount before,
      - amount after,
      - optional percentage/share before and after when allocation meaning depends on ratio.
    - Add a matching Phase 2 test-matrix row proving allocation changes are visible before apply.
  - Acceptance criteria:
    - When allocations change, `Import Review` shows concrete before/after allocation deltas rather than counts alone.
    - An operator can explain how funds are being redistributed across goals before confirming apply.

### 3.3 Architecture Review Findings
- [Low] `SnapshotManifest` still contains both `snapshotSchemaVersion` and `schemaVersion` without explicit semantic separation.
  - Evidence:
    - `DOC-05`: [cloudkit_qr_multipeer_sync_proposal.md:320](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L320)
    - `DOC-06`: [cloudkit_qr_multipeer_sync_proposal.md:531](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L531)
  - Why it matters:
    - The protocol-evolution story is much better now, but two similarly named version fields invite divergent implementations unless one is explicitly defined as transport/schema compatibility state and the other as app-model revision metadata. This is low severity because it is easy to fix, but it should be clarified before implementation starts.
  - Recommended fix:
    - Either remove `schemaVersion` if it is redundant, or rename it to something explicit such as `appModelSchemaVersion`.
    - State which version fields participate in handshake compatibility negotiation and which are operator/debug metadata only.
  - Acceptance criteria:
    - Every version field in `SnapshotManifest` has one unambiguous meaning.
    - A reader can tell from the document alone which version fields gate compatibility and which do not.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict:
  - Rich operator clarity vs keeping the review summary compact.
  - Tradeoff:
    - A smaller summary is easier to scan, but savings-allocation edits are too consequential to hide behind aggregate counts.
  - Decision:
    - Keep the review focused, but require concrete before/after diffs for every money-impacting category, including allocations.
  - Owner:
    - Product design + iOS/macOS implementation leads

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P1 | Add `allocationDiffs` to `ImportReviewSummary` and test matrix | UX | Product design | Now | Existing review summary contract | Allocation edits are visible and understandable before apply |
| P2 | Clarify or rename `schemaVersion` vs `snapshotSchemaVersion` | Architecture | iOS/macOS tech leads | Now | Snapshot manifest contract | No ambiguity remains in version semantics |

## 6. Execution Plan
- Now (0-2 weeks):
  - Add explicit allocation diffs to the operator review contract.
  - Clean up manifest version-field naming.
- Next (2-6 weeks):
  - Preserve the dedicated bridge surface and review flow as implementation starts.
- Later (6+ weeks):
  - None proposal-critical beyond carrying these contracts into implementation artifacts and tests.

## 7. Open Questions
- Should `allocationDiffs` describe only absolute amount changes, or also share/percentage changes where that better reflects operator intent?
- Is `schemaVersion` intended to be app-model revision metadata, or is it redundant with `snapshotSchemaVersion`?

## Appendix A. Evidence Pack

### A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Product Surface | Settings is now only an entry point; bridge work moves into a dedicated surface | Previous UI hierarchy issue is closed |
| DOC-02 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | iPhone Import Review Boundary | Review is now blocking and dedicated | Previous inline-review concern is closed |
| DOC-03 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | iPhone Import Review Boundary | Operator contract explicitly requires concrete diffs for allocations too | Summary object should include them explicitly |
| DOC-04 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | ImportReviewSummary | Example summary omits explicit allocation diffs | Remaining UX gap |
| DOC-05 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | SnapshotManifest | `snapshotSchemaVersion` and `schemaVersion` both exist | Remaining version-contract ambiguity |
| DOC-06 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Import Validation | Compatibility validation is stronger now | Version fields still need clearer roles |
| DOC-07 | `docs/proposals/CLOUDKIT_QR_MULTIPEER_SYNC_PROPOSAL_TRIAD_REVIEW_R1.md` | Prior review | Main `R1` issues were CloudKit reconciliation, protocol negotiation, dedicated surface, and stronger review contract | Used as comparison baseline |
| DOC-08 | `docs/CLOUDKIT_MIGRATION_PLAN.md` | CloudKit readiness | Runtime CloudKit migration is still a prerequisite | Proposal remains future-state only |

### B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | `https://developer.apple.com/documentation/CloudKit/CKSyncEngine-5sie5` and `https://developer.apple.com/videos/play/wwdc2023/10188/` | Accessed 2026-03-15 / WWDC23 | `CKSyncEngine` sync timing remains system-managed; explicit foreground actions are still the right basis for reconciliation checkpoints | Confirms previously added checkpoint model remains sound |
| WEB-02 | `https://developer.apple.com/la/videos/play/wwdc2020/10110/` | WWDC20 | Local network discovery still requires explicit privacy contract | Confirms no regression in the proposal’s foreground-only bridge stance |
| WEB-03 | `https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html` and `https://developer.apple.com/library/archive/qa/qa1937/_index.html` | Accessed 2026-03-15 | Camera use still requires explicit usage-description handling | Confirms camera fallback requirements remain correct |

### C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r1/settings-surface-current.png` | Current Settings entry surface | Existing pre-bridge state | Xcode Preview, current app | Confirms current app still has no bridge UI and that dedicated future surface remains a proposal-only contract |
| SCR-02 | `docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r1/macos-main-surface-current.png` | Current macOS main surface | Existing shared macOS app state | Xcode Preview, current app | Confirms bridge scope still sits inside the existing macOS app surface |

### D. Assumptions and Open Questions
- ASSUMP-01: The compile failure in `CompactGoalRequirementRow.swift` is unrelated to this proposal and does not alter the review verdict.
- ASSUMP-02: The implementation will preserve the dedicated bridge surface and not collapse it back into inline Settings content.
- QUESTION-01: Should allocation review include percentages in addition to absolute amounts?
- QUESTION-02: Is `schemaVersion` needed once `snapshotSchemaVersion` and `canonicalEncodingVersion` are both present?
