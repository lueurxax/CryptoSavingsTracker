# Contribution Process

> Optimized UX for monthly contributions with shared assets and multi-currency execution

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-01-04 |
| Platform | Shared |
| Audience | Developers |

---

The contribution process provides an optimized experience for monthly contributions, particularly for shared assets and multi-currency execution. It includes an "Add to Close Month" action that computes required contribution amounts with currency conversion, prioritizes the current goal in share-asset lists, and allows execution tracking to display remaining amounts in a user-selected currency.

This feature is additive and does not change the timestamp-based execution model described in `docs/CONTRIBUTION_FLOW.md`.

## Overview

The contribution process addresses three key user needs:

- **Fast month closing**: Quickly contribute the exact amount needed to close the current month, including shared assets
- **Reduced friction**: Surface the current goal first in share-asset UI
- **Currency flexibility**: Contribute in a preferred currency while showing accurate per-goal progress

**Key characteristics:**
- Integrates with existing execution tracking views
- Uses existing snapshot and derived totals (no new storage required)
- Preserves the allocation model (AssetAllocation + AllocationHistory)
- Does not persist per-contribution records during execution (the execution model remains derived)

## Quick Start

### Adding to Close Month (Dedicated Asset)

1. Open **Execution Tracking** during an active month
2. Find the goal you want to contribute to
3. Tap **Add to Close Month** on the goal card
4. The transaction form opens with the required amount pre-filled
5. Complete the transaction to close the month for that goal

### Adding to Close Month (Shared Asset)

1. Open **Execution Tracking** during an active month
2. Find the goal you want to contribute to
3. Tap **Add to Close Month** on the goal card
4. Select a shared asset
5. The allocation form opens with targets pre-filled to increase the goal's allocation by the required amount
6. Adjust if needed and confirm

### Changing Display Currency

1. Open **Execution Tracking**
2. Use the currency selector in the header
3. All remaining amounts update to show in the selected currency

## User Interface

### Execution View Goal Cards

Each goal card in the execution view displays:

- Goal name and progress
- Remaining amount to close the month
- **Add to Close Month** button (when remaining amount > 0)

The button is disabled when:
- The month is closed or in draft state
- The goal has zero remaining (already closed for this goal)

### Share-Asset List Ordering

When opening the share-asset view from a goal context:

- The current goal appears at the top of the list
- Remaining goals are sorted alphabetically
- Visual indicator shows which goal triggered the share view

### Currency Selector

The execution view header includes a currency selector:

- Dropdown shows available currencies
- Selection persists across sessions
- Rate timestamp shows when rates were last updated
- Converts all displayed amounts:
  - Remaining-to-close per goal
  - Total remaining for the month

## Algorithm

### Remaining Amount Calculation

The system computes the remaining amount to close a goal for the current month:

```
remainingToClose = max(0, plannedAmount - contributedAmount)
```

Where:
- `plannedAmount` comes from the execution snapshot (planned month amount)
- `contributedAmount` comes from the execution calculator's current derived totals

### Currency Conversion

When the display currency differs from the goal currency:

1. Fetch the current exchange rate from `ExchangeRateService`
2. Convert `remainingToClose` from goal currency to display currency
3. Display the converted amount with the rate timestamp

### Dedicated Asset Pre-fill

For assets dedicated to a single goal:

1. Calculate `remainingToClose` in goal currency
2. Convert to asset currency if different
3. Pre-fill the Add Transaction amount field

### Shared Asset Pre-fill

For assets shared across multiple goals:

1. Calculate `remainingToClose` in goal currency
2. Convert to asset currency
3. Pre-fill allocation targets to increase the chosen goal's allocation by the converted amount
4. Clamp to available asset balance if needed

## Data Model

### Settings Storage

The display currency selection is stored in the planning settings:

```kotlin
// Android - MonthlyPlanningSettings.kt
data class MonthlyPlanningSettings(
    val monthlyBudget: Double?,
    val budgetCurrency: String,
    val executionDisplayCurrency: String?,  // null = use goal currency
    // ... other settings
)
```

```swift
// iOS - MonthlyPlanningSettings.swift
struct MonthlyPlanningSettings {
    var monthlyBudget: Double?
    var budgetCurrency: String
    var executionDisplayCurrency: String?  // nil = use goal currency
    // ... other settings
}
```

### Calculator Result

The contribution calculator generates results on-demand:

```kotlin
// Android
data class ContributionSuggestion(
    val goalId: UUID,
    val remainingAmount: Double,
    val remainingCurrency: String,
    val convertedAmount: Double?,
    val convertedCurrency: String?,
    val rateTimestamp: Instant?
)
```

```swift
// iOS
struct ContributionSuggestion {
    let goalId: UUID
    let remainingAmount: Double
    let remainingCurrency: String
    let convertedAmount: Double?
    let convertedCurrency: String?
    let rateTimestamp: Date?
}
```

## Edge Cases

### Missing Exchange Rates

When exchange rates are unavailable:
- Fall back to displaying amounts in goal currency
- Show a warning indicating rates could not be fetched
- The "Add to Close Month" action still works using goal currency

### Shared Asset Over-Allocation

When the suggested allocation exceeds available balance:
- Clamp pre-filled allocations to the available balance
- Show a warning explaining the shortfall
- User can still proceed with partial contribution

### Closed or Draft Month

When the month is not in an active execution state:
- "Add to Close Month" button is disabled
- Tooltip or message explains the current state

### Already Closed Goal

When a goal has zero remaining for the month:
- Show "Month closed for this goal" state
- "Add to Close Month" button is hidden or disabled

## Contribution Flow

```
User taps "Add to Close Month"
         |
         v
+------------------+
| Get remaining    |
| from snapshot +  |
| derived totals   |
+------------------+
         |
         v
+------------------+
| Convert to       |
| display currency |
| (if different)   |
+------------------+
         |
         v
    Is asset shared?
    /           \
   No            Yes
   |              |
   v              v
+----------+  +---------------+
| Pre-fill |  | Pre-fill      |
| amount   |  | allocation    |
| in Add   |  | targets in    |
| Transaction| | Share Asset   |
+----------+  +---------------+
   |              |
   v              v
User completes transaction
         |
         v
Execution progress updates
```

## Source Files

### iOS

| File | Purpose |
|------|---------|
| `Services/ExecutionContributionCalculator.swift` | Core calculation logic for remaining amounts |
| `Services/ExecutionProgressCalculator.swift` | Derives contribution totals from transactions |
| `Views/Planning/MonthlyExecutionView.swift` | Execution tracking UI with currency selector |
| `ViewModels/MonthlyExecutionViewModel.swift` | State management and currency selection |
| `Views/AssetSharingView.swift` | Share-asset UI with goal ordering |
| `Views/Components/GoalAllocationCard.swift` | Goal card with "Add to Close Month" action |
| `Models/MonthlyPlanningSettings.swift` | Settings storage including display currency |

### Android

| File | Purpose |
|------|---------|
| `domain/usecase/execution/ExecutionContributionCalculatorUseCase.kt` | Core calculation logic for remaining amounts |
| `domain/usecase/execution/ExecutionProgressCalculator.kt` | Derives contribution totals from transactions |
| `presentation/execution/ExecutionScreen.kt` | Execution tracking UI with currency selector |
| `presentation/execution/ExecutionViewModel.kt` | State management and currency selection |
| `presentation/execution/components/GoalProgressCard.kt` | Goal card with "Add to Close Month" action |
| `presentation/assets/AssetSharingScreen.kt` | Share-asset UI with goal ordering |
| `presentation/assets/AssetSharingViewModel.kt` | Share-asset state management |
| `domain/model/MonthlyPlanningSettings.kt` | Settings storage including display currency |

## Related Documentation

- [Contribution Flow](CONTRIBUTION_FLOW.md) - Timestamp-based execution model
- [Budget Calculator](BUDGET_CALCULATOR.md) - Planning tool for optimal contributions
