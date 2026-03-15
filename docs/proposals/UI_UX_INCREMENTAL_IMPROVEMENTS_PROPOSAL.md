# UI/UX Incremental Improvements Proposal

> Audit mapping: issues #4, #5, #6, #8
> Review baseline: `docs/proposals/UI_UX_INCREMENTAL_IMPROVEMENTS_PROPOSAL_TRIAD_REVIEW_R3.md`
> Evidence pack: `docs/proposals/UI_UX_INCREMENTAL_IMPROVEMENTS_PROPOSAL_EVIDENCE_PACK_R3.md`

| Metadata | Value |
|---|---|
| Status | Revised after triad review R3 |
| Last Updated | 2026-03-15 |
| Platform | Workstream-scoped |
| Scope | Copy clarity, row density, stale draft context, form feedback |

---

## 0) Goals

- Reduce financial copy confusion in planning and goal flows.
- Reduce visual and cognitive density in monthly planning on compact iPhone layouts.
- Make stale draft resolution understandable and low-risk.
- Make goal-form validation and save failures visible, actionable, and testable.

## 0.1) Non-goals

- No full redesign of Goal Dashboard.
- No Android stale-draft feature invention in this proposal.
- No data-model migration for stale-draft goal-name lookup.
- No cross-product validator expansion hidden under a dashboard-specific tool name.

## 0.2) Decisions Locked After Review R3

1. Workstream scope is platform-specific, not blanket `iOS + Android` for every stream.
2. Workstream C v1 uses one visible `Resolve` entry point plus explicit delete confirmation.
3. Workstream C does not ship transient resolved-state chips in v1.
4. Workstream D chooses one iOS contract now:
   fixed bottom action area with tappable primary save, inline field errors, and blocking summary near the CTA.
5. Android is not forced into the iOS form layout contract.
6. Planning copy parity is enforced through a planning-specific or generic copy validator, not by silently extending Goal Dashboard tooling.
7. Workstream A parity is feature-scoped:
   shared entries require parity across declared platforms, platform-specific entries validate only on their declared targets.
8. Workstream B remains iOS-only by introducing an iOS-specific compact row wrapper; macOS keeps the current shared row layout in this proposal.
9. The row-level secondary action is `Goal Actions`, not `Adjust`, and opens a row-scoped sheet titled `Goal Actions`.
10. Delete confirmation evidence is runtime-only and does not live in the static preview fixture list.
11. The fixed bottom iOS form action region stays keyboard-safe through `safeAreaInset(edge: .bottom)` or an equivalent shared container.
12. Workstream B preview evidence validates both the new iOS compact wrapper and the unchanged shared row.
13. The normalized `not applied` wording is `Budget saved, not applied to this month yet`.

---

## 1) Platform Matrix

| Workstream | Target Platforms | Non-target Platforms | Change Type |
|---|---|---|---|
| A. Financial Copy Clarity | iOS, Android, macOS where targeted copy exists | None | Feature-scoped copy contract |
| B. Goal Requirement Row Simplification | iOS | Android, macOS | iOS implementation |
| C. Stale Draft Context | iOS, macOS | Android | iOS/macOS implementation |
| D. Form Validation and Save Errors | iOS | Android layout no-op, macOS deferred | iOS implementation plus Android parity review of copy/error surfacing |

Notes:

1. Android already has visible monthly-row actions and does not require Workstream B parity work from this proposal.
2. Android currently has no stale-draft planning surface; Workstream C is intentionally not extended there.
3. Android goal forms remain on their current layout path unless a later proposal proves a real product need to change layout topology.
4. Workstream A dictionary entries declare whether they are `shared` or `platform-specific`; only `shared` entries require parity across multiple platform paths.
5. Workstream B stays iOS-only by introducing an iOS-specific compact row wrapper in `PlanningView`; macOS continues using the current shared `GoalRequirementRow` contract unchanged.

---

## 2) Workstream A - Financial Copy Clarity (issue #4)

### Target platforms

- iOS
- Android
- macOS where targeted planning/form copy exists

### Problems

- Terms like `not applied`, `needs recalculation`, and `close month` are internal and ambiguous.
- Targeted planning and form copy is currently split between catalogs and inline literals.
- The current acceptance shape is too narrow to prove the real audited copy surface.

### Proposal

1. Introduce `docs/copy/FINANCIAL_COPY_DICTIONARY.md` as the source of truth for targeted planning/form language.
2. Normalize user-facing language for the targeted scope:
   - `not applied` -> `Budget saved, not applied to this month yet`
   - `needs recalculation` -> `Goals changed, review this plan`
   - `close month` -> `Finish {month}`
3. Require every targeted copy entry in scope to include scope metadata in `FINANCIAL_COPY_DICTIONARY.md`:
   - `shared` or `platform-specific`,
   - declared target platforms,
   - copy key and approved wording.
4. Require every targeted copy entry to map to the designated copy path for each declared target platform.
5. Eliminate unmanaged inline literals from targeted planning/form files once the dictionary is introduced.
6. Add one-line explanatory copy for each targeted risk/health status in scope.

### Tooling contract

1. Do not extend `validate_goal_dashboard_contracts.py` directly for this work.
2. Introduce a new validator boundary:
   - preferred: `scripts/validate_copy_contracts.py`,
   - acceptable alternative: rename the existing validator family before any planning scope is added.
3. CI workflow naming must reflect planning/form copy scope rather than Goal Dashboard scope.

### Acceptance criteria

1. CI validates the full targeted audited surface:
   - shared entries on every declared platform path,
   - platform-specific entries only on their declared target paths,
   - zero unmanaged inline literals in the targeted planning/form files.
2. CI fails if a targeted planning/form string is not represented in `docs/copy/FINANCIAL_COPY_DICTIONARY.md` with scope metadata and declared target platforms.
3. CI fails if a shared entry is missing on any declared platform path.
4. The validator/workflow name, inputs, and ownership match planning/form copy scope and feature-scoped parity rules.

---

## 3) Workstream B - Goal Requirement Row Simplification (issue #5)

### Target platforms

- iOS only

### Problems

- Requirement rows contain too many controls and status elements at once.
- Above-the-fold planning layout is overloaded by stacked header elements before the first row appears.
- The current proposal addressed row density but not the full compact-screen stack.
- Reusing `Adjust` at row level conflicts with the existing top-level planning tab label.

### Proposal

1. Default row anatomy on compact iPhone:
   - goal name,
   - monthly amount,
   - deadline/risk signal,
   - progress summary,
   - one visible secondary entry point: `Goal Actions`.
2. The row-level secondary action opens a row-scoped sheet titled `Goal Actions`.
3. Move lock/skip/custom-amount actions into the `Goal Actions` surface.
4. Expanded row state appears only on explicit user action.
5. Implementation boundary for iOS-only scope:
   - `Views/Planning/GoalRequirementRow.swift` remains the shared row contract used by macOS,
   - `PlanningView` introduces an iOS-specific compact wrapper `CompactGoalRequirementRow` for iPhone layouts that composes the shared row data and presents the `Goal Actions` surface,
   - macOS keeps the current shared `GoalRequirementRow` layout unchanged in this proposal.
6. Define a compact iPhone layout contract for the full stack above the first row:
   - priority 1: stale-draft banner, only when present,
   - priority 2: tab selector,
   - priority 3: `BudgetHealthCard`,
   - priority 4: compact consolidated stats header.
7. Collapse order on small screens:
   - first reduce consolidated stats density,
   - then switch to collapsed header strip,
   - never stack both a full header and collapsed strip in the same visible band longer than the transition state.
8. When stale drafts are absent, the first goal row must be partially visible without scrolling on the target compact iPhone layout.
9. When stale drafts are present on compact iPhone, `StaleDraftBanner` remains visible and the first goal row header remains partially visible before scrolling; the consolidated stats header collapses before `BudgetHealthCard` expands beyond one compact band.

### Acceptance criteria

1. Compact iPhone layout shows the first goal row partially above the fold when stale drafts are absent.
2. When stale drafts are present on compact iPhone, `StaleDraftBanner` and the first goal row header remain visible before scrolling, and consolidated stats collapse before `BudgetHealthCard` expands beyond one compact band.
3. The row-level action label is `Goal Actions` and opens a row-scoped sheet titled `Goal Actions`.
4. Default requirement row contains one visible primary information cluster and no always-visible secondary controls beyond `Goal Actions`.
5. The proposal names the iOS-only implementation boundary: `PlanningView` uses `CompactGoalRequirementRow`, while macOS retains the current shared `GoalRequirementRow`.
6. The row contract is proven by preview fixtures and UI screenshots for compact iPhone layouts.

---

## 4) Workstream C - Stale Draft Context (issue #6)

### Target platforms

- iOS
- macOS

### Problems

- Stale draft rows may not communicate enough context about which goal/month is being resolved.
- Destructive resolution needs clearer confirmation language.
- The prior proposal added resolved-state chips that would disappear too quickly to carry product value.

### Proposal

1. Every stale draft row must show:
   - goal name,
   - month,
   - one visible `Resolve` entry point.
2. V1 resolution model:
   - visible `Resolve` action,
   - explicit delete confirmation including month + goal name,
   - no transient resolved-state chips.
3. If the user resolves the row as completed/skipped, the row may disappear immediately after resolution because no resolved-state chip needs to remain visible.
4. Goal-name lookup contract:
   - `PlanningView` builds a `[UUID: String]` map once per stale-draft query result,
   - passes that map into `StaleDraftBanner`,
   - logs one warning per unresolved `goalId`,
   - falls back to `Unknown goal` when name resolution fails.
5. No model migration is introduced for this lookup path.

### Acceptance criteria

1. No stale draft row renders without month context.
2. No stale draft row renders without goal-name text or the explicit fallback `Unknown goal`.
3. V1 stale draft rows do not render resolved-state chips.
4. Delete confirmation text includes goal name and month.
5. Goal-name lookup is batched once per screen render path and does not require per-row fetches.

---

## 5) Workstream D - Form Validation and Save Errors (issue #8)

### Target platforms

- iOS implementation
- Android parity review of copy/error surfacing only

### Problems

- Disabled save creates discoverability failure on iOS.
- Save failures are not surfaced consistently as actionable recovery states.
- The previous proposal left layout and CTA topology unresolved, which blocked implementation and testing.

### Chosen iOS contract

1. iOS goal forms use a fixed bottom action area.
2. The primary save CTA remains visible in that area throughout form entry.
3. The primary save CTA is tappable; invalid tap triggers validation instead of silent non-action.
4. Blocking summary appears in the same bottom action region, directly above the CTA.
5. Inline field errors render under each failing field.
6. First invalid field receives focus after invalid submit.
7. Persistence failure renders a retry-capable error state in the bottom action region, not a silent console-only failure.

### Invalid-to-success flow

1. User taps `Save`.
2. If invalid:
   - inline errors appear under failing fields,
   - blocking summary appears above the fixed CTA,
   - focus moves to the first invalid field,
   - screen scrolls just enough to reveal the focused field if needed.
3. After correction:
   - summary updates or disappears,
   - save remains available in the same location.
4. If persistence fails after a valid submit:
   - the bottom action region shows a clear error message,
   - `Retry` is visible,
   - the user can keep editing without losing entered values.

### Android scope

1. Android keeps its current form layout topology.
2. Android parity review in this proposal is limited to:
   - summary/error copy consistency where applicable,
   - accessibility semantics for validation and save-error feedback,
   - no forced migration to the iOS fixed-bottom CTA contract.

### Affected iOS areas

1. `AddGoalView`
2. `EditGoalView`
3. Shared validation/error components introduced for those forms
4. Related previews and UI tests for invalid and persistence-error states

### Implementation note

1. `AddGoalView` and `EditGoalView` host the fixed bottom action region through a shared bottom-action container using `safeAreaInset(edge: .bottom)` or an equivalent shared abstraction.
2. The bottom action region stays above the keyboard while form content scrolls independently underneath it.
3. Keyboard appearance must never hide the primary CTA or the blocking summary in either `Form`-based or custom scroll-stack goal forms.

### Acceptance criteria

1. iOS goal forms use one documented fixed-bottom action contract.
2. Invalid save attempt always produces visible feedback:
   - inline field errors,
   - blocking summary near CTA,
   - focus movement to the first invalid field.
3. Persistence failure is visible and retryable; no silent fail path remains.
4. The fixed bottom action region remains visible above the keyboard in both `AddGoalView` and `EditGoalView`.
5. Android deltas are documented separately from the iOS implementation path.

---

## 6) Preview and QA Evidence Contract

The proposal is not implementation-ready unless the required preview/test evidence is planned explicitly.

### Required preview fixtures

1. `CompactGoalRequirementRow` default compact state
2. `CompactGoalRequirementRow` Dynamic Type accessibility variant
3. `GoalRequirementRow` shared-row continuity state for macOS
4. `StalePlanRow` unresolved state
5. `AddGoalView` invalid-form state
6. `AddGoalView` persistence-error state
7. `EditGoalView` invalid-form state
8. `EditGoalView` persistence-error state

### Required simulator and UI-test evidence

1. `StalePlanRow` delete-confirmation text and destructive action wording
2. Focus movement after invalid save
3. Bottom action summary visibility
4. Retry path after persistence failure
5. Compact planning above-the-fold layout assertions for the first row, with and without stale drafts

### Acceptance criteria

1. Preview files exist for every previewable row/form state listed above before UI implementation is considered complete, including `CompactGoalRequirementRow` for iPhone behavior and `GoalRequirementRow` for macOS shared-row continuity.
2. Simulator screenshots or UI tests exist for runtime-only interactions, including destructive confirmation text.
3. UI test hooks exist for every stateful interaction listed above.
4. Dynamic Type accessibility coverage is present for at least one row and one form flow.

---

## 7) Delivery Plan

### Phase 0 - Contracts first

1. Add the platform matrix to this proposal and freeze scope per workstream.
2. Create the copy-contract tooling plan and name boundary.
3. Lock Workstream A feature-scoped parity rules and dictionary metadata before validator work starts.
4. Lock the Workstream B iOS-specific compact row wrapper boundary before feature work starts.
5. Lock the Workstream D iOS layout contract and keyboard-safe bottom-action note in this proposal or a linked ADR before feature work starts.

### Phase 1 - Evidence scaffolding (hard gate)

1. Add missing preview fixtures for Workstreams B, C, and D, including both `CompactGoalRequirementRow` and `GoalRequirementRow` shared-row continuity previews.
2. Add UI-test hooks for invalid-form, persistence-error, and compact planning layout assertions.
3. Phase 2 does not begin until every preview fixture and runtime evidence item listed in Section 6 exists.

### Phase 2 - Workstream implementation

1. Implement Workstream A copy dictionary and targeted copy migration.
2. Implement Workstream B compact-row simplification and compact-stack collapse behavior.
3. Implement Workstream C stale-draft context rendering and resolution flow.
4. Implement Workstream D iOS form validation/save-error contract.

### Phase 3 - Verification

1. Run preview review against the defined fixture list.
2. Run targeted UI tests for planning rows, stale drafts, and iOS goal forms.
3. Run copy-contract CI checks across the full targeted surface.

---

## 8) Cross-workstream Acceptance Criteria

1. Each workstream header explicitly lists target platforms, non-target platforms, and intended change type.
2. Planning/form copy parity is feature-scoped: shared entries require parity across declared platforms, while platform-specific entries validate only on their declared targets.
3. No planning/form copy contract depends on a dashboard-specific validator name or workflow boundary.
4. No stale-draft row renders without month and goal context.
5. No stale-draft row ships with transient resolved-state chips in v1.
6. Workstream B names the iOS-only implementation boundary and leaves the current macOS shared row contract unchanged.
7. iOS compact planning layout has a documented above-the-fold priority order for both stale-draft-absent and stale-draft-present states.
8. The row-level action label and destination are distinct from the top-level planning tab.
9. iOS goal forms use one fixed-bottom action contract and no unresolved CTA topology branch remains.
10. The bottom action region stays visible above the keyboard in both `AddGoalView` and `EditGoalView`.
11. Save errors are always visible to the user and provide recovery.
12. Preview and UI-test evidence required by Section 6 exists before the feature set is called complete.
13. Workstream B preview evidence targets the new `CompactGoalRequirementRow` surface and also preserves shared `GoalRequirementRow` continuity evidence for macOS.

---

## 9) Open Questions Resolved

1. Should Workstream C keep resolved chips?
   - No. V1 uses `Resolve` plus confirmation and no resolved-state chips.
2. Should Workstream D change Android form layout?
   - No. This proposal standardizes iOS and limits Android to parity review of copy/error surfacing.
3. Should planning copy parity reuse Goal Dashboard validator naming?
   - No. Use a planning-specific or generic copy validator boundary instead.
4. Should Workstream A enforce blanket cross-platform parity for every string?
   - No. The dictionary marks entries as `shared` or `platform-specific`, and the validator enforces parity only for shared entries.
5. Should Workstream B become a shared iOS/macOS row redesign?
   - No. This proposal keeps Workstream B iOS-only through an iPhone-specific compact wrapper in `PlanningView`; macOS keeps the current shared `GoalRequirementRow`.
6. Should the row-level action keep the word `Adjust`?
   - No. The row action is `Goal Actions` and opens a row-scoped sheet titled `Goal Actions`.
7. Should delete confirmation remain in the preview fixture list?
   - No. Delete confirmation is validated through simulator screenshots or UI tests, not static previews.
8. Should Section 6 name only the wrapper preview or both wrapper and shared-row continuity?
   - Both. `CompactGoalRequirementRow` proves the new iPhone behavior, and `GoalRequirementRow` preview coverage protects unchanged macOS continuity.
9. Should the `not applied` wording be tightened before the dictionary is frozen?
   - Yes. The proposal uses `Budget saved, not applied to this month yet` as the normalized wording to carry into dictionary review.
