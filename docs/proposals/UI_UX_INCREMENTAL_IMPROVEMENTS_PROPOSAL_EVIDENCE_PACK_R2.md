# Evidence Pack

## A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/UI_UX_INCREMENTAL_IMPROVEMENTS_PROPOSAL.md` | lines 7-12, 42-55 | The proposal now uses a workstream-scoped platform matrix instead of a blanket `iOS + Android` claim. | Review should test whether later acceptance/tooling rules still respect that matrix. |
| DOC-02 | `docs/proposals/UI_UX_INCREMENTAL_IMPROVEMENTS_PROPOSAL.md` | lines 74-103 | Workstream A now introduces a dedicated copy dictionary and new validator boundary, but its acceptance still says CI fails if a targeted planning/form string is present only on one platform path. | The copy contract may still be too global for workstreams that are intentionally platform-specific. |
| DOC-03 | `docs/proposals/UI_UX_INCREMENTAL_IMPROVEMENTS_PROPOSAL.md` | lines 118-145 | Workstream B now proposes a stronger iOS redesign: compact row with one visible `Adjust` entry point, with lock/skip/custom-amount moved out of the default row. | Review must verify whether this is implementable without affecting macOS, because the current row component is shared. |
| DOC-04 | `docs/proposals/UI_UX_INCREMENTAL_IMPROVEMENTS_PROPOSAL.md` | lines 161-185 | Workstream C resolves the prior chip issue by removing transient resolved-state chips and defines a lookup-map contract for stale-draft goal names. | This closes one major R1 gap; remaining review should focus on operability and data-flow clarity. |
| DOC-05 | `docs/proposals/UI_UX_INCREMENTAL_IMPROVEMENTS_PROPOSAL.md` | lines 202-251 | Workstream D now locks one iOS contract: fixed bottom action area, tappable Save, inline errors, bottom summary, focus movement, and retryable persistence failure. | The proposal is no longer blocked, but implementation details still need to be specific enough for mixed `Form` and custom-scroll surfaces. |
| DOC-06 | `docs/proposals/UI_UX_INCREMENTAL_IMPROVEMENTS_PROPOSAL.md` | lines 255-282 | Section 6 now adds an explicit preview/test evidence contract for rows, stale drafts, and invalid/persistence-error form states. | Review should check whether the evidence contract distinguishes previewable states from simulator-only/system-dialog states. |
| DOC-07 | `ios/CryptoSavingsTracker/Views/Planning/PlanningView.swift` | lines 409-423, 837-851, 977-991, 1013-1027 | `GoalRequirementRow` is still used from iOS and macOS planning layouts. | A proposal that declares Workstream B to be iOS-only needs an isolation strategy at the component boundary. |
| DOC-08 | `ios/CryptoSavingsTracker/Views/Planning/PlanningView.swift` | line 173 | The existing planning chrome already has a top-level `Adjust` tab label. | A row-level `Adjust` action risks terminology collision unless the proposal distinguishes the two surfaces. |
| DOC-09 | `ios/CryptoSavingsTracker/Views/AddGoalView.swift` and `ios/CryptoSavingsTracker/Views/EditGoalView.swift` | Add Goal lines 296-379, 416-487; Edit Goal lines 221-321 | iOS goal forms still use two different layout systems: `Form` in `AddGoalView`, custom scroll stack in `EditGoalView`. | Workstream D needs one explicit implementation mechanism for keyboard-safe fixed bottom actions across both. |
| DOC-10 | `ios/CryptoSavingsTracker/Views/Planning/StaleDraftBanner.swift` and `ios/CryptoSavingsTracker/Models/MonthlyPlan.swift` | banner lines 230-299; model lines 16-33 | `StalePlanRow` still has the `"Goal"` placeholder in code, and `MonthlyPlan` still has only `goalId` rather than a `Goal` relationship. | Workstream C still correctly targets a real unresolved bug and still benefits from the no-migration lookup-map decision. |
| DOC-11 | `ios/CryptoSavingsTracker/Views/**/*Preview.swift` | grep on 2026-03-15 | Existing preview files still do not cover Dynamic Type accessibility row states or invalid/persistence-error goal-form states. | The proposal now names the missing evidence explicitly, which improves readiness, but the evidence is still not yet present in code. |

## B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | [Apple Design Tips](https://developer.apple.com/design/tips/) | no publication date shown; accessed 2026-03-15 | Apple emphasizes clarity of primary actions, hierarchy, and focused interfaces. | Relevant to the planning header stack and row-action simplification. |
| WEB-02 | [Apple Human Interface Guidelines — Menus](https://developer.apple.com/design/human-interface-guidelines/menus) | no publication date shown; accessed 2026-03-15 | Menus are appropriate for secondary actions, not the only discoverable resolution path in a critical workflow. | Relevant to stale-draft resolution design and the shift to a visible `Resolve` entry point. |
| WEB-03 | [Jetpack Compose — Configure text fields](https://developer.android.com/develop/ui/compose/text/user-input) | 2025-10-10 UTC | Compose standardizes `isError` + `supportingText` for field-level validation. | Confirms the proposal is right to keep Android on its current validation layout rather than forcing an iOS-style rewrite. |
| WEB-04 | [Jetpack Compose — Semantics](https://developer.android.com/develop/ui/compose/accessibility/semantics) | 2025-09-03 UTC | Semantics/focus APIs are the correct layer for controlled accessibility focus behavior. | Relevant to the Android parity-review scope in Workstream D. |
| WEB-05 | [Jetpack Compose — Dialog](https://developer.android.com/develop/ui/compose/components/dialog) | 2025-10-30 UTC | `AlertDialog` is the standard destructive-confirmation pattern in Compose. | Relevant to delete confirmation in stale-draft resolution, even though Workstream C is not targeted at Android in v1. |
| WEB-06 | [CFPB Policy Statement on Abusiveness](https://www.consumerfinance.gov/compliance/supervisory-guidance/policy-statement-on-abusiveness/) | 2023-04-03 | Obscuring important limitations or conditions can materially interfere with consumer understanding. | Relevant to copy-contract quality and visible save-blocking/error reasons in a finance app. |

## C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-ui-ux-incremental-r2/planning-view-compact-preview.png` | `PlanningViewPreview` | Compact planning surface | Xcode Preview canvas, recaptured 2026-03-15 | Confirms the compact planning surface still uses a dense chrome/header structure and gives context for Workstream B. |
| SCR-02 | `docs/screenshots/review-ui-ux-incremental-r2/stale-plan-row-preview.png` | `StaleDraftBannerPreview` | Single stale row | Xcode Preview canvas, recaptured 2026-03-15 | Confirms stale-draft row anatomy today: no goal name and actions hidden behind the menu. |
| SCR-03 | `docs/screenshots/review-ui-ux-incremental-r2/edit-goal-preview.png` | `EditGoalViewPreview` | Default edit form | Xcode Preview canvas, recaptured 2026-03-15 | Confirms the current custom-scroll form surface that Workstream D needs to harmonize with `AddGoalView`. |
| SCR-04 | `docs/screenshots/review-ui-ux-incremental-r1/form-preview-latest.png` | `AddGoalViewPreview` | Default add form | Xcode Preview canvas, same-day reuse | Captures the current `Form`-based anatomy for Add Goal. |

## D. Assumptions and Open Questions
- ASSUMP-01: UI code did not change between R1 and R2; refreshed screenshots are used only to keep the evidence pack current while reviewing the revised proposal text.
- ASSUMP-02: Workstream A copy parity is intended to be feature-scoped, not a blanket rule that forces Android to carry strings for iOS/macOS-only features.
- QUESTION-01: How will Workstream B isolate iOS-only row simplification from the macOS layouts that still use the same `GoalRequirementRow` component?
- QUESTION-02: Should the row-level action label remain `Adjust` when there is already a top-level `Adjust` tab in planning?
- QUESTION-03: Should destructive confirmation remain in the preview evidence contract, or move to simulator/UI-test evidence where system dialogs can be validated realistically?
