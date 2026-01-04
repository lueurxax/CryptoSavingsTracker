# Fixed Budget Planning Proposal

Status: **Revision 2** (Updated approach)
Owner: Product
Last updated: 2026-01-04

## Summary

Add a **Budget Calculator** tool to monthly planning that helps users determine optimal per-goal contributions based on a fixed monthly savings amount. Instead of replacing the existing planning interface, the calculator **applies adjustments** to the familiar Per-Goal view, preserving the flex slider, statistics, and per-goal customization users already know.

## Problem Statement

Current behavior calculates `requiredMonthly` independently per goal:

| Goal | Target | Deadline | Required/Month |
|------|--------|----------|----------------|
| Goal A | €3,000 | 12 months | €250 |
| Goal B | €1,000 | 3 months | €333 |
| **Total** | | | **€583 (months 1-3), €250 (months 4-12)** |

This creates uneven monthly pressure. Users with fixed salaries want to:
1. Know the minimum they need to save monthly
2. See how a fixed budget distributes across goals
3. **Keep using** their familiar planning tools (flex slider, protect/skip, statistics)

## Previous Approach (v1) - Problems

The v1 implementation created a **separate Fixed Budget Mode** with its own UI:
- Segmented control to switch between "Per Goal" and "Fixed Budget"
- Completely different view when in Fixed Budget mode
- Lost access to flex slider, per-goal adjustments, statistics
- Confusing mental model: two separate planning systems

**User feedback:** "I had good planner before with adjusting, statistics, next contribution. Now I switch to static view without adjusting. Can I enter budget, review plan, apply it to my usual view?"

## Revised Approach (v2) - Budget as a Tool

Fixed Budget becomes a **calculator tool** that informs the existing planning view:

```
┌─────────────────────────────────────────────────────────────┐
│                    CONCEPTUAL FLOW                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. User taps "Set Budget" in Monthly Planning              │
│                     ↓                                       │
│  2. Budget Calculator Sheet opens                           │
│     - Enter monthly amount (e.g., €383)                     │
│     - See real-time preview of per-goal distribution        │
│     - See timeline of when each goal completes              │
│     - See warnings if budget is too low                     │
│                     ↓                                       │
│  3. User taps "Apply to Plan"                               │
│                     ↓                                       │
│  4. Returns to SAME Monthly Planning view with:             │
│     - Per-goal amounts pre-filled from budget calculation   │
│     - Flex slider still available (shows 100% = budget)     │
│     - Can still protect/skip individual goals               │
│     - Statistics and execution tracking unchanged           │
│     - Budget summary card shows monthly target              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Goals

- Provide a budget calculator that determines optimal per-goal amounts
- **Enhance** existing planning view, don't replace it
- Keep flex slider, statistics, protect/skip, and all existing features
- Show budget context (total monthly target) in the planning view
- Allow users to tweak individual goals after applying budget

## Non-Goals

- Creating a separate planning mode/view
- Hiding or disabling existing planning features
- Automatic contributions or bank integration

## User Flow

### Step 1: Access Budget Calculator

From the existing Monthly Planning view, user sees a new entry point:

```
┌─────────────────────────────────────────┐
│ Monthly Planning              [?] [⚙️]  │
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ 💡 Plan by Budget                   │ │
│ │ Set a monthly amount and we'll      │ │
│ │ calculate optimal contributions.    │ │
│ │                      [Set Budget →] │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ January 2026                    EUR 583 │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ ┌───────────────────────────────────┐   │
│ │ 🏖️ Goal B: Vacation    EUR 333   │   │
│ │ ━━━━━━━━━━━━━━░░░░░░░░░  45%     │   │
│ │ [Protected] [Custom]              │   │
│ └───────────────────────────────────┘   │
│ ... existing goal cards ...             │
│                                         │
│ ┌───────────────────────────────────┐   │
│ │ Flex Adjustment        [━━━●━━━]  │   │
│ │ 100%                              │   │
│ └───────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### Step 2: Budget Calculator Sheet

Tapping "Set Budget" opens a bottom sheet:

```
┌─────────────────────────────────────────┐
│ Budget Calculator                     ✕ │
├─────────────────────────────────────────┤
│                                         │
│ Monthly Savings Budget                  │
│ ┌────────┐ ┌─────────────────────────┐  │
│ │ EUR  ▼ │ │ 383___________________│  │
│ └────────┘ └─────────────────────────┘  │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ ✓ All deadlines achievable          │ │
│ │   Minimum required: EUR 333.33      │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ─────────── Preview ───────────         │
│                                         │
│ This month's contribution:              │
│ ┌─────────────────────────────────────┐ │
│ │ 🏖️ Goal B          EUR 383.33      │ │
│ │    (full budget to nearest deadline)│ │
│ └─────────────────────────────────────┘ │
│                                         │
│ Upcoming schedule:                      │
│ ┌─────────────────────────────────────┐ │
│ │ |====[B]====|==[C]==|=====[A]=====| │ │
│ │ Jan       Mar      May          Dec │ │
│ │      ▲                              │ │
│ │   You are here                      │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ • Goal B completes Mar 15 (3 payments)  │
│ • Goal C completes May 15 (2 payments)  │
│ • Goal A completes Dec 15 (7 payments)  │
│                                         │
│ [Cancel]              [Apply to Plan]   │
└─────────────────────────────────────────┘
```

### Step 3: Apply and Return

When user taps "Apply to Plan":

1. Calculator generates per-goal amounts for current month
2. These amounts are applied as `customAmount` values in `MonthlyGoalPlan`
3. Sheet dismisses
4. User returns to **same** Monthly Planning view
5. Goal cards now show the calculated amounts
6. A budget summary appears at top

### Step 4: Enhanced Planning View (After Apply)

```
┌─────────────────────────────────────────┐
│ Monthly Planning              [?] [⚙️]  │
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ Monthly Budget: EUR 383       [Edit]│ │
│ │ ✓ On track for all deadlines        │ │
│ │ Next: Goal B (until Mar 15)         │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ January 2026                    EUR 383 │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ ┌───────────────────────────────────┐   │
│ │ 🏖️ Goal B: Vacation    EUR 383   │   │  ← full budget this month
│ │ ━━━━━━━━━━━━━━░░░░░░░░░  45%     │   │
│ │ [Protected] [Custom ●]            │   │  ← shows custom applied
│ └───────────────────────────────────┘   │
│ ┌───────────────────────────────────┐   │
│ │ 🚗 Goal A: Car         EUR 0     │   │  ← deferred to later
│ │ ░░░░░░░░░░░░░░░░░░░░░░░░  0%     │   │
│ │ Starts: Jun 15                    │   │
│ └───────────────────────────────────┘   │
│ ┌───────────────────────────────────┐   │
│ │ 💰 Goal C: Emergency   EUR 0     │   │
│ │ ░░░░░░░░░░░░░░░░░░░░░░░░  0%     │   │
│ │ Starts: Apr 15                    │   │
│ └───────────────────────────────────┘   │
│                                         │
│ ┌───────────────────────────────────┐   │
│ │ Flex Adjustment        [━━━━━●]   │   │  ← still available!
│ │ 100% of budget (EUR 383)          │   │
│ └───────────────────────────────────┘   │
│                                         │
│         [Start Tracking]                │
└─────────────────────────────────────────┘
```

**Key differences from v1:**
- Same view, just with budget context added
- Flex slider still works (adjusts from budget baseline)
- Can still tap any goal to protect/skip/customize
- Statistics section unchanged
- User can manually override any goal amount

## Algorithm

The algorithm remains the same as v1 - sequential contribution to earliest deadline first:

### Input
- List of active goals with: `targetAmount`, `currentProgress`, `deadline`, `currency`
- User's monthly budget

### Output
- Per-goal amounts for current month (to apply as `customAmount`)
- Timeline preview showing when each goal gets funded
- Feasibility status

### Calculation Steps

```
1. For each goal, calculate:
   - remainingAmount = targetAmount - currentProgress
   - monthsUntilDeadline = months between now and deadline
   - goalMinimum = remainingAmount / monthsUntilDeadline

2. Sort goals by deadline (earliest first)

3. Calculate minimum required budget:
   - minimumBudget = MAX(all goalMinimum values)

4. Check feasibility:
   - If userBudget >= minimumBudget: feasible
   - If userBudget < minimumBudget: show warnings, suggest fixes

5. Generate current month's allocation:
   - Allocate full budget to earliest-deadline goal
   - If goal completes mid-month, allocate remainder to next goal
   - Return per-goal amounts for this month only

6. Generate timeline preview:
   - Calculate when each goal starts/completes at this budget
   - Show as visual timeline in calculator
```

### Example

**Input:**
- Goal A: €3,000 remaining, 12 months
- Goal B: €1,000 remaining, 3 months
- Goal C: €600 remaining, 6 months
- User budget: €383/month

**Current month allocation:**
```
Goal B: €383.33 (full budget - earliest deadline)
Goal C: €0 (starts month 4)
Goal A: €0 (starts month 6)
```

**Timeline preview:**
```
Months 1-3:  Goal B receives €383/mo → completes
Months 4-5:  Goal C receives €383/mo → completes
Months 6-12: Goal A receives €383/mo → completes
```

## Data Model Changes

### Simplification from v1

Remove the separate `FixedBudgetPlan` storage. Instead, use existing structures:

```swift
// Existing MonthlyGoalPlan - no changes needed
struct MonthlyGoalPlan {
    let goalId: UUID
    let monthLabel: String
    var customAmount: Double?      // ← Budget calculator sets this
    var isProtected: Bool
    var isSkipped: Bool
}

// New: Budget context stored in settings
extension MonthlyPlanningSettings {
    var budgetAmount: Double?      // User's monthly budget (nil = not using budget mode)
    var budgetCurrency: String
}
```

### Timeline Preview (Calculator Only)

The timeline is generated on-demand for the calculator preview, not stored:

```swift
struct BudgetCalculatorResult {
    let monthlyBudget: Double
    let currency: String
    let currentMonthAllocations: [GoalAllocation]  // What to apply
    let timelinePreview: [TimelineBlock]           // For preview display
    let feasibility: FeasibilityResult
}

struct GoalAllocation {
    let goalId: UUID
    let amount: Double
    let startsThisMonth: Bool
}

struct TimelineBlock {
    let goalId: UUID
    let goalName: String
    let emoji: String?
    let startMonth: String
    let endMonth: String
    let paymentCount: Int
}
```

## UI Components

### New: Budget Summary Card

Shows at top of planning view when budget is set:

```swift
struct BudgetSummaryCard: View {
    let budget: Double
    let currency: String
    let currentFocusGoal: String?
    let isOnTrack: Bool
    let onEdit: () -> Void
}
```

### New: Budget Calculator Sheet

Bottom sheet with budget input and preview:

```swift
struct BudgetCalculatorSheet: View {
    @State var budgetInput: Double
    let minimumRequired: Double
    let feasibility: FeasibilityResult
    let timelinePreview: [TimelineBlock]
    let currentMonthAllocations: [GoalAllocation]
    let onApply: () -> Void
    let onCancel: () -> Void
}
```

### Modified: Goal Cards

Add visual indicator when amount comes from budget calculation:

```swift
// Existing goal card, add:
if plan.customAmount != nil && settings.budgetAmount != nil {
    Label("From budget", systemImage: "calculator")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

### Modified: Flex Slider

When budget is set, show percentage of budget:

```swift
// Instead of "100%" show "100% of budget (EUR 383)"
Text("\(Int(flexValue * 100))% of budget (\(formattedBudget))")
```

## Removed from v1

The following v1 components are no longer needed:

- ❌ `PlanningModeSegmentedControl` - No mode switching
- ❌ `FixedBudgetPlanningView` - No separate view
- ❌ `FixedBudgetPlanningViewModel` - No separate view model
- ❌ `FixedBudgetSetupSheet` (2-step onboarding) - Simple calculator instead
- ❌ `ScheduleCard` with expansion - Timeline is preview-only
- ❌ `CompletionBehavior` setting - Not needed with this approach
- ❌ `FixedBudgetExecutionHeader` - Use existing execution view

## Integration with Existing Features

### Flex Slider

Works normally, but baseline is the budget amount:
- 100% = budget amount (e.g., €383)
- 80% = €306
- 120% = €460

When flex is adjusted, per-goal amounts scale proportionally.

### Protect/Skip

Works exactly as before:
- Protected goals keep their calculated amount even if flex changes
- Skipped goals get €0, budget redistributes to others

### Statistics

No changes - continues showing:
- Critical/Attention/On Track counts
- Total monthly requirement
- Progress percentages

### Execution Tracking

No changes - tracks contributions against the per-goal amounts (which happen to come from budget calculation).

## Recalculation

When user edits budget via "Edit" button:
1. Re-run calculator with new budget
2. Show preview in calculator sheet
3. User confirms to apply new amounts
4. Per-goal `customAmount` values update

When goals change (added/removed/edited):
1. If budget is set, show prompt: "Recalculate for budget?"
2. User can recalculate or keep current amounts
3. If budget becomes infeasible, show warning

## Feasibility Handling

Same as v1, but shown in calculator sheet:

```
┌─────────────────────────────────────────┐
│ ⚠️ Budget Shortfall                     │
├─────────────────────────────────────────┤
│ EUR 300/month cannot meet all deadlines │
│                                         │
│ Goal B needs EUR 333/month              │
│ Shortfall: EUR 33/month                 │
│                                         │
│ Quick fixes:                            │
│ [Increase to EUR 333]                   │
│ [Extend Goal B by 1 month]              │
│ [Edit Goal B...]                        │
└─────────────────────────────────────────┘
```

User must resolve feasibility before "Apply to Plan" is enabled.

## Settings

Simplified settings in Monthly Planning settings screen:

```
┌─────────────────────────────────────────┐
│ Planning Settings                       │
├─────────────────────────────────────────┤
│ Monthly Budget                          │
│ ┌─────────────────────────────────────┐ │
│ │ EUR 383                       [Edit]│ │
│ │ ○ Use calculated minimum            │ │
│ │ ○ Clear budget                      │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ Payment Day                             │
│ [15th of each month              ▼]     │
│                                         │
│ Display Currency                        │
│ [EUR                             ▼]     │
└─────────────────────────────────────────┘
```

## Migration from v1

For users who already used v1 Fixed Budget mode:

1. Read their `monthlyBudget` setting
2. Apply it via budget calculator on next planning view load
3. Show one-time message: "Your budget has been applied to your plan. You can now adjust individual goals."

## Implementation Plan

### Phase 1: Core Calculator
1. Create `BudgetCalculatorService` (reuse algorithm from v1)
2. Create `BudgetCalculatorSheet` UI
3. Add "Set Budget" entry point to planning view

### Phase 2: Apply & Display
1. Apply calculator results as `customAmount` values
2. Add `BudgetSummaryCard` to planning view
3. Update flex slider to show budget context

### Phase 3: Polish
1. Add feasibility warnings and quick fixes
2. Add recalculation prompts when goals change
3. Add settings integration

### Phase 4: Cleanup
1. Remove v1 Fixed Budget mode components
2. Migrate existing users
3. Update tests

## Files to Modify

### iOS

| File | Changes |
|------|---------|
| `Services/BudgetCalculatorService.swift` | NEW - Core calculation (reuse from FixedBudgetPlanningService) |
| `Views/Planning/BudgetCalculatorSheet.swift` | NEW - Calculator UI |
| `Views/Planning/BudgetSummaryCard.swift` | NEW - Budget display |
| `Views/Planning/MonthlyPlanningView.swift` | Add entry point, summary card |
| `ViewModels/MonthlyPlanningViewModel.swift` | Add budget state, apply logic |
| `Models/MonthlyPlanningSettings.swift` | Add `budgetAmount`, `budgetCurrency` |

### Android

| File | Changes |
|------|---------|
| `domain/usecase/planning/BudgetCalculatorUseCase.kt` | NEW - Core calculation |
| `presentation/planning/BudgetCalculatorSheet.kt` | NEW - Calculator UI |
| `presentation/planning/components/BudgetSummaryCard.kt` | NEW - Budget display |
| `presentation/planning/MonthlyPlanningScreen.kt` | Add entry point, summary card |
| `presentation/planning/MonthlyPlanningViewModel.kt` | Add budget state, apply logic |
| `domain/model/MonthlyPlanningSettings.kt` | Add `budgetAmount`, `budgetCurrency` |

### Files to Remove (v1 cleanup)

- `Views/Planning/FixedBudgetPlanningView.swift`
- `Views/Planning/FixedBudgetIntroCard.swift`
- `Views/Planning/PlanningModeSegmentedControl.swift`
- `presentation/planning/FixedBudgetPlanningScreen.kt`
- `presentation/planning/FixedBudgetPlanningViewModel.kt`
- `presentation/planning/components/FixedBudgetIntroCard.kt`

## Summary of Changes from v1

| Aspect | v1 (Separate Mode) | v2 (Calculator Tool) |
|--------|-------------------|---------------------|
| UI | Separate view with segmented control | Same view with budget card |
| Flex slider | Hidden in Fixed Budget mode | Always available |
| Protect/Skip | Available but separate | Same as always |
| Statistics | Different view | Same as always |
| Mental model | Two planning systems | One system with budget helper |
| Timeline | Permanent schedule view | Preview in calculator only |
| Per-goal editing | Not available | Always available |
| Complexity | High (two modes) | Low (one mode + tool) |

## Benefits of v2

1. **Familiar interface** - Users keep their existing workflow
2. **Additive, not replacing** - Budget is a helper, not a mode
3. **Full flexibility** - Can tweak any goal after applying budget
4. **Simpler mental model** - No mode switching confusion
5. **Less code** - Reuse existing planning UI, remove duplicate views
6. **Better discoverability** - Budget option visible in main view
