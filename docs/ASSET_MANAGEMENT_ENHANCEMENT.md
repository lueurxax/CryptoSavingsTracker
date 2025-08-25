# Asset Splitting & Flexible Allocations Plan

## 1. Overview

This document outlines a plan to refactor the app's core asset management logic. The new approach, "Asset Splitting," will allow users to allocate a single asset across multiple savings goals by percentage. This provides maximum flexibility and eliminates the need for costly on-chain transactions to re-balance a portfolio.

### 1.1. Problem Statement

Users often have large, primary holdings (e.g., a single Bitcoin wallet) that they want to mentally earmark for multiple purposes. The current model, where an asset can only belong to one goal, is too rigid. It doesn't reflect how users think about their overall portfolio in relation to their various financial goals.

### 1.2. The Solution: Asset Splitting

Users will be able to take any tracked asset and allocate its value by percentage across any number of goals. For example, a single 1.0 BTC asset can be allocated as:

*   50% towards "House Down Payment"
*   30% towards "Emergency Fund"
*   20% towards "Vacation Fund"

Adjusting goal priorities becomes a simple matter of changing these percentage allocations, with no real-world transactions required.

---

## 2. User Stories

*   "As a user with a single large BTC holding, I want to allocate 50% of its value to my House goal and 50% to my Retirement goal so I can track my progress for both simultaneously."
*   "As a user, I want to easily adjust the allocation of my ETH from 70% on my 'Emergency Fund' to 60%, freeing up 10% of its value to contribute to a new 'Gadgets' goal."
*   "As a user, when I add a new asset, I want to decide how its value is spread across my existing goals."

---

## 3. UI/UX Vision

### 3.1. Allocation Management Screen

A dedicated screen will be required to manage the allocations for a single asset. This screen would be accessed from an asset's detail view.

**Key Elements:**

*   A header showing the asset's total value (e.g., "1.0 BTC ≈ $70,000").
*   A list of all goals.
*   A slider or text input next to each goal to define its percentage.
*   A visual indicator (e.g., a pie chart) showing the current allocation breakdown.
*   Validation to ensure the total allocation does not exceed 100%.

### 3.2. Goal and Asset Views

*   **Goal Detail View:** Will now show a list of assets and the percentage of each that is contributing to this goal.
*   **Asset Detail View:** Will show a summary of how the asset is currently allocated across different goals.

---

## 4. Technical Implementation Plan

This feature requires a significant refactoring of the core data model and services.

### 4.1. Data Model Refactoring (High-Risk)

The fundamental change is to introduce a new entity, `AssetAllocation`, to act as a join table between `Asset` and `Goal`.

**1. New Model: `AssetAllocation`**

A new SwiftData model is required.

**File to Create:** `CryptoSavingsTracker/Models/AssetAllocation.swift`
```swift
import SwiftData

@Model
final class AssetAllocation {
    @Attribute(.unique) var id: UUID
    var percentage: Double // Stored as 0.0 to 1.0

    // Relationships
    var asset: Asset?
    var goal: Goal?

    init(asset: Asset, goal: Goal, percentage: Double) {
        self.id = UUID()
        self.asset = asset
        self.goal = goal
        self.percentage = percentage
    }
}
```

**2. Modify `Asset` and `Goal` Models**

The direct relationship between `Asset` and `Goal` must be removed and replaced with a relationship to the new `AssetAllocation` model.

**File to Modify:** `CryptoSavingsTracker/Models/Asset.swift`
```swift
// Remove the `goal: Goal?` property.
// Add the new relationship to allocations.
@Relationship(deleteRule: .cascade, inverse: \AssetAllocation.asset)
var allocations: [AssetAllocation] = []
```

**File to Modify:** `CryptoSavingsTracker/Models/Goal.swift`
```swift
// Remove the direct relationship to assets.
// Add the new relationship to allocations.
@Relationship(deleteRule: .cascade, inverse: \AssetAllocation.goal)
var allocations: [AssetAllocation] = []
```

**3. Data Migration Plan (CRITICAL)**

A migration plan is essential for existing users. When the app is updated, a migration function must:
1.  Iterate through all existing `Asset`s.
2.  For each asset that has a `goal` assigned to it, create a new `AssetAllocation` instance.
3.  This new allocation will link the asset and its former goal with a `percentage` of `1.0` (100%).
4.  This ensures that existing data is preserved in the new structure.

### 4.2. Service Layer Refactoring

**1. `GoalCalculationService`**

This service needs to be rewritten. The `getProgress(for:)` method will no longer iterate through `goal.assets`. Instead, it will iterate through `goal.allocations`.

```swift
// Simplified logic for GoalCalculationService
func getProgress(for goal: Goal) async -> Double {
    var currentGoalValue = 0.0
    for allocation in goal.allocations {
        if let asset = allocation.asset {
            // Fetch asset's total value (with currency conversion)
            let assetTotalValue = await fetchAssetValueInGoalCurrency(asset, goal.currency)
            currentGoalValue += assetTotalValue * allocation.percentage
        }
    }
    // return progress based on currentGoalValue and goal.targetAmount
}
```

**2. New `AllocationService`**

A new service is needed to handle the business logic of creating and updating allocations, ensuring that the total percentage for any given asset does not exceed 100%.

**File to Create:** `CryptoSavingsTracker/Services/AllocationService.swift`
```swift
import SwiftData

@MainActor
class AllocationService {
    private let modelContext: ModelContext

    // ... init ...

    /// Updates all allocations for a single asset.
    /// - Parameter allocations: A dictionary where the key is the Goal and the value is the percentage (0.0 to 1.0).
    func updateAllocations(for asset: Asset, newAllocations: [Goal: Double]) throws {
        // 1. Validate that the sum of percentages is <= 1.0.
        let totalPercentage = newAllocations.values.reduce(0, +)
        guard totalPercentage <= 1.0 else { throw AllocationError.exceedsTotal }

        // 2. Delete all existing allocations for this asset.
        for oldAllocation in asset.allocations {
            modelContext.delete(oldAllocation)
        }

        // 3. Create new AssetAllocation objects from the input dictionary.
        for (goal, percentage) in newAllocations {
            if percentage > 0 {
                let newAllocation = AssetAllocation(asset: asset, goal: goal, percentage: percentage)
                modelContext.insert(newAllocation)
            }
        }

        try modelContext.save()
        NotificationCenter.default.post(name: .goalUpdated, object: nil)
    }
}

enum AllocationError: Error {
    case exceedsTotal
}
```

### 4.3. Impact on User Flows

*   **Add Asset Flow:** When a user adds a new asset, they will no longer assign it to a single goal. Instead, after creating the asset, they should be taken to the allocation management screen to decide how its value should be distributed.

---

## 5. Implementation Phases

### Phase 1: Data Model & Migration (2-3 weeks - High Risk)
1.  Implement the `AssetAllocation` model.
2.  Refactor the `Asset` and `Goal` models.
3.  **Crucially, build and test the data migration logic for existing users.**

### Phase 2: Service Layer Refactoring (2 weeks)
1.  Rewrite the `GoalCalculationService` to use the new allocation structure.
2.  Build and test the new `AllocationService`.

### Phase 3: UI/UX Implementation (2-3 weeks)
1.  Build the allocation management screen (sliders, validation, etc.).
2.  Update the Goal and Asset detail views to display allocation information.
3.  Redesign the "Add Asset" flow.

### Phase 4: Testing and Release (1 week)
1.  Perform end-to-end testing.
2.  Test the migration on various data sets.
3.  Prepare for release.

---

## 6. Conclusion

The "Asset Splitting" model offers a powerful and flexible user experience that aligns with modern portfolio management. While it represents a significant technical undertaking, particularly the data model refactoring and migration, the resulting feature will be a strong differentiator for the app and a major benefit for users.