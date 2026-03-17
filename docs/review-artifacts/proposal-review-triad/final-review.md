# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed: `DOC-01` through `DOC-07`
- Internet sources reviewed: `WEB-01` through `WEB-06`
- Xcode screenshots captured: `SCR-01` through `SCR-06`
- Remaining assumptions:
  - The requested proposal path is stale; `docs/VISUAL_SYSTEM_UNIFICATION.md` is the source-of-truth used for review.
  - Existing simulator/runtime captures are valid evidence because they were produced from checked-in visual-state bundles and live Xcode previews.

## 1. Executive Summary
- Overall readiness: **Amber**
- Top 3 risks:
  1. The proposal does not yet define a shell-level unification contract, so dashboards/settings can remain visually legacy while component cards are tokenized.
  2. Release certification artifacts are passing even when the state coverage report omits required fields, which weakens gate trust.
  3. Performance headroom is tight enough that any small regression could push future waves over budget.
- Top 3 opportunities:
  1. Add explicit shell-level acceptance criteria for planning, dashboard, and settings routes.
  2. Make state coverage schema validation fail on empty required-state/component outputs.
  3. Add a performance guardband so promotion requires more than a bare pass.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 6 | 0 | 0 | 1 | 0 |
| UX (Financial) | 6 | 0 | 0 | 1 | 0 |
| iOS Architecture | 5 | 0 | 1 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [Medium] Shell-level visual contract is missing
  - Evidence: `DOC-02`, `SCR-03`, `SCR-04`, `SCR-05`, `SCR-06`
  - Why it matters: The proposal scopes release-blocking flows, but the live previews still show a legacy dashboard shell while other screens are tokenized. That means teams can ship "unified" cards inside inconsistent screens, which is visually fragmented and weakens the Apple-style calm-surface goal.
  - Recommended fix: Add a shell-level acceptance contract for each release-blocking route: navigation chrome, spacing, empty-state treatment, material usage, and title hierarchy. If a shell is intentionally out of scope, say so explicitly and exclude it from release-blocking claims.
  - Acceptance criteria: Every release-blocking route has a shell snapshot baseline, and no route can retain legacy shell styling on a promoted wave.

### 3.2 UX Review Findings
- [Medium] Rollout UX does not explain legacy/mixed surfaces to users
  - Evidence: `DOC-02`, `DOC-07`, `SCR-04`, `SCR-06`
  - Why it matters: The proposal says migration should happen by complete user-flow slices to avoid mixed-language UX, but it does not specify what users see if a partially migrated screen or legacy shell is still present. In a finance app, unexplained visual inconsistency reduces trust in the numbers and in the app's state.
  - Recommended fix: Add explicit rollout UX rules for transitional surfaces: either block release on any legacy shell surface, or show a clear, consequence-aware explanation banner/state that tells users the screen is temporary and what action is available.
  - Acceptance criteria: No promoted wave ships with an unlabelled legacy shell, and any transitional surface includes a deterministic explanation and recovery path.

### 3.3 Architecture Review Findings
- [High] State coverage artifact passes while omitting required fields
  - Evidence: `DOC-02`, `DOC-03`, `DOC-05`
  - Why it matters: The proposal states that operational truth is controlled by artifacts, not prose, but the state coverage report is green with empty `Required states` and `Release components` fields. That makes the gate look complete when the structured evidence is actually incomplete.
  - Recommended fix: Make the state coverage report schema non-empty and fail validation when required states or release components are missing. Treat empty coverage fields as a release-blocking error.
  - Acceptance criteria: The report always contains populated required-state and component lists for each release-blocking component, and validation fails if either field is empty.

- [Medium] Performance gate has too little headroom
  - Evidence: `DOC-02`, `DOC-04`
  - Why it matters: Wave 1 passes, but the measured `8.04%` P95 regression is already close to the `10%` ceiling, and the jank delta is also close to its cap. The proposal does not require a guardband, so future waves could pass once and regress on the next small change.
  - Recommended fix: Add a guardband requirement before promotion, such as a minimum percentage of headroom under both thresholds or a trend review when a metric exceeds a defined fraction of the ceiling.
  - Acceptance criteria: Each wave must document headroom versus both performance ceilings, and promotion is blocked when the guardband is not met.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Stronger visual polish can drift into shell inconsistency or extra runtime cost.
  - Tradeoff: Liquid Glass-like material usage should stay calm and tokenized on finance-critical surfaces, but the shell contract must still be explicit enough to prevent mixed legacy/new styles.
  - Decision: Keep glass restrained on content surfaces and move the review standard up to the shell level, not just the card level.
  - Owner: Mobile Platform Lead with Design Lead approval.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Fail state coverage when required-state/component fields are empty | Architecture | Mobile Platform Team | Now | Schema/validator update | Empty coverage reports cannot pass certification |
| P1 | Add shell-level acceptance criteria for planning/dashboard/settings routes | UI | Design Lead + Mobile Platform Lead | Now | Route snapshot definitions | No promoted wave retains legacy shell styling |
| P2 | Add transitional rollout UX rules for mixed/legacy surfaces | UX | Product Design | Next | Shell-level contract | Users either see a clear explanation or no legacy surface ships |
| P3 | Add a performance guardband to promotion policy | Architecture | Mobile Platform Lead | Next | Updated release-gate policy | Each wave reports explicit headroom under both ceilings |

## 6. Execution Plan
- Now (0-2 weeks):
  - Fix the state coverage report so empty required-state/component output fails validation.
  - Add route-level shell acceptance criteria and snapshot baselines for planning, dashboard, and settings.
- Next (2-6 weeks):
  - Define transitional rollout UX rules for legacy or partially migrated surfaces.
  - Add a performance guardband policy and surface headroom in release reports.
- Later (6+ weeks):
  - Tighten shell-level visual consistency across all finance-critical flows and fold the new acceptance criteria into CI gate documentation.

## 7. Open Questions
- Should shell-level styling be considered part of the release-blocking proposal, or is it intentionally deferred?
- Is the empty state coverage report a bug in report generation or a missing validation requirement?
- What guardband is acceptable for performance promotion relative to the current 10% / 2pp ceilings?
