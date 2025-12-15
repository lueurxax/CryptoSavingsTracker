# Current Planning Implementation vs. DRAFT State Requirements

## Executive Summary

The current implementation already has a **solid foundation** for the DRAFT state of monthly planning. However, there are key architectural differences and missing features needed for the full execution tracking system.

**Overall Assessment**: ~70% complete for DRAFT state requirements

---

## Comparison Matrix

| Feature | Document Requirement | Current Implementation | Status | Gap Analysis |
|---------|---------------------|------------------------|--------|--------------|
| **Monthly Plan Model** | MonthlyPlan with status field | MonthlyPlan exists but different structure | 🟡 Partial | Different architecture |
| **Plan Status** | DRAFT → EXECUTING → CLOSED | No status tracking | ❌ Missing | Need to add lifecycle states |
| **Monthly Requirements** | Per-goal requirements | MonthlyRequirement struct (not @Model) | 🟡 Partial | Exists but not persisted |
| **Plan Persistence** | Persisted per month | MonthlyPlan persisted per goal | 🟡 Partial | Different granularity |
| **Custom Amounts** | User can override | ✅ Supported via customAmount | ✅ Complete | Working well |
| **Flex State** | Flexible/Protected/Skipped | ✅ Supported | ✅ Complete | Working well |
| **Monthly Calculation** | Calculate requirements | ✅ MonthlyPlanningService | ✅ Complete | Working well |
| **Requirements Display** | Show list of goals + amounts | ✅ MonthlyPlanningView | ✅ Complete | Working well |
| **"Start Executing" Button** | User-initiated transition | ❌ Missing | ❌ Missing | Need to add |
| **Month Label** | "2025-09" grouping | ❌ Missing | ❌ Missing | Need to add |
| **Plan Snapshot** | Capture state when starting | ❌ Missing | ❌ Missing | For Phase 2 |

---

## Detailed Analysis

### 1. Data Model Architecture

#### Current Implementation:
```swift
@Model
final class MonthlyPlan {
    var id: UUID
    var goalId: UUID              // ← One plan PER GOAL
    var requiredMonthly: Double
    var remainingAmount: Double
    var monthsRemaining: Int
    var currency: String
    var flexState: FlexState
    var customAmount: Double?
    // No status, no monthLabel
}

struct MonthlyRequirement {      // ← NOT persisted
    let goalId: UUID
    let goalName: String
    let requiredMonthly: Double
    // Calculated on-the-fly
}
```

#### Document Requirement:
```swift
@Model
final class MonthlyPlan {
    var id: UUID
    var monthLabel: String         // ← One plan PER MONTH
    var status: PlanStatus         // DRAFT/EXECUTING/CLOSED
    var startedAt: Date?
    var closedAt: Date?

    // Relationships
    var requirements: [MonthlyRequirement]
    var snapshot: MonthlyPlanSnapshot?
}

@Model
final class MonthlyRequirement { // ← IS persisted
    var goalId: UUID
    var goalName: String
    var requiredAmount: Double
    var customAmount: Double?
    var isFulfilledThisMonth: Bool

    var plan: MonthlyPlan?
}
```

**Gap**:
- Current: One `MonthlyPlan` per goal (goal-centric)
- Required: One `MonthlyPlan` per month with multiple requirements (month-centric)

**Impact**:
- ✅ Good for tracking individual goal settings
- ❌ Cannot track monthly execution as a unit
- ❌ Cannot create historical snapshots per month

---

### 2. What's Working Well ✅

#### A. Calculation Logic
```swift
// Current MonthlyPlanningService
func calculateMonthlyRequirements(for goals: [Goal]) async -> [MonthlyRequirement]
```
- ✅ Calculates required monthly amounts correctly
- ✅ Handles multiple currencies
- ✅ Determines status (onTrack, attention, critical)
- ✅ Caching for performance

**Assessment**: This logic is solid and can be reused.

#### B. User Preferences
```swift
// Current MonthlyPlan
var customAmount: Double?        // User override
var flexState: FlexState         // flexible/protected/skipped
var isProtected: Bool
var isSkipped: Bool
```
- ✅ Users can set custom amounts
- ✅ Flex adjustment system works
- ✅ Protection from adjustments

**Assessment**: This is exactly what we need for DRAFT state editing.

#### C. UI Display
```swift
// MonthlyPlanningView
- Shows list of goals
- Displays required amounts
- Shows progress bars
- Status indicators (critical/attention)
```
- ✅ Clean, functional UI
- ✅ Shows all necessary information

**Assessment**: UI is 90% ready for DRAFT state.

---

### 3. What's Missing ❌

#### A. Plan Lifecycle States
```swift
// Need to add:
enum PlanStatus: String, Codable {
    case draft      // Current implementation is always "draft"
    case executing  // Missing
    case closed     // Missing
}
```

**Why it matters**:
- Cannot distinguish between "planning" and "executing"
- Cannot lock plans for historical tracking
- No way to prevent editing closed plans

#### B. Month-Based Grouping
```swift
// Current: No month grouping
// Plans are per-goal, no date association

// Need:
var monthLabel: String  // "2025-09"
```

**Why it matters**:
- Cannot view "September's plan" as a unit
- Cannot compare month-to-month
- No historical tracking

#### C. Start Execution Button
```swift
// Current: No explicit "start" action
// Users just view the plan

// Need:
Button("Start Executing This Plan") {
    await startExecutingPlan()
}
```

**Why it matters**:
- No clear transition from planning to execution
- User doesn't commit to a plan
- No snapshot of "what I planned to do this month"

#### D. Contribution Tracking Integration
```swift
// Current: No link between plans and actual contributions
// When user adds money, plan just recalculates

// Need:
- Track contributions against plan
- Mark requirements as fulfilled
- Show progress toward monthly plan
```

**Why it matters**:
- Can't see "Did I follow my plan?"
- No accountability
- Plan is just a calculator, not a tracker

---

### 4. Architecture Comparison

#### Current Architecture (Goal-Centric)
```
┌──────────┐
│  Goal A  │
└────┬─────┘
     │
     ├──> MonthlyPlan (Goal A)
     │      - requiredMonthly: $600
     │      - customAmount: $800
     │
┌────┴─────┐
│  Goal B  │
└────┬─────┘
     │
     └──> MonthlyPlan (Goal B)
            - requiredMonthly: $300
```

**Pros**:
- Easy to see plan for each goal
- Natural relationship (goal has a plan)

**Cons**:
- No monthly view of "all goals this month"
- Can't track execution as a unit
- No historical "September plan" snapshot

#### Required Architecture (Month-Centric)
```
┌────────────────────────┐
│  MonthlyPlan: Sept 2025│
│  Status: DRAFT         │
└───────┬────────────────┘
        │
        ├──> Requirement (Goal A): $600
        ├──> Requirement (Goal B): $300
        └──> Requirement (Goal C): $400
```

**Pros**:
- Can view entire month's plan
- Can lock/snapshot monthly plan
- Can track execution per month
- Historical comparison possible

**Cons**:
- Slightly more complex relationships
- Need migration from current structure

---

## Migration Path

### Option 1: Keep Both (Recommended)
```swift
// Keep current MonthlyPlan for individual goal tracking
@Model
final class MonthlyPlan {
    // Current structure (per-goal settings)
}

// Add new MonthlyExecutionPlan for month-based tracking
@Model
final class MonthlyExecutionPlan {
    var monthLabel: String
    var status: PlanStatus
    var requirements: [MonthlyRequirement]
}
```

**Pros**:
- No breaking changes
- Current features keep working
- Add execution tracking alongside

**Cons**:
- Two similar models (naming confusion)
- Slight duplication

### Option 2: Refactor (Clean but risky)
```swift
// Rename current MonthlyPlan → GoalPlanSettings
@Model
final class GoalPlanSettings {
    var goalId: UUID
    var customAmount: Double?
    var flexState: FlexState
}

// Replace with new MonthlyPlan (per document)
@Model
final class MonthlyPlan {
    var monthLabel: String
    var status: PlanStatus
    var requirements: [MonthlyRequirement]
}
```

**Pros**:
- Cleaner architecture
- Matches document exactly
- Better separation of concerns

**Cons**:
- Breaking change
- Need data migration
- Risk of bugs

---

## What Can Be Reused

### ✅ Keep As-Is:
1. **MonthlyPlanningService** calculation logic
2. **FlexState** enum and logic
3. **RequirementStatus** enum
4. **UI components** (with minor updates)
5. **Custom amount** functionality
6. **Currency handling**

### 🔄 Needs Adaptation:
1. **MonthlyPlan model** - add status, monthLabel
2. **MonthlyRequirement** - make it @Model
3. **MonthlyPlanningView** - add "Start Executing" button
4. **Data persistence** - shift from per-goal to per-month

### ➕ Need to Add:
1. **Plan lifecycle management** (DRAFT → EXECUTING → CLOSED)
2. **MonthlyPlanSnapshot** model
3. **Contribution tracking** integration
4. **Execution view** (separate from planning view)
5. **History view**

---

## Recommended Next Steps

### Phase 1: Extend Current Implementation (Week 1)
1. ✅ Keep current MonthlyPlan as-is
2. ✅ Add new MonthlyExecutionPlan model
3. ✅ Add monthLabel field
4. ✅ Add status field (DRAFT/EXECUTING/CLOSED)
5. ✅ Make MonthlyRequirement a @Model

### Phase 2: Add Lifecycle (Week 2)
1. ✅ Add "Start Executing This Plan" button
2. ✅ Implement plan status transitions
3. ✅ Create MonthlyPlanSnapshot on start
4. ✅ Prevent editing closed plans

### Phase 3: UI Updates (Week 3)
1. ✅ Separate PlanningView (DRAFT) from ExecutionView (EXECUTING)
2. ✅ Add plan status indicators
3. ✅ Show "currently executing" vs "draft"
4. ✅ Add navigation between views

### Phase 4: Integration (Week 4)
1. ✅ Link Contribution tracking
2. ✅ Track isFulfilledThisMonth
3. ✅ Update progress in real-time
4. ✅ Add history view

---

## Conclusion

**Current State**: You have a **solid foundation** for monthly planning in DRAFT state.

**What Works**:
- ✅ Calculation logic is excellent
- ✅ User preferences (custom amounts, flex state) work well
- ✅ UI is clean and functional
- ✅ Currency handling is robust

**What's Missing**:
- ❌ Plan lifecycle (DRAFT → EXECUTING → CLOSED)
- ❌ Month-based organization (currently goal-based)
- ❌ Execution tracking integration
- ❌ Historical snapshots

**Effort to Complete**:
- DRAFT state alone: ~30% more work (add status, monthLabel, "Start" button)
- Full execution system: ~70% more work (as per document)

**Recommendation**:
**Option 1 (Keep Both)** is safer and faster. You can:
1. Keep current `MonthlyPlan` for goal settings
2. Add new `MonthlyExecutionPlan` for month tracking
3. Build execution features on top without breaking existing code

This allows you to ship DRAFT improvements quickly while building toward the full vision.

---

*Document Version: 1.0*
*Created: 2025-11-15*
*Status: Analysis Complete*
