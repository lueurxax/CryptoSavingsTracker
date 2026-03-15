# UI/UX Incremental Improvements Proposal

> Incremental UI/UX improvements for copy clarity, row density, stale draft context, and form feedback.

Audit mapping: issues #4, #5, #6, #8

| Metadata | Value |
|----------|-------|
| Status | 📋 Planning |
| Last Updated | 2026-03-14 |
| Platform | iOS, Android |
| Audience | Developers |
| Scope | Copy clarity, row density, stale draft context, form feedback |

macOS scope: `macOSPlanningView` and `macOSControlsPanel` render the same `GoalRequirementRow` and `StaleDraftBanner` components as iOS. Workstreams B and C apply to macOS with no layout exceptions unless noted. Workstream D applies to all form sheets that are shared across platforms. A follow-up ticket should be filed to audit `macOSControlsPanel` budget health copy under Workstream A separately, as it uses a distinct layout surface.

---

## 1) Goals

- Reduce financial copy confusion.
- Improve scanability in goal requirement rows and the planning screen header.
- Make stale draft resolution understandable and reachable without hidden menus.
- Improve form validation feedback and save-error UX.

---

## 2) Workstream A — Financial Copy Clarity (issue #4)

### Problems

- Terms like `not applied`, `needs recalculation`, `close month` are internal and ambiguous.
- `BudgetHealthState.statusText` (line 98 of `BudgetSummaryCard.swift`) already contains explanatory text, but it duplicates copy embedded in `GoalDashboardCopyCatalog.swift`. There is no single source of truth.
- The full set of user-facing planning strings has not been audited; only three are addressed below as a starting point.

### Proposal

- Audit all user-facing strings across both platforms and produce a complete inventory in `docs/copy/FINANCIAL_COPY_DICTIONARY.md` before implementation begins. Sources to audit:
  - iOS: `GoalDashboardCopyCatalog.swift`, `MonthlyCycleCopyCatalog.swift`, and all inline `Text` literals in planning views.
  - Android: `GoalDashboardCopyCatalog.kt`, `ExecutionActionCopyCatalog.kt`, and all inline Compose `Text(…)` literals in `MonthlyPlanningScreen.kt`, `MonthlyPlanningContainer.kt`, and related planning composables.
- Tone baseline: copy should be written from the user's perspective (what they see happening to their savings), avoid verb forms that imply the app has made a financial decision on their behalf, and avoid internal state machine vocabulary.
- Update the three highest-impact terms as follows:

  | Internal term | Current copy | Proposed copy | Rationale |
  |---------------|-------------|---------------|-----------|
  | `not applied` | Budget saved, not applied this month | Not yet applied to this month | "Budget saved" implies user intent; "saved" is ambiguous with monetary saving in a finance app |
  | `needs recalculation` | Your goals or month changed | Goal amounts changed — recalculate plan | Previous wording was vague on action; recalculation may not be automatic so the imperative is appropriate |
  | `close month` | Complete this month | Complete this month | Already correct; ensure both platforms use this exact string |

- Add a one-line contextual explanation under each risk/health status label **only when the card is expanded or the status is non-healthy**. Do not add the explanation to the collapsed `BudgetHealthCollapsedStrip`, and do not show it when `BudgetHealthState == .healthy`. Maximum 60 characters per explanation. Example: under `.atRisk`: "Shortfall may delay one or more goals." This conditional rule prevents alert fatigue on a screen already dense with status information.
- New copy introduced by other workstreams (chip labels, validation error strings, confirmation dialog text, "What's blocking save" heading) must be added to the dictionary before those workstreams ship.
- Ensure iOS (`GoalDashboardCopyCatalog.swift`) and Android (`GoalDashboardCopyCatalog.kt`) use identical keys; see Delivery Plan step 6 for CI enforcement.

### Acceptance criteria

- All user-facing planning strings are present in `docs/copy/FINANCIAL_COPY_DICTIONARY.md` with no gaps relative to a grep of `GoalDashboardCopyCatalog` and `MonthlyCycleCopyCatalog`.
- No string in the copy dictionary contains any of the terms flagged by `GoalDashboardCopyCatalog.diagnosticsChecklistViolations()`.
- Preview evidence required: `BudgetSummaryCard` in `.healthy`, `.notApplied`, `.atRisk`, and `.needsRecalculation` states, showing the conditional explanation rule applied correctly.

---

## 3) Workstream B — Goal Requirement Row and Screen Hierarchy (issue #5)

### Problems

- The primary problem on the planning screen is **action-model ambiguity**, not raw visual density. The actual collapsed row already shows: status indicator + icon, goal name, flex-state chip (which is a `Menu` containing lock/skip/custom-amount actions), details toggle. The row is not overcrowded; the issue is that the `flexStateChip` Menu is icon-only on iOS (line 272 of `GoalRequirementRow.swift`), so users cannot tell from the collapsed row what states are available or how to change them.
- The screen-level hierarchy compounds this: before the user reaches the first `GoalRequirementRow`, they must parse `BudgetHealthCard`, then the `consolidatedHeader` (Monthly Total, Goals count, Next Due), then the `statusSummaryRow` (On Track / Attention / Critical pills). This header stack occupies most of the above-the-fold viewport. Simplifying the row in isolation is unlikely to move the 3-second usability benchmark; the header stack must be addressed in the same workstream.

### Proposal

**Implementation targets**

This workstream modifies two components:

1. `GoalRequirementRow` in `Views/Planning/GoalRequirementRow.swift` — the individual goal row.
2. `planningHeaderSection` / `consolidatedHeader` / `statusSummaryRow` in `PlanningView.swift` (lines 193, 260, 326) — the screen-level header stack.

`UnifiedGoalRowView` is used for the goals list and sidebar, not for the planning screen. It must not be modified in this workstream.

**Row changes: visible state label**

Replace the icon-only `flexStateChip` label on iOS with a text+icon label showing the current flex state name. The label is already displayed on macOS (line 273 of `GoalRequirementRow.swift`); apply the same pattern to iOS by removing the `#if os(macOS)` guard around the `Text(flexState.displayName)` line. The `Menu` itself and its actions remain unchanged.

**Row changes: Adjust sheet (deferred)**

The proposal to introduce a separate `GoalRequirementAdjustSheet` is deferred. The existing `Menu`-in-chip pattern is serviceable once the state label is visible. A dedicated sheet should be reconsidered if user testing shows the Menu actions are still not discoverable after the label is added.

Note: `ScrollOrigin.programmaticReset(.sheetDismiss)` is defined in `CommitDock.swift` and is only wired into `PlanningView`'s scroll infrastructure. `GoalsListView` and `GoalsSidebarView` use standard `List` containers with no scroll restoration mechanism. No scroll-restoration work is required or possible for those surfaces in this workstream.

**Screen-level hierarchy: header simplification**

The `consolidatedHeader` currently shows Monthly Total (large), Goals count, and Next Due in one card, followed immediately by the status pills row. This creates three consecutive information layers above the first row. Proposed changes:

- Merge the status pills (`statusSummaryRow`) into the `consolidatedHeader` card as a secondary row below the stats, removing the separate card surface.
- Remove the Goals count stat from the `consolidatedHeader`; it is redundant with the row list below. Replace with the status pill summary inline.
- Keep `BudgetHealthCard` unchanged — it is the primary actionable element and must remain prominent.

**Large Dynamic Type**

At Accessibility XXXL, the flex state label on `GoalRequirementRow` must not truncate the goal name. If name + label cannot fit on one line, the label wraps below the name. The monthly amount and deadline columns in the middle row stack vertically (name above value) rather than truncating.

**macOS**

No changes required on macOS — the flex state label is already visible, and the header layout is rendered in `macOSControlsPanel` (separate surface, out of scope for this pass).

---

## 4) Workstream C — Stale Draft Context (issue #6)

### Problems

- The collapsed `StaleDraftBanner` header shows only aggregate count ("2 stale draft plans from past months") with no per-plan context visible until the user taps to expand.
- Within the expanded list, each `StalePlanRow` shows only `formatMonthLabel(plan.monthLabel)` and `plan.formattedEffectiveAmount()`. The goal name is a hardcoded placeholder `"Goal"` (line 233 of `StaleDraftBanner.swift`) — this is a confirmed bug.
- All three resolution actions (Mark Completed, Mark Skipped, Delete) are hidden inside an `ellipsis.circle` `Menu` with no visible indication that actions exist. Users must discover the menu to resolve any draft.

### Proposal

**Fix the goal name bug**

`MonthlyPlan` does not have a `Goal` relationship — it stores only `goalId` (a `UUID`). There is no SwiftData `@Relationship` to a `Goal` object in the current model. Implementing this fix therefore requires one of the following approaches, which must be decided before implementation begins:

Option 1 — Enrich at the `PlanningView` level (preferred, no model change)
: `staleDrafts` is computed in `PlanningView` via `@Query` over `allPlans` (line 16 of `PlanningView.swift`) and passed down as a plain `[MonthlyPlan]` to each sub-view. `PlanningView` also has `@Environment(\.modelContext)`, so it can resolve `plan.goalId → Goal.name` with a fetch immediately after the query filter and pass a `[UUID: String]` lookup dictionary alongside `staleDrafts` to `StaleDraftBanner` and then into each `StalePlanRow`. No view model or model change required.

Option 2 — Store goal name as a denormalised field on `MonthlyPlan`
: Add a `goalName: String` property to the `MonthlyPlan` model, populated at plan creation time. This avoids a runtime fetch but introduces a denormalisation that can drift if the goal is renamed.

Option 3 — Add a SwiftData `@Relationship` from `MonthlyPlan` to `Goal`
: Requires a model migration. Higher complexity; only justified if other features also need goal properties from a plan.

Remove the hardcoded `"Goal"` placeholder at `StaleDraftBanner.swift` line 233 regardless of which option is chosen. If the resolved name is unavailable at render time, fall back to "Unknown goal" (not "Goal") and log a warning.

**Row anatomy — always-visible content**

Each `StalePlanRow` must always show, without requiring any tap:

- Localized month+year label (already implemented via `formatMonthLabel`, which outputs "January 2025" format — compliant with the year-boundary requirement). Bare month names are disallowed.
- Goal name (fix above).
- Planned amount.
- A resolution button with visible label (see below).

**Visible resolution entry point**

Replace the `ellipsis.circle` Menu with an explicit `Resolve` button with label text visible on the row surface. Tapping `Resolve` presents a sheet (iOS) or popover (macOS) with the three actions: Mark Completed, Mark Skipped, Delete. This makes the resolution entry point scannable without requiring menu discovery.

The existing "What do these actions mean?" info box in the expanded `StaleDraftBanner` body is retained and shown above the row list.

**Status chips**

Add one status chip per row indicating the current resolution state. Chip visual specification:

| State | Label | Token — background | Token — foreground |
|-------|-------|--------------------|--------------------|
| Unresolved | Unresolved | `AccessibleColors.warningBackground` | `AccessibleColors.warning` |
| Marked completed | Marked completed | `AccessibleColors.successBackground` | `AccessibleColors.success` |
| Marked skipped | Marked skipped | `AccessibleColors.surfaceBase` | `AccessibleColors.secondaryText` |

Shape: pill, corner radius 100 pt, horizontal padding 8 pt, vertical padding 4 pt. No icon. Display-only — tapping the chip does nothing.

**Row lifecycle and state transitions**

| Action | Result |
|--------|--------|
| User taps "Resolve" | Sheet/popover presents three actions; no state change until an action is confirmed |
| User marks completed | Chip changes to "Marked completed"; row fades out after 0.6 s delay (ease-out, 0.3 s) and is removed from the list |
| User marks skipped | Chip changes to "Marked skipped"; same fade-out behaviour |
| User taps Delete (in sheet) | Confirmation dialog appears; on confirm, row removed immediately with no fade |

`accessibilityReduceMotion`: when `UIAccessibilityIsReduceMotionEnabled()` is true, omit the fade and remove the row immediately.

**Confirmation dialog**

Use a system alert (`UIAlertController` on iOS, `AlertDialog` on Android) — not inline confirmation.

- Title: "Delete draft?"
- Message: "This will permanently delete the [month+year] draft for [goal name]. This cannot be undone." — using the same localized month+year value displayed in the row.
- Buttons: "Delete" (destructive role), "Cancel" (cancel role). No undo path.

---

## 5) Workstream D — Form Validation and Save Errors (issue #8)

### Form anatomy pre-condition

`AddGoalView` and `EditGoalView` use different layout systems:

- `AddGoalView` (line 296): standard SwiftUI `Form` with `Section(header:)` groups — the system renders row separators, grouped backgrounds, and standard cell padding.
- `EditGoalView` (line 65): custom scroll stack using `FormSection` and `FormField` components with explicit `VStack` layout, section headers, and manual padding.

Inline validation errors and a sticky summary cannot be implemented consistently across both forms without first aligning their layout contracts. **This workstream is blocked until a form anatomy standardisation pass is completed.** Options:

1. Migrate `AddGoalView` to use the same `FormSection`/`FormField` components as `EditGoalView` (preferred — the custom components give more layout control).
2. Accept divergence and implement the validation UI separately per form (higher cost, higher risk of inconsistency).

The form anatomy decision must be made and documented before detailed implementation begins.

### CTA topology pre-condition

In both forms, Save is a `.navigationBarTrailing` toolbar item (`AddGoalView` line 345, `EditGoalView` line 244). The proposal's sticky "What's blocking save" summary cannot be anchored "above the Save button" without changing this topology. **This workstream must choose one of the following layout contracts before implementation begins:**

Option A — Save stays in toolbar, summary appears inline
: Keep Save in the navigation bar. The blocking summary appears as an inline card at the top of the form (below the navigation bar), visible without scrolling when the form is short or when the user is near the top. This avoids topology change but the summary may scroll out of view on long forms.

Option B — Save moves to a fixed bottom action area
: Remove Save from the toolbar. Add a fixed bottom `safeAreaInset` containing the Save button and the blocking summary directly above it. The navigation bar retains only Cancel. This is a layout contract change requiring new UI tests and a macOS equivalent for both forms:
  - `AddGoalView` on macOS already has an inline bottom button row (lines 276–291 of `AddGoalView.swift`). The blocking summary can be inserted above the Save button inside that HStack section.
  - `EditGoalView` on macOS uses `.primaryAction` toolbar placement (line 41 of `EditGoalView.swift`), not an inline bottom row. Option B therefore requires adding an equivalent inline bottom section to `EditGoalView`'s macOS layout, analogous to `AddGoalView`'s existing pattern.

The recommended option is **B**, as it keeps the summary and the CTA co-located regardless of scroll position. Option A is acceptable only if the forms are always short enough that the inline summary is visible when the user taps Save.

### Problems

- Disabled save button with no explanation of which field is invalid.
- Save failures (persistence errors) are not surfaced as actionable errors.

### Proposal

Validation errors (client-side) and persistence failures (SwiftData/Room write failed) require different UX treatments.

**Validation errors (client-side)**

- Show an inline error string directly below each failing field using `VisualComponentTokens.statusError` (`AccessibleColors.errorBackground` fill, `AccessibleColors.error` foreground text, caption type role).
- The "What's blocking save" summary lists each blocking field by name and reason. Placement depends on the chosen CTA topology (Option A: inline at form top; Option B: fixed above Save button).
- The Save button is **always enabled**. Validation runs on tap, not on field change. If one or more fields are invalid when Save is tapped, the inline errors and summary appear and the save is not submitted. This resolves the disabled-button discoverability problem and is consistent with how a disabled button is treated by assistive technology (non-actionable, non-announceable). Do not use `disabled(true)` on the Save button.
- Error indication must not rely on colour alone — an icon or label is required alongside any colour change.

**Persistence failures (save error)**

- On error: dismiss loading indicator and show a system alert.
- Title: "Couldn't save"
- Message: "Your changes couldn't be saved. Try again, or discard and start over." No internal error codes. If a correlation ID is available, append it as a separate line: "Error reference: [ID]".
- Buttons: "Try Again" (default), "Discard Changes" (destructive), "Cancel".

**Accessibility requirements**

- iOS: on failed save, programmatic focus moves to the "What's blocking save" summary using `AccessibilityFocusState`. Field-level error views are individually focusable via VoiceOver with error text as `accessibilityLabel`. Do not simultaneously post `UIAccessibility.post(notification: .announcement)` — that interrupts the focus-driven readout. The announcement approach is only appropriate for transient toasts that are not focusable.
- Android: on failed save, direct accessibility focus to the summary banner using `Modifier.semantics { focused = true }` on the summary composable in combination with a `FocusRequester` — the codebase already uses `Modifier.semantics` throughout (e.g. `BudgetCalculatorComponents.kt`, `GoalDashboardScreen.kt`). Field-level errors are exposed via `OutlinedTextField(isError = …, supportingText = { Text(errorString) })`, which is the pattern already established in `AddEditGoalScreen.kt` (lines 165, 190) and `AddEditAssetScreen.kt` (lines 156, 208). Do not call `announceForAccessibility` simultaneously with a focus move.
- Neither platform may use colour as the sole indicator of a validation error.

---

## 6) Delivery Plan

1. Audit all planning strings; produce `docs/copy/FINANCIAL_COPY_DICTIONARY.md`.
2. Apply Workstream A copy changes; add conditional health-status explanations.
3. Decide and document form anatomy and CTA topology choices for Workstream D.
4. Workstream B — add flex state text label to iOS `GoalRequirementRow`; simplify `consolidatedHeader` + `statusSummaryRow` merge in `PlanningView`.
5. Workstream C — fix `goalName` placeholder in `StaleDraftBanner.swift:233`; implement month+year labels, visible `Resolve` button, status chips, row lifecycle, and confirmation dialog.
6. Cross-platform copy key parity check: canonical source of truth is `docs/copy/FINANCIAL_COPY_DICTIONARY.md`. The repo already has a copy-catalog validator at `scripts/validate_goal_dashboard_contracts.py` (gate `DASH-COPY-ERR-001`), wired into `.github/workflows/goal-dashboard-gates.yml`. This step **extends** that existing validator rather than adding a parallel script. Specifically: add a new gate (e.g. `PLAN-COPY-PARITY-001`) to `validate_goal_dashboard_contracts.py` that reads keys from `FINANCIAL_COPY_DICTIONARY.md` and asserts that the **iOS union** (`GoalDashboardCopyCatalog.swift` ∪ `MonthlyCycleCopyCatalog.swift`) and the **Android union** (`GoalDashboardCopyCatalog.kt` ∪ `ExecutionActionCopyCatalog.kt`) each cover every key. Individual catalogs are not required to contain every key — only each platform's combined set must be complete — so valid platform-specific splits (e.g. a key present only in `MonthlyCycleCopyCatalog.swift` on iOS and only in `ExecutionActionCopyCatalog.kt` on Android) will pass. Extend the path triggers in `goal-dashboard-gates.yml` to also fire on changes to `MonthlyCycleCopyCatalog.swift`, `ExecutionActionCopyCatalog.kt`, and `docs/copy/`. Before this gate is meaningful, all strings audited in step 1 (including `MonthlyCycleCopyCatalog` and inline planning `Text` literals) must be centralised into the dictionary and catalog files — inline literals not in a catalog cannot be checked by any script.
7. Workstream D — form standardisation pass; validation and save-error implementation.
8. Snapshot + UI tests (iOS + Android parity checklist).

---

## 7) Acceptance Criteria

**Workstream A**

- All user-facing planning strings are present in `docs/copy/FINANCIAL_COPY_DICTIONARY.md` with no gaps relative to a grep of `GoalDashboardCopyCatalog` and `MonthlyCycleCopyCatalog`.
- No string in the dictionary contains any term flagged by `GoalDashboardCopyCatalog.diagnosticsChecklistViolations()`.
- Preview evidence required: `BudgetSummaryCard` rendered in all seven `BudgetHealthState` cases — `.noBudget`, `.healthy`, `.notApplied`, `.needsRecalculation`, `.atRisk`, `.severeRisk`, and `.staleFX` — in both light and dark appearance, showing the conditional explanation present or absent per the rule. This covers the full state surface of `BudgetHealthState` as defined in `BudgetSummaryCard.swift`.

**Workstream B**

- Users can identify the required monthly action in a goal requirement row within 3 seconds. Measurement protocol: task prompt is "What do you need to do for this goal this month?", tested against 5 internal participants per run on the updated screen (including header changes), app in a state with at least one active plan. Pass threshold is 4 of 5 per run. This is a directional signal — internal participants have app familiarity that real users lack; a borderline 4/5 result must be escalated for broader testing before release.
  Required runs:
  - iOS: iPhone 16 simulator at default Dynamic Type size (Large).
  - iOS large text: iPhone 16 simulator at Accessibility XXXL Dynamic Type size; goal name, flex state label, monthly amount, and deadline must all be visible without scrolling or expanding the row.
  - Android: Pixel 8 emulator at default font scale (1.0).
  - Android large text: Pixel 8 emulator at font scale 1.3 (largest non-accessibility scale).
  All four runs must pass before this criterion is considered met.
- Preview evidence required: `GoalRequirementRow` in `.onTrack`, `.attention`, `.critical`, `.protected`, and `.skipped` flex states at default and XXXL Dynamic Type sizes; `PlanningView` header at default and XXXL sizes showing merged status pills.

**Workstream C**

- No `StalePlanRow` rendered without both goal name and a localized month+year label (not bare month name).
- `StaleDraftBanner.swift` no longer contains the hardcoded `"Goal"` placeholder at line 233.
- All three chip states (`Unresolved`, `Marked completed`, `Marked skipped`) render with the correct `AccessibleColors` tokens under both light and dark appearance.
- The `Resolve` button is visible on the row surface without opening any menu.
- Preview evidence required: `StalePlanRow` in each of the three chip states, in light and dark appearance.

**Workstream D**

- Form anatomy and CTA topology decisions are documented (in this proposal or a linked decision record) before implementation begins.
- All invalid fields in `AddGoalView` and `EditGoalView` display an inline error when Save is tapped while the form is invalid; no field's invalidity is communicated by colour alone.
- The "What's blocking save" summary is visible in the viewport without scrolling when at least one field is invalid.
- A simulated persistence write failure produces the "Couldn't save" alert with "Try Again" and "Discard Changes" options; no internal error codes are shown.
- VoiceOver (iOS) and TalkBack (Android): after a failed save, focus lands on the "What's blocking save" summary before any other element; no concurrent announcement interrupts the focus-driven readout.
- Preview evidence required: `AddGoalView` and `EditGoalView` in default (valid), validation-error, and persistence-error states, at default and XXXL Dynamic Type sizes.

---

## Related documentation

- [COMPONENT_REGISTRY.md](../COMPONENT_REGISTRY.md) — component catalog; `GoalRequirementRow` (planning screen) and `UnifiedGoalRowView` (goals list and sidebar) are separate components — do not conflate
- [MONTHLY_PLANNING.md](../MONTHLY_PLANNING.md) — monthly planning and execution tracking architecture
- [CONTRIBUTION_FLOW.md](../CONTRIBUTION_FLOW.md) — contribution and allocation flow; relevant to Workstream A copy audit
- [STYLE_GUIDE.md](../STYLE_GUIDE.md) — documentation conventions

---

*Last updated: 2026-03-14*
