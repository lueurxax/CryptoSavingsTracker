//
//  GoalBalanceCalculatorTests.swift
//  CryptoSavingsTrackerTests
//

import Testing
import Foundation
@testable import CryptoSavingsTracker

/// Regression coverage for `GoalBalanceCalculator.calculateCurrentTotal(for:)`, which was
/// refactored to fetch each allocation's balance/conversion concurrently via a `TaskGroup`
/// instead of sequentially. These tests confirm the concurrent implementation still produces
/// the same total and conversion-error signal as the previous sequential version.
@MainActor
struct GoalBalanceCalculatorTests {

    private func makeCalculator(exchangeRateService: ExchangeRateServiceProtocol) -> GoalBalanceCalculator {
        GoalBalanceCalculator(tatumService: DIContainer.shared.tatumService, exchangeRateService: exchangeRateService)
    }

    @Test("Sums multiple manual-balance allocations across currencies concurrently")
    func sumsMultipleAllocationsAcrossCurrencies() async throws {
        let goal = Goal(name: "Multi-Asset Goal", currency: "USD", targetAmount: 10000, deadline: Date().addingTimeInterval(86_400 * 30))

        // Same currency as goal: contributes directly.
        _ = Asset(currency: "USD", goal: goal, balance: 100)
        // Different currency: requires conversion via exchange rate service.
        _ = Asset(currency: "EUR", goal: goal, balance: 50)
        _ = Asset(currency: "GBP", goal: goal, balance: 20)

        let exchange = MockExchangeRateService()
        exchange.setRate(from: "EUR", to: "USD", rate: 2.0)
        exchange.setRate(from: "GBP", to: "USD", rate: 3.0)

        let calculator = makeCalculator(exchangeRateService: exchange)
        let result = await calculator.calculateCurrentTotal(for: goal)

        // 100 (USD) + 50*2 (EUR->USD) + 20*3 (GBP->USD) = 260
        #expect(abs(result.total - 260.0) < 0.0000001)
        #expect(result.hasConversionError == false)
    }

    @Test("Reports conversion error and skips unconvertible allocations while still summing the rest")
    func reportsConversionErrorWhenExchangeRateFails() async throws {
        let goal = Goal(name: "Mixed Goal", currency: "USD", targetAmount: 10000, deadline: Date().addingTimeInterval(86_400 * 30))

        _ = Asset(currency: "USD", goal: goal, balance: 100)
        _ = Asset(currency: "EUR", goal: goal, balance: 50)

        let exchange = MockExchangeRateService()
        exchange.shouldFail = true

        let calculator = makeCalculator(exchangeRateService: exchange)
        let result = await calculator.calculateCurrentTotal(for: goal)

        // EUR conversion fails, so only the USD allocation is counted.
        #expect(abs(result.total - 100.0) < 0.0000001)
        #expect(result.hasConversionError == true)
    }

    @Test("Returns zero total with no error for a goal without allocations")
    func returnsZeroForGoalWithoutAllocations() async throws {
        let goal = Goal(name: "Empty Goal", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86_400 * 30))

        let exchange = MockExchangeRateService()
        let calculator = makeCalculator(exchangeRateService: exchange)
        let result = await calculator.calculateCurrentTotal(for: goal)

        #expect(result.total == 0)
        #expect(result.hasConversionError == false)
    }

    @Test("Caps each allocation's contribution at the asset's available balance")
    func capsContributionAtAvailableBalance() async throws {
        let goal = Goal(name: "Over-Allocated Goal", currency: "USD", targetAmount: 1000, deadline: Date().addingTimeInterval(86_400 * 30))

        // Allocation amount (200) exceeds the asset's actual balance (50).
        _ = Asset(currency: "USD", goal: goal, balance: 50)
        goal.allocations?.first?.updateAmount(200)

        let exchange = MockExchangeRateService()
        let calculator = makeCalculator(exchangeRateService: exchange)
        let result = await calculator.calculateCurrentTotal(for: goal)

        #expect(result.total == 50)
        #expect(result.hasConversionError == false)
    }
}
