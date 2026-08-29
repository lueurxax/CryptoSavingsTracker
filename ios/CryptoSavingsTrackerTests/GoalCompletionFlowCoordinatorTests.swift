import Foundation
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct GoalCompletionFlowCoordinatorTests {
    @Test("automatic plan applies without presenting a sheet")
    func automaticPlanAppliesWithoutPresentingSheet() async {
        let goal = makeGoal()
        let plan = makePlan(goalID: goal.id, modes: [.manual])
        let coordinator = GoalCompletionFlowCoordinator()
        var appliedDecisions: [GoalCompletionSettlementDecision]?

        await coordinator.start(
            goal: goal,
            prepare: { _ in plan },
            apply: { appliedGoal, appliedPlan, decisions in
                #expect(appliedGoal === goal)
                #expect(appliedPlan == plan)
                appliedDecisions = decisions
                return self.makeSnapshot(goal: goal)
            }
        )

        #expect(appliedDecisions == [])
        #expect(coordinator.phase == .idle)
        #expect(coordinator.isDecisionSheetPresented == false)
    }

    @Test("mixed plan presents and disables Apply until every decision exists")
    func mixedPlanRequiresEveryDecision() async {
        let goal = makeGoal()
        let plan = makePlan(goalID: goal.id, modes: [.mixed, .mixed])
        let coordinator = GoalCompletionFlowCoordinator()
        var applyCallCount = 0

        await coordinator.start(
            goal: goal,
            prepare: { _ in plan },
            apply: { _, _, _ in
                applyCallCount += 1
                return self.makeSnapshot(goal: goal)
            }
        )

        #expect(coordinator.phase == .deciding)
        #expect(coordinator.isDecisionSheetPresented)
        #expect(coordinator.canApply == false)
        #expect(applyCallCount == 0)

        coordinator.choose(
            allocationID: plan.unresolvedAllocationIDs[0],
            settlement: .balanceAlreadyDecreased
        )
        #expect(coordinator.canApply == false)

        coordinator.choose(
            allocationID: plan.unresolvedAllocationIDs[1],
            settlement: .keepAsSpent
        )
        #expect(coordinator.canApply)
        #expect(applyCallCount == 0)
    }

    @Test("apply error keeps the goal active and exposes a retryable message")
    func applyErrorKeepsRetryableState() async {
        let goal = makeGoal()
        let plan = makePlan(goalID: goal.id, modes: [.mixed])
        let coordinator = GoalCompletionFlowCoordinator()

        await coordinator.start(
            goal: goal,
            prepare: { _ in plan },
            apply: { _, _, _ in self.makeSnapshot(goal: goal) }
        )
        coordinator.choose(
            allocationID: plan.unresolvedAllocationIDs[0],
            settlement: .keepAsSpent
        )

        await coordinator.apply { _, _, _ in
            throw ExpectedFailure.retryable
        }

        #expect(goal.lifecycleStatus == .active)
        #expect(coordinator.phase == .failed("The goal could not be finished. Try again."))
        #expect(coordinator.plan == plan)
        #expect(coordinator.canApply)
        #expect(coordinator.isDecisionSheetPresented == false)
    }

    @Test("changed allocations error clears the stale plan before re-preparing")
    func changedAllocationsReprepareFromCleanState() async {
        let goal = makeGoal()
        let initialPlan = makePlan(goalID: goal.id, modes: [.mixed])
        let refreshedPlan = makePlan(goalID: goal.id, modes: [.mixed, .mixed])
        let coordinator = GoalCompletionFlowCoordinator()
        var prepareCallCount = 0
        var stalePlanWasCleared = false

        let prepare: GoalCompletionPrepare = { _ in
            prepareCallCount += 1
            if prepareCallCount == 2 {
                stalePlanWasCleared = coordinator.plan == nil
                return refreshedPlan
            }
            return initialPlan
        }

        await coordinator.start(
            goal: goal,
            prepare: prepare,
            apply: { _, _, _ in self.makeSnapshot(goal: goal) }
        )
        coordinator.choose(
            allocationID: initialPlan.unresolvedAllocationIDs[0],
            settlement: .keepAsSpent
        )

        await coordinator.apply { _, _, _ in
            throw GoalCompletionSettlementError.allocationsChanged(goal.id)
        }

        #expect(prepareCallCount == 2)
        #expect(stalePlanWasCleared)
        #expect(coordinator.plan == refreshedPlan)
        #expect(coordinator.decisions.isEmpty)
        #expect(coordinator.phase == .deciding)
        #expect(coordinator.isDecisionSheetPresented)
        #expect(coordinator.canApply == false)
    }

    private enum ExpectedFailure: LocalizedError {
        case retryable

        var errorDescription: String? {
            "The goal could not be finished. Try again."
        }
    }

    private func makeGoal() -> Goal {
        Goal(
            name: "Finish me",
            currency: "USD",
            targetAmount: 100,
            deadline: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    private func makePlan(
        goalID: UUID,
        modes: [AssetBalanceAccountingMode]
    ) -> GoalCompletionSettlementPlan {
        GoalCompletionSettlementPlanner().makePlan(
            goalID: goalID,
            origin: .newCompletion,
            allocations: modes.enumerated().map { index, mode in
                GoalCompletionAllocationInput(
                    allocationID: UUID(),
                    assetID: UUID(),
                    assetCurrency: index.isMultiple(of: 2) ? "USD" : "USDT",
                    amount: Double(index + 1) * 10,
                    accountingMode: mode,
                    bestKnownBalance: nil,
                    balanceCapturedAt: nil
                )
            }
        )
    }

    private func makeSnapshot(goal: Goal) -> GoalCompletionSnapshot {
        let timestamp = Date(timeIntervalSince1970: 1_900_000_000)
        return GoalCompletionSnapshot(
            id: UUID(),
            schemaVersion: GoalCompletionSnapshot.currentSchemaVersion,
            goalID: goal.id,
            goalName: goal.name,
            goalCurrency: goal.currency,
            goalTargetAmount: goal.targetAmount,
            goalCompletedAt: timestamp,
            snapshotCreatedAt: timestamp,
            entries: []
        )
    }
}
