# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed: 9 (see `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL_EVIDENCE_PACK_R2.md`)
- Internet sources reviewed: 7
- Xcode screenshots captured: 4 (large + compact, modal-open + post-cancel)
- Scope lock for this pass:
  - In scope: iPhone-first iOS/Android navigation-presentation policy, CI enforcement, rollout controls.
  - Out of scope: iPad regular-width policy details (tracked as follow-up).

## 1. Executive Summary
- Overall readiness: **Amber**
- Why not Green yet:
  1. CI enforcement is still path-based and not reliable for mixed source files with inline `#Preview` blocks.
  2. Kill-switch strategy is declared but not technically selected/owned.
  3. Outcome guardrails are defined, but telemetry schema and ownership are not implementation-ready.
- What is already strong:
  1. Proposal is now executable at policy level (owners, decision matrix, rollout waves, acceptance gates).
  2. Baseline is measurable and stable (`NavigationView=26`, `ActionSheet=2` in current inventory).
  3. Android baseline architecture already aligns with the direction (single `NavHost`).

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 7 | 0 | 0 | 2 | 1 |
| UX (Financial) | 7 | 0 | 0 | 3 | 0 |
| iOS Architecture | 6 | 0 | 1 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [Medium] Compact modal anatomy still lacks explicit overflow rules
  - Evidence: DOC-03, SCR-01, SCR-03
  - Why it matters: `MOD-02` screens are keyboard-heavy; without deterministic title/button overflow behavior, toolbar hierarchy can regress on compact devices.
  - Recommended fix: Add compact rules per decision ID: title truncation behavior, primary-button priority, secondary-action collapse, and keyboard toolbar fallback.
  - Acceptance criteria: All `MOD-02` flows pass compact screenshot checklist with no clipped/truncated primary actions.

- [Medium] iPad behavior remains an intentional gap in the contract
  - Evidence: DOC-01
  - Why it matters: iOS policy is now strong for iPhone but regular-width behavior is undefined, which creates future divergence risk.
  - Recommended fix: Add a linked iPad appendix mapping `MOD-01...MOD-05` to `NavigationSplitView`/popover/sheet rules.
  - Acceptance criteria: Appendix exists and is referenced before starting the “Next” rollout wave.

- [Low] Drag-dismiss interruption behavior is not explicitly specified
  - Evidence: DOC-03, SCR-02, SCR-04, WEB-02
  - Why it matters: Dirty forms need deterministic visual feedback when user drags to dismiss.
  - Recommended fix: Define interruption pattern: drag attempt on dirty form -> bounce-back -> discard confirmation.
  - Acceptance criteria: UI tests verify no partial dismiss transition on dirty forms.

### 3.2 UX Review Findings
- [Medium] Dirty-state semantics are still abstract across financial forms
  - Evidence: DOC-04, SCR-01, SCR-03
  - Why it matters: If each form defines “dirty” differently, users get inconsistent discard prompts and lose trust.
  - Recommended fix: Add a shared dirty-state contract (field mutation, canonical value delta, async-preview side effects).
  - Acceptance criteria: Dirty-state matrix exists for all guarded forms and is covered by unit/UI tests.

- [Medium] Section 10 guardrails lack an event-level telemetry contract
  - Evidence: DOC-07
  - Why it matters: Guardrails are not release-usable without event names, properties, ownership, and dashboard mapping.
  - Recommended fix: Add analytics appendix with `event`, `properties`, `owner`, `dashboard`, and alert threshold per metric.
  - Acceptance criteria: Dashboard is live and used in release go/no-go for two consecutive releases.

- [Medium] Top-5 parity journeys are defined but not executable as QA scripts
  - Evidence: DOC-06, DOC-09, WEB-04, WEB-05
  - Why it matters: “Parity” remains subjective unless each journey has deterministic steps and pass/fail checkpoints.
  - Recommended fix: Add scripted parity scenarios per journey: entry, primary action, cancel, validation error, recovery, completion.
  - Acceptance criteria: Same scripts run on iOS and Android with artifact capture and traceable pass/fail history.

### 3.3 Architecture Review Findings
- [High] Path-based CI allowlist is insufficient for mixed Swift files
  - Evidence: DOC-05, DOC-08
  - Why it matters: Many files contain both production code and `#Preview`; path filters can miss real violations or generate false positives.
  - Recommended fix: Move to syntax-aware linting (parse and ignore preview blocks) or enforce preview-only files by convention and CI check.
  - Acceptance criteria: Forbidden-API CI reports <1% false positives over one release cycle and always includes actionable file/line output.

- [Medium] Kill-switch strategy is declared but mechanism/owner is undefined
  - Evidence: DOC-06
  - Why it matters: Rollout safety is not operational until the toggle mechanism and fallback semantics are chosen.
  - Recommended fix: Select one mechanism (`RemoteConfig` or local feature registry), assign owner, and publish rollback runbook.
  - Acceptance criteria: Each migration wave has tested enable/disable behavior in staging.

- [Medium] Decision-ID compliance is not machine-auditable yet
  - Evidence: DOC-03, DOC-05
  - Why it matters: PR-template-only compliance drifts over time and is hard to verify.
  - Recommended fix: Require machine-checkable mapping annotation near each modal call-site (e.g., `MOD-xx` tag) and verify in CI.
  - Acceptance criteria: 100% modal/dialog call-sites are auto-validated against `MOD-01...MOD-05`.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Strict CI enforcement vs productivity in mixed source files.
  - Tradeoff: Aggressive checks reduce regressions but can create noisy failures.
  - Decision: Make CI syntax-aware (or enforce preview file split) before making it hard release gate.
  - Owner: Mobile Platform Team.

- Conflict: iPhone-first rollout speed vs regular-width consistency.
  - Tradeoff: Excluding iPad now accelerates migration but defers consistency risk.
  - Decision: Keep iPad out of current wave, but require appendix before “Next” wave execution.
  - Owner: Product Design Lead + iOS Lead.

- Conflict: Guardrail ambition vs observability maturity.
  - Tradeoff: Strong product gates require telemetry infra that may lag migration work.
  - Decision: Gate rollout progression on instrumentation readiness, not only code migration completion.
  - Owner: Product Analytics + Engineering Manager.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Implement syntax-aware forbidden-API CI check (or enforced preview-file split) | Architecture | Mobile Platform Team | Now | Lint tooling update | <1% false positives; actionable file/line output |
| P0 | Publish telemetry schema for Section 10 guardrails | UX/Architecture | Product Analytics + iOS Lead | Now | Event catalog alignment | Dashboard covers all guardrail metrics per journey |
| P1 | Add compact overflow rules for all `MOD-02` flows | UI | Product Designer + iOS Lead | Next | Presentation contract appendix | Compact screenshots pass with no clipped primary controls |
| P1 | Publish scripted parity tests for top 5 journeys | UX | QA Lead + Android Lead | Next | Journey script definition | Reproducible parity pass/fail artifacts on both platforms |
| P1 | Select and document kill-switch mechanism + rollback runbook | Architecture | Engineering Manager | Next | Feature-toggle decision | Each migration wave has tested rollback path |
| P2 | Add iPad appendix mapped to `MOD-01...MOD-05` | UI/UX | Product Design Lead | Later | iPad scope kickoff | Regular-width contract is explicit and testable |
| P2 | Enforce machine-checkable `MOD-xx` mapping at call-sites | Architecture | iOS Lead | Later | CI parser support | 100% modal call-sites auto-audited |

## 6. Execution Plan
- Now (0-2 weeks):
  - Deliver CI enforcement architecture decision (syntax-aware lint vs preview-file split).
  - Land telemetry schema and dashboard ownership for all Section 10 metrics.
  - Keep migration ledger updated weekly against the current baseline inventory.
- Next (2-6 weeks):
  - Execute module migration order (`Planning` -> `Dashboard` -> `Goals`).
  - Add compact `MOD-02` overflow contract and parity test scripts.
  - Validate kill-switch rollback in staging for every migrated module.
- Later (6+ weeks):
  - Publish iPad appendix and extend parity validation.
  - Enforce machine-checkable decision-ID mapping in CI.
  - Remove temporary allowlists as migration reaches full coverage.

## 7. Definition of Green (Exit Criteria)
Proposal review status moves from Amber to Green when all are true:
1. `policy-nav-ios-forbidden-apis` CI check is syntax-aware (or equivalent) and stable for one full release cycle.
2. Section 10 metrics are instrumented with owners, dashboards, and alert thresholds.
3. Top-5 parity journey scripts run on iOS + Android with reproducible artifacts.
4. Kill-switch and rollback runbook is tested for each migrated module wave.

## 8. Open Questions
- Should preview blocks remain inline with syntax-aware filtering, or be migrated to dedicated preview-only files?
- Which organization signs off release-blocking guardrail dashboards (Product Analytics, Mobile Platform, or both)?
- What deadline should be set for iPad appendix delivery relative to the first “Next” wave release candidate?
