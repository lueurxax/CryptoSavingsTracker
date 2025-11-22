# Monthly Planning Execution & Tracking Solution

> **Solution for Problem 3**: Monthly Planning Tool Lacks Execution Support

## ⚠️ DOCUMENT STATUS: CORRECTED TO MATCH IMPLEMENTATION

**Version 3.0 → 3.1**: This document has been updated to reflect the **actual implemented architecture** in the codebase, not an idealized design. Previous versions described fictional data models (`GoalPlanPreference`, `MonthlyExecutionPlan`) that were never implemented. This revision documents what actually ships.

### Key Architecture Differences (Document vs Reality)

| Document v3.0 (Idealized) | Codebase Reality (v3.1) |
|---------------------------|------------------------|
| `GoalPlanPreference` @Model | ❌ Doesn't exist → Use `MonthlyPlan` @Model |
| `MonthlyExecutionPlan` @Model | ❌ Doesn't exist → Use `MonthlyExecutionRecord` @Model |
| `MonthlyRequirement` @Model | ❌ Wrong → `MonthlyRequirement` is a **struct** (transient) |
| "Two-layer architecture" | ❌ Wrong → Single layer: `MonthlyPlan` serves both roles |
| Unified goal calculation (crypto + contributions) | ❌ Not implemented → Dual system (intentional) |
| `ContributionEntryView` with [+ Add] buttons | ❌ Not implemented → Missing UI layer |
| "Status: Ready for Implementation" | ❌ Misleading → **80% complete, missing UI** |

**This document now describes what actually works** so you can understand the system and implement the missing 20% (contribution entry UI) without rewriting everything.

---

## Executive Summary

This document describes the **implemented architecture** for monthly planning and execution tracking. The system allows users to:

1. **Plan monthly contributions** (set targets per goal)
2. **Start tracking** when ready (captures plan as immutable snapshot)
3. **Track progress** against the snapshot (via Contribution records)
4. **Close the month** when satisfied (or auto-close on month end)
5. **Review history** of past months

### What's Implemented (80%)

✅ **Data Layer Complete**:
- `MonthlyPlan` @Model with user preferences (flex state, custom amounts, skip/protect)
- `MonthlyExecutionRecord` @Model with state machine (draft → executing → closed)
- `ExecutionSnapshot` @Model capturing immutable plan baseline
- `Contribution` @Model linking to execution records

✅ **Service Layer Complete**:
- `MonthlyPlanningService` - calculates requirements, syncs MonthlyPlan records
- `ExecutionTrackingService` - manages lifecycle, calculates progress, links contributions
- `ContributionService` - records deposits, reallocations, queries

✅ **Partial UI**:
- `MonthlyExecutionView` - shows progress, completed/active goals
- `MonthlyPlanningContainer` - navigation between planning/execution
- "Start Tracking" and "Mark Complete" actions work

### What's Missing (20%)

❌ **UI Layer Gaps**:
- No `ContributionEntryView` (form to add contributions)
- No [+ Add] buttons in `MonthlyExecutionView`
- No easy way for users to record fiat contributions
- Existing `AddTransactionView` creates legacy `Transaction`, not `Contribution`

❌ **Goal Calculation Integration**:
- `GoalCalculationService.getCurrentTotal()` uses asset allocations only
- Contributions tracked separately in execution context
- Goal detail views don't show contribution totals
- **Note**: This may be intentional (crypto vs fiat separation)

**Completion Estimate**: 1-2 days to implement ContributionEntryView and wire it into MonthlyExecutionView.

---

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Integration with Existing Features](#integration-with-existing-features)
3. [Data Models](#data-models)
4. [User Flows](#user-flows)
5. [Sequence Diagrams](#sequence-diagrams)
6. [UI Specifications](#ui-specifications)
7. [Service Architecture](#service-architecture)
8. [Implementation Plan](#implementation-plan)
9. [Edge Cases & Validation](#edge-cases--validation)
10. [Risk Mitigation Strategy](#risk-mitigation-strategy)

---

## Core Concepts

### The Monthly Plan Lifecycle

> **UX Note**: State names use user-friendly terminology. "Planning" instead of "DRAFT", "Active" instead of "EXECUTING", "Completed" instead of "CLOSED".

```
┌─────────────┐
│  PLANNING   │  Review and adjust your monthly plan
│             │  Updates automatically when goals change
│             │  Apply flex adjustments and set preferences
└──────┬──────┘
       │ User clicks "Start Tracking This Month" OR auto-starts on 1st of month
       ▼
┌─────────────┐
│   ACTIVE    │  Tracking your monthly contributions
│  (Tracking) │  Adapts when goals change (shown with notifications)
│             │  Funded goals move to "Completed" section (stay visible)
└──────┬──────┘
       │ User clicks "Finish This Month" OR auto-completes on month end
       ▼
┌─────────────┐
│ COMPLETED   │  Historical record for this month
│ (Archived)  │  View your progress and contributions
│             │  Compare with other months
└─────────────┘
```

### Key Behaviors

#### 1. **PLANNING State** (User-Facing: "Planning")
- Review calculated monthly requirements for all goals
- Adjust amounts using flex slider (0-200%)
- Mark goals as protected (won't be reduced) or skipped (exclude this month)
- Apply Quick Actions (Skip Month, Pay Half, Pay Exact)
- All changes update instantly with live preview

**User Goal**: Prepare a realistic monthly savings plan

---

#### 2. **ACTIVE State** (User-Facing: "Tracking" or "Active This Month")

**Dynamic Adaptation**:
- When goals change (target, deadline), amounts recalculate automatically
- System shows notification: "Goal amounts updated due to changes" with details
- User can review changes and adjust if needed

**Contribution Tracking**:
- Add money to goals → progress bars update
- When goal reaches monthly target → moves to "✓ Completed" section at bottom
- Completed goals stay visible (collapsible) showing contribution history
- Remaining goals prominently displayed with progress

**Visual Feedback**:
```
Active Goals (2)
━━━━━━━━━━━━━━━
House Down Payment    $400 / $800    [+ Add]
Vacation Fund         $100 / $300    [+ Add]

✓ Completed This Month (1)          [Collapse ▼]
━━━━━━━━━━━━━━━━━━━━━━
Emergency Fund        $600 / $600    ✓
```

**User Goal**: Track progress toward monthly plan, see accomplishments

---

#### 3. **COMPLETED State** (User-Facing: "Completed" or "September 2025")
- Immutable historical record
- Shows planned vs actual contributions
- Displays completion percentage and timeline
- Used for comparison and insights
- Cannot add contributions (with helpful message if attempted)

**User Goal**: Review past performance, learn from history

---

### State Transition Safety

#### Auto-Transitions (Recommended UX)
- **PLANNING → ACTIVE**: Auto-starts on 1st of month (with 24hr undo option)
- **ACTIVE → COMPLETED**: Auto-completes on last day of month (with option to extend)

#### Manual Transitions (User Control)
If user prefers manual control:

**Starting Tracking**:
```
[Start Tracking This Month]

Confirmation Dialog:
┌────────────────────────────────────────┐
│ Start Tracking September 2025?        │
├────────────────────────────────────────┤
│ This will:                             │
│ ✓ Begin tracking your contributions   │
│ ✓ Lock this plan for historical record│
│ ℹ️  Your plan will still adapt to     │
│    goal changes                        │
│                                        │
│ [Cancel]  [Start Tracking]            │
└────────────────────────────────────────┘
```

**Finishing Month**:
```
[Finish This Month]

Confirmation Dialog:
┌────────────────────────────────────────┐
│ Complete September 2025?              │
├────────────────────────────────────────┤
│ Progress: $1,425 of $1,500 (95%)      │
│                                        │
│ ⚠️  Not fully funded:                 │
│    • House: $75 remaining             │
│                                        │
│ This amount will roll into October's  │
│ calculations.                          │
│                                        │
│ [Keep Tracking]  [Finish Month]       │
└────────────────────────────────────────┘
```

#### Undo Grace Period
- 24-hour window to undo state transitions
- Shows banner: "Started tracking. [Undo] (expires in 23h 45m)"
- Prevents accidental irreversible changes

---

### Handling Dynamic Updates (UX Clarity)

When goals change during ACTIVE state:

```
Notification:
┌────────────────────────────────────────┐
│ 📊 Plan Updated                        │
├────────────────────────────────────────┤
│ House Down Payment deadline moved:     │
│ Your monthly requirement increased:    │
│                                        │
│ Was: $600/month → Now: $1,500/month    │
│                                        │
│ You've contributed: $600               │
│ Still needed: $900                     │
│                                        │
│ [Got it]  [Adjust Plan]               │
└────────────────────────────────────────┘
```

This makes dynamic updates transparent and gives user control.

---

## Integration with Existing Features

### ⚠️ CRITICAL: Preserving Current Planning Features

The current implementation already has **excellent planning features** that must be preserved 100% during this implementation. This section outlines how to integrate the new execution tracking system **without losing any existing functionality**.

### Current Features to Preserve

#### 1. **Flex Adjustment System** ⭐ CRITICAL

**What Exists**:
- Users can adjust payment amounts from 0% to 200%
- Protected goals cannot be reduced by flex adjustment
- Skipped goals are excluded from this month's plan
- Real-time preview of adjusted amounts
- Quick Actions: Skip Month, Pay Half, Pay Exact, Reset

**Location**: `MonthlyPlanningViewModel`, `FlexAdjustmentService`

**How It Works** (Actual Implementation):

The existing `MonthlyPlan` @Model already serves both purposes:
1. **Persistent preferences** (customAmount, isProtected, isSkipped)
2. **Calculation baseline** (requiredMonthly, remainingAmount)

```swift
// ACTUAL ARCHITECTURE - Single Model
@Model
final class MonthlyPlan {
    var goalId: UUID

    // Calculation results (updated by service)
    var requiredMonthly: Double
    var remainingAmount: Double
    var monthsRemaining: Int

    // User preferences (persist across calculations)
    var customAmount: Double?      // User override
    var isProtected: Bool          // Protected from flex
    var isSkipped: Bool            // Skip this month
    var flexStateRawValue: String

    // Effective amount for execution snapshot
    var effectiveAmount: Double {
        if isSkipped { return 0 }
        return customAmount ?? requiredMonthly
    }
}
```

**How ExecutionSnapshot Captures It**:
```swift
// When user clicks "Start Tracking"
ExecutionTrackingService.startTracking(from: [MonthlyPlan], goals: [Goal])
→ Creates ExecutionSnapshot with:
  - plannedAmount = plan.effectiveAmount
  - flexState = plan.flexStateRawValue
  - isSkipped = plan.isSkipped
→ Snapshot is immutable for the month
```

**Key Insight**: No separate "preference" model needed—`MonthlyPlan` already handles both roles.

---

#### 2. **User Preferences Persistence** ⭐ IMPLEMENTED

**What Works Today**:
- `MonthlyPlan` @Model persists to SwiftData automatically
- User changes to `customAmount`, `isProtected`, `isSkipped` survive app restarts
- `MonthlyPlanningViewModel.syncMonthlyPlans()` keeps records up-to-date
- FlexAdjustmentService modifies `MonthlyPlan` records directly

**No Migration Needed**: The model already exists and works correctly.

---

#### 3. **Real-Time Calculation Updates** ⭐ IMPLEMENTED

**What Exists**:
- Auto-recalculates when goals change
- Auto-recalculates when assets change
- Auto-recalculates when settings change
- Debounced for performance

**How to Preserve**:
Make recalculation **state-aware** by checking MonthlyExecutionRecord status:

```swift
// In MonthlyPlanningViewModel

NotificationCenter.default.publisher(for: .goalUpdated)
    .sink { [weak self] _ in
        Task { [weak self] in
            // Check if there's an active execution record
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            let record = try? executionService.getCurrentMonthRecord()

            switch record?.status {
            case .draft, nil:
                // Full recalculation - planning is editable
                await self?.calculateRequirements()

            case .executing:
                // Update requirements based on user preference
                // Per spec: MonthlyPlan updates when goals change (dynamic)
                await self?.calculateRequirements()

            case .closed:
                // No recalculation - record is immutable
                break
            }
        }
    }
```

**Result**: DRAFT and EXECUTING both recalculate (dynamic), CLOSED is immutable.

---

#### 4. **FlexAdjustmentService Integration** ⭐ IMPORTANT

**What Exists**:
- Intelligent redistribution of amounts
- Multiple strategies (balanced, priority-based, etc.)
- Impact analysis for adjustments

**How to Preserve**:
FlexAdjustmentService already works with MonthlyRequirement structs (ALREADY IMPLEMENTED):

```swift
// In MonthlyPlanningViewModel (ACTUAL IMPLEMENTATION)

func previewAdjustment(_ percentage: Double) async {
    guard let flexService = flexService else { return }

    // Get transient requirements from MonthlyPlanningService
    let requirements = await monthlyPlanningService.calculateMonthlyRequirements(for: goals)

    // Use existing FlexAdjustmentService
    let adjusted = await flexService.applyFlexAdjustment(
        requirements: requirements,
        adjustment: percentage,
        protectedGoalIds: protectedGoalIds,
        skippedGoalIds: skippedGoalIds,
        strategy: .balanced
    )

    // Apply results to MonthlyPlan @Model records
    for result in adjusted {
        if let plan = monthlyPlans.first(where: { $0.goalId == result.requirement.goalId }) {
            plan.customAmount = result.adjustedAmount
        }
    }

    try? modelContext.save()
}
```

**Result**: FlexAdjustmentService already works with the existing architecture (no changes needed).

---

#### 5. **Quick Actions** ⭐ USEFUL

**What Exists**:
- Skip Month: Skip all flexible goals
- Pay Half: 50% of all amounts
- Pay Exact: 100% calculated amounts
- Reset: Clear all adjustments

**How to Preserve**:
Quick Actions work directly with MonthlyPlan records:

```swift
func applyQuickAction(_ action: QuickAction) async {
    switch action {
    case .skipMonth:
        for plan in monthlyPlans {
            if !plan.isProtected {
                plan.isSkipped = true
                plan.flexState = .skipped
            }
        }

    case .payHalf:
        for plan in monthlyPlans {
            plan.isSkipped = false
            plan.customAmount = plan.requiredMonthly * 0.5
        }

    // ... rest unchanged
    }

    try? modelContext.save()
}
```

**Result**: Quick Actions work by updating MonthlyPlan records directly.

---

### Architectural Decision: Dual Calculation Systems (Intentional)

#### The Reality: Two Separate Tracking Systems

The app maintains **two independent calculation systems** by design:

**System 1: Crypto Asset Tracking** (Existing)
```swift
// Goal total = sum of allocated crypto assets
GoalCalculationService.getCurrentTotal(goal)
→ Queries: goal.assets → asset.allocations
→ Returns: $500 (from BTC/ETH holdings)
```

**System 2: Fiat Contribution Tracking** (New - v2.1)
```swift
// Execution progress = sum of contributions
ExecutionTrackingService.calculateProgress(record)
→ Queries: Contribution records where executionRecordId = record.id
→ Returns: 40% ($200 contributed of $500 planned)
```

#### Why They're Separate

**Intentional Design Choice**:
1. **Crypto holdings** represent actual investments (BTC, ETH balances)
2. **Contributions** represent fiat savings commitments (monthly €200 target)
3. These track **different things**: holdings vs cash flow

**User Mental Model**:
- "My emergency fund has 0.5 BTC" (crypto tracking)
- "I contributed €200 this month toward my target" (execution tracking)

#### Where Users See Each System

| View | Uses Which System | Shows What |
|------|-------------------|------------|
| GoalDetailView | System 1: Asset allocations | "Current: 0.5 BTC ($15,000)" |
| DashboardView | System 1: Asset allocations | "Total Saved: $45,000" |
| MonthlyExecutionView | System 2: Contributions | "€200 / €625 (32%)" |
| PlanningView | System 1: Asset allocations | "Emergency Fund: $15,000 / $20,000" |

#### The Trade-off

**Current State** (Dual Systems):
- ✅ Clean separation of concerns
- ✅ Crypto tracking works independently
- ✅ Execution tracking works independently
- ❌ No unified "total progress" view
- ❌ Users must understand two separate concepts

**Alternative** (Unified System):
- Would require contributions to affect goal totals
- Would mix crypto holdings with fiat commitments
- Would complicate asset-based calculations
- **Decision**: Not implemented (yet)

#### If Unification Is Needed (Future Enhancement)

**To implement unified calculations** (contributions affect goal totals):

**Step 1**: Update `GoalCalculationService.getCurrentTotal()` to query both assets AND contributions:
```swift
// Pseudocode - NOT IMPLEMENTED
func getCurrentTotal(for goal: Goal, includeContributions: Bool = false) async -> Double {
    var total = 0.0

    // Part 1: Existing asset allocations
    for asset in goal.assets {
        total += asset.allocatedAmount(for: goal)
    }

    // Part 2: NEW - Fiat contributions
    if includeContributions {
        let contributions = fetchContributions(for: goal.id)
        total += contributions.sum(\.amount)
    }

    return total
}
```

**Step 2**: Update all view models to pass `includeContributions: true`

**Step 3**: Decide on UI presentation:
- Show combined total?
- Show breakdown (crypto vs fiat)?
- Different views show different totals?

**Estimated Effort**: 4-6 hours

**Trade-offs**:
- ✅ Users see one unified progress number
- ✅ Contributions feel "real" in goal context
- ❌ Mixes crypto holdings with fiat commitments
- ❌ Adds complexity to asset calculations

---

## Data Models

> **IMPLEMENTATION NOTE**: This section describes the **actual @Model classes** in the codebase, not hypothetical designs.

> **Key Insight**: `MonthlyPlan` is a **@Model (persistent)** that stores per-goal planning preferences. `MonthlyRequirement` is a **struct (transient)** used for UI display before syncing to MonthlyPlan records.

### 1. MonthlyPlan (@Model - SwiftData)

**Purpose**: Per-goal persistent storage of monthly planning calculations AND user preferences.

**Location**: `CryptoSavingsTracker/Models/MonthlyPlan.swift`

```swift
// ACTUAL IMPLEMENTATION
@Model
final class MonthlyPlan {
    @Attribute(.unique) var id: UUID

    // Core Planning Data
    var goalId: UUID                    // Links to Goal (not @Relationship)
    var requiredMonthly: Double         // Calculated monthly requirement
    var remainingAmount: Double         // Amount left to reach goal
    var monthsRemaining: Int            // Months until deadline
    var currency: String                // Goal's currency
    var statusRawValue: String          // RequirementStatus enum wrapper

    // User Preferences (Flex System)
    var flexStateRawValue: String       // FlexState enum: flexible/protected/skipped
    var customAmount: Double?           // User-set override (nil = use calculated)
    var isProtected: Bool               // Protected from flex adjustments
    var isSkipped: Bool                 // Skip this goal this month

    // Metadata
    var createdDate: Date
    var lastModifiedDate: Date
    var lastCalculated: Date            // Cache invalidation timestamp
    var version: Int                    // Future migration support

    // Computed Properties
    var effectiveAmount: Double {
        if isSkipped { return 0 }
        return customAmount ?? requiredMonthly
    }

    var flexState: FlexState {
        get { FlexState(rawValue: flexStateRawValue) ?? .flexible }
        set { flexStateRawValue = newValue.rawValue }
    }

    var status: RequirementStatus {
        get { RequirementStatus(rawValue: statusRawValue) ?? .onTrack }
        set { statusRawValue = newValue.rawValue }
    }

    // Business Logic Methods
    func updateCalculation(
        requiredMonthly: Double,
        remainingAmount: Double,
        monthsRemaining: Int,
        status: RequirementStatus
    ) {
        self.requiredMonthly = requiredMonthly
        self.remainingAmount = remainingAmount
        self.monthsRemaining = monthsRemaining
        self.status = status
        self.lastCalculated = Date()
        self.lastModifiedDate = Date()
    }

    func setCustomAmount(_ amount: Double?) {
        self.customAmount = amount
        self.lastModifiedDate = Date()
    }

    func toggleProtection() {
        self.isProtected.toggle()
        self.flexState = isProtected ? .protected : .flexible
    }

    func skipThisMonth(_ skip: Bool) {
        self.isSkipped = skip
        self.flexState = skip ? .skipped : .flexible
    }

    func applyFlexAdjustment(percentage: Double) {
        guard flexState == .flexible else { return }
        self.customAmount = requiredMonthly * percentage
    }
}
```

**How It's Used**:
1. `MonthlyPlanningViewModel` calculates transient `MonthlyRequirement` structs
2. `syncMonthlyPlans()` method persists them to `MonthlyPlan` @Model records
3. `ExecutionTrackingService.startTracking()` reads `MonthlyPlan[]` to create `ExecutionSnapshot`
4. User preferences (custom amounts, skip/protect) persist across months

### 1b. MonthlyRequirement (Struct - Transient)

**Purpose**: Transient calculation result for UI display. NOT persisted to database.

**Location**: `CryptoSavingsTracker/Models/MonthlyRequirement.swift`

```swift
// ACTUAL IMPLEMENTATION - NOT @Model
struct MonthlyRequirement: Identifiable {
    let id: UUID
    let goalId: UUID
    let goalName: String
    let currency: String
    let targetAmount: Double
    let currentTotal: Double            // From goal's asset allocations
    let remainingAmount: Double
    let monthsRemaining: Int
    let requiredMonthly: Double
    let progress: Double                // Percentage toward goal
    let deadline: Date
    let status: RequirementStatus       // onTrack/attention/critical
}
```

**How It's Used**:
1. `MonthlyPlanningService.calculateMonthlyRequirements()` returns `[MonthlyRequirement]`
2. UI displays these in planning view
3. `MonthlyPlanningViewModel.syncMonthlyPlans()` converts to `MonthlyPlan` records
4. Struct is discarded after sync

### 2. MonthlyExecutionRecord (NEW - Additive)

**New Architecture**: Per-month execution tracking that links to existing plans.

```swift
@Model
final class MonthlyExecutionRecord: @unchecked Sendable {
    @Attribute(.unique) var id: UUID
    var monthLabel: String              // "2025-09"
    var statusRawValue: String          // For SwiftData predicate support
    var createdAt: Date
    var startedAt: Date?                // When user clicked "Start Tracking"
    var completedAt: Date?              // When marked complete

    // UX: Undo grace period
    var canUndoUntil: Date?             // 24hr window to undo state change

    // Link to existing plans (NOT relationship - uses goalId lookup)
    var trackedGoalIds: Data            // Codable [UUID] - SwiftData doesn't support UUID arrays

    // Snapshot
    @Relationship(deleteRule: .cascade)
    var snapshot: ExecutionSnapshot?    // Created when tracking starts

    init(monthLabel: String, goalIds: [UUID]) {
        self.id = UUID()
        self.monthLabel = monthLabel
        self.statusRawValue = ExecutionStatus.draft.rawValue
        self.createdAt = Date()

        // Encode UUID array to Data
        if let encoded = try? JSONEncoder().encode(goalIds) {
            self.trackedGoalIds = encoded
        } else {
            self.trackedGoalIds = Data()
        }
    }

    // Computed property for status enum
    var status: ExecutionStatus {
        get {
            ExecutionStatus(rawValue: statusRawValue) ?? .draft
        }
        set {
            statusRawValue = newValue.rawValue
        }
    }

    // Decode goal IDs when needed
    var goalIds: [UUID] {
        guard let decoded = try? JSONDecoder().decode([UUID].self, from: trackedGoalIds) else {
            return []
        }
        return decoded
    }

    enum ExecutionStatus: String, Codable {
        case draft      // Internal: planning phase
        case executing  // Internal: active tracking
        case closed     // Internal: completed/archived

        // UI Display Names
        var displayName: String {
            switch self {
            case .draft: return "Planning"
            case .executing: return "Active This Month"
            case .closed: return "Completed"
            }
        }

        var icon: String {
            switch self {
            case .draft: return "pencil.circle"
            case .executing: return "chart.line.uptrend.xyaxis.circle"
            case .closed: return "checkmark.circle.fill"
            }
        }
    }

    // UX: Check if undo is still available
    var canUndo: Bool {
        guard let undoDeadline = canUndoUntil else { return false }
        return Date() < undoDeadline
    }
}
```

**Why Additive**: No migration needed, existing plans work unchanged, execution tracking is optional layer.

### 3. ExecutionSnapshot (NEW)

**Architecture**: Captures the state of all MonthlyPlans when execution starts. Used for historical comparison.

```swift
@Model
final class ExecutionSnapshot: @unchecked Sendable {
    @Attribute(.unique) var id: UUID
    var capturedAt: Date
    var totalPlanned: Double            // Sum of all goals' planned amounts
    var snapshotData: Data              // Codable array of GoalSnapshots

    // Relationship
    var executionRecord: MonthlyExecutionRecord?

    init(from plans: [MonthlyPlan]) {
        self.id = UUID()
        self.capturedAt = Date()

        let snapshots = plans.map { plan in
            GoalSnapshot(
                goalId: plan.goalId,
                goalName: "", // Will be filled from Goal lookup
                plannedAmount: plan.effectiveAmount,
                currency: plan.currency,
                flexState: plan.flexStateRawValue
            )
        }

        self.totalPlanned = snapshots.reduce(0) { $0 + $1.plannedAmount }

        // Encode to Data for SwiftData storage
        if let encoded = try? JSONEncoder().encode(snapshots) {
            self.snapshotData = encoded
        } else {
            self.snapshotData = Data()
        }
    }

    // Decode snapshots when needed
    var goalSnapshots: [GoalSnapshot] {
        guard let decoded = try? JSONDecoder().decode([GoalSnapshot].self, from: snapshotData) else {
            return []
        }
        return decoded
    }
}

struct GoalSnapshot: Codable {
    let goalId: UUID
    var goalName: String
    let plannedAmount: Double
    let currency: String
    let flexState: String
}
```

**Architecture Note**: Uses `Data` storage with Codable instead of SwiftData relationship to avoid complexity. SwiftData doesn't support arrays of structs in relationships.

### 4. Contribution (@Model - SwiftData) - IMPLEMENTED

**Purpose**: Tracks money movements (deposits, reallocations) for goals. Links to execution records for monthly tracking.

**Location**: `CryptoSavingsTracker/Models/Contribution.swift`

```swift
// ACTUAL IMPLEMENTATION
@Model
final class Contribution {
    @Attribute(.unique) var id: UUID
    var amount: Double           // Value in goal's currency (converted)
    var assetAmount: Double?     // Original crypto amount (e.g., 0.5 BTC)
    var date: Date
    var sourceType: ContributionSource
    var notes: String?

    // Relationships
    var goal: Goal?
    var asset: Asset?

    // Tracking metadata
    var monthLabel: String       // "2025-09" - UTC-based
    var isPlanned: Bool          // From monthly plan?
    var executionRecordId: UUID? // v2.1 - Links to MonthlyExecutionRecord

    // Exchange rate tracking
    var exchangeRateSnapshot: Double?
    var exchangeRateTimestamp: Date?
    var exchangeRateProvider: String?
    var currencyCode: String?    // Goal currency (e.g., "USD")
    var assetSymbol: String?     // Asset symbol (e.g., "BTC")

    // ACTUAL INITIALIZER
    init(amount: Double, goal: Goal, asset: Asset, source: ContributionSource) {
        self.id = UUID()
        self.amount = amount
        self.assetAmount = nil
        self.date = Date()
        self.sourceType = source
        self.notes = nil
        self.goal = goal
        self.asset = asset
        self.monthLabel = Self.monthLabel(from: Date())
        self.isPlanned = false
        self.exchangeRateSnapshot = nil
        self.exchangeRateTimestamp = nil
        self.exchangeRateProvider = nil
        self.currencyCode = goal.currency
        self.assetSymbol = asset.currency
    }

    static func monthLabel(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else {
            return "Unknown"
        }
        return String(format: "%04d-%02d", year, month)
    }
}

// ACTUAL ENUM
enum ContributionSource: String, Codable, Sendable {
    case manualDeposit      // User added money to asset
    case assetReallocation  // Moved between goals
    case initialAllocation  // First-time asset allocation
    case valueAppreciation  // Crypto price increase

    var displayName: String {
        switch self {
        case .manualDeposit: return "Manual Deposit"
        case .assetReallocation: return "Reallocation"
        case .initialAllocation: return "Initial Allocation"
        case .valueAppreciation: return "Value Appreciation"
        }
    }
}
```

**How It's Used**:
1. `ContributionService.recordDeposit()` creates contributions for manual adds
2. `ContributionService.recordReallocation()` creates paired contributions for moves
3. `ExecutionTrackingService` queries contributions by `executionRecordId`
4. Progress calculated as: `sum(contributions.amount) / snapshot.plannedAmount`

**Key Fields**:
- `executionRecordId`: Added in v2.1, links contribution to monthly execution record
- `monthLabel`: Auto-calculated UTC-based month for grouping
- `currencyCode`: Already exists, stores goal's currency for exchange rate tracking
- `sourceType`: Uses existing `.manualDeposit` (NOT `.manual`—that was fictional)

---

## Architecture Integration

### Additive vs. Replacement Strategy

**Decision**: Use **additive architecture** to preserve existing functionality while adding execution tracking.

#### Why Additive?

1. **Zero Breaking Changes**: Existing `MonthlyPlan` model unchanged
2. **No Data Migration Risk**: New models added, existing data preserved
3. **Gradual Rollout**: Feature can be optional/experimental initially
4. **Preserves FlexAdjustmentService**: Current planning features work unchanged

#### How It Works

```
┌─────────────────────────────────────────────────────────┐
│                  EXISTING LAYER                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │ MonthlyPlan │ → FlexAdj → │ Planning │             │
│  │ (per-goal)  │    Service  │   UI     │             │
│  └──────────┘  └──────────┘  └──────────┘             │
└─────────────────────────────────────────────────────────┘
                        ↓
                   (links to)
                        ↓
┌─────────────────────────────────────────────────────────┐
│                   NEW LAYER                             │
│  ┌─────────────────┐  ┌──────────────┐                │
│  │MonthlyExecution │→│ Execution    │                 │
│  │     Record      │  │   Tracking   │                 │
│  │  (per-month)    │  │      UI      │                 │
│  └─────────────────┘  └──────────────┘                │
│         ↓                                               │
│  ┌──────────────┐                                      │
│  │ Execution    │  (snapshot of MonthlyPlans)          │
│  │  Snapshot    │                                      │
│  └──────────────┘                                      │
└─────────────────────────────────────────────────────────┘
```

### Service Coordination

#### ExecutionTrackingService (NEW)

```swift
@MainActor
final class ExecutionTrackingService: ObservableObject {
    private let modelContext: ModelContext
    private let monthlyPlanningService: MonthlyPlanningService  // EXISTING
    private let contributionService: ContributionService         // EXISTING

    // Create execution record from current plans
    func startTracking(for monthLabel: String) async throws -> MonthlyExecutionRecord {
        // 1. Get all current MonthlyPlans
        let plans = try await monthlyPlanningService.getPlansForAllGoals()

        // 2. Create execution record
        let record = MonthlyExecutionRecord(
            monthLabel: monthLabel,
            goalIds: plans.map { $0.goalId }
        )

        // 3. Create snapshot
        let snapshot = ExecutionSnapshot(from: plans)
        record.snapshot = snapshot

        // 4. Update status and timestamps
        record.status = .executing
        record.startedAt = Date()
        record.canUndoUntil = Date().addingTimeInterval(24 * 3600)

        modelContext.insert(record)
        try modelContext.save()

        return record
    }

    // Link contributions to execution record
    func recordContribution(_ contribution: Contribution, to record: MonthlyExecutionRecord) {
        contribution.executionRecordId = record.id
        contribution.isPlanned = true
        try? modelContext.save()
    }

    // Check if goal fulfilled for the month
    func checkGoalFulfillment(goalId: UUID, in record: MonthlyExecutionRecord) async -> Bool {
        // Get plan for this goal
        guard let plan = try? await monthlyPlanningService.getPlan(for: goalId) else {
            return false
        }

        // Get contributions for this goal in this month
        let contributions = try? await contributionService.getContributions(
            for: goalId,
            monthLabel: record.monthLabel,
            executionRecordId: record.id
        )

        let totalContributed = contributions?.reduce(0) { $0 + $1.amount } ?? 0
        return totalContributed >= plan.effectiveAmount
    }
}
```

#### Integration Points

1. **MonthlyPlanningService** (EXISTING):
   - Continues to calculate requirements
   - Continues to manage user preferences
   - No changes required

2. **FlexAdjustmentService** (EXISTING):
   - Continues to work with MonthlyPlan
   - No changes required

3. **ContributionService** (EXISTING):
   - Add method to link contributions to execution records
   - Add method to query by execution record ID

4. **AllocationService** (EXISTING):
   - When user allocates money, trigger ExecutionTrackingService
   - Link new contributions to active execution record

### Thread Safety

**Critical**: All services accessing SwiftData must use `@MainActor`:

```swift
@MainActor
final class ExecutionTrackingService: ObservableObject { }

@MainActor
final class MonthlyPlanningService: ObservableObject { } // Already correct

@MainActor
final class ContributionService: ObservableObject { } // Already correct
```

### Predicate Patterns

**Architecture Note**: SwiftData predicates can't use enums directly. Use raw value comparison:

```swift
// ❌ WRONG - Won't compile
#Predicate<MonthlyExecutionRecord> { record in
    record.status == .executing
}

// ✅ CORRECT - Use statusRawValue
#Predicate<MonthlyExecutionRecord> { record in
    record.statusRawValue == "executing"
}
```

This requires adding `statusRawValue: String` to `MonthlyExecutionRecord` and computed property for the enum.

---

## UX Design Principles

### Strengths of the Current Design ✅

**1. Crisp Lifecycle with User-Friendly Language**
- ✅ **Planning → Active → Completed** (not DRAFT → EXECUTING → CLOSED)
- ✅ Confirmation dialogs spell out what happens
- ✅ Undo banner adds confidence (24-hour grace period)
- ✅ Matches existing app tone and feels natural

**2. Solid Execution View Concept**
- ✅ **Separate stacks**: "Active Goals" and "Completed This Month"
- ✅ **Progress bars** show immediate visual feedback
- ✅ **Undo grace period** visible in banner with countdown
- ✅ **Success messaging** when goals fulfilled
- ✅ **Collapsible history** keeps view clean

**3. Clear State Transitions**
```
Planning State:
├─ Show calculated requirements
├─ Allow flex adjustments
├─ Button: "Start Tracking This Month"
└─ Confirmation: "This will begin tracking your contributions..."

Active State:
├─ Show progress bars per goal
├─ [+ Add] buttons per goal (TO BE IMPLEMENTED)
├─ Undo banner (if < 24 hours)
└─ Button: "Finish This Month"

Completed State:
├─ Show performance summary
├─ Timeline of contributions
├─ Export report option
└─ Read-only (no edits)
```

### Critical UX Gap ⚠️

**Contribution Entry is Missing**

Without the [+ Add] buttons and ContributionEntryView:
- ❌ Users **cannot complete the "plan → execute" loop**
- ❌ Must jump into asset management (wrong mental model)
- ❌ Monthly tracking becomes a view-only feature

**Priority**: Implement ContributionEntryView to close the loop.

### UX Recommendations for ContributionEntryView

**Form Design Priorities**:
1. ✅ **Default to planned amount** (or remaining if partially fulfilled)
2. ✅ **Quick chips** for common amounts (Planned, Half, Remaining)
3. ✅ **Lightweight sheet** (amount + notes + preview only)
4. ✅ **Immediate feedback** (success toast + auto-refresh)

**Dual-System Clarity** (CRITICAL):

Add visual distinction between:
- **Crypto Holdings** (Goal.currentTotal from assets)
- **Fiat Contributions** (MonthlyExecutionRecord progress)

Options:
1. Show both values side-by-side in goal cards
2. Add tooltip/info button explaining the difference
3. Use subtitle: "Monthly Savings: $600 / $800" vs "Total Holdings: $5,200"

This prevents **"Why doesn't my goal total change?"** confusion.

---

## User Flows

### Flow 1: Creating and Starting a Monthly Plan

**UX Note**: User sees "Planning" state (not "DRAFT"). Clear confirmation dialog explains what happens next.

```
1. User navigates to Planning tab
2. System shows current month's plan in Planning state
   - 📝 Planning This Month
   - Calculated requirements for each goal
   - Total monthly target
   - [Start Tracking Contributions] button ← UX: Action-oriented
3. User reviews plan, optionally adjusts custom amounts
4. User clicks "Start Tracking Contributions"
5. System shows confirmation dialog:
   - "Ready to Start Tracking?"
   - Explains: will save plan, track contributions, show progress
   - Can still adjust targets if goals change
6. User confirms
7. System:
   - Creates ExecutionSnapshot (immutable copy of current MonthlyPlan states)
   - Changes record status: .draft → .executing (internal)
   - Display changes to "Active This Month" ← UX: User-friendly
   - Sets canUndoUntil = now + 24 hours ← UX: Grace period
   - Shows Monthly Execution View
```

### Flow 2: Making Contributions During Execution

**UX Note**: Completed goals stay visible in collapsible section to prevent disorientation.

```
1. User in Monthly Execution View (shows "Active This Month")
2. Sees Active Goals (2) section with goals needing contributions
3. User adds money to a goal (via asset allocation)
4. System:
   - Creates Contribution record
   - Links contribution to current plan (planId)
   - Checks if goal's monthly requirement is now met
   - If met: isFulfilledThisMonth = true
   - Goal moves to "✓ Completed This Month" section ← UX: Stays visible
   - Section is collapsible but expanded by default
   - Updates total progress bar with accessibility labels
5. If all goals fulfilled:
   - Shows "All goals funded for this month! 🎉"
   - Active Goals section shows (0)
   - Completed section shows all goals with checkmarks
   - Offers to mark month as complete
```

### Flow 3: Goals Changing During Execution

**UX Note**: Dynamic updates shown with clear explanation. User has access to original plan via snapshot.

```
Scenario: User contributed $600 to Goal A (target was $600, marked complete)
Then: Goal A's deadline changes, now needs $1,500/month

System behavior:
1. Recalculates MonthlyRequirement for Goal A
2. Updates requiredAmount: $600 → $1,500
3. Sets isFulfilledThisMonth = false (no longer met)
4. Goal A moves from "Completed" back to "Active Goals" section ← UX: Dynamic
5. Shows notification: "⚠️ Targets Updated"
   - Explains why target changed ("deadline moved closer")
   - Shows: "$600 of $1,500 (40%)" with "(was $600)" ← UX: Context
6. User needs to contribute $900 more
7. [View Original Plan] button shows snapshot for reference ← UX: Transparency
```

### Flow 4: Closing a Monthly Plan

**UX Note**: "Mark Complete" instead of "Close". 24-hour undo grace period for user confidence.

```
User-initiated completion:
1. User clicks "Mark Complete"
2. System shows confirmation dialog:
   - "Mark Month as Complete?"
   - Shows current progress: "$600 / $1,700 (35%)"
   - Shows completed goals count: "1 of 3 goals"
   - "⚠️ You can undo this within 24 hours" ← UX: Safety net
3. User confirms
4. System:
   - Sets plan status: .executing → .closed (internal)
   - Display changes to "Completed" ← UX: Positive language
   - Sets closedAt timestamp
   - Sets canUndoUntil = now + 24 hours ← UX: Grace period
   - Plan becomes read-only (but can undo)

All goals funded scenario:
1. User contributes to last unfunded goal
2. System detects all requirements met
3. Shows success message: "All goals funded for this month! 🎉"
4. Offers [Mark Complete] button
5. User confirms (same dialog as above)
6. Same as user-initiated completion

Undo within grace period:
1. User realizes mistake within 24 hours
2. Clicks [Undo] button in history view
3. System:
   - Reverts status: .closed → .executing
   - Clears closedAt and canUndoUntil
   - Returns to "Active This Month" view
```

### Flow 5: Viewing Historical Plans

**UX Note**: "Completed" state (not "CLOSED"). Pagination prevents overwhelming long history.

```
1. User navigates to Planning History
2. Sees paginated list of months (3 at a time):
   - ✓ September 2025 - Completed (95%)
   - ✓ August 2025 - Completed (100%)
   - ✓ July 2025 - Completed (87%)
   - [Load More...] "Showing 3 of 12 months" ← UX: Pagination
3. User taps a month (e.g., September)
4. System shows comprehensive detail view:
   - ✓ Completed (not "CLOSED") ← UX: Positive language
   - Completed on: September 30, 2025
   - Original snapshot (planned amounts per goal)
   - Actual contributions per goal
   - Completion percentage per goal
   - Timeline of all events with dates
   - Total: $1,425 of $1,500 (95%)
   - Accessibility labels for all progress bars
5. If within 24-hour undo window:
   - Shows [Undo] button
   - User can revert to Active state
```

---

## Sequence Diagrams

### Diagram 1: Planning Flow (Creating and Starting Plan)

```mermaid
sequenceDiagram
    actor User
    participant PlanningView
    participant MonthlyPlanningService
    participant GoalCalculationSvc
    participant ModelContext

    User->>PlanningView: Navigate to Planning
    PlanningView->>MonthlyPlanningService: Load current plan
    MonthlyPlanningService->>ModelContext: Query MonthlyPlan (current month)
    ModelContext-->>MonthlyPlanningService: Plan (DRAFT)

    MonthlyPlanningService->>GoalCalculationSvc: Calculate requirements
    GoalCalculationSvc-->>MonthlyPlanningService: Requirements[]
    MonthlyPlanningService-->>PlanningView: Plan with requirements

    PlanningView-->>User: Display plan<br/>- Goals list<br/>- Required amounts<br/>- Total: $X<br/>[Start Executing]

    opt User adjusts custom amount
        User->>PlanningView: Adjust custom amount
        PlanningView->>MonthlyPlanningService: Update requirement
        MonthlyPlanningService->>ModelContext: Save custom amount
        ModelContext-->>MonthlyPlanningService: Success
        MonthlyPlanningService-->>PlanningView: Updated
    end

    User->>PlanningView: Click "Start Executing This Plan"
    PlanningView->>MonthlyPlanningService: startExecutingPlan()

    MonthlyPlanningService->>MonthlyPlanningService: Create ExecutionSnapshot(from: monthlyPlans)

    MonthlyPlanningService->>ModelContext: Update record<br/>- status = .executing<br/>- startedAt = Date()<br/>- snapshot = snapshot
    ModelContext->>ModelContext: context.save()
    ModelContext-->>MonthlyPlanningService: Success

    MonthlyPlanningService-->>PlanningView: Success
    PlanningView-->>User: Navigate to Execution View
```

### Diagram 2: Execution Flow (Making Contributions)

```mermaid
sequenceDiagram
    actor User
    participant ExecutionView
    participant ContributionService
    participant MonthlyPlanningService
    participant GoalCalculationSvc
    participant ModelContext

    User->>ExecutionView: View execution
    ExecutionView->>MonthlyPlanningService: Load active plan
    MonthlyPlanningService->>ModelContext: Query MonthlyPlan (status = .executing)
    ModelContext-->>MonthlyPlanningService: Plan + Requirements

    ExecutionView->>ContributionService: Get contributions for this month
    ContributionService->>ModelContext: Query Contributions (monthLabel = "2025-09")
    ModelContext-->>ContributionService: Contributions[]
    ContributionService-->>ExecutionView: Contributions[]

    ExecutionView->>GoalCalculationSvc: Calculate progress per goal
    Note over GoalCalculationSvc: For each requirement:<br/>- Sum contributions<br/>- Compare to target<br/>- Calculate %
    GoalCalculationSvc-->>ExecutionView: Progress data

    ExecutionView-->>User: Display:<br/>- Unfunded goals<br/>- Progress bars<br/>- Total progress

    User->>ExecutionView: User adds $500 to Goal A<br/>(via asset allocation)
    ExecutionView->>ContributionService: recordContribution($500, goalA, asset)

    ContributionService->>ContributionService: Create Contribution<br/>- amount: 500<br/>- source: .manualDeposit<br/>- monthLabel: "2025-09"<br/>- planId: plan.id

    ContributionService->>ModelContext: Insert contribution
    ModelContext->>ModelContext: Save
    ModelContext-->>ContributionService: Success

    ContributionService->>MonthlyPlanningService: Check if goal funded
    MonthlyPlanningService->>ModelContext: Query Contributions for goalA (sum)
    ModelContext-->>MonthlyPlanningService: Total: $600

    MonthlyPlanningService->>MonthlyPlanningService: Get requirement for goalA<br/>Required: $600<br/>Compare: $600 >= $600 ✓

    MonthlyPlanningService->>ModelContext: Update requirement<br/>isFulfilledThisMonth = true
    ModelContext->>ModelContext: Save
    ModelContext-->>MonthlyPlanningService: Success

    MonthlyPlanningService-->>ContributionService: Goal funded: true
    ContributionService-->>ExecutionView: Success

    ExecutionView->>ExecutionView: Refresh view<br/>- Goal A disappears<br/>- Update progress bars<br/>- Check if all goals funded

    ExecutionView-->>User: Updated view:<br/>- Goal A removed<br/>- Goal B: $0/$400<br/>- Total: $600/$1000
```

### Diagram 3: History Viewing Flow

```mermaid
sequenceDiagram
    actor User
    participant HistoryView
    participant MonthlyPlanningService
    participant ContributionService
    participant ModelContext

    User->>HistoryView: Navigate to History
    HistoryView->>MonthlyPlanningService: Load closed plans
    MonthlyPlanningService->>ModelContext: Query MonthlyPlan<br/>(status = .closed, order by DESC)
    ModelContext-->>MonthlyPlanningService: Plans[]

    loop For each plan
        MonthlyPlanningService->>ModelContext: Get snapshot & contributions
        Note over MonthlyPlanningService: Calculate:<br/>- Total planned<br/>- Total contributed<br/>- Completion %
        ModelContext-->>MonthlyPlanningService: Summary data
    end

    MonthlyPlanningService-->>HistoryView: Plan summaries

    HistoryView-->>User: Display list:<br/>- Sept 2025 (95%)<br/>- Aug 2025 (100%)<br/>- July 2025 (87%)

    User->>HistoryView: Tap "Sept 2025"
    HistoryView->>MonthlyPlanningService: Load plan details
    MonthlyPlanningService->>ModelContext: Fetch plan with snapshot & requirements
    ModelContext-->>MonthlyPlanningService: Plan + Snapshot

    HistoryView->>ContributionService: Get contributions for this month
    ContributionService->>ModelContext: Query Contributions<br/>(monthLabel = "2025-09", order by date)
    ModelContext-->>ContributionService: Contributions[]
    ContributionService-->>HistoryView: Contributions[]

    HistoryView->>HistoryView: Group by goal<br/>For each goal:<br/>- Snapshot amount<br/>- Actual contributions<br/>- Calculate %<br/>- Build timeline

    HistoryView-->>User: Display details:<br/>━━━━━━━━━━━━━━━<br/>September 2025 (CLOSED)<br/>Overall: $1,425 / $1,500 (95%)<br/>━━━━━━━━━━━━━━━<br/>Goals:<br/>✓ Emergency: $600/$600 (100%)<br/>⚠️ House: $525/$600 (87%)<br/>✓ Vacation: $300/$300 (100%)<br/>━━━━━━━━━━━━━━━<br/>Timeline:<br/>Sept 5: $600 → Emergency<br/>Sept 12: $400 → House<br/>Sept 20: $125 (realloc) → House<br/>Sept 25: $300 → Vacation

    Note over User,HistoryView: Pagination available<br/>for all-time history
```

---

## UI Specifications

### 1. Planning View (DRAFT State)

**UX Note**: State displayed as "Planning" (not "DRAFT"). Clean, focused interface for setting up the month's contribution targets.

```
┌─────────────────────────────────────────────┐
│ ← Planning              September 2025      │
├─────────────────────────────────────────────┤
│                                             │
│ 📝 Planning This Month                      │
│                                             │
│ Set your contribution targets for each      │
│ goal. You can adjust these anytime.         │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ Emergency Fund                          │ │
│ │ Required: $600/month                    │ │
│ │ ─────────────────────────      [Edit]  │ │
│ ├─────────────────────────────────────────┤ │
│ │ House Down Payment                      │ │
│ │ Required: $600/month                    │ │
│ │ Custom:   $800/month ✏️         [Edit]  │ │
│ ├─────────────────────────────────────────┤ │
│ │ Vacation Fund                           │ │
│ │ Required: $300/month                    │ │
│ │ ─────────────────────────      [Edit]  │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ Total Monthly Target: $1,700                │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │      [Start Tracking Contributions]     │ │  ← UX: Clear action
│ └─────────────────────────────────────────┘ │
│                                             │
│ [View Previous Months]                      │
│                                             │
└─────────────────────────────────────────────┘

When user taps "Start Tracking Contributions":
┌─────────────────────────────────────────────┐
│ Ready to Start Tracking?                    │
├─────────────────────────────────────────────┤
│                                             │
│ This will:                                  │
│ • Save your current plan                    │
│ • Track contributions against these targets │
│ • Show progress throughout the month        │
│                                             │
│ You can still adjust targets if goals       │
│ change during the month.                    │
│                                             │
│ Total Target: $1,700                        │
│                                             │
│        [Cancel]  [Start Tracking]           │
│                                             │
└─────────────────────────────────────────────┘
```

### 2. Monthly Execution View (EXECUTING State)

**UX Note**: State displayed as "Active This Month" (not "EXECUTING"). Completed goals stay visible in collapsible section to prevent disorientation.

```
┌─────────────────────────────────────────────┐
│ ← Active                September 2025      │
├─────────────────────────────────────────────┤
│                                             │
│ 📊 Active This Month                        │
│ Started: Sept 5, 2025                       │
│                                             │
│ Overall Progress                            │
│ $600 of $1,700 (35%)                        │
│ ███████░░░░░░░░░░░░░░░░░░░░░░░              │
│ role="progressbar" aria-label="Overall      │
│ progress: 35%" aria-valuenow="35"           │  ← UX: Accessibility
│                                             │
│ Active Goals (2)                            │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ ┌─────────────────────────────────────────┐ │
│ │ House Down Payment                      │ │
│ │ $400 of $800                            │ │
│ │ ██████░░░░░░ 50%                        │ │
│ │ aria-label="House: 50% complete"        │  ← UX: Accessibility
│ │                          [+ Add]        │ │
│ ├─────────────────────────────────────────┤ │
│ │ Vacation Fund                           │ │
│ │ $0 of $300                              │ │
│ │ ░░░░░░░░░░░░ 0%                         │ │
│ │ aria-label="Vacation: 0% complete"      │
│ │                          [+ Add]        │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ✓ Completed This Month (1)     [Collapse ▲]│  ← UX: Collapsible section
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ ┌─────────────────────────────────────────┐ │
│ │ ✓ Emergency Fund       $600 / $600      │ │
│ │ Completed Sept 5                        │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │   [Update Plan]   [Mark Complete]       │ │  ← UX: Clearer than "Close"
│ └─────────────────────────────────────────┘ │
│                                             │
│ [View Plan Details] [View History]          │
│                                             │
└─────────────────────────────────────────────┘

When user taps "Mark Complete":
┌─────────────────────────────────────────────┐
│ Mark Month as Complete?                     │
├─────────────────────────────────────────────┤
│                                             │
│ This will close September's plan and save   │
│ it to your history.                         │
│                                             │
│ Your Progress:                              │
│ • Overall: $600 / $1,700 (35%)              │
│ • Completed: 1 of 3 goals                   │
│                                             │
│ ⚠️ You can undo this within 24 hours        │  ← UX: Grace period
│                                             │
│        [Cancel]  [Mark Complete]            │
│                                             │
└─────────────────────────────────────────────┘

### ⚠️ TO BE IMPLEMENTED: ContributionEntryView

**Current Status**: This UI does **NOT exist** in the codebase. The [+ Add] buttons are not present in `MonthlyExecutionView`.

**Design Specification** (when implemented):

When user taps **[+ Add] button** (to be added):
┌─────────────────────────────────────────────┐
│ ← Add Contribution    Add to House          │  ← UX: Clear context
├─────────────────────────────────────────────┤
│                                             │
│ Amount                                      │
│ ┌─────────────────────────────────────────┐ │
│ │ 400                            USD      │ │  ← Pre-filled with remaining
│ └─────────────────────────────────────────┘ │
│                                             │
│ Quick Amounts                               │
│ [Planned: $800] [Half: $400] [Full: $800]  │  ← UX: Common amounts
│                                             │
│ Notes (Optional)                            │
│ ┌─────────────────────────────────────────┐ │
│ │ e.g., Weekly savings                    │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ Preview                                     │
│ ┌─────────────────────────────────────────┐ │
│ │ Current:   $400                         │ │
│ │ Adding:    +$400                        │ │
│ │ New Total: $800 / $800 ✓ Complete       │ │  ← UX: Show outcome
│ └─────────────────────────────────────────┘ │
│                                             │
│        [Cancel]  [Add Contribution]         │
│                                             │
└─────────────────────────────────────────────┘

Success confirmation (subtle):
┌─────────────────────────────────────────────┐
│ ✓ Added $400 to House Down Payment          │  ← Dismisses after 2 sec
└─────────────────────────────────────────────┘
```

**Implementation Requirements**:
1. Create `ContributionEntryView.swift` in `Views/Planning/`
2. Add [+ Add] buttons to `MonthlyExecutionView.swift` goal cards
3. Wire up to `ContributionService.recordDeposit()` with placeholder Asset (see Integration section)
4. Link contribution to `executionRecordId`
5. Refresh UI after contribution added (listen to `.contributionAdded` notification)

**UX Priorities** ⭐:
1. **Default to remaining amount** - Pre-fill with what's needed to complete the goal
2. **Quick amount chips**:
   - "Planned: $800" (original snapshot amount)
   - "Half: $400" (50% of planned)
   - "Remaining: $400" (what's left to fulfill)
3. **Keep sheet lightweight**:
   - Amount input + quick chips + notes field only
   - Preview shows: Current → +Adding → New Total
   - Single primary CTA: "Add Contribution"
4. **Immediate feedback**:
   - Subtle success toast: "✓ Added $400 to House Down Payment"
   - Goal card updates to show new progress
   - Auto-moves to "Completed" section if fulfilled

**Critical UX Note - Dual System Clarity** ⚠️:

Users will ask **"Why doesn't my goal total change?"** when they add a contribution.

**Reason**: The app tracks two separate things:
- **Crypto Holdings** (Goal.currentTotal) = actual BTC/ETH balances
- **Fiat Contributions** (MonthlyExecutionRecord progress) = monthly savings tracking

**Recommended UI Solution**:
```swift
// In MonthlyExecutionView goal cards
VStack(alignment: .leading) {
    Text("House Down Payment")

    // Show BOTH systems clearly
    HStack {
        VStack(alignment: .leading) {
            Text("Crypto Holdings")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("$5,200")  // Goal.currentTotal
                .font(.title3)
        }

        Spacer()

        VStack(alignment: .trailing) {
            Text("This Month's Savings")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("$600 / $800")  // Execution progress
                .font(.title3)
            Text("75%")
                .font(.caption)
                .foregroundColor(.green)
        }
    }
}
```

Or use a **tooltip/info button**:
```
HStack {
    Text("Monthly Progress: $600 / $800")
    Button {
        showExplanation = true
    } label: {
        Image(systemName: "info.circle")
    }
}
.popover(isPresented: $showExplanation) {
    Text("""
    Monthly tracking measures your fiat contributions this month.
    Your goal's crypto holdings are tracked separately.
    """)
}
```

**Estimated Effort**: 4-6 hours (form) + 1-2 hours (dual-system clarity)

### 3. Execution View - Goal Changes Scenario

**UX Note**: Dynamic updates shown with clear explanation of what changed and why. User maintains context of original plan via snapshot.

```
┌─────────────────────────────────────────────┐
│ ← Active                September 2025      │
├─────────────────────────────────────────────┤
│                                             │
│ ⚠️ Targets Updated                          │  ← UX: Less alarming
│ You edited a goal. This month's targets     │
│ have been recalculated to keep you on       │
│ track for your new deadline.                │
│                              [Dismiss]      │
│                                             │
│ Overall Progress                            │
│ $600 of $2,000 (30%)  ← Updated total       │
│ ██████░░░░░░░░░░░░░░░░░░░░░░                │
│                                             │
│ Active Goals (2)                            │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ ┌─────────────────────────────────────────┐ │
│ │ 🔄 House Down Payment      Changed      │ │
│ │ $600 of $1,500             (was $600)   │ │  ← UX: Show original
│ │ ████░░░░░░░░ 40%                        │ │
│ │ Target increased: deadline moved closer │ │  ← UX: Explain why
│ │                          [+ Add]        │ │
│ ├─────────────────────────────────────────┤ │
│ │ Vacation Fund                           │ │
│ │ $0 of $500                              │ │
│ │ ░░░░░░░░░░░░ 0%                         │ │
│ │                          [+ Add]        │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ✓ Completed This Month (1)     [Collapse ▲]│
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ ┌─────────────────────────────────────────┐ │
│ │ ✓ Emergency Fund       $600 / $600      │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ [View Original Plan] [View Changes Detail]  │  ← UX: Access to snapshot
│                                             │
└─────────────────────────────────────────────┘
```

### 4. History List View

**UX Note**: State displayed as "Completed" (not "CLOSED"). Pagination for all-time history prevents overwhelming the user.

```
┌─────────────────────────────────────────────┐
│ ← History               Plan History        │
├─────────────────────────────────────────────┤
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ ✓ September 2025        Completed       │ │  ← UX: Positive framing
│ │ $1,425 of $1,500                        │ │
│ │ ████████░░ 95%                          │ │
│ │ Completed: Sept 30, 2025                │ │
│ │                                    [>]  │ │
│ ├─────────────────────────────────────────┤ │
│ │ ✓ August 2025           Completed       │ │
│ │ $1,500 of $1,500                        │ │
│ │ ██████████ 100% ✓                       │ │
│ │ Completed: Aug 31, 2025                 │ │
│ │                                    [>]  │ │
│ ├─────────────────────────────────────────┤ │
│ │ ✓ July 2025             Completed       │ │
│ │ $1,305 of $1,500                        │ │
│ │ ████████░░ 87%                          │ │
│ │ Completed: July 31, 2025                │ │
│ │                                    [>]  │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ [Load More...]                              │
│ Showing 3 of 12 months                      │  ← UX: Pagination
│                                             │
└─────────────────────────────────────────────┘
```

### 5. History Detail View (Single Month)

**UX Note**: Comprehensive historical view with planned vs. actual comparison. Shows the snapshot of original plan.

```
┌─────────────────────────────────────────────┐
│ ← Back                 September 2025       │
├─────────────────────────────────────────────┤
│                                             │
│ ✓ Completed                                 │  ← UX: Positive language
│ Completed on: September 30, 2025            │
│                                             │
│ Overall Performance                         │
│ $1,425 of $1,500 (95%)                      │
│ ████████░░                                  │
│ aria-label="Overall 95%"                    │  ← UX: Accessibility
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ Goals Breakdown                         │ │
│ ├─────────────────────────────────────────┤ │
│ │ ✓ Emergency Fund                        │ │
│ │   Planned:  $600                        │ │
│ │   Actual:   $600                        │ │
│ │   Status:   100% ✓                      │ │
│ │   ──────────                            │ │
│ │   Sept 5: $600 (manual deposit)         │ │
│ ├─────────────────────────────────────────┤ │
│ │ ⚠️ House Down Payment                    │ │
│ │   Planned:  $600 (original target)      │ │  ← UX: Clarify snapshot
│ │   Actual:   $525                        │ │
│ │   Status:   87% ⚠️                       │ │
│ │   ──────────                            │ │
│ │   Sept 12: $400 (manual deposit)        │ │
│ │   Sept 20: $125 (reallocated from       │ │
│ │            Vacation)                     │ │
│ ├─────────────────────────────────────────┤ │
│ │ ✓ Vacation Fund                         │ │
│ │   Planned:  $300                        │ │
│ │   Actual:   $300                        │ │
│ │   Status:   100% ✓                      │ │
│ │   ──────────                            │ │
│ │   Sept 25: $300 (manual deposit)        │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ Timeline                                    │
│ ┌─────────────────────────────────────────┐ │
│ │ Sept 5  • Plan started                  │ │  ← UX: Add start event
│ │ Sept 5  • $600 → Emergency Fund         │ │
│ │ Sept 12 • $400 → House                  │ │
│ │ Sept 20 • $125 reallocated → House      │ │
│ │ Sept 25 • $300 → Vacation               │ │
│ │ Sept 30 • Plan marked complete          │ │  ← UX: Clearer language
│ └─────────────────────────────────────────┘ │
│                                             │
│ [Export Report]                             │
│                                             │
└─────────────────────────────────────────────┘
```

### 6. Settings View - Auto-Transitions (Optional Feature)

**UX Note**: Optional automatic state transitions on month boundaries with clear explanations.

```
┌─────────────────────────────────────────────┐
│ ← Settings           Monthly Planning       │
├─────────────────────────────────────────────┤
│                                             │
│ Monthly Plan Automation                     │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ Auto-start new month's plan        [ ] │ │  ← Toggle OFF by default
│ │                                         │ │
│ │ When enabled, automatically create a    │ │
│ │ new plan on the 1st of each month.      │ │
│ │                                         │ │
│ │ You can still review and edit before    │ │
│ │ starting to track contributions.        │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ Auto-complete previous month       [ ] │ │  ← Toggle OFF by default
│ │                                         │ │
│ │ When enabled, automatically mark the    │ │
│ │ previous month complete on the 1st.     │ │
│ │                                         │ │
│ │ ⚠️ Recommended: Keep OFF to review your │ │
│ │ progress before closing each month.     │ │
│ │                                         │ │
│ │ If enabled, you can still undo within   │ │
│ │ 24 hours.                               │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ Grace period for undo                   │ │
│ │                                         │ │
│ │ ◉ 24 hours (recommended)                │ │
│ │ ○ 48 hours                              │ │
│ │ ○ 7 days                                │ │
│ │ ○ No undo (actions are final)           │ │
│ └─────────────────────────────────────────┘ │
│                                             │
└─────────────────────────────────────────────┘

**Default Behavior (all toggles OFF):**
- User manually starts tracking each month
- User manually marks months complete
- All state changes require explicit user action
- 24-hour undo grace period for safety
```

---

## Service Architecture

### MonthlyPlanningService - IMPLEMENTED

**Purpose**: Calculates monthly savings requirements for goals.

**Location**: `CryptoSavingsTracker/Services/MonthlyPlanningService.swift`

**Key Point**: This service does NOT manage MonthlyPlan persistence or execution state. It only calculates transient MonthlyRequirement structs for UI display.

```swift
// ACTUAL IMPLEMENTATION
@MainActor
final class MonthlyPlanningService: MonthlyPlanningServiceProtocol, ObservableObject {
    private let exchangeRateService: ExchangeRateServiceProtocol

    // MARK: - Calculation Methods

    /// Calculate monthly requirements for all goals
    func calculateMonthlyRequirements(for goals: [Goal]) async -> [MonthlyRequirement] {
        var requirements: [MonthlyRequirement] = []

        for goal in goals {
            let requirement = await calculateRequirementForGoal(goal)
            requirements.append(requirement)
        }

        return requirements.sorted { $0.goalName < $1.goalName }
    }

    /// Calculate total monthly requirement in display currency
    func calculateTotalRequired(for goals: [Goal], displayCurrency: String) async -> Double {
        let requirements = await calculateMonthlyRequirements(for: goals)

        var total: Double = 0

        for requirement in requirements {
            if requirement.currency == displayCurrency {
                total += requirement.requiredMonthly
            } else {
                // Convert to display currency
                let rate = try? await exchangeRateService.fetchRate(
                    from: requirement.currency,
                    to: displayCurrency
                )
                total += requirement.requiredMonthly * (rate ?? 1.0)
            }
        }

        return total
    }

    /// Get monthly requirement for a single goal
    func getMonthlyRequirement(for goal: Goal) async -> MonthlyRequirement? {
        let requirements = await calculateMonthlyRequirements(for: [goal])
        return requirements.first
    }

    // MARK: - Internal Calculation

    private func calculateRequirementForGoal(_ goal: Goal) async -> MonthlyRequirement {
        // Calculate based on goal.targetAmount, goal.currentTotal, goal.deadline
        let remaining = max(0, goal.targetAmount - goal.currentTotal)
        let monthsLeft = monthsUntilDeadline(goal.deadline)
        let requiredMonthly = monthsLeft > 0 ? remaining / Double(monthsLeft) : remaining

        return MonthlyRequirement(
            id: UUID(),
            goalId: goal.id,
            goalName: goal.name,
            currency: goal.currency,
            targetAmount: goal.targetAmount,
            currentTotal: goal.currentTotal,
            remainingAmount: remaining,
            monthsRemaining: monthsLeft,
            requiredMonthly: requiredMonthly,
            progress: goal.targetAmount > 0 ? (goal.currentTotal / goal.targetAmount) * 100 : 0,
            deadline: goal.deadline ?? Date(),
            status: determineStatus(for: goal)
        )
    }
}
```

**Integration Notes**:
- MonthlyPlan @Model persistence is handled by MonthlyPlanningViewModel (CryptoSavingsTracker/ViewModels/MonthlyPlanningViewModel.swift:1-384)
- Execution state management is handled by ExecutionTrackingService (not MonthlyPlanningService)
- This service only provides calculation logic, not persistence

### ContributionService - IMPLEMENTED

**Purpose**: Manages contribution records (deposits, reallocations, appreciations).

**Location**: `CryptoSavingsTracker/Services/ContributionService.swift`

```swift
// ACTUAL IMPLEMENTATION
@MainActor
class ContributionService {
    private let modelContext: ModelContext

    // MARK: - Create Contributions

    /// Record a manual deposit (SYNCHRONOUS, not async)
    func recordDeposit(
        amount: Double,                      // Fiat amount in goal currency
        assetAmount: Double,                 // Crypto amount
        to goal: Goal,
        from asset: Asset,
        exchangeRate: Double,
        exchangeRateProvider: String = "Manual",
        notes: String? = nil
    ) throws -> Contribution {
        let contribution = Contribution(
            amount: amount,
            goal: goal,
            asset: asset,
            source: .manualDeposit           // NOTE: .manualDeposit, not .manual
        )
        contribution.assetAmount = assetAmount
        contribution.notes = notes
        contribution.currencyCode = goal.currency
        contribution.assetSymbol = asset.currency
        contribution.exchangeRateSnapshot = exchangeRate
        contribution.exchangeRateTimestamp = Date()
        contribution.exchangeRateProvider = exchangeRateProvider

        modelContext.insert(contribution)
        try modelContext.save()

        return contribution
    }

    /// Record reallocation between goals (SYNCHRONOUS)
    func recordReallocation(
        fiatAmount: Double,
        assetAmount: Double,
        from fromGoal: Goal,
        to toGoal: Goal,
        asset: Asset,
        exchangeRate: Double,
        exchangeRateProvider: String = "Manual"
    ) throws -> (withdrawal: Contribution, deposit: Contribution) {
        // Creates paired contributions (negative + positive)
        let withdrawal = Contribution(amount: -fiatAmount, goal: fromGoal, asset: asset, source: .assetReallocation)
        // ... (sets all metadata)

        let deposit = Contribution(amount: fiatAmount, goal: toGoal, asset: asset, source: .assetReallocation)
        // ... (sets all metadata)

        modelContext.insert(withdrawal)
        modelContext.insert(deposit)
        try modelContext.save()

        return (withdrawal, deposit)
    }

    /// Record initial allocation (for migrations)
    func recordInitialAllocation(
        fiatAmount: Double,
        assetAmount: Double,
        to goal: Goal,
        from asset: Asset,
        exchangeRate: Double,
        exchangeRateProvider: String = "Migration",
        date: Date = Date()
    ) throws -> Contribution { /* ... */ }

    /// Record value appreciation (price increases)
    func recordAppreciation(
        fiatAmount: Double,
        for goal: Goal,
        asset: Asset,
        oldExchangeRate: Double,
        newExchangeRate: Double,
        exchangeRateProvider: String = "CoinGecko"
    ) throws -> Contribution { /* ... */ }

    // MARK: - Query Contributions (v2.1)

    func getContributions(for goal: Goal, sortedBy: ContributionSortOrder = .dateDescending) -> [Contribution] { /* ... */ }

    func getContributions(for goal: Goal, month: String) -> [Contribution] { /* ... */ }

    func getTotalContributions(for goal: Goal, from: Date? = nil, to: Date? = nil, excludingSources: [ContributionSource] = []) -> Double { /* ... */ }

    /// Link contribution to execution record (v2.1)
    func linkToExecutionRecord(_ contribution: Contribution, recordId: UUID) throws {
        contribution.executionRecordId = recordId
        contribution.isPlanned = true
        try modelContext.save()
    }
}
```

**Key Points**:
- All methods are **synchronous** (`throws`, not `async throws`)
- Uses existing `Contribution(amount:goal:asset:source:)` initializer
- Must manually set `assetAmount`, `currencyCode`, `exchangeRateSnapshot` after init
- `ContributionSource` enum is `.manualDeposit` (NOT `.manual`)
- No `ExchangeRateService.shared.getRate()` method exists (use `fetchRate()` instead)

### TO BE IMPLEMENTED: ContributionEntryView Integration

**Challenge**: The existing `Contribution` model requires an `Asset` parameter in its initializer:
```swift
// ACTUAL INITIALIZER (requires Asset)
Contribution(amount: Double, goal: Goal, asset: Asset, source: ContributionSource)
```

But monthly planning contributions are **fiat-only** (e.g., "I saved €200 this month") without a specific crypto asset.

**Solution Options**:

1. **Option A: Use existing `recordDeposit()` with a placeholder Asset** (easier, works now):
   ```swift
   // Create a temporary/placeholder Asset for fiat tracking
   let placeholderAsset = Asset(currency: goal.currency, balance: 0)
   placeholderAsset.name = "Monthly Contribution"
   modelContext.insert(placeholderAsset)

   // Use existing service method
   let contribution = try contributionService.recordDeposit(
       amount: amount,
       assetAmount: 0,  // No crypto amount
       to: goal,
       from: placeholderAsset,
       exchangeRate: 1.0,  // Fiat to fiat = 1:1
       exchangeRateProvider: "Manual",
       notes: "Monthly execution contribution"
   )
   contribution.executionRecordId = executionRecord.id
   try modelContext.save()
   ```

2. **Option B: Make Asset optional in Contribution model** (architectural change):
   - Requires changing `Contribution.asset` from `Asset?` to truly optional relationship
   - Would need to update all existing Contribution uses
   - More invasive change to existing architecture

**Recommendation**: Use Option A (placeholder Asset) for initial implementation. This:
- Works with existing ContributionService API (no new methods needed)
- Doesn't break existing crypto-based contribution flow
- Can be refactored later if needed

2. **Wire into MonthlyExecutionView**:
   ```swift
   // Add [+ Add] button in goal card
   Button {
       selectedGoal = goal
       showContributionEntry = true
   } label: {
       Label("Add", systemImage: "plus.circle.fill")
   }

   // Present sheet
   .sheet(item: $selectedGoal) { goal in
       ContributionEntryView(
           goal: goal,
           executionRecordId: viewModel.executionRecord?.id,
           plannedAmount: viewModel.snapshot?.snapshot(for: goal.id)?.plannedAmount ?? 0,
           currency: goal.currency
       )
   }
   ```

3. **Refresh UI after contribution**:
   ```swift
   // In ContributionEntryView, after saving:
   NotificationCenter.default.post(name: .contributionAdded, object: contribution)

   // In MonthlyExecutionViewModel, listen:
   NotificationCenter.default.publisher(for: .contributionAdded)
       .sink { [weak self] _ in
           Task { await self?.refresh() }
       }
   ```

**Estimated Effort**: 4-6 hours (create view + extend service + wire navigation)

---

## Implementation Plan

### What's Already Done (80%)

✅ **Data Layer**:
- MonthlyPlan @Model with flex system
- MonthlyExecutionRecord @Model with state machine
- ExecutionSnapshot @Model capturing immutable baseline
- Contribution @Model with execution linking

✅ **Service Layer**:
- MonthlyPlanningService calculates requirements
- ExecutionTrackingService manages lifecycle
- ContributionService records contributions
- All query methods implemented

✅ **UI Layer (Partial)**:
- MonthlyExecutionView shows progress
- MonthlyPlanningContainer handles navigation
- "Start Tracking" and "Mark Complete" work
- Progress bars display correctly

### What's Missing (20%)

❌ **UI for Adding Contributions**:
- Create `ContributionEntryView.swift`
- Add [+ Add] buttons in `MonthlyExecutionView`
- Extend `ContributionService` with fiat-only method (or handle pseudo-assets)
- Wire up notifications for UI refresh

❌ **Optional: Unified Goal Calculations**:
- Update `GoalCalculationService` to include contributions
- Decide if contributions should affect goal totals
- Handle dual currency display (crypto + fiat)

### Implementation Steps

1. **Create ContributionEntryView** (2-3 hours)
   - Form with amount field, quick buttons, notes
   - Preview showing before/after totals
   - Use existing `ContributionService.recordDeposit()` with placeholder Asset (see Option A above)
   - Link contribution to `executionRecordId`

2. **Update MonthlyExecutionView** (1-2 hours)
   - Add [+ Add] buttons to goal cards
   - Wire sheet presentation
   - Listen to `.contributionAdded` notification (or refresh on dismiss)

3. **Create Helper Method** (1 hour) - OPTIONAL
   - Add helper to create placeholder Assets for fiat contributions
   - Or just inline the placeholder Asset creation in ContributionEntryView

4. **Test End-to-End** (1 hour)
   - Add contribution via UI
   - Verify progress updates
   - Check fulfillment detection
   - Test mark complete flow

**Total Time**: 5-7 hours to complete feature

---

## Testing the Implemented Parts

### Manual Test Plan

1. **Planning Phase**:
   - ✅ Open planning view → see calculated requirements
   - ✅ Adjust amounts with flex slider → preferences persist
   - ✅ Mark goal as protected → can't be adjusted
   - ✅ Skip goal → amount becomes zero

2. **Start Tracking**:
   - ✅ Click "Start Tracking This Month"
   - ✅ Verify ExecutionSnapshot created
   - ✅ Check snapshot has correct planned amounts
   - ✅ Undo within 24 hours works

3. **Execution Progress** (Database Direct):
   - ✅ Manually insert Contribution via SQL
   - ✅ Verify execution view shows progress
   - ✅ Check fulfillment detection (100% = complete)

4. **Mark Complete**:
   - ✅ Click "Finish This Month"
   - ✅ Record moves to closed state
   - ✅ Can view in history

### Known Limitations

- ❌ No UI to add contributions (requires database SQL)
- ❌ Goal detail doesn't show contributions (only crypto assets)
- ❌ Dashboard doesn't include contributions in totals
- ⚠️ Exchange rate service uses `fetchRate`, not `getRate`

---

    func recordReallocation(
        amount: Double,
        from fromGoal: Goal,
        to toGoal: Goal,
        asset: Asset
    ) async throws {
        let monthLabel = Contribution.monthLabel(from: Date())

        // Create negative contribution for source goal
        let fromContribution = Contribution(
            amount: -amount,
            goal: fromGoal,
            asset: asset,
            source: .assetReallocation,
            monthLabel: monthLabel
        )
        fromContribution.notes = "Reallocated to \(toGoal.name)"

        // Create positive contribution for target goal
        let toContribution = Contribution(
            amount: amount,
            goal: toGoal,
            asset: asset,
            source: .assetReallocation,
            monthLabel: monthLabel
        )
        toContribution.notes = "Reallocated from \(fromGoal.name)"

        modelContext.insert(fromContribution)
        modelContext.insert(toContribution)

        try modelContext.save()
    }

    // MARK: - Querying Contributions

    func getContributions(
        for goalId: UUID,
        monthLabel: String
    ) async throws -> [Contribution] {
        let descriptor = FetchDescriptor<Contribution>(
            predicate: #Predicate { contribution in
                contribution.goal?.id == goalId &&
                contribution.monthLabel == monthLabel
            }
        )

        return try modelContext.fetch(descriptor)
    }

    func getContributions(monthLabel: String) async throws -> [Contribution] {
        let descriptor = FetchDescriptor<Contribution>(
            predicate: #Predicate { $0.monthLabel == monthLabel },
            sortBy: [SortDescriptor(\.date)]
        )

        return try modelContext.fetch(descriptor)
    }

    func getMonthlyTotal(for goal: Goal, month: String) async throws -> Double {
        let contributions = try await getContributions(for: goal.id, monthLabel: month)
        return contributions.reduce(0) { $0 + $1.amount }
    }

    // MARK: - History

    func getContributionHistory(
        for goal: Goal,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [Contribution] {
        let descriptor = FetchDescriptor<Contribution>(
            predicate: #Predicate { $0.goal?.id == goal.id },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let allContributions = try modelContext.fetch(descriptor)

        let endIndex = min(offset + limit, allContributions.count)
        guard offset < allContributions.count else { return [] }

        return Array(allContributions[offset..<endIndex])
    }

    // MARK: - Helper Methods

    private func getCurrentExecutingRecord() async throws -> MonthlyExecutionRecord? {
        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

        let descriptor = FetchDescriptor<MonthlyExecutionRecord>(
            predicate: #Predicate { record in
                record.monthLabel == monthLabel &&
                record.status == .executing
            }
        )

        return try modelContext.fetch(descriptor).first
    }

    private func getExchangeRate(for asset: Asset) async -> Double? {
        // Implementation depends on ExchangeRateService
        // Return current rate for the asset
        return nil // Placeholder
    }
}
```

---

## Implementation Plan

### Phase 1: Data Models & Migration (Week 1)

**Architecture**: Additive approach - create new models, preserve existing ones.

#### Tasks:
1. **Create new models (ADDITIVE)**
   - `MonthlyExecutionRecord.swift` (NEW per-month tracking)
   - `ExecutionSnapshot.swift` (NEW snapshot system)
   - **DO NOT modify** existing `MonthlyPlan.swift`
   - **DO NOT modify** existing `MonthlyRequirement.swift`

2. **Minor enhancement to existing models**
   - `Contribution.swift`: Add single field `executionRecordId: UUID?`
   - SwiftData migration for this single field (low risk)

3. **Update DIContainer**
   - Register `ExecutionTrackingService` (NEW)
   - ContributionService already registered
   - MonthlyPlanningService already registered

#### Files:
- `Models/MonthlyExecutionRecord.swift` (NEW)
- `Models/ExecutionSnapshot.swift` (NEW)
- `Models/Contribution.swift` (MODIFY - add 1 field)
- `Services/MigrationService.swift` (MODIFY - add executionRecordId field)
- `Utilities/DIContainer.swift` (MODIFY - register ExecutionTrackingService)

**Migration Strategy**: Only one field added to existing model. Existing MonthlyPlan unchanged = zero risk.

### Phase 2: Service Layer (Week 2)

**Architecture**: Create new ExecutionTrackingService, enhance existing services minimally.

#### Tasks:
1. **Create ExecutionTrackingService** (NEW)
   - Lifecycle management (draft → executing → closed)
   - Snapshot creation from existing MonthlyPlans
   - Link contributions to execution records
   - Fulfillment checking logic

2. **Enhance existing ContributionService** (MINOR)
   - Add method: `linkToExecutionRecord(_ contribution, _ record)`
   - Add query: `getContributions(for goalId, monthLabel, executionRecordId)`
   - **Preserve** all existing functionality

3. **Enhance existing AllocationService** (MINOR)
   - Hook into ExecutionTrackingService when allocating
   - Link new contributions to active execution record
   - **Preserve** all existing allocation logic

4. **MonthlyPlanningService** (NO CHANGES)
   - Continues to calculate requirements
   - Continues to manage MonthlyPlan preferences
   - Zero modifications required

#### Files:
- `Services/ExecutionTrackingService.swift` (NEW)
- `Services/ContributionService.swift` (ENHANCE - add 2 methods)
- `Services/AllocationService.swift` (ENHANCE - add execution hooks)
- `Services/MonthlyPlanningService.swift` (NO CHANGES)

**Thread Safety**: All new/modified services use `@MainActor` for SwiftData access.

### Phase 3: UI - Planning & Execution (Week 3)

**UX Note**: Implement user-friendly terminology throughout the UI. Internal state names (draft/executing/closed) are fine for code, but all user-facing text should use Planning/Active/Completed.

#### Tasks:
1. **Update PlanningView**
   - Show "Planning" header (not "DRAFT") ← UX
   - "Start Tracking Contributions" button (not "Start Executing") ← UX
   - Confirmation dialog with clear explanation ← UX
   - Edit custom amounts
   - 24-hour undo grace period indicator ← UX

2. **Create MonthlyExecutionView**
   - Show "Active This Month" header (not "EXECUTING") ← UX
   - Progress bars with ARIA labels for accessibility ← UX
   - "Active Goals" section (unfunded)
   - "Completed This Month" section (collapsible, funded goals) ← UX
   - "Mark Complete" button (not "Close Plan") ← UX
   - Confirmation dialog showing progress summary ← UX
   - "Update Plan" button

3. **Create contribution recording UI**
   - Triggered from asset allocation
   - Link to current plan
   - Visual feedback when goals move to completed section ← UX

#### Files:
- `Views/Planning/PlanningView.swift` (MODIFY)
- `Views/Planning/MonthlyExecutionView.swift` (NEW)
- `Views/Components/PlanStatusBadge.swift` (NEW)
- `Views/Components/GoalProgressCard.swift` (NEW)
- `ViewModels/MonthlyPlanningViewModel.swift` (MODIFY)
- `ViewModels/MonthlyExecutionViewModel.swift` (NEW)

### Phase 4: UI - History (Week 4)

**UX Note**: History shows "Completed" status with positive framing. Include undo functionality for recent completions.

#### Tasks:
1. **Create history list view**
   - Show all completed plans (display "Completed" not "CLOSED") ← UX
   - Summary cards with checkmarks for 100% completion ← UX
   - Pagination (3 months at a time) ← UX
   - "Load More..." with count indicator ← UX

2. **Create history detail view**
   - "✓ Completed" header (not "CLOSED") ← UX
   - Plan overview with accessibility labels ← UX
   - Goals breakdown showing planned vs actual ← UX
   - Timeline with all events (start, contributions, completion) ← UX
   - Undo button if within grace period ← UX
   - Export functionality

3. **Integration**
   - Navigation from planning to history
   - Deep linking to specific months
   - Undo flow returning to Active state ← UX

#### Files:
- `Views/Planning/PlanHistoryListView.swift` (NEW)
- `Views/Planning/PlanHistoryDetailView.swift` (NEW)
- `Views/Components/ContributionTimelineView.swift` (NEW)
- `Views/Components/PlanSummaryCard.swift` (NEW)
- `ViewModels/PlanHistoryViewModel.swift` (NEW)

### Phase 5: Testing & Polish (Week 5)

**UX Note**: Include accessibility testing and UX polish items from review.

#### Tasks:
1. **Unit tests**
   - MonthlyPlanningService tests
   - ContributionService tests
   - Plan lifecycle tests (including undo grace period) ← UX
   - Fulfillment logic tests

2. **Integration tests**
   - End-to-end plan execution
   - Goal changes during execution
   - Contribution recording from allocations
   - Undo flow within grace period ← UX
   - Auto-transition features (if enabled) ← UX

3. **UI tests**
   - Planning flow with confirmation dialogs ← UX
   - Execution flow with completed section ← UX
   - History viewing with undo ← UX
   - Pagination
   - Collapsible sections behavior ← UX

4. **Accessibility tests** ← UX
   - Screen reader support for progress bars
   - ARIA labels correct
   - Keyboard navigation
   - VoiceOver testing on iOS

5. **Edge cases**
   - Multiple plans (shouldn't happen)
   - Plan without snapshot
   - Goals deleted mid-execution
   - Negative contributions (withdrawals)
   - Undo after grace period expired ← UX

#### Files:
- `Tests/Services/MonthlyPlanningServiceTests.swift` (NEW)
- `Tests/Services/ContributionServiceTests.swift` (NEW)
- `Tests/Integration/PlanExecutionTests.swift` (NEW)
- `UITests/PlanningFlowTests.swift` (NEW)

---

## Edge Cases & Validation

### 1. Goal Deleted During Execution

**Scenario**: User deletes a goal that's part of the current executing plan.

**Solution**:
- Keep `MonthlyRequirement` even if goal is deleted (cached `goalName`)
- Mark requirement as "Goal Deleted"
- Don't count toward total progress
- Show in history with note

### 2. Multiple Executing Plans

**Scenario**: System bug or manual data edit creates two EXECUTING plans.

**Validation**:
```swift
func validateSingleExecutingPlan() throws {
    let descriptor = FetchDescriptor<MonthlyPlan>(
        predicate: #Predicate { $0.status == .executing }
    )

    let executingPlans = try modelContext.fetch(descriptor)

    if executingPlans.count > 1 {
        throw PlanError.multipleExecutingPlans
    }
}
```

### 3. Contribution Without Active Plan

**Scenario**: User adds money outside of any plan execution.

**Solution**:
- Still create `Contribution` record
- `planId` is nil
- Can be queried for monthly totals
- Not linked to any specific plan

### 4. Plan Closed But New Contribution Added

**Scenario**: User manually edits data and adds contribution to closed month.

**Validation**:
```swift
func recordContribution(...) async throws {
    if let record = try await getExecutionRecord(for: monthLabel) {
        guard record.status != .closed else {
            throw ContributionError.cannotAddToClosedRecord
        }
    }
    // Proceed with recording
}
```

### 5. Over-Contribution (Rollover Logic)

**Scenario**: User contributes $800 to a goal that needs $600 this month.

**Behavior**:
- Record full $800 contribution
- Mark requirement as fulfilled (isFulfilledThisMonth = true)
- When plan closes and next month calculates:
  - Goal's current total is higher
  - Next month's requirement recalculates based on NEW current total
  - Automatically accounts for over-contribution

**No explicit rollover needed** - the monthly requirement calculation naturally adjusts.

### 6. Withdrawal/Reduction

**Scenario**: User removes $200 from a goal mid-month.

**Solution**:
- Create negative contribution (amount: -200)
- Source: `.manualEdit`
- Recalculate fulfillment status
- If requirement was fulfilled but now underfunded → reappears in execution view

### 7. Goal Deadline Passes During Execution

**Scenario**: Goal deadline is Oct 15, executing October plan, deadline passes.

**Behavior**:
- Keep requirement in current month's plan
- When plan closes, don't include in next month (goal expired)
- Show in history with note "Deadline reached"

### 8. Empty Plan (No Requirements)

**Scenario**: All goals are fully funded or no active goals.

**Solution**:
- Allow creating DRAFT plan with empty requirements
- Don't allow starting execution if no requirements
- Show message: "All goals are fully funded! 🎉"

---

## Success Metrics

### Implementation Success:
- [ ] All unit tests pass (>90% coverage)
- [ ] All sequence diagrams implemented correctly
- [ ] No data loss during migration
- [ ] Plan lifecycle works: DRAFT → EXECUTING → CLOSED

### User Experience Success:
- [ ] Users can track monthly execution progress
- [ ] Clear visibility of what needs to be funded
- [ ] Historical tracking available for all closed months
- [ ] Plan updates reflect goal changes accurately

### Performance:
- [ ] History loads in <1 second with 12 months of data
- [ ] Contribution recording completes in <500ms
- [ ] Plan recalculation completes in <1 second

---

## Timeline Summary

| Phase | Duration | Deliverables |
|-------|----------|-------------|
| **Phase 1** | 1 week | Data models, migration, schema update |
| **Phase 2** | 1 week | Service layer complete |
| **Phase 3** | 1 week | Planning & execution UI |
| **Phase 4** | 1 week | History UI & navigation |
| **Phase 5** | 1 week | Testing, edge cases, polish |
| **Total** | **5 weeks** | Full solution deployed |

---

## Risk Mitigation Strategy

### Overview

This implementation carries **MEDIUM risk** due to the need to preserve existing features while adding new functionality. This section outlines specific risks and their mitigation strategies.

### 🔴 HIGH RISK: Flex Adjustment System

**Risk**: Losing the flex adjustment feature (adjust 0-200%, protected/skipped goals, quick actions)

**Impact**: Major feature regression, user complaints, loss of unique functionality

**Mitigation Strategy**:

1. **Preserve MonthlyPlan Architecture** (ALREADY IMPLEMENTED)
   - MonthlyPlan @Model stores all user preferences (customAmount, isProtected, isSkipped, flexState)
   - FlexAdjustmentService works directly with MonthlyPlan records
   - No migration needed - feature already preserved

2. **Integration with Execution Tracking**:
   - ExecutionSnapshot captures MonthlyPlan state when tracking starts
   - User can still adjust MonthlyPlan during execution (dynamic recalculation)
   - Snapshot remains immutable as historical baseline

3. **Testing Requirements**:
   ```swift
   ✅ Test flex adjustment works in DRAFT state
   ✅ Test protected goals not reduced by flex slider
   ✅ Test skipped goals excluded from calculations
   ✅ Test quick actions work in all states
   ✅ Test redistribution strategies preserved
   ✅ Test flex adjustments during EXECUTING state work
   ```

**Success Criteria**: All flex features work identically with execution tracking enabled.

---

### 🔴 HIGH RISK: User Preferences Data Loss

**Risk**: Custom amounts, protection status, skip status lost when starting execution tracking

**Impact**: Users lose all customizations, must reconfigure

**Mitigation Strategy**:

1. **No Data Loss by Design** (ALREADY IMPLEMENTED)
   - MonthlyPlan records persist unchanged
   - ExecutionSnapshot is a separate @Model that copies values
   - Starting execution doesn't modify MonthlyPlan data
   - User preferences remain in MonthlyPlan.customAmount, .isProtected, .isSkipped

2. **Validation on Execution Start**:
   ```swift
   func validateBeforeStartTracking() throws {
       // Verify all MonthlyPlan records have valid data
       for plan in monthlyPlans {
           guard plan.goalId != nil else {
               throw ValidationError.missingGoalId
           }
           guard plan.currency != nil else {
               throw ValidationError.missingCurrency
           }
       }
   }
   ```

3. **Testing Requirements**:
   ```swift
   ✅ Test all MonthlyPlan preferences preserved after starting execution
   ✅ Test custom amounts intact in MonthlyPlan after snapshot created
   ✅ Test flex states intact in MonthlyPlan
   ✅ Test ExecutionSnapshot has correct copies of values
   ✅ Test user can still modify MonthlyPlan during execution
   ```

**Success Criteria**: Zero data loss, all MonthlyPlan preferences accessible during and after execution.

---

### 🟡 MEDIUM RISK: Real-Time Updates Conflicts

**Risk**: Auto-recalculation conflicts with locked execution state

**Impact**: Either stale data (doesn't update) or broken tracking (updates too much)

**Mitigation Strategy**:

1. **State-Aware Recalculation**:
   ```swift
   func handleGoalUpdate() async {
       switch currentPlan.status {
       case .draft:
           // Full recalc - plan is editable
           await calculateRequirements()

       case .executing:
           // Dynamic recalc per user spec
           await calculateRequirements()

       case .closed:
           // No recalc - immutable
           break
       }
   }
   ```

2. **Debouncing Strategy**:
   ```swift
   // DRAFT: 0.5s debounce (responsive)
   // EXECUTING: 1.0s debounce (less frequent)
   // CLOSED: No updates
   ```

3. **Cache Invalidation**:
   ```swift
   // Clear cache only when transitioning states
   func startExecutingPlan() async throws {
       planningService.clearCache()
       // ... create snapshot ...
   }
   ```

4. **Testing Requirements**:
   ```swift
   ✅ Test DRAFT updates immediately
   ✅ Test EXECUTING updates when goals change
   ✅ Test CLOSED doesn't update
   ✅ Test debouncing works in each state
   ✅ Test cache invalidation on transitions
   ```

**Success Criteria**: Updates work correctly in each state, no stale data, no broken tracking.

---

### 🟡 MEDIUM RISK: Quick Actions Break

**Risk**: Quick actions (Skip Month, Pay Half, etc.) don't work with new architecture

**Impact**: Users lose convenient shortcuts

**Mitigation Strategy**:

1. **Adapt to Two-Layer System**:
   ```swift
   func applyQuickAction(_ action: QuickAction) async {
       switch action {
       case .skipMonth:
           // Update BOTH layers
           for req in currentPlan.requirements {
               // Update preference (long-term)
               let pref = getOrCreatePreference(for: req.goalId)
               pref.isSkipped = true

               // Update requirement (this month)
               req.isSkippedSnapshot = true
           }
       }
   }
   ```

2. **State Awareness**:
   - DRAFT: Can use all quick actions
   - EXECUTING: Can use all quick actions (dynamic)
   - CLOSED: Quick actions disabled

3. **Testing Requirements**:
   ```swift
   ✅ Test Skip Month in DRAFT
   ✅ Test Pay Half in EXECUTING
   ✅ Test Pay Exact after adjustments
   ✅ Test Reset clears everything
   ✅ Test actions disabled in CLOSED
   ```

**Success Criteria**: All quick actions work in DRAFT and EXECUTING states.

---

### 🟡 MEDIUM RISK: Performance Degradation

**Risk**: New models/relationships slow down the app

**Impact**: Laggy UI, slow calculations, poor UX

**Mitigation Strategy**:

1. **Keep Existing Caching**:
   ```swift
   // Keep 5-minute cache in MonthlyPlanningService
   // Add month-aware cache keys
   private var planCache: [String: CachedPlan] = [:]

   func getCacheKey(monthLabel: String, goalId: UUID) -> String {
       "\(monthLabel)-\(goalId.uuidString)"
   }
   ```

2. **Lazy Loading**:
   ```swift
   // Don't load all months at once
   // Load on-demand in history view
   func loadHistoryPage(offset: Int, limit: Int) async {
       // Paginated query
   }
   ```

3. **Relationship Optimization**:
   ```swift
   // Use @Relationship(deleteRule: .cascade)
   // Use proper FetchDescriptors with predicates
   // Avoid loading unnecessary data
   ```

4. **Monitoring**:
   ```swift
   // Add performance logging
   let start = Date()
   await calculateRequirements()
   let duration = Date().timeIntervalSince(start)
   if duration > 1.0 {
       AppLog.warning("Slow calculation: \(duration)s")
   }
   ```

5. **Testing Requirements**:
   ```swift
   ✅ Test plan loading <500ms
   ✅ Test requirement calculation <1s
   ✅ Test contribution recording <500ms
   ✅ Test history loading (12 months) <1s
   ✅ Test memory usage acceptable
   ```

**Success Criteria**: Performance matches or beats current implementation.

---

### 🟢 LOW RISK: UI Confusion During Transition

**Risk**: Users don't understand new states/buttons

**Impact**: Support questions, feature underutilization

**Mitigation Strategy**:

1. **Clear UI Indicators**:
   ```swift
   // Show status badge based on execution record
   HStack {
       Text("Monthly Plan")
       if let record = executionRecord {
           StatusBadge(status: record.status) // DRAFT/EXECUTING/CLOSED
       }
   }

   // Different buttons per state
   if executionRecord?.status == .draft || executionRecord == nil {
       Button("Start Tracking This Month")
   } else if executionRecord?.status == .executing {
       Button("Finish This Month")
   }
   ```

2. **First-Time Tutorial**:
   - Show on first open after update
   - Explain new workflow
   - Highlight "Start Executing" button

3. **Contextual Help**:
   ```swift
   // Info button next to "Start Executing"
   Button(action: { showHelp = true }) {
       Image(systemName: "info.circle")
   }
   .popover {
       Text("Starting execution locks your plan...")
   }
   ```

4. **Testing Requirements**:
   ```swift
   ✅ Test UI shows correct state
   ✅ Test buttons change per state
   ✅ Test help text is clear
   ✅ Test tutorial doesn't annoy users
   ```

**Success Criteria**: <5% support questions about new features.

---

### Rollback Strategy

If critical issues arise:

**Level 1: Disable New Features** (1 hour)
```swift
// Add feature flag
struct FeatureFlags {
    static var executionTrackingEnabled = false
}

// In UI
if FeatureFlags.executionTrackingEnabled {
    Button("Start Executing This Plan")
}
```

**Level 2: Revert to Previous Version** (4 hours)
```swift
// Restore from backup
func restorePreMigrationData() throws {
    let backupPath = "Documents/Backups/pre-v4-migration.sqlite"
    // Copy backup over current database
    // Restart app
}
```

**Level 3: Data Recovery** (Not Applicable)

No data migration needed - MonthlyPlan architecture already in place. ExecutionSnapshot is additive (doesn't replace existing data).

---

### Validation Checklist

Before deploying to production:

#### Data Integrity
- [ ] All MonthlyPlan records valid
- [ ] Custom amounts preserved exactly
- [ ] Flex states preserved exactly
- [ ] No orphaned records
- [ ] Relationship integrity validated

#### Feature Parity
- [ ] Flex adjustment works identically
- [ ] Protected goals work identically
- [ ] Skipped goals work identically
- [ ] Quick actions work identically
- [ ] Real-time updates work correctly
- [ ] Multi-currency works identically

#### Performance
- [ ] Plan loading <500ms
- [ ] Calculation <1s
- [ ] Contribution recording <500ms
- [ ] History loading <1s
- [ ] Memory usage acceptable

#### New Features
- [ ] DRAFT → EXECUTING transition works
- [ ] EXECUTING → CLOSED transition works
- [ ] Snapshot created correctly
- [ ] Contributions tracked correctly
- [ ] Fulfillment detection works
- [ ] History view displays correctly

#### Edge Cases
- [ ] Multiple executing plans handled
- [ ] Contribution without plan handled
- [ ] Goal deleted during execution handled
- [ ] Plan closed but contribution added rejected
- [ ] Over-contribution handled
- [ ] Withdrawal handled
- [ ] Empty plan handled

---

### Monitoring After Deployment

**Week 1: Intensive Monitoring**
```swift
// Log all state transitions
AppLog.info("Plan transitioned: \(old) → \(new)")

// Log all migrations
AppLog.info("Migration completed: v3 → v4")

// Track feature usage
Analytics.track("MonthlyPlan.StartExecuting")
Analytics.track("MonthlyPlan.Close")
```

**Week 2-4: Regular Monitoring**
```swift
// Monitor error rates
if errorRate > normalRate * 1.5 {
    alert("Error rate spike detected")
}

// Monitor performance
if avgCalculationTime > 1.0 {
    alert("Performance degradation")
}

// Monitor data integrity
if orphanedCount > 0 {
    alert("Data integrity issue")
}
```

**Metrics to Track**:
- Migration success rate (target: 100%)
- Feature usage (Start Executing: target >50% of users)
- Error rate (target: <0.1%)
- Performance (target: <1s calculations)
- Support tickets (target: <5% about new features)

---

### Success Criteria Summary

✅ **Feature Preservation**: All current features work identically
✅ **Data Integrity**: Zero data loss, all preferences intact
✅ **Performance**: Matches or beats current implementation
✅ **UX**: Users understand new features, <5% support questions
✅ **Stability**: Error rate <0.1%, no critical bugs

If all criteria met: **Implementation Success** ✅
If any criteria fail: **Rollback and reassess** ⚠️

---

## Conclusion

This solution provides a complete separation between **planning** (what you should do) and **execution** (what you actually did). Key features:

1. **User-initiated plan locking** - user controls when to start tracking
2. **Dynamic plan updates** - requirements update when goals change
3. **Disappearing goals** - funded goals remove clutter
4. **Comprehensive history** - all-time tracking with pagination
5. **Rollover handled automatically** - over-contributions reduce future requirements
6. **Manual edit tracking** - withdrawals and adjustments recorded
7. **100% feature preservation** - all current features work identically via two-layer architecture

The system is flexible, user-friendly, provides clear accountability for monthly savings goals, and **preserves all existing functionality** through careful integration design.

---

*Document Version: 3.1*
*Created: 2025-11-15*
*Updated: 2025-11-17 (Corrected to match actual implementation)*
*Status: 80% Complete - Missing UI Layer*

---

## Document Change Log

### Version 3.1 (2025-11-17) - Reality Check

**MAJOR CORRECTION**: This version replaces fictional architectural designs with actual implementation details.

**What Changed**:
1. **Removed fictional data models**:
   - ❌ `GoalPlanPreference` (never existed)
   - ❌ `MonthlyExecutionPlan` (never existed)
   - ❌ `@Model MonthlyRequirement` (wrong - it's a struct)
   - ✅ Documented actual `MonthlyPlan` @Model with real fields

2. **Removed fictional "unified calculation" code**:
   - ❌ Deleted non-existent `GoalCalculationService.getCurrentTotal(includeContributions:)`
   - ✅ Documented actual dual system (crypto vs contributions)
   - ✅ Explained this is **intentional design**, not a bug

3. **Marked missing UI as "TO BE IMPLEMENTED"**:
   - ❌ Removed claim that `ContributionEntryView` exists
   - ❌ Removed claim that [+ Add] buttons exist
   - ✅ Changed to design specification for future implementation

4. **Fixed implementation status**:
   - Changed "Ready for Implementation" → "80% Complete - Missing UI Layer"
   - Added clear breakdown of what's done vs what's missing

**Why This Matters**:
- v3.0 described an idealized architecture that was never built
- Developers following v3.0 would rewrite working code incorrectly
- v3.1 documents the **actual shipping architecture**
- Now you can implement the missing 20% without breaking the existing 80%

### Version 3.0 (2025-11-16) - Idealized Design (SUPERSEDED)
- ~~Proposed unified goal calculations~~ (not implemented)
- ~~Designed two-layer architecture~~ (single layer actually used)
- ~~Specified fictional data models~~ (actual models different)

### Version 2.0 (2025-11-15) - Original Planning Document
- Initial solution design based on requirements
- Architecture proposals
- UI mockups
