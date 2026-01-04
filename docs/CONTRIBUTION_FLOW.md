# Contribution Flow (Timestamp-Based Execution Tracking)

> How monthly plan fulfillment is tracked using timestamps and derived contributions

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-01-04 |
| Platform | Shared |
| Audience | Developers |

---

## Overview

This project tracks monthly plan fulfillment without persisting contributions during execution.

- **While a month is executing:** Progress is **derived on the fly** from timestamps
- **When a month is completed:** Derived events are **snapshotted into `CompletedExecution`** for immutable history

```mermaid
stateDiagram-v2
    [*] --> Draft: Create MonthlyExecutionRecord
    Draft --> Executing: startTracking()
    Executing --> Closed: markComplete()
    Executing --> Draft: undoStartTracking()
    Closed --> Executing: undoCompletion()
    Closed --> [*]

    note right of Executing
        Progress derived from timestamps
        No persisted contributions
    end note

    note right of Closed
        Frozen snapshot in CompletedExecution
        Immutable history record
    end note
```

---

## Key Models

### `Transaction`
Balance change for an `Asset` (manual or blockchain-imported).

| Field | Description |
|-------|-------------|
| `date` | When the transaction occurred |
| `amount` | Change amount (negative for withdrawals) |
| `asset` | Associated Asset |
| `source` | `.manual` or `.onChain` |

### `AssetAllocation`
Current allocation **target** from an asset to a goal.

| Field | Description |
|-------|-------------|
| `amount` | Target amount in asset's native currency |
| `asset` | Source Asset |
| `goal` | Destination Goal |

### `AllocationHistory`
Historical record of allocation **target snapshots** for a `(goal, asset)` pair.

| Field | Description |
|-------|-------------|
| `amount` | Target amount at this timestamp |
| `timestamp` | When this snapshot was recorded |
| `createdAt` | Tie-breaker for same-timestamp records |
| `monthLabel` | "yyyy-MM" for efficient queries |

### `MonthlyExecutionRecord`
Defines the window of what "counts" for a month's execution.

| Field | Description |
|-------|-------------|
| `startedAt` | Timestamp when tracking began |
| `status` | `.draft` → `.executing` → `.closed` |
| `snapshot` | `ExecutionSnapshot` captured at start |
| `completedExecution` | `CompletedExecution` created on close |

---

## How Execution Progress Is Derived

The `ExecutionProgressCalculator` derives "contributions" as **funding deltas** over time:

```mermaid
flowchart TB
    subgraph Inputs
        TX[Transactions<br/>balance changes]
        AH[AllocationHistory<br/>target changes]
        ER[ExchangeRateService<br/>current rates]
    end

    subgraph Calculator["ExecutionProgressCalculator"]
        B[Compute balance<br/>over time]
        T[Compute targets<br/>over time]
        F[Calculate funded<br/>amounts per goal]
        D[Derive delta events]
    end

    subgraph Output
        DE[DerivedEvent array]
        TOT[Goal totals in<br/>goal currency]
    end

    TX --> B
    AH --> T
    B --> F
    T --> F
    F --> D
    D --> DE
    DE --> TOT
    ER --> TOT
```

### Calculation Logic

1. **Compute asset balance over time** from `Transaction` changes
2. **Compute allocation targets over time** from `AllocationHistory` snapshots
3. **Convert balance + targets into funded amounts per goal:**
   - If `sum(targets) <= balance`: each goal is fully funded up to its target; extra is **unallocated**
   - If `sum(targets) > balance`: distribute available balance **proportionally** across targets
4. **Compute deltas** when balance or targets change → these become derived events

**Implementation:** `ExecutionProgressCalculator.swift:12`

---

## Core Flows

### 1. Start Tracking (Draft → Executing)

When a user starts tracking for a month:

```mermaid
sequenceDiagram
    participant User
    participant VM as MonthlyPlanningViewModel
    participant ETS as ExecutionTrackingService
    participant ES as ExecutionSnapshot
    participant MER as MonthlyExecutionRecord
    participant DB as ModelContext

    User->>VM: Tap "Start Tracking"
    VM->>ETS: startTracking(monthLabel, plans, goals)

    alt Record exists
        ETS->>DB: Fetch existing record
        ETS->>ETS: Refresh snapshot from current plans
    else No record
        ETS->>MER: Create new MonthlyExecutionRecord
    end

    ETS->>ES: ExecutionSnapshot.create(plans, goals)
    ES-->>ETS: Snapshot with goal targets

    ETS->>MER: Set startedAt = Date()
    ETS->>MER: Attach snapshot
    ETS->>MER: status = .executing

    ETS->>ETS: seedAllocationHistoryBaseline(goals, startedAt)
    Note over ETS: Creates AllocationHistory records<br/>at startedAt for tracked goals

    ETS->>DB: Save changes
    ETS-->>VM: Return record
    VM-->>User: Show execution view
```

**What happens:**
- `MonthlyExecutionRecord.startedAt` is set to current time
- `ExecutionSnapshot` captures planned amounts for each goal
- Baseline `AllocationHistory` snapshots are seeded at `startedAt` so the calculator has a stable reference point

**Implementation:** `ExecutionTrackingService.swift:71`

---

### 2. Add a Transaction

When a user adds a transaction during execution:

```mermaid
sequenceDiagram
    participant User
    participant ATV as AddTransactionView
    participant AS as AllocationService
    participant DB as ModelContext
    participant Cache as ExecutionProgressCache

    User->>ATV: Enter transaction details
    User->>ATV: Tap "Save"

    ATV->>DB: Insert Transaction(amount, date, asset)

    ATV->>AS: Check auto-allocation eligibility

    alt Asset 100% allocated to ONE goal
        AS->>AS: Calculate new target = old + amount
        AS->>DB: Update AssetAllocation target
        AS->>DB: Insert AllocationHistory(amount, timestamp)
        Note over AS: Auto-allocation keeps<br/>dedicated asset fully allocated
    else Asset shared or partially allocated
        Note over AS: No auto-allocation<br/>Funds go to "unallocated"
    end

    ATV->>DB: Save changes
    ATV->>Cache: Invalidate cache
    ATV-->>User: Transaction saved
```

**Auto-allocation rule:**
- If asset is **fully allocated to exactly one goal** before the deposit: increase that allocation target and record `AllocationHistory`
- Otherwise (shared or partially allocated): no allocation change, funds remain **unallocated**

**Implementation:** `AddTransactionView.swift`, `AllocationService.swift:36`

---

### 3. Change Allocations

When a user edits asset allocations:

```mermaid
sequenceDiagram
    participant User
    participant ASV as AssetSharingView
    participant AS as AllocationService
    participant DB as ModelContext
    participant Cache as ExecutionProgressCache

    User->>ASV: Adjust allocation sliders
    User->>ASV: Tap "Save"

    ASV->>AS: updateAllocations(asset, newAllocations)

    loop For each changed goal
        AS->>DB: Update AssetAllocation.amount

        alt Amount changed
            AS->>DB: Insert AllocationHistory(newAmount, Date())
        end

        alt Goal removed (amount = 0)
            AS->>DB: Insert AllocationHistory(amount: 0)
        end
    end

    AS->>DB: Save changes
    AS->>Cache: Invalidate cache
    AS-->>ASV: Success
    ASV-->>User: Allocations updated
```

**What happens:**
- `AssetAllocation` current state is updated
- For every changed goal, an `AllocationHistory` snapshot is inserted at current timestamp
- If a goal is removed from allocations, an `AllocationHistory(amount: 0)` is recorded

**Note:** UI can block over-allocation at save time, but persisted state can still become over-allocated later (external withdrawals). Calculations remain defensive.

**Implementation:** `AllocationService.swift:36`, `AssetSharingView.swift`

---

### 4. View Execution Progress (Read-Only)

`MonthlyExecutionViewModel` displays progress without persisting anything:

```mermaid
sequenceDiagram
    participant View as MonthlyExecutionView
    participant VM as MonthlyExecutionViewModel
    participant ETS as ExecutionTrackingService
    participant EPC as ExecutionProgressCalculator
    participant Cache as ExecutionProgressCache
    participant ERS as ExchangeRateService

    View->>VM: onAppear / refresh
    VM->>ETS: getActiveRecord()
    ETS-->>VM: MonthlyExecutionRecord

    alt Record is executing
        VM->>Cache: Check cached progress

        alt Cache valid
            Cache-->>VM: Cached totals
        else Cache stale/empty
            VM->>EPC: derivedEvents(record, end: Date())
            EPC->>EPC: Compute balance timeline
            EPC->>EPC: Compute target timeline
            EPC->>EPC: Calculate funded deltas
            EPC-->>VM: [DerivedEvent]

            VM->>ERS: Convert to goal currencies
            ERS-->>VM: Converted totals

            VM->>Cache: Store results
        end

        VM-->>View: Display live progress

    else Record is closed
        VM->>VM: Use CompletedExecution snapshot
        VM-->>View: Display frozen totals
    end
```

**Display sources:**
- **Executing:** Live calculated progress from `ExecutionProgressCalculator`
- **Closed:** Frozen totals from `CompletedExecution`

**Implementation:** `MonthlyExecutionViewModel.swift`, `ExecutionTrackingService.swift:254`

---

### 5. Complete Month (Executing → Closed)

When a user finishes the month:

```mermaid
sequenceDiagram
    participant User
    participant VM as MonthlyExecutionViewModel
    participant ETS as ExecutionTrackingService
    participant EPC as ExecutionProgressCalculator
    participant ERS as ExchangeRateService
    participant CE as CompletedExecution
    participant DB as ModelContext

    User->>VM: Tap "Complete Month"
    VM->>ETS: markComplete(record)

    ETS->>EPC: derivedEvents(record, end: Date())
    EPC-->>ETS: Final derived events

    ETS->>ERS: Fetch current exchange rates
    ERS-->>ETS: Rate snapshot

    ETS->>CE: Create CompletedExecution
    Note over CE: Snapshot includes:<br/>- Goal totals<br/>- Exchange rates<br/>- Contribution details

    ETS->>ETS: record.markComplete()
    ETS->>DB: Attach CompletedExecution to record
    ETS->>DB: Set status = .closed
    ETS->>DB: Save changes

    ETS-->>VM: Success
    VM-->>User: Month completed
```

**What happens:**
- Derived events from `startedAt` to `completedAt` are calculated one final time
- Exchange rates are snapshotted at completion time
- Everything is frozen into `CompletedExecution` for immutable history
- Record status transitions to `.closed`

**Implementation:** `ExecutionTrackingService.swift:206`

---

## Undo Operations

Both start and completion support a 24-hour undo window:

```mermaid
sequenceDiagram
    participant User
    participant VM as MonthlyExecutionViewModel
    participant ETS as ExecutionTrackingService
    participant MER as MonthlyExecutionRecord
    participant DB as ModelContext

    alt Undo Start Tracking
        User->>VM: Tap "Undo Start"
        VM->>ETS: undoStartTracking(record)
        ETS->>MER: Check canUndo (24hr window)

        alt Within window
            ETS->>MER: status = .draft
            ETS->>MER: startedAt = nil
            ETS->>MER: canUndoUntil = nil
            ETS->>DB: Save
            ETS-->>VM: Success
        else Window expired
            ETS-->>VM: Error: Undo expired
        end

    else Undo Completion
        User->>VM: Tap "Undo Complete"
        VM->>ETS: undoCompletion(record)
        ETS->>MER: Check canUndo (24hr window)

        alt Within window
            ETS->>MER: status = .executing
            ETS->>MER: completedAt = nil
            ETS->>DB: Delete CompletedExecution
            ETS->>DB: Save
            ETS-->>VM: Success
        else Window expired
            ETS-->>VM: Error: Undo expired
        end
    end
```

---

## Data Flow Summary

```mermaid
flowchart LR
    subgraph "User Actions"
        A1[Add Transaction]
        A2[Edit Allocations]
        A3[Start Tracking]
        A4[Complete Month]
    end

    subgraph "Persisted Models"
        TX[(Transaction)]
        AA[(AssetAllocation)]
        AH[(AllocationHistory)]
        MER[(MonthlyExecutionRecord)]
        CE[(CompletedExecution)]
    end

    subgraph "Derived (Not Persisted)"
        DE[DerivedEvents]
        PROG[Progress Totals]
    end

    A1 --> TX
    A1 -.->|auto-allocate| AH
    A2 --> AA
    A2 --> AH
    A3 --> MER
    A3 --> AH

    TX --> DE
    AH --> DE
    DE --> PROG

    A4 --> CE
    PROG -->|snapshot| CE
```

---

## Key Implementation Files

| File | Purpose |
|------|---------|
| `ExecutionTrackingService.swift` | Lifecycle operations (start, complete, undo) |
| `ExecutionProgressCalculator.swift` | Derives contribution events from timestamps |
| `ExecutionProgressCache.swift` | Caches calculated progress |
| `AllocationService.swift` | Manages allocations and history records |
| `MonthlyExecutionViewModel.swift` | View model for execution UI |
| `MonthlyExecutionRecord.swift` | Execution window model |
| `AllocationHistory.swift` | Historical allocation snapshots |
| `CompletedExecution.swift` | Immutable completion record |

---

## Related Documentation

- `CONTRIBUTION_TRACKING_REDESIGN.md` - Architecture overview and design decisions
- `CLOUDKIT_MIGRATION_PLAN.md` - CloudKit compatibility requirements
