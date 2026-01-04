import XCTest

@testable import CryptoSavingsTracker

@MainActor
final class ExecutionContributionCalculatorTests: XCTestCase {
    private struct MockRates: ExchangeRateServiceProtocol {
        let rate: Double
        let shouldThrow: Bool

        func fetchRate(from: String, to: String) async throws -> Double {
            if shouldThrow {
                throw ExchangeRateError.rateNotAvailable
            }
            if from.uppercased() == to.uppercased() { return 1 }
            return rate
        }

        func hasValidConfiguration() -> Bool { true }
        func setOfflineMode(_ offline: Bool) { }
    }

    func testRemainingToCloseWithoutConversion() async {
        let calculator = ExecutionContributionCalculator(exchangeRateService: MockRates(rate: 0.5, shouldThrow: false))
        let snapshot = ExecutionGoalSnapshot(
            goalId: UUID(),
            goalName: "Goal A",
            plannedAmount: 100,
            currency: "USD",
            flexState: "flexible",
            isSkipped: false,
            isProtected: false
        )

        let remaining = calculator.remainingToClose(goalSnapshot: snapshot, contributed: 30)
        XCTAssertEqual(remaining, 70, accuracy: 0.0001)
    }

    func testRemainingToCloseConversion() async {
        let calculator = ExecutionContributionCalculator(exchangeRateService: MockRates(rate: 0.5, shouldThrow: false))
        let snapshot = ExecutionGoalSnapshot(
            goalId: UUID(),
            goalName: "Goal A",
            plannedAmount: 100,
            currency: "USD",
            flexState: "flexible",
            isSkipped: false,
            isProtected: false
        )

        let remaining = await calculator.remainingToClose(goalSnapshot: snapshot, contributed: 40, in: "EUR")
        XCTAssertEqual(remaining, 30, accuracy: 0.0001)
    }

    func testRemainingToCloseReturnsZeroWhenOverfunded() async {
        let calculator = ExecutionContributionCalculator(exchangeRateService: MockRates(rate: 2, shouldThrow: false))
        let snapshot = ExecutionGoalSnapshot(
            goalId: UUID(),
            goalName: "Goal A",
            plannedAmount: 100,
            currency: "USD",
            flexState: "flexible",
            isSkipped: false,
            isProtected: false
        )

        let remaining = calculator.remainingToClose(goalSnapshot: snapshot, contributed: 120)
        XCTAssertEqual(remaining, 0, accuracy: 0.0001)
    }

    func testConvertAmountReturnsNilOnRateFailure() async {
        let calculator = ExecutionContributionCalculator(exchangeRateService: MockRates(rate: 0.5, shouldThrow: true))
        let converted = await calculator.convertAmount(10, from: "USD", to: "EUR")
        XCTAssertNil(converted)
    }
}
