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
struct AllocationService {
    private let modelContext: ModelContext
    private static let isTestRun: Bool = {
        let args = ProcessInfo.processInfo.arguments
        // XCTest environment vars differ across platforms/runner versions; use multiple signals.
        let env = ProcessInfo.processInfo.environment
        let isXCTestRun = env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil
        let isXCTestLoaded = NSClassFromString("XCTestCase") != nil
        let isUITestRun = args.contains(where: { $0.hasPrefix("UITEST") })
        return isXCTestRun || isXCTestLoaded || isUITestRun
    }()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Allocation Management (v2.0 - Fixed Amounts)

    /// Updates all allocations for a single asset using fixed amounts
    /// - Parameters:
    ///   - asset: The asset to update allocations for
    ///   - newAllocations: List of goals and their fixed amount allocations
    @MainActor
    func updateAllocations(for asset: Asset, newAllocations: [(goal: Goal, amount: Double)]) throws {
        try validateAllocations(newAllocations, for: asset)

        let timestamp = Date()
        let epsilon = 0.0000001

        // Snapshot old amounts before mutations.
        let existingAllocations = Array(asset.allocations)
        var existingByGoalId: [UUID: AssetAllocation] = [:]
        existingByGoalId.reserveCapacity(existingAllocations.count)

        var oldByGoalId: [UUID: (goal: Goal, amount: Double)] = [:]
        oldByGoalId.reserveCapacity(existingAllocations.count)

        for allocation in existingAllocations {
            guard let goal = allocation.goal else { continue }
            existingByGoalId[goal.id] = allocation
            oldByGoalId[goal.id] = (goal, allocation.amountValue)
        }

        // Normalize incoming allocations by goal id.
        var newByGoalId: [UUID: (goal: Goal, amount: Double)] = [:]
        newByGoalId.reserveCapacity(newAllocations.count)
        for entry in newAllocations {
            newByGoalId[entry.goal.id] = (entry.goal, max(0, entry.amount))
        }

        // Apply updates/inserts.
        for (goalId, entry) in newByGoalId {
            let newAmount = entry.amount
            if let existing = existingByGoalId[goalId] {
                existing.updateAmount(newAmount)
            } else if newAmount > epsilon {
                let newAllocation = AssetAllocation(asset: asset, goal: entry.goal, amount: newAmount)
                modelContext.insert(newAllocation)
            }
        }

        // Apply deletions for removed/zeroed goals.
        for (goalId, existing) in existingByGoalId {
            let newAmount = newByGoalId[goalId]?.amount ?? 0
            if newAmount <= epsilon {
                modelContext.delete(existing)
            }
        }

        // Record AllocationHistory for changed goal allocations (amount-only).
        let unionGoalIds = Set(oldByGoalId.keys).union(newByGoalId.keys)
        for goalId in unionGoalIds {
            let oldAmount = oldByGoalId[goalId]?.amount ?? 0
            let newEntry = newByGoalId[goalId]
            let newAmount = newEntry?.amount ?? 0
            guard abs(oldAmount - newAmount) > epsilon else { continue }
            if let goal = newEntry?.goal ?? oldByGoalId[goalId]?.goal {
                modelContext.insert(AllocationHistory(asset: asset, goal: goal, amount: newAmount, timestamp: timestamp))
            }
        }

        try modelContext.save()

        let goalIds = Array(newByGoalId.keys)
        NotificationCenter.default.post(
            name: .goalUpdated,
            object: nil,
            userInfo: [
                "assetId": asset.id,
                "goalIds": goalIds
            ]
        )
        NotificationCenter.default.post(
            name: .monthlyPlanningAssetUpdated,
            object: asset,
            userInfo: [
                "assetId": asset.id,
                "goalIds": goalIds
            ]
        )

        if !Self.isTestRun {
            let goals = newAllocations.map(\.goal)
            Task { @MainActor in
                await syncMonthlyPlans(for: goals)
            }
        }
    }

    /// Add or update a single allocation for an asset to a goal using fixed amount
    /// - Parameters:
    ///   - asset: The asset to allocate
    ///   - goal: The goal to allocate to
    ///   - amount: The fixed amount to allocate
    @MainActor
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

        if !Self.isTestRun {
            Task { @MainActor in
                await syncMonthlyPlans(for: [goal])
            }
        }
    }
    
    /// Remove an allocation between an asset and a goal
    /// - Parameters:
    ///   - asset: The asset to remove allocation from
    ///   - goal: The goal to remove allocation from
    @MainActor
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

            if !Self.isTestRun {
                Task { @MainActor in
                    await syncMonthlyPlans(for: [goal])
                }
            }
        }
    }
    
    // MARK: - Allocation Queries

    /// Get all allocations for a specific asset, sorted by amount
    @MainActor
    func getAllocations(for asset: Asset) -> [AssetAllocation] {
        return asset.allocations.sorted { $0.amountValue > $1.amountValue }
    }

    /// Get all allocations for a specific goal, sorted by amount
    @MainActor
    func getAllocations(for goal: Goal) -> [AssetAllocation] {
        return goal.allocations.sorted { $0.amountValue > $1.amountValue }
    }

    /// Check if an asset can accommodate a new allocation amount
    @MainActor
    func canAllocate(asset: Asset, amount: Double, excludingGoal: Goal? = nil) -> Bool {
        let currentAllocations = asset.allocations.filter { $0.goal?.id != excludingGoal?.id }
        let currentTotal = currentAllocations.reduce(0.0) { partial, allocation in
            partial + allocation.amountValue
        }
        return currentTotal + amount <= asset.currentAmount
    }

    /// Get the remaining unallocated amount for an asset
    @MainActor
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
    @MainActor
    func removeAllAllocations(for asset: Asset) throws {
        let existingAllocations = asset.allocations
        for allocation in existingAllocations {
            modelContext.delete(allocation)
        }
        try modelContext.save()
    }
    
    /// Remove all allocations for a goal (useful when deleting a goal)
    @MainActor
    func removeAllAllocations(for goal: Goal) throws {
        let existingAllocations = goal.allocations
        for allocation in existingAllocations {
            modelContext.delete(allocation)
        }
        try modelContext.save()
    }
    
    // MARK: - Validation Helpers

    /// Validate a complete set of allocations for an asset
    @MainActor
    func validateAllocations(_ allocations: [(goal: Goal, amount: Double)], for asset: Asset) throws {
        let totalAmount = allocations.map(\.amount).reduce(0, +)
        guard totalAmount <= asset.currentAmount else {
            throw AllocationError.exceedsTotal(totalAmount, asset.currentAmount)
        }

        for entry in allocations {
            guard entry.amount >= 0 else {
                throw AllocationError.negativeAmount(entry.amount)
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
