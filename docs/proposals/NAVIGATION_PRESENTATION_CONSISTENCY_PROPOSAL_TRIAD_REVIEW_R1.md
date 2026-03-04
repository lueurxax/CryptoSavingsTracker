# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed: 8 (see `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL_EVIDENCE_PACK_R1.md`)
- Internet sources reviewed: 7
- Xcode screenshots captured: 4 (large + compact, modal-open + post-cancel states)
- Remaining assumptions:
  - No explicit PRD/KPI document was provided beyond the proposal.
  - iPad-specific policy is currently unspecified and treated as open scope.

## 1. Executive Summary
- Overall readiness: Amber
- Top 3 risks:
  1. The proposal is directionally correct but not executable: it lacks a concrete migration inventory, ownership, and sequencing.
  2. Acceptance criteria are binary and incomplete (iOS-focused, API-count focused), so UX consistency and trust outcomes are not verifiable.
  3. Modal policy is underspecified for real states (keyboard-heavy forms, unsaved edits, compact layouts, async save/validation paths).
- Top 3 opportunities:
  1. Android already has a centralized `NavHost` baseline, enabling faster parity gains if iOS migration is operationalized.
  2. iOS inconsistencies are measurable today (`NavigationView`/`ActionSheet` inventory), making rollout progress trackable.
  3. The proposal can become implementation-ready with a small set of concrete artifacts: migration table, modal matrix, and CI gates.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 5 | 0 | 2 | 2 | 0 |
| UX (Financial) | 5 | 0 | 2 | 2 | 0 |
| iOS Architecture | 4 | 1 | 2 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Navigation/presentation visual spec is missing implementation detail
  - Evidence: DOC-01, DOC-03, SCR-01, SCR-03, WEB-01
  - Why it matters: Policy names components (`NavigationStack`, `.sheet`, `.fullScreenCover`) but does not define presentation anatomy (title mode, button hierarchy, detents, dismiss affordances), so teams can still produce visually divergent flows.
  - Recommended fix: Add a UI contract table per presentation type with exact rules: `title style`, `leading/trailing controls`, `CTA priority`, `detents`, `dismiss behavior`, `compact overflow behavior`.
  - Acceptance criteria: Each migrated flow references exactly one contract row; screenshot QA passes for compact + large devices.

- [High] Modal decision matrix is too abstract for production states
  - Evidence: DOC-01, DOC-06, SCR-01, SCR-03
  - Why it matters: “lightweight -> sheet / critical -> fullScreenCover” is insufficient when the same flow changes style by runtime condition (e.g., UI test branch), which creates presentation inconsistency and trust issues.
  - Recommended fix: Replace the binary rule with a decision matrix keyed by user intent and risk (`quick pick`, `multi-step commit`, `destructive confirmation`, `keyboard-heavy numeric input`, `blocking validation`).
  - Acceptance criteria: 100% modal call-sites are mapped to a decision ID and audited in PR review.

- [Medium] Transition and dismissal behavior is not standardized
  - Evidence: SCR-01, SCR-02, SCR-03, SCR-04, WEB-03
  - Why it matters: In compact states, action density and keyboard overlap increase friction; without explicit transition/dismiss rules, cancel/save flows feel inconsistent.
  - Recommended fix: Define a transition policy (`interactiveDismissDisabled` rules, keyboard dismissal affordance, animation timing), then enforce with UI tests for open/edit/cancel/return.
  - Acceptance criteria: No flow loses user orientation after dismiss; keyboard exit is deterministic and discoverable.

- [Medium] Platform fidelity guardrails are too weak for legacy cleanup
  - Evidence: DOC-04, DOC-05, WEB-01
  - Why it matters: Existing legacy API usage is material; “no new usage” still allows long-term mixed visual behavior.
  - Recommended fix: Add migration checkpoints with visible burn-down targets (per module) rather than only forward-looking bans.
  - Acceptance criteria: Module-level baseline decreases every release until zero active legacy usage.

### 3.2 UX Review Findings
- [High] Acceptance criteria do not measure user outcomes
  - Evidence: DOC-02, DOC-03, DOC-04
  - Why it matters: API replacement alone does not guarantee better user understanding or lower friction in finance-critical flows.
  - Recommended fix: Add outcome metrics: completion rate for budget-edit flow, cancel-to-retry rate, time-to-success, and error recovery rate.
  - Acceptance criteria: Metrics are logged and show improvement release-over-release in planning and goal-edit journeys.

- [High] Unsaved-change and cancellation semantics are undefined
  - Evidence: DOC-01, SCR-01, SCR-02, SCR-03, SCR-04
  - Why it matters: Financial planning actions require explicit trust boundaries; users must know whether data is saved, discarded, or partially applied when dismissing.
  - Recommended fix: Add a mandatory discard confirmation pattern for dirty forms and explicit post-cancel state messaging when risk remains unresolved.
  - Acceptance criteria: UI tests cover dirty cancel flow with explicit choice (`Keep Editing` / `Discard`), and users never encounter silent state loss.

- [Medium] Cross-platform parity is stated but user journey parity is not defined
  - Evidence: DOC-01, DOC-07, WEB-04, WEB-05
  - Why it matters: Android already has centralized navigation, but proposal does not define which journeys must behave identically across platforms.
  - Recommended fix: Define parity on journey level (goal create/edit, monthly budget adjust, destructive delete confirmation) with expected modal/dialog behavior per platform.
  - Acceptance criteria: Parity checklist passes for the top 5 recurring flows on iOS and Android.

- [Medium] Accessibility requirements are implied, not contractually specified
  - Evidence: DOC-01, SCR-03, WEB-03
  - Why it matters: Compact screenshots show dense controls; without explicit accessibility criteria, regressions are likely.
  - Recommended fix: Attach an accessibility section to the proposal (touch target min size, non-color cues, VoiceOver labels for primary actions, dynamic type overflow policy).
  - Acceptance criteria: Accessibility checklist is part of release gate for each migrated module.

### 3.3 Architecture Review Findings
- [Critical] Migration governance is missing (inventory, owner, and target date)
  - Evidence: DOC-02, DOC-03, DOC-04, DOC-05
  - Why it matters: Current iOS baseline contains broad legacy usage. Without explicit ownership and sequencing, migration will stall and policy will remain aspirational.
  - Recommended fix: Add a migration ledger (`file`, `legacy API`, `owner`, `target release`, `status`) and make it part of weekly engineering review.
  - Acceptance criteria: Ledger exists and active legacy usage reaches zero for agreed scope by target release.

- [High] CI enforcement is underspecified
  - Evidence: DOC-02, DOC-04
  - Why it matters: Proposal says “add lint script” but not where it runs, what it fails on, or how allowlists are managed (e.g., previews/tests).
  - Recommended fix: Define exact CI checks and script ownership; include allowlist policy and failure messaging.
  - Acceptance criteria: CI fails on forbidden APIs in active source paths and reports actionable file/line output.

- [High] Target iOS navigation architecture is ambiguous (local stacks vs coordinator path)
  - Evidence: DOC-01, DOC-08
  - Why it matters: Both root stack and coordinator abstractions exist; without a canonical pattern, teams may continue mixing approaches.
  - Recommended fix: Decide and document one canonical ownership model for route state (`feature-local` vs `app coordinator`) and where exceptions are allowed.
  - Acceptance criteria: New navigation work uses one documented pattern; architectural review rejects mixed ownership unless exception is approved.

- [Medium] Rollout safety and rollback controls are absent
  - Evidence: DOC-03
  - Why it matters: Broad navigation migration can regress key flows; no rollback or feature-flag strategy is currently defined.
  - Recommended fix: Add phased rollout with kill-switch scope per module (`planning`, `goals`, `dashboard`) and release health checkpoints.
  - Acceptance criteria: Each wave can be disabled independently without emergency patching.

- [Medium] Android section is policy-light relative to current maturity
  - Evidence: DOC-07, WEB-04, WEB-05
  - Why it matters: Android already satisfies part of the proposal; remaining gaps (modal parity, test matrix) are not explicitly tracked.
  - Recommended fix: Reframe Android section as “parity hardening” with explicit deliverables instead of generic policy restatement.
  - Acceptance criteria: Android parity tasks are listed with owners and merged into the same migration board.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Strict consistency vs flow-specific UX nuance.
  - Tradeoff: Overly rigid modal rules can degrade task efficiency for specific flows.
  - Decision: Keep one global decision matrix but allow documented exceptions with rationale and sunset date.
  - Owner: Product Design Lead + Mobile Platform Lead.

- Conflict: Fast cleanup vs release safety.
  - Tradeoff: Large migration in one wave risks regressions in finance-critical screens.
  - Decision: Ship by module waves with kill switches and explicit go/no-go criteria.
  - Owner: Engineering Manager.

- Conflict: CI strictness vs developer throughput.
  - Tradeoff: Hard-fail lint can block velocity if preview/test code is not scoped.
  - Decision: Fail hard on active source paths; maintain explicit allowlist for preview/test-only code.
  - Owner: Mobile Platform Team.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Create migration ledger for all legacy iOS navigation/presentation call-sites | Architecture | iOS Lead | Now | Baseline inventory (`rg` report) | 100% call-sites assigned owner + target release |
| P0 | Publish executable modal decision matrix (with examples and exceptions) | UI/UX | Product Designer + iOS Lead | Now | Flow taxonomy workshop | 100% modal call-sites mapped to decision ID |
| P0 | Implement CI gate for forbidden APIs in active paths | Architecture | Mobile Platform Team | Now | Script + allowlist policy | CI blocks new forbidden usages with file/line output |
| P1 | Define unsaved-change and cancel recovery pattern for financial forms | UX | UX Lead | Next | Modal matrix | Dirty-cancel UI tests pass across top 3 forms |
| P1 | Add journey-level cross-platform parity checklist | UX/Architecture | iOS + Android Leads | Next | Updated proposal scope | Top 5 journeys pass parity review on both platforms |
| P1 | Add accessibility contract for navigation/presentation surfaces | UX/UI | Accessibility Champion | Next | UI contract table | Touch target/VoiceOver/dynamic type checks pass on migrated flows |
| P2 | Add module-level feature flags for rollout safety | Architecture | Engineering Manager | Later | Build config support | Each migration wave has reversible kill switch |
| P2 | Reassess architecture model (coordinator vs local stacks) and codify standard | Architecture | Principal iOS Engineer | Later | ADR approval | All new route ownership follows approved ADR |

## 6. Execution Plan
- Now (0-2 weeks):
  - Build migration ledger from current inventory and assign owners.
  - Publish v1 modal decision matrix with concrete examples from planning/goals/dashboard.
  - Add CI lint script with active-path scope and preview/test allowlist.
- Next (2-6 weeks):
  - Migrate highest-risk iOS modules (`Planning` -> `Dashboard` -> `Goals`) using the matrix.
  - Add dirty-form cancel semantics and recovery copy.
  - Validate cross-platform parity for top recurring flows and enforce accessibility checklist.
- Later (6+ weeks):
  - Finalize architecture ADR for route ownership and coordinator usage.
  - Introduce module-level rollout toggles and observability for navigation regressions.
  - Complete legacy API elimination and remove temporary allowlists.

## 7. Open Questions
- Should preview-only `NavigationView` wrappers be allowed temporarily, or migrated in the same wave as active code?
- Is iPad regular-width behavior in scope for this proposal revision, or a follow-up proposal?
- Which owner is accountable for cross-platform parity sign-off before release?
- What are the release-blocking UX metrics for this initiative (completion rate, cancel churn, recovery success)?
