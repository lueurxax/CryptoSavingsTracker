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

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Allocation Management (v2.0 - Fixed Amounts)

    /// Updates all allocations for a single asset using fixed amounts
    /// - Parameters:
    ///   - asset: The asset to update allocations for
    ///   - newAllocations: Dictionary mapping goals to their fixed amount allocations
    func updateAllocations(for asset: Asset, newAllocations: [Goal: Double]) throws {
        try validateAllocations(newAllocations, for: asset)

        let timestamp = Date()
        let epsilon = 0.0000001

        // Snapshot old amounts before mutations.
        var oldByGoalId: [UUID: (goal: Goal, amount: Double)] = [:]
        for allocation in asset.allocations {
            if let goal = allocation.goal {
                oldByGoalId[goal.id] = (goal, allocation.amountValue)
            }
        }

        // Delete old allocations
        for oldAllocation in asset.allocations {
            modelContext.delete(oldAllocation)
        }

        // Insert new ones
        for (goal, amount) in newAllocations where amount > 0 {
            let newAllocation = AssetAllocation(asset: asset, goal: goal, amount: amount)
            modelContext.insert(newAllocation)
        }

        // Record AllocationHistory for changed goal allocations (amount-only).
        let newGoalIds = Set(newAllocations.keys.map(\.id))
        for goal in newAllocations.keys {
            let oldAmount = oldByGoalId[goal.id]?.amount ?? 0
            let newAmount = max(0, newAllocations[goal] ?? 0)
            guard abs(oldAmount - newAmount) > epsilon else { continue }
            modelContext.insert(AllocationHistory(asset: asset, goal: goal, amount: newAmount, timestamp: timestamp))
        }
        // Record removals (goals removed from allocations -> amount 0).
        for (oldGoalId, old) in oldByGoalId where !newGoalIds.contains(oldGoalId) && old.amount > epsilon {
            modelContext.insert(AllocationHistory(asset: asset, goal: old.goal, amount: 0, timestamp: timestamp))
        }

        try modelContext.save()

        NotificationCenter.default.post(
            name: .goalUpdated,
            object: nil,
            userInfo: [
                "assetId": asset.id,
                "goalIds": Array(newAllocations.keys.map { $0.id })
            ]
        )
        NotificationCenter.default.post(
            name: .monthlyPlanningAssetUpdated,
            object: asset,
            userInfo: [
                "assetId": asset.id,
                "goalIds": Array(newAllocations.keys.map { $0.id })
            ]
        )

        Task { [weak self] in
            await self?.syncMonthlyPlans(for: Array(newAllocations.keys))
        }
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

        // Calculate new total with updated allocation
        let currentAllocations = asset.allocations.filter { $0.goal?.id != goal.id }
        let currentTotal = currentAllocations.reduce(0.0) { partial, allocation in
            partial + allocation.amountValue
        }

        guard currentTotal + amount <= asset.currentAmount else {
            throw AllocationError.exceedsTotal(currentTotal + amount, asset.currentAmount)
        }

        if let existingAllocation = asset.allocations.first(where: { $0.goal?.id == goal.id }) {
            existingAllocation.updateAmount(amount)
        } else if amount > 0 {
            let newAllocation = AssetAllocation(asset: asset, goal: goal, amount: amount)
            modelContext.insert(newAllocation)
        }

        try modelContext.save()

        NotificationCenter.default.post(
            name: .goalUpdated,
            object: nil,
            userInfo: ["assetId": asset.id, "goalId": goal.id]
        )
        NotificationCenter.default.post(
            name: .monthlyPlanningAssetUpdated,
            object: asset,
            userInfo: [
                "assetId": asset.id,
                "goalId": goal.id,
                "goalIds": [goal.id]
            ]
        )

        Task { [weak self] in
            await self?.syncMonthlyPlans(for: [goal])
        }
    }
    
    /// Remove an allocation between an asset and a goal
    /// - Parameters:
    ///   - asset: The asset to remove allocation from
    ///   - goal: The goal to remove allocation from
    func removeAllocation(for asset: Asset, from goal: Goal) throws {
        if let allocation = asset.allocations.first(where: { $0.goal?.id == goal.id }) {
            let oldAmount = allocation.amountValue
            let timestamp = Date()
            modelContext.delete(allocation)
            if oldAmount > 0.0000001 {
                modelContext.insert(AllocationHistory(asset: asset, goal: goal, amount: 0, timestamp: timestamp))
            }
            try modelContext.save()
            
            NotificationCenter.default.post(
                name: .goalUpdated,
                object: nil,
                userInfo: ["assetId": asset.id, "goalId": goal.id, "removed": true]
            )
            NotificationCenter.default.post(
                name: .monthlyPlanningAssetUpdated,
                object: asset,
                userInfo: [
                    "assetId": asset.id,
                    "goalId": goal.id,
                    "goalIds": [goal.id],
                    "removed": true
                ]
            )

            Task { [weak self] in
                await self?.syncMonthlyPlans(for: [goal])
            }
        }
    }
    
    // MARK: - Allocation Queries

    /// Get all allocations for a specific asset, sorted by amount
    func getAllocations(for asset: Asset) -> [AssetAllocation] {
        return asset.allocations.sorted { $0.amountValue > $1.amountValue }
    }

    /// Get all allocations for a specific goal, sorted by amount
    func getAllocations(for goal: Goal) -> [AssetAllocation] {
        return goal.allocations.sorted { $0.amountValue > $1.amountValue }
    }

    /// Check if an asset can accommodate a new allocation amount
    func canAllocate(asset: Asset, amount: Double, excludingGoal: Goal? = nil) -> Bool {
        let currentAllocations = asset.allocations.filter { $0.goal?.id != excludingGoal?.id }
        let currentTotal = currentAllocations.reduce(0.0) { partial, allocation in
            partial + allocation.amountValue
        }
        return currentTotal + amount <= asset.currentAmount
    }

    /// Get the remaining unallocated amount for an asset
    func getUnallocatedAmount(for asset: Asset) -> Double {
        return asset.unallocatedAmount
    }

    /// Recalculate monthly plans for affected goals so execution tracking stays in sync even when the planning view model is not active.
    @MainActor
    private func syncMonthlyPlans(for goals: [Goal]) async {
        guard !goals.isEmpty else { return }

        let planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
        do {
            // Ensure plans exist for the current month
            let plans = try await planService.getOrCreatePlansForCurrentMonth(goals: goals)
            for plan in plans {
                guard let goal = goals.first(where: { $0.id == plan.goalId }) else { continue }
                try await planService.updatePlan(plan, withGoal: goal)
            }
            NotificationCenter.default.post(
                name: .monthlyPlanningGoalUpdated,
                object: nil,
                userInfo: ["goalIds": goals.map { $0.id }]
            )
        } catch {
            AppLog.error("Failed to sync monthly plans after allocation change: \(error)", category: .monthlyPlanning)
        }
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
