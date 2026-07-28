import SwiftData
import XCTest

@testable import CryptoSavingsTracker

@MainActor
final class ExecutionProgressCalculatorTests: XCTestCase {
    private final class MockExchangeRateService: ExchangeRateServiceProtocol {
        func fetchRate(from: String, to: String) async throws -> Double {
            if from.uppercased() == to.uppercased() { return 1 }
            return 10_000
        }

        func hasValidConfiguration() -> Bool { true }
        func setOfflineMode(_ offline: Bool) { }
        func refreshRatesIfStale() async { }
    }

    private func makeContainer() throws -> ModelContainer {
        // Use the same schema as the main app for consistency
        let schema = Schema([
            Goal.self,
            Asset.self,
            Transaction.self,
            MonthlyPlan.self,
            AssetAllocation.self,
            AllocationHistory.self,
            MonthlyExecutionRecord.self,
            CompletedExecution.self,
            CompletionEvent.self,
            ExecutionSnapshot.self
        ])
        let config = ModelConfiguration(
            "testStore",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testTransactionsBeforeStartedAtDoNotCount() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let txAfter = start.addingTimeInterval(3600)

        let container = try makeContainer()
        let context = container.mainContext

        let goal = Goal(name: "Goal A", currency: "USD", targetAmount: 1000, deadline: start.addingTimeInterval(86400))
        let asset = Asset(currency: "BTC")

        let txBeforeStart = Transaction(amount: 1.0, asset: asset)
        txBeforeStart.date = start.addingTimeInterval(-3600)
        let txAfterStart = Transaction(amount: 0.5, asset: asset)
        txAfterStart.date = txAfter

        asset.transactions = (asset.transactions ?? []) + [txBeforeStart, txAfterStart]

        // Dedicated + fully allocated at start (target == balance at start).
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 1.0)
        asset.allocations = (asset.allocations ?? []) + [allocation]

        // Baseline at start, and auto-allocation snapshot at tx timestamp (target tracks new balance).
        context.insert(goal)
        context.insert(asset)
        context.insert(txBeforeStart)
        context.insert(txAfterStart)
        context.insert(allocation)
        context.insert(AllocationHistory(asset: asset, goal: goal, amount: 1.0, timestamp: start))
        context.insert(AllocationHistory(asset: asset, goal: goal, amount: 1.5, timestamp: txAfter))
        try context.save()

        let record = MonthlyExecutionRecord(monthLabel: "2023-11", goalIds: [goal.id])
        record.statusRawValue = "executing"
        record.startedAt = start
        context.insert(record)
        try context.save()

        let calculator = ExecutionProgressCalculator(modelContext: context, exchangeRateService: MockExchangeRateService())
        let totals = try await calculator.contributionTotalsInGoalCurrency(for: record, end: txAfter.addingTimeInterval(1))

        XCTAssertEqual(totals[goal.id] ?? 0, 0.5 * 10_000, accuracy: 0.0001)
    }

    func testSharedAssetDepositDoesNotCountWhenUnallocatedExists() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let txAfter = start.addingTimeInterval(3600)

        let container = try makeContainer()
        let context = container.mainContext

        let goalA = Goal(name: "Goal A", currency: "USD", targetAmount: 1000, deadline: start.addingTimeInterval(86400))
        let goalB = Goal(name: "Goal B", currency: "USD", targetAmount: 1000, deadline: start.addingTimeInterval(86400))
        let asset = Asset(currency: "BTC")

        let txBeforeStart = Transaction(amount: 1.0, asset: asset)
        txBeforeStart.date = start.addingTimeInterval(-3600)
        let txAfterStart = Transaction(amount: 0.5, asset: asset)
        txAfterStart.date = txAfter
        asset.transactions = (asset.transactions ?? []) + [txBeforeStart, txAfterStart]

        // Shared but under-allocated at start (targets total 0.8 < balance 1.0).
        context.insert(goalA)
        context.insert(goalB)
        context.insert(asset)
        context.insert(txBeforeStart)
        context.insert(txAfterStart)
        context.insert(AllocationHistory(asset: asset, goal: goalA, amount: 0.4, timestamp: start))
        context.insert(AllocationHistory(asset: asset, goal: goalB, amount: 0.4, timestamp: start))
        try context.save()

        let record = MonthlyExecutionRecord(monthLabel: "2023-11", goalIds: [goalA.id, goalB.id])
        record.statusRawValue = "executing"
        record.startedAt = start
        context.insert(record)
        try context.save()

        let calculator = ExecutionProgressCalculator(modelContext: context, exchangeRateService: MockExchangeRateService())
        let totals = try await calculator.contributionTotalsInGoalCurrency(for: record, end: txAfter.addingTimeInterval(1))

        XCTAssertEqual(totals[goalA.id] ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(totals[goalB.id] ?? 0, 0, accuracy: 0.0001)
    }

    func testDedicatedAssetDepositCountsWithoutAllocationHistory() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let txAfter = start.addingTimeInterval(3600)

        let container = try makeContainer()
        let context = container.mainContext

        let goal = Goal(name: "Goal A", currency: "USD", targetAmount: 1000, deadline: start.addingTimeInterval(86400))
        let asset = Asset(currency: "BTC")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 0.01)

        let tx = Transaction(amount: 0.01, asset: asset, date: txAfter)
        asset.transactions = (asset.transactions ?? []) + [tx]

        context.insert(goal)
        context.insert(asset)
        context.insert(allocation)
        context.insert(tx)
        try context.save()

        let record = MonthlyExecutionRecord(monthLabel: "2023-11", goalIds: [goal.id])
        record.statusRawValue = "executing"
        record.startedAt = start
        context.insert(record)
        try context.save()

        let calculator = ExecutionProgressCalculator(modelContext: context, exchangeRateService: MockExchangeRateService())
        let totals = try await calculator.contributionTotalsInGoalCurrency(for: record, end: txAfter.addingTimeInterval(1))

        XCTAssertEqual(totals[goal.id] ?? 0, 0.01 * 10_000, accuracy: 0.0001)
    }

    func testOverAllocatedSharedAssetDepositFundsGoalsProportionally() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let txAfter = start.addingTimeInterval(3600)

        let container = try makeContainer()
        let context = container.mainContext

        let goalA = Goal(name: "Goal A", currency: "USD", targetAmount: 1000, deadline: start.addingTimeInterval(86400))
        let goalB = Goal(name: "Goal B", currency: "USD", targetAmount: 1000, deadline: start.addingTimeInterval(86400))
        let asset = Asset(currency: "BTC")

        let txBeforeStart = Transaction(amount: 1.0, asset: asset)
        txBeforeStart.date = start.addingTimeInterval(-3600)
        let txAfterStart = Transaction(amount: 0.2, asset: asset)
        txAfterStart.date = txAfter
        asset.transactions = (asset.transactions ?? []) + [txBeforeStart, txAfterStart]

        // Over-allocated at start (targets total 1.2 > balance 1.0).
        context.insert(goalA)
        context.insert(goalB)
        context.insert(asset)
        context.insert(txBeforeStart)
        context.insert(txAfterStart)
        context.insert(AllocationHistory(asset: asset, goal: goalA, amount: 0.6, timestamp: start))
        context.insert(AllocationHistory(asset: asset, goal: goalB, amount: 0.6, timestamp: start))
        try context.save()

        let record = MonthlyExecutionRecord(monthLabel: "2023-11", goalIds: [goalA.id, goalB.id])
        record.statusRawValue = "executing"
        record.startedAt = start
        context.insert(record)
        try context.save()

        let calculator = ExecutionProgressCalculator(modelContext: context, exchangeRateService: MockExchangeRateService())
        let totals = try await calculator.contributionTotalsInGoalCurrency(for: record, end: txAfter.addingTimeInterval(1))

        // Balance: 1.0 -> 1.2, targets 0.6/0.6 => funded per goal: 0.5 -> 0.6 => +0.1 BTC each.
        XCTAssertEqual(totals[goalA.id] ?? 0, 0.1 * 10_000, accuracy: 0.0001)
        XCTAssertEqual(totals[goalB.id] ?? 0, 0.1 * 10_000, accuracy: 0.0001)
    }

    func testSameTimestampAllocationHistoryUsesLatestCreatedAt() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = start.addingTimeInterval(3600)

        let container = try makeContainer()
        let context = container.mainContext

        let goal = Goal(name: "Goal A", currency: "USD", targetAmount: 1000, deadline: start.addingTimeInterval(86400))
        let asset = Asset(currency: "BTC")

        // Transaction at the same timestamp as two history snapshots.
        let tx = Transaction(amount: 0.01, asset: asset, date: ts)
        asset.transactions = (asset.transactions ?? []) + [tx]

        context.insert(goal)
        context.insert(asset)
        context.insert(tx)

        // Two allocation snapshots with the same timestamp: initial 0 and later 0.01.
        let initial = AllocationHistory(asset: asset, goal: goal, amount: 0, timestamp: ts)
        let later = AllocationHistory(asset: asset, goal: goal, amount: 0.01, timestamp: ts)
        initial.createdAt = ts
        later.createdAt = ts.addingTimeInterval(0.001)
        context.insert(initial)
        context.insert(later)
        try context.save()

        let record = MonthlyExecutionRecord(monthLabel: "2023-11", goalIds: [goal.id])
        record.statusRawValue = "executing"
        record.startedAt = start
        context.insert(record)
        try context.save()

        let calculator = ExecutionProgressCalculator(modelContext: context, exchangeRateService: MockExchangeRateService())
        let totals = try await calculator.contributionTotalsInGoalCurrency(for: record, end: ts.addingTimeInterval(1))

        XCTAssertEqual(totals[goal.id] ?? 0, 0.01 * 10_000, accuracy: 0.0001)
    }

    func testUnmatchedLegacyOnChainMovementDoesNotCountUntilCanonicalRefresh() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let transactionDate = start.addingTimeInterval(3_600)
        let container = try makeContainer()
        let context = container.mainContext

        let goal = Goal(
            name: "Verified history",
            currency: "USDT",
            targetAmount: 100,
            deadline: start.addingTimeInterval(86_400)
        )
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "USDT", address: trackedAddress, chainId: "ETH")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 5)
        let unmatchedLegacy = Transaction(
            amount: 5,
            asset: asset,
            date: transactionDate,
            source: .onChain,
            externalId: "unmatched-hash",
            comment: "Preserve until proven"
        )
        asset.transactions = [unmatchedLegacy]
        asset.allocations = [allocation]
        goal.allocations = [allocation]

        context.insert(goal)
        context.insert(asset)
        context.insert(allocation)
        context.insert(unmatchedLegacy)
        context.insert(AllocationHistory(asset: asset, goal: goal, amount: 5, timestamp: start))
        let record = MonthlyExecutionRecord(monthLabel: "2023-11", goalIds: [goal.id])
        record.statusRawValue = "executing"
        record.startedAt = start
        context.insert(record)
        try context.save()

        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "ETH",
            address: trackedAddress,
            symbol: "USDT"
        )
        BalanceCacheManager.shared.cacheBalance(5, for: cacheKey)

        let calculator = ExecutionProgressCalculator(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let beforeRefresh = try await calculator.contributionTotalsInGoalCurrency(
            for: record,
            end: transactionDate.addingTimeInterval(1)
        )
        XCTAssertEqual(beforeRefresh[goal.id] ?? 0, 0, accuracy: 0.0001)

        let canonical = TatumTransaction(
            hash: "unmatched-hash",
            timestamp: Int(transactionDate.timeIntervalSince1970 * 1_000),
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "5",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7"
        )
        XCTAssertEqual(
            try OnChainTransactionImportService(modelContext: context).upsert(
                transactions: [canonical],
                for: asset
            ),
            1
        )
        XCTAssertEqual(asset.transactions?.count, 1)
        XCTAssertEqual(asset.transactions?.first?.id, unmatchedLegacy.id)

        let afterRefresh = try await calculator.contributionTotalsInGoalCurrency(
            for: record,
            end: transactionDate.addingTimeInterval(1)
        )
        XCTAssertEqual(afterRefresh[goal.id] ?? 0, 5, accuracy: 0.0001)
    }

    func testLegacyQuickCanonicalMovementIsQuarantinedWhileCurrentContractRemainsEligible() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let transactionDate = start.addingTimeInterval(3_600)
        let container = try makeContainer()
        let context = container.mainContext

        let goal = Goal(
            name: "Current QUICK only",
            currency: "QUICK",
            targetAmount: 10,
            deadline: start.addingTimeInterval(86_400)
        )
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "QUICK", address: trackedAddress, chainId: "MATIC")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 1)
        let movement = Transaction(
            amount: 1,
            asset: asset,
            date: transactionDate,
            source: .onChain,
            externalId: """
            onchain_v3|matic|0x00000000000000000000000000000000000000aa|quick|00000000-0000-0000-0000-000000000003|legacy-quick|polygon-mainnet|0x00000000000000000000000000000000000000aa||fungible|0x831753dd7087cac61ab5644b308642cc1c33dc13|incoming||||3ff0000000000000|
            """
        )
        asset.transactions = [movement]
        asset.allocations = [allocation]
        goal.allocations = [allocation]

        context.insert(goal)
        context.insert(asset)
        context.insert(allocation)
        context.insert(movement)
        context.insert(AllocationHistory(asset: asset, goal: goal, amount: 1, timestamp: start))
        let record = MonthlyExecutionRecord(monthLabel: "2023-11", goalIds: [goal.id])
        record.statusRawValue = "executing"
        record.startedAt = start
        context.insert(record)
        try context.save()

        let cacheKey = BalanceCacheManager.balanceCacheKey(
            chainId: "MATIC",
            address: trackedAddress,
            symbol: "QUICK"
        )
        BalanceCacheManager.shared.cacheBalance(1, for: cacheKey)

        let calculator = ExecutionProgressCalculator(
            modelContext: context,
            exchangeRateService: MockExchangeRateService()
        )
        let legacyTotals = try await calculator.contributionTotalsInGoalCurrency(
            for: record,
            end: transactionDate.addingTimeInterval(1)
        )
        XCTAssertEqual(legacyTotals[goal.id] ?? 0, 0, accuracy: 0.0001)

        movement.externalId = """
        onchain_v3|matic|0x00000000000000000000000000000000000000aa|quick|00000000-0000-0000-0000-000000000003|current-quick|polygon-mainnet|0x00000000000000000000000000000000000000aa||fungible|0xb5c064f955d8e7f38fe0460c556a72987494ee17|incoming||||3ff0000000000000|
        """
        let currentTotals = try await calculator.contributionTotalsInGoalCurrency(
            for: record,
            end: transactionDate.addingTimeInterval(1)
        )
        XCTAssertEqual(currentTotals[goal.id] ?? 0, 1, accuracy: 0.0001)
    }
}
