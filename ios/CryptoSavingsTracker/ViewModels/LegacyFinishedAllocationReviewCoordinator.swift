import Foundation
import Observation

struct LegacyFinishedAllocationDecisionKey: Hashable, Sendable {
    let goalID: UUID
    let allocationID: UUID
}

typealias LegacyReviewPrepare = @MainActor (Goal) throws -> GoalCompletionSettlementPlan
typealias LegacyReviewApply = @MainActor (
    [GoalCompletionSettlementCommand]
) async throws -> [GoalCompletionSnapshot]

enum LegacyFinishedAllocationReviewError: Error, Equatable {
    case invalidPreparedPlan(UUID)
    case duplicateAllocationID(goalID: UUID, allocationID: UUID)
}

extension LegacyFinishedAllocationReviewError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidPreparedPlan:
            return "A finished goal produced an invalid review. Nothing was changed."
        case .duplicateAllocationID:
            return "A finished goal contains duplicate allocation data. Nothing was changed."
        }
    }
}

@MainActor
protocol LegacyFinishedAllocationReviewCoordinating: AnyObject {
    var plansByGoalID: [UUID: GoalCompletionSettlementPlan] { get }
    var decisions: [LegacyFinishedAllocationDecisionKey: FinishedAllocationSettlement] { get }
    var isPresented: Bool { get }
    var errorMessage: String? { get }
    var canApply: Bool { get }

    func load(goals: [Goal], prepare: @escaping LegacyReviewPrepare) throws
    func choose(
        goalID: UUID,
        allocationID: UUID,
        settlement: FinishedAllocationSettlement
    )
    func later()
    func apply(using applyBatch: LegacyReviewApply) async throws
}

@MainActor
@Observable
final class LegacyFinishedAllocationReviewCoordinator: LegacyFinishedAllocationReviewCoordinating {
    private(set) var plansByGoalID: [UUID: GoalCompletionSettlementPlan] = [:]
    private(set) var decisions: [LegacyFinishedAllocationDecisionKey: FinishedAllocationSettlement] = [:]
    private(set) var isPresented = false
    private(set) var errorMessage: String?
    private(set) var isApplying = false
    private var reviewGoals: [Goal] = []
    private var prepareAction: LegacyReviewPrepare?

    var canApply: Bool {
        guard isPresented, isApplying == false, plansByGoalID.isEmpty == false else { return false }
        return Set(expectedDecisionKeys) == Set(decisions.keys)
    }

    func load(goals: [Goal], prepare: @escaping LegacyReviewPrepare) throws {
        clearReview()
        reviewGoals = goals
        prepareAction = prepare

        do {
            try prepareReview(goals: goals, prepare: prepare)
        } catch {
            clearReview()
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func prepareReview(goals: [Goal], prepare: LegacyReviewPrepare) throws {
        plansByGoalID = [:]
        decisions = [:]
        isPresented = false
        isApplying = false

        var seenGoalIDs = Set<UUID>()
        let reviewableGoals = goals
            .filter { $0.completionSnapshotData == nil }
            .filter { seenGoalIDs.insert($0.id).inserted }
            .sorted {
                if $0.name != $1.name {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.id.uuidString < $1.id.uuidString
            }

        var preparedPlans: [UUID: GoalCompletionSettlementPlan] = [:]
        for goal in reviewableGoals {
            let plan = try prepare(goal)
            guard
                goal.lifecycleStatus == .finished,
                plan.origin == .legacyReview,
                plan.goalID == goal.id,
                plan.items.isEmpty == false,
                plan.items.allSatisfy({
                    $0.automaticSettlement == nil
                        && $0.input.amount.isFinite
                        && $0.input.amount > 0
                        && $0.input.assetCurrency.isEmpty == false
                }),
                plan.fingerprint == fingerprint(for: plan.items)
            else {
                throw LegacyFinishedAllocationReviewError.invalidPreparedPlan(goal.id)
            }
            var seenAllocationIDs = Set<UUID>()
            for item in plan.items {
                guard seenAllocationIDs.insert(item.id).inserted else {
                    throw LegacyFinishedAllocationReviewError.duplicateAllocationID(
                        goalID: goal.id,
                        allocationID: item.id
                    )
                }
            }
            preparedPlans[goal.id] = plan
        }
        plansByGoalID = preparedPlans
        isPresented = plansByGoalID.isEmpty == false
    }

    private func fingerprint(
        for items: [GoalCompletionSettlementItem]
    ) -> GoalCompletionAllocationFingerprint {
        GoalCompletionAllocationFingerprint(
            entries: items.map {
                GoalCompletionAllocationFingerprint.Entry(
                    allocationID: $0.input.allocationID,
                    assetID: $0.input.assetID,
                    amount: $0.input.amount,
                    accountingMode: $0.input.accountingMode
                )
            }
        )
    }

    func choose(
        goalID: UUID,
        allocationID: UUID,
        settlement: FinishedAllocationSettlement
    ) {
        guard plansByGoalID[goalID]?.items.contains(where: { $0.id == allocationID }) == true else {
            return
        }
        decisions[
            LegacyFinishedAllocationDecisionKey(goalID: goalID, allocationID: allocationID)
        ] = settlement
    }

    func later() {
        guard isApplying == false else { return }
        decisions = [:]
        errorMessage = nil
        isPresented = false
    }

    func apply(using applyBatch: LegacyReviewApply) async throws {
        guard canApply else { return }
        isApplying = true
        errorMessage = nil

        let commands: [GoalCompletionSettlementCommand] = plansByGoalID.values
            .sorted { $0.goalID.uuidString < $1.goalID.uuidString }
            .map { plan in
                let goalID = plan.goalID
                let planDecisions = plan.items.compactMap { item in
                    decisions[
                        LegacyFinishedAllocationDecisionKey(goalID: goalID, allocationID: item.id)
                    ].map {
                        GoalCompletionSettlementDecision(allocationID: item.id, settlement: $0)
                    }
                }
                return GoalCompletionSettlementCommand(plan: plan, decisions: planDecisions)
            }

        do {
            _ = try await applyBatch(commands)
            clearReview()
        } catch let error as GoalCompletionSettlementError {
            if case .allocationsChanged = error {
                try reloadAfterAllocationsChanged(error)
                throw error
            }
            isApplying = false
            errorMessage = error.localizedDescription
            isPresented = true
            throw error
        } catch {
            isApplying = false
            errorMessage = error.localizedDescription
            isPresented = true
            throw error
        }
    }

    private var expectedDecisionKeys: [LegacyFinishedAllocationDecisionKey] {
        plansByGoalID.flatMap { goalID, plan in
            plan.items.map {
                LegacyFinishedAllocationDecisionKey(goalID: goalID, allocationID: $0.id)
            }
        }
    }

    private func reloadAfterAllocationsChanged(
        _ error: GoalCompletionSettlementError
    ) throws {
        guard let prepareAction else {
            clearReview()
            errorMessage = error.localizedDescription
            return
        }

        do {
            try prepareReview(goals: reviewGoals, prepare: prepareAction)
            errorMessage = error.localizedDescription
        } catch {
            clearReview()
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func clearReview() {
        plansByGoalID = [:]
        decisions = [:]
        isPresented = false
        errorMessage = nil
        isApplying = false
        reviewGoals = []
        prepareAction = nil
    }
}
