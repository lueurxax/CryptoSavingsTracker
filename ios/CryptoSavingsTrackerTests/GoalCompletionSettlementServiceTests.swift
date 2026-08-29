import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct GoalCompletionSettlementServiceTests {
    private final class SpyNotificationManager: NotificationManager {
        var cancelledGoalIDs: [UUID] = []

        init() {
            super.init(runtimeMode: .publicMVP, isUITestRunProvider: { false })
        }

        override func cancelNotifications(for goal: Goal) async {
            cancelledGoalIDs.append(goal.id)
        }
    }

    @Test("manual completion snapshots and retains allocation")
    func manualCompletionSnapshotsAndRetainsAllocation() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Manual")
        context.insert(goal)
        let fixture = addAllocation(
            to: goal,
            currency: "USD",
            amount: 40,
            manualTransactions: [100],
            in: context
        )
        try context.save()

        let service = GoalCompletionSettlementService(modelContext: context)
        let plan = try service.prepareNewCompletion(for: goal)
        let timestamp = Date(timeIntervalSince1970: 10_000)
        let snapshot = try await service.apply(
            GoalCompletionSettlementCommand(plan: plan, decisions: []),
            at: timestamp
        )

        #expect(goal.lifecycleStatus == .finished)
        #expect(goal.lifecycleStatusChangedAt == timestamp)
        #expect(goal.completionSnapshot == snapshot)
        #expect(snapshot.goalCompletedAt == timestamp)
        #expect(snapshot.snapshotCreatedAt == timestamp)
        #expect(snapshot.entries == [
            GoalCompletionSnapshot.Entry(
                allocationID: fixture.allocation.id,
                assetID: fixture.asset.id,
                assetCurrency: "USD",
                amount: 40,
                accountingMode: .manual,
                settlement: .keepAsSpent,
                bestKnownBalance: 100,
                balanceCapturedAt: snapshot.entries.first?.balanceCapturedAt,
                balanceTiming: .completionTime
            )
        ])
        #expect((goal.allocations ?? []).map(\.id) == [fixture.allocation.id])
        #expect((fixture.asset.allocations ?? []).map(\.id) == [fixture.allocation.id])
    }

    @Test("on-chain completion releases allocation and writes one zero history row")
    func onChainCompletionReleasesAllocationAndWritesHistory() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "On-chain")
        context.insert(goal)
        let fixture = addAllocation(
            to: goal,
            currency: "USDT",
            amount: 35,
            address: "0xabc",
            chainID: "ethereum",
            in: context
        )
        try context.save()
        let baselineHistoryCount = try context.fetchCount(FetchDescriptor<AllocationHistory>())
        let timestamp = Date(timeIntervalSince1970: 20_000)
        let service = GoalCompletionSettlementService(modelContext: context)

        let plan = try service.prepareNewCompletion(for: goal)
        let snapshot = try await service.apply(
            GoalCompletionSettlementCommand(plan: plan, decisions: []),
            at: timestamp
        )

        #expect(snapshot.entries.first?.settlement == .balanceAlreadyDecreased)
        #expect(snapshot.entries.first?.accountingMode == .onChain)
        #expect(snapshot.entries.first?.bestKnownBalance == nil)
        #expect((goal.allocations ?? []).isEmpty)
        #expect((fixture.asset.allocations ?? []).isEmpty)
        let allocations = try context.fetch(FetchDescriptor<AssetAllocation>())
        #expect(!allocations.contains { $0.id == fixture.allocation.id })
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        #expect(histories.count == baselineHistoryCount + 1)
        let releaseHistory = histories.first { $0.goalId == goal.id && $0.assetId == fixture.asset.id && $0.amount == 0 }
        #expect(releaseHistory?.timestamp == timestamp)
    }

    @Test("mixed completion applies the explicit choice")
    func mixedCompletionAppliesExplicitChoice() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Mixed")
        context.insert(goal)
        let fixture = addAllocation(
            to: goal,
            currency: "BTC",
            amount: 0.1,
            address: "bc1qtracked",
            chainID: "bitcoin",
            manualTransactions: [0.2],
            in: context
        )
        try context.save()
        let service = GoalCompletionSettlementService(modelContext: context)
        let plan = try service.prepareNewCompletion(for: goal)
        #expect(plan.unresolvedAllocationIDs == [fixture.allocation.id])

        let snapshot = try await service.apply(
            GoalCompletionSettlementCommand(
                plan: plan,
                decisions: [
                    GoalCompletionSettlementDecision(
                        allocationID: fixture.allocation.id,
                        settlement: .keepAsSpent
                    )
                ]
            )
        )

        #expect(snapshot.entries.first?.accountingMode == .mixed)
        #expect(snapshot.entries.first?.settlement == .keepAsSpent)
        #expect((goal.allocations ?? []).contains { $0.id == fixture.allocation.id })
    }

    @Test("legacy review requires choices for every allocation across the goal")
    func legacyReviewRequiresChoicesForEveryAllocation() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Legacy")
        goal.markFinished(at: Date(timeIntervalSince1970: 1_000))
        context.insert(goal)
        let manual = addAllocation(
            to: goal,
            currency: "USD",
            amount: 10,
            manualTransactions: [100],
            in: context
        )
        let onChain = addAllocation(
            to: goal,
            currency: "USDT",
            amount: 20,
            address: "0xlegacy",
            chainID: "ethereum",
            in: context
        )
        let mixed = addAllocation(
            to: goal,
            currency: "BTC",
            amount: 0.1,
            address: "bc1qlegacy",
            chainID: "bitcoin",
            manualTransactions: [0.2],
            in: context
        )
        try context.save()

        let plan = try GoalCompletionSettlementService(modelContext: context).prepareLegacyReview(for: goal)

        #expect(plan.origin == .legacyReview)
        #expect(Set(plan.unresolvedAllocationIDs) == Set([
            manual.allocation.id,
            onChain.allocation.id,
            mixed.allocation.id
        ]))
    }

    @Test("batch legacy review saves all reviewed goals once")
    func batchLegacyReviewSavesAllGoalsOnce() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let firstGoal = makeGoal(name: "First Legacy")
        let secondGoal = makeGoal(name: "Second Legacy")
        firstGoal.markFinished(at: Date(timeIntervalSince1970: 1_000))
        secondGoal.markFinished(at: Date(timeIntervalSince1970: 2_000))
        context.insert(firstGoal)
        context.insert(secondGoal)
        let first = addAllocation(
            to: firstGoal,
            currency: "USD",
            amount: 10,
            manualTransactions: [50],
            in: context
        )
        let second = addAllocation(
            to: secondGoal,
            currency: "EUR",
            amount: 20,
            manualTransactions: [60],
            in: context
        )
        try context.save()
        let notificationManager = SpyNotificationManager()
        var saveCount = 0
        let service = GoalCompletionSettlementService(
            modelContext: context,
            notificationManager: notificationManager,
            save: {
                saveCount += 1
                try context.save()
            },
            rollback: { context.rollback() }
        )
        let commands = try [
            GoalCompletionSettlementCommand(
                plan: service.prepareLegacyReview(for: firstGoal),
                decisions: [
                    GoalCompletionSettlementDecision(
                        allocationID: first.allocation.id,
                        settlement: .keepAsSpent
                    )
                ]
            ),
            GoalCompletionSettlementCommand(
                plan: service.prepareLegacyReview(for: secondGoal),
                decisions: [
                    GoalCompletionSettlementDecision(
                        allocationID: second.allocation.id,
                        settlement: .keepAsSpent
                    )
                ]
            )
        ]
        let reviewedAt = Date(timeIntervalSince1970: 30_000)

        let snapshots = try await service.applyBatch(commands, at: reviewedAt)

        #expect(saveCount == 1)
        #expect(Set(snapshots.map(\.goalID)) == Set([firstGoal.id, secondGoal.id]))
        #expect(snapshots.allSatisfy { $0.snapshotCreatedAt == reviewedAt })
        #expect(snapshots.allSatisfy { $0.entries.allSatisfy { $0.balanceTiming == .reviewTime } })
        #expect(firstGoal.completionSnapshot != nil)
        #expect(secondGoal.completionSnapshot != nil)
        #expect(Set(notificationManager.cancelledGoalIDs) == Set([firstGoal.id, secondGoal.id]))
    }

    @Test("allocation change after planning rejects without mutation")
    func allocationChangeAfterPlanningRejectsWithoutMutation() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Changed")
        context.insert(goal)
        let fixture = addAllocation(
            to: goal,
            currency: "USD",
            amount: 25,
            manualTransactions: [100],
            in: context
        )
        try context.save()
        let service = GoalCompletionSettlementService(modelContext: context)
        let plan = try service.prepareNewCompletion(for: goal)
        fixture.allocation.updateAmount(30)
        try context.save()
        let baselineHistoryCount = try context.fetchCount(FetchDescriptor<AllocationHistory>())

        await #expect(throws: GoalCompletionSettlementError.allocationsChanged(goal.id)) {
            try await service.apply(GoalCompletionSettlementCommand(plan: plan, decisions: []))
        }

        #expect(goal.lifecycleStatus == .active)
        #expect(goal.completionSnapshotData == nil)
        #expect(fixture.allocation.amountValue == 30)
        #expect(try context.fetchCount(FetchDescriptor<AllocationHistory>()) == baselineHistoryCount)
    }

    @Test("asset currency change after planning rejects without mutation")
    func assetCurrencyChangeAfterPlanningRejectsWithoutMutation() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Changed Currency")
        context.insert(goal)
        let fixture = addAllocation(
            to: goal,
            currency: "USDT",
            amount: 25,
            address: "0xcurrency",
            chainID: "ethereum",
            in: context
        )
        try context.save()
        let service = GoalCompletionSettlementService(modelContext: context)
        let plan = try service.prepareNewCompletion(for: goal)
        fixture.asset.currency = "EUR"
        try context.save()
        let baselineHistoryCount = try context.fetchCount(FetchDescriptor<AllocationHistory>())

        await #expect(throws: GoalCompletionSettlementError.allocationsChanged(goal.id)) {
            try await service.apply(GoalCompletionSettlementCommand(plan: plan, decisions: []))
        }

        #expect(goal.lifecycleStatus == .active)
        #expect(goal.completionSnapshotData == nil)
        #expect(fixture.allocation.amountValue == 25)
        #expect(try context.fetchCount(FetchDescriptor<AllocationHistory>()) == baselineHistoryCount)
    }

    @Test("second apply returns the existing snapshot without duplicate history")
    func secondApplyReturnsExistingSnapshotWithoutDuplicateHistory() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Idempotent")
        context.insert(goal)
        addAllocation(
            to: goal,
            currency: "USDT",
            amount: 35,
            address: "0xidempotent",
            chainID: "ethereum",
            in: context
        )
        try context.save()
        let baselineHistoryCount = try context.fetchCount(FetchDescriptor<AllocationHistory>())
        let notificationManager = SpyNotificationManager()
        var saveCount = 0
        let service = GoalCompletionSettlementService(
            modelContext: context,
            notificationManager: notificationManager,
            save: {
                saveCount += 1
                try context.save()
            },
            rollback: { context.rollback() }
        )
        let command = GoalCompletionSettlementCommand(
            plan: try service.prepareNewCompletion(for: goal),
            decisions: []
        )
        let first = try await service.apply(command, at: Date(timeIntervalSince1970: 40_000))
        let historyCountAfterFirstApply = try context.fetchCount(FetchDescriptor<AllocationHistory>())

        let second = try await service.apply(command, at: Date(timeIntervalSince1970: 50_000))

        #expect(second == first)
        #expect(saveCount == 1)
        #expect(historyCountAfterFirstApply == baselineHistoryCount + 1)
        #expect(try context.fetchCount(FetchDescriptor<AllocationHistory>()) == historyCountAfterFirstApply)
        #expect(notificationManager.cancelledGoalIDs == [goal.id])
    }

    @Test("save failure rolls lifecycle snapshot allocations history and execution tracking back")
    func saveFailureRollsEveryMutationBack() async throws {
        enum ForcedSaveFailure: Error { case expected }

        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = makeGoal(name: "Rollback")
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Date(timeIntervalSince1970: 1_000)
        goal.firstReminderDate = Date(timeIntervalSince1970: 2_000)
        context.insert(goal)
        let fixture = addAllocation(
            to: goal,
            currency: "USDT",
            amount: 35,
            address: "0xrollback",
            chainID: "ethereum",
            in: context
        )
        let executionRecord = MonthlyExecutionRecord(
            monthLabel: MonthlyExecutionRecord.monthLabel(from: Date()),
            goalIds: [goal.id]
        )
        executionRecord.status = .executing
        context.insert(executionRecord)
        try context.save()
        let baselineHistoryCount = try context.fetchCount(FetchDescriptor<AllocationHistory>())
        let notificationManager = SpyNotificationManager()
        let service = GoalCompletionSettlementService(
            modelContext: context,
            notificationManager: notificationManager,
            save: { throw ForcedSaveFailure.expected },
            rollback: { context.rollback() }
        )
        let command = GoalCompletionSettlementCommand(
            plan: try service.prepareNewCompletion(for: goal),
            decisions: []
        )

        await #expect(throws: ForcedSaveFailure.expected) {
            try await service.apply(command)
        }

        #expect(goal.lifecycleStatus == .active)
        #expect(goal.lifecycleStatusChangedAt == nil)
        #expect(goal.completionSnapshotData == nil)
        #expect(goal.reminderFrequency == ReminderFrequency.weekly.rawValue)
        #expect(goal.reminderTime == Date(timeIntervalSince1970: 1_000))
        #expect(goal.firstReminderDate == Date(timeIntervalSince1970: 2_000))
        #expect(executionRecord.goalIds == [goal.id])
        #expect(try context.fetchCount(FetchDescriptor<AllocationHistory>()) == baselineHistoryCount)
        let allocations = try context.fetch(FetchDescriptor<AssetAllocation>())
        #expect(allocations.contains { $0.id == fixture.allocation.id })
        #expect(notificationManager.cancelledGoalIDs.isEmpty)
    }

    private func makeGoal(name: String) -> Goal {
        Goal(
            name: name,
            currency: "USD",
            targetAmount: 100,
            deadline: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    @discardableResult
    private func addAllocation(
        to goal: Goal,
        currency: String,
        amount: Double,
        address: String? = nil,
        chainID: String? = nil,
        manualTransactions: [Double] = [],
        in context: ModelContext
    ) -> (asset: Asset, allocation: AssetAllocation) {
        let asset = Asset(currency: currency, address: address, chainId: chainID)
        context.insert(asset)
        for amount in manualTransactions {
            let transaction = Transaction(amount: amount, asset: asset, source: .manual)
            asset.transactions = (asset.transactions ?? []) + [transaction]
            context.insert(transaction)
        }
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: amount)
        asset.allocations = (asset.allocations ?? []) + [allocation]
        goal.allocations = (goal.allocations ?? []) + [allocation]
        context.insert(allocation)
        return (asset, allocation)
    }
}
