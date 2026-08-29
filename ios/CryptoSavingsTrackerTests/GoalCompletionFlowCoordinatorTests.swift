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
        #expect(coordinator.isDecisionSheetPresented)
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

    @Test("cancel during an in-flight apply waits for persistence to finish")
    func cancelDuringApplyDoesNotResetFlow() async {
        let goal = makeGoal()
        let plan = makePlan(goalID: goal.id, modes: [.mixed])
        let snapshot = makeSnapshot(goal: goal)
        let coordinator = GoalCompletionFlowCoordinator()
        let gate = ApplyGate()

        await coordinator.start(
            goal: goal,
            prepare: { _ in plan },
            apply: { _, _, _ in snapshot }
        )
        coordinator.choose(
            allocationID: plan.unresolvedAllocationIDs[0],
            settlement: .keepAsSpent
        )

        let applyTask = Task { @MainActor in
            await coordinator.apply { _, _, _ in
                await gate.suspend()
            }
        }
        await waitForSuspension(gate)

        coordinator.cancel()

        #expect(coordinator.phase == .applying)
        #expect(coordinator.goal === goal)
        #expect(coordinator.plan == plan)
        #expect(coordinator.isDecisionSheetPresented)

        gate.resume(returning: snapshot)
        await applyTask.value

        #expect(coordinator.phase == .idle)
        #expect(coordinator.goal == nil)
    }

    @Test("two concurrent apply requests invoke persistence once")
    func concurrentApplyInvokesPersistenceOnce() async {
        let goal = makeGoal()
        let plan = makePlan(goalID: goal.id, modes: [.mixed])
        let snapshot = makeSnapshot(goal: goal)
        let coordinator = GoalCompletionFlowCoordinator()
        let gate = ApplyGate()
        var applyCallCount = 0

        await coordinator.start(
            goal: goal,
            prepare: { _ in plan },
            apply: { _, _, _ in snapshot }
        )
        coordinator.choose(
            allocationID: plan.unresolvedAllocationIDs[0],
            settlement: .keepAsSpent
        )

        let firstApply = Task { @MainActor in
            await coordinator.apply { _, _, _ in
                applyCallCount += 1
                return await gate.suspend()
            }
        }
        await waitForSuspension(gate)

        await coordinator.apply { _, _, _ in
            applyCallCount += 1
            return snapshot
        }

        #expect(applyCallCount == 1)
        gate.resume(returning: snapshot)
        await firstApply.value
    }

    @Test("a stale apply completion cannot reset a newer flow")
    func staleApplyCompletionDoesNotResetNewFlow() async {
        let firstGoal = makeGoal(name: "First")
        let firstPlan = makePlan(goalID: firstGoal.id, modes: [.mixed])
        let firstSnapshot = makeSnapshot(goal: firstGoal)
        let secondGoal = makeGoal(name: "Second")
        let secondPlan = makePlan(goalID: secondGoal.id, modes: [.mixed])
        let coordinator = GoalCompletionFlowCoordinator()
        let gate = ApplyGate()

        await coordinator.start(
            goal: firstGoal,
            prepare: { _ in firstPlan },
            apply: { _, _, _ in firstSnapshot }
        )
        coordinator.choose(
            allocationID: firstPlan.unresolvedAllocationIDs[0],
            settlement: .keepAsSpent
        )
        let firstApply = Task { @MainActor in
            await coordinator.apply { _, _, _ in
                await gate.suspend()
            }
        }
        await waitForSuspension(gate)

        await coordinator.start(
            goal: secondGoal,
            prepare: { _ in secondPlan },
            apply: { _, _, _ in self.makeSnapshot(goal: secondGoal) }
        )
        gate.resume(returning: firstSnapshot)
        await firstApply.value

        #expect(coordinator.goal === secondGoal)
        #expect(coordinator.plan == secondPlan)
        #expect(coordinator.phase == .deciding)
        #expect(coordinator.isDecisionSheetPresented)
    }

    @Test("mixed apply failures keep Retry and Cancel in the decision sheet")
    func mixedFailuresKeepDecisionSheetPresented() async {
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
            throw RepeatedFailure.first
        }

        #expect(coordinator.phase == .failed("First persistence failure."))
        #expect(coordinator.isDecisionSheetPresented)
        #expect(coordinator.canApply)

        await coordinator.apply { _, _, _ in
            throw RepeatedFailure.second
        }

        #expect(coordinator.phase == .failed("Second persistence failure."))
        #expect(coordinator.isDecisionSheetPresented)
        #expect(coordinator.canApply)

        coordinator.cancel()
        #expect(coordinator.phase == .idle)
        #expect(coordinator.goal == nil)
    }

    private enum ExpectedFailure: LocalizedError {
        case retryable

        var errorDescription: String? {
            "The goal could not be finished. Try again."
        }
    }

    private enum RepeatedFailure: LocalizedError {
        case first
        case second

        var errorDescription: String? {
            switch self {
            case .first:
                return "First persistence failure."
            case .second:
                return "Second persistence failure."
            }
        }
    }

    @MainActor
    private final class ApplyGate {
        private var continuation: CheckedContinuation<GoalCompletionSnapshot, Never>?

        var isSuspended: Bool {
            continuation != nil
        }

        func suspend() async -> GoalCompletionSnapshot {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func resume(returning snapshot: GoalCompletionSnapshot) {
            continuation?.resume(returning: snapshot)
            continuation = nil
        }
    }

    private func waitForSuspension(_ gate: ApplyGate) async {
        for _ in 0..<1_000 {
            if gate.isSuspended {
                return
            }
            await Task.yield()
        }
        Issue.record("Apply closure did not suspend in time.")
    }

    private func makeGoal(name: String = "Finish me") -> Goal {
        Goal(
            name: name,
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
