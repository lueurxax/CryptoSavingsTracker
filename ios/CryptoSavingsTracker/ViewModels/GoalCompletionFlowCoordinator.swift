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
    private var flowID: UUID?

    var canApply: Bool {
        guard let plan else { return false }
        return Set(plan.unresolvedAllocationIDs) == Set(decisions.keys)
    }

    func start(
        goal: Goal,
        prepare: @escaping GoalCompletionPrepare,
        apply: GoalCompletionApply
    ) async {
        let flowID = UUID()
        self.flowID = flowID
        phase = .idle
        self.goal = goal
        plan = nil
        decisions = [:]
        isDecisionSheetPresented = false
        prepareAction = prepare
        await prepareAndAdvance(using: apply, flowID: flowID)
    }

    func choose(allocationID: UUID, settlement: FinishedAllocationSettlement) {
        guard plan?.unresolvedAllocationIDs.contains(allocationID) == true else { return }
        decisions[allocationID] = settlement
    }

    func apply(using apply: GoalCompletionApply) async {
        guard phase != .applying, let flowID, let goal, let plan, canApply else { return }
        phase = .applying
        let orderedDecisions = plan.unresolvedAllocationIDs.compactMap { allocationID in
            decisions[allocationID].map {
                GoalCompletionSettlementDecision(allocationID: allocationID, settlement: $0)
            }
        }

        do {
            _ = try await apply(goal, plan, orderedDecisions)
            guard self.flowID == flowID else { return }
            reset()
        } catch GoalCompletionSettlementError.allocationsChanged {
            guard self.flowID == flowID else { return }
            self.plan = nil
            decisions = [:]
            isDecisionSheetPresented = false
            await prepareAndAdvance(using: apply, flowID: flowID)
        } catch {
            guard self.flowID == flowID else { return }
            phase = .failed(error.localizedDescription)
            isDecisionSheetPresented = plan.unresolvedAllocationIDs.isEmpty == false
        }
    }

    func cancel() {
        guard phase != .applying else { return }
        reset()
    }

    private func prepareAndAdvance(using apply: GoalCompletionApply, flowID: UUID) async {
        guard self.flowID == flowID, let goal, let prepareAction else { return }
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
        flowID = nil
    }
}
