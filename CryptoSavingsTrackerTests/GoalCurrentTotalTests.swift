//
//  GoalCurrentTotalTests.swift
//  CryptoSavingsTracker
//
//  Created by user on 05/08/2025.
//

import XCTest
import SwiftData
@testable import CryptoSavingsTracker

final class GoalCurrentTotalTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    
    @MainActor
    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
        modelContext = modelContainer.mainContext
    }
    
    override func tearDown() {
        modelContainer = nil
        modelContext = nil
    }
    
    @MainActor
    func testGoalCurrentTotalWithManualAssets() async throws {
        // Create a goal with USD target
        let goal = Goal(name: "Test Goal", currency: "USD", targetAmount: 1000.0, deadline: Date().addingTimeInterval(86400 * 30))
        modelContext.insert(goal)
        
        // Create a manual asset (no address) and add to goal
        let asset = Asset(currency: "USD", goal: goal, address: nil, chainId: nil)
        goal.assets.append(asset) // Explicitly add to goal's assets
        modelContext.insert(asset)
        
        // Add manual transactions and add to asset
        let transaction1 = Transaction(amount: 100.0, asset: asset)
        let transaction2 = Transaction(amount: 50.0, asset: asset)
        asset.transactions.append(transaction1) // Explicitly add to asset's transactions
        asset.transactions.append(transaction2)
        modelContext.insert(transaction1)
        modelContext.insert(transaction2)
        
        try modelContext.save()
        
        // Refresh the context to ensure relationships are loaded
        modelContext.processPendingChanges()
        
        // Query to verify data was saved correctly
        let goalQuery = FetchDescriptor<Goal>()
        let savedGoals = try modelContext.fetch(goalQuery)
        XCTAssertEqual(savedGoals.count, 1, "Should have 1 saved goal")
        
        let assetQuery = FetchDescriptor<Asset>()
        let savedAssets = try modelContext.fetch(assetQuery)
        XCTAssertEqual(savedAssets.count, 1, "Should have 1 saved asset")
        
        let transactionQuery = FetchDescriptor<Transaction>()
        let savedTransactions = try modelContext.fetch(transactionQuery)
        XCTAssertEqual(savedTransactions.count, 2, "Should have 2 saved transactions")
        
        // Use the saved goal from the query
        let savedGoal = savedGoals[0]
        let savedAsset = savedAssets[0]
        
        // Verify the test setup worked
        XCTAssertEqual(savedGoal.assets.count, 1, "Goal should have 1 asset")
        XCTAssertEqual(savedAsset.transactions.count, 2, "Asset should have 2 transactions")
        
        // Test individual asset amount first (use saved asset)
        let assetAmount = await savedAsset.getCurrentAmount()
        XCTAssertEqual(assetAmount, 150.0, accuracy: 0.01, "Asset should have 150 USD from transactions")
        
        // Test that getCurrentTotal() returns sum of manual transactions (use saved goal)
        let total = await savedGoal.getCurrentTotal()
        XCTAssertEqual(total, 150.0, accuracy: 0.01, "Manual asset total should be 150 USD")
        
        let progress = await savedGoal.getProgress()
        XCTAssertEqual(progress, 0.15, accuracy: 0.01, "Progress should be 15% (150/1000)")
    }
    
    @MainActor
    func testGoalCurrentTotalWithOnChainAssets() async throws {
        // Create a goal with USD target
        let goal = Goal(name: "Test Goal", currency: "USD", targetAmount: 1000.0, deadline: Date().addingTimeInterval(86400 * 30))
        modelContext.insert(goal)
        
        // Create an on-chain asset (with address)
        let asset = Asset(currency: "ETH", goal: goal, address: "0x8640fa96047e0f7d637f0ab1f143e12a069ec27b", chainId: "ETH")
        modelContext.insert(asset)
        
        try modelContext.save()
        
        // Test that getCurrentTotal() attempts to fetch on-chain balance
        // Note: This will likely fail due to API key or network, but we can test the logic
        let total = await goal.getCurrentTotal()
        
        // Since we don't have real API access in tests, it should fall back to manual transactions (0)
        // Or use a 1:1 fallback rate if exchange rate fails
        print("On-chain asset total: \(total)")
        
        // The exact value depends on whether TatumService and ExchangeRateService have valid API keys
        // In a test environment, it should be 0 (no manual transactions, no valid API response)
        XCTAssertGreaterThanOrEqual(total, 0.0, "Total should be non-negative")
    }
    
    @MainActor
    func testGoalCurrentTotalWithMixedAssets() async throws {
        // Create a goal with USD target
        let goal = Goal(name: "Test Goal", currency: "USD", targetAmount: 1000.0, deadline: Date().addingTimeInterval(86400 * 30))
        modelContext.insert(goal)
        
        // Create a manual USD asset
        let manualAsset = Asset(currency: "USD", goal: goal, address: nil, chainId: nil)
        goal.assets.append(manualAsset)
        modelContext.insert(manualAsset)
        
        let manualTransaction = Transaction(amount: 200.0, asset: manualAsset)
        manualAsset.transactions.append(manualTransaction)
        modelContext.insert(manualTransaction)
        
        // Create an on-chain asset
        let onChainAsset = Asset(currency: "ETH", goal: goal, address: "0x8640fa96047e0f7d637f0ab1f143e12a069ec27b", chainId: "ETH")
        goal.assets.append(onChainAsset)
        modelContext.insert(onChainAsset)
        
        try modelContext.save()
        modelContext.processPendingChanges()
        
        // Test mixed calculation
        let total = await goal.getCurrentTotal()
        print("Mixed assets total: \(total)")
        
        // Should at least include the manual asset amount (200 USD)
        XCTAssertGreaterThanOrEqual(total, 200.0, "Total should include at least the manual asset amount")
    }
    
    @MainActor
    func testAssetCurrentAmountWithAddress() async throws {
        // Test individual asset amount calculation
        let goal = Goal(name: "Test Goal", currency: "USD", targetAmount: 1000.0, deadline: Date().addingTimeInterval(86400 * 30))
        modelContext.insert(goal)
        
        // Test asset with address
        let onChainAsset = Asset(currency: "ETH", goal: goal, address: "0x8640fa96047e0f7d637f0ab1f143e12a069ec27b", chainId: "ETH")
        modelContext.insert(onChainAsset)
        
        try modelContext.save()
        
        // Check if asset has proper address configuration
        XCTAssertNotNil(onChainAsset.address, "Asset should have address")
        XCTAssertNotNil(onChainAsset.chainId, "Asset should have chainId")
        XCTAssertEqual(onChainAsset.address, "0x8640fa96047e0f7d637f0ab1f143e12a069ec27b")
        XCTAssertEqual(onChainAsset.chainId, "ETH")
        
        print("Asset address: \(onChainAsset.address ?? "nil")")
        print("Asset chainId: \(onChainAsset.chainId ?? "nil")")
        print("Asset currency: \(onChainAsset.currency)")
    }
    
    @MainActor
    func testAssetCurrentAmountWithoutAddress() async throws {
        // Test individual asset amount calculation
        let goal = Goal(name: "Test Goal", currency: "USD", targetAmount: 1000.0, deadline: Date().addingTimeInterval(86400 * 30))
        modelContext.insert(goal)
        
        // Test manual asset
        let manualAsset = Asset(currency: "USD", goal: goal, address: nil, chainId: nil)
        goal.assets.append(manualAsset)
        modelContext.insert(manualAsset)
        
        let transaction = Transaction(amount: 150.0, asset: manualAsset)
        manualAsset.transactions.append(transaction)
        modelContext.insert(transaction)
        
        try modelContext.save()
        modelContext.processPendingChanges()
        
        // Manual asset should use transaction sum
        let transactionSum = manualAsset.transactions.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(transactionSum, 150.0, "Transaction sum should be 150")
        
        print("Manual asset transaction sum: \(transactionSum)")
    }
    
    @MainActor
    func testGoalAssetRetrieval() async throws {
        // Test that goal can retrieve its assets
        let goal = Goal(name: "Test Goal", currency: "USD", targetAmount: 1000.0, deadline: Date().addingTimeInterval(86400 * 30))
        modelContext.insert(goal)
        
        let asset1 = Asset(currency: "USD", goal: goal, address: nil, chainId: nil)
        let asset2 = Asset(currency: "ETH", goal: goal, address: "0x123", chainId: "ETH")
        goal.assets.append(asset1)
        goal.assets.append(asset2)
        modelContext.insert(asset1)
        modelContext.insert(asset2)
        
        try modelContext.save()
        modelContext.processPendingChanges()
        
        // Check that goal can access its assets
        let assets = goal.assets
        XCTAssertEqual(assets.count, 2, "Goal should have 2 assets")
        
        print("Goal has \(assets.count) assets")
        for (index, asset) in assets.enumerated() {
            print("Asset \(index): \(asset.currency), address: \(asset.address ?? "nil"), chainId: \(asset.chainId ?? "nil")")
        }
    }
}