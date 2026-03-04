# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed: 7 (`docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL_EVIDENCE_PACK_R4.md`)
- Internet sources reviewed: 7
- Xcode screenshots captured/revalidated: 4
- Scope lock: proposal-quality re-review (not implementation audit).

## 1. Executive Summary
- Overall readiness: **Amber-Green**
- Top remaining risks:
  1. CI parser implementation details are not yet bound to a specific tooling plan.
  2. Release sign-off workflow for metrics + rollback evidence is defined, but not yet operationalized in a runbook artifact.
  3. Compact-state policy is strong in text, but requires strict screenshot test enforcement to avoid drift.
- Top strengths:
  1. Proposal is now decision-complete for navigation/presentation policy.
  2. Trust-critical financial UX behavior (dirty-dismiss, recovery, no silent loss) is explicitly specified.
  3. Exit criteria to Green are measurable and practical.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 9 | 0 | 0 | 1 | 0 |
| UX (Financial) | 9 | 0 | 0 | 1 | 0 |
| iOS Architecture | 8 | 0 | 0 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [Medium] Compact overflow policy needs hard test gate linkage
  - Evidence: DOC-01, SCR-01, SCR-03
  - Why it matters: The policy is good, but without mandatory screenshot diff gate it can regress silently.
  - Recommended fix: Make compact `MOD-02` screenshot checks a required CI artifact for changed modal flows.
  - Acceptance criteria: PRs touching modal flows fail when compact screenshot artifacts are missing or regress.

### 3.2 UX Review Findings
- [Medium] Dirty-state matrix requires explicit “canonicalization” examples per flow
  - Evidence: DOC-02
  - Why it matters: Teams can interpret canonicalization inconsistently, leading to prompt inconsistency.
  - Recommended fix: Add one concrete canonicalization example for each form in the matrix.
  - Acceptance criteria: Form docs include baseline/edited/reverted examples and matching expected dirty-state transitions.

### 3.3 Architecture Review Findings
- [Medium] Parser/tooling implementation is still abstract
  - Evidence: DOC-04, QUESTION-01
  - Why it matters: CI reliability depends on exact parser behavior and fallback semantics.
  - Recommended fix: Add a short implementation ADR with tool choice, failure modes, and ownership.
  - Acceptance criteria: ADR approved and linked from proposal Section 7.

- [Medium] Release gate ownership is stated but not operationalized
  - Evidence: DOC-05, DOC-06, QUESTION-02
  - Why it matters: Joint ownership can stall go/no-go decisions without explicit ceremony and artifacts.
  - Recommended fix: Add a release-governance runbook template (inputs, approvers, SLA, escalation).
  - Acceptance criteria: One rehearsal go/no-go run uses the runbook before first “Next” wave RC.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Strict CI artifact gates vs delivery speed.
  - Tradeoff: More evidence per PR increases overhead but prevents regression.
  - Decision: Require artifacts for modal-flow changes only; keep scope bounded.
  - Owner: Mobile Platform Team + QA Lead.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Add ADR for syntax-aware CI parser + fallback behavior | Architecture | Mobile Platform Team | Now | Tool selection | ADR linked; CI behavior unambiguous |
| P0 | Add release-governance runbook for metric + rollback sign-off | Architecture/UX | Engineering Manager + Product Analytics | Now | Existing Section 10 contract | One dry run completed |
| P1 | Enforce compact modal screenshot artifacts in CI | UI | QA Lead | Next | Snapshot pipeline | Modal regressions caught pre-merge |
| P1 | Add canonicalization examples for dirty-state matrix forms | UX | UX Lead + Feature Leads | Next | Form ownership map | No dirty-state ambiguity in review |

## 6. Execution Plan
- Now (0-2 weeks): finalize parser ADR and release runbook.
- Next (2-6 weeks): enforce compact screenshot artifacts and canonicalization examples.
- Later (6+ weeks): track cycle metrics and confirm Green criteria completion over one release cycle.

## 7. Open Questions
- Which parser stack is approved for syntax-aware checks in CI?
- Who is escalation owner when Product Analytics and Mobile Platform disagree on go/no-go?

## 8. Rating Decision
Current combined readiness rating: **8.7 / 10**.
- Condition “9+ => all good” is **not met yet**.
- The proposal is very close; after closing the two P0 items above, it is likely to cross 9.
