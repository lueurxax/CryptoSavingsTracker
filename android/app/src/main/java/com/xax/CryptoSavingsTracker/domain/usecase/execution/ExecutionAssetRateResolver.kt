package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateQuote
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import javax.inject.Inject

internal fun executionRelevantAssetIds(
    snapshots: List<ExecutionSnapshot>,
    allocationHistory: List<AllocationHistory>
): Set<String> {
    val snapshotGoalIds = snapshots.mapTo(mutableSetOf()) { it.goalId }
    return allocationHistory
        .asSequence()
        .filter { it.goalId in snapshotGoalIds }
        .mapTo(mutableSetOf()) { it.assetId }
}

class ExecutionAssetRateResolver @Inject constructor(
    private val assetRepository: AssetRepository,
    private val exchangeRateRepository: ExchangeRateRepository
) {
    suspend fun capture(
        assetIds: Set<String>,
        snapshotCurrencies: Set<String>,
        capturedAtMillis: Long = System.currentTimeMillis()
    ): List<ExecutionAssetRate> {
        val rates = mutableListOf<ExecutionAssetRate>()

        for (assetId in assetIds) {
            val assetCurrency = assetRepository.getAssetById(assetId)?.currency?.uppercase()
                ?: throw IllegalStateException("Execution asset not found: $assetId")
            for (snapshotCurrency in snapshotCurrencies.map(String::uppercase)) {
                val quote = if (assetCurrency == snapshotCurrency) {
                    ExchangeRateQuote(
                        rate = 1.0,
                        fetchedAtMillis = capturedAtMillis
                    )
                } else {
                    exchangeRateRepository.fetchRateForImmutableSnapshot(
                        from = assetCurrency,
                        to = snapshotCurrency,
                        maximumAgeMillis = MAXIMUM_EXECUTION_RATE_AGE_MILLIS
                    )
                }

                check(quote.rate.isFinite() && quote.rate > 0.0) {
                    "Invalid execution rate for $assetCurrency/$snapshotCurrency: ${quote.rate}"
                }
                rates += ExecutionAssetRate(
                    assetId = assetId,
                    snapshotCurrency = snapshotCurrency,
                    rate = quote.rate,
                    capturedAtMillis = quote.fetchedAtMillis
                )
            }
        }

        return rates
    }

    private companion object {
        const val MAXIMUM_EXECUTION_RATE_AGE_MILLIS = 5 * 60 * 1000L
    }
}
