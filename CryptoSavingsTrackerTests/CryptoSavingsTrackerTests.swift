//
//  CryptoSavingsTrackerTests.swift
//  CryptoSavingsTrackerTests
//
//  Created by user on 25/07/2025.
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

@MainActor struct CryptoSavingsTrackerTests {
    
    // MARK: - Test Setup
    
    @MainActor func createTestContainer() throws -> ModelContainer {
        let schema = Schema([Goal.self, Asset.self, Transaction.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
    
    // MARK: - ReminderFrequency Tests
    
    @Test func reminderFrequencyDisplayNames() {
        #expect(ReminderFrequency.weekly.displayName == "Weekly")
        #expect(ReminderFrequency.biweekly.displayName == "Bi-weekly")
        #expect(ReminderFrequency.monthly.displayName == "Monthly")
    }
    
    @Test func reminderFrequencyDateComponents() {
        #expect(ReminderFrequency.weekly.dateComponents == DateComponents(day: 7))
        #expect(ReminderFrequency.biweekly.dateComponents == DateComponents(day: 14))
        #expect(ReminderFrequency.monthly.dateComponents == DateComponents(month: 1))
    }
    
    @Test func reminderFrequencyIdentifiable() {
        #expect(ReminderFrequency.weekly.id == "weekly")
        #expect(ReminderFrequency.biweekly.id == "biweekly")
        #expect(ReminderFrequency.monthly.id == "monthly")
    }
    
    // MARK: - Goal Model Tests
    
    @Test func goalInitialization() throws {
        let deadline = Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days from now
        let goal = Goal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 1000.0,
            deadline: deadline,
            frequency: .weekly
        )
        
        #expect(goal.name == "Test Goal")
        #expect(goal.currency == "USD")
        #expect(goal.targetAmount == 1000.0)
        #expect(goal.deadline == deadline)
        #expect(goal.frequency == .weekly)
        #expect(goal.assets.isEmpty)
    }
    
    @Test func goalDefaultValues() throws {
        let deadline = Date().addingTimeInterval(30 * 24 * 60 * 60)
        let goal = Goal(
            name: "Default Goal",
            currency: "EUR",
            targetAmount: 500.0,
            deadline: deadline
        )
        
        // Test default frequency
        #expect(goal.frequency == .weekly)
        
        // Test default start date is recent
        let timeDifference = abs(goal.startDate.timeIntervalSinceNow)
        #expect(timeDifference < 5.0) // Should be within 5 seconds of now
    }
    
    @Test @MainActor func goalDaysRemaining() throws {
        let calendar = Calendar.current
        let baseDate = Date()
        let futureDate = calendar.date(byAdding: .day, value: 10, to: baseDate)!
        let pastDate = calendar.date(byAdding: .day, value: -5, to: baseDate)!
        
        let futureGoal = Goal(name: "Future", currency: "USD", targetAmount: 100, deadline: futureDate)
        let pastGoal = Goal(name: "Past", currency: "USD", targetAmount: 100, deadline: pastDate)
        
        // Allow for some variance due to timing
        #expect(futureGoal.daysRemaining >= 9 && futureGoal.daysRemaining <= 10)
        #expect(pastGoal.daysRemaining == 0) // Should not be negative
    }
    
    @Test func goalReminderDates() throws {
        let calendar = Calendar.current
        let startDate = Date()
        let endDate = calendar.date(byAdding: .day, value: 21, to: startDate)! // 3 weeks
        
        let goal = Goal(
            name: "Weekly Goal",
            currency: "USD",
            targetAmount: 100,
            deadline: endDate,
            startDate: startDate,
            frequency: .weekly
        )
        
        let reminderDates = goal.reminderDates
        #expect(reminderDates.count == 4) // Week 0, 1, 2, 3
        #expect(reminderDates[0] == startDate)
        
        // Check weekly intervals
        for i in 1..<reminderDates.count {
            let expectedDate = calendar.date(byAdding: .day, value: i * 7, to: startDate)!
            let actualDate = reminderDates[i]
            let timeDifference = abs(expectedDate.timeIntervalSince(actualDate))
            #expect(timeDifference < 60) // Within 1 minute tolerance
        }
    }
    
    @Test func goalRemainingDates() throws {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date())!
        
        let goal = Goal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 100,
            deadline: nextWeek,
            startDate: yesterday,
            frequency: .weekly
        )
        
        let remainingDates = goal.remainingDates
        
        // Should only include today and future dates
        for date in remainingDates {
            let dayDifference = calendar.dateComponents([.day], from: Date(), to: date).day ?? 0
            #expect(dayDifference >= 0)
        }
    }
    
    @Test func goalNextReminder() throws {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date())!
        
        let goal = Goal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 100,
            deadline: nextWeek,
            startDate: tomorrow,
            frequency: .weekly
        )
        
        let nextReminder = goal.nextReminder
        #expect(nextReminder != nil)
        #expect(nextReminder! >= Date()) // Should be in the future
    }
    
    // MARK: - Asset Model Tests
    
    @Test func assetInitialization() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Test", currency: "USD", targetAmount: 100, deadline: Date())
        let asset = Asset(currency: "BTC", goal: goal)
        
        #expect(asset.currency == "BTC")
        #expect(asset.goal === goal)
        #expect(asset.transactions.isEmpty)
        #expect(asset.currentAmount == 0.0)
    }
    
    @Test func assetCurrentAmount() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Test", currency: "USD", targetAmount: 100, deadline: Date())
        let asset = Asset(currency: "BTC", goal: goal)
        
        // Explicitly establish relationships
        goal.assets.append(asset)
        
        context.insert(goal)
        context.insert(asset)
        
        let transaction1 = Transaction(amount: 10.5, asset: asset)
        let transaction2 = Transaction(amount: 5.25, asset: asset)
        let transaction3 = Transaction(amount: -2.0, asset: asset) // withdrawal
        
        asset.transactions.append(transaction1)
        asset.transactions.append(transaction2)
        asset.transactions.append(transaction3)
        
        context.insert(transaction1)
        context.insert(transaction2)
        context.insert(transaction3)
        
        try context.save()
        context.processPendingChanges()
        
        #expect(asset.currentAmount == 13.75) // 10.5 + 5.25 - 2.0
    }
    
    @Test func assetManualBalance() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Test", currency: "USD", targetAmount: 100, deadline: Date())
        let asset = Asset(currency: "BTC", goal: goal)
        
        context.insert(goal)
        context.insert(asset)
        
        let tx1 = Transaction(amount: 0.1, asset: asset, comment: "First purchase")
        let tx2 = Transaction(amount: 0.05, asset: asset, comment: "Second purchase")
        
        asset.transactions.append(tx1)
        asset.transactions.append(tx2)
        
        context.insert(tx1)
        context.insert(tx2)
        
        try context.save()
        context.processPendingChanges()
        
        #expect(asset.manualBalance == 0.15)
    }
    
    @Test func assetCombinedBalance() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Test", currency: "USD", targetAmount: 100, deadline: Date())
        // Asset with address to simulate on-chain + manual
        let asset = Asset(currency: "ETH", goal: goal, address: "0x123", chainId: "ETH")
        
        context.insert(goal)
        context.insert(asset)
        
        // Add manual transactions
        let tx1 = Transaction(amount: 1.0, asset: asset, comment: "Manual deposit")
        let tx2 = Transaction(amount: 0.5, asset: asset, comment: "Another manual")
        
        asset.transactions.append(tx1)
        asset.transactions.append(tx2)
        
        context.insert(tx1)
        context.insert(tx2)
        
        try context.save()
        context.processPendingChanges()
        
        // Manual balance should be 1.5
        #expect(asset.manualBalance == 1.5)
        
        // getCurrentAmount will try to fetch on-chain but will return manual balance on top
        // since we're in test environment without actual API, on-chain will be 0
        let totalAmount = await asset.getCurrentAmount()
        #expect(totalAmount == 1.5) // Will be manual only in test since on-chain will fail
    }
    
    // MARK: - Transaction Model Tests
    
    @Test func transactionInitialization() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Test", currency: "USD", targetAmount: 100, deadline: Date())
        let asset = Asset(currency: "BTC", goal: goal)
        let transaction = Transaction(amount: 25.5, asset: asset)
        
        #expect(transaction.amount == 25.5)
        #expect(transaction.asset === asset)
        #expect(transaction.comment == nil)
        
        // Date should be recent
        let timeDifference = abs(transaction.date.timeIntervalSinceNow)
        #expect(timeDifference < 5.0)
    }
    
    @Test func transactionWithComment() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Test", currency: "USD", targetAmount: 100, deadline: Date())
        let asset = Asset(currency: "BTC", goal: goal)
        let transaction = Transaction(amount: 50.0, asset: asset, comment: "Monthly investment")
        
        #expect(transaction.amount == 50.0)
        #expect(transaction.comment == "Monthly investment")
    }
    
    // MARK: - Goal Calculation Tests
    
    @Test func goalCurrentTotalSameCurrency() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "USD Goal", currency: "USD", targetAmount: 1000, deadline: Date())
        let asset1 = Asset(currency: "USD", goal: goal)
        let asset2 = Asset(currency: "USD", goal: goal)
        
        // Explicitly establish relationships
        goal.assets.append(asset1)
        goal.assets.append(asset2)
        
        context.insert(goal)
        context.insert(asset1)
        context.insert(asset2)
        
        let transaction1 = Transaction(amount: 100, asset: asset1)
        let transaction2 = Transaction(amount: 200, asset: asset2)
        
        asset1.transactions.append(transaction1)
        asset2.transactions.append(transaction2)
        
        context.insert(transaction1)
        context.insert(transaction2)
        
        try context.save()
        context.processPendingChanges()
        
        let total = await GoalCalculationService.getCurrentTotal(for: goal)
        #expect(total == 300.0)
    }
    
    @Test func goalProgressCalculation() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Progress Goal", currency: "USD", targetAmount: 1000, deadline: Date())
        let asset = Asset(currency: "USD", goal: goal)
        
        // Explicitly establish relationships
        goal.assets.append(asset)
        
        context.insert(goal)
        context.insert(asset)
        
        let transaction = Transaction(amount: 250, asset: asset)
        asset.transactions.append(transaction)
        context.insert(transaction)
        
        try context.save()
        context.processPendingChanges()
        
        let progress = await GoalCalculationService.getProgress(for: goal)
        #expect(progress == 0.25) // 250/1000 = 0.25
    }
    
    @Test func goalProgressCappedAtOne() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Over Goal", currency: "USD", targetAmount: 100, deadline: Date())
        let asset = Asset(currency: "USD", goal: goal)
        
        // Explicitly establish relationships
        goal.assets.append(asset)
        
        context.insert(goal)
        context.insert(asset)
        
        let transaction = Transaction(amount: 150, asset: asset) // Over target
        asset.transactions.append(transaction)
        context.insert(transaction)
        
        try context.save()
        context.processPendingChanges()
        
        let progress = await GoalCalculationService.getProgress(for: goal)
        #expect(progress == 1.0) // Should be capped at 1.0
    }
    
    @Test func goalSuggestedDepositCalculation() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let calendar = Calendar.current
        let startDate = Date()
        let endDate = calendar.date(byAdding: .day, value: 14, to: startDate)! // 2 weeks
        
        let goal = Goal(
            name: "Deposit Goal",
            currency: "USD",
            targetAmount: 1000,
            deadline: endDate,
            startDate: startDate,
            frequency: .weekly
        )
        let asset = Asset(currency: "USD", goal: goal)
        
        context.insert(goal)
        context.insert(asset)
        
        let transaction = Transaction(amount: 200, asset: asset) // Already have $200
        context.insert(transaction)
        
        try context.save()
        
        let suggestedDeposit = await goal.getSuggestedDeposit()
        // Need $800 more, with remaining reminders (should be 2: week 1 and 2)
        // So approximately $400 per reminder
        #expect(suggestedDeposit > 300)
        #expect(suggestedDeposit < 500)
    }
    
    @Test func goalZeroTargetProgress() async throws {
        let goal = Goal(name: "Zero Target", currency: "USD", targetAmount: 0, deadline: Date())
        
        let progress = await GoalCalculationService.getProgress(for: goal)
        #expect(progress == 0.0)
    }
    
    // MARK: - SwiftData Persistence Tests
    
    @Test func goalPersistence() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let deadline = Date().addingTimeInterval(30 * 24 * 60 * 60)
        let goal = Goal(
            name: "Persistent Goal",
            currency: "EUR",
            targetAmount: 500.0,
            deadline: deadline,
            frequency: .monthly
        )
        
        context.insert(goal)
        try context.save()
        
        // Fetch the goal back
        let descriptor = FetchDescriptor<Goal>()
        let fetchedGoals = try context.fetch(descriptor)
        
        #expect(fetchedGoals.count == 1)
        
        let fetchedGoal = fetchedGoals[0]
        #expect(fetchedGoal.name == "Persistent Goal")
        #expect(fetchedGoal.currency == "EUR")
        #expect(fetchedGoal.targetAmount == 500.0)
        #expect(fetchedGoal.frequency == .monthly)
    }
    
    @Test func relationshipPersistence() throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let goal = Goal(name: "Relationship Goal", currency: "USD", targetAmount: 1000, deadline: Date())
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
        
        // Fetch and verify relationships
        let goalDescriptor = FetchDescriptor<Goal>()
        let fetchedGoals = try context.fetch(goalDescriptor)
        
        #expect(fetchedGoals.count == 1)
        let fetchedGoal = fetchedGoals[0]
        
        #expect(fetchedGoal.assets.count == 1)
        guard let fetchedAsset = fetchedGoal.assets.first else {
            fatalError("Expected to find at least one asset but none found")
        }
        
        #expect(fetchedAsset.transactions.count == 1)
        guard let fetchedTransaction = fetchedAsset.transactions.first else {
            fatalError("Expected to find at least one transaction but none found")
        }
        
        #expect(fetchedTransaction.amount == 100)
        #expect(fetchedTransaction.asset === fetchedAsset)
        #expect(fetchedAsset.goal === fetchedGoal)
    }
}
