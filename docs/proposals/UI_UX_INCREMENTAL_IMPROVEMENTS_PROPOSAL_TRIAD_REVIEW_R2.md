# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed: revised proposal `R1 -> R2`, current planning/form/stale-draft code, current preview coverage, and current shared component boundaries.
- Internet sources reviewed: Apple Design Tips, Apple HIG Menus, Android Compose guidance for text input, semantics, dialogs, and CFPB guidance on consumer understanding in finance.
- Xcode screenshots captured: refreshed compact planning, stale-plan row, and Edit Goal previews; Add Goal preview reused from same-day unchanged UI evidence.
- Remaining assumptions: copy parity should be feature-scoped, not blanket; UI code is unchanged from the first pass.

## 1. Executive Summary
- Overall readiness: Amber-Green
- Top 3 risks:
  1. Workstream A still defines cross-platform copy parity too globally for a proposal that now intentionally includes platform-specific workstreams.
  2. Workstream B is called iOS-only, but the row component it targets is still shared by iOS and macOS.
  3. The new row-level `Adjust` concept is not yet distinct enough from the existing top-level `Adjust` tab.
- Top 3 opportunities:
  1. Add one explicit isolation strategy for the shared iOS/macOS row component and the proposal becomes materially more implementation-ready.
  2. Scope the copy validator by feature/workstream and the new tooling contract becomes clean and defensible.
  3. Split previewable states from simulator-only dialog evidence and the QA contract becomes more executable.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 8.1 | 0 | 0 | 2 | 0 |
| UX (Financial) | 8.0 | 0 | 1 | 1 | 0 |
| iOS Architecture | 7.8 | 0 | 1 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [Medium] Row-level `Adjust` is ambiguous next to the existing top-level `Adjust` tab
  - Evidence: DOC-03, DOC-08, SCR-01, WEB-01
  - Why it matters: The proposal improves row simplification, but `Adjust` already names a primary planning tab. Reusing the same term for a row-level secondary action risks orientation loss: users may not know whether they are entering a per-goal surface or switching to the global planning tab.
  - Recommended fix: Either rename the row action to something more local (`Options`, `Edit`, `Goal Actions`) or explicitly define it as a row-scoped adjustment sheet and give that sheet its own title.
  - Acceptance criteria: The row-level action label is no longer ambiguous with the top-level planning tab, and the proposal names the destination surface explicitly.

- [Medium] The evidence contract still mixes previewable UI states with system-dialog states
  - Evidence: DOC-06, SCR-02, SCR-03
  - Why it matters: A real delete confirmation is a system alert, which is not as naturally validated through static preview fixtures as row anatomy or form-state visuals. Keeping them in one undifferentiated preview list weakens the QA contract.
  - Recommended fix: Keep row/form anatomy in the preview fixture list, and move destructive confirmation validation to simulator screenshots or UI tests.
  - Acceptance criteria: Section 6 clearly separates preview evidence from simulator/UI-test evidence, and delete-confirmation text is validated in the latter bucket.

### 3.2 UX Review Findings
- [High] Workstream A copy parity still conflicts with the proposal's platform-scoped feature model
  - Evidence: DOC-01, DOC-02, DOC-04, ASSUMP-02, WEB-06
  - Why it matters: The proposal now explicitly says some workstreams are iOS/macOS-only or iOS-only, but Workstream A still says CI should fail if a targeted planning/form string appears only on one platform path. That would either force Android to carry copy for non-Android features or make valid platform-specific strings look like contract failures.
  - Recommended fix: Change the copy contract from blanket platform parity to feature-scoped parity. Shared features must have parity; platform-specific features must be validated only on their target platforms and marked as such in the dictionary.
  - Acceptance criteria: `FINANCIAL_COPY_DICTIONARY.md` includes a scope column or equivalent marker per entry, and the validator enforces parity only where the feature matrix says parity is required.

- [Medium] Workstream B improves directionally, but it still needs one explicit compact-screen success scenario when stale drafts are present
  - Evidence: DOC-03, SCR-01, WEB-01
  - Why it matters: The proposal now documents collapse order and above-the-fold behavior when stale drafts are absent, but the stale-draft-present case is still mostly qualitative. On compact phones, that is exactly where hierarchy is most fragile.
  - Recommended fix: Add one target success statement for stale-draft-present compact layouts, for example which two surfaces must remain visible before scroll and what collapses first.
  - Acceptance criteria: Workstream B includes one measurable compact-iPhone acceptance statement for the stale-draft-present case, not only the stale-draft-absent case.

### 3.3 Architecture Review Findings
- [High] Workstream B still lacks an isolation plan for a shared iOS/macOS component
  - Evidence: DOC-03, DOC-07, QUESTION-01
  - Why it matters: The proposal now marks Workstream B as iOS-only, but `GoalRequirementRow` is still used by macOS planning layouts. Without an explicit split strategy, iOS-only implementation work will either leak onto macOS or force last-minute conditional layout logic into a shared component.
  - Recommended fix: Add one implementation boundary decision in the proposal:
    - either create an iOS-specific row wrapper/layout,
    - or add explicit platform-conditional layout branches inside `GoalRequirementRow`,
    - or change Workstream B scope to iOS + macOS intentionally.
  - Acceptance criteria: The proposal names the exact file/component boundary and expected macOS outcome before implementation starts.

- [Medium] Workstream D still needs one implementation note for keyboard-safe fixed bottom actions across both iOS form architectures
  - Evidence: DOC-05, DOC-09, SCR-03, SCR-04
  - Why it matters: The proposal now chooses a fixed bottom action contract, which is the right move, but `AddGoalView` and `EditGoalView` still use different scroll/layout primitives. Without a short implementation note, there is still delivery risk around keyboard avoidance and CTA visibility.
  - Recommended fix: Add one technical note that iOS uses `safeAreaInset(edge: .bottom)` or an equivalent shared bottom-action container for both form types, with explicit keyboard-visibility behavior.
  - Acceptance criteria: The proposal states how the fixed bottom region stays visible above the keyboard in both `Form` and custom scroll-stack forms.

- [Medium] Section 6 is stronger, but preview scaffolding remains a real prerequisite rather than a nice-to-have
  - Evidence: DOC-06, DOC-11
  - Why it matters: The document now correctly names the missing preview/test evidence, which is a real improvement. But because the fixtures do not yet exist, delivery still depends on honoring Phase 1 as a hard prerequisite.
  - Recommended fix: Mark Phase 1 as an explicit gate for entering Phase 2, not just an earlier phase in the sequence.
  - Acceptance criteria: The delivery plan states that UI implementation does not begin until the preview fixtures and test hooks listed in Section 6 exist.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Workstream A wants parity enforcement, while the proposal now intentionally includes platform-specific workstreams.
  - Tradeoff: Strong parity rules are useful for shared features, but incorrect when features are intentionally absent on one platform.
  - Decision: Enforce parity only for shared-scope entries and mark platform-specific copy explicitly in the dictionary/validator model.
  - Owner: Product + Architecture

- Conflict: Workstream B wants a simplified row action named `Adjust`, while the screen already has a top-level `Adjust` tab.
  - Tradeoff: Reusing one term sounds semantically neat, but it harms local/global navigation clarity.
  - Decision: Use distinct naming or explicitly scoped row-destination labeling.
  - Owner: Product + Design

- Conflict: Section 6 wants preview evidence for all states, while destructive confirmation is better proven in runtime UI tests.
  - Tradeoff: One evidence list is simpler, but it mixes static and runtime validation in a way that blurs test responsibility.
  - Decision: Split preview evidence from simulator/UI-test evidence.
  - Owner: QA + iOS lead

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Make Workstream A copy parity feature-scoped rather than blanket platform-scoped | UX / Architecture | Product + Architecture | Now | Platform matrix already present | Validator rules no longer conflict with iOS/macOS-only or iOS-only workstreams |
| P0 | Add an explicit isolation strategy for `GoalRequirementRow` so Workstream B can remain iOS-only without accidental macOS regression | Architecture | iOS lead | Now | None | Proposal names the exact component boundary and expected macOS behavior |
| P1 | Resolve the `Adjust` naming collision between the row-level action and the top-level planning tab | UI / UX | Product + Design | Next | Workstream B destination surface defined | Users can distinguish row actions from global planning navigation |
| P1 | Split preview evidence from simulator/UI-test evidence in Section 6 | UI / Architecture | QA + iOS lead | Next | None | QA contract is executable without abusing preview fixtures for system alerts |
| P1 | Add one keyboard-avoidance implementation note for the fixed bottom iOS form action region | Architecture | iOS lead | Next | Chosen iOS contract already locked | Proposal defines how CTA visibility is preserved in both iOS form architectures |

## 6. Execution Plan
- Now (0-2 weeks):
  - Scope Workstream A parity rules by feature/workstream rather than by a blanket shared rule.
  - Lock the `GoalRequirementRow` isolation strategy for iOS-only Workstream B.
- Next (2-6 weeks):
  - Rename or redefine the row-level `Adjust` destination.
  - Split preview vs runtime evidence responsibilities in Section 6.
  - Add the keyboard-safe bottom-action implementation note for iOS forms.
- Later (6+ weeks):
  - Re-evaluate whether any Android parity work remains after iOS implementation lands and the shared copy contract is operational.

## 7. Open Questions
- Should the row-level action keep the word `Adjust`, or should the proposal rename it now to avoid the tab collision?
- Does the team want to keep Workstream B strictly iOS-only, or is it acceptable to make the new row contract a shared iOS/macOS planning row?
