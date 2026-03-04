# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed: 11
- Internet sources reviewed: 6
- Xcode screenshots captured/reused: 6 (including fresh preview + iOS visual-state/production captures)
- Scope lock: proposal-quality review for `GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` (not implementation-complete certification)
- Evidence pack: `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL_EVIDENCE_PACK_R1.md`

## 1. Executive Summary
- Overall readiness: **Amber**
- Proposal readiness score: **7.4 / 10**
- Top 3 risks:
  1. Core architecture contract is underspecified: `GoalDashboardSceneModel` is named but not defined as an executable schema.
  2. Decision support can mislead users in financial contexts because CTA and risk modules do not define freshness/error explainability rules.
  3. Rollout safety is incomplete: migration/rollback details for legacy dashboard routes and persisted widget config are missing.
- Top 3 opportunities:
  1. IA ordering is strong and correctly re-centers the screen around user actionability.
  2. Ownership cleanup direction is correct (preview-only vs production boundaries, one VM source).
  3. State taxonomy (`loading/ready/empty/error/stale`) is a good base for deterministic testing once recovery behavior is specified.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 7.8 | 0 | 1 | 2 | 0 |
| UX (Financial) | 7.2 | 0 | 2 | 2 | 0 |
| iOS Architecture | 7.0 | 1 | 1 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Visual system rules are directional but not enforceable as a token contract
  - Evidence: DOC-02, DOC-08, WEB-02, WEB-06
  - Why it matters: The proposal bans ad-hoc depth/shadow usage, but without a token map and deprecation list teams can reintroduce inconsistent card styles during rollout.
  - Recommended fix: Add a dashboard token contract appendix (`surface`, `elevation`, `stroke`, `statusChip`) plus a component-to-token mapping table.
  - Acceptance criteria: Every dashboard module references token names only; lint/snapshot checks fail on non-token shadows/material mixes.

- [Medium] No motion/orientation contract for module reorder and state transitions
  - Evidence: DOC-02, DOC-03, WEB-01
  - Why it matters: Reordering and replacing dashboard modules without transition rules can increase perceived instability and reduce orientation.
  - Recommended fix: Add motion policy for module insert/remove/state change (durations, easing, reduced-motion fallback).
  - Acceptance criteria: Transition matrix exists for `loading->ready`, `ready->error`, `stale->recovery`; reduced-motion behavior is explicitly defined.

- [Medium] Status chip spec is incomplete for accessibility-safe semantics
  - Evidence: DOC-03, WEB-03, SCR-03, SCR-04
  - Why it matters: Risk states in finance cannot rely on color impression only; proposal names chip states but does not enforce icon/text/contrast behavior.
  - Recommended fix: Define status chip anatomy (icon + text + semantic color token + VoiceOver label) and contrast thresholds.
  - Acceptance criteria: Chip spec includes non-color cue requirement and WCAG contrast target; snapshot/a11y tests validate each risk state.

### 3.2 UX Review Findings
- [High] `Next Action` resolver is too narrow for real financial states
  - Evidence: DOC-03, DOC-05, DOC-10, WEB-05
  - Why it matters: Four resolver branches are insufficient for stale prices, failed fetches, paused/finished goals, or over-allocated conditions, creating wrong or missing primary actions.
  - Recommended fix: Expand resolver matrix to include data-health and goal-lifecycle conditions, with explicit fallback CTA priority rules.
  - Acceptance criteria: Resolver table covers at least `no-assets`, `no-contributions`, `behind`, `on-track`, `stale-data`, `hard-error`, `goal-finished`, `over-allocated` and guarantees exactly one primary CTA.

- [High] Forecast/risk module lacks explainability contract
  - Evidence: DOC-01, DOC-03, DOC-05, DOC-10, WEB-05
  - Why it matters: The proposal promises risk guidance but explicitly excludes algorithm redesign; without explanation of assumptions/confidence windows users may distrust or misinterpret recommendations.
  - Recommended fix: Add trust copy contract: "based on last X days", last-update timestamp, confidence level, and "why this status" disclosure pattern.
  - Acceptance criteria: Forecast card always shows assumption basis + recency metadata + drill-down explanation link in `ready/stale/error` states.

- [Medium] `<= 3 seconds` comprehension criterion is not measurable as written
  - Evidence: DOC-05, QUESTION-02
  - Why it matters: Success criterion is strong but cannot be validated without a protocol (sample size, scenario setup, instrumentation, pass threshold).
  - Recommended fix: Define UX test protocol and telemetry proxy (time-to-first-primary-action tap, question success rate).
  - Acceptance criteria: A runbook specifies participant/task script and quantitative pass threshold; telemetry event contract is linked.

- [Medium] Error and stale states do not mandate recovery actions per module
  - Evidence: DOC-03, SCR-03, SCR-04, WEB-05
  - Why it matters: Declaring state names is not enough; users need clear recovery controls in financial contexts.
  - Recommended fix: Add per-module state behavior table with mandatory recovery affordance and copy.
  - Acceptance criteria: Each module defines at least one recovery action in `error` and one data-refresh action in `stale`.

### 3.3 Architecture Review Findings
- [Critical] Single-source scene model is not specified as an executable contract
  - Evidence: DOC-04, DOC-09, DOC-10, QUESTION-01
  - Why it matters: The proposal's core architectural promise is one canonical state source, but no schema, freshness semantics, or error provenance fields are defined, which risks recreating fragmented per-module logic.
  - Recommended fix: Add a `GoalDashboardSceneModel` contract section with field definitions, derivation ownership, freshness/error metadata, and update triggers.
  - Acceptance criteria: Contract includes typed field list and lifecycle diagram; all modules consume only scene model slices.

- [High] Migration/rollback path for legacy dashboard and persisted settings is incomplete
  - Evidence: DOC-04, DOC-07, DOC-09, QUESTION-03
  - Why it matters: Existing call-sites and persisted `dashboard_widgets` state can regress during cutover unless migration and rollback behavior is explicit.
  - Recommended fix: Add migration plan: route switch sequence, data compatibility handling, and rollback conditions under feature flag.
  - Acceptance criteria: Proposal includes cutover checklist with compatibility behavior for legacy persisted data and rollback verification steps.

- [Medium] Test strategy misses integration-level performance/concurrency gates
  - Evidence: DOC-05, DOC-10
  - Why it matters: Unit/UI/snapshot tests are present, but they do not bound latency, duplicate loading, or race conditions from async dashboard aggregation.
  - Recommended fix: Add integration tests + performance budgets for initial load and refresh paths.
  - Acceptance criteria: CI enforces max load-time budget and verifies no duplicate load invocation across module tree.

- [Medium] Android parity is intent-level, not contract-level
  - Evidence: DOC-02, DOC-04, DOC-05, WEB-06
  - Why it matters: "Android parity note" is too weak to prevent platform drift without a shared schema/copy key artifact.
  - Recommended fix: Publish shared parity contract (`module IDs`, `state IDs`, `copy keys`, `CTA resolver states`) consumed by both apps.
  - Acceptance criteria: Both platforms reference the same parity artifact; release check fails on key/state drift.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Exactly one primary CTA vs discoverability of advanced actions
  - Tradeoff: Single CTA reduces cognitive load, but power users may feel constrained.
  - Decision: Keep one primary CTA above the fold; expose secondary actions in `Utilities` with stable placement.
  - Owner: Product Design + Mobile Engineering.

- Conflict: Strict same-module semantics across iPhone/iPad vs platform affordance differences
  - Tradeoff: Semantic parity improves consistency; strict visual parity can reduce platform fit.
  - Decision: Keep semantic parity (same modules/state model), allow layout-density and interaction affordance adaptation by size class.
  - Owner: Design System + iOS/Android leads.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Define `GoalDashboardSceneModel` schema + freshness/error provenance contract | Architecture | iOS Tech Lead | Now | None | All modules consume scene slices; no raw model queries in view layer |
| P0 | Expand `Next Action` resolver matrix with data-health/lifecycle states | UX | Product Designer + PM | Now | Scene model fields | Exactly one correct CTA for all defined states |
| P0 | Add migration + rollback plan for legacy dashboard routes and `dashboard_widgets` compatibility | Architecture | iOS Lead | Now | Feature-flag strategy | Cutover rehearsal passes without data loss/regression |
| P1 | Add trust/explainability contract to Forecast/Risk module | UX | Product + Content Design | Next | Resolver + scene model | Users can explain risk status source in UX test |
| P1 | Add token mapping appendix and status-chip accessibility spec | UI | Design System Owner | Next | Visual token inventory | No ad-hoc shadow/material usage in dashboard modules |
| P1 | Add integration performance/concurrency tests for dashboard load pipeline | Architecture | QA + iOS Eng | Next | Scene-model implementation | Load-time budget and duplicate-load checks enforced in CI |
| P2 | Publish shared iOS/Android parity contract artifact | Architecture/UX | Cross-platform working group | Later | iOS schema stabilized | No module/state/copy drift at release gate |

## 6. Execution Plan
- Now (0-2 weeks):
  - Freeze scene model contract and expanded CTA resolver matrix.
  - Add migration/rollback section with explicit persisted-data compatibility handling.
- Next (2-6 weeks):
  - Implement trust copy for forecast/risk and formalize token/status-chip spec.
  - Add integration performance/concurrency test gates.
- Later (6+ weeks):
  - Operationalize parity artifact and make it release-gating across iOS/Android.

## 7. Open Questions
- Which layer owns scene-model derivation for forecast/risk freshness metadata?
- What user-research protocol and sample size will validate the `<= 3 seconds` comprehension target?
- Should legacy widget customization be migrated, reset, or ignored during cutover?

## 8. Rating Decision
Current combined readiness rating: **7.4 / 10 (Amber)**.
- Proposal direction is strong, but it is not implementation-ready yet.
- Closing the three P0 items should move readiness into **8.5+** territory for execution.
