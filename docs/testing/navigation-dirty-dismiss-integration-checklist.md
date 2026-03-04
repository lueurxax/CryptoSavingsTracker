# Navigation Dirty-Dismiss Integration Checklist

Date: 2026-03-03
Owner: Mobile Platform Team

## iOS

1. `AddGoalView`
- Path: `ios/CryptoSavingsTracker/Views/AddGoalView.swift`
- Guard: `interactiveDismissDisabled(goalsMigrationEnabled && isDirty)`
- Confirmation: `Discard Changes` / `Keep Editing`
- Automated check: `CryptoSavingsTrackerUITests.testAddGoalDirtyDismissConfirmationFlow`

2. `EditGoalView`
- Path: `ios/CryptoSavingsTracker/Views/EditGoalView.swift`
- Guard: `interactiveDismissDisabled(goalsMigrationEnabled && viewModel.isDirty)`
- Confirmation: `Discard Changes` / `Keep Editing`
- Automated check: covered by existing edit-goal UI flow suite.

3. `BudgetCalculatorSheet`
- Path: `ios/CryptoSavingsTracker/Views/Planning/BudgetCalculatorSheet.swift`
- Guard: `interactiveDismissDisabled(planningMigrationEnabled && isDirty)`
- Confirmation: `Discard Changes` / `Keep Editing`
- Automated check: covered by existing monthly-planning UI suite.

## Android

1. `AddEditGoalScreen`
- Path: `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/goals/AddEditGoalScreen.kt`
- Current behavior: cancel path emits `nav_cancelled` with dirty context.

2. `MonthlyPlanningScreen`
- Path: `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/planning/MonthlyPlanningScreen.kt`
- Current behavior: budget sheet dismiss path emits `nav_cancelled` and guarded telemetry.

3. `GoalDetailScreen` (destructive flow)
- Path: `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/goals/GoalDetailScreen.kt`
- Current behavior: destructive dialog emits `nav_flow_started/completed/cancelled/discard_confirmed` under migration gate.

## Gate Validation

- `scripts/run_navigation_policy_gates.sh origin/main release` must pass before release evidence promotion.
