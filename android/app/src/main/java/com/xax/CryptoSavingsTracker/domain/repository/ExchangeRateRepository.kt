package com.xax.CryptoSavingsTracker.domain.repository

/**
 * Repository interface for fetching exchange rates.
 * Matches iOS ExchangeRateService behavior.
 */
interface ExchangeRateRepository {
    /**
     * Fetch the exchange rate from one currency to another.
     * @param from Source currency code (e.g., "BTC", "USD", "EUR")
     * @param to Target currency code (e.g., "USD", "EUR", "BTC")
     * @return The exchange rate, or throws ExchangeRateException on failure
     */
    suspend fun fetchRate(from: String, to: String): Double

    /**
     * Check if the service has a valid API key configured.
     */
    fun hasValidConfiguration(): Boolean

    /**
     * Clear the rate cache.
     */
    suspend fun clearCache()
}

/**
 * Exception thrown when exchange rate fetching fails.
 */
sealed class ExchangeRateException(message: String) : Exception(message) {
    data object RateNotAvailable : ExchangeRateException("Exchange rate temporarily unavailable. Please check your internet connection.")
    data object NetworkError : ExchangeRateException("Network error. Please try again later.")
    data object RateLimitExceeded : ExchangeRateException("API rate limit exceeded. Please wait before trying again.")
    data object ApiKeyMissing : ExchangeRateException("API key not configured. Please add your CoinGecko API key in settings.")
}
