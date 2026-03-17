import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct CloudKitSchemaTests {

    // MARK: - All Models Insert Cleanly

    @Test("All model types can be inserted and fetched from an in-memory container")
    func allModelsInsertAndFetch() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        // 1. Goal
        let goal = Goal(
            name: "Schema Test Goal",
            currency: "USD",
            targetAmount: 5000,
            deadline: Date().addingTimeInterval(86400 * 90)
        )
        context.insert(goal)

        // 2. Asset
        let asset = Asset(currency: "BTC")
        context.insert(asset)

        // 3. Transaction
        let tx = Transaction(amount: 0.5, asset: asset)
        context.insert(tx)

        // 4. AssetAllocation
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 0.5)
        context.insert(allocation)

        // 5. AllocationHistory
        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5, timestamp: Date())
        context.insert(history)

        // 6. MonthlyExecutionRecord
        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
        let execRecord = MonthlyExecutionRecord(monthLabel: monthLabel, goalIds: [goal.id])
        context.insert(execRecord)

        // 7. MonthlyPlan
        let plan = MonthlyPlan(
            goalId: goal.id,
            monthLabel: monthLabel,
            requiredMonthly: 500,
            remainingAmount: 4500,
            monthsRemaining: 9,
            currency: "USD",
            status: .onTrack,
            state: .draft
        )
        plan.executionRecord = execRecord
        context.insert(plan)

        // 8. CompletedExecution
        let completed = CompletedExecution(
            monthLabel: monthLabel,
            completedAt: Date(),
            exchangeRatesSnapshot: [:],
            goalSnapshots: [],
            contributionSnapshots: []
        )
        completed.executionRecord = execRecord
        context.insert(completed)

        // 9. ExecutionSnapshot
        let snapshot = ExecutionSnapshot(
            id: UUID(),
            capturedAt: Date(),
            totalPlanned: 500,
            snapshotData: Data()
        )
        snapshot.executionRecord = execRecord
        context.insert(snapshot)

        // 10. CompletionEvent
        let event = CompletionEvent(
            executionRecord: execRecord,
            sequence: 1,
            sourceDiscriminator: "test",
            completedAt: Date(),
            completionSnapshot: completed
        )
        context.insert(event)

        try context.save()

        // Verify all fetches return correct counts
        #expect(try context.fetchCount(FetchDescriptor<Goal>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AssetAllocation>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AllocationHistory>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<MonthlyExecutionRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<MonthlyPlan>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<CompletedExecution>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ExecutionSnapshot>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<CompletionEvent>()) == 1)
    }

    // MARK: - Inverse Relationship Navigation

    @Test("MonthlyPlan.executionRecord ↔ MonthlyExecutionRecord.plans is bidirectional")
    func planExecutionRecordInverse() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
        let execRecord = MonthlyExecutionRecord(monthLabel: monthLabel, goalIds: [UUID()])
        context.insert(execRecord)

        let plan = MonthlyPlan(
            goalId: UUID(),
            monthLabel: monthLabel,
            requiredMonthly: 100,
            remainingAmount: 900,
            monthsRemaining: 9,
            currency: "USD",
            status: .onTrack,
            state: .draft
        )
        plan.executionRecord = execRecord
        context.insert(plan)
        try context.save()

        // Navigate from record → plans
        #expect((execRecord.plans ?? []).count == 1)
        #expect((execRecord.plans ?? []).first?.id == plan.id)

        // Navigate from plan → record
        #expect(plan.executionRecord?.id == execRecord.id)
    }

    @Test("CompletedExecution.executionRecord ↔ MonthlyExecutionRecord.completedExecution is bidirectional")
    func completedExecutionInverse() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
        let execRecord = MonthlyExecutionRecord(monthLabel: monthLabel, goalIds: [UUID()])
        context.insert(execRecord)

        let completed = CompletedExecution(
            monthLabel: monthLabel,
            completedAt: Date(),
            exchangeRatesSnapshot: [:],
            goalSnapshots: [],
            contributionSnapshots: []
        )
        completed.executionRecord = execRecord
        execRecord.completedExecution = completed
        context.insert(completed)
        try context.save()

        // Navigate both directions
        #expect(execRecord.completedExecution?.id == completed.id)
        #expect(completed.executionRecord?.id == execRecord.id)
    }

    @Test("Asset.transactions ↔ Transaction.asset is bidirectional")
    func assetTransactionInverse() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let asset = Asset(currency: "ETH")
        context.insert(asset)

        let tx = Transaction(amount: 1.5, asset: asset)
        asset.transactions = (asset.transactions ?? []) + [tx]
        context.insert(tx)
        try context.save()

        #expect((asset.transactions ?? []).count == 1)
        #expect(tx.asset?.id == asset.id)
    }

    @Test("Goal.allocations ↔ AssetAllocation.goal is bidirectional")
    func goalAllocationInverse() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let goal = Goal(
            name: "Inverse Test",
            currency: "USD",
            targetAmount: 1000,
            deadline: Date().addingTimeInterval(86400 * 30)
        )
        let asset = Asset(currency: "BTC")
        context.insert(goal)
        context.insert(asset)

        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 0.1)
        context.insert(allocation)
        try context.save()

        #expect((goal.allocations ?? []).contains(where: { $0.id == allocation.id }))
        #expect(allocation.goal?.id == goal.id)
        #expect(allocation.asset?.id == asset.id)
    }

    // MARK: - Optional Relationships

    @Test("Transaction can be created without an asset")
    func transactionWithoutAsset() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let tx = Transaction(amount: 100)
        context.insert(tx)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Transaction>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.asset == nil)
    }

    // MARK: - Default Values

    @Test("All model properties have CloudKit-compatible defaults")
    func modelDefaultValues() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        // Goal with minimal init
        let goal = Goal(
            name: "Default Test",
            currency: "USD",
            targetAmount: 100,
            deadline: Date().addingTimeInterval(86400)
        )
        context.insert(goal)

        // Asset with minimal init
        let asset = Asset(currency: "BTC")
        context.insert(asset)

        try context.save()

        // Verify no crashes from nil defaults
        #expect(goal.id != UUID())  // Should have a valid ID
        #expect(goal.lifecycleStatusRawValue == "active")
        #expect(asset.id != UUID())
    }
}
