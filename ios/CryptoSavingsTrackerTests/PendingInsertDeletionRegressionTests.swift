import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct PendingInsertDeletionRegressionTests {
    @Test("Deleting an unsaved transaction cancels it without saving unrelated changes")
    func transactionDeleteCancelsPendingInsertWithoutSaving() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let asset = Asset(currency: "USD")
        let unrelatedGoal = TestDataFactory.createSampleGoal(name: "Durable unrelated goal")
        context.insert(asset)
        context.insert(unrelatedGoal)
        try context.save()

        unrelatedGoal.name = "Unsaved unrelated rename"
        let pendingTransaction = Transaction(amount: 15, asset: asset)
        asset.transactions = [pendingTransaction]
        context.insert(pendingTransaction)

        var saveAttempts = 0
        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: PendingInsertAllowAllAccessGuard(),
            saveChanges: {
                saveAttempts += 1
                try context.save()
            }
        )

        try service.deleteTransaction(pendingTransaction)

        context.processPendingChanges()
        #expect(saveAttempts == 0)
        #expect((asset.transactions ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
        #expect(unrelatedGoal.name == "Unsaved unrelated rename")

        let durableContext = ModelContext(container)
        #expect(try durableContext.fetch(FetchDescriptor<Transaction>()).isEmpty)
        #expect(try durableContext.fetch(FetchDescriptor<Goal>()).first?.name == "Durable unrelated goal")
    }

    @Test("Deleting an unsaved asset cancels it without saving unrelated changes")
    func assetDeleteCancelsPendingInsertWithoutSaving() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let unrelatedGoal = TestDataFactory.createSampleGoal(name: "Durable unrelated goal")
        context.insert(unrelatedGoal)
        try context.save()

        unrelatedGoal.name = "Unsaved unrelated rename"
        let pendingAsset = Asset(currency: "BTC")
        let pendingTransaction = Transaction(amount: 50, asset: pendingAsset)
        let pendingAllocation = AssetAllocation(
            asset: pendingAsset,
            goal: unrelatedGoal,
            amount: 20
        )
        pendingAsset.transactions = [pendingTransaction]
        pendingAsset.allocations = [pendingAllocation]
        unrelatedGoal.allocations = [pendingAllocation]
        context.insert(pendingAsset)
        context.insert(pendingTransaction)
        context.insert(pendingAllocation)

        var saveAttempts = 0
        let service = AssetMutationService(
            modelContext: context,
            accessGuard: PendingInsertAllowAllAccessGuard(),
            saveChanges: {
                saveAttempts += 1
                try context.save()
            }
        )

        try service.deleteAsset(pendingAsset)

        context.processPendingChanges()
        #expect(saveAttempts == 0)
        #expect(try context.fetch(FetchDescriptor<Asset>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        #expect((unrelatedGoal.allocations ?? []).isEmpty)
        #expect(unrelatedGoal.name == "Unsaved unrelated rename")

        let durableContext = ModelContext(container)
        #expect(try durableContext.fetch(FetchDescriptor<Asset>()).isEmpty)
        #expect(try durableContext.fetch(FetchDescriptor<Transaction>()).isEmpty)
        #expect(try durableContext.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        #expect(try durableContext.fetch(FetchDescriptor<Goal>()).first?.name == "Durable unrelated goal")
    }

    @Test("Monthly plan service cancels an unsaved plan without saving unrelated pending changes")
    func monthlyPlanDeleteCancelsPendingInsertWithoutSaving() throws {
        let fixture = try makePendingPlanDeletionFixture()
        var saveAttempts = 0
        let service = MonthlyPlanService(
            modelContext: fixture.context,
            goalCalculationService: GoalCalculationService(modelContext: fixture.context),
            saveChanges: {
                saveAttempts += 1
                try fixture.context.save()
            }
        )

        assertPendingPlanDeletionPreconditions(fixture)
        try service.deletePlan(fixture.pendingPlan)

        try assertPendingPlanDeletionOutcome(fixture, saveAttempts: saveAttempts)
    }

    @Test("Planning mutation service cancels an unsaved plan without saving unrelated pending changes")
    func planningMutationDeleteCancelsPendingInsertWithoutSaving() throws {
        let fixture = try makePendingPlanDeletionFixture()
        var saveAttempts = 0
        let service = PlanningMutationService(
            modelContext: fixture.context,
            exchangeRateService: MockExchangeRateService(),
            accessGuard: PendingInsertAllowAllAccessGuard(),
            saveChanges: {
                saveAttempts += 1
                try fixture.context.save()
            }
        )

        assertPendingPlanDeletionPreconditions(fixture)
        try service.deletePlan(fixture.pendingPlan)

        try assertPendingPlanDeletionOutcome(fixture, saveAttempts: saveAttempts)
    }

    @Test("Monthly plan service restores a pending shadow after deletion preflight fails")
    func monthlyPlanDeleteRestoresPendingShadowAfterPreflightFailure() throws {
        try verifyPendingShadowDeletionRollback(.monthlyPlanService)
    }

    @Test("Planning mutation service restores a pending shadow after deletion preflight fails")
    func planningMutationDeleteRestoresPendingShadowAfterPreflightFailure() throws {
        try verifyPendingShadowDeletionRollback(.planningMutationService)
    }

    @Test("Monthly plan service retries a shadow delete through preflight and save failure")
    func monthlyPlanDeleteRetriesPendingShadowThroughFailures() throws {
        try verifyPendingShadowDeletionRetry(.monthlyPlanService)
    }

    @Test("Planning mutation service retries a shadow delete through preflight and save failure")
    func planningMutationDeleteRetriesPendingShadowThroughFailures() throws {
        try verifyPendingShadowDeletionRetry(.planningMutationService)
    }

    @Test("Monthly plan service isolates shadow restoration after resolver failure")
    func monthlyPlanDeleteIsolatesResolverFailureRestoration() throws {
        try verifyPendingShadowResolverFailure(.monthlyPlanService)
    }

    @Test("Planning mutation service isolates shadow restoration after resolver failure")
    func planningMutationDeleteIsolatesResolverFailureRestoration() throws {
        try verifyPendingShadowResolverFailure(.planningMutationService)
    }

    @Test("Removing an unsaved allocation cancels it without history or save")
    func allocationRemoveCancelsPendingInsertWithoutSaving() throws {
        let fixture = try makeAllocationFixture()
        let pendingAllocation = AssetAllocation(
            asset: fixture.asset,
            goal: fixture.goal,
            amount: 25
        )
        fixture.asset.allocations = [pendingAllocation]
        fixture.goal.allocations = [pendingAllocation]
        fixture.context.insert(pendingAllocation)

        var saveAttempts = 0
        let service = AllocationService(
            modelContext: fixture.context,
            saveChanges: {
                saveAttempts += 1
                try fixture.context.save()
            }
        )

        try service.removeAllocation(for: fixture.asset, from: fixture.goal)

        fixture.context.processPendingChanges()
        #expect(saveAttempts == 0)
        #expect((fixture.asset.allocations ?? []).isEmpty)
        #expect((fixture.goal.allocations ?? []).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<AllocationHistory>()).isEmpty)
        #expect(fixture.unrelatedGoal.name == "Unsaved unrelated rename")
    }

    @Test("Replacing allocations cancels a removed unsaved row without history or save")
    func allocationUpdateCancelsRemovedPendingInsertWithoutSaving() throws {
        let fixture = try makeAllocationFixture()
        let pendingAllocation = AssetAllocation(
            asset: fixture.asset,
            goal: fixture.goal,
            amount: 25
        )
        fixture.asset.allocations = [pendingAllocation]
        fixture.goal.allocations = [pendingAllocation]
        fixture.context.insert(pendingAllocation)

        var saveAttempts = 0
        let service = AllocationService(
            modelContext: fixture.context,
            saveChanges: {
                saveAttempts += 1
                try fixture.context.save()
            }
        )

        try service.updateAllocations(for: fixture.asset, newAllocations: [])

        fixture.context.processPendingChanges()
        #expect(saveAttempts == 0)
        #expect((fixture.asset.allocations ?? []).isEmpty)
        #expect((fixture.goal.allocations ?? []).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<AllocationHistory>()).isEmpty)
        #expect(fixture.unrelatedGoal.name == "Unsaved unrelated rename")
    }

    private struct PendingPlanDeletionFixture {
        let container: ModelContainer
        let context: ModelContext
        let pendingPlan: MonthlyPlan
        let dirtyGoal: Goal
        let durableGoalName: String
        let pendingAsset: Asset
        let deletedTransaction: Transaction
    }

    private func makePendingPlanDeletionFixture() throws -> PendingPlanDeletionFixture {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let durableGoalName = "Durable unrelated goal"
        let dirtyGoal = TestDataFactory.createSampleGoal(name: durableGoalName)
        let durableAsset = Asset(currency: "USD")
        let deletedTransaction = Transaction(amount: 12, asset: durableAsset)
        durableAsset.transactions = [deletedTransaction]
        context.insert(dirtyGoal)
        context.insert(durableAsset)
        context.insert(deletedTransaction)
        try context.saveWithRelationships()

        dirtyGoal.name = "Unsaved unrelated rename"
        let pendingAsset = Asset(currency: "EUR")
        context.insert(pendingAsset)
        context.delete(deletedTransaction)

        let pendingPlan = MonthlyPlan(
            goalId: UUID(),
            monthLabel: "2026-08",
            requiredMonthly: 25,
            remainingAmount: 100,
            monthsRemaining: 4,
            currency: "USD"
        )
        context.insert(pendingPlan)
        context.processPendingChanges()

        return PendingPlanDeletionFixture(
            container: container,
            context: context,
            pendingPlan: pendingPlan,
            dirtyGoal: dirtyGoal,
            durableGoalName: durableGoalName,
            pendingAsset: pendingAsset,
            deletedTransaction: deletedTransaction
        )
    }

    private func assertPendingPlanDeletionPreconditions(
        _ fixture: PendingPlanDeletionFixture
    ) {
        #expect(
            fixture.context.changedModelsArray.contains {
                $0.persistentModelID == fixture.dirtyGoal.persistentModelID
            }
        )
        #expect(
            fixture.context.insertedModelsArray.contains {
                $0.persistentModelID == fixture.pendingAsset.persistentModelID
            }
        )
        #expect(
            fixture.context.deletedModelsArray.contains {
                $0.persistentModelID == fixture.deletedTransaction.persistentModelID
            }
        )
    }

    private func assertPendingPlanDeletionOutcome(
        _ fixture: PendingPlanDeletionFixture,
        saveAttempts: Int
    ) throws {
        fixture.context.processPendingChanges()
        #expect(saveAttempts == 0)
        #expect(
            try fixture.context.fetch(FetchDescriptor<MonthlyPlan>()).contains {
                $0.id == fixture.pendingPlan.id
            } == false
        )
        #expect(fixture.dirtyGoal.name == "Unsaved unrelated rename")
        #expect(
            try fixture.context.fetch(FetchDescriptor<Asset>()).contains {
                $0.id == fixture.pendingAsset.id
            }
        )
        #expect(
            fixture.context.deletedModelsArray.contains {
                $0.persistentModelID == fixture.deletedTransaction.persistentModelID
            }
        )

        let durableContext = ModelContext(fixture.container)
        #expect(
            try durableContext.fetch(FetchDescriptor<Goal>()).first {
                $0.id == fixture.dirtyGoal.id
            }?.name == fixture.durableGoalName
        )
        #expect(
            try durableContext.fetch(FetchDescriptor<Transaction>()).contains {
                $0.id == fixture.deletedTransaction.id
            }
        )
        #expect(
            try durableContext.fetch(FetchDescriptor<Asset>()).contains {
                $0.id == fixture.pendingAsset.id
            } == false
        )
        #expect(
            try durableContext.fetch(FetchDescriptor<MonthlyPlan>()).contains {
                $0.id == fixture.pendingPlan.id
            } == false
        )
    }

    private enum PendingShadowDeletionEntryPoint {
        case monthlyPlanService
        case planningMutationService
    }

    private struct PendingPlanShadowDeletionFixture {
        let container: ModelContainer
        let context: ModelContext
        let durablePlan: MonthlyPlan
        let pendingShadow: MonthlyPlan
        let executionRecord: MonthlyExecutionRecord
        let dirtyGoal: Goal
        let durableGoalName: String
        let pendingAsset: Asset
        let deletedTransaction: Transaction
    }

    private func verifyPendingShadowDeletionRollback(
        _ entryPoint: PendingShadowDeletionEntryPoint
    ) throws {
        let fixture = try makePendingPlanShadowDeletionFixture()
        var saveAttempts = 0
        let deletePlan: () throws -> Void

        switch entryPoint {
        case .monthlyPlanService:
            let service = MonthlyPlanService(
                modelContext: fixture.context,
                goalCalculationService: GoalCalculationService(modelContext: fixture.context),
                saveChanges: {
                    saveAttempts += 1
                    try fixture.context.save()
                }
            )
            deletePlan = {
                try service.deletePlan(fixture.pendingShadow)
            }
        case .planningMutationService:
            let service = PlanningMutationService(
                modelContext: fixture.context,
                exchangeRateService: MockExchangeRateService(),
                accessGuard: PendingInsertAllowAllAccessGuard(),
                saveChanges: {
                    saveAttempts += 1
                    try fixture.context.save()
                }
            )
            deletePlan = {
                try service.deletePlan(fixture.pendingShadow)
            }
        }

        let notifications = PendingInsertNotificationCounter()
        let goalID = fixture.pendingShadow.goalId
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { notification in
            guard (notification.userInfo?["affectedGoalIDs"] as? [UUID])?.contains(goalID) == true else {
                return
            }
            notifications.count += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        assertPendingPlanShadowDeletionPreconditions(fixture)

        for _ in 1...2 {
            #expect(throws: PersistenceMutationError.self) {
                try deletePlan()
            }
            try assertPendingPlanShadowDeletionRollback(
                fixture,
                saveAttempts: saveAttempts,
                notificationCount: notifications.count
            )
        }
    }

    private func makePendingPlanShadowDeletionFixture() throws -> PendingPlanShadowDeletionFixture {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goalID = UUID()
        let durablePlan = MonthlyPlan(
            goalId: goalID,
            monthLabel: "2026-09",
            requiredMonthly: 25,
            remainingAmount: 100,
            monthsRemaining: 4,
            currency: "USD"
        )
        let executionRecord = MonthlyExecutionRecord(
            monthLabel: durablePlan.monthLabel,
            goalIds: [goalID]
        )
        durablePlan.executionRecord = executionRecord
        executionRecord.plans = [durablePlan]

        let durableGoalName = "Durable unrelated goal"
        let dirtyGoal = TestDataFactory.createSampleGoal(name: durableGoalName)
        let durableAsset = Asset(currency: "GBP")
        let deletedTransaction = Transaction(
            amount: 12,
            asset: durableAsset,
            comment: "Pending unrelated deletion"
        )
        durableAsset.transactions = [deletedTransaction]

        context.insert(durablePlan)
        context.insert(executionRecord)
        context.insert(dirtyGoal)
        context.insert(durableAsset)
        context.insert(deletedTransaction)
        try context.saveWithRelationships()

        dirtyGoal.name = "Unsaved unrelated rename"
        let pendingAsset = Asset(currency: "EUR")
        context.insert(pendingAsset)
        context.delete(deletedTransaction)

        let pendingShadow = MonthlyPlan(
            goalId: goalID,
            monthLabel: durablePlan.monthLabel,
            requiredMonthly: 777,
            remainingAmount: 888,
            monthsRemaining: 9,
            currency: "CHF",
            status: .critical,
            flexState: .protected,
            state: .executing
        )
        pendingShadow.id = durablePlan.id
        pendingShadow.customAmount = 333
        pendingShadow.isProtected = true
        pendingShadow.executionRecord = executionRecord
        context.insert(pendingShadow)
        executionRecord.plans = [durablePlan, pendingShadow]
        context.processPendingChanges()

        return PendingPlanShadowDeletionFixture(
            container: container,
            context: context,
            durablePlan: durablePlan,
            pendingShadow: pendingShadow,
            executionRecord: executionRecord,
            dirtyGoal: dirtyGoal,
            durableGoalName: durableGoalName,
            pendingAsset: pendingAsset,
            deletedTransaction: deletedTransaction
        )
    }

    private func assertPendingPlanShadowDeletionPreconditions(
        _ fixture: PendingPlanShadowDeletionFixture
    ) {
        #expect(fixture.pendingShadow.modelContext === fixture.context)
        #expect(
            fixture.context.insertedModelsArray.contains {
                $0.persistentModelID == fixture.pendingShadow.persistentModelID
            }
        )
        #expect(fixture.pendingShadow.id == fixture.durablePlan.id)
        #expect(fixture.pendingShadow !== fixture.durablePlan)
        #expect(fixture.pendingShadow.executionRecord === fixture.executionRecord)
        #expect(
            (fixture.executionRecord.plans ?? []).contains {
                $0 === fixture.durablePlan
            }
        )
        #expect(
            (fixture.executionRecord.plans ?? []).contains {
                $0 === fixture.pendingShadow
            }
        )
        assertUnrelatedPendingPlanShadowState(fixture)
    }

    private func assertPendingPlanShadowDeletionRollback(
        _ fixture: PendingPlanShadowDeletionFixture,
        saveAttempts: Int,
        notificationCount: Int
    ) throws {
        fixture.context.processPendingChanges()

        #expect(saveAttempts == 0)
        #expect(notificationCount == 0)
        #expect(fixture.pendingShadow.modelContext === fixture.context)
        #expect(
            fixture.context.insertedModelsArray.contains {
                $0.persistentModelID == fixture.pendingShadow.persistentModelID
            }
        )
        #expect(fixture.pendingShadow.requiredMonthly == 777)
        #expect(fixture.pendingShadow.remainingAmount == 888)
        #expect(fixture.pendingShadow.monthsRemaining == 9)
        #expect(fixture.pendingShadow.currency == "CHF")
        #expect(fixture.pendingShadow.customAmount == 333)
        #expect(fixture.pendingShadow.isProtected)
        #expect(fixture.pendingShadow.state == .executing)
        #expect(fixture.pendingShadow.executionRecord === fixture.executionRecord)
        #expect(
            (fixture.executionRecord.plans ?? []).contains {
                $0 === fixture.durablePlan
            }
        )
        #expect(
            (fixture.executionRecord.plans ?? []).contains {
                $0 === fixture.pendingShadow
            }
        )
        assertUnrelatedPendingPlanShadowState(fixture)

        let durableContext = ModelContext(fixture.container)
        let durablePlans = try durableContext.fetch(FetchDescriptor<MonthlyPlan>()).filter {
            $0.id == fixture.durablePlan.id
        }
        let durablePlan = try #require(durablePlans.first)
        #expect(durablePlans.count == 1)
        #expect(durablePlan.requiredMonthly == 25)
        #expect(durablePlan.executionRecord?.id == fixture.executionRecord.id)

        let durableExecutionRecord = try #require(
            durableContext.fetch(FetchDescriptor<MonthlyExecutionRecord>()).first {
                $0.id == fixture.executionRecord.id
            }
        )
        #expect((durableExecutionRecord.plans ?? []).count == 1)
        #expect(durableExecutionRecord.plans?.first?.id == fixture.durablePlan.id)
        #expect(
            try durableContext.fetch(FetchDescriptor<Goal>()).first {
                $0.id == fixture.dirtyGoal.id
            }?.name == fixture.durableGoalName
        )
        #expect(
            try durableContext.fetch(FetchDescriptor<Asset>()).contains {
                $0.id == fixture.pendingAsset.id
            } == false
        )
        #expect(
            try durableContext.fetch(FetchDescriptor<Transaction>()).contains {
                $0.id == fixture.deletedTransaction.id
            }
        )
    }

    private func assertUnrelatedPendingPlanShadowState(
        _ fixture: PendingPlanShadowDeletionFixture
    ) {
        #expect(fixture.dirtyGoal.name == "Unsaved unrelated rename")
        #expect(
            fixture.context.changedModelsArray.contains {
                $0.persistentModelID == fixture.dirtyGoal.persistentModelID
            }
        )
        #expect(fixture.pendingAsset.modelContext === fixture.context)
        #expect(
            fixture.context.insertedModelsArray.contains {
                $0.persistentModelID == fixture.pendingAsset.persistentModelID
            }
        )
        #expect(
            fixture.context.deletedModelsArray.contains {
                $0.persistentModelID == fixture.deletedTransaction.persistentModelID
            }
        )
    }

    private struct PendingPlanShadowRetryFixture {
        let container: ModelContainer
        let context: ModelContext
        let durablePlan: MonthlyPlan
        let pendingShadow: MonthlyPlan
        let durableExecutionRecord: MonthlyExecutionRecord
        let candidateExecutionRecord: MonthlyExecutionRecord
        let pendingBlocker: Asset
    }

    private func verifyPendingShadowDeletionRetry(
        _ entryPoint: PendingShadowDeletionEntryPoint
    ) throws {
        let fixture = try makePendingPlanShadowRetryFixture()
        var shouldFailSave = true
        var saveAttempts = 0
        var successfulSaves = 0
        let deletePlan: () throws -> Void

        let saveChanges = {
            saveAttempts += 1
            if shouldFailSave {
                throw PendingPlanInjectedSaveError.failed
            }
            try fixture.context.save()
            successfulSaves += 1
        }

        switch entryPoint {
        case .monthlyPlanService:
            let service = MonthlyPlanService(
                modelContext: fixture.context,
                goalCalculationService: GoalCalculationService(modelContext: fixture.context),
                saveChanges: saveChanges
            )
            deletePlan = {
                try service.deletePlan(fixture.pendingShadow)
            }
        case .planningMutationService:
            let service = PlanningMutationService(
                modelContext: fixture.context,
                exchangeRateService: MockExchangeRateService(),
                accessGuard: PendingInsertAllowAllAccessGuard(),
                saveChanges: saveChanges
            )
            deletePlan = {
                try service.deletePlan(fixture.pendingShadow)
            }
        }

        let notifications = PendingInsertNotificationCounter()
        let goalID = fixture.pendingShadow.goalId
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { notification in
            guard (notification.userInfo?["affectedGoalIDs"] as? [UUID])?.contains(goalID) == true else {
                return
            }
            notifications.count += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        assertPendingPlanShadowRetryGraph(fixture)
        #expect(
            fixture.context.insertedModelsArray.contains {
                $0.persistentModelID == fixture.pendingBlocker.persistentModelID
            }
        )

        #expect(throws: PersistenceMutationError.self) {
            try deletePlan()
        }
        #expect(saveAttempts == 0)
        #expect(successfulSaves == 0)
        #expect(notifications.count == 0)
        assertPendingPlanShadowRetryGraph(fixture)

        fixture.context.delete(fixture.pendingBlocker)
        fixture.context.processPendingChanges()
        #expect(fixture.pendingBlocker.modelContext == nil)
        #expect(
            fixture.context.insertedModelsArray.contains {
                $0.persistentModelID == fixture.pendingBlocker.persistentModelID
            } == false
        )

        do {
            try deletePlan()
            Issue.record("Expected the injected save failure")
        } catch {}

        #expect(saveAttempts == 1)
        #expect(successfulSaves == 0)
        #expect(notifications.count == 0)
        guard saveAttempts == 1 else { return }
        try assertPendingPlanShadowRetryGraphAfterSaveFailure(fixture)

        shouldFailSave = false
        try deletePlan()

        #expect(saveAttempts == 2)
        #expect(successfulSaves == 1)
        #expect(notifications.count == 1)
        #expect(fixture.pendingShadow.modelContext == nil)
        #expect(fixture.durableExecutionRecord.modelContext === fixture.context)
        #expect(fixture.candidateExecutionRecord.modelContext === fixture.context)
        #expect((fixture.durableExecutionRecord.plans ?? []).isEmpty)
        #expect((fixture.candidateExecutionRecord.plans ?? []).isEmpty)
        #expect(fixture.context.insertedModelsArray.isEmpty)
        #expect(fixture.context.changedModelsArray.isEmpty)
        #expect(fixture.context.deletedModelsArray.isEmpty)

        let durableContext = ModelContext(fixture.container)
        #expect(
            try durableContext.fetch(FetchDescriptor<MonthlyPlan>()).contains {
                $0.id == fixture.durablePlan.id
            } == false
        )
        let durableRecord = try #require(
            durableContext.fetch(FetchDescriptor<MonthlyExecutionRecord>()).first {
                $0.id == fixture.durableExecutionRecord.id
            }
        )
        #expect((durableRecord.plans ?? []).isEmpty)
        let candidateRecord = try #require(
            durableContext.fetch(FetchDescriptor<MonthlyExecutionRecord>()).first {
                $0.id == fixture.candidateExecutionRecord.id
            }
        )
        #expect((candidateRecord.plans ?? []).isEmpty)
        #expect(
            try durableContext.fetch(FetchDescriptor<Asset>()).contains {
                $0.id == fixture.pendingBlocker.id
            } == false
        )
    }

    private func makePendingPlanShadowRetryFixture() throws -> PendingPlanShadowRetryFixture {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goalID = UUID()
        let durablePlan = MonthlyPlan(
            goalId: goalID,
            monthLabel: "2026-10",
            requiredMonthly: 25,
            remainingAmount: 100,
            monthsRemaining: 4,
            currency: "USD"
        )
        let durableExecutionRecord = MonthlyExecutionRecord(
            monthLabel: durablePlan.monthLabel,
            goalIds: [goalID]
        )
        let candidateExecutionRecord = MonthlyExecutionRecord(
            monthLabel: durablePlan.monthLabel,
            goalIds: [goalID]
        )
        durablePlan.executionRecord = durableExecutionRecord
        durableExecutionRecord.plans = [durablePlan]
        context.insert(durablePlan)
        context.insert(durableExecutionRecord)
        context.insert(candidateExecutionRecord)
        try context.saveWithRelationships()

        let pendingBlocker = Asset(currency: "JPY")
        context.insert(pendingBlocker)

        let pendingShadow = MonthlyPlan(
            goalId: goalID,
            monthLabel: durablePlan.monthLabel,
            requiredMonthly: 777,
            remainingAmount: 888,
            monthsRemaining: 9,
            currency: "CHF",
            status: .critical,
            flexState: .protected,
            state: .executing
        )
        pendingShadow.id = durablePlan.id
        pendingShadow.customAmount = 333
        pendingShadow.isProtected = true
        pendingShadow.executionRecord = candidateExecutionRecord
        context.insert(pendingShadow)
        candidateExecutionRecord.plans = [pendingShadow]
        context.processPendingChanges()

        return PendingPlanShadowRetryFixture(
            container: container,
            context: context,
            durablePlan: durablePlan,
            pendingShadow: pendingShadow,
            durableExecutionRecord: durableExecutionRecord,
            candidateExecutionRecord: candidateExecutionRecord,
            pendingBlocker: pendingBlocker
        )
    }

    private func assertPendingPlanShadowRetryGraph(
        _ fixture: PendingPlanShadowRetryFixture
    ) {
        #expect(fixture.durablePlan.modelContext === fixture.context)
        #expect(fixture.pendingShadow.modelContext === fixture.context)
        #expect(
            fixture.context.insertedModelsArray.contains {
                $0.persistentModelID == fixture.pendingShadow.persistentModelID
            }
        )
        #expect(fixture.durableExecutionRecord !== fixture.candidateExecutionRecord)
        #expect(fixture.durablePlan.executionRecord === fixture.durableExecutionRecord)
        #expect(fixture.pendingShadow.executionRecord === fixture.candidateExecutionRecord)
        #expect(
            (fixture.durableExecutionRecord.plans ?? []).contains {
                $0 === fixture.durablePlan
            }
        )
        #expect(
            (fixture.durableExecutionRecord.plans ?? []).contains {
                $0 === fixture.pendingShadow
            } == false
        )
        #expect(
            (fixture.candidateExecutionRecord.plans ?? []).contains {
                $0 === fixture.pendingShadow
            }
        )
        #expect(
            (fixture.candidateExecutionRecord.plans ?? []).contains {
                $0 === fixture.durablePlan
            } == false
        )
    }

    private func assertPendingPlanShadowRetryGraphAfterSaveFailure(
        _ fixture: PendingPlanShadowRetryFixture
    ) throws {
        fixture.context.processPendingChanges()
        assertPendingPlanShadowRetryGraph(fixture)
        #expect(
            fixture.context.deletedModelsArray.contains {
                $0.persistentModelID == fixture.durablePlan.persistentModelID
            } == false
        )
        #expect(fixture.durablePlan.requiredMonthly == 25)
        #expect(fixture.durablePlan.remainingAmount == 100)
        #expect(fixture.durablePlan.monthsRemaining == 4)
        #expect(fixture.durablePlan.currency == "USD")
        #expect(fixture.pendingShadow.requiredMonthly == 777)
        #expect(fixture.pendingShadow.customAmount == 333)

        let durableContext = ModelContext(fixture.container)
        let durablePlans = try durableContext.fetch(FetchDescriptor<MonthlyPlan>()).filter {
            $0.id == fixture.durablePlan.id
        }
        let durablePlan = try #require(durablePlans.first)
        #expect(durablePlans.count == 1)
        #expect(durablePlan.requiredMonthly == 25)
        #expect(durablePlan.executionRecord?.id == fixture.durableExecutionRecord.id)

        let durableRecord = try #require(
            durableContext.fetch(FetchDescriptor<MonthlyExecutionRecord>()).first {
                $0.id == fixture.durableExecutionRecord.id
            }
        )
        #expect((durableRecord.plans ?? []).count == 1)
        #expect(durableRecord.plans?.first?.id == fixture.durablePlan.id)
        let candidateRecord = try #require(
            durableContext.fetch(FetchDescriptor<MonthlyExecutionRecord>()).first {
                $0.id == fixture.candidateExecutionRecord.id
            }
        )
        #expect((candidateRecord.plans ?? []).isEmpty)
    }

    private func verifyPendingShadowResolverFailure(
        _ entryPoint: PendingShadowDeletionEntryPoint
    ) throws {
        let fixture = try makePendingPlanShadowRetryFixture()
        fixture.context.delete(fixture.pendingBlocker)
        fixture.context.processPendingChanges()

        var fetchAttempts = 0
        let fetchByIDs: (ModelContext, [UUID]) throws -> [MonthlyPlan] = { context, ids in
            fetchAttempts += 1
            if fetchAttempts == 2 {
                throw PendingPlanInjectedResolverError.failed
            }
            let planIDs = ids
            let descriptor = FetchDescriptor<MonthlyPlan>(
                predicate: #Predicate<MonthlyPlan> { candidate in
                    planIDs.contains(candidate.id)
                }
            )
            return try context.fetch(descriptor)
        }

        var saveAttempts = 0
        let deletePlan: () throws -> Void
        switch entryPoint {
        case .monthlyPlanService:
            let service = MonthlyPlanService(
                modelContext: fixture.context,
                goalCalculationService: GoalCalculationService(modelContext: fixture.context),
                saveChanges: {
                    saveAttempts += 1
                    try fixture.context.save()
                },
                planDeletionFetchByIDs: fetchByIDs
            )
            deletePlan = {
                try service.deletePlan(fixture.pendingShadow)
            }
        case .planningMutationService:
            let service = PlanningMutationService(
                modelContext: fixture.context,
                exchangeRateService: MockExchangeRateService(),
                accessGuard: PendingInsertAllowAllAccessGuard(),
                saveChanges: {
                    saveAttempts += 1
                    try fixture.context.save()
                },
                planDeletionFetchByIDs: fetchByIDs
            )
            deletePlan = {
                try service.deletePlan(fixture.pendingShadow)
            }
        }

        let undoManager = UndoManager()
        let undoProbe = PendingPlanUndoProbe()
        undoManager.registerUndo(withTarget: undoProbe) { probe in
            probe.wasUndone = true
        }
        fixture.context.undoManager = undoManager

        let notifications = PendingInsertNotificationCounter()
        let goalID = fixture.pendingShadow.goalId
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { notification in
            guard (notification.userInfo?["affectedGoalIDs"] as? [UUID])?.contains(goalID) == true else {
                return
            }
            notifications.count += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        #expect(throws: PendingPlanInjectedResolverError.self) {
            try deletePlan()
        }

        #expect(fetchAttempts == 2)
        #expect(saveAttempts == 0)
        #expect(notifications.count == 0)
        #expect(fixture.context.undoManager === undoManager)
        assertPendingPlanShadowRetryGraph(fixture)

        undoManager.undo()
        #expect(undoProbe.wasUndone)
        assertPendingPlanShadowRetryGraph(fixture)

        let durableContext = ModelContext(fixture.container)
        let durablePlans = try durableContext.fetch(FetchDescriptor<MonthlyPlan>()).filter {
            $0.id == fixture.durablePlan.id
        }
        #expect(durablePlans.count == 1)
        #expect(durablePlans.first?.executionRecord?.id == fixture.durableExecutionRecord.id)
        let durableRecords = try durableContext.fetch(FetchDescriptor<MonthlyExecutionRecord>())
        #expect(
            durableRecords.first {
                $0.id == fixture.durableExecutionRecord.id
            }?.plans?.count == 1
        )
        #expect(
            durableRecords.first {
                $0.id == fixture.candidateExecutionRecord.id
            }?.plans?.isEmpty == true
        )
    }

    private func makeAllocationFixture() throws -> (
        context: ModelContext,
        goal: Goal,
        asset: Asset,
        unrelatedGoal: Goal
    ) {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Allocation goal")
        let unrelatedGoal = TestDataFactory.createSampleGoal(name: "Durable unrelated goal")
        let asset = Asset(currency: "USD")
        let openingTransaction = Transaction(amount: 100, asset: asset)
        asset.transactions = [openingTransaction]

        context.insert(goal)
        context.insert(unrelatedGoal)
        context.insert(asset)
        context.insert(openingTransaction)
        try context.saveWithRelationships()

        unrelatedGoal.name = "Unsaved unrelated rename"
        return (context, goal, asset, unrelatedGoal)
    }
}

@MainActor
private final class PendingInsertAllowAllAccessGuard: FamilyShareAccessChecking {
    func isSharedGoalID(_ goalID: UUID) -> Bool { false }
    func assertOwnerWritable(goalID: UUID) throws {}
    func assertOwnerWritable(goal: Goal) throws {}
    func assertOwnerWritable(asset: Asset) throws {}
    func assertOwnerWritable(transaction: Transaction) throws {}
    func assertOwnerWritable(plan: MonthlyPlan) throws {}
    func assertOwnerWritable(plans: [MonthlyPlan]) throws {}
    func assertOwnerWritable(goals: [Goal]) throws {}
}

private final class PendingInsertNotificationCounter: @unchecked Sendable {
    var count = 0
}

private enum PendingPlanInjectedSaveError: Error {
    case failed
}

private enum PendingPlanInjectedResolverError: Error {
    case failed
}

private final class PendingPlanUndoProbe: NSObject {
    var wasUndone = false
}
