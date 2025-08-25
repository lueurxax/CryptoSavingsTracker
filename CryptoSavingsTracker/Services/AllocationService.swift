//
//  AllocationService.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 25/08/2025.
//

import SwiftData
import Foundation

/// Service responsible for managing asset allocations across goals
@MainActor
class AllocationService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Allocation Management
    
    /// Updates all allocations for a single asset
    /// - Parameters:
    ///   - asset: The asset to update allocations for
    ///   - newAllocations: Dictionary mapping goals to their percentage allocations (0.0 to 1.0)
    func updateAllocations(for asset: Asset, newAllocations: [Goal: Double]) throws {
        // 1. Validate that the sum of percentages is <= 1.0
        let totalPercentage = newAllocations.values.reduce(0, +)
        guard totalPercentage <= 1.0 else {
            throw AllocationError.exceedsTotal(totalPercentage)
        }
        
        // 2. Validate that all percentages are non-negative
        for (_, percentage) in newAllocations {
            guard percentage >= 0 else {
                throw AllocationError.negativePercentage(percentage)
            }
        }
        
        // 3. Delete all existing allocations for this asset
        for oldAllocation in asset.allocations {
            modelContext.delete(oldAllocation)
        }
        
        // 4. Create new AssetAllocation objects from the input dictionary
        for (goal, percentage) in newAllocations {
            if percentage > 0 {
                let newAllocation = AssetAllocation(asset: asset, goal: goal, percentage: percentage)
                modelContext.insert(newAllocation)
            }
        }
        
        try modelContext.save()
        
        // 5. Post notification for any listeners
        NotificationCenter.default.post(
            name: .goalUpdated,
            object: nil,
            userInfo: ["assetId": asset.id]
        )
    }
    
    /// Add or update a single allocation for an asset to a goal
    /// - Parameters:
    ///   - asset: The asset to allocate
    ///   - goal: The goal to allocate to
    ///   - percentage: The percentage to allocate (0.0 to 1.0)
    func setAllocation(for asset: Asset, to goal: Goal, percentage: Double) throws {
        guard percentage >= 0 && percentage <= 1.0 else {
            throw AllocationError.invalidPercentage(percentage)
        }
        
        // Get current allocations excluding the one we're updating
        let currentAllocations = asset.allocations.filter { $0.goal?.id != goal.id }
        let currentTotal = currentAllocations.reduce(0) { $0 + $1.percentage }
        
        // Check if adding this allocation would exceed 100%
        guard currentTotal + percentage <= 1.0 else {
            throw AllocationError.exceedsTotal(currentTotal + percentage)
        }
        
        // Find existing allocation or create new one
        if let existingAllocation = asset.allocations.first(where: { $0.goal?.id == goal.id }) {
            existingAllocation.updatePercentage(percentage)
        } else if percentage > 0 {
            let newAllocation = AssetAllocation(asset: asset, goal: goal, percentage: percentage)
            modelContext.insert(newAllocation)
        }
        
        try modelContext.save()
        
        NotificationCenter.default.post(
            name: .goalUpdated,
            object: nil,
            userInfo: ["assetId": asset.id, "goalId": goal.id]
        )
    }
    
    /// Remove an allocation between an asset and a goal
    /// - Parameters:
    ///   - asset: The asset to remove allocation from
    ///   - goal: The goal to remove allocation from
    func removeAllocation(for asset: Asset, from goal: Goal) throws {
        if let allocation = asset.allocations.first(where: { $0.goal?.id == goal.id }) {
            modelContext.delete(allocation)
            try modelContext.save()
            
            NotificationCenter.default.post(
                name: .goalUpdated,
                object: nil,
                userInfo: ["assetId": asset.id, "goalId": goal.id, "removed": true]
            )
        }
    }
    
    // MARK: - Allocation Queries
    
    /// Get all allocations for a specific asset
    func getAllocations(for asset: Asset) -> [AssetAllocation] {
        return asset.allocations.sorted { $0.percentage > $1.percentage }
    }
    
    /// Get all allocations for a specific goal
    func getAllocations(for goal: Goal) -> [AssetAllocation] {
        return goal.allocations.sorted { $0.percentage > $1.percentage }
    }
    
    /// Check if an asset can accommodate a new allocation percentage
    /// - Parameters:
    ///   - asset: The asset to check
    ///   - percentage: The proposed percentage to allocate
    ///   - excludingGoal: Optional goal to exclude from current total calculation (for updates)
    func canAllocate(asset: Asset, percentage: Double, excludingGoal: Goal? = nil) -> Bool {
        let currentAllocations = asset.allocations.filter { $0.goal?.id != excludingGoal?.id }
        let currentTotal = currentAllocations.reduce(0) { $0 + $1.percentage }
        return currentTotal + percentage <= 1.0
    }
    
    /// Get the remaining unallocated percentage for an asset
    func getUnallocatedPercentage(for asset: Asset) -> Double {
        return max(0, 1.0 - asset.totalAllocatedPercentage)
    }
    
    // MARK: - Bulk Operations
    
    /// Remove all allocations for an asset (useful when deleting an asset)
    func removeAllAllocations(for asset: Asset) throws {
        for allocation in asset.allocations {
            modelContext.delete(allocation)
        }
        try modelContext.save()
    }
    
    /// Remove all allocations for a goal (useful when deleting a goal)
    func removeAllAllocations(for goal: Goal) throws {
        for allocation in goal.allocations {
            modelContext.delete(allocation)
        }
        try modelContext.save()
    }
    
    // MARK: - Validation Helpers
    
    /// Validate a complete set of allocations for an asset
    func validateAllocations(_ allocations: [Goal: Double]) throws {
        let totalPercentage = allocations.values.reduce(0, +)
        guard totalPercentage <= 1.0 else {
            throw AllocationError.exceedsTotal(totalPercentage)
        }
        
        for (_, percentage) in allocations {
            guard percentage >= 0 && percentage <= 1.0 else {
                throw AllocationError.invalidPercentage(percentage)
            }
        }
    }
}

// MARK: - Error Types

enum AllocationError: Error, LocalizedError {
    case exceedsTotal(Double)
    case negativePercentage(Double)
    case invalidPercentage(Double)
    case assetNotFound
    case goalNotFound
    
    var errorDescription: String? {
        switch self {
        case .exceedsTotal(let percentage):
            return "Total allocation percentage (\(String(format: "%.1f%%", percentage * 100))) exceeds 100%"
        case .negativePercentage(let percentage):
            return "Percentage cannot be negative (\(String(format: "%.1f%%", percentage * 100)))"
        case .invalidPercentage(let percentage):
            return "Invalid percentage (\(String(format: "%.1f%%", percentage * 100))). Must be between 0% and 100%"
        case .assetNotFound:
            return "Asset not found"
        case .goalNotFound:
            return "Goal not found"
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let allocationUpdated = Notification.Name("allocationUpdated")
}