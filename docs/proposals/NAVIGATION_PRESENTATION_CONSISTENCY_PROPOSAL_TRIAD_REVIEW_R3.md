# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed: 10 (see `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL_EVIDENCE_PACK_R3.md`)
- Internet sources reviewed: 8
- Xcode screenshots captured: 4 (2 fresh large-device captures on 2026-03-03 + 2 validated compact baselines)
- Remaining assumptions:
  - Proposal is evaluated as governance/design artifact; implementation status is out of scope.
  - iPad regular-width policy is intentionally deferred.

## 1. Executive Summary
- Overall readiness: **Amber (close to Green)**
- What improved vs prior pass:
  1. Policy is now executable: decision matrix, ownership, rollout waves, burn-down targets, and measurable acceptance criteria are defined.
  2. Trust-critical dismiss behavior is explicitly specified (`Keep Editing` / `Discard`, no silent loss).
  3. Release guardrails are framed with product metrics, not only API migration counts.
- Remaining blockers to Green:
  1. CI forbidden-API enforcement is still not technically robust for mixed source files (production + inline `#Preview`).
  2. Kill-switch/rollback intent exists but operational mechanism and owner are still undefined.
  3. Telemetry contract for Section 10 guardrails is not yet implementation-ready.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 8 | 0 | 0 | 1 | 1 |
| UX (Financial) | 8 | 0 | 0 | 2 | 0 |
| iOS Architecture | 6 | 0 | 1 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [Medium] Compact `MOD-02` behavior still lacks explicit overflow fallback
  - Evidence: DOC-03, SCR-01, SCR-03
  - Why it matters: Compact keyboard-heavy screens still risk title/action crowding without deterministic collapse/overflow rules.
  - Recommended fix: Add compact layout contract for `MOD-02` with explicit priority order (`primary CTA` > `cancel/back` > `secondary text`) and truncation policy.
  - Acceptance criteria: Compact screenshot tests show no clipped primary actions across all `MOD-02` mapped screens.

- [Low] iPad follow-up exists only as open scope, not linked plan
  - Evidence: DOC-01, ASSUMP-03
  - Why it matters: Deferral is acceptable, but without a linked appendix plan, regular-width consistency may drift while iPhone migration proceeds.
  - Recommended fix: Add a dated follow-up artifact link in the proposal (`iPad modal/navigation appendix`).
  - Acceptance criteria: Appendix link and target date are present before entering “Next” wave.

### 3.2 UX Review Findings
- [Medium] Dirty-state contract is policy-level but not flow-level
  - Evidence: DOC-04, SCR-01, SCR-03
  - Why it matters: If forms compute “dirty” differently, users get inconsistent discard prompts in financial flows.
  - Recommended fix: Define a shared dirty-state spec (`field mutation`, `canonical amount delta`, `async preview side effects`) and map it to each targeted form.
  - Acceptance criteria: Dirty-state matrix exists for all guarded forms and is verified in unit/UI tests.

- [Medium] Metric guardrails still lack executable event schema
  - Evidence: DOC-07, QUESTION-03
  - Why it matters: Release gate metrics cannot operate without concrete event names/properties/owners/dashboard.
  - Recommended fix: Add analytics appendix with event contract and ownership table.
  - Acceptance criteria: Dashboard is live and used for go/no-go in two consecutive releases.

### 3.3 Architecture Review Findings
- [High] CI allowlist strategy is path-pattern based and fragile
  - Evidence: DOC-05, DOC-08, QUESTION-01
  - Why it matters: Pattern-based allowlists can miss violations or create noise when production code and previews live in the same file.
  - Recommended fix: Use syntax-aware linting (SwiftSyntax/AST) or enforce preview-only files via CI rule.
  - Acceptance criteria: `policy-nav-ios-forbidden-apis` runs with <1% false positives over one release cycle and reports actionable file/line output.

- [Medium] Kill-switch strategy is declarative, not operational
  - Evidence: DOC-06, QUESTION-02
  - Why it matters: Rollout rollback cannot be trusted until mechanism, owner, and drill process are defined.
  - Recommended fix: Choose mechanism (`RemoteConfig` or local feature registry), assign owner, and publish rollback runbook.
  - Acceptance criteria: Each migration wave completes a staged rollback drill with documented evidence.

- [Medium] Decision-ID mapping is not auto-audited
  - Evidence: DOC-03, DOC-05
  - Why it matters: Manual PR-template compliance does not scale and is prone to drift.
  - Recommended fix: Require machine-checkable `MOD-xx` annotation on modal/dialog call-sites and validate in CI.
  - Acceptance criteria: 100% modal call-sites are auto-linked to `MOD-01...MOD-05`.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Strict CI policing vs developer ergonomics in mixed source files.
  - Tradeoff: Hard-fail lint improves consistency but can produce noisy failures when preview code is inline.
  - Decision: Make lint syntax-aware (or split preview files) before enforcing as hard release gate.
  - Owner: Mobile Platform Team.

- Conflict: Fast iPhone rollout vs postponed iPad policy.
  - Tradeoff: Current pace improves near-term delivery but risks regular-width divergence.
  - Decision: Keep iPad out of current wave, but bind follow-up appendix to a dated milestone.
  - Owner: Product Design Lead + iOS Lead.

- Conflict: Ambitious product guardrails vs incomplete telemetry plumbing.
  - Tradeoff: Strong metrics are desirable but cannot gate releases without event contract and ownership.
  - Decision: Block transition to Green until telemetry contract is implemented.
  - Owner: Product Analytics + Engineering Manager.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Implement syntax-aware forbidden-API CI enforcement (or preview-file split rule) | Architecture | Mobile Platform Team | Now | Lint tooling decision | <1% false positives; actionable file/line output |
| P0 | Publish Section 10 telemetry event contract + dashboard ownership | UX/Architecture | Product Analytics + iOS Lead | Now | Event catalog review | Guardrail dashboard live for all top-5 journeys |
| P1 | Define and adopt shared dirty-state specification across financial forms | UX | UX Lead + iOS Lead | Next | Form-level mapping workshop | Dirty-dismiss behavior is deterministic in tests |
| P1 | Select kill-switch mechanism and run rollback drills per wave | Architecture | Engineering Manager | Next | Toggle infra decision | Staged rollback evidence exists for each module wave |
| P1 | Add compact `MOD-02` overflow contract and screenshot checks | UI | Product Designer + QA Lead | Next | UI contract appendix | No clipped primary actions on compact devices |
| P2 | Add machine-checkable `MOD-xx` annotations in source + CI validator | Architecture | iOS Lead | Later | Parser/lint support | 100% modal call-sites auto-audited |
| P2 | Publish iPad appendix with `MOD-01...MOD-05` mapping | UI/UX | Product Design Lead | Later | iPad scope kickoff | Regular-width behavior contract documented |

## 6. Execution Plan
- Now (0-2 weeks):
  - Close CI architecture decision (syntax-aware lint vs preview-file split).
  - Publish telemetry event contract and assign dashboard ownership.
  - Keep migration ledger updated weekly against baseline inventory.
- Next (2-6 weeks):
  - Execute module migration order (`Planning` -> `Dashboard` -> `Goals`).
  - Implement shared dirty-state spec and compact overflow contract for `MOD-02`.
  - Validate kill-switch rollback drills in staging for each migrated wave.
- Later (6+ weeks):
  - Enforce machine-checkable decision-ID mapping.
  - Ship iPad appendix and extend parity validation beyond iPhone-first scope.
  - Remove temporary allowlist exceptions as migration nears 100%.

## 7. Exit Criteria to Green
Status moves from Amber to Green when all criteria are met:
1. CI forbidden-API enforcement is robust for mixed source files and stable for one full release cycle.
2. Section 10 telemetry contract is implemented with owned dashboards and alert thresholds.
3. Kill-switch and rollback runbook is exercised for each migration wave.
4. Dirty-dismiss behavior is deterministic and test-proven across all targeted financial forms.

## 8. Open Questions
- Do we standardize on syntax-aware filtering for inline previews, or enforce preview-only file segregation?
- Which team owns final release sign-off for guardrail metrics (Product Analytics, Mobile Platform, or joint)?
- What concrete deadline will be set for the iPad appendix relative to the first “Next” wave RC?
