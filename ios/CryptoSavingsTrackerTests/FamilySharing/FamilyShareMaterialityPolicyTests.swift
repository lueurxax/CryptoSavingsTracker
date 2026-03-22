import XCTest
@testable import CryptoSavingsTracker

final class FamilyShareMaterialityPolicyTests: XCTestCase {

    let policy = FamilyShareMaterialityPolicy()

    // MARK: - 1% Threshold Wins for Large Goals

    func testLargeGoal_onePercentWins() {
        // Target: $10,000. 1% = $100. $5 floor = $5. max($100, $5) = $100.
        // Delta of $150 > $100 → material
        let result = policy.isMaterial(
            newAmount: 5150,
            lastPublishedAmount: 5000,
            targetAmount: 10000,
            goalCurrency: "USD",
            usdToGoalCurrencyRate: 1
        )
        XCTAssertTrue(result)
    }

    func testLargeGoal_belowThreshold_notMaterial() {
        // Delta of $50 < $100 threshold → not material
        let result = policy.isMaterial(
            newAmount: 5050,
            lastPublishedAmount: 5000,
            targetAmount: 10000,
            goalCurrency: "USD",
            usdToGoalCurrencyRate: 1
        )
        XCTAssertFalse(result)
    }

    // MARK: - $5 Floor Wins for Small Goals

    func testSmallGoal_fiveUsdFloorWins() {
        // Target: $200. 1% = $2. $5 floor = $5. max($2, $5) = $5.
        // Delta of $6 > $5 → material
        let result = policy.isMaterial(
            newAmount: 106,
            lastPublishedAmount: 100,
            targetAmount: 200,
            goalCurrency: "USD",
            usdToGoalCurrencyRate: 1
        )
        XCTAssertTrue(result)
    }

    // MARK: - Non-USD Currency

    func testEurGoal_convertsFloor() {
        // $5 USD at rate 0.92 EUR/USD = ~4.60 EUR
        // Target: 8000 EUR. 1% = 80 EUR. max(80, 4.60) = 80.
        // Delta of 100 > 80 → material
        let result = policy.isMaterial(
            newAmount: 4100,
            lastPublishedAmount: 4000,
            targetAmount: 8000,
            goalCurrency: "EUR",
            usdToGoalCurrencyRate: Decimal(string: "0.92")!
        )
        XCTAssertTrue(result)
    }

    // MARK: - Rate Unavailable Fallback

    func testRateUnavailable_usesOnePercentOnly() {
        // No USD-to-goal rate → fall back to 1% only
        // Target: 500. 1% = 5. Delta = 6 > 5 → material
        let result = policy.isMaterial(
            newAmount: 256,
            lastPublishedAmount: 250,
            targetAmount: 500,
            goalCurrency: "BTC",
            usdToGoalCurrencyRate: nil
        )
        XCTAssertTrue(result)
    }

    // MARK: - JPY Rounding (0 decimal places)

    func testJpyGoal_roundsToZeroDecimals() {
        // $5 USD at rate 150 JPY/USD = 750 JPY (rounded to 0 decimals)
        // Target: 500,000 JPY. 1% = 5000 JPY. max(5000, 750) = 5000.
        // Delta of 6000 > 5000 → material
        let result = policy.isMaterial(
            newAmount: 256000,
            lastPublishedAmount: 250000,
            targetAmount: 500000,
            goalCurrency: "JPY",
            usdToGoalCurrencyRate: 150
        )
        XCTAssertTrue(result)
    }
}
