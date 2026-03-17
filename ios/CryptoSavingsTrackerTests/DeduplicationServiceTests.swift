import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct DeduplicationServiceTests {

    private func makeService() -> DeduplicationService {
        DeduplicationService()
    }

    // MARK: - MonthlyPlan Deduplication

    @Test("Duplicate MonthlyPlans with same monthLabel+goalId are deduplicated")
    func deduplicateMonthlyPlans() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let goalId = UUID()
        let monthLabel = "2026-03"

        let plan1 = MonthlyPlan(
            goalId: goalId, monthLabel: monthLabel,
            requiredMonthly: 100, remainingAmount: 900, monthsRemaining: 9,
            currency: "USD", status: .onTrack, state: .draft
        )
        plan1.lastModifiedDate = Date().addingTimeInterval(-60)

        let plan2 = MonthlyPlan(
            goalId: goalId, monthLabel: monthLabel,
            requiredMonthly: 150, remainingAmount: 850, monthsRemaining: 9,
            currency: "USD", status: .onTrack, state: .draft
        )
        plan2.lastModifiedDate = Date()

        context.insert(plan1)
        context.insert(plan2)
        try context.save()

        let removed = try service.deduplicateMonthlyPlans(in: context)
        try context.save()

        #expect(removed == 1)
        let remaining = try context.fetch(FetchDescriptor<MonthlyPlan>())
        #expect(remaining.count == 1)
        // The most recently modified plan should survive
        #expect(remaining.first?.requiredMonthly == 150)
    }

    @Test("Distinct MonthlyPlans are not deduplicated")
    func distinctMonthlyPlansPreserved() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let plan1 = MonthlyPlan(
            goalId: UUID(), monthLabel: "2026-03",
            requiredMonthly: 100, remainingAmount: 900, monthsRemaining: 9,
            currency: "USD", status: .onTrack, state: .draft
        )
        let plan2 = MonthlyPlan(
            goalId: UUID(), monthLabel: "2026-04",
            requiredMonthly: 200, remainingAmount: 800, monthsRemaining: 8,
            currency: "USD", status: .onTrack, state: .draft
        )

        context.insert(plan1)
        context.insert(plan2)
        try context.save()

        let removed = try service.deduplicateMonthlyPlans(in: context)
        #expect(removed == 0)
        #expect(try context.fetchCount(FetchDescriptor<MonthlyPlan>()) == 2)
    }

    // MARK: - MonthlyExecutionRecord Deduplication

    @Test("Duplicate execution records with same monthLabel are deduplicated")
    func deduplicateExecutionRecords() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let record1 = MonthlyExecutionRecord(monthLabel: "2026-03", goalIds: [UUID()])
        record1.createdAt = Date().addingTimeInterval(-120)
        let record2 = MonthlyExecutionRecord(monthLabel: "2026-03", goalIds: [UUID()])
        record2.createdAt = Date()

        context.insert(record1)
        context.insert(record2)
        try context.save()

        let removed = try service.deduplicateExecutionRecords(in: context)
        try context.save()

        #expect(removed == 1)
        #expect(try context.fetchCount(FetchDescriptor<MonthlyExecutionRecord>()) == 1)
    }

    // MARK: - CompletedExecution Deduplication

    @Test("Duplicate completed executions with same monthLabel are deduplicated")
    func deduplicateCompletedExecutions() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let ce1 = CompletedExecution(
            monthLabel: "2026-03", completedAt: Date().addingTimeInterval(-60),
            exchangeRatesSnapshot: [:], goalSnapshots: [], contributionSnapshots: []
        )
        let ce2 = CompletedExecution(
            monthLabel: "2026-03", completedAt: Date(),
            exchangeRatesSnapshot: [:], goalSnapshots: [], contributionSnapshots: []
        )

        context.insert(ce1)
        context.insert(ce2)
        try context.save()

        let removed = try service.deduplicateCompletedExecutions(in: context)
        try context.save()

        #expect(removed == 1)
        #expect(try context.fetchCount(FetchDescriptor<CompletedExecution>()) == 1)
    }

    // MARK: - Asset Deduplication

    @Test("Duplicate assets with same currency+chain+address are deduplicated and merged")
    func deduplicateAssets() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let asset1 = Asset(currency: "BTC", address: "addr1", chainId: "bitcoin")
        let tx1 = Transaction(amount: 1.0, asset: asset1)
        asset1.transactions = (asset1.transactions ?? []) + [tx1]
        context.insert(asset1)
        context.insert(tx1)

        let asset2 = Asset(currency: "BTC", address: "addr1", chainId: "bitcoin")
        let tx2 = Transaction(amount: 0.5, asset: asset2)
        asset2.transactions = (asset2.transactions ?? []) + [tx2]
        context.insert(asset2)
        context.insert(tx2)

        try context.save()

        let removed = try service.deduplicateAssets(in: context)
        try context.save()

        #expect(removed == 1)
        let assets = try context.fetch(FetchDescriptor<Asset>())
        #expect(assets.count == 1)
        // Survivor should have both transactions
        #expect((assets.first?.transactions ?? []).count == 2)
    }

    // MARK: - AssetAllocation Deduplication

    @Test("Duplicate allocations for same asset+goal are deduplicated")
    func deduplicateAssetAllocations() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let goal = Goal(
            name: "Dedup Goal", currency: "USD", targetAmount: 1000,
            deadline: Date().addingTimeInterval(86400 * 90)
        )
        let asset = Asset(currency: "BTC")
        context.insert(goal)
        context.insert(asset)

        let alloc1 = AssetAllocation(asset: asset, goal: goal, amount: 100)
        let alloc2 = AssetAllocation(asset: asset, goal: goal, amount: 50)
        context.insert(alloc1)
        context.insert(alloc2)
        try context.save()

        let removed = try service.deduplicateAssetAllocations(in: context)
        try context.save()

        #expect(removed == 1)
        let allocations = try context.fetch(FetchDescriptor<AssetAllocation>())
        #expect(allocations.count == 1)
        // Higher amount should survive
        #expect(allocations.first!.amount == 100)
    }

    // MARK: - Goal Deduplication

    @Test("Duplicate goals with same name+currency+startDate are deduplicated")
    func deduplicateGoals() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let sharedStart = Date()
        let goal1 = Goal(
            name: "Retirement", currency: "BTC", targetAmount: 1.0,
            deadline: Date().addingTimeInterval(86400 * 365),
            startDate: sharedStart
        )
        goal1.lastModifiedDate = Date().addingTimeInterval(-60)

        let goal2 = Goal(
            name: "Retirement", currency: "BTC", targetAmount: 1.0,
            deadline: Date().addingTimeInterval(86400 * 365),
            startDate: sharedStart
        )
        goal2.lastModifiedDate = Date()

        context.insert(goal1)
        context.insert(goal2)
        try context.save()

        let removed = try service.deduplicateGoals(in: context)
        try context.save()

        #expect(removed == 1)
        #expect(try context.fetchCount(FetchDescriptor<Goal>()) == 1)
    }

    @Test("Goals with same name but different startDate are NOT deduplicated")
    func distinctGoalsWithDifferentStartDate() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let goal1 = Goal(
            name: "Retirement", currency: "BTC", targetAmount: 1.0,
            deadline: Date().addingTimeInterval(86400 * 365),
            startDate: Date().addingTimeInterval(-86400 * 30)  // Started 30 days ago
        )
        let goal2 = Goal(
            name: "Retirement", currency: "BTC", targetAmount: 1.0,
            deadline: Date().addingTimeInterval(86400 * 365),
            startDate: Date()  // Started today
        )

        context.insert(goal1)
        context.insert(goal2)
        try context.save()

        let removed = try service.deduplicateGoals(in: context)
        #expect(removed == 0)
        #expect(try context.fetchCount(FetchDescriptor<Goal>()) == 2)
    }

    // MARK: - Transaction Deduplication

    @Test("Duplicate on-chain transactions with same externalId are deduplicated")
    func deduplicateTransactions() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let asset = Asset(currency: "BTC", address: "addr1", chainId: "bitcoin")
        context.insert(asset)

        let tx1 = Transaction(amount: 1.0, asset: asset, source: .onChain, externalId: "0xabc123")
        let tx2 = Transaction(amount: 1.0, asset: asset, source: .onChain, externalId: "0xabc123")
        context.insert(tx1)
        context.insert(tx2)
        try context.save()

        let removed = try service.deduplicateTransactions(in: context)
        try context.save()

        #expect(removed == 1)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    @Test("Manual transactions without externalId are not deduplicated")
    func manualTransactionsNotDeduplicated() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let asset = Asset(currency: "BTC")
        context.insert(asset)

        let tx1 = Transaction(amount: 1.0, asset: asset, comment: "Manual deposit 1")
        let tx2 = Transaction(amount: 1.0, asset: asset, comment: "Manual deposit 2")
        context.insert(tx1)
        context.insert(tx2)
        try context.save()

        let removed = try service.deduplicateTransactions(in: context)
        #expect(removed == 0)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 2)
    }

    // MARK: - Full Deduplication

    @Test("runFullDeduplication processes all entity types without error")
    func fullDeduplicationRuns() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        // Insert some non-duplicate data
        let goal = Goal(
            name: "Full Dedup Test", currency: "USD", targetAmount: 500,
            deadline: Date().addingTimeInterval(86400 * 60)
        )
        context.insert(goal)
        try context.save()

        // Should complete without error
        try await service.runFullDeduplication(in: context)

        // Data should still be there
        #expect(try context.fetchCount(FetchDescriptor<Goal>()) == 1)
    }

    // MARK: - P2: Goal Dedup Rewrites UUID-Based References

    @Test("deduplicateGoals rewrites MonthlyPlan.goalId to survivor")
    func goalDedupRewritesMonthlyPlanGoalId() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let sharedStart = Date()
        let goal1 = Goal(
            name: "Savings", currency: "USD", targetAmount: 1000,
            deadline: Date().addingTimeInterval(86400 * 365),
            startDate: sharedStart
        )
        goal1.lastModifiedDate = Date().addingTimeInterval(-60)

        let goal2 = Goal(
            name: "Savings", currency: "USD", targetAmount: 1000,
            deadline: Date().addingTimeInterval(86400 * 365),
            startDate: sharedStart
        )
        goal2.lastModifiedDate = Date() // newer → survivor

        context.insert(goal1)
        context.insert(goal2)

        // Create a MonthlyPlan referencing the OLDER goal (will be deleted)
        let plan = MonthlyPlan(
            goalId: goal1.id, monthLabel: "2026-04",
            requiredMonthly: 100, remainingAmount: 900, monthsRemaining: 9,
            currency: "USD", status: .onTrack, state: .draft
        )
        context.insert(plan)
        try context.save()

        let removed = try service.deduplicateGoals(in: context)
        try context.save()

        #expect(removed == 1)

        // The surviving goal should be goal2 (most recently modified)
        let goals = try context.fetch(FetchDescriptor<Goal>())
        #expect(goals.count == 1)
        let survivor = goals[0]
        #expect(survivor.id == goal2.id)

        // MonthlyPlan.goalId must have been rewritten to survivor
        let plans = try context.fetch(FetchDescriptor<MonthlyPlan>())
        #expect(plans.count == 1)
        #expect(plans[0].goalId == survivor.id)
    }

    @Test("deduplicateGoals rewrites MonthlyExecutionRecord.trackedGoalIds to survivor")
    func goalDedupRewritesExecutionRecordGoalIds() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let sharedStart = Date()
        let goal1 = Goal(
            name: "Retire", currency: "BTC", targetAmount: 2.0,
            deadline: Date().addingTimeInterval(86400 * 365),
            startDate: sharedStart
        )
        goal1.lastModifiedDate = Date().addingTimeInterval(-120)

        let goal2 = Goal(
            name: "Retire", currency: "BTC", targetAmount: 2.0,
            deadline: Date().addingTimeInterval(86400 * 365),
            startDate: sharedStart
        )
        goal2.lastModifiedDate = Date() // newer → survivor

        // A third, unrelated goal to verify it's not touched
        let otherGoal = Goal(
            name: "Vacation", currency: "USD", targetAmount: 5000,
            deadline: Date().addingTimeInterval(86400 * 180)
        )

        context.insert(goal1)
        context.insert(goal2)
        context.insert(otherGoal)

        // Create an execution record referencing both the duplicate AND another goal
        let execRecord = MonthlyExecutionRecord(
            monthLabel: "2026-04",
            goalIds: [goal1.id, otherGoal.id]
        )
        context.insert(execRecord)
        try context.save()

        let removed = try service.deduplicateGoals(in: context)
        try context.save()

        #expect(removed == 1)

        // Verify the survivor is goal2
        let goals = try context.fetch(FetchDescriptor<Goal>(
            sortBy: [SortDescriptor(\.name)]
        ))
        let retireGoals = goals.filter { $0.name == "Retire" }
        #expect(retireGoals.count == 1)
        let survivor = retireGoals[0]
        #expect(survivor.id == goal2.id)

        // Verify execution record's goalIds were rewritten
        let records = try context.fetch(FetchDescriptor<MonthlyExecutionRecord>())
        #expect(records.count == 1)
        let updatedIds = records[0].goalIds
        #expect(updatedIds.contains(survivor.id))
        #expect(updatedIds.contains(otherGoal.id))
        #expect(!updatedIds.contains(goal1.id)) // duplicate ID must be gone
        #expect(updatedIds.count == 2) // no duplicates in the list
    }

    // MARK: - P2: Orphaned Relationships Handled Cleanly

    @Test("deduplicateGoals handles goals with nil relationships without crashing")
    func goalDedupHandlesNilRelationships() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let sharedStart = Date()
        // Two duplicate goals with NO allocations, NO allocationHistory
        let goal1 = Goal(
            name: "Empty", currency: "ETH", targetAmount: 10,
            deadline: Date().addingTimeInterval(86400 * 90),
            startDate: sharedStart
        )
        goal1.lastModifiedDate = Date().addingTimeInterval(-30)

        let goal2 = Goal(
            name: "Empty", currency: "ETH", targetAmount: 10,
            deadline: Date().addingTimeInterval(86400 * 90),
            startDate: sharedStart
        )
        goal2.lastModifiedDate = Date()

        context.insert(goal1)
        context.insert(goal2)
        try context.save()

        // Should not crash — nil allocations/allocationHistory are safely handled
        let removed = try service.deduplicateGoals(in: context)
        try context.save()

        #expect(removed == 1)
        #expect(try context.fetchCount(FetchDescriptor<Goal>()) == 1)
    }

    @Test("deduplicateAssets handles assets with nil relationships without crashing")
    func assetDedupHandlesNilRelationships() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        // Two duplicate assets with NO transactions, NO allocations
        let asset1 = Asset(currency: "SOL", address: "addr", chainId: "solana")
        let asset2 = Asset(currency: "SOL", address: "addr", chainId: "solana")
        context.insert(asset1)
        context.insert(asset2)
        try context.save()

        let removed = try service.deduplicateAssets(in: context)
        try context.save()

        #expect(removed == 1)
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 1)
    }
}
