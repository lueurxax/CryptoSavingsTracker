# CloudKit Migration Plan

## Overview

This document outlines the changes required to make the SwiftData models compatible with CloudKit for iCloud sync.

## CloudKit Requirements

1. **No unique constraints** - `@Attribute(.unique)` is not supported
2. **All attributes must be optional or have defaults**
3. **All relationships must have inverse relationships**
4. **All relationships must be optional**

## Current Issues by Model

### 1. Goal

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var name: String` | Non-optional | Add default `""` |
| `var deadline: Date` | Non-optional | Add default `Date()` |
| `var allocations: [AssetAllocation]` | No inverse | Add inverse to AssetAllocation |

### 2. Asset

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var currency: String` | Non-optional | Add default `""` |
| `var transactions: [Transaction]` | No inverse | Add inverse to Transaction |
| `var allocations: [AssetAllocation]` | No inverse | Add inverse to AssetAllocation |

### 3. AssetAllocation

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var amount: Double` | Non-optional | Add default `0.0` |
| `var createdDate: Date` | Non-optional | Add default `Date()` |
| `var lastModifiedDate: Date` | Non-optional | Add default `Date()` |
| `var asset: Asset?` | No inverse | Add `@Relationship(inverse: \Asset.allocations)` |
| `var goal: Goal?` | No inverse | Add `@Relationship(inverse: \Goal.allocations)` |

### 4. Transaction

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var amount: Double` | Non-optional | Add default `0.0` |
| `var date: Date` | Non-optional | Add default `Date()` |
| `@Relationship var asset: Asset` | Non-optional, no inverse | Make optional, add inverse |

### 5. MonthlyPlan

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var goalId: UUID` | Non-optional | Add default `UUID()` |
| `var requiredMonthly: Double` | Non-optional | Add default `0.0` |
| `var remainingAmount: Double` | Non-optional | Add default `0.0` |
| `var monthsRemaining: Int` | Non-optional | Add default `0` |
| `var currency: String` | Non-optional | Add default `""` |
| `var statusRawValue: String` | Non-optional | Has default already |
| `var lastCalculated: Date` | Non-optional | Add default `Date()` |
| `var createdDate: Date` | Non-optional | Add default `Date()` |
| `var lastModifiedDate: Date` | Non-optional | Add default `Date()` |
| `var executionRecord` | No inverse | Add inverse to MonthlyExecutionRecord |

### 6. Contribution

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var amount: Double` | Non-optional | Add default `0.0` |
| `var date: Date` | Non-optional | Add default `Date()` |
| `var sourceType: ContributionSource` | Non-optional enum | Store as optional String |
| `var monthLabel: String` | Non-optional | Add default `""` |
| `var isPlanned: Bool` | Non-optional | Add default `false` |

### 7. MonthlyExecutionRecord

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var monthLabel: String` | Non-optional | Add default `""` |
| `var statusRawValue: String` | Non-optional | Has default already |
| `var createdAt: Date` | Non-optional | Add default `Date()` |
| `var trackedGoalIds: Data` | Non-optional | Add default `Data()` |
| `var completedExecution` | No inverse | Add inverse to CompletedExecution |
| Needs inverse for `MonthlyPlan.executionRecord` | | Add relationship |

### 8. ExecutionSnapshot

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var capturedAt: Date` | Non-optional | Add default `Date()` |
| `var totalPlanned: Double` | Non-optional | Add default `0.0` |
| `var snapshotData: Data` | Non-optional | Add default `Data()` |

### 9. CompletedExecution

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var monthLabel: String` | Non-optional | Add default `""` |
| `var completedAt: Date` | Non-optional | Add default `Date()` |
| Needs inverse for `MonthlyExecutionRecord.completedExecution` | | Add relationship |

### 10. AllocationHistory

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var amount: Double` | Non-optional | Add default `0.0` |
| `var timestamp: Date` | Non-optional | Add default `Date()` |
| `var monthLabel: String` | Non-optional | Add default `""` |
| `var asset: Asset?` | No inverse | Add inverse relationship |
| `var goal: Goal?` | No inverse | Add inverse relationship |

---

## Implementation Plan

### Phase 1: Add Missing Inverse Relationships

Create bidirectional relationships:

```swift
// Asset.swift
@Relationship(deleteRule: .cascade, inverse: \Transaction.asset)
var transactions: [Transaction] = []

@Relationship(deleteRule: .cascade, inverse: \AssetAllocation.asset)
var allocations: [AssetAllocation] = []

@Relationship(deleteRule: .nullify, inverse: \AllocationHistory.asset)
var allocationHistory: [AllocationHistory] = []

// Goal.swift
@Relationship(deleteRule: .cascade, inverse: \AssetAllocation.goal)
var allocations: [AssetAllocation] = []

@Relationship(deleteRule: .nullify, inverse: \AllocationHistory.goal)
var allocationHistory: [AllocationHistory] = []

// Transaction.swift
@Relationship(inverse: \Asset.transactions)
var asset: Asset?  // Make optional

// AssetAllocation.swift
@Relationship(inverse: \Asset.allocations) var asset: Asset?
@Relationship(inverse: \Goal.allocations) var goal: Goal?

// MonthlyExecutionRecord.swift
@Relationship(deleteRule: .cascade, inverse: \CompletedExecution.executionRecord)
var completedExecution: CompletedExecution?

@Relationship(inverse: \MonthlyPlan.executionRecord)
var plans: [MonthlyPlan] = []

// MonthlyPlan.swift
@Relationship(deleteRule: .nullify, inverse: \MonthlyExecutionRecord.plans)
var executionRecord: MonthlyExecutionRecord?

// CompletedExecution.swift
@Relationship(inverse: \MonthlyExecutionRecord.completedExecution)
var executionRecord: MonthlyExecutionRecord?

// AllocationHistory.swift
@Relationship(inverse: \Asset.allocationHistory) var asset: Asset?
@Relationship(inverse: \Goal.allocationHistory) var goal: Goal?
```

### Phase 2: Add Default Values to All Properties

```swift
// Goal.swift
var id: UUID = UUID()
var name: String = ""
var currency: String = "USD"
var targetAmount: Double = 0.0
var deadline: Date = Date()
var startDate: Date = Date()

// Asset.swift
var id: UUID = UUID()
var currency: String = ""

// Transaction.swift
var id: UUID = UUID()
var amount: Double = 0.0
var date: Date = Date()

// AssetAllocation.swift
var id: UUID = UUID()
var amount: Double = 0.0
var createdDate: Date = Date()
var lastModifiedDate: Date = Date()

// MonthlyPlan.swift
var id: UUID = UUID()
var goalId: UUID = UUID()
var requiredMonthly: Double = 0.0
var remainingAmount: Double = 0.0
var monthsRemaining: Int = 0
var currency: String = ""
var lastCalculated: Date = Date()
var createdDate: Date = Date()
var lastModifiedDate: Date = Date()

// Contribution.swift
var id: UUID = UUID()
var amount: Double = 0.0
var date: Date = Date()
var sourceTypeRaw: String = "manualDeposit"  // Store enum as string
var monthLabel: String = ""
var isPlanned: Bool = false

// MonthlyExecutionRecord.swift
var id: UUID = UUID()
var monthLabel: String = ""
var createdAt: Date = Date()
var trackedGoalIds: Data = Data()

// ExecutionSnapshot.swift
var id: UUID = UUID()
var capturedAt: Date = Date()
var totalPlanned: Double = 0.0
var snapshotData: Data = Data()

// CompletedExecution.swift
var id: UUID = UUID()
var monthLabel: String = ""
var completedAt: Date = Date()

// AllocationHistory.swift
var id: UUID = UUID()
var amount: Double = 0.0
var timestamp: Date = Date()
var monthLabel: String = ""
```

### Phase 3: Remove @Attribute(.unique) Constraints

Remove `@Attribute(.unique)` from all models. Instead, use application-level logic to prevent duplicates when needed.

```swift
// Before
@Attribute(.unique) var id: UUID

// After
var id: UUID = UUID()
```

### Phase 4: Handle Enum Properties

CloudKit doesn't support custom enums directly. Store as raw String values:

```swift
// Contribution.swift - Before
var sourceType: ContributionSource

// Contribution.swift - After
var sourceTypeRaw: String = ContributionSource.manualDeposit.rawValue

var sourceType: ContributionSource {
    get { ContributionSource(rawValue: sourceTypeRaw) ?? .manualDeposit }
    set { sourceTypeRaw = newValue.rawValue }
}
```

### Phase 5: Update Initializers

Update all initializers to work with optional relationships:

```swift
// Transaction.swift
init(amount: Double = 0.0, asset: Asset? = nil, comment: String? = nil) {
    self.id = UUID()
    self.amount = amount
    self.date = Date()
    self.asset = asset
    self.comment = comment
}
```

### Phase 6: Enable CloudKit

After all model changes:

```swift
// CryptoSavingsTrackerApp.swift
let modelConfiguration = ModelConfiguration(
    "default",
    schema: schema,
    isStoredInMemoryOnly: false,
    allowsSave: true,
    groupContainer: .none,
    cloudKitDatabase: .automatic  // Enable CloudKit
)
```

---

## Data Migration Strategy

### Option A: Clean Migration (Recommended for Development)

1. Export existing data to JSON
2. Delete app and reinstall
3. Import data after CloudKit models are in place

### Option B: In-Place Migration

1. Create new CloudKit-compatible model versions
2. Use SwiftData's automatic migration (works for adding defaults/making optional)
3. Manual migration script for relationship changes

### Option C: Parallel Database

1. Keep existing local database
2. Create new CloudKit database
3. Background sync service copies data between them

---

## Testing Checklist

- [ ] All models compile without errors
- [ ] Relationships are bidirectional
- [ ] No `@Attribute(.unique)` constraints
- [ ] All properties have defaults or are optional
- [ ] CloudKit schema deploys successfully
- [ ] Data syncs between devices
- [ ] Conflict resolution works correctly
- [ ] Offline mode works properly

---

## Risks and Considerations

1. **Breaking Change**: Existing local data may not migrate automatically
2. **Conflict Resolution**: CloudKit uses last-write-wins by default
3. **Performance**: CloudKit sync adds latency to saves
4. **Storage Limits**: iCloud has storage quotas
5. **Apple ID Required**: Users must be signed into iCloud

---

## Timeline Estimate

| Phase | Complexity |
|-------|------------|
| Phase 1: Inverse relationships | Medium |
| Phase 2: Default values | Low |
| Phase 3: Remove unique constraints | Low |
| Phase 4: Enum handling | Low |
| Phase 5: Update initializers | Medium |
| Phase 6: Enable CloudKit | Low |
| Testing & validation | High |

---

## References

- [Apple SwiftData with CloudKit](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [CloudKit Schema Requirements](https://developer.apple.com/documentation/cloudkit/designing_and_creating_a_cloudkit_database)
