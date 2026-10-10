import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct PersistenceMutationAtomicityTests {
    private enum ForcedSaveError: Error {
        case failed
    }

    @MainActor
    private final class FailFirstSave {
        private let modelContext: ModelContext
        private let failuresBeforeSuccess: Int
        private(set) var attempts = 0

        init(modelContext: ModelContext, failuresBeforeSuccess: Int = 1) {
            self.modelContext = modelContext
            self.failuresBeforeSuccess = failuresBeforeSuccess
        }

        func save() throws {
            attempts += 1
            if attempts <= failuresBeforeSuccess {
                throw ForcedSaveError.failed
            }
            try modelContext.save()
        }
    }

    private final class NotificationFlag: @unchecked Sendable {
        var wasPosted = false
    }

    @MainActor
    private final class DeferredSyncProbe {
        var receivedContext: ModelContext?
        var didRun = false
    }

    private enum RetryAction: Equatable {
        case deleteTransaction
    }

    @Test("Mutation failure state retains a retry action until a retry succeeds")
    func mutationFailureStateSupportsVisibleRetry() {
        var state = PersistenceMutationRetryState<RetryAction>()

        let firstResult = state.perform(.deleteTransaction) {
            throw ForcedSaveError.failed
        }

        #expect(firstResult == false)
        #expect(state.action == .deleteTransaction)
        #expect(state.errorMessage?.isEmpty == false)

        var retryAttempts = 0
        let retryResult = state.retry { action in
            #expect(action == .deleteTransaction)
            retryAttempts += 1
        }

        #expect(retryResult)
        #expect(retryAttempts == 1)
        #expect(state.action == nil)
        #expect(state.errorMessage == nil)
    }

    @Test("Failed transaction creation rolls back its graph and retries exactly once")
    func transactionCreateFailureIsAtomicAndRetrySafe() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Dedicated Goal")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(
            amount: 100,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_000),
            comment: "Opening balance"
        )
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 100)
        asset.transactions = [openingTransaction]
        asset.allocations = [allocation]
        goal.allocations = [allocation]

        context.insert(goal)
        context.insert(asset)
        context.insert(openingTransaction)
        context.insert(allocation)
        try context.saveWithRelationships()

        let progressSignal = NotificationFlag()
        let sharedSignal = NotificationFlag()
        let progressToken = NotificationCenter.default.addObserver(
            forName: .goalProgressRefreshed,
            object: nil,
            queue: nil
        ) { _ in
            progressSignal.wasPosted = true
        }
        let sharedToken = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { _ in
            sharedSignal.wasPosted = true
        }
        defer {
            NotificationCenter.default.removeObserver(progressToken)
            NotificationCenter.default.removeObserver(sharedToken)
        }

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard(),
            saveChanges: failFirstSave.save
        )
        let contributionDate = Date(timeIntervalSince1970: 2_000)

        #expect(throws: PersistenceMutationError.self) {
            _ = try service.createTransaction(
                for: asset,
                amount: 25,
                date: contributionDate,
                comment: "Retryable contribution",
                autoAllocateGoalId: nil
            )
        }

        context.processPendingChanges()
        #expect((asset.transactions ?? []).map(\.id) == [openingTransaction.id])
        #expect(allocation.amountValue == 100)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AllocationHistory>()).isEmpty)
        #expect(progressSignal.wasPosted == false)
        #expect(sharedSignal.wasPosted == false)

        let savedTransaction = try service.createTransaction(
            for: asset,
            amount: 25,
            date: contributionDate,
            comment: "Retryable contribution",
            autoAllocateGoalId: nil
        )

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 2)
        #expect((asset.transactions ?? []).filter { $0.id == savedTransaction.id }.count == 1)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).count == 1)
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        #expect(histories.count == 1)
        #expect(histories.first?.amount == 125)
        #expect(histories.first?.timestamp == contributionDate)
        #expect(allocation.amountValue == 125)
        #expect(progressSignal.wasPosted)
        #expect(sharedSignal.wasPosted)
    }

    @Test("Failed auto-allocation transaction creation removes the new allocation graph before retry")
    func transactionCreateAutoAllocationFailureIsAtomicAndRetrySafe() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Auto Allocation Goal")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: 100, asset: asset)
        asset.transactions = [openingTransaction]
        context.insert(goal)
        context.insert(asset)
        context.insert(openingTransaction)
        try context.saveWithRelationships()

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard(),
            saveChanges: failFirstSave.save
        )
        let contributionDate = Date(timeIntervalSince1970: 3_000)

        #expect(throws: PersistenceMutationError.self) {
            _ = try service.createTransaction(
                for: asset,
                amount: 25,
                date: contributionDate,
                comment: "Auto allocation",
                autoAllocateGoalId: goal.id
            )
        }

        context.processPendingChanges()
        #expect((asset.transactions ?? []).map(\.id) == [openingTransaction.id])
        #expect((asset.allocations ?? []).isEmpty)
        #expect((goal.allocations ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AllocationHistory>()).isEmpty)

        _ = try service.createTransaction(
            for: asset,
            amount: 25,
            date: contributionDate,
            comment: "Auto allocation",
            autoAllocateGoalId: goal.id
        )

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 2)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AllocationHistory>()).count == 1)
        #expect(asset.allocations?.first?.goal?.id == goal.id)
        #expect(asset.allocations?.first?.amountValue == 25)
    }

    @Test("Missing auto-allocation goal rolls back the staged transaction before save")
    func transactionCreateMissingAutoAllocationGoalIsAtomic() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: 100, asset: asset)
        asset.transactions = [openingTransaction]
        context.insert(asset)
        context.insert(openingTransaction)
        try context.saveWithRelationships()

        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard()
        )

        #expect(throws: PersistenceMutationError.self) {
            _ = try service.createTransaction(
                for: asset,
                amount: 25,
                date: Date(timeIntervalSince1970: 4_000),
                comment: "Missing goal",
                autoAllocateGoalId: UUID()
            )
        }

        context.processPendingChanges()
        #expect((asset.transactions ?? []).map(\.id) == [openingTransaction.id])
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AllocationHistory>()).isEmpty)
    }

    @Test("Failed transaction deletion keeps the row and retries without duplicate effects")
    func transactionDeleteFailureIsAtomicAndRetrySafe() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Transaction Goal")
        let asset = Asset(currency: "USD")
        let transaction = Transaction(amount: 80, asset: asset)
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 50)
        asset.transactions = [transaction]
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        context.insert(goal)
        context.insert(asset)
        context.insert(transaction)
        context.insert(allocation)
        try context.saveWithRelationships()

        let progressSignal = NotificationFlag()
        let token = NotificationCenter.default.addObserver(
            forName: .goalProgressRefreshed,
            object: nil,
            queue: nil
        ) { _ in
            progressSignal.wasPosted = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard(),
            saveChanges: failFirstSave.save
        )

        #expect(throws: PersistenceMutationError.self) {
            try service.deleteTransaction(transaction)
        }

        context.processPendingChanges()
        #expect((asset.transactions ?? []).map(\.id) == [transaction.id])
        #expect(transaction.asset?.id == asset.id)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).map(\.id) == [transaction.id])
        #expect(progressSignal.wasPosted == false)

        try service.deleteTransaction(transaction)

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 2)
        #expect((asset.transactions ?? []).isEmpty)
        let remainingTransactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(remainingTransactions.isEmpty)
        #expect(progressSignal.wasPosted)
    }

    @Test("Deleting an auto-allocated deposit replays its linked allocation history")
    func transactionDeleteReversesLinkedDepositAllocation() throws {
        let fixture = try makeDedicatedTransactionFixture()
        let service = TransactionMutationService(
            modelContext: fixture.context,
            accessGuard: AtomicityAllowAllAccessGuard()
        )
        let contributionDate = Date(timeIntervalSince1970: 5_000)

        let deposit = try service.createTransaction(
            for: fixture.asset,
            amount: 20,
            date: contributionDate,
            comment: "Linked deposit",
            autoAllocateGoalId: nil
        )
        #expect(fixture.allocation.amountValue == 120)
        let linkedBeforeDelete = try fixture.context
            .fetch(FetchDescriptor<AllocationHistory>())
            .filter { $0.sourceTransactionId == deposit.id }
        #expect(linkedBeforeDelete.count == 1)

        try service.deleteTransaction(deposit)

        fixture.context.processPendingChanges()
        #expect(fixture.allocation.amountValue == 100)
        #expect(
            try fixture.context.fetch(FetchDescriptor<AllocationHistory>())
                .allSatisfy { $0.sourceTransactionId != deposit.id }
        )
        #expect(
            try fixture.context.fetch(FetchDescriptor<Transaction>())
                .map(\.id) == [fixture.openingTransaction.id]
        )
    }

    @Test("Deleting an auto-allocated withdrawal restores the dedicated target")
    func transactionDeleteReversesLinkedWithdrawalAllocation() throws {
        let fixture = try makeDedicatedTransactionFixture()
        let service = TransactionMutationService(
            modelContext: fixture.context,
            accessGuard: AtomicityAllowAllAccessGuard()
        )
        let withdrawal = try service.createTransaction(
            for: fixture.asset,
            amount: -20,
            date: Date(timeIntervalSince1970: 6_000),
            comment: "Linked withdrawal",
            autoAllocateGoalId: nil
        )
        #expect(fixture.allocation.amountValue == 80)

        try service.deleteTransaction(withdrawal)

        fixture.context.processPendingChanges()
        #expect(fixture.allocation.amountValue == 100)
        #expect(
            try fixture.context.fetch(FetchDescriptor<AllocationHistory>())
                .allSatisfy { $0.sourceTransactionId != withdrawal.id }
        )
    }

    @Test("Deleting a clamped auto-allocated withdrawal restores its exact prior target")
    func transactionDeleteReversesClampedLinkedWithdrawalAllocation() throws {
        let fixture = try makeDedicatedTransactionFixture(openingAmount: 10)
        let service = TransactionMutationService(
            modelContext: fixture.context,
            accessGuard: AtomicityAllowAllAccessGuard()
        )
        let withdrawal = try service.createTransaction(
            for: fixture.asset,
            amount: -20,
            date: Date(timeIntervalSince1970: 6_500),
            comment: "Clamped linked withdrawal",
            autoAllocateGoalId: nil
        )
        #expect(fixture.asset.currentAmount == -10)
        #expect(fixture.allocation.amountValue == 0)

        try service.deleteTransaction(withdrawal)

        fixture.context.processPendingChanges()
        #expect(fixture.asset.currentAmount == 10)
        #expect(fixture.allocation.amountValue == 10)
        #expect(
            try fixture.context.fetch(FetchDescriptor<AllocationHistory>())
                .allSatisfy { $0.sourceTransactionId != withdrawal.id }
        )
    }

    @Test("Deleting one of two same-time linked deposits replays only the survivor")
    func transactionDeleteReplaysSameTimestampLinkedHistoriesDeterministically() throws {
        let fixture = try makeDedicatedTransactionFixture()
        let service = TransactionMutationService(
            modelContext: fixture.context,
            accessGuard: AtomicityAllowAllAccessGuard()
        )
        let timestamp = Date(timeIntervalSince1970: 7_000)
        let first = try service.createTransaction(
            for: fixture.asset,
            amount: 10,
            date: timestamp,
            comment: "First",
            autoAllocateGoalId: nil
        )
        let second = try service.createTransaction(
            for: fixture.asset,
            amount: 20,
            date: timestamp,
            comment: "Second",
            autoAllocateGoalId: nil
        )
        #expect(fixture.allocation.amountValue == 130)

        try service.deleteTransaction(first)

        fixture.context.processPendingChanges()
        #expect(fixture.allocation.amountValue == 120)
        let histories = try fixture.context
            .fetch(FetchDescriptor<AllocationHistory>())
            .filter { $0.assetId == fixture.asset.id }
        #expect(histories.count == 1)
        #expect(histories.first?.sourceTransactionId == second.id)
        #expect(histories.first?.amount == 120)
    }

    @Test("Deleting an explicitly allocated transaction reverses only its selected goal")
    func transactionDeleteReversesExplicitMultiGoalAllocation() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let firstGoal = TestDataFactory.createSampleGoal(name: "Explicit target")
        let secondGoal = TestDataFactory.createSampleGoal(name: "Independent target")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: 100, asset: asset)
        let firstAllocation = AssetAllocation(
            asset: asset,
            goal: firstGoal,
            amount: 40
        )
        let secondAllocation = AssetAllocation(
            asset: asset,
            goal: secondGoal,
            amount: 30
        )
        asset.transactions = [openingTransaction]
        asset.allocations = [firstAllocation, secondAllocation]
        firstGoal.allocations = [firstAllocation]
        secondGoal.allocations = [secondAllocation]
        for model in [firstGoal, secondGoal] {
            context.insert(model)
        }
        context.insert(asset)
        context.insert(openingTransaction)
        context.insert(firstAllocation)
        context.insert(secondAllocation)
        try context.saveWithRelationships()
        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard()
        )

        let deposit = try service.createTransaction(
            for: asset,
            amount: 10,
            date: Date(timeIntervalSince1970: 7_500),
            comment: "Explicit contribution",
            autoAllocateGoalId: firstGoal.id
        )
        #expect(firstAllocation.amountValue == 50)
        #expect(secondAllocation.amountValue == 30)

        try service.deleteTransaction(deposit)

        #expect(firstAllocation.amountValue == 40)
        #expect(secondAllocation.amountValue == 30)
        #expect(
            try context.fetch(FetchDescriptor<AllocationHistory>())
                .allSatisfy { $0.sourceTransactionId != deposit.id }
        )
    }

    @Test("Legacy unlinked allocation history blocks deletion on a multi-goal asset")
    func transactionDeleteFailsClosedForLegacyExplicitMultiGoalAllocation() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let firstGoal = TestDataFactory.createSampleGoal(name: "Legacy target")
        let secondGoal = TestDataFactory.createSampleGoal(name: "Independent target")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: 100, asset: asset)
        let firstAllocation = AssetAllocation(
            asset: asset,
            goal: firstGoal,
            amount: 40
        )
        let secondAllocation = AssetAllocation(
            asset: asset,
            goal: secondGoal,
            amount: 30
        )
        asset.transactions = [openingTransaction]
        asset.allocations = [firstAllocation, secondAllocation]
        firstGoal.allocations = [firstAllocation]
        secondGoal.allocations = [secondAllocation]
        for model in [firstGoal, secondGoal] {
            context.insert(model)
        }
        context.insert(asset)
        context.insert(openingTransaction)
        context.insert(firstAllocation)
        context.insert(secondAllocation)
        try context.saveWithRelationships()
        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard()
        )
        let timestamp = Date(timeIntervalSince1970: 7_750)
        let deposit = try service.createTransaction(
            for: asset,
            amount: 10,
            date: timestamp,
            comment: "Legacy explicit contribution",
            autoAllocateGoalId: firstGoal.id
        )
        let legacyHistory = try #require(
            try context.fetch(FetchDescriptor<AllocationHistory>())
                .first { $0.sourceTransactionId == deposit.id }
        )
        legacyHistory.sourceTransactionId = nil
        legacyHistory.sourcePreviousAmount = nil
        try context.save()

        #expect(throws: PersistenceMutationError.self) {
            try service.deleteTransaction(deposit)
        }

        context.processPendingChanges()
        #expect(firstAllocation.amountValue == 50)
        #expect(secondAllocation.amountValue == 30)
        #expect(
            try context.fetch(FetchDescriptor<Transaction>())
                .contains { $0.id == deposit.id }
        )
        #expect(
            try context.fetch(FetchDescriptor<AllocationHistory>())
                .contains { $0.id == legacyHistory.id }
        )
        #expect(context.hasChanges == false)
    }

    @Test("Failed linked transaction deletion restores row allocation and history")
    func transactionDeleteLinkedAllocationFailureRollsBackWholeGraph() throws {
        let fixture = try makeDedicatedTransactionFixture()
        let createService = TransactionMutationService(
            modelContext: fixture.context,
            accessGuard: AtomicityAllowAllAccessGuard()
        )
        let deposit = try createService.createTransaction(
            for: fixture.asset,
            amount: 20,
            date: Date(timeIntervalSince1970: 8_000),
            comment: "Rollback linked deposit",
            autoAllocateGoalId: nil
        )
        let failingService = TransactionMutationService(
            modelContext: fixture.context,
            accessGuard: AtomicityAllowAllAccessGuard(),
            saveChanges: { throw ForcedSaveError.failed }
        )

        #expect(throws: PersistenceMutationError.self) {
            try failingService.deleteTransaction(deposit)
        }

        fixture.context.processPendingChanges()
        #expect(fixture.allocation.amountValue == 120)
        #expect(
            try fixture.context.fetch(FetchDescriptor<Transaction>())
                .contains { $0.id == deposit.id }
        )
        let linked = try fixture.context
            .fetch(FetchDescriptor<AllocationHistory>())
            .filter { $0.sourceTransactionId == deposit.id }
        #expect(linked.count == 1)
        #expect(linked.first?.amount == 120)
    }

    @Test("Deleting an unsaved transaction cancels only that pending insert")
    func transactionDeleteHandlesPendingInsert() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let asset = Asset(currency: "USD")
        context.insert(asset)
        try context.save()

        let pendingTransaction = Transaction(amount: 15, asset: asset)
        asset.transactions = [pendingTransaction]
        context.insert(pendingTransaction)

        let unrelatedGoal = TestDataFactory.createSampleGoal(name: "Pending unrelated goal")
        context.insert(unrelatedGoal)

        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard()
        )

        try service.deleteTransaction(pendingTransaction)

        context.processPendingChanges()
        #expect((asset.transactions ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
        #expect(
            try context.fetch(FetchDescriptor<Goal>()).contains {
                $0.id == unrelatedGoal.id
            }
        )
    }

    private func makeDedicatedTransactionFixture(
        openingAmount: Double = 100
    ) throws -> (
        context: ModelContext,
        goal: Goal,
        asset: Asset,
        openingTransaction: Transaction,
        allocation: AssetAllocation
    ) {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Linked allocation goal")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: openingAmount, asset: asset)
        let allocation = AssetAllocation(
            asset: asset,
            goal: goal,
            amount: openingAmount
        )
        asset.transactions = [openingTransaction]
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        context.insert(goal)
        context.insert(asset)
        context.insert(openingTransaction)
        context.insert(allocation)
        try context.saveWithRelationships()
        return (context, goal, asset, openingTransaction, allocation)
    }

    @Test("Failed allocation replacement restores rows, amounts, relationships, and retry history")
    func allocationUpdateFailureIsAtomicAndRetrySafe() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let firstGoal = TestDataFactory.createSampleGoal(name: "First Goal")
        let removedGoal = TestDataFactory.createSampleGoal(name: "Removed Goal")
        let insertedGoal = TestDataFactory.createSampleGoal(name: "Inserted Goal")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: 100, asset: asset)
        let firstAllocation = AssetAllocation(asset: asset, goal: firstGoal, amount: 40)
        let removedAllocation = AssetAllocation(asset: asset, goal: removedGoal, amount: 20)
        asset.transactions = [openingTransaction]
        asset.allocations = [firstAllocation, removedAllocation]
        firstGoal.allocations = [firstAllocation]
        removedGoal.allocations = [removedAllocation]

        for goal in [firstGoal, removedGoal, insertedGoal] {
            context.insert(goal)
        }
        context.insert(asset)
        context.insert(openingTransaction)
        context.insert(firstAllocation)
        context.insert(removedAllocation)
        try context.saveWithRelationships()

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = AllocationService(
            modelContext: context,
            saveChanges: failFirstSave.save
        )
        let replacement = [
            (goal: firstGoal, amount: 50.0),
            (goal: insertedGoal, amount: 30.0)
        ]

        #expect(throws: ForcedSaveError.self) {
            try service.updateAllocations(for: asset, newAllocations: replacement)
        }

        context.processPendingChanges()
        #expect(Set((asset.allocations ?? []).map(\.id)) == Set([firstAllocation.id, removedAllocation.id]))
        #expect(firstAllocation.amountValue == 40)
        #expect(firstAllocation.goal?.id == firstGoal.id)
        #expect(removedAllocation.amountValue == 20)
        #expect(removedAllocation.goal?.id == removedGoal.id)
        #expect((firstGoal.allocations ?? []).map(\.id) == [firstAllocation.id])
        #expect((removedGoal.allocations ?? []).map(\.id) == [removedAllocation.id])
        #expect((insertedGoal.allocations ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<AllocationHistory>()).isEmpty)
        try service.updateAllocations(for: asset, newAllocations: replacement)

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 2)
        #expect((asset.allocations ?? []).count == 2)
        #expect((asset.allocations ?? []).first { $0.goal?.id == firstGoal.id }?.amountValue == 50)
        #expect((asset.allocations ?? []).first { $0.goal?.id == insertedGoal.id }?.amountValue == 30)
        #expect((asset.allocations ?? []).contains { $0.goal?.id == removedGoal.id } == false)
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        #expect(histories.count == 3)
        #expect(histories.filter { $0.goalId == firstGoal.id }.map(\.amount) == [50])
        #expect(histories.filter { $0.goalId == removedGoal.id }.map(\.amount) == [0])
        #expect(histories.filter { $0.goalId == insertedGoal.id }.map(\.amount) == [30])
    }

    @Test("Failed allocation insertion is removed and same-context retry creates one row")
    func setAllocationFailureIsAtomicAndRetrySafe() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Set Allocation Goal")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: 100, asset: asset)
        asset.transactions = [openingTransaction]
        context.insert(goal)
        context.insert(asset)
        context.insert(openingTransaction)
        try context.saveWithRelationships()

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = AllocationService(modelContext: context, saveChanges: failFirstSave.save)

        #expect(throws: ForcedSaveError.self) {
            try service.setAllocation(for: asset, to: goal, amount: 30)
        }

        context.processPendingChanges()
        #expect((asset.allocations ?? []).isEmpty)
        #expect((goal.allocations ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)

        try service.setAllocation(for: asset, to: goal, amount: 30)

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 2)
        #expect((asset.allocations ?? []).count == 1)
        #expect((goal.allocations ?? []).count == 1)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).count == 1)
        #expect(asset.allocations?.first?.amountValue == 30)
    }

    @Test("Failed allocation removal restores the relationship and retry records one zero snapshot")
    func removeAllocationFailureIsAtomicAndRetrySafe() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Remove Allocation Goal")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: 100, asset: asset)
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 30)
        asset.transactions = [openingTransaction]
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        context.insert(goal)
        context.insert(asset)
        context.insert(openingTransaction)
        context.insert(allocation)
        try context.saveWithRelationships()

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = AllocationService(modelContext: context, saveChanges: failFirstSave.save)

        #expect(throws: ForcedSaveError.self) {
            try service.removeAllocation(for: asset, from: goal)
        }

        context.processPendingChanges()
        #expect((asset.allocations ?? []).map(\.id) == [allocation.id])
        #expect((goal.allocations ?? []).map(\.id) == [allocation.id])
        #expect(allocation.asset?.id == asset.id)
        #expect(allocation.goal?.id == goal.id)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AllocationHistory>()).isEmpty)

        try service.removeAllocation(for: asset, from: goal)

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 2)
        #expect((asset.allocations ?? []).isEmpty)
        #expect((goal.allocations ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        #expect(histories.count == 1)
        #expect(histories.first?.goalId == goal.id)
        #expect(histories.first?.amount == 0)
    }

    @Test("Repeated allocation removal failures keep the durable row retryable")
    func removeAllocationRemainsAtomicAcrossRepeatedFailures() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Repeated Remove Goal")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: 100, asset: asset)
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 30)
        asset.transactions = [openingTransaction]
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        context.insert(goal)
        context.insert(asset)
        context.insert(openingTransaction)
        context.insert(allocation)
        try context.saveWithRelationships()

        let failTwiceSave = FailFirstSave(
            modelContext: context,
            failuresBeforeSuccess: 2
        )
        let service = AllocationService(
            modelContext: context,
            saveChanges: failTwiceSave.save
        )

        for _ in 0..<2 {
            #expect(throws: ForcedSaveError.self) {
                try service.removeAllocation(for: asset, from: goal)
            }
            context.processPendingChanges()
            #expect((asset.allocations ?? []).map(\.id) == [allocation.id])
            #expect((goal.allocations ?? []).map(\.id) == [allocation.id])
            #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).map(\.id) == [allocation.id])
            #expect(try context.fetch(FetchDescriptor<AllocationHistory>()).isEmpty)
        }

        try service.removeAllocation(for: asset, from: goal)

        context.processPendingChanges()
        #expect(failTwiceSave.attempts == 3)
        #expect((asset.allocations ?? []).isEmpty)
        #expect((goal.allocations ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        #expect(histories.count == 1)
        #expect(histories.first?.amount == 0)
    }

    @Test("Failed remove-all for an asset restores every allocation and retry removes each once")
    func removeAllAssetAllocationsFailureIsAtomicAndRetrySafe() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let firstGoal = TestDataFactory.createSampleGoal(name: "First Goal")
        let secondGoal = TestDataFactory.createSampleGoal(name: "Second Goal")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: 100, asset: asset)
        let firstAllocation = AssetAllocation(asset: asset, goal: firstGoal, amount: 30)
        let secondAllocation = AssetAllocation(asset: asset, goal: secondGoal, amount: 20)
        asset.transactions = [openingTransaction]
        asset.allocations = [firstAllocation, secondAllocation]
        firstGoal.allocations = [firstAllocation]
        secondGoal.allocations = [secondAllocation]
        context.insert(firstGoal)
        context.insert(secondGoal)
        context.insert(asset)
        context.insert(openingTransaction)
        context.insert(firstAllocation)
        context.insert(secondAllocation)
        try context.saveWithRelationships()

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = AllocationService(modelContext: context, saveChanges: failFirstSave.save)

        #expect(throws: ForcedSaveError.self) {
            try service.removeAllAllocations(for: asset)
        }

        context.processPendingChanges()
        #expect(Set((asset.allocations ?? []).map(\.id)) == Set([firstAllocation.id, secondAllocation.id]))
        #expect((firstGoal.allocations ?? []).map(\.id) == [firstAllocation.id])
        #expect((secondGoal.allocations ?? []).map(\.id) == [secondAllocation.id])
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).count == 2)

        try service.removeAllAllocations(for: asset)

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 2)
        #expect((asset.allocations ?? []).isEmpty)
        #expect((firstGoal.allocations ?? []).isEmpty)
        #expect((secondGoal.allocations ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
    }

    @Test("Failed remove-all for a goal restores allocations across assets and retry removes each once")
    func removeAllGoalAllocationsFailureIsAtomicAndRetrySafe() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Shared Goal")
        let firstAsset = Asset(currency: "USD")
        let secondAsset = Asset(currency: "EUR")
        let firstTransaction = Transaction(amount: 100, asset: firstAsset)
        let secondTransaction = Transaction(amount: 100, asset: secondAsset)
        let firstAllocation = AssetAllocation(asset: firstAsset, goal: goal, amount: 30)
        let secondAllocation = AssetAllocation(asset: secondAsset, goal: goal, amount: 20)
        firstAsset.transactions = [firstTransaction]
        secondAsset.transactions = [secondTransaction]
        firstAsset.allocations = [firstAllocation]
        secondAsset.allocations = [secondAllocation]
        goal.allocations = [firstAllocation, secondAllocation]
        context.insert(goal)
        context.insert(firstAsset)
        context.insert(secondAsset)
        context.insert(firstTransaction)
        context.insert(secondTransaction)
        context.insert(firstAllocation)
        context.insert(secondAllocation)
        try context.saveWithRelationships()

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = AllocationService(modelContext: context, saveChanges: failFirstSave.save)

        #expect(throws: ForcedSaveError.self) {
            try service.removeAllAllocations(for: goal)
        }

        context.processPendingChanges()
        #expect(Set((goal.allocations ?? []).map(\.id)) == Set([firstAllocation.id, secondAllocation.id]))
        #expect((firstAsset.allocations ?? []).map(\.id) == [firstAllocation.id])
        #expect((secondAsset.allocations ?? []).map(\.id) == [secondAllocation.id])
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).count == 2)

        try service.removeAllAllocations(for: goal)

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 2)
        #expect((goal.allocations ?? []).isEmpty)
        #expect((firstAsset.allocations ?? []).isEmpty)
        #expect((secondAsset.allocations ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
    }

    @Test("Failed asset creation removes its graph and same-context retry creates one graph")
    func assetCreateFailureIsAtomicAndRetrySafe() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Create Asset Goal")
        context.insert(goal)
        try context.save()

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard(),
            saveChanges: failFirstSave.save
        )

        await #expect(throws: PersistenceMutationError.self) {
            _ = try await service.createAsset(
                currency: "BTC",
                address: nil,
                chainId: nil,
                goal: goal
            )
        }

        context.processPendingChanges()
        #expect((goal.allocations ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Asset>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AllocationHistory>()).isEmpty)

        let createdAsset = try await service.createAsset(
            currency: "BTC",
            address: nil,
            chainId: nil,
            goal: goal
        )

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 2)
        #expect(try context.fetch(FetchDescriptor<Asset>()).filter { $0.id == createdAsset.id }.count == 1)
        #expect((goal.allocations ?? []).count == 1)
        #expect((createdAsset.allocations ?? []).count == 1)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AllocationHistory>()).count == 1)
    }

    @Test("Failed single asset deletion restores the full graph and retry deletes it once")
    func assetDeleteFailureIsAtomicAndRetrySafe() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Delete Asset Goal")
        let asset = Asset(currency: "USD")
        let transaction = Transaction(amount: 100, asset: asset)
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 50)
        let history = AllocationHistory(asset: asset, goal: goal, amount: 50)
        asset.transactions = [transaction]
        asset.allocations = [allocation]
        asset.allocationHistory = [history]
        goal.allocations = [allocation]
        goal.allocationHistory = [history]
        context.insert(goal)
        context.insert(asset)
        context.insert(transaction)
        context.insert(allocation)
        context.insert(history)
        try context.saveWithRelationships()

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard(),
            saveChanges: failFirstSave.save
        )

        #expect(throws: PersistenceMutationError.self) {
            try service.deleteAsset(asset)
        }

        context.processPendingChanges()
        #expect(try context.fetch(FetchDescriptor<Asset>()).map(\.id) == [asset.id])
        #expect(try context.fetch(FetchDescriptor<Transaction>()).map(\.id) == [transaction.id])
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).map(\.id) == [allocation.id])
        #expect(try context.fetch(FetchDescriptor<AllocationHistory>()).map(\.id) == [history.id])
        #expect((asset.transactions ?? []).map(\.id) == [transaction.id])
        #expect((asset.allocations ?? []).map(\.id) == [allocation.id])
        #expect((goal.allocations ?? []).map(\.id) == [allocation.id])
        #expect(transaction.asset?.id == asset.id)
        #expect(allocation.asset?.id == asset.id)
        #expect(allocation.goal?.id == goal.id)

        try service.deleteAsset(asset)

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 2)
        #expect(try context.fetch(FetchDescriptor<Asset>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        #expect((goal.allocations ?? []).isEmpty)
    }

    @Test("Failed bulk asset deletion restores every graph and retry deletes each once")
    func assetBulkDeleteFailureIsAtomicAndRetrySafe() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Bulk Delete Goal")
        let firstAsset = Asset(currency: "USD")
        let secondAsset = Asset(currency: "EUR")
        let firstTransaction = Transaction(amount: 100, asset: firstAsset)
        let secondTransaction = Transaction(amount: 50, asset: secondAsset)
        let firstAllocation = AssetAllocation(asset: firstAsset, goal: goal, amount: 30)
        let secondAllocation = AssetAllocation(asset: secondAsset, goal: goal, amount: 20)
        firstAsset.transactions = [firstTransaction]
        secondAsset.transactions = [secondTransaction]
        firstAsset.allocations = [firstAllocation]
        secondAsset.allocations = [secondAllocation]
        goal.allocations = [firstAllocation, secondAllocation]
        context.insert(goal)
        context.insert(firstAsset)
        context.insert(secondAsset)
        context.insert(firstTransaction)
        context.insert(secondTransaction)
        context.insert(firstAllocation)
        context.insert(secondAllocation)
        try context.saveWithRelationships()

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard(),
            saveChanges: failFirstSave.save
        )

        #expect(throws: PersistenceMutationError.self) {
            try service.deleteAssets([firstAsset, secondAsset])
        }

        context.processPendingChanges()
        #expect(Set(try context.fetch(FetchDescriptor<Asset>()).map(\.id)) == Set([firstAsset.id, secondAsset.id]))
        #expect(
            Set(try context.fetch(FetchDescriptor<Transaction>()).map(\.id))
                == Set([firstTransaction.id, secondTransaction.id])
        )
        #expect(
            Set(try context.fetch(FetchDescriptor<AssetAllocation>()).map(\.id))
                == Set([firstAllocation.id, secondAllocation.id])
        )
        #expect(Set((goal.allocations ?? []).map(\.id)) == Set([firstAllocation.id, secondAllocation.id]))

        try service.deleteAssets([firstAsset, secondAsset])

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 2)
        #expect(try context.fetch(FetchDescriptor<Asset>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        #expect((goal.allocations ?? []).isEmpty)
    }

    @Test("Failed mixed durable and pending asset deletion restores both graphs")
    func mixedAssetDeleteFailureRestoresPendingAndDurableGraphs() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Mixed Asset Goal")
        let durableAsset = Asset(currency: "USD")
        let durableTransaction = Transaction(amount: 100, asset: durableAsset)
        let durableAllocation = AssetAllocation(asset: durableAsset, goal: goal, amount: 40)
        durableAsset.transactions = [durableTransaction]
        durableAsset.allocations = [durableAllocation]
        goal.allocations = [durableAllocation]
        context.insert(goal)
        context.insert(durableAsset)
        context.insert(durableTransaction)
        context.insert(durableAllocation)
        try context.saveWithRelationships()

        let pendingAsset = Asset(currency: "EUR")
        let pendingTransaction = Transaction(amount: 50, asset: pendingAsset)
        let pendingAllocation = AssetAllocation(asset: pendingAsset, goal: goal, amount: 20)
        pendingAsset.transactions = [pendingTransaction]
        pendingAsset.allocations = [pendingAllocation]
        goal.allocations = [durableAllocation, pendingAllocation]
        context.insert(pendingAsset)
        context.insert(pendingTransaction)
        context.insert(pendingAllocation)

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard(),
            saveChanges: failFirstSave.save
        )

        #expect(throws: PersistenceMutationError.self) {
            try service.deleteAssets([durableAsset, pendingAsset])
        }

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 1)
        #expect(Set(try context.fetch(FetchDescriptor<Asset>()).map(\.id)) == Set([durableAsset.id, pendingAsset.id]))
        #expect(
            Set(try context.fetch(FetchDescriptor<Transaction>()).map(\.id))
                == Set([durableTransaction.id, pendingTransaction.id])
        )
        #expect(
            Set(try context.fetch(FetchDescriptor<AssetAllocation>()).map(\.id))
                == Set([durableAllocation.id, pendingAllocation.id])
        )
        #expect(Set((goal.allocations ?? []).map(\.id)) == Set([durableAllocation.id, pendingAllocation.id]))
        #expect(pendingAsset.modelContext === context)
        #expect(pendingTransaction.asset?.id == pendingAsset.id)
        #expect(pendingAllocation.asset?.id == pendingAsset.id)
        #expect(pendingAllocation.goal?.id == goal.id)
    }

    @Test("Failed allocation update restores a removed pending allocation beside durable changes")
    func mixedAllocationUpdateFailureRestoresPendingAllocation() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let durableGoal = TestDataFactory.createSampleGoal(name: "Durable Allocation Goal")
        let pendingGoal = TestDataFactory.createSampleGoal(name: "Pending Allocation Goal")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: 100, asset: asset)
        let durableAllocation = AssetAllocation(asset: asset, goal: durableGoal, amount: 30)
        asset.transactions = [openingTransaction]
        asset.allocations = [durableAllocation]
        durableGoal.allocations = [durableAllocation]
        context.insert(durableGoal)
        context.insert(pendingGoal)
        context.insert(asset)
        context.insert(openingTransaction)
        context.insert(durableAllocation)
        try context.saveWithRelationships()

        let pendingAllocation = AssetAllocation(asset: asset, goal: pendingGoal, amount: 20)
        asset.allocations = [durableAllocation, pendingAllocation]
        pendingGoal.allocations = [pendingAllocation]
        context.insert(pendingAllocation)

        let failFirstSave = FailFirstSave(modelContext: context)
        let service = AllocationService(modelContext: context, saveChanges: failFirstSave.save)

        #expect(throws: ForcedSaveError.self) {
            try service.updateAllocations(
                for: asset,
                newAllocations: [(goal: durableGoal, amount: 40)]
            )
        }

        context.processPendingChanges()
        #expect(failFirstSave.attempts == 1)
        #expect(Set((asset.allocations ?? []).map(\.id)) == Set([durableAllocation.id, pendingAllocation.id]))
        #expect((durableGoal.allocations ?? []).map(\.id) == [durableAllocation.id])
        #expect((pendingGoal.allocations ?? []).map(\.id) == [pendingAllocation.id])
        #expect(durableAllocation.amountValue == 30)
        #expect(pendingAllocation.amountValue == 20)
        #expect(pendingAllocation.modelContext === context)
        #expect(try context.fetch(FetchDescriptor<AllocationHistory>()).isEmpty)
    }

    @Test("Mixed asset deletion restores pending rows when an unrelated draft blocks the save")
    func mixedAssetDeletePreconditionFailureRestoresPendingGraph() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Precondition Goal")
        let durableAsset = Asset(currency: "USD")
        let durableTransaction = Transaction(amount: 100, asset: durableAsset)
        let durableAllocation = AssetAllocation(asset: durableAsset, goal: goal, amount: 40)
        durableAsset.transactions = [durableTransaction]
        durableAsset.allocations = [durableAllocation]
        goal.allocations = [durableAllocation]
        context.insert(goal)
        context.insert(durableAsset)
        context.insert(durableTransaction)
        context.insert(durableAllocation)
        try context.saveWithRelationships()

        let pendingAsset = Asset(currency: "EUR")
        let pendingTransaction = Transaction(amount: 50, asset: pendingAsset)
        let pendingAllocation = AssetAllocation(asset: pendingAsset, goal: goal, amount: 20)
        pendingAsset.transactions = [pendingTransaction]
        pendingAsset.allocations = [pendingAllocation]
        goal.allocations = [durableAllocation, pendingAllocation]
        context.insert(pendingAsset)
        context.insert(pendingTransaction)
        context.insert(pendingAllocation)

        let unrelatedPendingAsset = Asset(currency: "GBP")
        context.insert(unrelatedPendingAsset)
        var saveAttempts = 0
        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard(),
            saveChanges: {
                saveAttempts += 1
                try context.save()
            }
        )

        #expect(throws: PersistenceMutationError.self) {
            try service.deleteAssets([durableAsset, pendingAsset])
        }

        context.processPendingChanges()
        #expect(saveAttempts == 0)
        #expect(
            Set(try context.fetch(FetchDescriptor<Asset>()).map(\.id))
                == Set([durableAsset.id, pendingAsset.id, unrelatedPendingAsset.id])
        )
        #expect(
            Set(try context.fetch(FetchDescriptor<Transaction>()).map(\.id))
                == Set([durableTransaction.id, pendingTransaction.id])
        )
        #expect(
            Set(try context.fetch(FetchDescriptor<AssetAllocation>()).map(\.id))
                == Set([durableAllocation.id, pendingAllocation.id])
        )
        #expect(Set((goal.allocations ?? []).map(\.id)) == Set([durableAllocation.id, pendingAllocation.id]))
        #expect(pendingAsset.modelContext === context)
        #expect(pendingTransaction.asset?.id == pendingAsset.id)
        #expect(pendingAllocation.asset?.id == pendingAsset.id)
        #expect(pendingAllocation.goal?.id == goal.id)
    }

    @Test("Durable mutations reject a dirty shared context instead of committing unrelated drafts")
    func transactionCreateRejectsUnrelatedPendingChanges() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let asset = Asset(currency: "USD")
        let unrelatedGoal = TestDataFactory.createSampleGoal(name: "Durable unrelated goal")
        context.insert(asset)
        context.insert(unrelatedGoal)
        try context.save()

        unrelatedGoal.name = "Unsaved unrelated rename"
        let unrelatedPendingAsset = Asset(currency: "EUR")
        context.insert(unrelatedPendingAsset)

        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: AtomicityAllowAllAccessGuard()
        )

        #expect(throws: PersistenceMutationError.self) {
            _ = try service.createTransaction(
                for: asset,
                amount: 25,
                date: Date(timeIntervalSince1970: 9_000),
                comment: "Must not commit unrelated drafts",
                autoAllocateGoalId: nil
            )
        }

        let durableContext = ModelContext(container)
        let durableGoal = try #require(
            durableContext.fetch(FetchDescriptor<Goal>()).first {
                $0.id == unrelatedGoal.id
            }
        )
        #expect(durableGoal.name == "Durable unrelated goal")
        #expect(
            try durableContext.fetch(FetchDescriptor<Asset>()).contains {
                $0.id == unrelatedPendingAsset.id
            } == false
        )
        #expect(try durableContext.fetch(FetchDescriptor<Transaction>()).isEmpty)
    }

    @Test("Deferred allocation plan sync cannot commit drafts opened after the allocation save")
    func deferredAllocationSyncUsesIsolatedContext() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Deferred sync goal")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: 100, asset: asset)
        asset.transactions = [openingTransaction]
        context.insert(goal)
        context.insert(asset)
        context.insert(openingTransaction)
        try context.saveWithRelationships()

        let probe = DeferredSyncProbe()
        let service = AllocationService(
            modelContext: context,
            runDeferredPlanSync: true,
            deferredPlanSync: { syncContext, goalIDs in
                probe.receivedContext = syncContext
                let ids = goalIDs
                let descriptor = FetchDescriptor<Goal>(
                    predicate: #Predicate<Goal> { candidate in
                        ids.contains(candidate.id)
                    }
                )
                if let syncedGoal = try? syncContext.fetch(descriptor).first {
                    syncedGoal.goalDescription = "Deferred sync completed"
                    try? syncContext.save()
                }
                probe.didRun = true
            }
        )

        try service.setAllocation(for: asset, to: goal, amount: 20)

        goal.name = "Unsaved draft rename"
        let unrelatedPendingAsset = Asset(currency: "EUR")
        context.insert(unrelatedPendingAsset)

        for _ in 0..<50 where !probe.didRun {
            await Task.yield()
        }

        #expect(probe.didRun)
        #expect(probe.receivedContext !== context)

        let durableContext = ModelContext(container)
        let durableGoal = try #require(
            durableContext.fetch(FetchDescriptor<Goal>()).first {
                $0.id == goal.id
            }
        )
        #expect(durableGoal.name == "Deferred sync goal")
        #expect(durableGoal.goalDescription == "Deferred sync completed")
        #expect(
            try durableContext.fetch(FetchDescriptor<Asset>()).contains {
                $0.id == unrelatedPendingAsset.id
            } == false
        )
    }

    @Test("Planning persistence rejects unrelated dirty, inserted, and deleted models")
    func planningSuccessfulSaveRejectsUnrelatedPendingChanges() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let plan = MonthlyPlan(
            goalId: UUID(),
            monthLabel: "2026-07",
            requiredMonthly: 100,
            remainingAmount: 400,
            monthsRemaining: 4,
            currency: "USD",
            state: .draft
        )
        context.insert(plan)
        try context.save()

        let unrelated = try stageUnrelatedPendingChanges(in: context)
        plan.customAmount = 125

        let service = PlanningMutationService(
            modelContext: context,
            exchangeRateService: MockExchangeRateService(),
            accessGuard: AtomicityAllowAllAccessGuard()
        )

        #expect(throws: PersistenceMutationError.self) {
            try service.markPlanCompleted(plan)
        }

        #expect(plan.state == .draft)
        #expect(plan.customAmount == 125)
        try assertUnrelatedChangesRemainPending(unrelated, in: container)

        let durableContext = ModelContext(container)
        let durablePlan = try #require(
            durableContext.fetch(FetchDescriptor<MonthlyPlan>()).first {
                $0.id == plan.id
            }
        )
        #expect(durablePlan.state == .draft)
        #expect(durablePlan.customAmount == nil)
    }

    @Test("Goal lifecycle persistence rejects unrelated dirty, inserted, and deleted models")
    func goalLifecycleSuccessfulSaveRejectsUnrelatedPendingChanges() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Lifecycle target")
        context.insert(goal)
        try context.save()

        let unrelated = try stageUnrelatedPendingChanges(in: context)
        goal.name = "Owned lifecycle draft"
        let service = GoalLifecycleService(
            modelContext: context,
            notificationManager: AtomicityNotificationManager()
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await service.finishGoal(
                goal,
                at: Date(timeIntervalSince1970: 12_000)
            )
        }

        #expect(goal.lifecycleStatus == .active)
        #expect(goal.name == "Owned lifecycle draft")
        try assertUnrelatedChangesRemainPending(unrelated, in: container)

        let durableContext = ModelContext(container)
        let durableGoal = try #require(
            durableContext.fetch(FetchDescriptor<Goal>()).first {
                $0.id == goal.id
            }
        )
        #expect(durableGoal.lifecycleStatus == .active)
        #expect(durableGoal.name == "Lifecycle target")
    }

    @Test("On-chain import rejects unrelated dirty, inserted, and deleted models")
    func onChainImportSuccessfulSaveRejectsUnrelatedPendingChanges() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        let existingTransaction = Transaction(
            amount: 0.5,
            asset: asset,
            source: .onChain,
            externalId: "owned-existing-movement",
            comment: "Durable owned comment"
        )
        asset.transactions = [existingTransaction]
        context.insert(asset)
        context.insert(existingTransaction)
        try context.saveWithRelationships()

        let unrelated = try stageUnrelatedPendingChanges(in: context)
        existingTransaction.comment = "Owned draft comment"
        let incoming = TatumTransaction(
            hash: "isolated-import-movement",
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1.25"
        )

        #expect(throws: PersistenceMutationError.self) {
            _ = try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [incoming],
                for: asset
            )
        }

        #expect(existingTransaction.comment == "Owned draft comment")
        #expect(
            (asset.transactions ?? []).contains {
                $0.externalId?.contains("isolated-import-movement") == true
            } == false
        )
        try assertUnrelatedChangesRemainPending(unrelated, in: container)

        let durableContext = ModelContext(container)
        let durableTransactions = try durableContext.fetch(FetchDescriptor<Transaction>())
            .filter { $0.asset?.id == asset.id }
        #expect(durableTransactions.count == 1)
        #expect(durableTransactions.first?.comment == "Durable owned comment")
    }

    @Test("Empty on-chain import is a no-op even with unrelated pending changes")
    func emptyOnChainImportSkipsPreflightAndSave() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let asset = Asset(
            currency: "ETH",
            address: "0x00000000000000000000000000000000000000bb",
            chainId: "ETH"
        )
        context.insert(asset)
        try context.save()

        let unrelated = try stageUnrelatedPendingChanges(in: context)
        var saveAttempts = 0
        let importer = OnChainTransactionImportService(
            modelContext: context,
            saveChanges: {
                saveAttempts += 1
                try context.save()
            }
        )

        let imported = try importer.upsert(transactions: [], for: asset)

        #expect(imported == 0)
        #expect(saveAttempts == 0)
        #expect((asset.transactions ?? []).isEmpty)
        try assertUnrelatedChangesRemainPending(unrelated, in: container)
    }

    @Test("All-existing on-chain import is a no-op even with unrelated pending changes")
    func allExistingOnChainImportSkipsPreflightAndSave() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000cc"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let incoming = TatumTransaction(
            hash: "already-imported-movement",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1.5"
        )
        var saveAttempts = 0
        let importer = OnChainTransactionImportService(
            modelContext: context,
            saveChanges: {
                saveAttempts += 1
                try context.save()
            }
        )
        #expect(try importer.upsert(transactions: [incoming], for: asset) == 1)
        #expect(saveAttempts == 1)

        let unrelated = try stageUnrelatedPendingChanges(in: context)
        saveAttempts = 0

        let imported = try importer.upsert(transactions: [incoming], for: asset)

        #expect(imported == 0)
        #expect(saveAttempts == 0)
        #expect(
            (asset.transactions ?? []).filter { $0.source == .onChain }.count == 1
        )
        try assertUnrelatedChangesRemainPending(unrelated, in: container)
    }

    private struct UnrelatedPendingChanges {
        let dirtyGoal: Goal
        let durableGoalName: String
        let pendingAsset: Asset
        let deletedTransaction: Transaction
    }

    private func stageUnrelatedPendingChanges(
        in context: ModelContext
    ) throws -> UnrelatedPendingChanges {
        let durableGoalName = "Durable unrelated goal"
        let dirtyGoal = TestDataFactory.createSampleGoal(name: durableGoalName)
        let durableAsset = Asset(currency: "GBP")
        let deletedTransaction = Transaction(
            amount: 12,
            asset: durableAsset,
            comment: "Pending unrelated deletion"
        )
        durableAsset.transactions = [deletedTransaction]
        context.insert(dirtyGoal)
        context.insert(durableAsset)
        context.insert(deletedTransaction)
        try context.saveWithRelationships()

        dirtyGoal.name = "Unsaved unrelated rename"
        let pendingAsset = Asset(currency: "EUR")
        context.insert(pendingAsset)
        context.delete(deletedTransaction)
        context.processPendingChanges()

        return UnrelatedPendingChanges(
            dirtyGoal: dirtyGoal,
            durableGoalName: durableGoalName,
            pendingAsset: pendingAsset,
            deletedTransaction: deletedTransaction
        )
    }

    private func assertUnrelatedChangesRemainPending(
        _ changes: UnrelatedPendingChanges,
        in container: ModelContainer
    ) throws {
        #expect(changes.dirtyGoal.name == "Unsaved unrelated rename")
        #expect(changes.pendingAsset.modelContext != nil)

        let durableContext = ModelContext(container)
        let durableGoal = try #require(
            durableContext.fetch(FetchDescriptor<Goal>()).first {
                $0.id == changes.dirtyGoal.id
            }
        )
        #expect(durableGoal.name == changes.durableGoalName)
        #expect(
            try durableContext.fetch(FetchDescriptor<Asset>()).contains {
                $0.id == changes.pendingAsset.id
            } == false
        )
        #expect(
            try durableContext.fetch(FetchDescriptor<Transaction>()).contains {
                $0.id == changes.deletedTransaction.id
            }
        )
    }
}

@MainActor
private final class AtomicityAllowAllAccessGuard: FamilyShareAccessChecking {
    func isSharedGoalID(_ goalID: UUID) -> Bool { false }
    func assertOwnerWritable(goalID: UUID) throws {}
    func assertOwnerWritable(goal: Goal) throws {}
    func assertOwnerWritable(asset: Asset) throws {}
    func assertOwnerWritable(transaction: Transaction) throws {}
    func assertOwnerWritable(plan: MonthlyPlan) throws {}
    func assertOwnerWritable(plans: [MonthlyPlan]) throws {}
    func assertOwnerWritable(goals: [Goal]) throws {}
}

@MainActor
private final class AtomicityNotificationManager: NotificationManager {
    init() {
        super.init(runtimeMode: .publicMVP, isUITestRunProvider: { false })
    }

    override func cancelNotifications(for goal: Goal) async {}
}
