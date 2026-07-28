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

    @Test("Provably redundant evidence-free execution records are deduplicated")
    func deduplicateEvidenceFreeExecutionRecords() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()

        let goalID = UUID()
        let record1 = MonthlyExecutionRecord(monthLabel: "2026-03", goalIds: [goalID])
        record1.createdAt = Date().addingTimeInterval(-120)
        let record2 = MonthlyExecutionRecord(monthLabel: "2026-03", goalIds: [goalID])
        record2.createdAt = Date()

        context.insert(record1)
        context.insert(record2)
        try context.save()

        let removed = try service.deduplicateExecutionRecords(in: context)
        try context.save()

        #expect(removed == 1)
        #expect(try context.fetchCount(FetchDescriptor<MonthlyExecutionRecord>()) == 1)
    }

    @Test("Execution dedup preserves an older closed graph over a newer empty draft")
    func executionDedupPreservesClosedEvidenceGraph() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        let goalID = UUID()
        let completedAt = Date().addingTimeInterval(-60)

        let closed = MonthlyExecutionRecord(
            monthLabel: "2026-03",
            goalIds: [goalID]
        )
        closed.createdAt = Date().addingTimeInterval(-120)
        closed.status = .closed
        closed.startedAt = Date().addingTimeInterval(-3_600)
        closed.completedAt = completedAt
        let snapshot = ExecutionSnapshot(
            id: UUID(),
            capturedAt: closed.startedAt!,
            totalPlanned: 100,
            snapshotData: try JSONEncoder().encode([
                ExecutionGoalSnapshot(
                    goalId: goalID,
                    goalName: "Closed evidence",
                    plannedAmount: 100,
                    currency: "USD",
                    flexState: "flexible",
                    isSkipped: false,
                    isProtected: false
                )
            ])
        )
        let completion = CompletedExecution(
            monthLabel: closed.monthLabel,
            completedAt: completedAt,
            exchangeRatesSnapshot: [:],
            goalSnapshots: snapshot.goalSnapshots,
            contributionSnapshots: []
        )
        let event = CompletionEvent(
            executionRecord: closed,
            sequence: 1,
            sourceDiscriminator: completion.id.uuidString,
            completedAt: completedAt,
            completionSnapshot: completion
        )
        closed.snapshot = snapshot
        snapshot.executionRecord = closed
        closed.completedExecution = completion
        completion.executionRecord = closed
        closed.completionEvents = [event]

        let newerDraft = MonthlyExecutionRecord(
            monthLabel: closed.monthLabel,
            goalIds: [goalID]
        )
        newerDraft.createdAt = Date()

        [closed, newerDraft].forEach(context.insert)
        context.insert(snapshot)
        context.insert(completion)
        context.insert(event)
        try context.save()

        #expect(try service.deduplicateExecutionRecords(in: context) == 1)
        try context.save()

        let record = try #require(
            context.fetch(FetchDescriptor<MonthlyExecutionRecord>()).first
        )
        #expect(record.id == closed.id)
        #expect(record.status == .closed)
        #expect(record.snapshot?.id == snapshot.id)
        #expect(record.completedExecution?.id == completion.id)
        #expect(record.completionEvents?.map(\.eventId) == [event.eventId])
        #expect(try context.fetchCount(FetchDescriptor<ExecutionSnapshot>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<CompletedExecution>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<CompletionEvent>()) == 1)
    }

    @Test("Conflicting execution evidence aborts the whole deduplication pass")
    func conflictingExecutionEvidenceFailsClosedWithoutPartialSave() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        let goalID = UUID()
        let monthLabel = "2026-03"

        for offset in [0.0, 60.0] {
            let record = MonthlyExecutionRecord(
                monthLabel: monthLabel,
                goalIds: [goalID]
            )
            record.status = .executing
            record.startedAt = Date().addingTimeInterval(-3_600 + offset)
            let snapshot = ExecutionSnapshot(
                id: UUID(),
                capturedAt: record.startedAt!,
                totalPlanned: 100 + offset,
                snapshotData: try JSONEncoder().encode(
                    [ExecutionGoalSnapshot]()
                )
            )
            record.snapshot = snapshot
            snapshot.executionRecord = record
            context.insert(record)
            context.insert(snapshot)
        }

        context.insert(MonthlyPlan(
            goalId: goalID,
            monthLabel: monthLabel,
            requiredMonthly: 100,
            remainingAmount: 100,
            monthsRemaining: 1,
            currency: "USD"
        ))
        context.insert(MonthlyPlan(
            goalId: goalID,
            monthLabel: monthLabel,
            requiredMonthly: 200,
            remainingAmount: 200,
            monthsRemaining: 1,
            currency: "USD"
        ))
        try context.save()

        await #expect(throws: DeduplicationError.self) {
            try await service.runFullDeduplication(in: context)
        }

        let durable = ModelContext(container)
        #expect(try durable.fetchCount(FetchDescriptor<MonthlyExecutionRecord>()) == 2)
        #expect(try durable.fetchCount(FetchDescriptor<ExecutionSnapshot>()) == 2)
        #expect(try durable.fetchCount(FetchDescriptor<MonthlyPlan>()) == 2)
    }

    // MARK: - CompletedExecution Deduplication

    @Test("Distinct completion cycles in one month remain append-only")
    func completedExecutionCyclesAreNotDeduplicatedByMonth() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        let record = MonthlyExecutionRecord(
            monthLabel: "2026-03",
            goalIds: [UUID()]
        )
        record.status = .closed
        let firstCompletedAt = Date().addingTimeInterval(-60)
        let secondCompletedAt = Date()
        let first = CompletedExecution(
            monthLabel: record.monthLabel,
            completedAt: firstCompletedAt,
            exchangeRatesSnapshot: [:], goalSnapshots: [], contributionSnapshots: []
        )
        let second = CompletedExecution(
            monthLabel: record.monthLabel,
            completedAt: secondCompletedAt,
            exchangeRatesSnapshot: [:], goalSnapshots: [], contributionSnapshots: []
        )
        let firstEvent = CompletionEvent(
            executionRecord: record,
            sequence: 1,
            sourceDiscriminator: first.id.uuidString,
            completedAt: firstCompletedAt,
            completionSnapshot: first
        )
        firstEvent.undoneAt = firstCompletedAt.addingTimeInterval(30)
        firstEvent.undoReason = "manualUndo"
        let secondEvent = CompletionEvent(
            executionRecord: record,
            sequence: 2,
            sourceDiscriminator: second.id.uuidString,
            completedAt: secondCompletedAt,
            completionSnapshot: second
        )
        record.completedExecution = second
        record.completionEvents = [firstEvent, secondEvent]
        first.executionRecord = record
        second.executionRecord = record

        context.insert(record)
        context.insert(first)
        context.insert(second)
        context.insert(firstEvent)
        context.insert(secondEvent)
        try context.save()

        #expect(try service.deduplicateCompletedExecutions(in: context) == 0)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<CompletedExecution>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<CompletionEvent>()) == 2)
        #expect(record.completedExecution?.id == second.id)
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

    @Test("Addressless accounts in the same currency are never deduplicated")
    func addresslessAccountsAreIndependent() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        context.insert(Asset(currency: "USD"))
        context.insert(Asset(currency: "usd"))
        try context.save()

        #expect(try service.deduplicateAssets(in: context) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 2)
    }

    @Test("Distinct case-sensitive Solana addresses are never grouped")
    func solanaAddressCaseIsPreserved() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        context.insert(Asset(
            currency: "SOL",
            address: "AbcDefGhijkLmnoPqrstUvwxyz123456789",
            chainId: "SOL"
        ))
        context.insert(Asset(
            currency: "sol",
            address: "abcDefGhijkLmnoPqrstUvwxyz123456789",
            chainId: "sol"
        ))
        try context.save()

        #expect(try service.deduplicateAssets(in: context) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 2)
    }

    @Test("Bitcoin Bech32 case aliases use one canonical asset identity")
    func bitcoinBech32AliasesDeduplicate() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        context.insert(Asset(
            currency: "BTC",
            address: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080",
            chainId: "BTC"
        ))
        context.insert(Asset(
            currency: "btc",
            address: "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KYGT080",
            chainId: "btc"
        ))
        try context.save()

        #expect(try service.deduplicateAssets(in: context) == 1)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 1)
    }

    @Test("Legacy MATIC and POL assets for one Polygon wallet deduplicate")
    func polygonNativeCurrencyAliasesDeduplicate() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        context.insert(Asset(
            currency: "MATIC",
            address: "0x00000000000000000000000000000000000000AA",
            chainId: "MATIC"
        ))
        context.insert(Asset(
            currency: "POL",
            address: "0x00000000000000000000000000000000000000aa",
            chainId: "polygon-mainnet"
        ))
        try context.save()

        #expect(try service.deduplicateAssets(in: context) == 1)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 1)
    }

    @Test("True asset duplicate merge preserves the complete safe allocation total")
    func duplicateAssetMergePreservesSafeAllocationTotal() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        let goal = Goal(
            name: "Merged allocations",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        let first = Asset(currency: "USD", address: "wallet", chainId: "SOL")
        let second = Asset(currency: "USD", address: "wallet", chainId: "sol")
        let firstTransaction = Transaction(amount: 40, asset: first)
        let secondTransaction = Transaction(amount: 60, asset: second)
        let firstAllocation = AssetAllocation(asset: first, goal: goal, amount: 40)
        let secondAllocation = AssetAllocation(asset: second, goal: goal, amount: 60)
        first.transactions = [firstTransaction]
        second.transactions = [secondTransaction]
        first.allocations = [firstAllocation]
        second.allocations = [secondAllocation]
        goal.allocations = [firstAllocation, secondAllocation]
        context.insert(goal)
        context.insert(first)
        context.insert(second)
        context.insert(firstTransaction)
        context.insert(secondTransaction)
        context.insert(firstAllocation)
        context.insert(secondAllocation)
        try context.save()

        #expect(try service.deduplicateAssets(in: context) == 1)
        #expect(try service.deduplicateAssetAllocations(in: context) == 1)
        try context.save()

        let survivor = try #require(context.fetch(FetchDescriptor<Asset>()).first)
        let allocation = try #require(context.fetch(FetchDescriptor<AssetAllocation>()).first)
        #expect(allocation.amountValue == 100)
        #expect(survivor.manualBalance == 100)
        #expect(survivor.isOverAllocated == false)
    }

    @Test("Unsafe allocation deduplication fails closed instead of over-allocating")
    func unsafeAllocationMergeFailsClosed() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        let goal = Goal(
            name: "Unsafe allocation",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        let asset = Asset(currency: "USD")
        let transaction = Transaction(amount: 100, asset: asset)
        let first = AssetAllocation(asset: asset, goal: goal, amount: 80)
        let second = AssetAllocation(asset: asset, goal: goal, amount: 80)
        asset.transactions = [transaction]
        asset.allocations = [first, second]
        goal.allocations = [first, second]
        context.insert(goal)
        context.insert(asset)
        context.insert(transaction)
        context.insert(first)
        context.insert(second)
        try context.save()

        #expect(throws: DeduplicationError.self) {
            try service.deduplicateAssetAllocations(in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<AssetAllocation>()) == 2)
        #expect(asset.totalAllocatedAmount == 160)
    }

    @Test("Full deduplication failure preserves unrelated pending edits")
    func fullDeduplicationFailurePreservesUnrelatedPendingEdits() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        let goal = Goal(
            name: "Unsafe allocation",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        let asset = Asset(currency: "USD")
        let transaction = Transaction(amount: 100, asset: asset)
        let first = AssetAllocation(asset: asset, goal: goal, amount: 80)
        let second = AssetAllocation(asset: asset, goal: goal, amount: 80)
        let editedDraft = Goal(
            name: "Existing draft",
            currency: "USD",
            targetAmount: 500,
            deadline: Date().addingTimeInterval(172_800)
        )
        asset.transactions = [transaction]
        asset.allocations = [first, second]
        goal.allocations = [first, second]
        context.insert(goal)
        context.insert(asset)
        context.insert(transaction)
        context.insert(first)
        context.insert(second)
        context.insert(editedDraft)
        try context.save()

        editedDraft.goalDescription = "Unrelated unsaved edit"
        let insertedDraft = Goal(
            name: "New unsaved draft",
            currency: "EUR",
            targetAmount: 750,
            deadline: Date().addingTimeInterval(259_200)
        )
        context.insert(insertedDraft)
        context.processPendingChanges()

        await #expect(throws: DeduplicationError.self) {
            try await service.runFullDeduplication(in: context)
        }

        #expect(editedDraft.goalDescription == "Unrelated unsaved edit")
        #expect(context.changedModelsArray.contains {
            $0.persistentModelID == editedDraft.persistentModelID
        })
        #expect(context.insertedModelsArray.contains {
            $0.persistentModelID == insertedDraft.persistentModelID
        })

        let durableProbe = ModelContext(container)
        #expect(try durableProbe.fetchCount(FetchDescriptor<AssetAllocation>()) == 2)
        #expect(try durableProbe.fetchCount(FetchDescriptor<Goal>()) == 2)
    }

    @Test("Full deduplication success does not commit unrelated pending edits")
    func fullDeduplicationSuccessDoesNotCommitUnrelatedPendingEdits() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        let editedDraft = Goal(
            name: "Existing draft",
            currency: "USD",
            targetAmount: 500,
            deadline: Date().addingTimeInterval(172_800)
        )
        let goalID = UUID()
        context.insert(editedDraft)
        context.insert(MonthlyPlan(
            goalId: goalID,
            monthLabel: "2026-07",
            requiredMonthly: 100,
            remainingAmount: 900,
            monthsRemaining: 9,
            currency: "USD",
            status: .onTrack,
            state: .draft
        ))
        context.insert(MonthlyPlan(
            goalId: goalID,
            monthLabel: "2026-07",
            requiredMonthly: 150,
            remainingAmount: 850,
            monthsRemaining: 9,
            currency: "USD",
            status: .onTrack,
            state: .draft
        ))
        try context.save()

        editedDraft.goalDescription = "Unrelated unsaved edit"
        let insertedDraft = Goal(
            name: "New unsaved draft",
            currency: "EUR",
            targetAmount: 750,
            deadline: Date().addingTimeInterval(259_200)
        )
        context.insert(insertedDraft)
        context.processPendingChanges()

        try await service.runFullDeduplication(in: context)

        #expect(editedDraft.goalDescription == "Unrelated unsaved edit")
        #expect(context.changedModelsArray.contains {
            $0.persistentModelID == editedDraft.persistentModelID
        })
        #expect(context.insertedModelsArray.contains {
            $0.persistentModelID == insertedDraft.persistentModelID
        })

        let durableProbe = ModelContext(container)
        #expect(try durableProbe.fetchCount(FetchDescriptor<MonthlyPlan>()) == 1)
        #expect(try durableProbe.fetchCount(FetchDescriptor<Goal>()) == 1)
        let durableGoal = try #require(
            durableProbe.fetch(FetchDescriptor<Goal>()).first {
                $0.id == editedDraft.id
            }
        )
        #expect(durableGoal.goalDescription == nil)
    }

    @Test("CloudKit monitor surfaces a fail-closed deduplication error")
    func cloudKitMonitorSurfacesDeduplicationFailure() async {
        let monitor = CloudKitHealthMonitor(
            postSyncDeduplication: {
                throw DeduplicationError.unsafeAllocationMerge(
                    assetID: UUID(),
                    requested: 160,
                    available: 100
                )
            }
        )

        await monitor.performPostSyncDeduplication()

        #expect(monitor.syncHealth == .error)
        #expect(monitor.lastSyncError?.contains("160") == true)
        #expect(monitor.lastSyncError?.contains("100") == true)
    }

    @Test("CloudKit deduplicates only after a completed import boundary")
    func cloudKitMonitorWaitsForCompletedImport() async {
        var deduplicationCount = 0
        let monitor = CloudKitHealthMonitor(
            postSyncDeduplication: {
                deduplicationCount += 1
            }
        )

        await monitor.handleSyncBoundary(.startedImport)

        #expect(monitor.syncHealth == .syncing)
        #expect(deduplicationCount == 0)

        await monitor.handleSyncBoundary(.completedExport)
        #expect(monitor.syncHealth == .idle)
        #expect(deduplicationCount == 0)

        await monitor.handleSyncBoundary(.startedImport)
        await monitor.handleSyncBoundary(.completedImport)

        #expect(monitor.syncHealth == .idle)
        #expect(deduplicationCount == 1)
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
        let transaction = Transaction(amount: 150, asset: asset)
        asset.transactions = [transaction]
        context.insert(goal)
        context.insert(asset)
        context.insert(transaction)

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
        #expect(allocations.first!.amount == 150)
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

    @Test("Transaction dedup rekeys linked allocation history to the deterministic survivor")
    func transactionDedupRekeysAllocationHistorySource() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        let asset = Asset(currency: "ETH", address: "0xabc", chainId: "ETH")
        let goal = Goal(
            name: "Cloud conflict",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let sharedDate = Date(timeIntervalSince1970: 1_750_000_000)
        let survivor = Transaction(
            amount: 1,
            asset: asset,
            date: sharedDate,
            source: .onChain,
            externalId: "provider-record"
        )
        survivor.id = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        let duplicate = Transaction(
            amount: 1,
            asset: asset,
            date: sharedDate,
            source: .onChain,
            externalId: "provider-record"
        )
        duplicate.id = UUID(
            uuidString: "00000000-0000-0000-0000-000000000002"
        )!
        let history = AllocationHistory(
            asset: asset,
            goal: goal,
            amount: 1,
            timestamp: sharedDate,
            sourceTransactionId: duplicate.id,
            sourcePreviousAmount: 0
        )
        asset.transactions = [survivor, duplicate]
        asset.allocationHistory = [history]
        goal.allocationHistory = [history]
        context.insert(asset)
        context.insert(goal)
        context.insert(survivor)
        context.insert(duplicate)
        context.insert(history)
        try context.save()

        #expect(try service.deduplicateTransactions(in: context) == 1)
        try context.save()

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        #expect(transactions.map(\.id) == [survivor.id])
        #expect(histories.map(\.sourceTransactionId) == [survivor.id])
        #expect(
            Set(histories.compactMap(\.sourceTransactionId))
                .isSubset(of: Set(transactions.map(\.id)))
        )
    }

    @Test("Conflicting linked transaction provenance aborts every dedup plan")
    func transactionDedupConflictingHistorySourcesFailWithoutPartialState()
        throws
    {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        let asset = Asset(currency: "ETH", address: "0xdef", chainId: "ETH")
        let goal = Goal(
            name: "Conflicting cloud evidence",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let sharedDate = Date(timeIntervalSince1970: 1_750_000_000)

        let safeFirst = Transaction(
            amount: 2,
            asset: asset,
            date: sharedDate,
            source: .onChain,
            externalId: "a-safe-record"
        )
        safeFirst.id = UUID(
            uuidString: "00000000-0000-0000-0000-000000000011"
        )!
        let safeSecond = Transaction(
            amount: 2,
            asset: asset,
            date: sharedDate,
            source: .onChain,
            externalId: "a-safe-record"
        )
        safeSecond.id = UUID(
            uuidString: "00000000-0000-0000-0000-000000000012"
        )!
        let safeHistory = AllocationHistory(
            asset: asset,
            goal: goal,
            amount: 2,
            timestamp: sharedDate,
            sourceTransactionId: safeSecond.id,
            sourcePreviousAmount: 0
        )

        let conflictFirst = Transaction(
            amount: 3,
            asset: asset,
            date: sharedDate,
            source: .onChain,
            externalId: "z-conflicting-record"
        )
        conflictFirst.id = UUID(
            uuidString: "00000000-0000-0000-0000-000000000021"
        )!
        let conflictSecond = Transaction(
            amount: 3,
            asset: asset,
            date: sharedDate,
            source: .onChain,
            externalId: "z-conflicting-record"
        )
        conflictSecond.id = UUID(
            uuidString: "00000000-0000-0000-0000-000000000022"
        )!
        let firstConflictHistory = AllocationHistory(
            asset: asset,
            goal: goal,
            amount: 3,
            timestamp: sharedDate,
            sourceTransactionId: conflictFirst.id,
            sourcePreviousAmount: 0
        )
        let secondConflictHistory = AllocationHistory(
            asset: asset,
            goal: goal,
            amount: 3,
            timestamp: sharedDate,
            sourceTransactionId: conflictSecond.id,
            sourcePreviousAmount: 0
        )

        let originalTransactions = [
            safeFirst,
            safeSecond,
            conflictFirst,
            conflictSecond
        ]
        let originalHistories = [
            safeHistory,
            firstConflictHistory,
            secondConflictHistory
        ]
        asset.transactions = originalTransactions
        asset.allocationHistory = originalHistories
        goal.allocationHistory = originalHistories
        context.insert(asset)
        context.insert(goal)
        originalTransactions.forEach(context.insert)
        originalHistories.forEach(context.insert)
        try context.save()

        do {
            _ = try service.deduplicateTransactions(in: context)
            Issue.record("Expected conflicting transaction allocation provenance")
        } catch let error as DeduplicationError {
            switch error {
            case .conflictingTransactionAllocationProvenance(
                let externalID,
                let transactionIDs,
                let linkedTransactionIDs
            ):
                #expect(externalID == "z-conflicting-record")
                #expect(
                    Set(transactionIDs)
                        == Set([conflictFirst.id, conflictSecond.id])
                )
                #expect(
                    Set(linkedTransactionIDs)
                        == Set([conflictFirst.id, conflictSecond.id])
                )
            default:
                Issue.record("Unexpected deduplication error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        context.processPendingChanges()
        #expect(context.hasChanges == false)
        #expect(
            Set(try context.fetch(FetchDescriptor<Transaction>()).map(\.id))
                == Set(originalTransactions.map(\.id))
        )
        #expect(
            Set(
                try context.fetch(FetchDescriptor<AllocationHistory>())
                    .compactMap(\.sourceTransactionId)
            ) == Set(originalHistories.compactMap(\.sourceTransactionId))
        )
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

    @Test("Goal dedup rewrites historical-only execution evidence to the survivor")
    func goalDedupPreservesHistoricalOnlyExecutionProgress() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = makeService()
        let sharedStart = Date().addingTimeInterval(-3_600)
        let executionStart = Date().addingTimeInterval(-120)

        let duplicate = Goal(
            name: "Execution history",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400),
            startDate: sharedStart
        )
        duplicate.lastModifiedDate = Date().addingTimeInterval(-60)
        let survivor = Goal(
            name: "Execution history",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400),
            startDate: sharedStart
        )
        survivor.lastModifiedDate = Date()

        let asset = Asset(currency: "USD")
        let history = AllocationHistory(
            asset: asset,
            goal: duplicate,
            amount: 100,
            timestamp: executionStart
        )
        history.monthLabel = "2026-03"
        let transaction = Transaction(
            amount: 10,
            asset: asset,
            date: executionStart.addingTimeInterval(60)
        )
        asset.transactions = [transaction]
        asset.allocationHistory = [history]
        duplicate.allocationHistory = [history]

        let record = MonthlyExecutionRecord(
            monthLabel: "2026-03",
            goalIds: [duplicate.id]
        )
        record.status = .executing
        record.startedAt = executionStart

        [duplicate, survivor].forEach(context.insert)
        context.insert(asset)
        context.insert(history)
        context.insert(transaction)
        context.insert(record)
        try context.save()

        #expect(try service.deduplicateGoals(in: context) == 1)
        try context.save()

        #expect(history.goal?.id == survivor.id)
        #expect(history.goalId == survivor.id)
        #expect(record.goalIds == [survivor.id])

        let calculator = ExecutionProgressCalculator(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let totals = try await calculator.contributionTotalsInGoalCurrency(
            for: record,
            end: executionStart.addingTimeInterval(120)
        )
        #expect(totals[survivor.id] == 10)
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
