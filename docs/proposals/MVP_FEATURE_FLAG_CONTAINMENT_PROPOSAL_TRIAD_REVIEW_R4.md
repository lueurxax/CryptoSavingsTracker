# Consolidated Review

## 0. Review Mode and Proposal Evidence Summary
- Mode used: `proposal-readiness`
- Evidence completeness: `Complete`
- Proposal / docs reviewed:
  - [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md)
  - [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R3.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R3.md)
  - [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R3.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R3.md)
  - [current-system-baseline.md](/Users/user/Documents/CryptoSavingsTracker/.review-baselines/current-system-baseline.md)
- Reusable baseline used:
  - [current-system-baseline.md](/Users/user/Documents/CryptoSavingsTracker/.review-baselines/current-system-baseline.md)
- Baseline reused:
  - Apple public MVP contract
  - Retained goal-dashboard boundary
  - Diagnostics boundary
- Baseline refreshed:
  - No broad baseline refresh required
  - Targeted re-check only against the new source-based containment tests
- Baseline freshness: `Fresh`
- Proposal-specific integration context:
  - None
- Targeted context refresh performed:
  - [GoalDashboardContract.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Models/GoalDashboardContract.swift)
  - [GoalDashboardLegacyWidgetMigration.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/GoalDashboardLegacyWidgetMigration.swift)
  - [GoalDashboardSceneAssembler.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift)
  - [SettingsView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift)
  - [GoalDashboardScreen.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift)
  - [MVPContainmentContractTests.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift)
- External research used: `None`
- Research pack:
  - None
- Sources reused:
  - Proposal, baseline, `R3` review, `R3` evidence pack
- Sources refreshed:
  - Retained-dashboard implementation seams
  - Diagnostics boundary validation seam
- Time-sensitive external guidance:
  - None
- Code areas inspected:
  - Retained goal-dashboard CTA sources
  - Settings/About retained surface
  - Source-based containment tests
- Current repo contradictions found:
  - The proposal is now semantically aligned with repo reality on dashboard containment and diagnostics placement.
  - One exact-string mismatch remains between proposal wording and the new diagnostics containment test.
- Runtime evidence used: `None`
- Provenance of key evidence:
  - Proposal + baseline for intended contract
  - Current source files and tests for repo reality
- Remaining assumptions:
  - Diagnostics should remain dashboard-local in the first Apple MVP.
- Remaining blockers:
  - The diagnostics boundary sentence in the proposal does not match the exact literal substring asserted by the current containment test.

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `High`
- Proposal completeness signal: `Strong`
- Top risks:
  1. The only remaining drift is now a validation seam: one source-based containment test expects a canonical diagnostics phrase that the proposal does not literally contain.
  2. If left unresolved, this can create a false negative release gate even though the product contract is otherwise coherent.
  3. Because the larger `R3` gaps are closed, this smaller issue is easy to miss.
- Top opportunities:
  1. The retained-dashboard containment gap is materially closed in both proposal and source.
  2. Diagnostics placement is now explicit in the proposal and baseline.
  3. One small wording or test fix can likely move this proposal to `Green`.

## 2. Proposal Scope and Completeness
- In scope:
  - Post-`R3` retained-dashboard and diagnostics changes
  - Proposal/baseline/source alignment for the affected slices
  - Source-based containment validation introduced after `R3`
- Out of scope:
  - Runtime simulator validation
  - Android scope
  - Full implementation audit
- Deferred intentionally:
  - General dead-code cleanup outside the reviewed slices
- Most important baseline refreshes performed:
  - Verified that the diagnostics boundary and retained-dashboard boundary are now reflected in the reusable baseline
- Most important contradictions with current repo:
  - Only one exact-string diagnostics contract mismatch remains
- Most important missing or partial states:
  - None on the retained-dashboard product contract
  - One partial state remains in validation wording

## 3. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | Green | High | Complete | 0 | 0 | 0 | 0 |
| UX | Green | High | Complete | 0 | 0 | 0 | 0 |
| iOS Architecture | Amber | High | Complete | 0 | 0 | 1 | 0 |

## 4. Findings by Discipline

### 4.1 iOS Architecture Findings
- Finding ID: `F-ARCH-01`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `DOC-03`, `NAV-03`, `MAP-04`, `MAP-05`, `REAL-02`
  Why it matters:
  The proposal is now directionally correct on diagnostics placement, but the validation contract is not fully aligned with the actual text that ships in the repo. [MVPContainmentContractTests.swift:172](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift#L172) asserts that the proposal source must contain the exact substring `Public diagnostics remains goal-dashboard-local`, while [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:76](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L76) currently says `Diagnostics remains goal-dashboard-local through the retained hard-error diagnostics flow`. The user-facing intent is the same, and the repo UI and baseline both align on dashboard-local diagnostics, but the literal mismatch is enough to make the source-based containment test fail. That leaves the proposal operationally almost ready, but not fully self-consistent with its own validation layer.
  Recommended fix:
  Align the proposal and the source-based test on one canonical diagnostics sentence. Either:
  1. add the exact canonical phrase the test already asserts to the proposal, ideally in a short dedicated diagnostics boundary line, or
  2. relax the test so it validates the diagnostics rule semantically instead of requiring one exact source substring.
  Acceptance criteria:
  The proposal, reusable baseline, and containment test all agree on one canonical diagnostics contract, and the source-based diagnostics validation passes without relying on ad hoc wording tweaks.
  Confidence:
  `High`

## 5. Cross-Discipline Conflicts and Decisions
- Conflict:
  The proposal is now semantically clean, but one validation test treats a specific wording variant as canonical.
- Tradeoff:
  Exact-string validation is simple and cheap, but brittle when the proposal wording evolves without changing product meaning.
- Decision:
  Keep the dashboard-local diagnostics rule, but make the validation contract deterministic by aligning wording or loosening the test.
- Owner:
  Proposal author + Apple containment owner

## 6. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P1 | Align the proposal diagnostics sentence with the current containment test, or update the test to semantic matching | iOS Architecture | Proposal author + Apple owner | Now | None | Proposal-source diagnostics validation passes cleanly | `F-ARCH-01` |
| P2 | Rerun repeat review after the diagnostics validation seam is closed | iOS Architecture | Reviewer | Next | P1 | Proposal can be signed off without residual contract drift | `F-ARCH-01` |

## 7. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Retained-dashboard containment | Whether planner/history CTA leakage is absent from retained public sources | Contract, scene assembly, migration, and tests all use `review_activity` | Do not reopen hidden CTA IDs in public Apple mode | Next repeat review | Hold if `view_history` reappears in retained public sources |
| Diagnostics contract validation | Whether proposal, baseline, and tests agree on one diagnostics rule | Source-based test passes against the checked-in proposal text | Do not keep a brittle failing literal assertion in the release gate | Next repeat review | Hold if proposal/test wording still diverges |

## 8. Evidence Gaps and Open Questions

### Evidence Gaps
- GAP-01: This round remained doc/code-based and did not run simulator validation, which was not required for proposal readiness.

### Open Questions
- QUESTION-01: Should the proposal carry one explicit canonical diagnostics sentence for validation tooling, or should the test stop coupling to literal prose?

## Appendix A. Evidence Pack
- [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R4.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R4.md)
