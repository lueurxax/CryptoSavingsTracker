import Foundation

/// Pure, non-@MainActor domain calculator for goal progress.
///
/// This calculator operates exclusively on `Sendable` value types (`GoalProgressInput`,
/// `RateSnapshot`) and does not depend on SwiftData, ViewModels, or any UI framework.
/// It is safe to call from any actor context, including the republish coordinator's
/// dedicated actor.
///
/// Canonical computation path for `currentAmount` in shared projections (Section 7.0.3).
struct GoalProgressCalculator: Sendable {
    nonisolated init() {}

    /// Calculate progress for a single goal.
    ///
    /// For each allocation, converts `allocatedAmount` from `assetCurrency` to the
    /// goal's `currency` using the provided `rates` snapshot, then sums all converted
    /// amounts to produce `currentAmount`.
    ///
    /// - Parameters:
    ///   - input: Pure value-type goal input with allocations.
    ///   - rates: Immutable rate snapshot for currency conversion.
    /// - Returns: Calculated `currentAmount` and `progressRatio`.
    nonisolated func calculateProgress(for input: GoalProgressInput, rates: RateSnapshot) -> GoalProgressResult {
        var totalAmount: Decimal = 0
        var missingRatePairs: Set<String> = []

        for allocation in input.allocations {
            let conversion = convert(
                amount: allocation.allocatedAmount,
                from: allocation.assetCurrency,
                to: input.currency,
                rates: rates
            )
            totalAmount += conversion.amount
            if let missingRatePair = conversion.missingRatePair {
                missingRatePairs.insert(missingRatePair)
            }
        }

        let progressRatio: Double
        if input.targetAmount > 0 {
            let ratio = NSDecimalNumber(decimal: totalAmount / input.targetAmount).doubleValue
            progressRatio = min(max(ratio, 0), 1.0)
        } else {
            progressRatio = 0
        }

        return GoalProgressResult(
            currentAmount: totalAmount,
            progressRatio: progressRatio,
            isComplete: missingRatePairs.isEmpty,
            missingRatePairs: missingRatePairs
        )
    }

    /// Calculate progress for multiple goals in a batch.
    nonisolated func calculateProgress(for inputs: [GoalProgressInput], rates: RateSnapshot) -> [UUID: GoalProgressResult] {
        var results: [UUID: GoalProgressResult] = [:]
        for input in inputs {
            results[input.goalID] = calculateProgress(for: input, rates: rates)
        }
        return results
    }

    // MARK: - Currency Conversion

    /// Convert an amount from one currency to another using the rate snapshot.
    ///
    /// Tries direct rate first, then reciprocal, then cross-rate via USD.
    private nonisolated func convert(
        amount: Decimal,
        from: String,
        to: String,
        rates: RateSnapshot
    ) -> (amount: Decimal, missingRatePair: String?) {
        let fromNorm = from.uppercased()
        let toNorm = to.uppercased()

        guard fromNorm != toNorm else { return (amount, nil) }
        guard amount > 0 else { return (0, nil) }

        // Direct rate
        if let rate = rates.rate(from: fromNorm, to: toNorm), rate > 0 {
            return (amount * rate, nil)
        }

        // Reciprocal rate
        if let rate = rates.rate(from: toNorm, to: fromNorm), rate > 0 {
            return (amount / rate, nil)
        }

        // Cross-rate via USD
        if let rateToUSD = rates.rate(from: fromNorm, to: "USD"), rateToUSD > 0,
           let rateFromUSD = rates.rate(from: "USD", to: toNorm), rateFromUSD > 0 {
            return (amount * rateToUSD * rateFromUSD, nil)
        }

        // Reciprocal cross-rate via USD
        if let rateUsdToFrom = rates.rate(from: "USD", to: fromNorm), rateUsdToFrom > 0,
           let rateUsdToTo = rates.rate(from: toNorm, to: "USD"), rateUsdToTo > 0 {
            return (amount / rateUsdToFrom * (1 / rateUsdToTo), nil)
        }

        return (
            0,
            CurrencyPair.canonicalKey(from: fromNorm, to: toNorm)
        )
    }
}
