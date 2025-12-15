# Contribution Flow (Timestamp-Based Execution Tracking)

## Overview

This project tracks monthly plan fulfillment without “bridging” transactions into persisted contributions during execution.

- **While a month is executing:** progress is **derived on the fly** from timestamps.
- **When a month is completed:** derived events are **snapshotted into persisted** `Contribution` records for history/immutability.

## Key Models

### `Transaction`
Represents any balance change for an `Asset` (manual or blockchain-imported).

- Timestamp: `transaction.date`
- Amount: `transaction.amount` (can be negative for withdrawals)

### `AssetAllocation`
The current allocation **target** from an asset to a goal (amount-only).

- Field of interest: `amountValue` (in the asset’s currency)

### `AllocationHistory`
The historical record of allocation **target snapshots** over time for a `(goal, asset)` pair.

- Field of interest: `amount` (target amount in asset currency at that timestamp)
- Timestamp: `history.timestamp`

### `MonthlyExecutionRecord`
Defines the window of what “counts” for a month’s execution.

- Start timestamp: `record.startedAt`
- Status: `.draft` → `.executing` → `.closed`

## How Execution Progress Is Derived

The engine derives “contribution” as **funding deltas** over time:

1. Compute asset **balance** over time from `Transaction` changes.
2. Compute allocation **targets** over time from `AllocationHistory` (fallback to current `AssetAllocation` if needed).
3. Convert balance + targets into “funded amounts per goal”:
   - If `sum(targets) <= balance`: each goal is fully funded up to its target; extra is **unallocated** (daily spending).
   - If `sum(targets) > balance`: treat as a valid state and distribute the available balance **proportionally** across targets.
4. Every time balance or targets change, compute the difference in funded amounts and treat that as a derived event for execution totals.

Implementation:
- `CryptoSavingsTracker/Services/ExecutionProgressCalculator.swift`

## Core Flows

### 1) Start Tracking (Planning → Executing)

When a user starts tracking for a month:

- `MonthlyExecutionRecord.startedAt` is set.
- A baseline `AllocationHistory` snapshot is seeded for tracked goals/assets at `startedAt` so the engine has a stable reference point.

Implementation:
- `CryptoSavingsTracker/Services/ExecutionTrackingService.swift:startTracking(...)`

### 2) Add a Transaction

Saving a transaction always:
- Inserts `Transaction(amount:, date:, asset:)`.

Auto-allocation rule (to avoid “guessing” when an asset is shared):
- If the asset was **fully allocated to exactly one goal** before the deposit, we keep it fully allocated by:
  - Increasing that single `AssetAllocation` target to the new balance, and
  - Writing an `AllocationHistory(amount:)` snapshot at the transaction timestamp.
- Otherwise (shared or partially allocated), no allocation history is written and the change remains **unallocated** unless the user adjusts allocation targets.

Implementation:
- `CryptoSavingsTracker/Views/AddTransactionView.swift:1`

### 3) Change Allocations (Share Asset / Edit Targets)

When a user edits allocations:

- `AssetAllocation` current state is updated.
- For every changed goal, an `AllocationHistory(amount:)` snapshot is inserted at the save timestamp.
- If a goal is removed from allocations, an `AllocationHistory(amount: 0)` snapshot is inserted.

UI can hard-block saving allocations that exceed current balance, but the persisted state can still become over-allocated later (e.g., external withdrawals). Execution calculations must remain defensive and not crash.

Implementation:
- `CryptoSavingsTracker/Services/AllocationService.swift:updateAllocations(for:newAllocations:)`
- `CryptoSavingsTracker/Views/AssetSharingView.swift:1`

### 4) MonthlyExecutionView (Read-Only Display)

`MonthlyExecutionView` is read-only by design. It displays:

- Planned amounts (from live `MonthlyPlan` during execution, frozen snapshot after closing)
- **Derived contributed totals** during execution (not persisted `Contribution` rows)
- Persisted `Contribution` totals for closed months

Implementation:
- `CryptoSavingsTracker/ViewModels/MonthlyExecutionViewModel.swift:323`
- `CryptoSavingsTracker/Services/ExecutionTrackingService.swift:getDerivedContributionTotals(...)`

### 5) Finish Month (Executing → Closed)

When a user completes the month:

- Derived events from `startedAt … completedAt` are snapped into persisted `Contribution` records (with exchange-rate snapshots).
- History views (and closed-month execution UI) use these persisted contributions as immutable records.

Implementation:
- `CryptoSavingsTracker/Services/ExecutionTrackingService.swift:markComplete(_:)`

## What Changed vs. the Old System

The legacy system created and re-created persisted contributions during execution (transaction-bridging + re-bridging on allocation changes). That approach is intentionally removed in favor of timestamp-based derivation.

If you’re looking for the old entry points, they are no longer part of the active execution flow.

