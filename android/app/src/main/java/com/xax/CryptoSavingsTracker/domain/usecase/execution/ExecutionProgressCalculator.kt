package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.Transaction

/**
 * Calculates execution progress by deriving contribution events from transactions
 * and allocation history changes. This matches the iOS ExecutionProgressCalculator
 * approach of tracking actual contribution deltas rather than comparing static
 * funded amounts.
 */
class ExecutionProgressCalculator(
    private val fundedDeltaCalculator: FundedDeltaAttributionCalculator =
        FundedDeltaAttributionCalculator()
) {

    /**
     * Calculate progress for each goal snapshot.
     * Returns contribution-based progress that tracks actual transaction deltas
     * that benefit each goal (matching iOS behavior).
     */
    fun calculateForSnapshots(
        snapshots: List<ExecutionSnapshot>,
        transactions: List<Transaction>,
        allocationHistory: List<AllocationHistory>,
        assetRates: List<ExecutionAssetRate>,
        startedAtMillis: Long,
        nowMillis: Long = System.currentTimeMillis()
    ): List<ExecutionGoalProgress> {
        val goalIds = snapshots.map { it.goalId }.toSet()
        if (goalIds.isEmpty() || startedAtMillis <= 0L) {
            return snapshots.map { snapshot ->
                ExecutionGoalProgress(
                    snapshot = snapshot,
                    contributed = 0.0,
                    plannedAmount = snapshot.requiredAmount,
                    isFulfilled = false
                )
            }
        }

        val contributionsByGoal = mutableMapOf<String, Double>()
        val snapshotCurrencyByGoal = snapshots.associate { it.goalId to it.currency.uppercase() }
        val rateByAssetAndSnapshotCurrency = assetRates
            .filter { it.rate.isFinite() && it.rate > 0.0 }
            .associate { rate ->
                (rate.assetId to rate.snapshotCurrency.uppercase()) to rate.rate
            }

        val snapshotAssetIds = allocationHistory
            .asSequence()
            .filter { it.goalId in goalIds }
            .mapTo(mutableSetOf()) { it.assetId }
        val assetIds = transactions.mapTo(snapshotAssetIds) { it.assetId }
        val relevantHistory = allocationHistory.filter { it.assetId in assetIds }
        val attributionGoalIds = buildSet {
            addAll(goalIds)
            relevantHistory.mapTo(this) { it.goalId }
        }
        requireRatesForAssets(
            assetIds = assetIds,
            snapshotCurrencies = snapshotCurrencyByGoal.values.toSet(),
            rateByAssetAndSnapshotCurrency = rateByAssetAndSnapshotCurrency
        )

        val attributions = fundedDeltaCalculator.calculate(
            goalIds = attributionGoalIds,
            transactions = transactions,
            allocationHistory = relevantHistory,
            startedAtMillis = startedAtMillis,
            nowMillis = nowMillis
        )
        for (attribution in attributions) {
            if (attribution.goalId !in goalIds) continue
            val snapshotCurrency = snapshotCurrencyByGoal[attribution.goalId] ?: continue
            val rate = rateByAssetAndSnapshotCurrency[attribution.assetId to snapshotCurrency]
                ?: throw MissingExecutionAssetRateException(attribution.assetId, snapshotCurrency)
            val converted = attribution.amount * rate
            check(converted.isFinite()) {
                "Execution contribution overflowed for ${attribution.assetId}/$snapshotCurrency"
            }
            contributionsByGoal[attribution.goalId] =
                (contributionsByGoal[attribution.goalId] ?: 0.0) + converted
        }

        return snapshots.map { snapshot ->
            val contributed = contributionsByGoal[snapshot.goalId] ?: 0.0
            val plannedAmount = snapshot.requiredAmount
            val isFulfilled = plannedAmount > 0 && contributed >= plannedAmount
            ExecutionGoalProgress(
                snapshot = snapshot,
                contributed = contributed,
                plannedAmount = plannedAmount,
                isFulfilled = isFulfilled
            )
        }.sortedBy { it.snapshot.goalName }
    }

    private fun requireRatesForAssets(
        assetIds: Set<String>,
        snapshotCurrencies: Set<String>,
        rateByAssetAndSnapshotCurrency: Map<Pair<String, String>, Double>
    ) {
        for (assetId in assetIds) {
            for (snapshotCurrency in snapshotCurrencies) {
                if ((assetId to snapshotCurrency) !in rateByAssetAndSnapshotCurrency) {
                    throw MissingExecutionAssetRateException(assetId, snapshotCurrency)
                }
            }
        }
    }
}

class MissingExecutionAssetRateException(assetId: String, snapshotCurrency: String) : IllegalStateException(
    "Missing execution rate snapshot for $assetId/$snapshotCurrency"
)
