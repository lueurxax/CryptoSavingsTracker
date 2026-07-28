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
    private let notificationManager: NotificationManager
    private let saveChanges: () throws -> Void

    init(
        modelContext: ModelContext,
        notificationManager: NotificationManager? = nil,
        saveChanges: (() throws -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.allocationService = AllocationService(modelContext: modelContext)
        self.notificationManager = notificationManager ?? .shared
        self.saveChanges = saveChanges ?? {
            try modelContext.save()
        }
    }

    /// Cancel a goal: allocations become unallocated/reusable, goal is excluded from current execution tracking.
    func cancelGoal(_ goal: Goal, at timestamp: Date = Date()) async throws {
        try persistLifecycleMutation(for: goal, removesAllocations: true) {
            goal.markCancelled(at: timestamp)
        }

        await notificationManager.cancelNotifications(for: goal)
        postLifecycleNotifications(for: goal)
    }

    /// Finish a goal: goal is preserved for history and excluded from current execution tracking.
    /// Allocations remain, so funds are treated as "spent"/not reusable.
    func finishGoal(_ goal: Goal, at timestamp: Date = Date()) async throws {
        try persistLifecycleMutation(for: goal, removesAllocations: false) {
            goal.markFinished(at: timestamp)
        }

        await notificationManager.cancelNotifications(for: goal)
        postLifecycleNotifications(for: goal)
    }

    /// Delete a goal (soft delete): remove it from current tracking and free its allocations so funds are not locked.
    func deleteGoal(_ goal: Goal, at timestamp: Date = Date()) async throws {
        try persistLifecycleMutation(for: goal, removesAllocations: true) {
            goal.softDelete(at: timestamp)
        }

        await notificationManager.cancelNotifications(for: goal)
        postLifecycleNotifications(for: goal)
    }

    private func persistLifecycleMutation(
        for goal: Goal,
        removesAllocations: Bool,
        mutation: () -> Void
    ) throws {
        let allocations = removesAllocations ? Array(goal.allocations ?? []) : []
        let goalID = goal.id
        let executingPlans = try modelContext
            .fetch(FetchDescriptor<MonthlyPlan>())
            .filter {
                $0.goalId == goalID && $0.state == .executing
            }
        var executionRecordsByID: [UUID: MonthlyExecutionRecord] = [:]
        for record in executingPlans.compactMap(\.executionRecord) {
            executionRecordsByID[record.id] = record
        }
        for record in try modelContext
            .fetch(FetchDescriptor<MonthlyExecutionRecord>())
        where record.status == .executing
                && record.goalIds.contains(goalID) {
            executionRecordsByID[record.id] = record
        }
        let executionRecords = Array(executionRecordsByID.values)
        var ownedModels: [any PersistentModel] = [goal]
        ownedModels.append(
            contentsOf: allocations.map { $0 as any PersistentModel }
        )
        ownedModels.append(
            contentsOf: allocations.compactMap(\.asset).map { $0 as any PersistentModel }
        )
        ownedModels.append(
            contentsOf: executingPlans.map { $0 as any PersistentModel }
        )
        ownedModels.append(
            contentsOf: executionRecords.map {
                $0 as any PersistentModel
            }
        )
        try PersistenceOperationTransaction.assertNoUnrelatedPendingChanges(
            in: modelContext,
            allowing: ownedModels
        )

        let goalSnapshot = GoalLifecycleMutationSnapshot(goal: goal)
        let allocationSnapshot = GoalAllocationRelationshipSnapshot(goal: goal)
        let executionSnapshot = GoalExecutionMembershipSnapshot(
            records: executionRecords,
            plans: executingPlans
        )

        do {
            clearReminderState(for: goal)
            if removesAllocations {
                allocationService.stageRemovalOfAllAllocations(for: goal)
            }

            mutation()
            try stageRemovalFromActiveExecution(
                goalId: goalID,
                records: executionRecords,
                plans: executingPlans
            )
            try saveChanges()
        } catch {
            goalSnapshot.restore(goal)
            if removesAllocations {
                allocationSnapshot.restoreDeletedAllocations(for: goal, in: modelContext)
            }
            executionSnapshot.restore()
            throw error
        }
    }

    private func stageRemovalFromActiveExecution(
        goalId: UUID,
        records: [MonthlyExecutionRecord],
        plans: [MonthlyPlan]
    ) throws {
        for plan in plans {
            plan.state = .draft
            plan.executionRecord = nil
        }

        for record in records {
            record.plans = (record.plans ?? []).filter {
                $0.goalId != goalId
            }
            guard record.status == .executing else { continue }

            let updatedIds = record.goalIds.filter { $0 != goalId }
            record.trackedGoalIds = try JSONEncoder().encode(updatedIds)
            if updatedIds.isEmpty {
                // With no tracked goals there is no active execution left.
                // Keep the reusable draft record, matching manual undo-start
                // semantics, and let a future start replace its snapshot.
                record.status = .draft
                record.startedAt = nil
                record.completedAt = nil
                record.canUndoUntil = nil
                record.plans = []
            }
        }
    }

    private func postLifecycleNotifications(for goal: Goal) {
        NotificationCenter.default.post(name: .goalDeleted, object: goal)
        NotificationCenter.default.post(name: .goalUpdated, object: goal, userInfo: ["goalId": goal.id])
        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": [goal.id],
                "reason": "goalMutation"
            ]
        )
    }

    private func clearReminderState(for goal: Goal) {
        goal.clearRetiredReminderState()
    }
}

private struct GoalExecutionMembershipSnapshot {
    private struct RecordState {
        let record: MonthlyExecutionRecord
        let statusRawValue: String
        let startedAt: Date?
        let completedAt: Date?
        let canUndoUntil: Date?
        let trackedGoalIds: Data
        let plans: [MonthlyPlan]?
    }

    private struct PlanState {
        let plan: MonthlyPlan
        let stateRawValue: String
        let lastModifiedDate: Date
        let executionRecord: MonthlyExecutionRecord?
    }

    private let recordStates: [RecordState]
    private let planStates: [PlanState]

    init(
        records: [MonthlyExecutionRecord],
        plans: [MonthlyPlan]
    ) {
        recordStates = records.map {
            RecordState(
                record: $0,
                statusRawValue: $0.statusRawValue,
                startedAt: $0.startedAt,
                completedAt: $0.completedAt,
                canUndoUntil: $0.canUndoUntil,
                trackedGoalIds: $0.trackedGoalIds,
                plans: $0.plans
            )
        }
        planStates = plans.map {
            PlanState(
                plan: $0,
                stateRawValue: $0.stateRawValue,
                lastModifiedDate: $0.lastModifiedDate,
                executionRecord: $0.executionRecord
            )
        }
    }

    func restore() {
        for state in recordStates {
            state.record.statusRawValue = state.statusRawValue
            state.record.startedAt = state.startedAt
            state.record.completedAt = state.completedAt
            state.record.canUndoUntil = state.canUndoUntil
            state.record.trackedGoalIds = state.trackedGoalIds
            state.record.plans = state.plans
        }
        for state in planStates {
            state.plan.stateRawValue = state.stateRawValue
            state.plan.lastModifiedDate = state.lastModifiedDate
            state.plan.executionRecord = state.executionRecord
        }
    }
}

private struct GoalLifecycleMutationSnapshot {
    private let lifecycleStatusRawValue: String
    private let lifecycleStatusChangedAt: Date?
    private let lastModifiedDate: Date
    private let reminderFrequency: String?
    private let reminderTime: Date?
    private let firstReminderDate: Date?

    init(goal: Goal) {
        lifecycleStatusRawValue = goal.lifecycleStatusRawValue
        lifecycleStatusChangedAt = goal.lifecycleStatusChangedAt
        lastModifiedDate = goal.lastModifiedDate
        reminderFrequency = goal.reminderFrequency
        reminderTime = goal.reminderTime
        firstReminderDate = goal.firstReminderDate
    }

    func restore(_ goal: Goal) {
        goal.lifecycleStatusRawValue = lifecycleStatusRawValue
        goal.lifecycleStatusChangedAt = lifecycleStatusChangedAt
        goal.lastModifiedDate = lastModifiedDate
        goal.reminderFrequency = reminderFrequency
        goal.reminderTime = reminderTime
        goal.firstReminderDate = firstReminderDate
    }
}

private struct GoalAllocationRelationshipSnapshot {
    private struct AllocationReference {
        let allocation: AssetAllocation
        let asset: Asset?
    }

    private struct AssetRelationship {
        let asset: Asset
        let allocations: [AssetAllocation]?
    }

    private let goalAllocations: [AssetAllocation]?
    private let allocationReferences: [AllocationReference]
    private let assetRelationships: [AssetRelationship]

    init(goal: Goal) {
        goalAllocations = goal.allocations
        allocationReferences = (goal.allocations ?? []).map {
            AllocationReference(allocation: $0, asset: $0.asset)
        }

        var seenAssetIDs: Set<UUID> = []
        assetRelationships = allocationReferences.compactMap { reference in
            guard let asset = reference.asset, seenAssetIDs.insert(asset.id).inserted else {
                return nil
            }
            return AssetRelationship(asset: asset, allocations: asset.allocations)
        }
    }

    func restoreDeletedAllocations(for goal: Goal, in modelContext: ModelContext) {
        for reference in allocationReferences {
            modelContext.insert(reference.allocation)
        }
        modelContext.processPendingChanges()

        // Force SwiftData to rebuild both inverse relationship collections for
        // allocations resurrected from this operation's pending deletes.
        for reference in allocationReferences {
            reference.allocation.goal = nil
            reference.allocation.asset = nil
        }
        modelContext.processPendingChanges()
        for reference in allocationReferences {
            reference.allocation.goal = goal
            reference.allocation.asset = reference.asset
        }
        modelContext.processPendingChanges()

        goal.allocations = goalAllocations
        for relationship in assetRelationships {
            relationship.asset.allocations = relationship.allocations
        }
    }
}
