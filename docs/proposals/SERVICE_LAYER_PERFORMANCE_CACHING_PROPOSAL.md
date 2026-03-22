# Service Layer Performance and Caching Overhaul Proposal

> Eliminate N+1 data fetches, add strategic caching, and resolve serialization bottlenecks across the service layer

| Metadata | Value |
|---|---|
| Status | Draft |
| Priority | P1 Performance |
| Last Updated | 2026-03-21 |
| Platform | iOS + macOS |
| Scope | Service layer batch operations, caching strategy, serial executor optimization, SwiftUI re-render reduction |
| Affected Runtime | `MonthlyPlanService`, `ExecutionTrackingService`, `AllocationService`, `GoalCalculationService`, `CoinGeckoService`, `DashboardViewModel`, View layer |

---

## 1) Problem

The service layer has several performance patterns that degrade user experience as data volume grows. A user with 10+ goals and 5+ assets will experience noticeable latency.

### 1.1 N+1 Data Fetch Pattern

Multiple services iterate collections and issue individual database queries per item:

**MonthlyPlanService.getOrCreatePlans()**

```
For each active goal (N goals):
    1. Fetch existing plan for this goal + month  → 1 SwiftData query
    2. If not found, create new plan              → 1 SwiftData insert
    3. Save context                                → 1 SwiftData save
Total: Up to 3N database operations for N goals
```

With 15 goals, this produces up to 45 database operations sequentially.

**ExecutionTrackingService.getCompletionEvents()**

```
1. Fetch all completion events                     → 1 query
For each event (N events):
    2. Fetch associated goal by ID                 → 1 query per event
Total: 1 + N queries
```

**AllocationService.processAllocations()**

```
For each allocation change:
    1. Fetch current allocation                    → 1 query
    2. Update or create allocation                 → 1 write
    3. Create allocation history entry             → 1 write
    4. Save context                                → 1 save
Total: Up to 4N operations
```

### 1.2 Missing Service-Level Caching

| Service | Computation Cost | Cache | Recalculation Trigger |
|---|---|---|---|
| `GoalCalculationService` | High (exchange rates + allocation sums) | None | Every view update |
| `MonthlyPlanningService` | Medium (requirement calculations) | None | Every planning view load |
| `CoinGeckoService.fetchCoinList()` | Low compute, high network | `NSCache` (memory, inconsistently used) | Every app launch |
| `BudgetCalculatorService` | Medium (shortfall analysis) | None | Every budget widget render |

`GoalCalculationService` is the worst offender: it recalculates goal progress (fetching exchange rates, summing allocations, converting currencies) on every SwiftUI view body evaluation. For 15 goals on the dashboard, this means 15 concurrent calculation requests per render cycle.

### 1.3 Global Serial Executor Bottleneck

`MonthlyPlanService` uses a single `AsyncSerialExecutor` shared across all plan operations:

```swift
private static let sharedExecutor = AsyncSerialExecutor()
```

This means creating plans for 10 goals takes O(10 * t) time where t is the time per plan, because all operations serialize through one queue. Since plans for different goals are independent, this serialization is unnecessary.

### 1.4 SwiftUI Re-render Cascade

Several patterns cause unnecessary SwiftUI view re-evaluation:

- `DashboardViewModel` publishes multiple `@Published` properties that change independently, but any change triggers a full view body evaluation
- `GoalRowView` uses inline `@StateObject` creation without memoization
- Chart data is recomputed inline in view bodies rather than pre-computed in ViewModels
- `MobileStatsSection` recalculates statistics on every parent state change

## 2) Goal

1. Reduce database operations from O(N) individual queries to O(1) batch queries
2. Add calculation caching with intelligent invalidation for `GoalCalculationService` and `MonthlyPlanningService`
3. Replace global serial executor with per-entity serialization
4. Reduce SwiftUI re-render frequency by 50%+ for dashboard views
5. Maintain data correctness: caches must invalidate on mutations

## 3) Proposed Changes

### 3.1 Batch Data Fetch Pattern

Replace N+1 loops with batch queries:

**MonthlyPlanService - Batch Plan Resolution**

```swift
// Before: N individual queries
func getOrCreatePlans(for goals: [Goal], month: String) async throws -> [MonthlyPlan] {
    var plans: [MonthlyPlan] = []
    for goal in goals {
        let plan = try await getOrCreatePlan(for: goal, month: month) // 1 query each
        plans.append(plan)
    }
    return plans
}

// After: 1 batch query + bulk insert
func getOrCreatePlans(for goals: [Goal], month: String) async throws -> [MonthlyPlan] {
    let goalIds = goals.map(\.id)

    // Single batch fetch for all existing plans
    let descriptor = FetchDescriptor<MonthlyPlan>(
        predicate: #Predicate { plan in
            goalIds.contains(plan.goalId) && plan.monthLabel == month
        }
    )
    let existingPlans = try modelContext.fetch(descriptor)
    let existingGoalIds = Set(existingPlans.map(\.goalId))

    // Bulk create missing plans
    let missingGoals = goals.filter { !existingGoalIds.contains($0.id) }
    let newPlans = missingGoals.map { goal in
        MonthlyPlan(goalId: goal.id, monthLabel: month, /* ... */)
    }
    newPlans.forEach { modelContext.insert($0) }

    // Single save
    try modelContext.save()

    return existingPlans + newPlans
}
```

**ExecutionTrackingService - Eager Goal Loading**

```swift
// Before: Fetch events, then N goal queries
// After: Single fetch with predicate covering both entities
func getCompletionEventsWithGoals() throws -> [(CompletionEvent, Goal?)] {
    let events = try modelContext.fetch(FetchDescriptor<CompletionEvent>())
    let goalIds = events.compactMap(\.goalId)

    // Single batch fetch for all referenced goals
    let goalDescriptor = FetchDescriptor<Goal>(
        predicate: #Predicate { goal in goalIds.contains(goal.id) }
    )
    let goals = try modelContext.fetch(goalDescriptor)
    let goalMap = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })

    return events.map { event in (event, goalMap[event.goalId]) }
}
```

### 3.2 Calculation Cache with Invalidation

```swift
actor GoalCalculationCache {
    struct CachedProgress: Sendable {
        let currentTotal: Double
        let progress: Double
        let status: RequirementStatus
        let computedAt: Date
        let exchangeRateSnapshot: [String: Double]

        var isValid: Bool {
            Date().timeIntervalSince(computedAt) < 60  // 1-minute TTL
        }
    }

    private var cache: [UUID: CachedProgress] = [:]

    func get(goalId: UUID) -> CachedProgress? {
        guard let entry = cache[goalId], entry.isValid else {
            cache.removeValue(forKey: goalId)
            return nil
        }
        return entry
    }

    func set(goalId: UUID, progress: CachedProgress) {
        cache[goalId] = progress
    }

    // Invalidation triggers
    func invalidate(goalId: UUID) {
        cache.removeValue(forKey: goalId)
    }

    func invalidateAll() {
        cache.removeAll()
    }

    func invalidateOnRateChange() {
        // Invalidate all entries whose exchange rate snapshot differs from current rates
        cache.removeAll()
    }
}
```

Integration with `GoalCalculationService`:

```swift
func getProgress(for goal: Goal) async throws -> GoalProgress {
    // Check cache first
    if let cached = await calculationCache.get(goalId: goal.id) {
        return GoalProgress(
            currentTotal: cached.currentTotal,
            progress: cached.progress,
            status: cached.status,
            source: .cached
        )
    }

    // Compute fresh
    let progress = try await computeProgress(for: goal)

    // Cache result
    await calculationCache.set(
        goalId: goal.id,
        progress: .init(
            currentTotal: progress.currentTotal,
            progress: progress.progress,
            status: progress.status,
            computedAt: Date(),
            exchangeRateSnapshot: currentRates
        )
    )

    return progress
}
```

### 3.3 Per-Entity Serial Executor

Replace global serialization with per-goal serialization:

```swift
// Before: Global serial executor
private static let sharedExecutor = AsyncSerialExecutor()

// After: Per-goal executor map
actor PlanExecutorMap {
    private var executors: [UUID: AsyncSerialExecutor] = [:]

    func executor(for goalId: UUID) -> AsyncSerialExecutor {
        if let existing = executors[goalId] {
            return existing
        }
        let executor = AsyncSerialExecutor()
        executors[goalId] = executor
        return executor
    }

    func cleanup(goalId: UUID) {
        executors.removeValue(forKey: goalId)
    }
}
```

This allows plan operations for different goals to run concurrently while still serializing operations for the same goal (preventing conflicts).

### 3.4 SwiftUI Re-render Optimization

**Dedicated Published Properties per Section**

```swift
// Before: Single ViewModel with many @Published properties
class DashboardViewModel: ObservableObject {
    @Published var balanceHistory: [ChartPoint] = []    // Change triggers full re-render
    @Published var assetComposition: [ChartPoint] = []  // Change triggers full re-render
    @Published var forecastData: [ChartPoint] = []      // Change triggers full re-render
    @Published var isLoading: Bool = false               // Change triggers full re-render
}

// After: Section-specific observable objects
class DashboardViewModel: ObservableObject {
    let balanceSection = ChartSectionModel()
    let compositionSection = ChartSectionModel()
    let forecastSection = ChartSectionModel()
    @Published var isLoading: Bool = false
}

@Observable
class ChartSectionModel {
    var data: [ChartPoint] = []
    var loadingState: ChartLoadingState = .idle
    var error: UserFacingError?
}
```

**Equatable View Data**

```swift
// Wrap computed data in Equatable struct to prevent unnecessary re-renders
struct GoalRowData: Equatable {
    let name: String
    let emoji: String?
    let progress: Double
    let currentTotal: Double
    let targetAmount: Double
    let status: RequirementStatus
}
```

## 4) Implementation Plan

### Phase 1: Batch Query Pattern (Est. 3-4 hours)

| Step | Action | Files |
|---|---|---|
| 1.1 | Refactor `MonthlyPlanService.getOrCreatePlans()` to batch fetch + bulk insert | `Services/MonthlyPlanService.swift` |
| 1.2 | Refactor `ExecutionTrackingService.getCompletionEvents()` to eager-load goals | `Services/ExecutionTrackingService.swift` |
| 1.3 | Refactor `AllocationService.processAllocations()` to batch operations | `Services/AllocationService.swift` |
| 1.4 | Update existing tests to verify batch behavior and correctness | `Tests/MonthlyPlanServiceTests.swift`, etc. |
| 1.5 | Add performance benchmark tests (measure time for 20-goal scenario) | New: `Tests/ServicePerformanceBenchmarks.swift` |

### Phase 2: Calculation Caching (Est. 3-4 hours)

| Step | Action | Files |
|---|---|---|
| 2.1 | Create `GoalCalculationCache` actor | New: `Utilities/GoalCalculationCache.swift` |
| 2.2 | Integrate cache into `GoalCalculationService` | `Services/GoalCalculationService.swift` |
| 2.3 | Add cache invalidation on goal mutation, allocation change, and rate refresh | `Services/PersistenceMutationServices.swift`, `Services/ExchangeRateService.swift` |
| 2.4 | Create `MonthlyPlanningCache` for requirement calculations | New: `Utilities/MonthlyPlanningCache.swift` |
| 2.5 | Unit tests for cache hit/miss/invalidation scenarios | New: `Tests/GoalCalculationCacheTests.swift` |

### Phase 3: Serial Executor Optimization (Est. 1-2 hours)

| Step | Action | Files |
|---|---|---|
| 3.1 | Create `PlanExecutorMap` actor | New: `Utilities/PlanExecutorMap.swift` |
| 3.2 | Replace `sharedExecutor` in `MonthlyPlanService` with per-goal executors | `Services/MonthlyPlanService.swift` |
| 3.3 | Add concurrent plan creation test (verify parallel execution for different goals) | New: `Tests/PlanExecutorMapTests.swift` |

### Phase 4: SwiftUI Re-render Reduction (Est. 3-4 hours)

| Step | Action | Files |
|---|---|---|
| 4.1 | Extract `ChartSectionModel` as `@Observable` sub-model | `ViewModels/DashboardViewModel.swift` |
| 4.2 | Create `GoalRowData` equatable struct for `GoalRowView` | `ViewModels/GoalRowViewModel.swift` |
| 4.3 | Audit and refactor inline calculations in view bodies to pre-computed properties | `Views/DashboardView.swift`, `Views/GoalDetailView.swift` |
| 4.4 | Add `EquatableView` wrapper where appropriate | Various view files |
| 4.5 | Measure re-render frequency before/after using Instruments | Manual testing |

## 5) Performance Targets

| Metric | Current (Est.) | Target | Measurement |
|---|---|---|---|
| Dashboard load time (15 goals) | ~2-3s | < 500ms | Time from `onAppear` to last chart rendered |
| Monthly plan creation (10 goals) | ~1-2s (serial) | < 300ms (parallel) | Time from button tap to plans visible |
| Goal row render count per navigation | 3-5x per row | 1x per row | Instruments SwiftUI render count |
| GoalCalculationService calls per dashboard load | 15+ (one per goal) | 1-3 (cache hits) | Log counter in service |
| Database queries for plan resolution | 30-45 (N+1) | 2-3 (batch) | SwiftData query log |

## 6) Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Cache serving stale calculation results | Medium | High | 1-minute TTL with mandatory invalidation on mutations; freshness indicator in UI |
| Batch query predicate complexity with SwiftData | Low | Medium | Fall back to chunked queries (batches of 50) if predicate performance degrades |
| Per-goal executor memory growth | Low | Low | Cleanup executors when goals are deleted; cap at 100 concurrent executors |
| SwiftUI `@Observable` migration breaking existing `@StateObject` patterns | Medium | Medium | Incremental migration; keep `@StateObject` for views not yet migrated |
| Incorrect batch insert creating duplicates | Low | High | Wrap in transaction; verify with deduplication check before save |

## 7) Success Metrics

- Dashboard loads in under 500ms with 15+ goals (measured via Instruments)
- Monthly plan creation completes in under 300ms for 10 goals
- Database query count reduced by 80% for plan resolution and execution tracking
- `GoalCalculationService` cache hit rate > 80% during normal dashboard browsing
- Zero correctness regressions (all existing tests pass; new cache tests pass)
- SwiftUI body evaluation count reduced by 50% for `DashboardView`

## 8) Out of Scope

- Network request performance (covered in Offline-First Architecture proposal)
- View hierarchy flattening for compilation speed (future work)
- Android performance parity (separate effort)
- Image/asset caching (not currently a concern)

---

## Related Documentation

- `docs/ARCHITECTURE.md` - Service layer architecture
- `Services/MonthlyPlanService.swift` - Primary N+1 location
- `Services/GoalCalculationService.swift` - Primary cache candidate
- `Utilities/AsyncSerialExecutor.swift` - Current serialization utility
- `ViewModels/DashboardViewModel.swift` - Re-render optimization target
