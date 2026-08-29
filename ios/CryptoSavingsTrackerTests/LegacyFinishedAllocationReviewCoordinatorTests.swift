import Foundation
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct LegacyFinishedAllocationReviewCoordinatorTests {
    private enum TestFailure: Error {
        case generic
    }

    @Test("wrong-origin plan rejects the entire multi-goal load without partial apply")
    func wrongOriginRejectsEntireLoad() async throws {
        let validGoal = makeFinishedGoal(name: "A valid")
        let malformedGoal = makeFinishedGoal(name: "B malformed")
        let validPlan = makePlan(
            goalID: validGoal.id,
            allocationIDs: [UUID()],
            currencies: ["USDT"]
        )
        let malformedPlan = makePlan(
            goalID: malformedGoal.id,
            allocationIDs: [UUID()],
            currencies: ["BTC"],
            origin: .newCompletion
        )
        let plans = [validGoal.id: validPlan, malformedGoal.id: malformedPlan]
        let coordinator = LegacyFinishedAllocationReviewCoordinator()
        var applyCallCount = 0

        #expect(throws: LegacyFinishedAllocationReviewError.invalidPreparedPlan(malformedGoal.id)) {
            try coordinator.load(goals: [validGoal, malformedGoal]) { plans[$0.id]! }
        }
        try await coordinator.apply { _ in
            applyCallCount += 1
            return []
        }

        #expect(coordinator.plansByGoalID.isEmpty)
        #expect(coordinator.decisions.isEmpty)
        #expect(coordinator.isPresented == false)
        #expect(coordinator.canApply == false)
        #expect(applyCallCount == 0)
    }

    @Test("malformed plan rejects the entire multi-goal load without partial state")
    func malformedPlanRejectsEntireLoad() throws {
        let validGoal = makeFinishedGoal(name: "A valid")
        let malformedGoal = makeFinishedGoal(name: "B malformed")
        let validPlan = makePlan(
            goalID: validGoal.id,
            allocationIDs: [UUID()],
            currencies: ["USDT"]
        )
        let preparedMalformedPlan = makePlan(
            goalID: malformedGoal.id,
            allocationIDs: [UUID()],
            currencies: ["BTC"]
        )
        let malformedPlan = GoalCompletionSettlementPlan(
            goalID: preparedMalformedPlan.goalID,
            origin: preparedMalformedPlan.origin,
            items: preparedMalformedPlan.items,
            fingerprint: GoalCompletionAllocationFingerprint(entries: [])
        )
        let plans = [validGoal.id: validPlan, malformedGoal.id: malformedPlan]
        let coordinator = LegacyFinishedAllocationReviewCoordinator()

        #expect(throws: LegacyFinishedAllocationReviewError.invalidPreparedPlan(malformedGoal.id)) {
            try coordinator.load(goals: [validGoal, malformedGoal]) { plans[$0.id]! }
        }

        #expect(coordinator.plansByGoalID.isEmpty)
        #expect(coordinator.decisions.isEmpty)
        #expect(coordinator.isPresented == false)
        #expect(coordinator.canApply == false)
    }

    @Test("wrong-goal plan rejects the entire multi-goal load")
    func wrongGoalRejectsEntireLoad() throws {
        let validGoal = makeFinishedGoal(name: "A valid")
        let malformedGoal = makeFinishedGoal(name: "B wrong goal")
        let validPlan = makePlan(
            goalID: validGoal.id,
            allocationIDs: [UUID()],
            currencies: ["USDT"]
        )
        let malformedPlan = makePlan(
            goalID: UUID(),
            allocationIDs: [UUID()],
            currencies: ["BTC"]
        )
        let plans = [validGoal.id: validPlan, malformedGoal.id: malformedPlan]
        let coordinator = LegacyFinishedAllocationReviewCoordinator()

        #expect(throws: LegacyFinishedAllocationReviewError.invalidPreparedPlan(malformedGoal.id)) {
            try coordinator.load(goals: [validGoal, malformedGoal]) { plans[$0.id]! }
        }

        #expect(coordinator.plansByGoalID.isEmpty)
        #expect(coordinator.isPresented == false)
    }

    @Test("empty plan rejects the entire multi-goal load")
    func emptyPlanRejectsEntireLoad() throws {
        let validGoal = makeFinishedGoal(name: "A valid")
        let malformedGoal = makeFinishedGoal(name: "B empty")
        let plans = [
            validGoal.id: makePlan(
                goalID: validGoal.id,
                allocationIDs: [UUID()],
                currencies: ["USDT"]
            ),
            malformedGoal.id: makePlan(
                goalID: malformedGoal.id,
                allocationIDs: [],
                currencies: []
            )
        ]
        let coordinator = LegacyFinishedAllocationReviewCoordinator()

        #expect(throws: LegacyFinishedAllocationReviewError.invalidPreparedPlan(malformedGoal.id)) {
            try coordinator.load(goals: [validGoal, malformedGoal]) { plans[$0.id]! }
        }

        #expect(coordinator.plansByGoalID.isEmpty)
        #expect(coordinator.isPresented == false)
    }

    @Test("duplicate allocation IDs reject the entire multi-goal load")
    func duplicateAllocationIDsRejectEntireLoad() throws {
        let validGoal = makeFinishedGoal(name: "A valid")
        let malformedGoal = makeFinishedGoal(name: "B duplicate")
        let duplicateAllocationID = UUID()
        let plans = [
            validGoal.id: makePlan(
                goalID: validGoal.id,
                allocationIDs: [UUID()],
                currencies: ["USDT"]
            ),
            malformedGoal.id: makePlan(
                goalID: malformedGoal.id,
                allocationIDs: [duplicateAllocationID, duplicateAllocationID],
                currencies: ["BTC", "ETH"]
            )
        ]
        let coordinator = LegacyFinishedAllocationReviewCoordinator()

        #expect(
            throws: LegacyFinishedAllocationReviewError.duplicateAllocationID(
                goalID: malformedGoal.id,
                allocationID: duplicateAllocationID
            )
        ) {
            try coordinator.load(goals: [validGoal, malformedGoal]) { plans[$0.id]! }
        }

        #expect(coordinator.plansByGoalID.isEmpty)
        #expect(coordinator.isPresented == false)
    }

    @Test("allocations changed reloads updated plans and clears stale decisions")
    func allocationsChangedReloadsUpdatedPlans() async throws {
        let goal = makeFinishedGoal(name: "Updated review")
        let allocationID = UUID()
        let initialPlan = makePlan(
            goalID: goal.id,
            allocationIDs: [allocationID],
            currencies: ["USDT"],
            amounts: [10]
        )
        let updatedPlan = makePlan(
            goalID: goal.id,
            allocationIDs: [allocationID],
            currencies: ["USDT"],
            amounts: [25]
        )
        let coordinator = LegacyFinishedAllocationReviewCoordinator()
        var prepareCallCount = 0

        try coordinator.load(goals: [goal]) { _ in
            defer { prepareCallCount += 1 }
            return prepareCallCount == 0 ? initialPlan : updatedPlan
        }
        coordinator.choose(
            goalID: goal.id,
            allocationID: allocationID,
            settlement: .keepAsSpent
        )

        await #expect(throws: GoalCompletionSettlementError.allocationsChanged(goal.id)) {
            try await coordinator.apply { _ in
                throw GoalCompletionSettlementError.allocationsChanged(goal.id)
            }
        }

        #expect(prepareCallCount == 2)
        #expect(coordinator.plansByGoalID[goal.id]?.items.first?.input.amount == 25)
        #expect(coordinator.decisions.isEmpty)
        #expect(coordinator.isPresented)
        #expect(coordinator.canApply == false)
        #expect(coordinator.errorMessage == GoalCompletionSettlementError.allocationsChanged(goal.id).localizedDescription)
    }

    @Test("repeated allocations changes always reload the latest whole-goal plan")
    func repeatedAllocationsChangesReloadAgain() async throws {
        let goal = makeFinishedGoal(name: "Repeated update")
        let allocationID = UUID()
        let plans = [10.0, 20.0, 30.0].map {
            makePlan(
                goalID: goal.id,
                allocationIDs: [allocationID],
                currencies: ["BTC"],
                amounts: [$0]
            )
        }
        let coordinator = LegacyFinishedAllocationReviewCoordinator()
        var prepareCallCount = 0

        try coordinator.load(goals: [goal]) { _ in
            let plan = plans[min(prepareCallCount, plans.count - 1)]
            prepareCallCount += 1
            return plan
        }

        for expectedAmount in [20.0, 30.0] {
            coordinator.choose(
                goalID: goal.id,
                allocationID: allocationID,
                settlement: .keepAsSpent
            )
            await #expect(throws: GoalCompletionSettlementError.allocationsChanged(goal.id)) {
                try await coordinator.apply { _ in
                    throw GoalCompletionSettlementError.allocationsChanged(goal.id)
                }
            }
            #expect(coordinator.plansByGoalID[goal.id]?.items.first?.input.amount == expectedAmount)
            #expect(coordinator.decisions.isEmpty)
            #expect(coordinator.canApply == false)
        }

        #expect(prepareCallCount == 3)
        #expect(coordinator.isPresented)
    }

    @Test("generic apply failure keeps choices for retry")
    func genericFailureKeepsChoices() async throws {
        let goal = makeFinishedGoal(name: "Retry same choices")
        let allocationID = UUID()
        let plan = makePlan(goalID: goal.id, allocationIDs: [allocationID], currencies: ["USDT"])
        let coordinator = LegacyFinishedAllocationReviewCoordinator()

        try coordinator.load(goals: [goal]) { _ in plan }
        coordinator.choose(
            goalID: goal.id,
            allocationID: allocationID,
            settlement: .balanceAlreadyDecreased
        )

        await #expect(throws: TestFailure.generic) {
            try await coordinator.apply { _ in throw TestFailure.generic }
        }

        #expect(coordinator.plansByGoalID[goal.id] == plan)
        #expect(
            coordinator.decisions[
                LegacyFinishedAllocationDecisionKey(goalID: goal.id, allocationID: allocationID)
            ] == .balanceAlreadyDecreased
        )
        #expect(coordinator.isPresented)
        #expect(coordinator.canApply)
    }

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

    @Test("settlement choice identifiers stay unique when allocation UUIDs repeat across goals")
    func settlementChoiceAccessibilityIdentifiersIncludeGoalAndAllocation() {
        let allocationID = UUID()
        let firstGoalID = UUID()
        let secondGoalID = UUID()

        let firstIdentifier = LegacyFinishedAllocationReviewSheet
            .settlementChoiceAccessibilityIdentifier(
                goalID: firstGoalID,
                allocationID: allocationID
            )
        let secondIdentifier = LegacyFinishedAllocationReviewSheet
            .settlementChoiceAccessibilityIdentifier(
                goalID: secondGoalID,
                allocationID: allocationID
            )

        #expect(firstIdentifier != secondIdentifier)
        #expect(firstIdentifier.contains(firstGoalID.uuidString))
        #expect(firstIdentifier.contains(allocationID.uuidString))
        #expect(secondIdentifier.contains(secondGoalID.uuidString))
        #expect(secondIdentifier.contains(allocationID.uuidString))
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
        currencies: [String],
        amounts: [Double]? = nil,
        origin: GoalCompletionSettlementOrigin = .legacyReview
    ) -> GoalCompletionSettlementPlan {
        let resolvedAmounts = amounts ?? allocationIDs.indices.map { Double($0 + 1) * 10 }
        return GoalCompletionSettlementPlanner().makePlan(
            goalID: goalID,
            origin: origin,
            allocations: zip(zip(allocationIDs, currencies), resolvedAmounts).enumerated().map { index, pair in
                GoalCompletionAllocationInput(
                    allocationID: pair.0.0,
                    assetID: UUID(),
                    assetCurrency: pair.0.1,
                    amount: pair.1,
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
