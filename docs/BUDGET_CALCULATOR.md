# Budget Calculator

> Planning tool for determining optimal per-goal contributions based on a fixed monthly savings amount

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-01-04 |
| Platform | Shared |
| Audience | Developers |

---

The Budget Calculator is a planning tool that helps users determine optimal per-goal contributions based on a fixed monthly savings amount. Rather than operating as a separate mode, it integrates with the existing Monthly Planning view, preserving familiar features like the flex slider, protect/skip toggles, and per-goal customization.

## Overview

The Budget Calculator solves the problem of uneven monthly contribution requirements. When goals have different deadlines, calculating contributions independently can create months requiring much higher savings than others. The calculator determines a consistent monthly budget that meets all deadlines.

**Key characteristics:**
- Calculator tool, not a separate planning mode
- Applies results to the existing Monthly Planning view
- Preserves flex slider, statistics, and all existing features
- Uses Earliest Deadline First (EDF) allocation strategy

## Quick Start

1. Open **Monthly Planning**
2. Tap **Set Budget** in the "Plan by Budget" card
3. Enter your monthly savings amount
4. Review the preview showing per-goal distribution and timeline
5. Tap **Apply to Plan** to set the calculated amounts
6. Continue using Monthly Planning normally - adjust individual goals as needed

## User Interface

### Entry Point

The Monthly Planning view displays a "Plan by Budget" card:

```
+-------------------------------------+
| Plan by Budget                      |
| Set a monthly amount and we'll      |
| calculate optimal contributions.    |
|                      [Set Budget]   |
+-------------------------------------+
```

### Calculator Sheet

The calculator opens as a bottom sheet with:

- **Budget input field**: Enter monthly savings amount with currency selector
- **Feasibility indicator**: Shows if the budget meets all deadlines and the minimum required amount
- **This month's allocation**: Preview of how the budget distributes this month
- **Timeline preview**: Visual representation of when each goal receives funding and completes
- **Action buttons**: Cancel or Apply to Plan

### After Applying

The Monthly Planning view shows:

- **Budget Summary Card**: Displays the active budget, current focus goal, and on-track status with an Edit button
- **Goal cards**: Show calculated amounts with a "From budget" indicator for budget-derived values
- **Flex slider**: Displays percentage of budget (e.g., "100% of budget (EUR 383)")

## Algorithm

The calculator uses sequential contribution with earliest deadline first (EDF) allocation.

### Minimum Budget Calculation

The minimum required budget uses a cumulative method to ensure all deadlines are achievable:

1. Sort goals by deadline (earliest first)
2. At each deadline, calculate the cumulative remaining amount for all goals due by that date
3. Divide cumulative remaining by months until that deadline
4. The minimum budget is the maximum of all these values

**Example:**

| Goal | Remaining | Deadline | Cumulative | Months | Required/Month |
|------|-----------|----------|------------|--------|----------------|
| B | EUR 1,000 | 3 months | EUR 1,000 | 3 | EUR 333 |
| C | EUR 600 | 6 months | EUR 1,600 | 6 | EUR 267 |
| A | EUR 3,000 | 12 months | EUR 4,600 | 12 | EUR 383 |

**Minimum budget: EUR 383/month** (the maximum constraint)

### Monthly Allocation

Each month, the full budget goes to the goal with the earliest deadline:

1. Allocate entire budget to the earliest-deadline goal
2. If that goal completes mid-month, allocate the remainder to the next goal
3. Continue until budget is exhausted

This concentrated funding approach completes goals faster than proportional distribution.

**Example allocation with EUR 383/month budget:**

- Months 1-3: Goal B receives EUR 383/month, completes
- Months 4-5: Goal C receives EUR 383/month, completes
- Months 6-12: Goal A receives EUR 383/month, completes

## Data Model

### Storage

The calculator stores results using existing planning structures:

```kotlin
// MonthlyGoalPlan - calculator sets customAmount
data class MonthlyGoalPlan(
    val goalId: UUID,
    val monthLabel: String,
    var customAmount: Double?,  // Set by budget calculator
    var isProtected: Boolean,
    var isSkipped: Boolean
)

// MonthlyPlanningSettings - stores the budget
data class MonthlyPlanningSettings(
    val monthlyBudget: Double?,   // null = not using budget mode
    val budgetCurrency: String,
    // ... other settings
)
```

Budget mode is active when `monthlyBudget != null`.

### Calculator Result

The calculator generates results on-demand (timeline is not persisted):

```kotlin
data class BudgetCalculatorResult(
    val monthlyBudget: Double,
    val currency: String,
    val currentMonthAllocations: List<GoalAllocation>,
    val timelinePreview: List<TimelineBlock>,
    val feasibility: FeasibilityResult
)

data class GoalAllocation(
    val goalId: UUID,
    val amount: Double,
    val startsThisMonth: Boolean
)

data class TimelineBlock(
    val goalId: UUID,
    val goalName: String,
    val emoji: String?,
    val startMonth: String,
    val endMonth: String,
    val paymentCount: Int
)
```

## Feature Integration

### Flex Slider

The flex slider uses the budget as its baseline:
- 100% = full budget amount
- Adjusting the slider scales all per-goal amounts proportionally

### Protect/Skip

- **Protected goals**: Keep their calculated amount when flex changes
- **Skipped goals**: Receive EUR 0; budget redistributes to remaining goals

### Execution Tracking

Execution reads from `MonthlyGoalPlan.customAmount`, the same as non-budget planning:
- Tracks contributions against each goal's target for the month
- "Current Focus" shows the goal with the earliest deadline that has remaining amount
- No multi-month schedule is stored; re-open the calculator to see future months

### Statistics

Statistics remain unchanged, showing:
- Critical/Attention/On Track goal counts
- Total monthly requirement
- Progress percentages

## Feasibility Handling

If the entered budget cannot meet all deadlines, the calculator displays:

- Warning message identifying the shortfall
- The specific goal causing the constraint
- Quick fix options:
  - Increase budget to the minimum required
  - Extend the constraining goal's deadline
  - Edit the goal directly

The **Apply to Plan** button is disabled until feasibility is resolved.

## Recalculation

### Editing the Budget

1. Tap **Edit** on the Budget Summary Card
2. Calculator sheet opens with current budget
3. Modify the amount and review the new preview
4. Tap **Apply to Plan** to update all amounts

### When Goals Change

When goals are added, removed, or edited while a budget is set:
- The system prompts: "Recalculate for budget?"
- User can recalculate or keep current amounts
- If the budget becomes infeasible, a warning appears

## Settings

Budget settings appear in the Monthly Planning settings screen:

- **Monthly Budget**: Current amount with Edit option
- **Use calculated minimum**: Sets budget to the minimum required
- **Clear budget**: Removes the budget and returns to standard planning

## Source Files

### iOS

| File | Purpose |
|------|---------|
| `Services/BudgetCalculatorService.swift` | Core calculation logic |
| `Views/Planning/BudgetCalculatorSheet.swift` | Calculator UI |
| `Views/Planning/BudgetSummaryCard.swift` | Budget display in planning view |
| `Views/Planning/MonthlyPlanningView.swift` | Entry point integration |
| `ViewModels/MonthlyPlanningViewModel.swift` | Budget state management |
| `Models/MonthlyPlanningSettings.swift` | Budget storage |

### Android

| File | Purpose |
|------|---------|
| `domain/usecase/planning/BudgetCalculatorUseCase.kt` | Core calculation logic |
| `presentation/planning/BudgetCalculatorSheet.kt` | Calculator UI |
| `presentation/planning/components/BudgetSummaryCard.kt` | Budget display in planning view |
| `presentation/planning/MonthlyPlanningScreen.kt` | Entry point integration |
| `presentation/planning/MonthlyPlanningViewModel.kt` | Budget state management |
| `domain/model/MonthlyPlanningSettings.kt` | Budget storage |
