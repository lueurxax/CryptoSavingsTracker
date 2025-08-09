//
//  MonthlyPlanningIntegrationTests.swift
//  CryptoSavingsTrackerTests
//
//  Created by Claude on 09/08/2025.
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

struct MonthlyPlanningIntegrationTests {
    
    var modelContainer: ModelContainer
    var monthlyPlanningService: MonthlyPlanningService
    var mockExchangeRateService: MockExchangeRateService
    
    init() async throws {
        // Create in-memory model container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.modelContainer = try ModelContainer(
            for: Goal.self, Asset.self, Transaction.self, MonthlyPlan.self,
            configurations: config
        )
        
        // Create services
        self.mockExchangeRateService = MockExchangeRateService()
        self.monthlyPlanningService = MonthlyPlanningService(exchangeRateService: mockExchangeRateService)
    }
    
    // MARK: - Full Data Flow Integration Tests
    
    @Test("Complete monthly planning workflow")
    func testCompleteMonthlyPlanningWorkflow() async throws {
        let context = modelContainer.mainContext
        
        // Given - Create a complete goal with assets and transactions
        let goal1 = Goal(
            name: "Bitcoin Savings",
            currency: "USD",
            targetAmount: 10000,
            deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        )
        
        let asset1 = Asset(
            goal: goal1,
            currency: "USD",
            address: "test_address_1",
            balance: 2500
        )
        
        let transaction1 = Transaction(
            asset: asset1,
            amount: 1000,
            type: .deposit,
            date: Date().addingTimeInterval(-86400 * 30) // 30 days ago
        )
        
        let transaction2 = Transaction(
            asset: asset1,
            amount: 1500,
            type: .deposit,
            date: Date().addingTimeInterval(-86400 * 15) // 15 days ago
        )
        
        goal1.assets.append(asset1)
        asset1.transactions.append(transaction1)
        asset1.transactions.append(transaction2)
        
        context.insert(goal1)
        context.insert(asset1)
        context.insert(transaction1)
        context.insert(transaction2)
        try context.save()
        
        // When - Calculate monthly requirements
        let requirements = await monthlyPlanningService.calculateMonthlyRequirements(for: [goal1])
        
        // Then - Verify complete calculation
        #expect(requirements.count == 1)
        let requirement = requirements.first!
        
        #expect(requirement.goalId == goal1.id)
        #expect(requirement.goalName == "Bitcoin Savings")
        #expect(requirement.currency == "USD")
        #expect(requirement.targetAmount == 10000)
        #expect(requirement.currentTotal == 2500) // Asset balance
        #expect(requirement.remainingAmount == 7500) // 10000 - 2500
        #expect(requirement.monthsRemaining == 6)
        #expect(requirement.requiredMonthly == 1250) // 7500 / 6
        #expect(requirement.progress == 0.25) // 2500 / 10000
        #expect(requirement.status == .onTrack)
    }
    
    @Test("Multi-goal multi-currency integration")
    func testMultiGoalMultiCurrencyIntegration() async throws {
        let context = modelContainer.mainContext
        
        // Given - Set up exchange rates
        mockExchangeRateService.setRate(from: "EUR", to: "USD", rate: 1.1)
        mockExchangeRateService.setRate(from: "GBP", to: "USD", rate: 1.25)
        
        // Create multiple goals in different currencies
        let usdGoal = Goal(
            name: "USD Goal",
            currency: "USD",
            targetAmount: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 5, to: Date())!
        )
        
        let eurGoal = Goal(
            name: "EUR Goal", 
            currency: "EUR",
            targetAmount: 4000,
            deadline: Calendar.current.date(byAdding: .month, value: 4, to: Date())!
        )
        
        let gbpGoal = Goal(
            name: "GBP Goal",
            currency: "GBP",
            targetAmount: 3000,
            deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        )
        
        // Add assets with balances
        let usdAsset = Asset(goal: usdGoal, currency: "USD", address: "usd_addr", balance: 1000)
        let eurAsset = Asset(goal: eurGoal, currency: "EUR", address: "eur_addr", balance: 1000)
        let gbpAsset = Asset(goal: gbpGoal, currency: "GBP", address: "gbp_addr", balance: 1000)
        
        usdGoal.assets.append(usdAsset)
        eurGoal.assets.append(eurAsset)
        gbpGoal.assets.append(gbpAsset)
        
        [usdGoal, eurGoal, gbpGoal, usdAsset, eurAsset, gbpAsset].forEach { context.insert($0) }
        try context.save()
        
        // When - Calculate requirements and total
        let goals = [usdGoal, eurGoal, gbpGoal]
        let requirements = await monthlyPlanningService.calculateMonthlyRequirements(for: goals)
        let totalUSD = await monthlyPlanningService.calculateTotalRequired(for: goals, displayCurrency: "USD")
        
        // Then - Verify individual calculations
        #expect(requirements.count == 3)
        
        let usdReq = requirements.first { $0.goalName == "USD Goal" }!
        #expect(usdReq.requiredMonthly == 800) // (5000-1000)/5
        
        let eurReq = requirements.first { $0.goalName == "EUR Goal" }!
        #expect(eurReq.requiredMonthly == 750) // (4000-1000)/4
        
        let gbpReq = requirements.first { $0.goalName == "GBP Goal" }!
        #expect(gbpReq.requiredMonthly == 666.67, accuracy: 0.01) // (3000-1000)/3
        
        // Verify total conversion: 800 + (750 * 1.1) + (666.67 * 1.25) = 800 + 825 + 833.34 = 2458.34
        #expect(totalUSD == 2458.34, accuracy: 0.1)
    }
    
    @Test("Service coordination with ViewModel")
    func testServiceCoordinationWithViewModel() async throws {
        let context = modelContainer.mainContext
        
        // Given - Create test data
        let goal = Goal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 8000,
            deadline: Calendar.current.date(byAdding: .month, value: 4, to: Date())!
        )
        
        let asset = Asset(goal: goal, currency: "USD", address: "test_addr", balance: 3000)
        goal.assets.append(asset)
        
        context.insert(goal)
        context.insert(asset)
        try context.save()
        
        // When - Create ViewModel and load data
        let viewModel = MonthlyPlanningViewModel(modelContext: context)
        await viewModel.loadMonthlyRequirements()
        
        // Then - Verify ViewModel state
        #expect(viewModel.monthlyRequirements.count == 1)
        #expect(viewModel.totalRequired == 1250) // (8000-3000)/4
        #expect(viewModel.displayCurrency == "USD")
        #expect(!viewModel.isLoading)
        #expect(viewModel.error == nil)
        
        // Verify statistics
        let stats = viewModel.statistics
        #expect(stats.totalGoals == 1)
        #expect(stats.onTrackCount == 1)
        #expect(stats.attentionCount == 0)
        #expect(stats.criticalCount == 0)
        #expect(stats.averageMonthlyRequired == 1250)
    }
    
    @Test("Flex adjustment integration")
    func testFlexAdjustmentIntegration() async throws {
        let context = modelContainer.mainContext
        
        // Given - Create multiple goals
        let goal1 = TestHelpers.createGoalWithAsset(
            name: "Goal 1", currency: "USD", target: 6000, current: 1000, 
            months: 5, context: context
        )
        let goal2 = TestHelpers.createGoalWithAsset(
            name: "Goal 2", currency: "USD", target: 8000, current: 2000, 
            months: 6, context: context
        )
        
        let viewModel = MonthlyPlanningViewModel(modelContext: context)
        await viewModel.loadMonthlyRequirements()
        
        // When - Apply flex adjustment
        await viewModel.previewAdjustment(0.75) // 75%
        
        // Then - Verify adjustments
        let goal1Adjusted = viewModel.adjustmentPreview[goal1.id]!
        let goal2Adjusted = viewModel.adjustmentPreview[goal2.id]!
        
        // Original: Goal1 = 1000, Goal2 = 1000
        // Adjusted: Goal1 = 750, Goal2 = 750
        #expect(goal1Adjusted == 750) // 1000 * 0.75
        #expect(goal2Adjusted == 750) // 1000 * 0.75
        #expect(viewModel.adjustedTotal == 1500) // 750 + 750
        
        // When - Protect one goal
        viewModel.toggleProtection(for: goal1.id)
        await viewModel.previewAdjustment(0.5) // 50%
        
        // Then - Protected goal unchanged, flexible goal adjusted
        let goal1Protected = viewModel.adjustmentPreview[goal1.id]!
        let goal2Flexible = viewModel.adjustmentPreview[goal2.id]!
        
        #expect(goal1Protected == 1000) // Original amount (protected)
        #expect(goal2Flexible == 500) // 1000 * 0.5 (flexible)
        #expect(viewModel.adjustedTotal == 1500) // 1000 + 500
    }
    
    @Test("Quick actions integration")
    func testQuickActionsIntegration() async throws {
        let context = modelContainer.mainContext
        
        // Given - Create test goals
        let goal1 = TestHelpers.createGoalWithAsset(
            name: "Goal 1", currency: "USD", target: 5000, current: 1000,
            months: 4, context: context
        )
        let goal2 = TestHelpers.createGoalWithAsset(
            name: "Goal 2", currency: "USD", target: 6000, current: 2000,
            months: 4, context: context
        )
        
        let viewModel = MonthlyPlanningViewModel(modelContext: context)
        await viewModel.loadMonthlyRequirements()
        
        // When - Apply "Pay Half" quick action
        await viewModel.applyQuickAction(.payHalf)
        
        // Then - Verify 50% adjustment
        #expect(viewModel.flexAdjustment == 0.5)
        #expect(viewModel.adjustedTotal == 1500) // (1000 + 1000) * 0.5
        #expect(viewModel.skippedGoalIds.isEmpty)
        
        // When - Apply "Skip Month" quick action
        await viewModel.applyQuickAction(.skipMonth)
        
        // Then - Verify all goals skipped
        #expect(viewModel.skippedGoalIds.contains(goal1.id))
        #expect(viewModel.skippedGoalIds.contains(goal2.id))
        #expect(viewModel.adjustedTotal == 0)
        
        // When - Apply "Reset" quick action
        await viewModel.applyQuickAction(.reset)
        
        // Then - Verify reset state
        #expect(viewModel.flexAdjustment == 1.0)
        #expect(viewModel.skippedGoalIds.isEmpty)
        #expect(viewModel.protectedGoalIds.isEmpty)
        #expect(viewModel.adjustedTotal == 2000) // Back to original
    }
    
    @Test("Real-time updates integration")
    func testRealTimeUpdatesIntegration() async throws {
        let context = modelContainer.mainContext
        
        // Given - Create initial data
        let goal = Goal(
            name: "Dynamic Goal",
            currency: "USD",
            targetAmount: 10000,
            deadline: Calendar.current.date(byAdding: .month, value: 5, to: Date())!
        )
        
        let asset = Asset(goal: goal, currency: "USD", address: "dynamic_addr", balance: 2000)
        goal.assets.append(asset)
        
        context.insert(goal)
        context.insert(asset)
        try context.save()
        
        let viewModel = MonthlyPlanningViewModel(modelContext: context)
        await viewModel.loadMonthlyRequirements()
        
        // Verify initial state
        #expect(viewModel.monthlyRequirements.count == 1)
        #expect(viewModel.totalRequired == 1600) // (10000-2000)/5
        
        // When - Add new transaction (simulating real-time update)
        let newTransaction = Transaction(
            asset: asset,
            amount: 1000,
            type: .deposit,
            date: Date()
        )
        asset.transactions.append(newTransaction)
        asset.balance += 1000 // Update balance
        
        context.insert(newTransaction)
        try context.save()
        
        // Simulate notification (would normally come from app)
        NotificationCenter.default.post(name: .monthlyPlanningAssetUpdated, object: asset)
        
        // Wait for reactive update
        try await Task.sleep(for: .seconds(1.5))
        
        // Then - Verify automatic update
        #expect(viewModel.monthlyRequirements.count == 1)
        #expect(viewModel.totalRequired == 1400) // (10000-3000)/5
        
        let updatedRequirement = viewModel.monthlyRequirements.first!
        #expect(updatedRequirement.currentTotal == 3000)
        #expect(updatedRequirement.requiredMonthly == 1400)
        #expect(updatedRequirement.remainingAmount == 7000)
    }
    
    @Test("Error handling integration")
    func testErrorHandlingIntegration() async throws {
        let context = modelContainer.mainContext
        
        // Given - Set up service to fail
        mockExchangeRateService.shouldFail = true
        
        let goal = Goal(
            name: "EUR Goal",
            currency: "EUR", 
            targetAmount: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        )
        
        let asset = Asset(goal: goal, currency: "EUR", address: "eur_addr", balance: 1000)
        goal.assets.append(asset)
        
        context.insert(goal)
        context.insert(asset)
        try context.save()
        
        let viewModel = MonthlyPlanningViewModel(modelContext: context)
        
        // When - Calculate total with failing exchange service
        let totalUSD = await monthlyPlanningService.calculateTotalRequired(for: [goal], displayCurrency: "USD")
        
        // Then - Should gracefully fall back to original amount
        let expectedMonthly = (5000.0 - 1000.0) / 3.0 // 1333.33
        #expect(totalUSD == expectedMonthly, accuracy: 0.01)
        
        // ViewModel should handle service errors gracefully
        await viewModel.updateDisplayCurrency("USD")
        #expect(viewModel.error == nil) // Service errors shouldn't propagate to ViewModel errors
    }
    
    @Test("Performance with large dataset")
    func testPerformanceWithLargeDataset() async throws {
        let context = modelContainer.mainContext
        
        // Given - Create many goals
        var goals: [Goal] = []
        for i in 1...50 {
            let goal = Goal(
                name: "Goal \(i)",
                currency: i % 2 == 0 ? "USD" : "EUR",
                targetAmount: Double(1000 * i),
                deadline: Calendar.current.date(byAdding: .month, value: i % 12 + 1, to: Date())!
            )
            
            let asset = Asset(goal: goal, currency: goal.currency, address: "addr_\(i)", balance: Double(100 * i))
            goal.assets.append(asset)
            
            context.insert(goal)
            context.insert(asset)
            goals.append(goal)
        }
        try context.save()
        
        // Set up exchange rate
        mockExchangeRateService.setRate(from: "EUR", to: "USD", rate: 1.1)
        
        // When - Measure performance
        let startTime = Date()
        let requirements = await monthlyPlanningService.calculateMonthlyRequirements(for: goals)
        let totalUSD = await monthlyPlanningService.calculateTotalRequired(for: goals, displayCurrency: "USD")
        let duration = Date().timeIntervalSince(startTime)
        
        // Then - Verify performance and results
        #expect(requirements.count == 50)
        #expect(totalUSD > 0)
        #expect(duration < 5.0) // Should complete within 5 seconds
        
        // Verify parallel processing worked by checking all requirements are valid
        for requirement in requirements {
            #expect(requirement.requiredMonthly > 0)
            #expect(requirement.monthsRemaining > 0)
            #expect(!requirement.goalName.isEmpty)
        }
    }
    
    @Test("SwiftData persistence integration")
    func testSwiftDataPersistenceIntegration() async throws {
        let context = modelContainer.mainContext
        
        // Given - Create goal and calculate plan
        let goal = Goal(
            name: "Persistent Goal",
            currency: "USD",
            targetAmount: 6000,
            deadline: Calendar.current.date(byAdding: .month, value: 4, to: Date())!
        )
        
        let asset = Asset(goal: goal, currency: "USD", address: "persist_addr", balance: 1500)
        goal.assets.append(asset)
        
        context.insert(goal)
        context.insert(asset)
        try context.save()
        
        // When - Create and persist monthly plan
        let monthlyPlan = MonthlyPlan(
            goalId: goal.id,
            requiredMonthly: 1125, // (6000-1500)/4
            remainingAmount: 4500,
            monthsRemaining: 4,
            currency: "USD",
            status: .onTrack,
            flexState: .flexible
        )
        
        monthlyPlan.setCustomAmount(1000) // User override
        monthlyPlan.toggleProtection() // Protect from adjustments
        
        context.insert(monthlyPlan)
        try context.save()
        
        // Clear context to force reload from database
        context.reset()
        
        // When - Reload from database
        let descriptor = FetchDescriptor<MonthlyPlan>(
            predicate: #Predicate { $0.goalId == goal.id }
        )
        let loadedPlans = try context.fetch(descriptor)
        
        // Then - Verify persistence
        #expect(loadedPlans.count == 1)
        let loadedPlan = loadedPlans.first!
        
        #expect(loadedPlan.goalId == goal.id)
        #expect(loadedPlan.requiredMonthly == 1125)
        #expect(loadedPlan.customAmount == 1000)
        #expect(loadedPlan.flexState == .protected)
        #expect(loadedPlan.effectiveAmount == 1000) // Uses custom amount
        #expect(loadedPlan.isActionable == true)
        #expect(loadedPlan.validate().isEmpty) // Valid plan
    }
}

// MARK: - Test Helpers Extension

extension TestHelpers {
    static func createGoalWithAsset(
        name: String,
        currency: String,
        target: Double,
        current: Double,
        months: Int,
        context: ModelContext
    ) -> Goal {
        let deadline = Calendar.current.date(byAdding: .month, value: months, to: Date())!
        let goal = Goal(name: name, currency: currency, targetAmount: target, deadline: deadline)
        let asset = Asset(goal: goal, currency: currency, address: "test_addr", balance: current)
        
        goal.assets.append(asset)
        
        context.insert(goal)
        context.insert(asset)
        
        return goal
    }
}

// MARK: - Mock Exchange Rate Service

private class MockExchangeRateService: ExchangeRateService {
    var shouldFail = false
    private var rates: [String: Double] = [:]
    
    func setRate(from: String, to: String, rate: Double) {
        rates["\(from)-\(to)"] = rate
    }
    
    override func fetchRate(from: String, to: String) async throws -> Double {
        if shouldFail {
            throw ExchangeRateError.networkError("Mock failure")
        }
        
        if from == to {
            return 1.0
        }
        
        return rates["\(from)-\(to)"] ?? 1.0
    }
}