# Financial Copy Dictionary

Normative copy source for targeted planning and goal-form strings covered by `UI_UX_INCREMENTAL_IMPROVEMENTS_PROPOSAL`.

| Key | Wording | Scope | Target Platforms | iOS Paths | Android Paths | Notes |
|---|---|---|---|---|---|---|
| `planning_budget_not_applied` | `Budget saved, not applied to this month yet` | `shared` | `iOS, Android, macOS` | `ios/CryptoSavingsTracker/Views/Planning/BudgetSummaryCard.swift` | `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/planning/components/BudgetCalculatorComponents.kt` | macOS uses the shared SwiftUI planning surface. |
| `planning_goals_changed_review_plan` | `Goals changed, review this plan` | `shared` | `iOS, Android, macOS` | `ios/CryptoSavingsTracker/Views/Planning/BudgetSummaryCard.swift`<br>`ios/CryptoSavingsTracker/Views/Planning/CompactGoalRequirementRow.swift` | `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/planning/MonthlyPlanningScreen.kt` | Covers stale/recalculation planning feedback. |
| `planning_finish_month_cta` | `Finish {month}` | `shared` | `iOS, Android` | `ios/CryptoSavingsTracker/Views/Planning/MonthlyPlanningContainer.swift` | `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/planning/MonthlyPlanningContainer.kt` | `{month}` is a dynamic month token. |
| `goal_form_save_error_retry` | `Unable to save this goal right now. Please try again.` | `platform-specific` | `iOS` | `ios/CryptoSavingsTracker/Views/AddGoalView.swift`<br>`ios/CryptoSavingsTracker/Views/EditGoalView.swift` | `-` | Retryable persistence failure copy for iOS fixed-bottom action forms. |
