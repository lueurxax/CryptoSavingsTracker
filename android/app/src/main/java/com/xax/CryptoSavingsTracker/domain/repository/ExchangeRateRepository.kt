package com.xax.CryptoSavingsTracker.domain.repository

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

data class ExchangeRateQuote(
    val rate: Double,
    val fetchedAtMillis: Long
)

/**
 * Repository interface for fetching exchange rates.
 * Matches iOS ExchangeRateService behavior.
 */
interface ExchangeRateRepository {
    /**
     * Fetch the exchange rate from one currency to another.
     * Implementations may use cached fallback data only when it is no more than
     * five minutes old at the actual return time.
     * @param from Source currency code (e.g., "BTC", "USD", "EUR")
     * @param to Target currency code (e.g., "USD", "EUR", "BTC")
     * @return The exchange rate, or throws ExchangeRateException on failure
     */
    suspend fun fetchRate(from: String, to: String): Double

    /**
     * Fetch a rate that is safe to freeze into an immutable financial
     * snapshot. Implementations must reject fallback data older than
     * [maximumAgeMillis] and retain the real provider/cache timestamp.
     */
    suspend fun fetchRateForImmutableSnapshot(
        from: String,
        to: String,
        maximumAgeMillis: Long
    ): ExchangeRateQuote {
        return ExchangeRateQuote(
            rate = fetchRate(from, to),
            fetchedAtMillis = System.currentTimeMillis()
        )
    }

    /**
     * Check if the service has a valid API key configured.
     */
    fun hasValidConfiguration(): Boolean

    /**
     * Clear the rate cache.
     */
    suspend fun clearCache()

    /**
     * Monotonic cache/provider data version used to invalidate derived
     * financial views without polling.
     */
    fun observeRateInvalidations(): Flow<Long> = flowOf(0L)
}

/**
 * Exception thrown when exchange rate fetching fails.
 */
sealed class ExchangeRateException(message: String) : Exception(message) {
    data object RateNotAvailable : ExchangeRateException("Exchange rate temporarily unavailable. Please check your internet connection.")
    data object NetworkError : ExchangeRateException("Network error. Please try again later.")
    data object RateLimitExceeded : ExchangeRateException("API rate limit exceeded. Please wait before trying again.")
    data object ApiKeyMissing : ExchangeRateException("CoinGecko API key not configured. Add one in Settings to increase rate limits.")
}
