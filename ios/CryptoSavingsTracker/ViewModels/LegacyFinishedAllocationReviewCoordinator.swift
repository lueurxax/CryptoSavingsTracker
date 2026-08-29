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

@MainActor
protocol LegacyFinishedAllocationReviewCoordinating: AnyObject {
    var plansByGoalID: [UUID: GoalCompletionSettlementPlan] { get }
    var decisions: [LegacyFinishedAllocationDecisionKey: FinishedAllocationSettlement] { get }
    var isPresented: Bool { get }
    var errorMessage: String? { get }
    var canApply: Bool { get }

    func load(goals: [Goal], prepare: LegacyReviewPrepare) throws
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

    var canApply: Bool {
        guard isPresented, isApplying == false, plansByGoalID.isEmpty == false else { return false }
        return Set(expectedDecisionKeys) == Set(decisions.keys)
    }

    func load(goals: [Goal], prepare: LegacyReviewPrepare) throws {
        clearReview()

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

        do {
            for goal in reviewableGoals {
                let plan = try prepare(goal)
                guard plan.origin == .legacyReview, plan.goalID == goal.id, plan.items.isEmpty == false else {
                    continue
                }
                plansByGoalID[goal.id] = plan
            }
            isPresented = plansByGoalID.isEmpty == false
        } catch {
            clearReview()
            errorMessage = error.localizedDescription
            throw error
        }
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

    private func clearReview() {
        plansByGoalID = [:]
        decisions = [:]
        isPresented = false
        errorMessage = nil
        isApplying = false
    }
}
