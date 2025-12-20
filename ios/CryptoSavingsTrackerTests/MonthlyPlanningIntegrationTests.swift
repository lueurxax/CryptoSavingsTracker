//
//  MonthlyPlanningIntegrationTests.swift
//  CryptoSavingsTrackerTests
//
//  Simplified integration tests for monthly planning calculations.
//

import Testing
import SwiftData
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct MonthlyPlanningIntegrationTests {

    var modelContainer: ModelContainer
    var mockExchangeRateService: MockExchangeRateService
    var monthlyPlanningService: MonthlyPlanningService

    init() async throws {
        // Use shared TestContainer for consistent schema
        self.modelContainer = try TestContainer.create()
        self.mockExchangeRateService = MockExchangeRateService()
        self.monthlyPlanningService = MonthlyPlanningService(exchangeRateService: mockExchangeRateService)
    }

    @Test("Calculates requirements for goals with assets in different currencies")
    func testMultiGoalMultiCurrencyIntegration() async throws {
        let context = modelContainer.mainContext

        // Rates to USD
        mockExchangeRateService.setRate(from: "EUR", to: "USD", rate: 1.1)
        mockExchangeRateService.setRate(from: "GBP", to: "USD", rate: 1.25)

        let usdGoal = TestHelpers.createGoalWithAsset(
            name: "USD Goal",
            currency: "USD",
            target: 5000,
            current: 1000,
            months: 5,
            context: context
        )
        let eurGoal = TestHelpers.createGoalWithAsset(
            name: "EUR Goal",
            currency: "EUR",
            target: 4000,
            current: 1000,
            months: 4,
            context: context
        )
        let gbpGoal = TestHelpers.createGoalWithAsset(
            name: "GBP Goal",
            currency: "GBP",
            target: 3000,
            current: 1000,
            months: 3,
            context: context
        )
        try context.save()

        let requirements = await monthlyPlanningService.calculateMonthlyRequirements(for: [usdGoal, eurGoal, gbpGoal])
        #expect(requirements.count == 3)

        // Basic sanity: requiredMonthly should be remaining/ monthsRemaining using current totals
        let reqUSD = requirements.first { $0.goalId == usdGoal.id }
        let reqEUR = requirements.first { $0.goalId == eurGoal.id }
        let reqGBP = requirements.first { $0.goalId == gbpGoal.id }

        #expect(reqUSD?.requiredMonthly ?? 0 > 0)
        #expect(reqEUR?.requiredMonthly ?? 0 > 0)
        #expect(reqGBP?.requiredMonthly ?? 0 > 0)
    }

    @Test("Persists MonthlyPlan flex and custom amount")
    func testPlanPersistence() async throws {
        let context = modelContainer.mainContext
        let goal = TestHelpers.createGoalWithAsset(
            name: "Persisted Goal",
            currency: "USD",
            target: 5000,
            current: 2000,
            months: 5,
            context: context
        )

        let plan = MonthlyPlan(
            goalId: goal.id,
            monthLabel: MonthlyExecutionRecord.monthLabel(from: Date()),
            requiredMonthly: 1125,
            remainingAmount: 3000,
            monthsRemaining: 3,
            currency: "USD",
            status: .onTrack,
            flexState: .protected,
            state: .draft
        )
        plan.setCustomAmount(1000)
        context.insert(plan)
        try context.save()

        context.processPendingChanges()

        // Fetch all plans and filter in-memory to avoid predicate compatibility issues
        let loaded = try context.fetch(FetchDescriptor<MonthlyPlan>()).filter { $0.goalId == goal.id }
        #expect(loaded.count == 1)
        let loadedPlan = loaded[0]
        #expect(loadedPlan.customAmount == 1000)
        #expect(loadedPlan.flexState == .protected)
        #expect(loadedPlan.effectiveAmount == 1000)
    }
}
