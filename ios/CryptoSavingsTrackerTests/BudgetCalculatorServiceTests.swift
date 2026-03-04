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

    @Test("Snapshot minimum canonicalization rounds up for gating")
    func snapshotCanonicalizationRoundsUp() async throws {
        let exchange = MockExchangeRateService()
        let service = BudgetCalculatorService(exchangeRateService: exchange)
        let deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let goal = TestHelpers.createGoal(
            name: "Goal",
            currency: "USD",
            targetAmount: 1000,
            currentTotal: 0,
            deadline: deadline
        )

        let entered = MoneyQuantizer.normalize(Decimal(string: "999.99")!, currency: "USD", mode: .halfUp)
        let snapshot = await service.computeBudgetSnapshot(
            requestId: UUID(),
            goals: [goal],
            enteredBudget: entered,
            goalsSignature: "sig",
            rateSnapshotId: nil
        )

        #expect(snapshot.minimumRequiredCanonical.value == Decimal(string: "1000"))
        #expect(snapshot.state == .blockedInfeasible)
    }

    @Test("Snapshot ignores legacy epsilon and accepts exact minimum at minor-unit precision")
    func snapshotAcceptsExactMinimum() async throws {
        let exchange = MockExchangeRateService()
        let service = BudgetCalculatorService(exchangeRateService: exchange)
        let deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let goal = TestHelpers.createGoal(
            name: "Goal",
            currency: "USD",
            targetAmount: 1000,
            currentTotal: 0,
            deadline: deadline
        )

        let entered = MoneyQuantizer.normalize(Decimal(string: "1000.00")!, currency: "USD", mode: .halfUp)
        let snapshot = await service.computeBudgetSnapshot(
            requestId: UUID(),
            goals: [goal],
            enteredBudget: entered,
            goalsSignature: "sig",
            rateSnapshotId: nil
        )

        #expect(snapshot.state == .readyFeasible)
        #expect(snapshot.shortfallCanonical.minorUnitValue == 0)
    }

    @Test("Snapshot blocks Save when required FX rates are unavailable")
    func snapshotBlocksOnMissingRates() async throws {
        let exchange = MockExchangeRateService()
        exchange.shouldFail = true
        let service = BudgetCalculatorService(exchangeRateService: exchange)
        let deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let goal = TestHelpers.createGoal(
            name: "EUR Goal",
            currency: "EUR",
            targetAmount: 1000,
            currentTotal: 0,
            deadline: deadline
        )

        let entered = MoneyQuantizer.normalize(Decimal(string: "2000.00")!, currency: "USD", mode: .halfUp)
        let snapshot = await service.computeBudgetSnapshot(
            requestId: UUID(),
            goals: [goal],
            enteredBudget: entered,
            goalsSignature: "sig",
            rateSnapshotId: nil
        )

        #expect(snapshot.state == .blockedRates)
        #expect(snapshot.plan == nil)
        #expect(snapshot.timeline.isEmpty)
        #expect(snapshot.affectedCurrencies == ["EUR"])
    }

    @Test("Snapshot reuses locked FX rates when rateSnapshotId is provided")
    func snapshotReusesLockedRates() async throws {
        let exchange = MockExchangeRateService()
        exchange.setRate(from: "EUR", to: "USD", rate: 1.0)

        let service = BudgetCalculatorService(exchangeRateService: exchange)
        let deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let goal = TestHelpers.createGoal(
            name: "EUR Goal",
            currency: "EUR",
            targetAmount: 1000,
            currentTotal: 0,
            deadline: deadline
        )
        let entered = MoneyQuantizer.normalize(Decimal(string: "1500.00")!, currency: "USD", mode: .halfUp)

        let first = await service.computeBudgetSnapshot(
            requestId: UUID(),
            goals: [goal],
            enteredBudget: entered,
            goalsSignature: "sig",
            rateSnapshotId: nil
        )
        #expect(first.state == .readyFeasible)
        #expect(first.rateSnapshotId != nil)

        exchange.setRate(from: "EUR", to: "USD", rate: 2.0)

        let locked = await service.computeBudgetSnapshot(
            requestId: UUID(),
            goals: [goal],
            enteredBudget: entered,
            goalsSignature: "sig",
            rateSnapshotId: first.rateSnapshotId
        )
        #expect(locked.minimumRequiredCanonical == first.minimumRequiredCanonical)
        #expect(locked.state == first.state)

        let refreshed = await service.computeBudgetSnapshot(
            requestId: UUID(),
            goals: [goal],
            enteredBudget: entered,
            goalsSignature: "sig",
            rateSnapshotId: nil
        )
        #expect(refreshed.minimumRequiredCanonical.minorUnitValue > first.minimumRequiredCanonical.minorUnitValue)
        #expect(refreshed.state == .blockedInfeasible)
    }
}
