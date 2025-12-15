//
//  MonthlyPlanningServiceTests.swift
//  CryptoSavingsTrackerTests
//
//  Created by Claude on 09/08/2025.
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct MonthlyPlanningServiceTests {
    
    var modelContainer: ModelContainer
    var mockExchangeRateService: MockExchangeRateService
    var monthlyPlanningService: MonthlyPlanningService
    
    init() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.modelContainer = try ModelContainer(
            for: Goal.self, Asset.self, Transaction.self, MonthlyPlan.self,
            configurations: config
        )
        
        self.mockExchangeRateService = MockExchangeRateService()
        self.monthlyPlanningService = MonthlyPlanningService(exchangeRateService: mockExchangeRateService)
    }
    
    // MARK: - Basic Calculation Tests
    
    @Test("Calculate basic monthly requirement")
    func testBasicMonthlyCalculation() async throws {
        // Given
        let goal = TestHelpers.createGoal(
            name: "Bitcoin Savings",
            currency: "USD",
            targetAmount: 12000,
            currentTotal: 3000,
            deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        )
        
        // When
        let requirement = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        
        // Then
        #expect(requirement != nil)
        #expect(requirement?.requiredMonthly == 3000) // (12000-3000)/3
        #expect(requirement?.remainingAmount == 9000)
        #expect(requirement?.monthsRemaining == 3)
        #expect(requirement?.status == .onTrack)
    }
    
    @Test("Handle completed goal")
    func testCompletedGoal() async throws {
        // Given
        let goal = TestHelpers.createGoal(
            name: "Completed Goal",
            currency: "USD", 
            targetAmount: 5000,
            currentTotal: 6000, // More than target
            deadline: Calendar.current.date(byAdding: .month, value: 2, to: Date())!
        )
        
        // When
        let requirement = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        
        // Then
        #expect(requirement != nil)
        #expect(requirement?.requiredMonthly == 0)
        #expect(requirement?.remainingAmount == 0)
        #expect(requirement?.status == .completed)
    }
    
    @Test("Handle critical requirement")
    func testCriticalRequirement() async throws {
        // Given
        let goal = TestHelpers.createGoal(
            name: "Urgent Goal",
            currency: "USD",
            targetAmount: 25000,
            currentTotal: 5000,
            deadline: Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        )
        
        // When
        let requirement = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        
        // Then
        #expect(requirement != nil)
        #expect(requirement?.requiredMonthly == 20000) // (25000-5000)/1
        #expect(requirement?.status == .critical)
    }
    
    @Test("Handle attention status")
    func testAttentionStatus() async throws {
        // Given
        let goal = TestHelpers.createGoal(
            name: "High Amount Goal",
            currency: "USD",
            targetAmount: 18000,
            currentTotal: 3000,
            deadline: Calendar.current.date(byAdding: .month, value: 2, to: Date())!
        )
        
        // When
        let requirement = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        
        // Then
        #expect(requirement != nil)
        #expect(requirement?.requiredMonthly == 7500) // (18000-3000)/2
        #expect(requirement?.status == .attention)
    }
    
    // MARK: - Multiple Goals Tests
    
    @Test("Calculate requirements for multiple goals")
    func testMultipleGoalsCalculation() async throws {
        // Given
        let goal1 = TestHelpers.createGoal(
            name: "Goal 1",
            currency: "USD",
            targetAmount: 6000,
            currentTotal: 1000,
            deadline: Calendar.current.date(byAdding: .month, value: 5, to: Date())!
        )
        
        let goal2 = TestHelpers.createGoal(
            name: "Goal 2", 
            currency: "USD",
            targetAmount: 12000,
            currentTotal: 2000,
            deadline: Calendar.current.date(byAdding: .month, value: 10, to: Date())!
        )
        
        let goals = [goal1, goal2]
        
        // When
        let requirements = await monthlyPlanningService.calculateMonthlyRequirements(for: goals)
        
        // Then
        #expect(requirements.count == 2)
        
        let req1 = requirements.first { $0.goalName == "Goal 1" }
        let req2 = requirements.first { $0.goalName == "Goal 2" }
        
        #expect(req1?.requiredMonthly == 1000) // (6000-1000)/5
        #expect(req2?.requiredMonthly == 1000) // (12000-2000)/10
    }
    
    @Test("Calculate total required with currency conversion")
    func testTotalRequiredWithCurrencyConversion() async throws {
        // Given
        mockExchangeRateService.setRate(from: "EUR", to: "USD", rate: 1.1)
        
        let usdGoal = TestHelpers.createGoal(
            name: "USD Goal",
            currency: "USD",
            targetAmount: 6000,
            currentTotal: 1000,
            deadline: Calendar.current.date(byAdding: .month, value: 5, to: Date())!
        )
        
        let eurGoal = TestHelpers.createGoal(
            name: "EUR Goal",
            currency: "EUR", 
            targetAmount: 5000,
            currentTotal: 1000,
            deadline: Calendar.current.date(byAdding: .month, value: 4, to: Date())!
        )
        
        let goals = [usdGoal, eurGoal]
        
        // When
        let totalUSD = await monthlyPlanningService.calculateTotalRequired(for: goals, displayCurrency: "USD")
        
        // Then
        // USD: (6000-1000)/5 = 1000
        // EUR: (5000-1000)/4 = 1000 EUR = 1100 USD
        // Total: 1000 + 1100 = 2100 USD
        #expect(totalUSD == 2100)
    }
    
    // MARK: - Edge Cases Tests
    
    @Test("Handle minimum months remaining")
    func testMinimumMonthsRemaining() async throws {
        // Given - deadline is tomorrow
        let goal = TestHelpers.createGoal(
            name: "Urgent Goal",
            currency: "USD",
            targetAmount: 1000,
            currentTotal: 400,
            deadline: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        )
        
        // When
        let requirement = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        
        // Then - should default to minimum 1 month
        #expect(requirement != nil)
        #expect(requirement?.monthsRemaining == 1)
        #expect(requirement?.requiredMonthly == 600) // (1000-400)/1
    }
    
    @Test("Handle zero remaining amount")
    func testZeroRemainingAmount() async throws {
        // Given
        let goal = TestHelpers.createGoal(
            name: "At Target Goal",
            currency: "USD",
            targetAmount: 1000,
            currentTotal: 1000, // Exactly at target
            deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        )
        
        // When
        let requirement = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        
        // Then
        #expect(requirement != nil)
        #expect(requirement?.requiredMonthly == 0)
        #expect(requirement?.remainingAmount == 0)
        #expect(requirement?.status == .completed)
    }
    
    @Test("Handle negative current total")
    func testNegativeCurrentTotal() async throws {
        // Given
        let goal = TestHelpers.createGoal(
            name: "Debt Goal",
            currency: "USD",
            targetAmount: 1000,
            currentTotal: -500, // Negative balance
            deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        )
        
        // When
        let requirement = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        
        // Then
        #expect(requirement != nil)
        #expect(requirement?.requiredMonthly == 500) // (1000-(-500))/3 = 1500/3
        #expect(requirement?.remainingAmount == 1500)
    }
    
    // MARK: - Performance Tests
    
    @Test("Performance with many goals")
    func testPerformanceWithManyGoals() async throws {
        // Given
        var goals: [Goal] = []
        for i in 1...100 {
            let goal = TestHelpers.createGoal(
                name: "Goal \(i)",
                currency: "USD",
                targetAmount: Double(1000 * i),
                currentTotal: Double(100 * i),
                deadline: Calendar.current.date(byAdding: .month, value: i % 12 + 1, to: Date())!
            )
            goals.append(goal)
        }
        
        // When
        let startTime = Date()
        let requirements = await monthlyPlanningService.calculateMonthlyRequirements(for: goals)
        let duration = Date().timeIntervalSince(startTime)
        
        // Then
        #expect(requirements.count == 100)
        #expect(duration < 2.0) // Should complete within 2 seconds
    }
    
    // MARK: - Caching Tests
    
    @Test("Test calculation caching")
    func testCalculationCaching() async throws {
        // Given
        let goal = TestHelpers.createGoal(
            name: "Cached Goal",
            currency: "USD",
            targetAmount: 5000,
            currentTotal: 1000,
            deadline: Calendar.current.date(byAdding: .month, value: 4, to: Date())!
        )
        
        // When - first calculation
        let startTime1 = Date()
        let requirement1 = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        let duration1 = Date().timeIntervalSince(startTime1)
        
        // When - second calculation (should use cache)
        let startTime2 = Date()
        let requirement2 = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        let duration2 = Date().timeIntervalSince(startTime2)
        
        // Then
        #expect(requirement1?.requiredMonthly == requirement2?.requiredMonthly)
        #expect(duration2 < duration1) // Second call should be faster (cached)
    }
    
    @Test("Test cache clearing")
    func testCacheClearing() async throws {
        // Given
        let goal = TestHelpers.createGoal(
            name: "Cache Test Goal",
            currency: "USD", 
            targetAmount: 3000,
            currentTotal: 500,
            deadline: Calendar.current.date(byAdding: .month, value: 5, to: Date())!
        )
        
        // When - calculate, then clear cache, then calculate again
        let _ = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        
        monthlyPlanningService.clearCache()
        #expect(monthlyPlanningService.needsCacheRefresh == true)
        
        let requirement = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        
        // Then
        #expect(requirement != nil)
        #expect(requirement?.requiredMonthly == 500) // (3000-500)/5
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Handle currency conversion failure")
    func testCurrencyConversionFailure() async throws {
        // Given
        mockExchangeRateService.shouldFail = true
        
        let goal = TestHelpers.createGoal(
            name: "EUR Goal",
            currency: "EUR",
            targetAmount: 2000,
            currentTotal: 500,
            deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        )
        
        // When
        let totalUSD = await monthlyPlanningService.calculateTotalRequired(for: [goal], displayCurrency: "USD")
        
        // Then - should fallback to original amount
        #expect(totalUSD == 500) // (2000-500)/3 = 500 EUR, fallback to EUR amount
    }
    
    @Test("Handle empty goals array")
    func testEmptyGoalsArray() async throws {
        // When
        let requirements = await monthlyPlanningService.calculateMonthlyRequirements(for: [])
        let total = await monthlyPlanningService.calculateTotalRequired(for: [], displayCurrency: "USD")
        
        // Then
        #expect(requirements.isEmpty)
        #expect(total == 0)
    }
    
    // MARK: - Formatting Tests
    
    @Test("Test MonthlyRequirement formatting")
    func testMonthlyRequirementFormatting() async throws {
        // Given
        let goal = TestHelpers.createGoal(
            name: "Format Test Goal",
            currency: "USD",
            targetAmount: 5000,
            currentTotal: 1234.56,
            deadline: Calendar.current.date(byAdding: .month, value: 4, to: Date())!
        )
        
        // When
        let requirement = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        
        // Then
        #expect(requirement != nil)
        #expect(requirement?.formattedRequiredMonthly().contains("USD") == true)
        #expect(requirement?.formattedRemainingAmount().contains("USD") == true)
        #expect(requirement?.timeRemainingDescription == "4 months remaining")
    }
    
    @Test("Test singular month description")
    func testSingularMonthDescription() async throws {
        // Given
        let goal = TestHelpers.createGoal(
            name: "One Month Goal",
            currency: "USD",
            targetAmount: 2000,
            currentTotal: 1500,
            deadline: Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        )
        
        // When
        let requirement = await monthlyPlanningService.getMonthlyRequirement(for: goal)
        
        // Then
        #expect(requirement != nil)
        #expect(requirement?.timeRemainingDescription == "1 month remaining")
    }
}
