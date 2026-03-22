import XCTest
@testable import CryptoSavingsTracker

final class GoalProgressCalculatorTests: XCTestCase {

    let calculator = GoalProgressCalculator()

    // MARK: - Single Currency (No Conversion)

    func testSingleCurrencyGoal_noConversionNeeded() {
        let input = GoalProgressInput(
            goalID: UUID(),
            currency: "USD",
            targetAmount: 1000,
            allocations: [
                AllocationInput(assetCurrency: "USD", allocatedAmount: 500)
            ]
        )
        let rates = RateSnapshot(rates: [:], timestamp: Date())
        let result = calculator.calculateProgress(for: input, rates: rates)

        XCTAssertEqual(result.currentAmount, 500)
        XCTAssertEqual(result.progressRatio, 0.5, accuracy: 0.001)
    }

    // MARK: - Multi-Currency Conversion

    func testMultiCurrencyGoal_convertsCorrectly() {
        let input = GoalProgressInput(
            goalID: UUID(),
            currency: "USD",
            targetAmount: 10000,
            allocations: [
                AllocationInput(assetCurrency: "BTC", allocatedAmount: Decimal(string: "0.1")!),
                AllocationInput(assetCurrency: "USD", allocatedAmount: 2000)
            ]
        )
        let rates = RateSnapshot(
            rates: [CurrencyPair(from: "BTC", to: "USD"): 50000],
            timestamp: Date()
        )
        let result = calculator.calculateProgress(for: input, rates: rates)

        // 0.1 BTC * 50000 = 5000 + 2000 USD = 7000
        XCTAssertEqual(result.currentAmount, 7000)
        XCTAssertEqual(result.progressRatio, 0.7, accuracy: 0.001)
    }

    // MARK: - Zero Target

    func testZeroTarget_returnsZeroProgress() {
        let input = GoalProgressInput(
            goalID: UUID(),
            currency: "USD",
            targetAmount: 0,
            allocations: [
                AllocationInput(assetCurrency: "USD", allocatedAmount: 100)
            ]
        )
        let rates = RateSnapshot(rates: [:], timestamp: Date())
        let result = calculator.calculateProgress(for: input, rates: rates)

        XCTAssertEqual(result.progressRatio, 0)
    }

    // MARK: - Missing Rate

    func testMissingRate_returnsZeroForThatAllocation() {
        let input = GoalProgressInput(
            goalID: UUID(),
            currency: "EUR",
            targetAmount: 1000,
            allocations: [
                AllocationInput(assetCurrency: "XYZ_UNKNOWN", allocatedAmount: 100)
            ]
        )
        let rates = RateSnapshot(rates: [:], timestamp: Date())
        let result = calculator.calculateProgress(for: input, rates: rates)

        XCTAssertEqual(result.currentAmount, 0)
    }

    // MARK: - Batch Calculation

    func testBatchCalculation_returnsResultPerGoal() {
        let goal1 = GoalProgressInput(goalID: UUID(), currency: "USD", targetAmount: 1000, allocations: [
            AllocationInput(assetCurrency: "USD", allocatedAmount: 500)
        ])
        let goal2 = GoalProgressInput(goalID: UUID(), currency: "USD", targetAmount: 2000, allocations: [
            AllocationInput(assetCurrency: "USD", allocatedAmount: 1000)
        ])
        let rates = RateSnapshot(rates: [:], timestamp: Date())

        let results = calculator.calculateProgress(for: [goal1, goal2], rates: rates)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[goal1.goalID]?.currentAmount, 500)
        XCTAssertEqual(results[goal2.goalID]?.currentAmount, 1000)
    }

    // MARK: - Reciprocal Rate

    func testReciprocalRate_usedWhenDirectMissing() {
        let input = GoalProgressInput(
            goalID: UUID(),
            currency: "USD",
            targetAmount: 10000,
            allocations: [
                AllocationInput(assetCurrency: "ETH", allocatedAmount: 2)
            ]
        )
        // Only provide the reverse rate (USD -> ETH)
        let rates = RateSnapshot(
            rates: [CurrencyPair(from: "USD", to: "ETH"): Decimal(string: "0.0005")!],
            timestamp: Date()
        )
        let result = calculator.calculateProgress(for: input, rates: rates)

        // 2 ETH / 0.0005 = 4000 USD
        XCTAssertEqual(result.currentAmount, 4000)
    }

    // MARK: - Progress Capped at 1.0

    func testProgress_cappedAtOne() {
        let input = GoalProgressInput(
            goalID: UUID(),
            currency: "USD",
            targetAmount: 100,
            allocations: [
                AllocationInput(assetCurrency: "USD", allocatedAmount: 200)
            ]
        )
        let rates = RateSnapshot(rates: [:], timestamp: Date())
        let result = calculator.calculateProgress(for: input, rates: rates)

        XCTAssertEqual(result.progressRatio, 1.0, accuracy: 0.001)
    }
}
