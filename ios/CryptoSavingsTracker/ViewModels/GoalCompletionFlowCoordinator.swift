import Foundation
import Observation

enum GoalCompletionFlowPhase: Equatable {
    case idle
    case deciding
    case applying
    case failed(String)
}

typealias GoalCompletionPrepare = @MainActor (Goal) throws -> GoalCompletionSettlementPlan
typealias GoalCompletionApply = @MainActor (
    Goal,
    GoalCompletionSettlementPlan,
    [GoalCompletionSettlementDecision]
) async throws -> GoalCompletionSnapshot

@MainActor
protocol GoalCompletionFlowCoordinating: AnyObject {
    var phase: GoalCompletionFlowPhase { get }
    var goal: Goal? { get }
    var plan: GoalCompletionSettlementPlan? { get }
    var decisions: [UUID: FinishedAllocationSettlement] { get }
    var isDecisionSheetPresented: Bool { get }
    var canApply: Bool { get }

    func start(
        goal: Goal,
        prepare: @escaping GoalCompletionPrepare,
        apply: GoalCompletionApply
    ) async
    func choose(allocationID: UUID, settlement: FinishedAllocationSettlement)
    func apply(using apply: GoalCompletionApply) async
    func cancel()
}

@MainActor
@Observable
final class GoalCompletionFlowCoordinator: GoalCompletionFlowCoordinating {
    private(set) var phase: GoalCompletionFlowPhase = .idle
    private(set) var goal: Goal?
    private(set) var plan: GoalCompletionSettlementPlan?
    private(set) var decisions: [UUID: FinishedAllocationSettlement] = [:]
    private(set) var isDecisionSheetPresented = false

    private var prepareAction: GoalCompletionPrepare?

    var canApply: Bool {
        guard let plan else { return false }
        return Set(plan.unresolvedAllocationIDs) == Set(decisions.keys)
    }

    func start(
        goal: Goal,
        prepare: @escaping GoalCompletionPrepare,
        apply: GoalCompletionApply
    ) async {
        reset()
        self.goal = goal
        prepareAction = prepare
        await prepareAndAdvance(using: apply)
    }

    func choose(allocationID: UUID, settlement: FinishedAllocationSettlement) {
        guard plan?.unresolvedAllocationIDs.contains(allocationID) == true else { return }
        decisions[allocationID] = settlement
    }

    func apply(using apply: GoalCompletionApply) async {
        guard let goal, let plan, canApply else { return }
        phase = .applying
        let orderedDecisions = plan.unresolvedAllocationIDs.compactMap { allocationID in
            decisions[allocationID].map {
                GoalCompletionSettlementDecision(allocationID: allocationID, settlement: $0)
            }
        }

        do {
            _ = try await apply(goal, plan, orderedDecisions)
            reset()
        } catch GoalCompletionSettlementError.allocationsChanged {
            self.plan = nil
            decisions = [:]
            isDecisionSheetPresented = false
            await prepareAndAdvance(using: apply)
        } catch {
            phase = .failed(error.localizedDescription)
            isDecisionSheetPresented = false
        }
    }

    func cancel() {
        reset()
    }

    private func prepareAndAdvance(using apply: GoalCompletionApply) async {
        guard let goal, let prepareAction else { return }
        do {
            let preparedPlan = try prepareAction(goal)
            plan = preparedPlan
            decisions = [:]
            if preparedPlan.unresolvedAllocationIDs.isEmpty {
                await self.apply(using: apply)
            } else {
                phase = .deciding
                isDecisionSheetPresented = true
            }
        } catch {
            phase = .failed(error.localizedDescription)
            isDecisionSheetPresented = false
        }
    }

    private func reset() {
        phase = .idle
        goal = nil
        plan = nil
        decisions = [:]
        isDecisionSheetPresented = false
        prepareAction = nil
    }
}
