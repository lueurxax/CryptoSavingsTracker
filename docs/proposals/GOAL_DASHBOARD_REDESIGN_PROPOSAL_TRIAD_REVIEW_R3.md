# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed: 9
- Internet sources reviewed: 3
- Xcode screenshots captured/revalidated: 4 (including fresh iOS production dashboard captures on 2026-03-04)
- Scope lock: proposal-readiness review after R2 revisions.
- Evidence pack: `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL_EVIDENCE_PACK_R3.md`

## 1. Executive Summary
- Overall readiness: **Amber-Green**
- Proposal readiness score: **8.9 / 10**
- Top 3 residual risks:
  1. Shared-schema serialization contract is still ambiguous for financial types (`Decimal`, `Date`) at wire level.
  2. Proposal references normative runbook/schema/parity artifacts that are not yet present in repository.
  3. Preview/runtime stability risk exists today but is not explicitly tracked as a delivery risk item.
- Top 3 strengths:
  1. R1/R2 major gaps are now closed (deterministic resolver, schema appendix, rollback governance, parity policy).
  2. UI/UX contracts are concrete and test-oriented, with clear acceptance criteria and gate IDs.
  3. Cross-platform governance quality is materially stronger and now enforceable in principle.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 9.1 | 0 | 0 | 1 | 0 |
| UX (Financial) | 9.0 | 0 | 0 | 1 | 0 |
| iOS Architecture | 8.6 | 0 | 1 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [Medium] Visual quality contract is strong, but preview stability risk is not reflected in delivery risks
  - Evidence: DOC-09, SCR-04
  - Why it matters: UI execution confidence is lower when preview flows are unstable, especially for state-rich dashboard modules.
  - Recommended fix: Add explicit risk/mitigation entry for preview/runtime instability in section 10 or a dedicated risk section.
  - Acceptance criteria: Proposal includes owner + mitigation path for preview stability and fallback validation strategy.

### 3.2 UX Review Findings
- [Medium] `hard_error` diagnostics contract lacks minimum user-facing wording quality bar
  - Evidence: DOC-03, DOC-04
  - Why it matters: Even with required fields, financial users can still get opaque diagnostics if copy quality is inconsistent.
  - Recommended fix: Add copy quality constraints for diagnostics (`plain language`, `no internal-only jargon`, `next step in one sentence`).
  - Acceptance criteria: Content checklist validates diagnostics strings for readability and actionability before release.

### 3.3 Architecture Review Findings
- [High] Shared wire-format specification for `Decimal` and `Date` is still underspecified
  - Evidence: DOC-02, DOC-06, QUESTION-01
  - Why it matters: iOS/Android parity can drift or lose precision if numeric/time serialization rules are not canonicalized.
  - Recommended fix: Add canonical encoding contract (for example: decimal as string with fixed scale, ISO-8601 UTC timestamps) in schema appendix.
  - Acceptance criteria: Both platforms pass strict schema conformance tests with canonical fixtures and round-trip precision checks.

- [Medium] Normative artifact references are ahead of repository state
  - Evidence: DOC-08
  - Why it matters: Proposal claims normative source paths, but absent files reduce immediate execution readiness.
  - Recommended fix: Add bootstrap checklist item in Phase 1 to create these artifacts before dependent gates are enabled.
  - Acceptance criteria: referenced runbook + parity/schema files exist before CI rules that depend on them are activated.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Tight contract specificity vs iteration speed.
  - Tradeoff: More explicit schema/copy rules reduce ambiguity but add upfront authoring overhead.
  - Decision: Keep strong contract approach; add a short bootstrap milestone to unblock implementation pragmatically.
  - Owner: iOS/Android leads + Product Design.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Define canonical wire format for `Decimal` and `Date` in shared schema contract | Architecture | Cross-platform tech leads | Now | Existing schema appendix | Zero precision/timezone drift in parity tests |
| P0 | Create missing normative artifacts (runbook + parity/schema files) before gating | Architecture | Engineering Manager + QA | Now | Phase 1 bootstrap | All referenced files exist and are validated in CI |
| P1 | Add preview/runtime stability risk entry + mitigation owner | UI/Architecture | iOS lead | Next | Current crash evidence | Stable preview validation path for dashboard states |
| P1 | Add diagnostics copy-quality checklist | UX | Product Content + UX | Next | Hard-error payload contract | Diagnostics copy passes readability/actionability checks |

## 6. Execution Plan
- Now (0-2 weeks):
  - Canonicalize wire formats for money/time fields.
  - Add bootstrap artifact-creation milestone and create referenced files.
- Next (2-6 weeks):
  - Add preview stability risk/mitigation tracking.
  - Implement diagnostics copy-quality review checklist.
- Later (6+ weeks):
  - Keep CI parity and UI contract gates as release blockers through stabilization window.

## 7. Open Questions
- None blocking beyond the two P0 actions.

## 8. Rating Decision
Current combined readiness rating: **8.9 / 10**.
- Proposal is close to Green and implementation-ready.
- Completing both P0 actions should move it to **9.3+** with low residual ambiguity.
