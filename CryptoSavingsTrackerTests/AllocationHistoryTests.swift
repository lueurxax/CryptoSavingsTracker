import SwiftData
import XCTest

@testable import CryptoSavingsTracker

final class AllocationHistoryTests: XCTestCase {
    func testUpdateAllocationsRecordsHistoryOnlyOnChange() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Goal.self,
            Asset.self,
            Transaction.self,
            AssetAllocation.self,
            AllocationHistory.self,
            configurations: config
        )
        let context = container.mainContext

        let goalA = Goal(name: "Goal A", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86400 * 30))
        let goalB = Goal(name: "Goal B", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86400 * 30))
        let asset = Asset(currency: "BTC")
        let tx = Transaction(amount: 1.0, asset: asset)
        asset.transactions.append(tx)

        context.insert(goalA)
        context.insert(goalB)
        context.insert(asset)
        context.insert(tx)
        try context.save()

        let service = AllocationService(modelContext: context)
        try service.updateAllocations(for: asset, newAllocations: [goalA: 0.6, goalB: 0.4])

        var histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        XCTAssertEqual(histories.count, 2)

        // Same values should not create additional history.
        try service.updateAllocations(for: asset, newAllocations: [goalA: 0.6, goalB: 0.4])
        histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        XCTAssertEqual(histories.count, 2)

        // Change only Goal A.
        try service.updateAllocations(for: asset, newAllocations: [goalA: 0.5, goalB: 0.4])
        histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        XCTAssertEqual(histories.count, 3)
    }

    func testRemoveAllocationRecordsZeroAmountHistory() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Goal.self,
            Asset.self,
            Transaction.self,
            AssetAllocation.self,
            AllocationHistory.self,
            configurations: config
        )
        let context = container.mainContext

        let goalA = Goal(name: "Goal A", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86400 * 30))
        let goalB = Goal(name: "Goal B", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86400 * 30))
        let asset = Asset(currency: "BTC")
        let tx = Transaction(amount: 1.0, asset: asset)
        asset.transactions.append(tx)

        context.insert(goalA)
        context.insert(goalB)
        context.insert(asset)
        context.insert(tx)
        try context.save()

        let service = AllocationService(modelContext: context)
        try service.updateAllocations(for: asset, newAllocations: [goalA: 0.6, goalB: 0.4])

        try service.removeAllocation(for: asset, from: goalB)

        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        XCTAssertTrue(histories.contains(where: { $0.goal?.id == goalB.id && $0.amount == 0 }))
    }

    func testOverAllocatedAfterExternalWithdrawalDoesNotCrash() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Goal.self,
            Asset.self,
            Transaction.self,
            AssetAllocation.self,
            AllocationHistory.self,
            configurations: config
        )
        let context = container.mainContext

        let goalA = Goal(name: "Goal A", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86400 * 30))
        let goalB = Goal(name: "Goal B", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86400 * 30))
        let asset = Asset(currency: "BTC")

        // Start with 1.2 BTC so allocations can be saved.
        let deposit = Transaction(amount: 1.2, asset: asset)
        asset.transactions.append(deposit)
        context.insert(goalA)
        context.insert(goalB)
        context.insert(asset)
        context.insert(deposit)
        try context.save()

        let service = AllocationService(modelContext: context)
        try service.updateAllocations(for: asset, newAllocations: [goalA: 0.6, goalB: 0.6]) // fully allocated

        // External withdrawal reduces observed balance to 1.0 BTC.
        let withdrawal = Transaction(amount: -0.2, asset: asset)
        asset.transactions.append(withdrawal)
        context.insert(withdrawal)
        try context.save()

        XCTAssertEqual(asset.currentAmount, 1.0, accuracy: 0.000001)
        XCTAssertEqual(asset.unallocatedAmount, 0, accuracy: 0.000001)
        XCTAssertTrue(asset.isFullyAllocated)
    }
}

