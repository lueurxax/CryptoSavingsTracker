//
//  BudgetCalculatorServiceTests.swift
//  CryptoSavingsTrackerTests
//

import Testing
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct BudgetCalculatorServiceTests {

    @Test("Reduce target suggestion keeps goal currency")
    func reduceTargetSuggestionUsesGoalCurrency() async throws {
        let exchange = MockExchangeRateService()
        exchange.setRate(from: "EUR", to: "USD", rate: 2.0)

        let service = BudgetCalculatorService(exchangeRateService: exchange)
        let deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let goal = TestHelpers.createGoal(
            name: "Euro Goal",
            currency: "EUR",
            targetAmount: 1000,
            currentTotal: 0,
            deadline: deadline
        )

        let feasibility = await service.checkFeasibility(
            goals: [goal],
            budget: 1000,
            currency: "USD"
        )

        #expect(feasibility.isFeasible == false)

        let reduceSuggestion = feasibility.suggestions.first { suggestion in
            if case .reduceTarget = suggestion { return true }
            return false
        }
        #expect(reduceSuggestion != nil)

        if case .reduceTarget(_, _, let target, let currency) = reduceSuggestion {
            #expect(currency == "EUR")
            #expect(target == 500)
        }
    }
}
