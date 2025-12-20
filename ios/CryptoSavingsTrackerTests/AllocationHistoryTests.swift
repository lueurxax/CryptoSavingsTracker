import SwiftData
import XCTest

@testable import CryptoSavingsTracker

@MainActor
final class AllocationHistoryTests: XCTestCase {

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

    func testUpdateAllocationsRecordsHistoryOnlyOnChange() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let goalA = Goal(name: "Goal A", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86400 * 30))
        let goalB = Goal(name: "Goal B", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86400 * 30))
        let asset = Asset(currency: "BTC")

        context.insert(goalA)
        context.insert(goalB)
        context.insert(asset)
        try context.save()

        // Add transaction after initial save to ensure relationship is properly established
        let tx = Transaction(amount: 1.0, asset: asset)
        asset.transactions.append(tx)
        context.insert(tx)
        try context.save()

        // Verify asset balance is correct before proceeding
        XCTAssertEqual(asset.currentAmount, 1.0, accuracy: 0.0001, "Asset should have 1.0 BTC balance")

        let service = AllocationService(modelContext: context)
        try service.updateAllocations(for: asset, newAllocations: [(goalA, 0.6), (goalB, 0.4)])

        var histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        XCTAssertEqual(histories.count, 2)

        // Same values should not create additional history.
        try service.updateAllocations(for: asset, newAllocations: [(goalA, 0.6), (goalB, 0.4)])
        histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        XCTAssertEqual(histories.count, 2)

        // Change only Goal A.
        try service.updateAllocations(for: asset, newAllocations: [(goalA, 0.5), (goalB, 0.4)])
        histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        XCTAssertEqual(histories.count, 3)
    }

    func testRemoveAllocationRecordsZeroAmountHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let goalA = Goal(name: "Goal A", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86400 * 30))
        let goalB = Goal(name: "Goal B", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86400 * 30))
        let asset = Asset(currency: "BTC")

        context.insert(goalA)
        context.insert(goalB)
        context.insert(asset)
        try context.save()

        // Add transaction after initial save
        let tx = Transaction(amount: 1.0, asset: asset)
        asset.transactions.append(tx)
        context.insert(tx)
        try context.save()

        let service = AllocationService(modelContext: context)
        try service.updateAllocations(for: asset, newAllocations: [(goalA, 0.6), (goalB, 0.4)])

        try service.removeAllocation(for: asset, from: goalB)

        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        XCTAssertTrue(histories.contains(where: { $0.goal?.id == goalB.id && $0.amount == 0 }))
    }

    func testOverAllocatedAfterExternalWithdrawalDoesNotCrash() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let goalA = Goal(name: "Goal A", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86400 * 30))
        let goalB = Goal(name: "Goal B", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86400 * 30))
        let asset = Asset(currency: "BTC")

        context.insert(goalA)
        context.insert(goalB)
        context.insert(asset)
        try context.save()

        // Start with 1.2 BTC so allocations can be saved.
        let deposit = Transaction(amount: 1.2, asset: asset)
        asset.transactions.append(deposit)
        context.insert(deposit)
        try context.save()

        // Verify balance before setting allocations
        XCTAssertEqual(asset.currentAmount, 1.2, accuracy: 0.000001, "Asset should have 1.2 BTC")

        // Set allocations to total 1.2 BTC (fully allocated at this moment).
        let allocA = AssetAllocation(asset: asset, goal: goalA, amount: 0.6)
        let allocB = AssetAllocation(asset: asset, goal: goalB, amount: 0.6)
        asset.allocations.append(allocA)
        asset.allocations.append(allocB)
        context.insert(allocA)
        context.insert(allocB)
        let t0 = Date()
        context.insert(AllocationHistory(asset: asset, goal: goalA, amount: 0.6, timestamp: t0))
        context.insert(AllocationHistory(asset: asset, goal: goalB, amount: 0.6, timestamp: t0))
        try context.save()

        // External withdrawal reduces observed balance to 1.0 BTC.
        let withdrawal = Transaction(amount: -0.2, asset: asset)
        asset.transactions.append(withdrawal)
        context.insert(withdrawal)
        try context.save()

        XCTAssertEqual(asset.currentAmount, 1.0, accuracy: 0.000001)
        XCTAssertEqual(asset.unallocatedAmount, 0, accuracy: 0.000001)
        XCTAssertTrue(asset.isOverAllocated)
        XCTAssertFalse(asset.isFullyAllocated)
    }
}
