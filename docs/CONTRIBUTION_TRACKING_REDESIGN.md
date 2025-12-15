# Contribution Tracking Redesign

## Problem Statement

### Current Architecture Issues

The current contribution tracking system uses **two separate paths** for creating contributions:

| Path | Trigger | Location |
|------|---------|----------|
| Path A | New transaction added | `AddTransactionView.linkTransactionToCurrentExecution` |
| Path B | Allocation changed | `AllocationService.rebridgeCurrentMonthTransactions` |

**Problems with this approach:**

1. **No single source of truth** - Two different code paths create contributions with different logic
2. **Destructive re-bridging** - Path B deletes ALL existing contributions and recreates them when allocations change
3. **Complex state management** - Must track what's been bridged vs. not bridged
4. **Potential race conditions** - Transaction added while allocation change is processing
5. **Difficult to debug** - Two entry points with `[REBRIDGE]` logs, hard to trace issues
6. **Fragile** - Easy to introduce bugs when modifying either path

### Root Cause

The fundamental issue is that contributions are **actively created and managed** rather than being **derived from timestamps**.

---

## Proposed Solution: Timestamp-Based Tracking

### Core Principle

**Single source of truth: Timestamps determine what counts toward execution.**

```
ExecutionRecord.startedAt = 2025-12-01T00:00:00

All value changes WHERE timestamp >= startedAt
    → automatically reflected in execution tracking
```

### Value Changes (Abstract Concept)

**"Value Change"** is an abstract term for any event that changes the value in a **goal-asset pair**. There are three sources, all using existing or slightly modified models:

| Source | Model | What Changes | Timestamp Source |
|--------|-------|--------------|------------------|
| **Manual Transaction** | `Transaction` | Asset balance increases/decreases | `transaction.date` (existing) |
| **Blockchain Transaction** | `Transaction` | Asset balance from on-chain detection | `transaction.date` (from blockchain) |
| **Allocation Change** | `AllocationHistory` (NEW) | Distribution of asset to goals | `history.timestamp` |

**Key insight:** All three sources change the **amount** allocated to a goal-asset pair.

**Important:** `AssetAllocation` stores only **current state** - when user changes 0.5 BTC → 0.3 BTC, the old value is lost. We need `AllocationHistory` to record each change for execution tracking.

```swift
// Pseudo-code for execution progress
let transactionChanges = transactions.filter { $0.date >= execution.startedAt }
let allocationHistory = allocationHistories.filter { $0.timestamp >= execution.startedAt }

// Calculate current value for each goal based on:
// - Transaction amounts at their timestamps
// - Allocation amounts at their timestamps
// - Current exchange rates
```

### Key Benefits

1. **No bridging logic** - No "create contributions" step needed
2. **No re-bridging** - Allocation changes don't require reprocessing
3. **Simpler mental model** - "Everything after start date counts"
4. **Idempotent** - No delete/recreate cycles
5. **Complete audit trail** - All changes preserved with timestamps

---

## Core Rules

### Rule 1: How New Transactions Are Allocated

When a new transaction (manual or blockchain) arrives, allocation depends on the **current state** of the asset:

| Asset State | New Transaction Goes To |
|-------------|-------------------------|
| 100% allocated to ONE goal | That goal (automatically) |
| Shared between multiple goals | **Unallocated** (user must allocate manually) |
| Partially allocated (has unallocated portion) | **Unallocated** (user must allocate manually) |

**Rationale:**
- If asset is fully dedicated to one goal, it's clear where new money goes
- If asset is shared or partially allocated, the app shouldn't guess - user decides

```swift
// Pseudo-code for transaction arrival
func handleNewTransaction(asset: Asset, amount: Double) {
    let allocations = asset.allocations.filter { $0.amount > 0 }

    if allocations.count == 1 && isFullyAllocated(asset) {
        // 100% to one goal → auto-allocate
        let goal = allocations.first!.goal
        // Increase the allocation target and record a snapshot (amount-only)
        // so execution tracking can derive funded deltas without re-bridging.
        recordAllocationHistory(asset: asset, goal: goal, newTargetAmount: currentTarget + amount)
    } else {
        // Shared or partial → goes to unallocated
        // User sees increased unallocated balance
        // No AllocationHistory record created
    }
}
```

### Rule 2: AllocationHistory Records Amount Snapshots

`AllocationHistory` stores **amount-only snapshots** of the allocation target at a point in time (no percentages).

```swift
// Examples:
AllocationHistory(asset: BTC, goal: GoalA, amount: 0.5, timestamp: Jan 1)  // Target: 0.5 BTC to GoalA
AllocationHistory(asset: BTC, goal: GoalA, amount: 0.3, timestamp: Jan 10) // Target changed: 0.3 BTC
AllocationHistory(asset: BTC, goal: GoalB, amount: 0.2, timestamp: Jan 10) // Target changed: 0.2 BTC

// To get allocation target for GoalA at time T:
let targetAtT = allocationHistory
    .filter { $0.goal == goalA && $0.timestamp <= t }
    .max(by: { $0.timestamp < $1.timestamp })?
    .amount ?? 0
```

**Why snapshots are used:**
- Amount-only (percentage was a doc mistake)
- Easy to reconstruct "target at time T" using `latest <= timestamp`
- Matches the UI mental model (“I set Goal A to 0.3 BTC”)

### Rule 3: Pre-Execution Allocations Count

Allocations that exist before tracking starts define the **starting allocation target**, but **do not count as contributions by themselves**.

- Tracking is timestamp-based: value changes are counted only when they occur `>= execution.startedAt`.
- At `execution.startedAt`, snapshot current allocation targets so later allocation edits and balance changes can be evaluated correctly.

### Rule 4: Model Responsibilities

| Model | Purpose | Used For |
|-------|---------|----------|
| `AssetAllocation` | Current state | UI display, "what is allocated now" |
| `AllocationHistory` | Historical snapshots | Execution calculations, audit trail |

Both stay in sync: when `AssetAllocation` changes, record a new `AllocationHistory(amount:)` snapshot.

---

## Design Decisions

### 1. Exchange Rate Handling

**Decision: Use CURRENT exchange rate**

**Rationale:**
- If rate changes during execution, your real contribution value changed - this is reality
- The app should reflect current financial situation, not historical snapshots
- User who wants predictable contributions should execute quickly (hours, not days)

**Future Enhancement:**
- Calculate "volatility gap" based on currency volatility
- Show warning: "BTC is volatile, your $500 contribution could range from $450-$550"
- If user contributes MORE than planned due to rate increase, that's not a problem

```swift
// Display logic
let currentRate = await exchangeService.fetchRate(from: asset.currency, to: goal.currency)
let currentValue = assetAmount * currentRate
```

### 2. Audit Trail & History

**Decision: Store history of all value changes**

All three sources need timestamps for history:

```swift
// 1. Manual Transaction (existing)
@Model class Transaction {
    var amount: Double
    var date: Date  // Already exists - when user added via UI
}

// 2. Blockchain Transaction (same model)
// Uses Transaction with date from blockchain

// 3. AllocationHistory (NEW - records target snapshots)
@Model class AllocationHistory {
    var asset: Asset
    var goal: Goal
    var amount: Double            // Allocation target in asset currency at this timestamp
    var timestamp: Date           // When this change occurred
}
```

**Why we need AllocationHistory:**
- `AssetAllocation` only stores **current state**
- When user changes 0.5 BTC → 0.3 BTC, the 0.5 BTC value is lost
- For execution tracking, we need to know: "What was allocated during this period?"
- `AllocationHistory` preserves each change as a separate record

**Result:**
- Complete history of all value movements
- Can build any view: current execution, past plans, full asset history
- Data exists for future features without schema changes

### 3. Goal Lifecycle: Cancel vs. Finish vs. Delete

**Three distinct states:**

| Action | Contributions | Goal Record | Use Case |
|--------|---------------|-------------|----------|
| **Cancel** | Become unallocated, reusable | Marked cancelled | User abandons goal, wants money back |
| **Finish** | Marked as "spent" | Preserved for history | Goal achieved, keep for analysis |
| **Delete** | Removed from current tracking | Old finished plans unchanged | Cleanup, but preserve history |

**Rules:**
- Deleting a goal during active tracking → remove from current tracking only
- Finished plans are IMMUTABLE → historical record preserved
- Cancelled goal → contributions return to "unallocated" pool for reuse

```swift
enum GoalStatus {
    case active
    case cancelled(date: Date)    // Contributions freed
    case finished(date: Date)     // Contributions spent, preserved
    case deleted                  // Soft delete, history intact
}
```

### 4. Performance & Caching

**Decision: Cache calculations, invalidate on changes**

```swift
class ExecutionProgressCache {
    private var cachedProgress: [UUID: GoalProgress] = [:]
    private var lastCalculation: Date?

    func getProgress(for goal: Goal) -> GoalProgress {
        if let cached = cachedProgress[goal.id],
           !needsRefresh() {
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

// Invalidate on:
// - New transaction added
// - Allocation changed
// - Exchange rate significantly changed (> 1%?)
```

This is standard caching - not architecturally complex.

### 5. Execution Completion & Immutability

**Decision: Snapshot on completion, immutable thereafter**

When user finishes a month's execution:

```swift
struct CompletedExecution {
    let monthLabel: String
    let completedAt: Date
    let goals: [GoalSnapshot]
    let contributions: [ContributionSnapshot]  // IMMUTABLE
    let exchangeRates: [String: Double]        // Rates at completion time
}

struct ContributionSnapshot {
    let amount: Double
    let amountInGoalCurrency: Double
    let exchangeRateUsed: Double
    let goalId: UUID
    let assetId: UUID
    let timestamp: Date
    // Immutable - never changes after completion
}
```

**Key points:**
- During execution: dynamic calculation with current rates
- On completion: snapshot everything, including exchange rates
- After completion: immutable record for analysis
- Can answer: "How did I perform in January 2025?" with exact numbers

### 6. Allocation Edge Cases

**Unallocated portions:**
- Totally fine - represents money for daily spending (untracked)
- User checks app, sees unallocated balance, uses for daily needs
- No action required from the system

**Over-allocated (sum > current balance):**
- This state can happen even if UI prevents it, because users can withdraw from an on-chain address outside the app
- Treat it as a valid runtime state: allocations represent the *plan*, not a guaranteed available balance
- System shows: "Underfunded by X" (shortfall between allocated amounts and current balance)
- Must not crash or assert; calculations should be defensive
- Execution calculations should remain deterministic; when `sum(targets) > balance`, distribute the available balance proportionally across targets for progress calculations

```swift
// Example: Valid states
Asset: 1 BTC (current balance)

// Under-allocated (daily spending money)
Goal A: 0.3 BTC
Goal B: 0.3 BTC
Total allocated: 0.6 BTC
Unallocated: 0.4 BTC  // For coffee, groceries, etc.

// Over-allocated (savings target)
Goal A: 0.6 BTC
Goal B: 0.6 BTC
Total allocated: 1.2 BTC
Current balance: 1.0 BTC
Shortfall: 0.2 BTC  // Need to add more to fully fund
```

---

## Data Model Changes

### NEW: AllocationHistory Model

Records each allocation **change** (amount-only snapshot) for historical tracking:

```swift
@Model
final class AllocationHistory {
    var id: UUID
    var asset: Asset?
    var goal: Goal?
    var amount: Double               // New target amount in asset currency
    var timestamp: Date              // When this change occurred

    init(asset: Asset, goal: Goal, amount: Double, timestamp: Date = Date()) {
        self.id = UUID()
        self.asset = asset
        self.goal = goal
        self.amount = amount
        self.timestamp = timestamp
    }
}
```

**How it works:**
- Each record represents a new **target snapshot** ("Goal A should have 0.3 BTC")
- To get current target: take the latest record for that goal-asset pair
- To get target at time T: take latest record WHERE `timestamp <= T`

```swift
// In AllocationService.saveAllocations:
func saveAllocations(asset: Asset, allocations: [UUID: Double]) {
    for (goalId, newAmount) in allocations {
        let oldAmount = allocation.amountValue
        _ = newAmount - oldAmount

        // Update current state (existing logic)
        allocation.updateAmount(newAmount)

        // Record snapshot (NEW) - only if actually changed
        if abs(newAmount - oldAmount) > 0.0001 {
            let history = AllocationHistory(asset: asset, goal: goal, amount: newAmount)
            modelContext.insert(history)
        }
    }
}

// Helper: Get allocation target at specific time
func getAllocationTarget(asset: Asset, goal: Goal, at date: Date) -> Double {
    allocationHistory
        .filter { $0.asset == asset && $0.goal == goal && $0.timestamp <= date }
        .max(by: { $0.timestamp < $1.timestamp })?
        .amount ?? 0
}
```

### Modified: Goal Model

```swift
@Model
final class Goal {
    // ... existing properties ...

    var status: GoalStatus = .active
    var cancelledAt: Date?
    var finishedAt: Date?

    enum GoalStatus: String, Codable {
        case active
        case cancelled
        case finished
    }
}
```

### Modified: CompletedExecution (Enhanced)

```swift
@Model
final class CompletedExecution {
    var id: UUID
    var monthLabel: String
    var completedAt: Date
    var exchangeRatesSnapshot: [String: Double]  // Currency pair -> rate
    var goalSnapshots: [GoalSnapshot]
    var contributionSnapshots: [ContributionSnapshot]

    // Immutable after creation
}
```

---

## Migration Path

### Phase 1: Add AllocationHistory Model
1. Create `AllocationHistory` SwiftData model
2. Add to ModelContainer schema
3. Modify `AllocationService.saveAllocations` to create history records
4. Backfill: Create initial history record for each existing `AssetAllocation`

### Phase 2: Implement Dynamic Calculation
1. Create `ExecutionProgressCalculator` service
2. Query transactions by `date` + allocation history by `timestamp`
3. Calculate progress dynamically with current exchange rates
4. Add caching layer
5. Keep existing contribution logic temporarily (parallel run)

### Phase 3: Refactor Goal Lifecycle
1. Add `GoalStatus` enum to Goal model
2. Implement soft-delete for goals
3. Update queries to exclude deleted/cancelled goals from active execution
4. Preserve finished goals for historical review

### Phase 4: Implement Completion Snapshots
1. Enhance completion flow to snapshot all data
2. Store exchange rates at completion time
3. Mark snapshots as immutable

### Phase 5: Remove Old Bridging Logic
1. Remove `linkTransactionToCurrentExecution` from AddTransactionView
2. Remove `rebridgeCurrentMonthTransactions` from AllocationService
3. Delete unused Contribution creation code
4. Update documentation

---

## Summary

| Aspect | Current | Proposed |
|--------|---------|----------|
| Source of truth | Two bridging paths | Timestamps on Transaction + AllocationHistory |
| Allocation changes | Delete & recreate contributions | Record in `AllocationHistory`, query by timestamp |
| Exchange rates | Stored at contribution time | Current during execution, snapshot on completion |
| Goal deletion | Hard delete | Soft delete, preserve history |
| Performance | Recalculate on every change | Cache + invalidate |
| Audit trail | Fragmented (current state only) | Complete history via AllocationHistory |
| Code complexity | High (two paths) | Low (one calculation) |
| Model changes needed | Many (Contribution, bridging) | AllocationHistory (new) + GoalStatus (enum) |

This redesign simplifies the architecture while providing better data for future features like historical analysis, volatility warnings, and progress reviews.

---

## Testing Guidance (Required)

Even if UI forms block saving an over-allocation, the persisted model state can become over-allocated after external on-chain withdrawals. Add tests that ensure the app remains stable:

1. **Over-allocated state does not crash**
   - Setup: allocations sum > `asset.currentAmount` (simulate external withdrawal or stale allocation).
   - Expectation: UI renders, execution progress calculation completes, and a shortfall is displayed.

2. **Allocation edit timestamp respected**
   - Allocation changes before `execution.startedAt` should not affect execution progress.
   - Allocation changes after `execution.startedAt` should affect execution progress.

3. **Transaction timestamp respected**
   - Transactions before tracking starts do not count.
   - Transactions after tracking starts do count.

4. **Transaction auto-allocation (Rule 1)**
   - Setup A: Asset 100% allocated to Goal A, new transaction arrives.
   - Expectation A: Transaction auto-allocated to Goal A (AllocationHistory amount snapshot recorded).
   - Setup B: Asset shared between Goal A (50%) and Goal B (50%), new transaction arrives.
   - Expectation B: Transaction goes to unallocated (no AllocationHistory record created).
   - Setup C: Asset partially allocated (70% to Goal A, 30% unallocated), new transaction arrives.
   - Expectation C: Transaction goes to unallocated (no AllocationHistory record created).

5. **AllocationHistory snapshot reconstruction**
   - Setup: Multiple allocation target snapshots over time (0.5, 0.3, 0.6).
   - Expectation: Target at intermediate timestamp returns correct snapshot value.

---

## Q&A: Design Clarifications

### Q1: What exactly is a "value change" event?

**Question:** Today we have `Transaction` and `AssetAllocation`. What does the calculator treat as a value change?

**Answer:** "Value Change" is an abstract concept covering all events that change value in a **goal-asset pair**:

| Event Type | Model | Treatment |
|------------|-------|-----------|
| Manual transaction | `Transaction` | Changes asset balance at `transaction.date` |
| Blockchain transaction | `Transaction` | Same model, timestamp from blockchain |
| Allocation change | `AllocationHistory` (NEW) | Changes distribution rules at `history.timestamp` |

All three modify the **amount** in the goal-asset relationship.

**Why AllocationHistory instead of AssetAllocation?**
- `AssetAllocation` stores only **current state** - history is overwritten on each change
- `AllocationHistory` stores **snapshots** of the target amount over time
- Use `latest <= timestamp` to get the target at any point in time
- This allows querying: "What allocations existed during execution period X?"

---

### Q2: Current exchange rate means UI numbers shift during execution?

**Question:** Using CURRENT rate means historic execution numbers will shift until completion. The plan is to snapshot rates at completion - but during the month, users see retroactive changes?

**Answer:** Yes, this is intentional and acceptable.

**Rationale:**
- This is not a problem with the proposal - this is **cryptocurrency reality**
- Crypto is volatile; users should expect price changes
- The app should reflect **current financial reality**, not historical snapshots
- When execution completes, rates are frozen in the snapshot
- Users who want predictable numbers should execute quickly (hours, not days)

**UI Implication:** Progress bars and amounts may change without user action during active execution. This is correct behavior - it shows real current value.

---

### Q3: Goal lifecycle - how does current code handle delete vs cancel vs finish?

**Question:** Current code likely doesn't have `GoalStatus` persisted. How do queries exclude deleted/cancelled goals in execution vs planning?

**Answer:** This requires refactoring. Current state:

| Current | Proposed |
|---------|----------|
| Hard delete (goal removed) | Soft delete (`status = .deleted`) |
| No cancel concept | Cancel frees allocations for reuse |
| No finish concept | Finish preserves for history |

**Refactoring needed:**
1. Add `GoalStatus` enum to `Goal` model
2. Change delete operations to set `status = .deleted` instead of removing
3. Update all queries:
   - **Active execution:** `WHERE status == .active`
   - **Planning:** `WHERE status == .active`
   - **History views:** Include `.finished` goals
   - **Cancelled:** Contributions become unallocated, goal hidden from active views

**Query examples:**
```swift
// Active goals for planning/execution
let activeGoals = goals.filter { $0.status == .active }

// Historical view (show finished too)
let historicalGoals = goals.filter { $0.status == .active || $0.status == .finished }

// Deleted goals excluded everywhere except maybe admin/debug views
```

This is a necessary prerequisite for the redesign and improves data integrity regardless.
