//
//  IntegrationTests.swift
//  CryptoSavingsTrackerTests
//
//  Created by user on 27/07/2025.
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

@MainActor struct IntegrationTests {
    
    // MARK: - Test Setup
    
    @MainActor func createTestContainer() throws -> ModelContainer {
        let schema = Schema([Goal.self, Asset.self, Transaction.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
    
    // MARK: - Data Persistence Integration Tests
    
    @Test @MainActor func fullDataFlowPersistence() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create a complete goal with assets and transactions
        let calendar = Calendar.current
        let deadline = calendar.date(byAdding: .month, value: 3, to: Date())!
        
        let goal = Goal(
            name: "Integration Test Goal",
            currency: "USD",
            targetAmount: 10000,
            deadline: deadline,
            frequency: .weekly
        )
        
        let btcAsset = Asset(currency: "BTC", goal: goal)
        let ethAsset = Asset(currency: "ETH", goal: goal)
        let usdAsset = Asset(currency: "USD", goal: goal)
        
        // Explicitly establish relationships
        goal.assets.append(btcAsset)
        goal.assets.append(ethAsset)
        goal.assets.append(usdAsset)
        
        context.insert(goal)
        context.insert(btcAsset)
        context.insert(ethAsset)
        context.insert(usdAsset)
        
        // Add transactions to each asset
        let btcTransaction1 = Transaction(amount: 0.1, asset: btcAsset)
        let btcTransaction2 = Transaction(amount: 0.05, asset: btcAsset)
        let ethTransaction1 = Transaction(amount: 2.5, asset: ethAsset)
        let usdTransaction1 = Transaction(amount: 1000, asset: usdAsset)
        
        btcAsset.transactions.append(btcTransaction1)
        btcAsset.transactions.append(btcTransaction2)
        ethAsset.transactions.append(ethTransaction1)
        usdAsset.transactions.append(usdTransaction1)
        
        context.insert(btcTransaction1)
        context.insert(btcTransaction2)
        context.insert(ethTransaction1)
        context.insert(usdTransaction1)
        
        try context.save()
        context.processPendingChanges()
        
        // Verify the complete data structure persisted correctly
        let goalDescriptor = FetchDescriptor<Goal>()
        let fetchedGoals = try context.fetch(goalDescriptor)
        
        #expect(fetchedGoals.count == 1)
        let fetchedGoal = fetchedGoals[0]
        
        #expect(fetchedGoal.name == "Integration Test Goal")
        #expect(fetchedGoal.assets.count == 3)
        
        // Verify asset amounts are calculated correctly
        let fetchedBtcAsset = fetchedGoal.assets.first { $0.currency == "BTC" }!
        let fetchedEthAsset = fetchedGoal.assets.first { $0.currency == "ETH" }!
        let fetchedUsdAsset = fetchedGoal.assets.first { $0.currency == "USD" }!
        
        #expect(fetchedBtcAsset.currentAmount == 0.15) // 0.1 + 0.05
        #expect(fetchedEthAsset.currentAmount == 2.5)
        #expect(fetchedUsdAsset.currentAmount == 1000)
        
        // Verify transactions are properly linked
        #expect(fetchedBtcAsset.transactions.count == 2)
        #expect(fetchedEthAsset.transactions.count == 1)
        #expect(fetchedUsdAsset.transactions.count == 1)
    }
    
    @Test @MainActor func cascadingDeleteBehavior() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create goal with assets and transactions
        let goal = Goal(name: "Delete Test", currency: "USD", targetAmount: 1000, deadline: Date())
        let asset = Asset(currency: "BTC", goal: goal)
        let transaction = Transaction(amount: 100, asset: asset)
        
        // Explicitly establish relationships
        goal.assets.append(asset)
        asset.transactions.append(transaction)
        
        context.insert(goal)
        context.insert(asset)
        context.insert(transaction)
        try context.save()
        context.processPendingChanges()
        
        // Verify everything exists
        #expect(try context.fetch(FetchDescriptor<Goal>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Asset>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 1)
        
        // Delete the goal
        context.delete(goal)
        try context.save()
        
        // Verify cascading delete worked
        #expect(try context.fetch(FetchDescriptor<Goal>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<Asset>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 0)
    }
    
    @Test @MainActor func dataConsistencyAfterUpdates() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Update Test", currency: "USD", targetAmount: 5000, deadline: Date())
        let asset = Asset(currency: "USD", goal: goal)
        
        // Explicitly establish relationships
        goal.assets.append(asset)
        
        context.insert(goal)
        context.insert(asset)
        try context.save()
        context.processPendingChanges()
        
        // Add initial transaction
        let transaction1 = Transaction(amount: 1000, asset: asset)
        asset.transactions.append(transaction1)
        context.insert(transaction1)
        try context.save()
        context.processPendingChanges()
        
        // Verify initial state
        #expect(asset.currentAmount == 1000)
        
        // Add another transaction
        let transaction2 = Transaction(amount: 500, asset: asset)
        asset.transactions.append(transaction2)
        context.insert(transaction2)
        try context.save()
        context.processPendingChanges()
        
        // Verify updated state
        #expect(asset.currentAmount == 1500)
        
        // Update existing transaction
        transaction1.amount = 1200
        try context.save()
        
        // Verify consistency after update
        #expect(asset.currentAmount == 1700) // 1200 + 500
        
        // Delete one transaction
        context.delete(transaction2)
        try context.save()
        
        // Verify consistency after deletion
        #expect(asset.currentAmount == 1200)
    }
    
    // MARK: - Currency Conversion Integration Tests
    
    @Test @MainActor func multiCurrencyGoalCalculation() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Multi Currency Goal", currency: "USD", targetAmount: 10000, deadline: Date())
        let usdAsset = Asset(currency: "USD", goal: goal)
        let eurAsset = Asset(currency: "EUR", goal: goal)
        
        // Explicitly establish relationships
        goal.assets.append(usdAsset)
        goal.assets.append(eurAsset)
        
        context.insert(goal)
        context.insert(usdAsset)
        context.insert(eurAsset)
        
        let usdTransaction = Transaction(amount: 5000, asset: usdAsset)
        let eurTransaction = Transaction(amount: 3000, asset: eurAsset)
        
        usdAsset.transactions.append(usdTransaction)
        eurAsset.transactions.append(eurTransaction)
        
        context.insert(usdTransaction)
        context.insert(eurTransaction)
        try context.save()
        context.processPendingChanges()
        
        // Test synchronous calculation (no conversion)
        let syncTotal = goal.currentTotal
        #expect(syncTotal == 8000) // 5000 USD + 3000 EUR (no conversion)
        
        // Test async calculation (with conversion attempt)
        let asyncTotal = await GoalCalculationService.getCurrentTotal(for: goal)
        // The exact value depends on exchange rate service, but should be different from sync
        // In fallback mode, it might still be 8000 if conversion fails
        #expect(asyncTotal >= 8000) // Should at least equal the fallback
    }
    
    @Test @MainActor func progressCalculationConsistency() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Progress Test", currency: "USD", targetAmount: 1000, deadline: Date())
        let asset = Asset(currency: "USD", goal: goal)
        
        // Explicitly establish relationships
        goal.assets.append(asset)
        
        context.insert(goal)
        context.insert(asset)
        try context.save()
        context.processPendingChanges()
        
        // Test with no transactions
        #expect(goal.progress == 0.0)
        #expect(await GoalCalculationService.getProgress(for: goal) == 0.0)
        
        // Add transaction for 25% progress
        let transaction = Transaction(amount: 250, asset: asset)
        asset.transactions.append(transaction)
        context.insert(transaction)
        try context.save()
        context.processPendingChanges()
        
        #expect(goal.progress == 0.25)
        #expect(await GoalCalculationService.getProgress(for: goal) == 0.25)
        
        // Add transaction for over 100% progress
        let largeTransaction = Transaction(amount: 1000, asset: asset)
        asset.transactions.append(largeTransaction)
        context.insert(largeTransaction)
        try context.save()
        context.processPendingChanges()
        
        // Both should cap at 1.0
        #expect(goal.progress == 1.0)
        #expect(await GoalCalculationService.getProgress(for: goal) == 1.0)
    }
    
    // MARK: - Reminder System Integration Tests
    
    @Test func reminderDateCalculation() throws {
        let calendar = Calendar.current
        let startDate = Date()
        let endDate = calendar.date(byAdding: .month, value: 2, to: startDate)!
        
        // Test weekly reminders
        let weeklyGoal = Goal(
            name: "Weekly Reminders",
            currency: "USD",
            targetAmount: 1000,
            deadline: endDate,
            startDate: startDate,
            frequency: .weekly
        )
        
        let weeklyDates = weeklyGoal.reminderDates
        #expect(weeklyDates.count >= 8) // Should have at least 8 weekly reminders in 2 months
        
        // Test monthly reminders
        let monthlyGoal = Goal(
            name: "Monthly Reminders",
            currency: "USD",
            targetAmount: 1000,
            deadline: endDate,
            startDate: startDate,
            frequency: .monthly
        )
        
        let monthlyDates = monthlyGoal.reminderDates
        #expect(monthlyDates.count == 3) // Should have 3 monthly reminders (0, 1, 2 months)
        
        // Test biweekly reminders
        let biweeklyGoal = Goal(
            name: "Biweekly Reminders",
            currency: "USD",
            targetAmount: 1000,
            deadline: endDate,
            startDate: startDate,
            frequency: .biweekly
        )
        
        let biweeklyDates = biweeklyGoal.reminderDates
        #expect(biweeklyDates.count >= 4) // Should have at least 4 biweekly reminders in 2 months
    }
    
    @Test func reminderDateFiltering() throws {
        let calendar = Calendar.current
        let pastDate = calendar.date(byAdding: .day, value: -10, to: Date())!
        let futureDate = calendar.date(byAdding: .day, value: 20, to: Date())!
        
        let goal = Goal(
            name: "Date Filter Test",
            currency: "USD",
            targetAmount: 1000,
            deadline: futureDate,
            startDate: pastDate,
            frequency: .weekly
        )
        
        let allDates = goal.reminderDates
        let remainingDates = goal.remainingDates
        
        // Should have more total dates than remaining dates
        #expect(allDates.count > remainingDates.count)
        
        // All remaining dates should be today or in the future
        let today = calendar.startOfDay(for: Date())
        for date in remainingDates {
            let reminderDay = calendar.startOfDay(for: date)
            #expect(reminderDay >= today)
        }
        
        // Next reminder should be the first remaining date
        if let nextReminder = goal.nextReminder {
            #expect(nextReminder == remainingDates.first)
        }
    }
    
    // MARK: - Complex Scenario Tests
    
    @Test @MainActor func multipleGoalsWithSharedAssetTypes() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create two goals that both use BTC
        let goal1 = Goal(name: "Goal 1", currency: "USD", targetAmount: 5000, deadline: Date())
        let goal2 = Goal(name: "Goal 2", currency: "EUR", targetAmount: 3000, deadline: Date())
        
        let btcAsset1 = Asset(currency: "BTC", goal: goal1)
        let btcAsset2 = Asset(currency: "BTC", goal: goal2)
        
        // Explicitly establish relationships
        goal1.assets.append(btcAsset1)
        goal2.assets.append(btcAsset2)
        
        context.insert(goal1)
        context.insert(goal2)
        context.insert(btcAsset1)
        context.insert(btcAsset2)
        
        let transaction1 = Transaction(amount: 0.1, asset: btcAsset1)
        let transaction2 = Transaction(amount: 0.2, asset: btcAsset2)
        
        btcAsset1.transactions.append(transaction1)
        btcAsset2.transactions.append(transaction2)
        
        context.insert(transaction1)
        context.insert(transaction2)
        try context.save()
        context.processPendingChanges()
        
        // Verify each goal tracks its own BTC separately
        #expect(btcAsset1.currentAmount == 0.1)
        #expect(btcAsset2.currentAmount == 0.2)
        
        // Verify goals are independent
        #expect(goal1.assets.count == 1)
        #expect(goal2.assets.count == 1)
        #expect(goal1.assets.first !== goal2.assets.first)
    }
    
    @Test @MainActor func goalCompletionScenario() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Completion Test", currency: "USD", targetAmount: 1000, deadline: Date())
        let asset = Asset(currency: "USD", goal: goal)
        
        // Explicitly establish relationships
        goal.assets.append(asset)
        
        context.insert(goal)
        context.insert(asset)
        
        // Gradually add transactions to reach completion
        let transactions = [
            Transaction(amount: 200, asset: asset),
            Transaction(amount: 300, asset: asset),
            Transaction(amount: 250, asset: asset),
            Transaction(amount: 350, asset: asset) // Total: 1100, over target
        ]
        
        for transaction in transactions {
            asset.transactions.append(transaction)
            context.insert(transaction)
        }
        try context.save()
        context.processPendingChanges()
        
        // Verify completion
        let total = await GoalCalculationService.getCurrentTotal(for: goal)
        let progress = await GoalCalculationService.getProgress(for: goal)
        
        #expect(total == 1100)
        #expect(progress == 1.0) // Capped at 100%
        #expect(total >= goal.targetAmount) // Goal is complete
        
        // Suggested deposit should be 0 for completed goals
        let suggested = await goal.getSuggestedDeposit()
        #expect(suggested == 0.0)
    }
    
    @Test @MainActor func edgeCaseHandling() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Test goal with zero target amount
        let zeroGoal = Goal(name: "Zero Goal", currency: "USD", targetAmount: 0, deadline: Date())
        context.insert(zeroGoal)
        
        // Test asset with negative transactions (withdrawals)
        let normalGoal = Goal(name: "Normal Goal", currency: "USD", targetAmount: 1000, deadline: Date())
        let asset = Asset(currency: "USD", goal: normalGoal)
        
        // Explicitly establish relationships
        normalGoal.assets.append(asset)
        
        context.insert(normalGoal)
        context.insert(asset)
        
        let deposit = Transaction(amount: 500, asset: asset)
        let withdrawal = Transaction(amount: -200, asset: asset)
        
        asset.transactions.append(deposit)
        asset.transactions.append(withdrawal)
        
        context.insert(deposit)
        context.insert(withdrawal)
        try context.save()
        context.processPendingChanges()
        
        // Verify handling of negative transactions
        #expect(asset.currentAmount == 300) // 500 - 200
        #expect(normalGoal.progress == 0.3) // 300/1000
        
        // Verify zero target handling
        #expect(zeroGoal.progress == 0.0)
    }
    
    // MARK: - Performance Integration Tests
    
    @Test @MainActor func largeDataSetPerformance() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create a goal with many assets and transactions
        let goal = Goal(name: "Performance Test", currency: "USD", targetAmount: 100000, deadline: Date())
        context.insert(goal)
        
        var assets: [Asset] = []
        let assetCount = 50
        let transactionsPerAsset = 20
        
        // Create many assets
        for i in 0..<assetCount {
            let asset = Asset(currency: "ASSET\(i)", goal: goal)
            assets.append(asset)
            goal.assets.append(asset) // Explicitly establish relationship
            context.insert(asset)
        }
        
        // Create many transactions
        for asset in assets {
            for j in 0..<transactionsPerAsset {
                let transaction = Transaction(amount: Double(j + 1), asset: asset)
                asset.transactions.append(transaction) // Explicitly establish relationship
                context.insert(transaction)
            }
        }
        
        try context.save()
        context.processPendingChanges()
        
        // Verify the large dataset
        #expect(goal.assets.count == assetCount)
        
        let totalTransactions = goal.assets.reduce(0) { $0 + $1.transactions.count }
        #expect(totalTransactions == assetCount * transactionsPerAsset)
        
        // Test performance of calculations on large dataset
        let startTime = Date()
        let total = goal.currentTotal
        let endTime = Date()
        
        // Should complete calculation in reasonable time (less than 1 second)
        let calculationTime = endTime.timeIntervalSince(startTime)
        #expect(calculationTime < 1.0)
        
        // Verify calculation correctness
        // Each asset should have sum 1+2+...+20 = 210
        let expectedTotal = Double(assetCount) * 210.0
        #expect(total == expectedTotal)
    }
}