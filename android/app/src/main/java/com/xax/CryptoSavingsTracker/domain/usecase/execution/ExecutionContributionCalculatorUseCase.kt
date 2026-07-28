package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import javax.inject.Inject
import kotlin.math.max

/**
 * Calculates remaining-to-close amounts using only the immutable rate matrix
 * captured for the active execution. Live FX is intentionally not a fallback:
 * a suggestion that cannot be proven from the execution snapshot fails closed.
 */
class ExecutionContributionCalculatorUseCase @Inject constructor() {
    fun remainingToClose(goalProgress: ExecutionGoalProgress): Double {
        return max(0.0, goalProgress.plannedAmount - goalProgress.contributed)
    }

    fun remainingToCloseInAsset(
        goalProgress: ExecutionGoalProgress,
        assetId: String,
        assetRates: List<ExecutionAssetRate>
    ): Double? {
        val remaining = remainingToClose(goalProgress)
        if (remaining <= 0.0) return 0.0

        val rate = uniqueRate(
            assetId = assetId,
            snapshotCurrency = goalProgress.snapshot.currency,
            assetRates = assetRates
        ) ?: return null
        return (remaining / rate).takeIf { it.isFinite() && it >= 0.0 }
    }

    /**
     * Converts between two execution snapshot currencies through a deterministic
     * asset row that has both persisted rates. This is used only for display;
     * asset contribution suggestions use [remainingToCloseInAsset] directly.
     */
    fun convertSnapshotCurrencyAmount(
        amount: Double,
        fromSnapshotCurrency: String,
        toSnapshotCurrency: String,
        assetRates: List<ExecutionAssetRate>
    ): Double? {
        if (!amount.isFinite() || amount < 0.0) return null
        if (amount == 0.0) return 0.0
        if (fromSnapshotCurrency.equals(toSnapshotCurrency, ignoreCase = true)) return amount
        if (!isValidMatrix(assetRates)) return null

        val from = fromSnapshotCurrency.uppercase()
        val to = toSnapshotCurrency.uppercase()
        val rateByAssetAndCurrency = assetRates.associate {
            (it.assetId to it.snapshotCurrency.uppercase()) to it.rate
        }
        val anchorAssetId = assetRates
            .asSequence()
            .map { it.assetId }
            .distinct()
            .sorted()
            .firstOrNull { assetId ->
                (assetId to from) in rateByAssetAndCurrency &&
                    (assetId to to) in rateByAssetAndCurrency
            }
            ?: return null
        val fromRate = rateByAssetAndCurrency.getValue(anchorAssetId to from)
        val toRate = rateByAssetAndCurrency.getValue(anchorAssetId to to)
        return (amount * toRate / fromRate).takeIf { it.isFinite() && it >= 0.0 }
    }

    private fun uniqueRate(
        assetId: String,
        snapshotCurrency: String,
        assetRates: List<ExecutionAssetRate>
    ): Double? {
        if (!isValidMatrix(assetRates)) return null
        val matches = assetRates.filter {
            it.assetId == assetId &&
                it.snapshotCurrency.equals(snapshotCurrency, ignoreCase = true)
        }
        return matches.singleOrNull()?.rate
    }

    private fun isValidMatrix(assetRates: List<ExecutionAssetRate>): Boolean {
        if (
            assetRates.any {
                it.assetId.isBlank() ||
                    it.snapshotCurrency.isBlank() ||
                    !it.rate.isFinite() ||
                    it.rate <= 0.0 ||
                    it.capturedAtMillis < 0L
            }
        ) {
            return false
        }
        val keys = assetRates.map { it.assetId to it.snapshotCurrency.uppercase() }
        return keys.size == keys.toSet().size
    }
}
