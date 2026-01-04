# CloudKit Migration Plan

> Changes required for SwiftData models to support CloudKit iCloud sync

| Metadata | Value |
|----------|-------|
| Status | 📋 Planning |
| Last Updated | 2026-01-04 |
| Platform | iOS |
| Audience | Developers |

---

## Overview

This document outlines the changes required to make the SwiftData models compatible with CloudKit for iCloud sync.

> **Architecture Note:** As of the contribution tracking redesign, the app no longer uses a persisted `Contribution` model. Contributions are now **timestamp-derived** from `Transaction.date` and `AllocationHistory.timestamp` during active execution, then frozen into `CompletedExecution` snapshots on completion. See `CONTRIBUTION_TRACKING_REDESIGN.md` for details.

## CloudKit Requirements

1. **No unique constraints** - `@Attribute(.unique)` is not supported
2. **All attributes must be optional or have defaults**
3. **All relationships must have inverse relationships**
4. **To-one relationships must be optional** - Due to sync ordering, a record may arrive before its related record. To-many arrays (`[Type] = []`) are fine as non-optional with empty default.
5. **Data blobs** - `Data` properties sync fine but should be kept reasonably sized (CloudKit has per-record size limits ~1MB)

> ⚠️ **CRITICAL: SwiftData loads don't run `init()`**
>
> When CloudKit materializes records, SwiftData **does not call your custom initializers**. It creates instances and directly populates stored properties from the database. This means:
> - Defaults must be on the **stored property declarations** (e.g., `var status: String = "draft"`)
> - Setting a value in `init()` is **not sufficient** for CloudKit compatibility
> - If a property has no default on its declaration, CloudKit may fail to materialize the record
>
> Several current models violate this by relying on "set in init" patterns. These are called out in the tables below.

### Current Violations Summary

| Requirement | Violating Models | Count |
|-------------|------------------|-------|
| `@Attribute(.unique)` | Goal, Asset, AssetAllocation, Transaction, MonthlyPlan, MonthlyExecutionRecord, ExecutionSnapshot, CompletedExecution, AllocationHistory | **9/9 models** |
| Missing `@Relationship` decorator | Transaction (asset), AssetAllocation (asset, goal), AllocationHistory (asset, goal) | **5 properties** |
| Missing inverse relationships | CompletedExecution↔MonthlyExecutionRecord, MonthlyPlan↔MonthlyExecutionRecord, AllocationHistory↔Asset, AllocationHistory↔Goal | **4 pairs** |
| Non-optional without defaults | Various `String`, `Date`, `Double` properties (includes `statusRawValue`, `monthLabel` on MonthlyPlan/MonthlyExecutionRecord) | ~27 properties |

> **Note on "Missing `@Relationship`":** These properties are declared as plain `var asset: Asset?` without the `@Relationship` decorator. They work locally but CloudKit requires explicit relationship annotations with inverses. This is distinct from "Missing inverse" where a `@Relationship` exists but lacks an inverse specification.

### Tradeoff Decisions

1. **UUID `id` properties**: We'll keep `var id: UUID = UUID()` as a normal attribute (not unique). CloudKit generates its own record IDs, so our UUIDs become just another property. Risk: duplicate records possible during sync conflicts—mitigate with application-level deduplication on fetch using these composite keys:
   - `MonthlyPlan`: dedupe by `(monthLabel, goalId)`
   - `MonthlyExecutionRecord`: dedupe by `monthLabel` (one per month)
   - `AllocationHistory`: dedupe by `(assetId, goalId, timestamp, createdAt)`
   - `AssetAllocation`: dedupe by `(asset.id, goal.id)`
   - `CompletedExecution`: dedupe by `monthLabel`

   > ⚠️ **Logical duplicates beyond month-based records:** Removing uniqueness constraints will also make **logical duplicates** more visible. For example:
   > - Two devices could create the **same Asset** independently by `(chainId, address, currency)` tuple
   > - Two devices could create the **same Goal** with identical names/targets
   >
   > The dedupe strategy should account for these cases, not just temporal records like MonthlyPlan. Consider:
   > - `Asset`: dedupe by `(chainId, address, currency)` or `(walletAddress, currency)` depending on chain
   > - `Goal`: dedupe by `(name, targetAmount, deadline, currency)` or accept duplicates with user-driven merge

2. **Orphaned relationships**: CloudKit's eventual consistency means relationships can temporarily point to non-existent records. All relationships must handle `nil` gracefully.

3. **Data blob serialization**: We accept that `CompletedExecution` and `ExecutionSnapshot` use JSON-encoded Data blobs. These aren't queryable in CloudKit but keep our model simpler than normalizing into separate records.

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
| `var amount: Double` | Non-optional, set in init only | Add default `0.0` on declaration |
| `var createdDate: Date` | Non-optional, set in init only | Add default `Date()` on declaration |
| `var lastModifiedDate: Date` | Non-optional, set in init only | Add default `Date()` on declaration |
| `var asset: Asset?` | ⚠️ **Missing `@Relationship`**, no inverse | Add `@Relationship(inverse: \Asset.allocations)` |
| `var goal: Goal?` | ⚠️ **Missing `@Relationship`**, no inverse | Add `@Relationship(inverse: \Goal.allocations)` |

### 4. Transaction

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var amount: Double` | Non-optional, set in init only | Add default `0.0` on declaration |
| `var date: Date` | Non-optional, set in init only | Add default `Date()` on declaration |
| `var asset: Asset` | ⚠️ **Missing `@Relationship`**, non-optional, no inverse | Add `@Relationship(inverse: \Asset.transactions)`, make optional |

### 5. MonthlyPlan

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var goalId: UUID` | Non-optional, set in init only | Add default `UUID()` on declaration |
| `var monthLabel: String` | Non-optional, set in init only | Add default `""` on declaration |
| `var requiredMonthly: Double` | Non-optional, set in init only | Add default `0.0` on declaration |
| `var remainingAmount: Double` | Non-optional, set in init only | Add default `0.0` on declaration |
| `var monthsRemaining: Int` | Non-optional, set in init only | Add default `0` on declaration |
| `var currency: String` | Non-optional, set in init only | Add default `""` on declaration |
| `var statusRawValue: String` | ⚠️ Non-optional, **NO default on declaration** (set in init) | Add default `RequirementStatus.onTrack.rawValue` on declaration |
| `var lastCalculated: Date` | Non-optional, set in init only | Add default `Date()` on declaration |
| `var createdDate: Date` | Non-optional, set in init only | Add default `Date()` on declaration |
| `var lastModifiedDate: Date` | Non-optional, set in init only | Add default `Date()` on declaration |
| `var executionRecord` | No inverse | Add inverse to MonthlyExecutionRecord |

### 6. MonthlyExecutionRecord

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var monthLabel: String` | Non-optional, set in init only | Add default `""` on declaration |
| `var statusRawValue: String` | ⚠️ Non-optional, **NO default on declaration** (set in init) | Add default `ExecutionStatus.draft.rawValue` on declaration |
| `var createdAt: Date` | Non-optional, set in init only | Add default `Date()` on declaration |
| `var trackedGoalIds: Data` | Non-optional Data blob, set in init only | Add default `Data()` on declaration |
| `var completedExecution` | No inverse | Add inverse to CompletedExecution |
| Needs inverse for `MonthlyPlan.executionRecord` | | Add relationship |

### 7. ExecutionSnapshot

> ⚠️ **Warning:** ExecutionSnapshot uses a memberwise initializer which may obscure that the stored properties still need defaults for CloudKit materialization.

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint, no default on declaration | Remove `@Attribute(.unique)`, add default `UUID()` |
| `var capturedAt: Date` | ⚠️ Non-optional, **NO default on declaration** | Add default `Date()` on declaration |
| `var totalPlanned: Double` | ⚠️ Non-optional, **NO default on declaration** | Add default `0.0` on declaration |
| `var snapshotData: Data` | ⚠️ Non-optional Data blob, **NO default on declaration** | Add default `Data()` on declaration |

### 8. CompletedExecution

> **Note:** This model stores frozen contribution snapshots. Data blobs contain serialized exchange rates and contribution details captured at completion time.

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var monthLabel: String` | Non-optional | Add default `""` |
| `var completedAt: Date` | Non-optional | Add default `Date()` |
| `var exchangeRatesSnapshotData: Data?` | Optional Data blob | Already optional (OK) |
| `var goalSnapshotsData: Data?` | Optional Data blob | Already optional (OK) |
| `var contributionSnapshotsData: Data?` | Optional Data blob | Already optional (OK) |
| Needs inverse for `MonthlyExecutionRecord.completedExecution` | | Add relationship |

### 9. AllocationHistory

| Property | Issue | Fix |
|----------|-------|-----|
| `@Attribute(.unique) var id: UUID` | Unique constraint | Remove `@Attribute(.unique)` |
| `var amount: Double` | Non-optional, set in init only | Add default `0.0` on declaration |
| `var timestamp: Date` | Non-optional, set in init only | Add default `Date()` on declaration |
| `var createdAt: Date` | Non-optional, set in init only | Add default `Date()` on declaration |
| `var monthLabel: String` | Non-optional, set in init only | Add default `""` on declaration |
| `var asset: Asset?` | ⚠️ **Missing `@Relationship`**, no inverse | Add `@Relationship(inverse: \Asset.allocationHistory)` |
| `var goal: Goal?` | ⚠️ **Missing `@Relationship`**, no inverse | Add `@Relationship(inverse: \Goal.allocationHistory)` |

---

## Implementation Plan

### Phase 1: Add Missing `@Relationship` Decorators and Inverse Relationships

**This phase is more extensive than the "Missing inverse relationships" count suggests.** Several models have relationships declared as plain `var` properties without `@Relationship` decorators at all—not just missing inverses.

**Models requiring `@Relationship` decorator additions:**
- `Transaction.asset` — plain `var asset: Asset`, needs `@Relationship` + inverse + make optional
- `AssetAllocation.asset` / `.goal` — plain `var`s, need `@Relationship` + inverse
- `AllocationHistory.asset` / `.goal` — plain `var`s, need `@Relationship` + inverse + new arrays on Asset/Goal

**Models requiring inverse specification on existing `@Relationship`:**
- `CompletedExecution` ↔ `MonthlyExecutionRecord` — CompletedExecution has no inverse for `MonthlyExecutionRecord.completedExecution`
- `MonthlyPlan` ↔ `MonthlyExecutionRecord` — MonthlyPlan.executionRecord has `@Relationship` but no inverse specified

Create bidirectional relationships:

```swift
// Asset.swift - ADD inverse specifications and new allocationHistory array
@Relationship(deleteRule: .cascade, inverse: \Transaction.asset)
var transactions: [Transaction] = []

@Relationship(deleteRule: .cascade, inverse: \AssetAllocation.asset)
var allocations: [AssetAllocation] = []

@Relationship(deleteRule: .nullify, inverse: \AllocationHistory.asset)  // NEW - doesn't exist yet
var allocationHistory: [AllocationHistory] = []

// Goal.swift - ADD inverse specifications and new allocationHistory array
@Relationship(deleteRule: .cascade, inverse: \AssetAllocation.goal)
var allocations: [AssetAllocation] = []

@Relationship(deleteRule: .nullify, inverse: \AllocationHistory.goal)  // NEW - doesn't exist yet
var allocationHistory: [AllocationHistory] = []

// Transaction.swift - CHANGE from plain var to @Relationship, make optional
@Relationship(inverse: \Asset.transactions)
var asset: Asset?  // Was: var asset: Asset (non-optional, no @Relationship)

// AssetAllocation.swift - ADD @Relationship decorators with inverses
@Relationship(inverse: \Asset.allocations) var asset: Asset?   // Was: var asset: Asset? (no @Relationship)
@Relationship(inverse: \Goal.allocations) var goal: Goal?      // Was: var goal: Goal? (no @Relationship)

// AllocationHistory.swift - ADD @Relationship decorators with inverses
@Relationship(inverse: \Asset.allocationHistory) var asset: Asset?  // Was: var asset: Asset? (no @Relationship)
@Relationship(inverse: \Goal.allocationHistory) var goal: Goal?     // Was: var goal: Goal? (no @Relationship)

// MonthlyExecutionRecord.swift - ADD inverse specification
@Relationship(deleteRule: .cascade, inverse: \CompletedExecution.executionRecord)
var completedExecution: CompletedExecution?

@Relationship(inverse: \MonthlyPlan.executionRecord)
var plans: [MonthlyPlan] = []  // NEW - doesn't exist yet

// MonthlyPlan.swift - ADD inverse specification
@Relationship(deleteRule: .nullify, inverse: \MonthlyExecutionRecord.plans)
var executionRecord: MonthlyExecutionRecord?

// CompletedExecution.swift - ADD inverse relationship (currently missing entirely)
@Relationship(inverse: \MonthlyExecutionRecord.completedExecution)
var executionRecord: MonthlyExecutionRecord?
```

> **Critical Note:** This phase will feel more invasive than expected because several "relationships" aren't actually relationships yet—they're plain `var` properties that happen to reference model types. CloudKit requires explicit `@Relationship` decorators with inverses for all model-to-model references.

### Phase 2: Add Default Values to All Properties

> ⚠️ **Reminder:** Defaults must be on the **stored property declarations**, not just set in `init()`. SwiftData/CloudKit doesn't call your initializers when materializing records.

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

// MonthlyPlan.swift - NOTE: statusRawValue and monthLabel currently have NO defaults!
var id: UUID = UUID()
var goalId: UUID = UUID()
var monthLabel: String = ""                                    // ⚠️ MISSING - currently no default
var requiredMonthly: Double = 0.0
var remainingAmount: Double = 0.0
var monthsRemaining: Int = 0
var currency: String = ""
var statusRawValue: String = RequirementStatus.onTrack.rawValue // ⚠️ MISSING - currently no default
var lastCalculated: Date = Date()
var createdDate: Date = Date()
var lastModifiedDate: Date = Date()

// MonthlyExecutionRecord.swift - NOTE: statusRawValue currently has NO default!
var id: UUID = UUID()
var monthLabel: String = ""
var statusRawValue: String = ExecutionStatus.draft.rawValue    // ⚠️ MISSING - currently no default
var createdAt: Date = Date()
var trackedGoalIds: Data = Data()

// ExecutionSnapshot.swift - NOTE: ALL stored properties lack defaults despite memberwise init!
var id: UUID = UUID()                   // ⚠️ MISSING - currently no default
var capturedAt: Date = Date()           // ⚠️ MISSING - currently no default
var totalPlanned: Double = 0.0          // ⚠️ MISSING - currently no default
var snapshotData: Data = Data()         // ⚠️ MISSING - currently no default

// CompletedExecution.swift
var id: UUID = UUID()
var monthLabel: String = ""
var completedAt: Date = Date()
var exchangeRatesSnapshotData: Data? = nil  // Already optional
var goalSnapshotsData: Data? = nil          // Already optional
var contributionSnapshotsData: Data? = nil  // Already optional

// AllocationHistory.swift - NOTE: createdAt was missing from previous list!
var id: UUID = UUID()
var amount: Double = 0.0
var timestamp: Date = Date()
var createdAt: Date = Date()            // ⚠️ MISSING - currently no default (was omitted from previous list)
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

CloudKit doesn't support custom enums directly. Store as raw String values. The codebase already follows this pattern:

```swift
// MonthlyPlan.swift - Uses RequirementStatus (defined in MonthlyRequirement.swift)
var statusRawValue: String = RequirementStatus.onTrack.rawValue

var status: RequirementStatus {
    get { RequirementStatus(rawValue: statusRawValue) ?? .onTrack }
    set { statusRawValue = newValue.rawValue }
}

// MonthlyPlan.swift - Also uses nested PlanState and FlexState enums
var stateRawValue: String = PlanState.draft.rawValue
var flexStateRawValue: String = FlexState.flexible.rawValue

// MonthlyExecutionRecord.swift - Uses nested ExecutionStatus enum
var statusRawValue: String = MonthlyExecutionRecord.ExecutionStatus.draft.rawValue

var status: ExecutionStatus {
    get { ExecutionStatus(rawValue: statusRawValue) ?? .draft }
    set { statusRawValue = newValue.rawValue }
}
```

> **Status:** All enum properties already use this pattern. No changes needed.

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

**Prerequisites before enabling CloudKit:**
1. ⚠️ **Remove wipe-on-failure strategy** - The current `resetStoreFilesIfPresent()` call in `CryptoSavingsTrackerApp.swift:72-80` must be disabled or guarded when CloudKit is enabled. Otherwise, temporary sync failures will wipe local data and cause repeated deletion/reupload cycles. See "Risks and Considerations" section for details.
2. All model changes from Phases 1-5 must be complete
3. Test thoroughly in Development CloudKit container first

After all prerequisites are met:

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

### Model Compatibility
- [ ] All models compile without errors
- [ ] Relationships are bidirectional (all have inverses)
- [ ] No `@Attribute(.unique)` constraints remain
- [ ] All properties have defaults or are optional
- [ ] AllocationHistory has proper `@Relationship` decorators (not plain vars)

### Schema Deployment
- [ ] CloudKit schema deploys successfully to Development container
- [ ] Schema promotes to Production without errors
- [ ] Schema changes propagate to existing installs within acceptable time
- [ ] App handles "schema not yet available" gracefully (no wipe!)

### Authentication & Account Handling
- [ ] App works when user is signed out of iCloud
- [ ] App handles iCloud sign-in during use
- [ ] App handles iCloud sign-out during use (preserves local data)
- [ ] App handles iCloud account switch (different Apple ID)
- [ ] Restricted iCloud accounts work (parental controls, managed devices)

### Sync & Conflict Resolution
- [ ] Fresh install syncs existing CloudKit data correctly
- [ ] Existing local data uploads to CloudKit on first sync
- [ ] Concurrent edits on two devices resolve correctly
- [ ] Offline edits sync when connectivity returns
- [ ] Large batch imports don't timeout or corrupt
- [ ] Deleted records propagate correctly (no orphans)

### Data Integrity Scenarios
- [ ] **Fresh install**: New device gets all CloudKit data
- [ ] **Existing local store + CloudKit enabled**: Local data merges with cloud
- [ ] **Existing local store + CloudKit has data**: Handles potential duplicates
- [ ] **App update with schema changes**: Migration works, no data loss
- [ ] **Downgrade scenario**: Older app version handles newer schema gracefully

### Edge Cases
- [ ] Very large ExecutionSnapshot/CompletedExecution Data blobs sync
- [ ] Relationship cycles don't cause infinite sync loops
- [ ] Rapid successive saves don't cause race conditions
- [ ] App backgrounded during sync resumes correctly

---

## Risks and Considerations

1. **Breaking Change**: Existing local data may not migrate automatically
2. **Conflict Resolution**: CloudKit uses last-write-wins by default
3. **Performance**: CloudKit sync adds latency to saves
4. **Storage Limits**: iCloud has storage quotas
5. **Apple ID Required**: Users must be signed into iCloud
6. **Data Blob Sizes**: `CompletedExecution` and `ExecutionSnapshot` store serialized JSON in Data blobs. CloudKit has ~1MB per-record limit. Current usage is well under this (~1-2KB per goal), but monitor if users track many goals

### ⚠️ CRITICAL: Wipe-on-Failure Strategy Must Be Removed

**Current behavior** (`CryptoSavingsTrackerApp.swift:72-80`):
```swift
// Initial-schema-only strategy: if the store can't be opened due to schema mismatch,
// wipe and recreate. This is acceptable while we have 0 clients.
resetStoreFilesIfPresent()
```

**Why this is dangerous with CloudKit:**
- CloudKit sync can temporarily fail (network issues, iCloud account changes, schema propagation delays)
- With the current strategy, any sync failure would **wipe all local data**
- User could lose months of tracking data that hasn't synced yet
- CloudKit schema changes propagate asynchronously—a new app version might wipe data before the schema arrives

**Required changes before Phase 6:**
1. Remove the automatic wipe-on-failure behavior entirely
2. Implement graceful degradation: if CloudKit unavailable, operate in local-only mode
3. Add explicit user confirmation before any data reset
4. Implement data export before destructive operations
5. Consider a "pending changes" queue for offline edits

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
