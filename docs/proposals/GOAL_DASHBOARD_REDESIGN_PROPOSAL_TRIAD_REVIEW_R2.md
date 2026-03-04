# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed: 9
- Internet sources reviewed: 3 (official/primary)
- Xcode screenshots captured/reused: 6
- Scope lock: proposal-readiness re-review after R1 remediation, not implementation certification.
- Evidence pack: `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL_EVIDENCE_PACK_R2.md`

## 1. Executive Summary
- Overall readiness: **Amber-Green**
- Proposal readiness score: **8.6 / 10**
- Top 3 residual risks:
  1. Acceptance matrix is not fully internally consistent (`goal_paused` exists in resolver but not in acceptance coverage list).
  2. Scene model contract still omits normative field-level schemas for slice sub-objects, leaving cross-platform interpretation room.
  3. Rollback and parity governance controls are defined but not yet operationally pinned (numeric baselines, ownership/versioning discipline).
- Top 3 strengths:
  1. R1 architectural gap is materially closed via explicit scene model contract and recompute triggers.
  2. UX trust layer is materially improved with resolver determinism and forecast explainability requirements.
  3. Visual and accessibility contracts are now substantially implementation-ready (tokens, chips, motion, recovery states).

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 8.9 | 0 | 0 | 1 | 0 |
| UX (Financial) | 8.7 | 0 | 1 | 1 | 0 |
| iOS Architecture | 8.3 | 0 | 1 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [Medium] Visual contract is strong, but enforcement linkage is still implicit
  - Evidence: DOC-04, DOC-06, WEB-01, WEB-02
  - Why it matters: Token/chip/motion rules are defined, but proposal text does not explicitly bind each rule to a concrete lint/snapshot gate mapping.
  - Recommended fix: Add one enforcement table mapping each visual rule to CI gate/test owner.
  - Acceptance criteria: Every UI contract row includes `enforcedBy` (lint/snapshot/a11y test ID) and owning team.

### 3.2 UX Review Findings
- [High] Acceptance criteria omit `goal_paused` despite resolver support
  - Evidence: DOC-03
  - Why it matters: This creates a blind spot where a valid resolver state can ship unvalidated, breaking “exactly one correct primary CTA” promise.
  - Recommended fix: Add `goal_paused` to section 11 resolver coverage list and to section 12 test matrix.
  - Acceptance criteria: Resolver coverage in acceptance/test sections exactly matches section 4 state IDs.

- [Medium] Recovery actions are defined, but user-facing failure transparency for diagnostics path is shallow
  - Evidence: DOC-03, DOC-04, DOC-05
  - Why it matters: For `hard_error`, users may get retry + diagnostics action without a minimum diagnostic payload contract.
  - Recommended fix: Define minimal diagnostics content (reason code, last successful refresh time, next step guidance).
  - Acceptance criteria: `hard_error` details sheet always includes reason, last-success timestamp, and actionable next step.

### 3.3 Architecture Review Findings
- [High] Slice-level schema remains underspecified
  - Evidence: DOC-02, DOC-06
  - Why it matters: Top-level scene contract is clear, but undefined `SnapshotSlice`/`ForecastRiskSlice` field contracts can cause platform drift and incompatible serializers.
  - Recommended fix: Add normative schema appendix for all slice types (required/optional fields, enums, nullability).
  - Acceptance criteria: Shared schema artifact validates slice payloads in iOS and Android tests.

- [Medium] Rollback trigger “below baseline” lacks explicit numeric policy
  - Evidence: DOC-05
  - Why it matters: Operational decisions become subjective under release pressure if baseline thresholds and windows are not pinned.
  - Recommended fix: Add numeric baseline deltas and observation windows in proposal or linked release runbook.
  - Acceptance criteria: Rollback section includes measurable thresholds (example: crash-free delta and minimum sample window).

- [Medium] Parity artifact governance model is not explicit
  - Evidence: DOC-06, QUESTION-01
  - Why it matters: Without ownership/versioning rules, parity file can drift or be edited ad hoc.
  - Recommended fix: Add governance subsection (owner, change-approval path, version bump policy, backward compatibility rule).
  - Acceptance criteria: Parity artifact has named owner and semantic versioning rules enforced in CI.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Strong deterministic CTA policy vs nuanced lifecycle/error contexts.
  - Tradeoff: Determinism prevents ambiguity; overly simple acceptance lists can miss legitimate states.
  - Decision: Keep deterministic resolver; enforce full state-list parity across resolver, acceptance criteria, and tests.
  - Owner: Product + QA.

- Conflict: Proposal detail depth vs execution speed.
  - Tradeoff: More schema/governance detail increases authoring overhead but lowers cross-platform drift.
  - Decision: Add targeted appendices (slice schema + parity governance) without expanding product scope.
  - Owner: iOS/Android tech leads.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Add `goal_paused` to acceptance + test coverage matrix | UX | Product Designer + QA Lead | Now | Resolver table | Coverage lists exactly match resolver states |
| P0 | Define slice-level schema appendix for all scene subtypes | Architecture | iOS + Android Tech Leads | Now | Scene model contract | Shared schema validation passes on both platforms |
| P1 | Add explicit rollback numeric thresholds/window | Architecture | Engineering Manager | Next | Release telemetry baseline | Rollback decisions become objective and auditable |
| P1 | Add parity artifact governance/versioning section | Architecture | Cross-platform owner | Next | Shared fixture path | Versioned parity changes with owner approval |
| P2 | Map UI contract rows to CI enforcement IDs | UI | Design System + QA | Later | Existing CI gates | Each visual rule has automated enforcement linkage |

## 6. Execution Plan
- Now (0-2 weeks):
  - Close resolver coverage inconsistency (`goal_paused`).
  - Publish slice schema appendix.
- Next (2-6 weeks):
  - Pin rollback metrics numerically.
  - Formalize parity artifact governance and versioning.
- Later (6+ weeks):
  - Complete UI-rule-to-gate traceability matrix.

## 7. Open Questions
- Should rollback thresholds live in this proposal or a mandatory linked release runbook?
- Will parity artifact version bumps require joint iOS+Android approval by policy?

## 8. Rating Decision
Current combined readiness rating: **8.6 / 10**.
- Compared to R1, proposal quality is significantly improved and near implementation-ready.
- Closing two P0 actions should move readiness to **9+**.
