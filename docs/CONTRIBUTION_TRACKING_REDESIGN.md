# Contribution Tracking Architecture

> Timestamp-based contribution tracking system for monthly execution

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-07-28 |
| Platform | Shared |
| Audience | Developers |

---

## Overview

This document describes the timestamp-based contribution tracking system used for monthly execution tracking. The system derives contribution values dynamically from timestamps rather than maintaining separate contribution records.

**Core Principle:** Timestamps determine what counts toward execution.

```
ExecutionRecord.startedAt = 2025-12-01T00:00:00

All value changes WHERE timestamp >= startedAt
    → automatically reflected in execution tracking
```

---

## Value Change Events

A **"value change"** is any event that modifies the value allocated to a goal-asset pair. The system tracks three sources:

| Source | Model | What Changes | Timestamp Field |
|--------|-------|--------------|-----------------|
| **Manual Transaction** | `Transaction` | Asset balance increases/decreases | `transaction.date` |
| **Blockchain Transaction** | `Transaction` | Asset balance from on-chain detection | `transaction.date` |
| **Allocation Change** | `AllocationHistory` | Distribution of asset to goals | `history.timestamp` |

All three sources change the **amount** allocated to a goal-asset pair.

### Why AllocationHistory Exists

`AssetAllocation` stores only the **current state**. When a user changes an allocation from 0.5 BTC to 0.3 BTC, the old value is lost. `AllocationHistory` records each change as a timestamped snapshot, enabling:

- Querying "what was allocated during execution period X?"
- Calculating progress based on when changes occurred
- Complete audit trail of allocation decisions

```swift
// Calculate execution progress
let transactionChanges = transactions.filter { $0.date >= execution.startedAt }
let allocationChanges = allocationHistory.filter { $0.timestamp >= execution.startedAt }

// Current value for each goal based on:
// - Transaction amounts at their timestamps
// - Allocation amounts at their timestamps
// - The platform's explicit execution-rate policy
```

---

## Core Rules

### Rule 1: New Transaction Allocation

When a new transaction (manual or blockchain) arrives, allocation depends on the asset's current state:

| Asset State | New Transaction Goes To |
|-------------|-------------------------|
| 100% allocated to ONE goal | That goal (automatically) |
| Shared between multiple goals | Unallocated (user must allocate) |
| Partially allocated (has unallocated portion) | Unallocated (user must allocate) |

**Rationale:**
- If an asset is fully dedicated to one goal, the destination is unambiguous
- If an asset is shared or partially allocated, the system doesn't guess—the user decides

```swift
func handleNewTransaction(asset: Asset, amount: Double) {
    let allocations = asset.allocations.filter { $0.amount > 0 }

    if allocations.count == 1 && isFullyAllocated(asset) {
        // 100% to one goal → auto-allocate
        let goal = allocations.first!.goal
        recordAllocationHistory(asset: asset, goal: goal, newTargetAmount: currentTarget + amount)
    } else {
        // Shared or partial → goes to unallocated
        // User sees increased unallocated balance
        // No AllocationHistory record created
    }
}
```

### Rule 2: AllocationHistory Snapshots

`AllocationHistory` stores the allocation target at a point in time. Manual
edits are ordinary amount snapshots. Automatic transaction-driven changes also
store the source transaction ID and the exact target immediately before that
movement so later correction or deletion can replay the sequence safely.

```swift
// Examples:
AllocationHistory(
    asset: BTC,
    goal: GoalA,
    amount: 0.5,
    timestamp: Jan 1,
    sourceTransactionId: deposit.id,
    sourcePreviousAmount: 0
) // Automatic target: 0.5 BTC
AllocationHistory(asset: BTC, goal: GoalA, amount: 0.3, timestamp: Jan 10) // Target changed
AllocationHistory(asset: BTC, goal: GoalB, amount: 0.2, timestamp: Jan 10) // New allocation

// To get allocation target for GoalA at time T:
let targetAtT = allocationHistory
    .filter { $0.goal == goalA && $0.timestamp <= t }
    .max(by: { $0.timestamp < $1.timestamp })?
    .amount ?? 0
```

### Rule 3: Pre-Execution Allocations

Allocations existing before tracking starts define the **starting allocation target** but do not count as contributions.

- Value changes are counted only when they occur `>= execution.startedAt`
- At `execution.startedAt`, the current allocation targets are snapshotted
- Later allocation edits and balance changes are evaluated against this baseline

### Rule 4: Model Responsibilities

| Model | Purpose | Used For |
|-------|---------|----------|
| `AssetAllocation` | Current state | UI display, "what is allocated now" |
| `AllocationHistory` | Historical snapshots | Execution calculations, audit trail |

Both stay in sync: when `AssetAllocation` changes, a new `AllocationHistory` snapshot is recorded.

---

## Design Decisions

### 1. Exchange Rate Handling

#### Apple execution-rate policy

**Decision:** Apple uses the current exchange rate during active execution.

**Rationale:**
- Apple reflects the current financial situation during active execution.
- Completion freezes the final values for historical reporting.

**Behavior:**
- **During Apple execution:** Dynamic calculation with current rates (numbers
  may shift).
- **On Apple completion:** Rates are frozen in the `CompletedExecution`
  snapshot.
- **After Apple completion:** The historical record is immutable.

```swift
let currentRate = await exchangeService.fetchRate(from: asset.currency, to: goal.currency)
let currentValue = assetAmount * currentRate
```

#### Android execution-rate persistence

Android deliberately uses a narrower, platform-specific policy for execution
tracking: it captures asset-to-goal-currency rates at execution start and stores
them in `execution_asset_rates` under the execution record. The Android session
and completion flows reuse that snapshot after a process restart; they do not
fetch live FX rates. A missing required Android snapshot is an explicit error,
not a zero-value contribution. This does not describe the current Apple policy.

Room schema version 6 introduced this table with a composite key of execution,
asset, and snapshot currency. A new execution captures rates only for assets
required by the execution's immutable goal/allocation snapshot. Legacy
backfill also includes historically relevant assets that were later removed
from current allocations. An unrelated asset cannot block the month, and an
asset added after Start cannot enter the active execution without an already
persisted rate.

Migration 5-to-6 marks active legacy executions and closed executions whose undo
window remains open as pending backfill. On first resolution, Android captures
the complete rate matrix for the execution-relevant assets, persists it
atomically, and clears the marker. A partial or invalid matrix is treated as
corruption rather than silently replaced or valued at zero.

### 2. Execution Completion & Immutability

When a user completes a month's execution, all data is snapshotted:

```swift
struct CompletedExecution {
    let monthLabel: String
    let completedAt: Date
    let goals: [GoalSnapshot]
    let contributions: [ContributionSnapshot]  // IMMUTABLE
    let exchangeRates: [String: Double]        // Rates at completion time
}
```

After completion, the record is immutable and answers questions like "How did I perform in January 2025?" with exact numbers.

### 3. Goal Lifecycle States

Goals have three distinct end states:

| Action | Allocations | Goal Record | Use Case |
|--------|-------------|-------------|----------|
| **Cancel** | Freed for reuse | Marked cancelled | User abandons goal |
| **Finish** | Manual retained as spent; on-chain released; mixed chosen once | Immutable completion snapshot | Goal achieved without double-counting |
| **Delete** | Removed from tracking | Old finished plans unchanged | Cleanup |

```swift
enum GoalLifecycleStatus: String, Codable {
    case active
    case cancelled
    case finished
}
```

**Query patterns:**
- Active execution/planning: `WHERE status == .active`
- Historical views: Include `.finished` goals
- Cancelled goals: Hidden from active views, allocations freed

#### Balance Accounting Modes at Finish

Finished-allocation settlement follows the configured balance source rather than one universal retention rule:

- **Manual:** the asset has no complete wallet address and chain configuration. The app ledger is the balance
  authority, so the allocation is retained as spent.
- **On-chain:** the asset has complete wallet tracking and no manual transactions. The tracked wallet balance has
  already decreased after an external purchase, so the allocation is released.
- **Mixed:** the asset has complete wallet tracking and at least one manual transaction. The source of the spent
  amount is ambiguous, so the user chooses once between retaining it as spent and releasing it.

The presence of manual transaction history makes an asset mixed even when its current net manual balance is zero.
Wallet refresh success or freshness does not change the accounting mode.

#### Immutable Completion Snapshot

Before a goal is marked Finished or any current allocation is released, the app records one immutable completion
snapshot. Its raw allocation quantities are the historical authority. Best-known balances and converted display
values are optional context only: missing prices or wallet balances cannot block completion, and a balance observed
during later legacy review must not be presented as the earlier completion-time balance.

The snapshot and settlement changes are persisted atomically in one save. That save includes retained or released
allocations, zero-value allocation-history records for releases, the Finished lifecycle state, and removal from
active execution tracking. A failure leaves all of those states unchanged; lifecycle notifications are published
only after the save succeeds.

#### Legacy Finished Allocations

A finished goal that still has allocations but has no completion snapshot is a legacy pending-review record. Its
allocations remain unavailable and are never released automatically. `Later` makes no changes. Applying review
resolves every allocation of each affected goal together, creates its immutable snapshot, and makes the selected
retain-or-release decisions final.

The allocation editor distinguishes legacy `Pending review` amounts from snapshot-confirmed `Reserved as spent`
amounts. Released allocations are removed from current allocation totals and remain visible through the finished
goal snapshot and history.

These finish semantics and the snapshot format are a shared platform contract. The initial implementation is on
iOS; Android must follow the same manual, on-chain, mixed, legacy-review, atomicity, and raw-quantity rules when its
implementation is added.

### 4. Performance & Caching

The system uses `ExecutionProgressCache` to avoid recalculating on every access:

```swift
class ExecutionProgressCache {
    private var cachedProgress: [UUID: GoalProgress] = [:]

    func getProgress(for goal: Goal) -> GoalProgress {
        if let cached = cachedProgress[goal.id], !needsRefresh() {
            return cached
        }
        let fresh = calculateProgress(for: goal)
        cachedProgress[goal.id] = fresh
        return fresh
    }

    func invalidate() {
        cachedProgress.removeAll()
    }
}
```

Cache is invalidated on:
- New transaction added
- Allocation changed
- Significant exchange rate change (> 1%)

### 5. Allocation Edge Cases

**Unallocated portions:**
- Valid state representing money for daily spending
- No system action required

**Over-allocated (sum > current balance):**
- Can occur when users withdraw from on-chain addresses outside the app
- Treated as valid runtime state: allocations represent the *plan*, not guaranteed balance
- UI shows "Underfunded by X" shortfall
- Calculations distribute available balance proportionally across targets

```swift
// Under-allocated (daily spending money)
Asset: 1 BTC
Goal A: 0.3 BTC
Goal B: 0.3 BTC
Total: 0.6 BTC allocated
Unallocated: 0.4 BTC  // For daily expenses

// Over-allocated (savings target exceeds balance)
Asset: 1 BTC
Goal A: 0.6 BTC
Goal B: 0.6 BTC
Total: 1.2 BTC allocated
Shortfall: 0.2 BTC  // Need to add more to fully fund
```

---

## Data Models

### AllocationHistory

Records each allocation change as a timestamped snapshot:

```swift
@Model
final class AllocationHistory {
    @Attribute(.unique) var id: UUID
    var asset: Asset?
    var goal: Goal?
    var amount: Double      // Target amount in asset currency
    var timestamp: Date     // When this change occurred
    var createdAt: Date     // Tie-breaker for same-timestamp records
    var monthLabel: String  // "yyyy-MM" for efficient queries
    var sourceTransactionId: UUID?    // Automatic-change provenance
    var sourcePreviousAmount: Double? // Exact target before that movement

    init(
        asset: Asset,
        goal: Goal,
        amount: Double,
        timestamp: Date = Date(),
        sourceTransactionId: UUID? = nil,
        sourcePreviousAmount: Double? = nil
    ) {
        self.id = UUID()
        self.asset = asset
        self.goal = goal
        self.amount = amount
        self.timestamp = timestamp
        self.createdAt = Date()
        self.monthLabel = MonthlyExecutionRecord.monthLabel(from: timestamp)
        self.sourceTransactionId = sourceTransactionId
        self.sourcePreviousAmount = sourcePreviousAmount
    }
}
```

**Usage in AllocationService:**

```swift
func saveAllocations(asset: Asset, allocations: [UUID: Double]) {
    for (goalId, newAmount) in allocations {
        let oldAmount = allocation.amountValue

        // Update current state
        allocation.updateAmount(newAmount)

        // Record snapshot if changed
        if abs(newAmount - oldAmount) > 0.0001 {
            let history = AllocationHistory(asset: asset, goal: goal, amount: newAmount)
            modelContext.insert(history)
        }
    }
}

// Get allocation target at specific time
func getAllocationTarget(asset: Asset, goal: Goal, at date: Date) -> Double {
    allocationHistory
        .filter { $0.asset == asset && $0.goal == goal && $0.timestamp <= date }
        .max(by: { $0.timestamp < $1.timestamp })?
        .amount ?? 0
}
```

### CompletedExecution

Stores immutable completion snapshots:

```swift
@Model
final class CompletedExecution {
    var id: UUID
    var monthLabel: String
    var completedAt: Date
    var exchangeRatesSnapshotData: Data?      // Encoded [String: Double]
    var goalSnapshotsData: Data?              // Encoded [GoalSnapshot]
    var contributionSnapshotsData: Data?      // Encoded [ContributionSnapshot]

    @Relationship(inverse: \MonthlyExecutionRecord.completedExecution)
    var executionRecord: MonthlyExecutionRecord?
}
```

### ExecutionSnapshot

Captures plan state when execution starts:

```swift
@Model
final class ExecutionSnapshot {
    var id: UUID
    var capturedAt: Date
    var totalPlanned: Double
    var snapshotData: Data  // Encoded [ExecutionGoalSnapshot]

    @Relationship(inverse: \MonthlyExecutionRecord.snapshot)
    var executionRecord: MonthlyExecutionRecord?
}
```

---

## Key Services

### ExecutionProgressCalculator

Calculates contribution progress by querying timestamps:

```swift
class ExecutionProgressCalculator {
    func calculateProgress(
        for goal: Goal,
        since startDate: Date,
        allocations: [AssetAllocation],
        allocationHistory: [AllocationHistory],
        transactions: [Transaction]
    ) async -> GoalProgress {
        // Filter to relevant time period
        let relevantHistory = allocationHistory.filter { $0.timestamp >= startDate }
        let relevantTransactions = transactions.filter { $0.date >= startDate }

        // Calculate value changes from both sources
        // Apply current exchange rates
        // Return progress
    }
}
```

### ExecutionTrackingService

Coordinates execution lifecycle:

```swift
class ExecutionTrackingService {
    func startTracking(for record: MonthlyExecutionRecord, plans: [MonthlyPlan], goals: [Goal])
    func completeExecution(_ record: MonthlyExecutionRecord) async throws
    func undoStartTracking(_ record: MonthlyExecutionRecord)
    func undoCompletion(_ record: MonthlyExecutionRecord)
}
```

---

## Benefits Over Previous Architecture

| Aspect | Previous (Two Bridging Paths) | Current (Timestamp-Based) |
|--------|-------------------------------|---------------------------|
| Source of truth | Two code paths creating contributions | Timestamps on Transaction + AllocationHistory |
| Allocation changes | Delete & recreate contributions | Query AllocationHistory by timestamp |
| Exchange rates | Stored at contribution time | Apple: current during execution, frozen on completion; Android: immutable execution-start snapshot |
| Performance | Recalculate on every change | Cache + invalidate |
| Audit trail | Current state only | Complete history via AllocationHistory |
| Code complexity | High (two paths, bridging logic) | Low (one calculation path) |

Android freezes the complete execution-relevant asset/rate matrix at Start.
Legacy executions include both the current and historically relevant asset
scope once per backfill attempt and keep the first matrix committed atomically
by concurrent callers. Unrelated assets are excluded. Assets introduced later
cannot be allocated into an active execution without a persisted rate, and an
asset currency cannot change while an execution using its rate remains active
or undoable.

Execution start and legacy backfill capture an exact fingerprint of asset
currency and allocation scope before fetching rates. Their commit phase runs
through the same Room transaction boundary as allocation and asset-currency
mutations, rechecks that fingerprint, and rejects a stale result rather than
committing rates for a changed scope. Allocation validation and persistence are
also performed inside that shared transaction, so concurrent add or update
operations cannot both validate against the same old balance and over-allocate
the asset.

---

## Testing Requirements

### Over-Allocated State Handling
- Setup: allocations sum > `asset.currentAmount`
- Expectation: UI renders, execution progress completes, shortfall displayed

### Timestamp Boundaries
- Allocation changes before `execution.startedAt` should not affect progress
- Allocation changes after `execution.startedAt` should affect progress
- Transactions before tracking starts do not count
- Transactions after tracking starts do count

### Auto-Allocation (Rule 1)
- Asset 100% to one goal + new transaction → auto-allocated
- Asset shared between goals + new transaction → unallocated
- Asset partially allocated + new transaction → unallocated

### AllocationHistory Reconstruction
- Multiple snapshots over time (0.5, 0.3, 0.6)
- Query at intermediate timestamp returns correct value

---

## Related Documentation

- [Contribution flow](CONTRIBUTION_FLOW.md) - Timestamp-based execution
  tracking flows
- [CloudKit migration plan](CLOUDKIT_MIGRATION_PLAN.md) - CloudKit
  compatibility requirements for Apple models
- [Application defect audit](audits/APPLICATION_DEFECT_AUDIT_2026-07-25.md) -
  evidence and verification for the execution-rate correction

---

*Last updated: 2026-07-27*
