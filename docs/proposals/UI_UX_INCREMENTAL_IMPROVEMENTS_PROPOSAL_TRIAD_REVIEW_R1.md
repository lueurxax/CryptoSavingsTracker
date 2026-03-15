# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed: proposal, related monthly-planning architecture notes, current iOS/Android code paths for planning rows, stale drafts, budget copy, and goal forms, plus the existing Goal Dashboard validator/CI contract surface.
- Internet sources reviewed: Apple Design Tips, Apple HIG Menus, Android Compose docs for text input, dialogs, and semantics, and CFPB guidance/research on consumer understanding in finance products.
- Xcode screenshots captured: goal requirement rows, stale draft banner/row, planning surface, Add Goal, and Edit Goal previews. Evidence pack: `docs/proposals/UI_UX_INCREMENTAL_IMPROVEMENTS_PROPOSAL_EVIDENCE_PACK_R1.md`.
- Remaining assumptions: Android currently has no stale-draft planning surface; previews are structural evidence only; Workstream D applies to goal forms, not every save CTA in planning.

## 1. Executive Summary
- Overall readiness: Amber
- Top 3 risks:
  1. The proposal claims broad cross-platform scope, but Workstreams B/C/D are materially platform-asymmetric in the current codebase.
  2. Workstream A acceptance and CI language do not actually verify the full copy surface the proposal says will be audited.
  3. Workstream D is still blocked by unresolved layout contracts, so implementation sequencing is not yet decision-complete.
- Top 3 opportunities:
  1. Split the document into a platform matrix per workstream and remove parity work that Android does not need.
  2. Convert Workstream A into an enforceable copy contract that includes inline literals and Android union coverage.
  3. Simplify Workstream C by choosing one resolution model: visible entry point plus confirmation, without adding chips that disappear almost immediately.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 7.4 | 0 | 1 | 2 | 0 |
| UX (Financial) | 6.9 | 0 | 2 | 1 | 0 |
| iOS Architecture | 6.6 | 0 | 2 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Workstream C adds state chips that have no durable visual job
  - Evidence: DOC-04, SCR-03, SCR-04
  - Why it matters: The proposal adds `Unresolved / Marked completed / Marked skipped` chips, but the same section also removes resolved rows after 0.6 seconds or immediately on delete. That makes the chip state largely ceremonial and increases row complexity without improving scanability.
  - Recommended fix: Pick one model. For v1, keep the visible `Resolve` button and the delete confirmation, but drop the resolved-state chips if rows still auto-dismiss. If the team wants chips, resolved rows must persist until the user leaves the screen or manually filters them out.
  - Acceptance criteria: A resolved stale draft either remains visible long enough to be meaningfully read, or the row contains no resolved-state chip at all. The final row anatomy has one visible primary action and no transient-only display elements.

- [Medium] Header simplification is still underspecified against the full above-the-fold stack
  - Evidence: DOC-03, DOC-08, SCR-05, SCR-08, WEB-01
  - Why it matters: The proposal correctly identifies `GoalRequirementRow` as only part of the problem, but the fix only merges the status pills into `consolidatedHeader` and removes the Goals count. The screen still has the optional stale-draft banner, tab selector, conditional collapsed strip, `BudgetHealthCard`, and the stats header before the first row. That is still a multi-layer stack.
  - Recommended fix: Add an explicit small-screen layout contract for the whole stack, not just `consolidatedHeader`. Define which elements must remain above the fold on compact iPhone layouts and what collapses first.
  - Acceptance criteria: On the target compact iPhone layout, the first goal row is partially visible without scrolling when stale drafts are absent, and the header stack has a documented priority order for collapse when stale drafts are present.

- [Medium] Preview coverage is too thin for the visual claims in Workstreams B/C/D
  - Evidence: DOC-17, SCR-01, SCR-02, SCR-06, SCR-07
  - Why it matters: The proposal requires preview evidence for Dynamic Type XXXL, validation-error, and persistence-error states, but current preview scaffolding only covers default goal forms and default stale-draft/row states. That makes the visual acceptance plan weaker than it appears.
  - Recommended fix: Add preview fixtures for `GoalRequirementRow` at large text, `StalePlanRow` resolved variants if they survive in the spec, and both goal forms in invalid and persistence-error states before implementation starts.
  - Acceptance criteria: Preview files exist for every state called out in Section 7, including at least one Dynamic Type accessibility variant and one invalid-form variant per form.

### 3.2 UX Review Findings
- [High] Workstream A acceptance does not verify the copy surface the proposal says it will fix
  - Evidence: DOC-02, DOC-06, DOC-12, DOC-13, DOC-16
  - Why it matters: The proposal promises to audit iOS catalogs, Android catalogs, and inline planning literals, but the acceptance criteria only mention grepping two iOS catalogs. In a financial app, unclear or unmanaged inline strings create trust breaks exactly where the proposal is trying to improve clarity.
  - Recommended fix: Rewrite Workstream A acceptance so it covers the full audited surface: iOS union, Android union, and a zero-inline-literal rule for the targeted planning/form files once the dictionary is introduced.
  - Acceptance criteria: CI fails if any targeted planning/form string is not represented in `docs/copy/FINANCIAL_COPY_DICTIONARY.md` and surfaced through the designated catalog path for that platform.

- [High] Platform scope is overstated; the workstreams are not symmetric today
  - Evidence: DOC-01, DOC-12, DOC-13, DOC-14
  - Why it matters: Android already exposes visible monthly-row actions and already uses enabled-save plus inline field errors in goal forms. Separately, the stale-draft surface appears to be iOS/macOS-only. Keeping one undifferentiated `Platform | iOS, Android` label obscures where parity work is real and where it is invented.
  - Recommended fix: Add a per-workstream platform matrix. Example: A = iOS + Android, B = iOS only, C = iOS + macOS only unless Android scope is added, D = iOS implementation plus Android parity review of summary/save-error treatment only.
  - Acceptance criteria: Each workstream header explicitly lists target platforms, non-target platforms, and whether the work is net-new, parity cleanup, or no-op on that platform.

- [Medium] Workstream D uses the right problem statement but not a decision-complete user flow
  - Evidence: DOC-05, DOC-10, DOC-11, WEB-03, WEB-06
  - Why it matters: The proposal correctly identifies the disabled-save discoverability problem on iOS, but it still leaves the critical user-flow choice open between top-inline summary and fixed-bottom action area. Without that choice, the promised focus movement, summary placement, and save-error recovery path are not testable as one flow.
  - Recommended fix: Choose one iOS contract in the proposal now. The stronger option is fixed bottom action area for iOS forms, while explicitly leaving Android on its existing full-width save pattern unless later evidence shows a need to change it.
  - Acceptance criteria: The proposal names one chosen layout contract for iOS, includes one annotated flow description from invalid tap -> summary focus -> corrected save -> persistence failure recovery, and lists Android deltas separately.

### 3.3 Architecture Review Findings
- [High] Workstream D is still blocked by unresolved architecture decisions
  - Evidence: DOC-05, DOC-10, DOC-11
  - Why it matters: The proposal itself says Workstream D is blocked, but later sections still speak in implementation terms and acceptance terms as if the blocking decisions have already been made. That leaves engineering without a source of truth for layout ownership, safe-area behavior, and UI-test strategy.
  - Recommended fix: Convert the form anatomy and CTA topology choice into a short linked ADR or make the proposal itself decision-complete by selecting one path and removing the unchosen path from the implementation plan.
  - Acceptance criteria: Before any implementation task starts, one document names the chosen iOS form contract, affected files, migration steps, and test deltas.

- [High] The proposal tries to reuse a Goal Dashboard validator for a planning-copy contract without first generalizing the tool boundary
  - Evidence: DOC-16, DOC-02
  - Why it matters: `validate_goal_dashboard_contracts.py` and `goal-dashboard-gates.yml` are strongly coupled to Goal Dashboard artifacts, fixtures, and naming. Extending them directly for planning copy parity will increase cognitive load and blur ownership between unrelated product areas.
  - Recommended fix: Either extract a generic copy-contract validator (`validate_copy_contracts.py`) or rename the existing tool/workflow to a broader contract-validation boundary before adding planning gates. Do not hide a cross-domain expansion inside one step of the delivery plan.
  - Acceptance criteria: CI naming, script naming, and ownership reflect the actual scope. Planning copy parity is enforced by a tool whose name and inputs match planning, not only dashboard.

- [Medium] Preview and QA evidence in Section 7 is not yet operationalized
  - Evidence: DOC-17, SCR-06, SCR-07
  - Why it matters: Section 7 requires preview evidence for error states, large text, and state variants, but the current preview fixtures do not expose those conditions. If the proposal ships unchanged, QA evidence becomes a manual aspiration rather than an executable requirement.
  - Recommended fix: Add a delivery-plan step that creates the missing preview fixtures and UI-test hooks before UI implementation begins.
  - Acceptance criteria: The delivery plan includes explicit preview fixture work and test owners, and the relevant preview files exist before feature code lands.

- [Medium] Workstream C should make the goal-name lookup contract explicit if Option 1 remains preferred
  - Evidence: DOC-04, DOC-09, DOC-15
  - Why it matters: Option 1 is the right low-risk choice, but the proposal currently stops at "pass a lookup dictionary." It does not define where the lookup is built, how missing goals are logged, or whether the fetch is batched and memoized per screen render.
  - Recommended fix: Specify that `PlanningView` builds a `[UUID: String]` map once per stale-draft query result, passes it into `StaleDraftBanner`, logs one warning per unresolved `goalId`, and falls back to `Unknown goal`.
  - Acceptance criteria: Workstream C includes one explicit data-flow contract for goal-name resolution with missing-data behavior and no model migration.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Workstream C wants richer visual row state (chips) while UX wants faster resolution and less cognitive load.
  - Tradeoff: More visible state can help orientation, but only if rows persist long enough to be read.
  - Decision: Prefer a visible `Resolve` action plus clear confirmation. Drop resolved-state chips in v1 unless rows stay on-screen after resolution.
  - Owner: Product + iOS lead

- Conflict: Workstream D recommends a fixed-bottom CTA for co-located summary/action, while platform fidelity favors existing Android patterns.
  - Tradeoff: One shared pattern sounds cleaner, but the current Android form already achieves tap-to-validate and inline feedback without the iOS anatomy blocker.
  - Decision: Treat iOS and Android separately in Workstream D. Standardize iOS first; review Android only for parity gaps that remain after iOS decisions are made.
  - Owner: Product + iOS lead + Android lead

- Conflict: Delivery Plan step 6 prefers reusing an existing validator, while architecture wants clean ownership boundaries.
  - Tradeoff: Reuse is faster short term, but the current tool boundary is dashboard-specific.
  - Decision: Generalize or rename the validator before adding planning scope; do not accrete more product areas into a dashboard-specific gate.
  - Owner: Architecture lead

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Add a per-workstream platform matrix and narrow scope claims where Android/macOS are not actually in play | UX / Architecture | Product | Now | None | Proposal metadata and each workstream header explicitly match real platform scope |
| P0 | Rewrite Workstream A acceptance and CI contract to cover iOS union, Android union, and inline planning literals | UX / Architecture | Product + Architecture | Now | Platform matrix | CI can prove full audited copy coverage rather than only two iOS catalogs |
| P0 | Resolve Workstream D by choosing one iOS form anatomy + CTA topology contract and documenting it as the implementation source of truth | UX / Architecture | Product + iOS lead | Now | None | Proposal no longer contains blocking decision branches for Workstream D |
| P1 | Simplify Workstream C row model: visible `Resolve` entry point, deletion confirmation, and either persistent resolved rows or no resolved chips | UI / UX | Product + iOS lead | Next | Platform matrix | Final stale-draft row has one clear action model with no transient-only ornamentation |
| P1 | Add preview fixtures and QA hooks for Dynamic Type, invalid forms, persistence failures, and stale-draft variants | UI / Architecture | iOS lead | Next | Workstream decisions complete | Section 7 evidence can be generated directly from preview files/UI tests |
| P2 | Extract or rename the dashboard validator/workflow before using it for planning copy parity | Architecture | Architecture lead | Later | Workstream A contract finalized | CI/tooling names and ownership boundaries reflect actual scope |

## 6. Execution Plan
- Now (0-2 weeks):
  - Split platform applicability by workstream and update metadata accordingly.
  - Rewrite Workstream A acceptance so it validates the full promised copy surface.
  - Choose and document the Workstream D iOS form contract.
- Next (2-6 weeks):
  - Refine Workstream C to a single coherent resolution model.
  - Add preview fixtures and UI-test hooks required to prove Workstreams B/C/D acceptance.
  - Prepare the planning copy contract/gate after the dictionary scope is finalized.
- Later (6+ weeks):
  - Generalize CI contract tooling across product areas if the team wants one shared validator family.
  - Revisit Android-specific parity only after the iOS-heavy workstreams land and real divergence remains.

## 7. Open Questions
- Should Workstream C preserve resolved rows long enough to justify state chips, or should the v1 scope be reduced to visible `Resolve` + confirmation only?
- Does the team want Workstream D to change Android goal-form layout at all, or only align error copy and accessibility semantics where gaps remain?
- Is the intent to create one generic product-copy contract framework, or only a planning-specific extension with minimal tooling change?
