//
//  GoalLifecycleService.swift
//  CryptoSavingsTracker
//
//  Implements cancel/finish/delete semantics described in docs/CONTRIBUTION_TRACKING_REDESIGN.md.
//

import Foundation
import SwiftData

@MainActor
struct GoalLifecycleService {
    private let modelContext: ModelContext
    private let allocationService: AllocationService
    private let executionService: ExecutionTrackingService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.allocationService = AllocationService(modelContext: modelContext)
        self.executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
    }

    /// Cancel a goal: allocations become unallocated/reusable, goal is excluded from current execution tracking.
    func cancelGoal(_ goal: Goal, at timestamp: Date = Date()) async {
        await NotificationManager.shared.cancelNotifications(for: goal)
        freeAllocations(for: goal)

        goal.markCancelled(at: timestamp)
        removeGoalFromActiveExecution(goalId: goal.id)
        try? modelContext.save()

        NotificationCenter.default.post(name: .goalDeleted, object: goal)
        NotificationCenter.default.post(name: .goalUpdated, object: goal, userInfo: ["goalId": goal.id])
    }

    /// Finish a goal: goal is preserved for history and excluded from current execution tracking.
    /// Allocations remain, so funds are treated as "spent"/not reusable.
    func finishGoal(_ goal: Goal, at timestamp: Date = Date()) async {
        await NotificationManager.shared.cancelNotifications(for: goal)

        goal.markFinished(at: timestamp)
        removeGoalFromActiveExecution(goalId: goal.id)
        try? modelContext.save()

        NotificationCenter.default.post(name: .goalDeleted, object: goal)
        NotificationCenter.default.post(name: .goalUpdated, object: goal, userInfo: ["goalId": goal.id])
    }

    /// Delete a goal (soft delete): remove it from current tracking and free its allocations so funds are not locked.
    func deleteGoal(_ goal: Goal, at timestamp: Date = Date()) async {
        await NotificationManager.shared.cancelNotifications(for: goal)
        freeAllocations(for: goal)

        goal.softDelete(at: timestamp)
        removeGoalFromActiveExecution(goalId: goal.id)
        try? modelContext.save()

        NotificationCenter.default.post(name: .goalDeleted, object: goal)
        NotificationCenter.default.post(name: .goalUpdated, object: goal, userInfo: ["goalId": goal.id])
    }

    private func freeAllocations(for goal: Goal) {
        // Snapshot assets before we mutate allocations via AllocationService.
        var assetsById: [UUID: Asset] = [:]
        for allocation in goal.allocations {
            if let asset = allocation.asset {
                assetsById[asset.id] = asset
            }
        }

        for asset in assetsById.values {
            let newAllocations: [(goal: Goal, amount: Double)] = asset.allocations.compactMap { allocation in
                guard let otherGoal = allocation.goal, otherGoal.id != goal.id else { return nil }
                return (goal: otherGoal, amount: allocation.amountValue)
            }
            // Best-effort: if an asset is in an over-allocated state, still allow freeing this goal by removing it.
            // AllocationService.validateAllocations only checks sum <= balance; removing a goal always moves toward validity.
            try? allocationService.updateAllocations(for: asset, newAllocations: newAllocations)
        }
    }

    private func removeGoalFromActiveExecution(goalId: UUID) {
        guard let record = try? executionService.getActiveRecord() else { return }
        guard record.goalIds.contains(goalId) else { return }

        let updatedIds = record.goalIds.filter { $0 != goalId }
        if let encoded = try? JSONEncoder().encode(updatedIds) {
            record.trackedGoalIds = encoded
            try? modelContext.save()
        }
    }
}

