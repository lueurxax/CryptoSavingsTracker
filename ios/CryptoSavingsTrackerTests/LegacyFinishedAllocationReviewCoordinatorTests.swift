import Foundation
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct LegacyFinishedAllocationReviewCoordinatorTests {
    @Test("loading from one asset prepares every allocation of the affected goal")
    func loadingFromOneAssetPreparesWholeGoal() throws {
        let goal = makeFinishedGoal(name: "Whole goal")
        let allocationIDs = [UUID(), UUID()]
        let plan = makePlan(
            goalID: goal.id,
            allocationIDs: allocationIDs,
            currencies: ["USDT", "BTC"]
        )
        let coordinator = LegacyFinishedAllocationReviewCoordinator()
        var preparedGoalIDs: [UUID] = []

        try coordinator.load(goals: [goal]) { preparedGoal in
            preparedGoalIDs.append(preparedGoal.id)
            return plan
        }

        #expect(preparedGoalIDs == [goal.id])
        #expect(coordinator.plansByGoalID[goal.id] == plan)
        #expect(Set(coordinator.plansByGoalID[goal.id]?.items.map(\.id) ?? []) == Set(allocationIDs))
        #expect(coordinator.decisions.isEmpty)
        #expect(coordinator.isPresented)
    }

    @Test("Later clears presentation without calling apply")
    func laterClearsPresentationWithoutApply() async throws {
        let goal = makeFinishedGoal(name: "Review later")
        let plan = makePlan(goalID: goal.id, allocationIDs: [UUID()], currencies: ["USDT"])
        let coordinator = LegacyFinishedAllocationReviewCoordinator()
        var applyCallCount = 0

        try coordinator.load(goals: [goal]) { _ in plan }
        coordinator.choose(
            goalID: goal.id,
            allocationID: plan.items[0].id,
            settlement: .keepAsSpent
        )

        coordinator.later()
        try await coordinator.apply { _ in
            applyCallCount += 1
            return []
        }

        #expect(applyCallCount == 0)
        #expect(coordinator.isPresented == false)
        #expect(coordinator.decisions.isEmpty)
    }

    @Test("Apply is disabled until every legacy allocation has a choice")
    func applyRequiresEveryAllocationChoice() throws {
        let goal = makeFinishedGoal(name: "No partial settlement")
        let plan = makePlan(
            goalID: goal.id,
            allocationIDs: [UUID(), UUID()],
            currencies: ["USDT", "BTC"]
        )
        let coordinator = LegacyFinishedAllocationReviewCoordinator()

        try coordinator.load(goals: [goal]) { _ in plan }
        #expect(coordinator.canApply == false)

        coordinator.choose(
            goalID: goal.id,
            allocationID: plan.items[0].id,
            settlement: .balanceAlreadyDecreased
        )
        #expect(coordinator.canApply == false)

        coordinator.choose(
            goalID: goal.id,
            allocationID: plan.items[1].id,
            settlement: .keepAsSpent
        )
        #expect(coordinator.canApply)
    }

    @Test("Apply sends all reviewed goals in one batch command")
    func applySendsOneWholeSheetBatch() async throws {
        let firstGoal = makeFinishedGoal(name: "First")
        let secondGoal = makeFinishedGoal(name: "Second")
        let sharedAllocationID = UUID()
        let firstPlan = makePlan(
            goalID: firstGoal.id,
            allocationIDs: [sharedAllocationID, UUID()],
            currencies: ["USDT", "BTC"]
        )
        let secondPlan = makePlan(
            goalID: secondGoal.id,
            allocationIDs: [sharedAllocationID],
            currencies: ["USDT"]
        )
        let plans = [firstGoal.id: firstPlan, secondGoal.id: secondPlan]
        let coordinator = LegacyFinishedAllocationReviewCoordinator()
        var batches: [[GoalCompletionSettlementCommand]] = []

        try coordinator.load(goals: [secondGoal, firstGoal]) { plans[$0.id]! }
        for plan in plans.values {
            for item in plan.items {
                coordinator.choose(
                    goalID: plan.goalID,
                    allocationID: item.id,
                    settlement: .keepAsSpent
                )
            }
        }

        try await coordinator.apply { commands in
            batches.append(commands)
            return commands.map { self.makeSnapshot(goalID: $0.plan.goalID) }
        }

        #expect(batches.count == 1)
        #expect(Set(batches[0].map(\.plan.goalID)) == Set([firstGoal.id, secondGoal.id]))
        #expect(batches[0].allSatisfy { command in
            Set(command.decisions.map(\.allocationID)) == Set(command.plan.items.map(\.id))
        })
        #expect(coordinator.isPresented == false)
    }

    @Test("successful final review cannot be reopened because snapshots now exist")
    func completedReviewCannotReopen() async throws {
        let goal = makeFinishedGoal(name: "Final review")
        let plan = makePlan(goalID: goal.id, allocationIDs: [UUID()], currencies: ["USDT"])
        let coordinator = LegacyFinishedAllocationReviewCoordinator()
        var prepareCallCount = 0

        try coordinator.load(goals: [goal]) { _ in
            prepareCallCount += 1
            return plan
        }
        coordinator.choose(
            goalID: goal.id,
            allocationID: plan.items[0].id,
            settlement: .balanceAlreadyDecreased
        )
        try await coordinator.apply { _ in
            let snapshot = self.makeSnapshot(goalID: goal.id)
            goal.completionSnapshotData = try GoalCompletionSnapshotCodec.encode(snapshot)
            return [snapshot]
        }

        try coordinator.load(goals: [goal]) { _ in
            prepareCallCount += 1
            return plan
        }

        #expect(prepareCallCount == 1)
        #expect(coordinator.plansByGoalID.isEmpty)
        #expect(coordinator.decisions.isEmpty)
        #expect(coordinator.isPresented == false)
        #expect(coordinator.canApply == false)
    }

    private func makeFinishedGoal(name: String) -> Goal {
        let goal = Goal(
            name: name,
            currency: "USD",
            targetAmount: 100,
            deadline: Date(timeIntervalSince1970: 2_000_000_000)
        )
        goal.lifecycleStatus = .finished
        return goal
    }

    private func makePlan(
        goalID: UUID,
        allocationIDs: [UUID],
        currencies: [String]
    ) -> GoalCompletionSettlementPlan {
        GoalCompletionSettlementPlanner().makePlan(
            goalID: goalID,
            origin: .legacyReview,
            allocations: zip(allocationIDs, currencies).enumerated().map { index, pair in
                GoalCompletionAllocationInput(
                    allocationID: pair.0,
                    assetID: UUID(),
                    assetCurrency: pair.1,
                    amount: Double(index + 1) * 10,
                    accountingMode: index.isMultiple(of: 2) ? .onChain : .manual,
                    bestKnownBalance: nil,
                    balanceCapturedAt: nil
                )
            }
        )
    }

    private func makeSnapshot(goalID: UUID) -> GoalCompletionSnapshot {
        let timestamp = Date(timeIntervalSince1970: 1_900_000_000)
        return GoalCompletionSnapshot(
            id: UUID(),
            schemaVersion: GoalCompletionSnapshot.currentSchemaVersion,
            goalID: goalID,
            goalName: "Reviewed",
            goalCurrency: "USD",
            goalTargetAmount: 100,
            goalCompletedAt: timestamp,
            snapshotCreatedAt: timestamp,
            entries: []
        )
    }
}
