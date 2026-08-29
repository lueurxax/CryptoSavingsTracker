import Foundation
import SwiftData

struct GoalCompletionSettlementCommand: Sendable {
    let plan: GoalCompletionSettlementPlan
    let decisions: [GoalCompletionSettlementDecision]
}

enum GoalCompletionSettlementError: Error, Equatable {
    case invalidGoalState(UUID)
    case alreadySettled(UUID)
    case goalNotFound(UUID)
    case missingAsset(UUID)
    case allocationsChanged(UUID)
    case duplicateGoal(UUID)
}

extension GoalCompletionSettlementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidGoalState:
            return "This goal can no longer be finished from its current state."
        case .alreadySettled:
            return "This goal has already been settled."
        case .goalNotFound:
            return "This goal is no longer available."
        case .missingAsset:
            return "One of the allocated assets is no longer available."
        case .allocationsChanged:
            return "Allocations changed while this review was open. Review the updated amounts."
        case .duplicateGoal:
            return "The same goal was included in this settlement more than once."
        }
    }
}

typealias GoalCompletionSave = @MainActor () throws -> Void
typealias GoalCompletionRollback = @MainActor () -> Void

@MainActor
protocol GoalCompletionSettlementServicing {
    func prepareNewCompletion(for goal: Goal) throws -> GoalCompletionSettlementPlan
    func prepareLegacyReview(for goal: Goal) throws -> GoalCompletionSettlementPlan
    func apply(
        _ command: GoalCompletionSettlementCommand,
        at timestamp: Date
    ) async throws -> GoalCompletionSnapshot
    func applyBatch(
        _ commands: [GoalCompletionSettlementCommand],
        at timestamp: Date
    ) async throws -> [GoalCompletionSnapshot]
}

extension GoalCompletionSettlementServicing {
    func apply(_ command: GoalCompletionSettlementCommand) async throws -> GoalCompletionSnapshot {
        try await apply(command, at: Date())
    }

    func applyBatch(_ commands: [GoalCompletionSettlementCommand]) async throws -> [GoalCompletionSnapshot] {
        try await applyBatch(commands, at: Date())
    }
}

@MainActor
struct GoalCompletionSettlementService: GoalCompletionSettlementServicing {
    private struct PendingSettlement {
        let commandIndex: Int
        let goal: Goal
        let plan: GoalCompletionSettlementPlan
        let settlements: [UUID: FinishedAllocationSettlement]
        let snapshot: GoalCompletionSnapshot
        let snapshotData: Data
    }

    private let modelContext: ModelContext
    private let notificationManager: NotificationManager
    private let save: GoalCompletionSave
    private let rollback: GoalCompletionRollback
    private let planner = GoalCompletionSettlementPlanner()
    private let executionTrackingService: ExecutionTrackingService

    init(
        modelContext: ModelContext,
        notificationManager: NotificationManager = .shared,
        save: GoalCompletionSave? = nil,
        rollback: GoalCompletionRollback? = nil
    ) {
        self.modelContext = modelContext
        self.notificationManager = notificationManager
        self.save = save ?? { try modelContext.save() }
        self.rollback = rollback ?? { modelContext.rollback() }
        self.executionTrackingService = ExecutionTrackingService(modelContext: modelContext)
    }

    func prepareNewCompletion(for goal: Goal) throws -> GoalCompletionSettlementPlan {
        if goal.completionSnapshotData != nil {
            throw GoalCompletionSettlementError.alreadySettled(goal.id)
        }
        guard goal.lifecycleStatus == .active else {
            throw GoalCompletionSettlementError.invalidGoalState(goal.id)
        }
        return try makePlan(for: goal, origin: .newCompletion)
    }

    func prepareLegacyReview(for goal: Goal) throws -> GoalCompletionSettlementPlan {
        if goal.completionSnapshotData != nil {
            throw GoalCompletionSettlementError.alreadySettled(goal.id)
        }
        guard goal.lifecycleStatus == .finished else {
            throw GoalCompletionSettlementError.invalidGoalState(goal.id)
        }
        return try makePlan(for: goal, origin: .legacyReview)
    }

    func apply(
        _ command: GoalCompletionSettlementCommand,
        at timestamp: Date = Date()
    ) async throws -> GoalCompletionSnapshot {
        let snapshots = try await applyBatch([command], at: timestamp)
        return snapshots[0]
    }

    func applyBatch(
        _ commands: [GoalCompletionSettlementCommand],
        at timestamp: Date = Date()
    ) async throws -> [GoalCompletionSnapshot] {
        guard !commands.isEmpty else { return [] }

        var seenGoalIDs = Set<UUID>()
        for command in commands {
            guard seenGoalIDs.insert(command.plan.goalID).inserted else {
                throw GoalCompletionSettlementError.duplicateGoal(command.plan.goalID)
            }
        }

        let allGoals = try modelContext.fetch(FetchDescriptor<Goal>())
        let goalsByID = Dictionary(uniqueKeysWithValues: allGoals.map { ($0.id, $0) })
        var results = Array<GoalCompletionSnapshot?>(repeating: nil, count: commands.count)
        var pending: [PendingSettlement] = []
        pending.reserveCapacity(commands.count)

        for (index, command) in commands.enumerated() {
            guard let goal = goalsByID[command.plan.goalID] else {
                throw GoalCompletionSettlementError.goalNotFound(command.plan.goalID)
            }
            if let snapshotData = goal.completionSnapshotData {
                results[index] = try GoalCompletionSnapshotCodec.decode(snapshotData)
                continue
            }

            let currentPlan: GoalCompletionSettlementPlan
            switch command.plan.origin {
            case .newCompletion:
                currentPlan = try prepareNewCompletion(for: goal)
            case .legacyReview:
                currentPlan = try prepareLegacyReview(for: goal)
            }
            guard currentPlan.fingerprint == command.plan.fingerprint else {
                throw GoalCompletionSettlementError.allocationsChanged(goal.id)
            }
            let settlements = try planner.resolve(plan: currentPlan, decisions: command.decisions)
            let snapshot = makeSnapshot(
                for: goal,
                plan: currentPlan,
                settlements: settlements,
                at: timestamp
            )
            let snapshotData = try GoalCompletionSnapshotCodec.encode(snapshot)
            pending.append(
                PendingSettlement(
                    commandIndex: index,
                    goal: goal,
                    plan: currentPlan,
                    settlements: settlements,
                    snapshot: snapshot,
                    snapshotData: snapshotData
                )
            )
            results[index] = snapshot
        }

        guard !pending.isEmpty else {
            return results.compactMap { $0 }
        }

        do {
            for settlement in pending {
                settlement.goal.completionSnapshotData = settlement.snapshotData
                try applyAllocationMutations(settlement, at: timestamp)
                if settlement.plan.origin == .newCompletion {
                    settlement.goal.markFinished(at: timestamp)
                }
                settlement.goal.clearRetiredReminderState()
            }
            try removeNewlyFinishedGoalsFromActiveExecution(pending)
            try save()
        } catch {
            rollback()
            throw error
        }

        let affectedGoals = pending.map(\.goal)
        for goal in affectedGoals {
            await notificationManager.cancelNotifications(for: goal)
            NotificationCenter.default.post(name: .goalDeleted, object: goal)
            NotificationCenter.default.post(
                name: .goalUpdated,
                object: goal,
                userInfo: ["goalId": goal.id]
            )
        }
        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": affectedGoals.map(\.id),
                "reason": "assetMutation"
            ]
        )

        return results.compactMap { $0 }
    }

    private func makePlan(
        for goal: Goal,
        origin: GoalCompletionSettlementOrigin
    ) throws -> GoalCompletionSettlementPlan {
        var inputs: [GoalCompletionAllocationInput] = []
        for allocation in goal.allocations ?? [] where allocation.amountValue > 0 {
            guard let asset = allocation.asset else {
                throw GoalCompletionSettlementError.missingAsset(allocation.id)
            }
            let mode = AssetBalanceAccountingModeResolver.resolve(asset: asset)
            let evidence = bestKnownBalanceEvidence(for: asset, mode: mode)
            inputs.append(
                GoalCompletionAllocationInput(
                    allocationID: allocation.id,
                    assetID: asset.id,
                    assetCurrency: asset.currency,
                    amount: allocation.amountValue,
                    accountingMode: mode,
                    bestKnownBalance: evidence.balance,
                    balanceCapturedAt: evidence.capturedAt
                )
            )
        }
        return planner.makePlan(goalID: goal.id, origin: origin, allocations: inputs)
    }

    private func bestKnownBalanceEvidence(
        for asset: Asset,
        mode: AssetBalanceAccountingMode
    ) -> (balance: Double?, capturedAt: Date?) {
        guard mode != .manual else { return (asset.manualBalance, Date()) }
        guard
            let chainID = asset.chainId,
            let address = asset.address,
            !chainID.isEmpty,
            !address.isEmpty
        else { return (nil, nil) }
        let key = BalanceCacheManager.balanceCacheKey(
            chainId: chainID,
            address: address,
            symbol: asset.currency
        )
        guard let cachedOnChain = BalanceCacheManager.shared.getFallbackBalance(for: key) else {
            return (nil, nil)
        }
        return (
            asset.manualBalance + cachedOnChain,
            BalanceCacheManager.shared.getLastBalanceUpdate(for: key)
        )
    }

    private func makeSnapshot(
        for goal: Goal,
        plan: GoalCompletionSettlementPlan,
        settlements: [UUID: FinishedAllocationSettlement],
        at timestamp: Date
    ) -> GoalCompletionSnapshot {
        let isLegacyReview = plan.origin == .legacyReview
        let entries = plan.items.map { item in
            GoalCompletionSnapshot.Entry(
                allocationID: item.input.allocationID,
                assetID: item.input.assetID,
                assetCurrency: item.input.assetCurrency,
                amount: item.input.amount,
                accountingMode: item.input.accountingMode,
                settlement: settlements[item.id]!,
                bestKnownBalance: item.input.bestKnownBalance,
                balanceCapturedAt: item.input.balanceCapturedAt,
                balanceTiming: isLegacyReview ? .reviewTime : .completionTime
            )
        }
        return GoalCompletionSnapshot(
            id: UUID(),
            schemaVersion: GoalCompletionSnapshot.currentSchemaVersion,
            goalID: goal.id,
            goalName: goal.name,
            goalCurrency: goal.currency,
            goalTargetAmount: goal.targetAmount,
            goalCompletedAt: isLegacyReview ? (goal.lifecycleStatusChangedAt ?? timestamp) : timestamp,
            snapshotCreatedAt: timestamp,
            entries: entries
        )
    }

    private func applyAllocationMutations(
        _ settlement: PendingSettlement,
        at timestamp: Date
    ) throws {
        let allocationsByID = Dictionary(
            uniqueKeysWithValues: (settlement.goal.allocations ?? []).map { ($0.id, $0) }
        )
        for item in settlement.plan.items {
            guard settlement.settlements[item.id] == .balanceAlreadyDecreased else { continue }
            guard let allocation = allocationsByID[item.id] else {
                throw GoalCompletionSettlementError.allocationsChanged(settlement.goal.id)
            }
            guard let asset = allocation.asset else {
                throw GoalCompletionSettlementError.missingAsset(allocation.id)
            }
            asset.allocations?.removeAll { $0.id == allocation.id }
            settlement.goal.allocations?.removeAll { $0.id == allocation.id }
            modelContext.insert(
                AllocationHistory(
                    asset: asset,
                    goal: settlement.goal,
                    amount: 0,
                    timestamp: timestamp
                )
            )
            modelContext.delete(allocation)
        }
    }

    private func removeNewlyFinishedGoalsFromActiveExecution(_ pending: [PendingSettlement]) throws {
        let newlyFinishedGoalIDs = Set(
            pending.filter { $0.plan.origin == .newCompletion }.map { $0.goal.id }
        )
        guard !newlyFinishedGoalIDs.isEmpty else { return }
        guard let record = try executionTrackingService.getActiveRecord() else { return }
        let updatedGoalIDs = record.goalIds.filter { !newlyFinishedGoalIDs.contains($0) }
        guard updatedGoalIDs != record.goalIds else { return }
        record.trackedGoalIds = try JSONEncoder().encode(updatedGoalIDs)
    }
}
