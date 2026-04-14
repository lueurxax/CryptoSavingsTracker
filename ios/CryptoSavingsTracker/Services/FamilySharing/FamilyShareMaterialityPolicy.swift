import Foundation

/// Evaluates whether a rate-drift-induced change in `currentAmount` is material
/// enough to trigger a republish.
///
/// Materiality threshold: 1% of `targetAmount` or $5 (converted to goal currency),
/// whichever is **larger**. This prevents churn on small goals ($5 floor) while
/// catching significant drift on large goals (1% cap).
struct FamilyShareMaterialityPolicy: Sendable {
    nonisolated init() {}

    /// Evaluate whether a change is material for a specific goal.
    ///
    /// - Parameters:
    ///   - newAmount: The newly computed `currentAmount`.
    ///   - lastPublishedAmount: The `currentAmount` from the last published projection.
    ///   - targetAmount: The goal's target amount.
    ///   - goalCurrency: The goal's currency (e.g., "EUR", "JPY", "BTC").
    ///   - usdToGoalCurrencyRate: The current USD-to-goal-currency exchange rate.
    ///     `nil` if the rate is unavailable (falls back to 1% only).
    /// - Returns: `true` if the change exceeds the materiality threshold.
    nonisolated func isMaterial(
        newAmount: Decimal,
        lastPublishedAmount: Decimal,
        targetAmount: Decimal,
        goalCurrency: String,
        usdToGoalCurrencyRate: Decimal?
    ) -> Bool {
        let delta = abs(newAmount - lastPublishedAmount)

        let percentThreshold = targetAmount * Decimal(0.01)  // 1% of target

        let absoluteFloor: Decimal
        if let rate = usdToGoalCurrencyRate, rate > 0 {
            let usdFloor: Decimal = 5  // $5 USD
            let converted = usdFloor * rate
            absoluteFloor = roundToMinorUnits(converted, currency: goalCurrency)
        } else {
            // Rate unavailable — use 1% only (no absolute floor)
            return delta > percentThreshold
        }

        let threshold = max(percentThreshold, absoluteFloor)
        return delta > threshold
    }

    // MARK: - Rounding

    /// Round a decimal to the appropriate number of minor units for the given currency.
    /// Uses `.bankers` rounding (round half to even).
    private nonisolated func roundToMinorUnits(_ value: Decimal, currency: String) -> Decimal {
        let minorUnits = Self.minorUnitsForCurrency(currency)
        var result = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, minorUnits, .bankers)
        return rounded
    }

    /// Number of minor units (decimal places) for common currencies.
    private nonisolated static func minorUnitsForCurrency(_ currency: String) -> Int {
        switch currency.uppercased() {
        case "JPY", "KRW", "VND", "ISK":
            return 0
        case "BHD", "KWD", "OMR":
            return 3
        case "BTC":
            return 8
        case "ETH":
            return 8
        case "SOL", "DOGE", "ADA", "DOT", "AVAX", "MATIC", "XRP":
            return 6
        default:
            return 2  // Most fiat currencies
        }
    }
}
