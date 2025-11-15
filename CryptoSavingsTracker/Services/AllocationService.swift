//
//  AllocationService.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 25/08/2025.
//

import SwiftData
import Foundation

/// Service responsible for managing asset allocations across goals
/// v2.0 - Now uses fixed amounts instead of percentages
@MainActor
class AllocationService {
    private let modelContext: ModelContext
    private var contributionService: ContributionService?
    private var executionTrackingService: ExecutionTrackingService?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Inject dependencies for execution tracking (v2.1)
    func setExecutionTracking(
        contributionService: ContributionService,
        executionTrackingService: ExecutionTrackingService
    ) {
        self.contributionService = contributionService
        self.executionTrackingService = executionTrackingService
    }

    // MARK: - Allocation Management (v2.0 - Fixed Amounts)

    /// Updates all allocations for a single asset using fixed amounts
    /// - Parameters:
    ///   - asset: The asset to update allocations for
    ///   - newAllocations: Dictionary mapping goals to their fixed amount allocations
    func updateAllocations(for asset: Asset, newAllocations: [Goal: Double]) throws {
        // 1. Validate that the sum of amounts doesn't exceed asset balance
        let totalAmount = newAllocations.values.reduce(0, +)
        guard totalAmount <= asset.currentAmount else {
            throw AllocationError.exceedsTotal(totalAmount, asset.currentAmount)
        }

        // 2. Validate that all amounts are non-negative
        for (_, amount) in newAllocations {
            guard amount >= 0 else {
                throw AllocationError.negativeAmount(amount)
            }
        }

        // 3. Delete all existing allocations for this asset
        for oldAllocation in asset.allocations {
            modelContext.delete(oldAllocation)
        }

        // 4. Create new AssetAllocation objects from the input dictionary
        for (goal, amount) in newAllocations {
            if amount > 0 {
                let newAllocation = AssetAllocation(asset: asset, goal: goal, fixedAmount: amount)
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

    /// Legacy method for backward compatibility
    /// - Parameters:
    ///   - asset: The asset to update allocations for
    ///   - newAllocations: Dictionary mapping goals to their percentage allocations (0.0 to 1.0)
    @available(*, deprecated, message: "Use updateAllocations(for:newAllocations:) with fixed amounts instead")
    func updateAllocationsLegacy(for asset: Asset, newAllocations: [Goal: Double]) throws {
        // 1. Validate that the sum of percentages is <= 1.0
        let totalPercentage = newAllocations.values.reduce(0, +)
        guard totalPercentage <= 1.0 else {
            throw AllocationError.exceedsTotal(totalPercentage, 1.0)
        }

        // 2. Validate that all percentages are non-negative
        for (_, percentage) in newAllocations {
            guard percentage >= 0 else {
                throw AllocationError.negativeAmount(percentage)
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
    
    /// Add or update a single allocation for an asset to a goal using fixed amount
    /// - Parameters:
    ///   - asset: The asset to allocate
    ///   - goal: The goal to allocate to
    ///   - amount: The fixed amount to allocate
    func setAllocation(for asset: Asset, to goal: Goal, amount: Double) throws {
        guard amount >= 0 else {
            throw AllocationError.negativeAmount(amount)
        }

        // Get current allocations excluding the one we're updating
        let currentAllocations = asset.allocations.filter { $0.goal?.id != goal.id }
        let currentTotal = currentAllocations.reduce(0) { $0 + $1.fixedAmount }

        // Check if adding this allocation would exceed asset balance
        guard currentTotal + amount <= asset.currentAmount else {
            throw AllocationError.exceedsTotal(currentTotal + amount, asset.currentAmount)
        }

        // Find existing allocation or create new one
        if let existingAllocation = asset.allocations.first(where: { $0.goal?.id == goal.id }) {
            existingAllocation.updateAmount(amount)
        } else if amount > 0 {
            let newAllocation = AssetAllocation(asset: asset, goal: goal, fixedAmount: amount)
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

    /// Get all allocations for a specific asset, sorted by amount
    func getAllocations(for asset: Asset) -> [AssetAllocation] {
        return asset.allocations.sorted { $0.fixedAmount > $1.fixedAmount }
    }

    /// Get all allocations for a specific goal, sorted by amount
    func getAllocations(for goal: Goal) -> [AssetAllocation] {
        return goal.allocations.sorted { $0.fixedAmount > $1.fixedAmount }
    }

    /// Check if an asset can accommodate a new allocation amount
    /// - Parameters:
    ///   - asset: The asset to check
    ///   - amount: The proposed amount to allocate
    ///   - excludingGoal: Optional goal to exclude from current total calculation (for updates)
    func canAllocate(asset: Asset, amount: Double, excludingGoal: Goal? = nil) -> Bool {
        let currentAllocations = asset.allocations.filter { $0.goal?.id != excludingGoal?.id }
        let currentTotal = currentAllocations.reduce(0) { $0 + $1.fixedAmount }
        return currentTotal + amount <= asset.currentAmount
    }

    /// Get the remaining unallocated balance for an asset
    func getUnallocatedBalance(for asset: Asset) -> Double {
        return asset.unallocatedBalance
    }

    // MARK: - Execution Tracking Integration (v2.1)

    /// Record an allocation as a contribution and link to active execution record
    /// - Parameters:
    ///   - asset: The asset being allocated from
    ///   - goal: The goal receiving the allocation
    ///   - amount: The amount being allocated (in fiat currency)
    ///   - assetAmount: The crypto amount being allocated
    ///   - exchangeRate: Exchange rate at time of allocation
    ///   - exchangeRateProvider: Source of the exchange rate
    /// - Returns: The created contribution, or nil if execution tracking not configured
    @discardableResult
    func recordAllocationAsContribution(
        asset: Asset,
        goal: Goal,
        amount: Double,
        assetAmount: Double,
        exchangeRate: Double,
        exchangeRateProvider: String = "Manual"
    ) throws -> Contribution? {
        guard let contributionService = contributionService else {
            // Execution tracking not configured, skip contribution recording
            return nil
        }

        // Record the deposit contribution
        let contribution = try contributionService.recordDeposit(
            amount: amount,
            assetAmount: assetAmount,
            to: goal,
            from: asset,
            exchangeRate: exchangeRate,
            exchangeRateProvider: exchangeRateProvider,
            notes: "Allocation from \(asset.currency)"
        )

        // Link to active execution record if one exists
        if let executionService = executionTrackingService {
            let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
            if let activeRecord = try executionService.getRecord(for: monthLabel),
               activeRecord.status == .executing {
                try contributionService.linkToExecutionRecord(contribution, recordId: activeRecord.id)
            }
        }

        return contribution
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
    func validateAllocations(_ allocations: [Goal: Double], for asset: Asset) throws {
        let totalAmount = allocations.values.reduce(0, +)
        guard totalAmount <= asset.currentAmount else {
            throw AllocationError.exceedsTotal(totalAmount, asset.currentAmount)
        }

        for (_, amount) in allocations {
            guard amount >= 0 else {
                throw AllocationError.negativeAmount(amount)
            }
        }
    }
}

// MARK: - Error Types

enum AllocationError: Error, LocalizedError {
    case exceedsTotal(Double, Double) // (attempted, available)
    case negativeAmount(Double)
    case assetNotFound
    case goalNotFound

    var errorDescription: String? {
        switch self {
        case .exceedsTotal(let attempted, let available):
            return "Total allocation (\(String(format: "%.4f", attempted))) exceeds available balance (\(String(format: "%.4f", available)))"
        case .negativeAmount(let amount):
            return "Amount cannot be negative (\(String(format: "%.4f", amount)))"
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