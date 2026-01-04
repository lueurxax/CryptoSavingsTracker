package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import javax.inject.Inject
import kotlin.math.max

/**
 * Calculates remaining-to-close amounts and performs currency conversion for execution tracking.
 * Mirrors iOS ExecutionContributionCalculator behavior.
 */
class ExecutionContributionCalculatorUseCase @Inject constructor(
    private val exchangeRateRepository: ExchangeRateRepository
) {
    fun remainingToClose(goalProgress: ExecutionGoalProgress): Double {
        return max(0.0, goalProgress.plannedAmount - goalProgress.contributed)
    }

    suspend fun remainingToCloseInCurrency(
        goalProgress: ExecutionGoalProgress,
        currency: String
    ): Double? {
        val remaining = remainingToClose(goalProgress)
        if (remaining <= 0.0) return 0.0

        val from = goalProgress.snapshot.currency
        if (from.equals(currency, ignoreCase = true)) {
            return remaining
        }

        return runCatching {
            val rate = exchangeRateRepository.fetchRate(from, currency)
            remaining * rate
        }.getOrNull()
    }

    suspend fun convertAmount(amount: Double, from: String, to: String): Double? {
        if (amount <= 0.0) return 0.0
        if (from.equals(to, ignoreCase = true)) return amount
        return runCatching {
            val rate = exchangeRateRepository.fetchRate(from, to)
            amount * rate
        }.getOrNull()
    }
}
