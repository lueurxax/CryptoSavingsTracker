package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import kotlinx.coroutines.CancellationException
import java.util.Locale
import javax.inject.Inject

/** Shared valuation for live tracking and persisted completion, expressed in each goal's currency. */
class CalculateExecutionProgressUseCase @Inject constructor(
    private val exchangeRateRepository: ExchangeRateRepository
) {
    private val calculator = ExecutionProgressCalculator()

    suspend operator fun invoke(
        snapshots: List<ExecutionSnapshot>,
        transactions: List<Transaction>,
        allocationHistory: List<AllocationHistory>,
        assets: List<Asset>,
        startedAtMillis: Long,
        nowMillis: Long = System.currentTimeMillis()
    ): List<ExecutionGoalProgress> {
        val contributions = calculator.calculateContributionsByAsset(
            snapshots, transactions, allocationHistory, startedAtMillis, nowMillis
        )
        val assetsById = assets.associateBy { it.id }
        val rates = mutableMapOf<Pair<String, String>, Result<Double>>()

        return snapshots.map { snapshot ->
            var contributed = 0.0
            var error: String? = null
            try {
                val targetCurrency = snapshot.currency.trim().uppercase(Locale.ROOT)
                require(targetCurrency.isNotEmpty()) { "Goal currency is missing" }
                for ((key, amount) in contributions) {
                    if (key.goalId != snapshot.goalId) continue
                    val sourceCurrency = assetsById[key.assetId]?.currency?.trim()?.uppercase(Locale.ROOT)
                    require(!sourceCurrency.isNullOrEmpty()) { "Currency is missing for asset ${key.assetId}" }
                    val rate = if (sourceCurrency == targetCurrency) {
                        1.0
                    } else {
                        val pair = sourceCurrency to targetCurrency
                        val cached = rates[pair] ?: try {
                            val value = exchangeRateRepository.fetchRate(sourceCurrency, targetCurrency)
                            require(value.isFinite() && value > 0.0) {
                                "Exchange rate unavailable for $sourceCurrency → $targetCurrency"
                            }
                            Result.success(value)
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (failure: Exception) {
                            Result.failure<Double>(failure)
                        }.also { rates[pair] = it }
                        cached.getOrThrow()
                    }
                    contributed += amount * rate
                    require(contributed.isFinite()) { "Contribution amount is invalid" }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                // A partial sum must not masquerade as a complete goal-currency amount.
                contributed = 0.0
                error = "Progress unavailable: ${failure.message ?: "currency conversion failed"}"
            }
            ExecutionGoalProgress(
                snapshot = snapshot,
                contributed = contributed,
                plannedAmount = snapshot.requiredAmount,
                isFulfilled = error == null && snapshot.requiredAmount > 0.0 && contributed >= snapshot.requiredAmount,
                conversionError = error
            )
        }.sortedBy { it.snapshot.goalName }
    }
}
