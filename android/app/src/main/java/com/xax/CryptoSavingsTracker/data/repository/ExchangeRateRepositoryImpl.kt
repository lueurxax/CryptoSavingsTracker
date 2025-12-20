package com.xax.CryptoSavingsTracker.data.repository

import android.content.Context
import android.content.SharedPreferences
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.data.remote.api.CoinGeckoApi
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateException
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import com.xax.CryptoSavingsTracker.domain.util.TokenBucketRateLimiter
import java.io.IOException
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

/**
 * Implementation of ExchangeRateRepository using CoinGecko API.
 * Matches iOS ExchangeRateService behavior with caching and multiple rate fetching strategies.
 */
@Singleton
class ExchangeRateRepositoryImpl @Inject constructor(
    private val coinGeckoApi: CoinGeckoApi,
    @Named("CoinGeckoRateLimiter") private val rateLimiter: TokenBucketRateLimiter,
    private val apiKeyStore: ApiKeyStore,
    @ApplicationContext private val context: Context
) : ExchangeRateRepository {

    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences("exchange_rate_cache", Context.MODE_PRIVATE)
    }

    private val mutex = Mutex()
    private val cachedRates = mutableMapOf<String, MutableMap<String, Double>>()
    private val lastFetchTime = mutableMapOf<String, Long>()

    private val cacheExpirationMs = 5 * 60 * 1000L // 5 minutes

    // Map common crypto symbols to CoinGecko IDs
    private val cryptoIdMap = mapOf(
        "BTC" to "bitcoin",
        "ETH" to "ethereum",
        "USDT" to "tether",
        "BNB" to "binancecoin",
        "SOL" to "solana",
        "USDC" to "usd-coin",
        "XRP" to "ripple",
        "ADA" to "cardano",
        "DOGE" to "dogecoin",
        "TRX" to "tron",
        "AVAX" to "avalanche-2",
        "DOT" to "polkadot",
        "MATIC" to "matic-network",
        "LINK" to "chainlink",
        "SHIB" to "shiba-inu",
        "LTC" to "litecoin",
        "BCH" to "bitcoin-cash",
        "ALGO" to "algorand",
        "XLM" to "stellar",
        "UNI" to "uniswap"
    )

    private val fiatCurrencies = setOf("USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF", "CNY", "INR", "KRW")
    private val usdPegged = setOf("USD", "USDT", "USDC")

    init {
        loadCachedData()
    }

    override suspend fun fetchRate(from: String, to: String): Double {
        val canonicalFrom = from.uppercase()
        val canonicalTo = to.uppercase()

        // Same currency = 1.0
        if (canonicalFrom == canonicalTo) {
            return 1.0
        }

        // Fast-path stablecoin pegs
        if (usdPegged.contains(canonicalFrom) && usdPegged.contains(canonicalTo)) {
            return 1.0
        }

        // Check cache
        getCachedRate(canonicalFrom, canonicalTo)?.let { return it }
        val stale = getStaleRate(canonicalFrom, canonicalTo)

        // Fetch from API
        return try {
            rateLimiter.acquire()
            val rate = fetchRateFromAPI(canonicalFrom, canonicalTo)
            cacheRate(canonicalFrom, canonicalTo, rate)
            rate
        } catch (e: Exception) {
            stale ?: throw e
        }
    }

    override fun hasValidConfiguration(): Boolean {
        return apiKeyStore.getCoinGeckoApiKey().isNotEmpty()
    }

    override suspend fun clearCache() {
        mutex.withLock {
            cachedRates.clear()
            lastFetchTime.clear()
            prefs.edit().clear().apply()
        }
    }

    private suspend fun getCachedRate(from: String, to: String): Double? {
        val cacheKey = "$from-$to"
        return mutex.withLock {
            val lastFetch = lastFetchTime[cacheKey] ?: return@withLock null
            if (System.currentTimeMillis() - lastFetch < cacheExpirationMs) {
                cachedRates[from]?.get(to)
            } else {
                null
            }
        }
    }

    private suspend fun getStaleRate(from: String, to: String): Double? {
        return mutex.withLock {
            cachedRates[from]?.get(to)
        }
    }

    private suspend fun cacheRate(from: String, to: String, rate: Double) {
        val cacheKey = "$from-$to"
        mutex.withLock {
            if (cachedRates[from] == null) {
                cachedRates[from] = mutableMapOf()
            }
            cachedRates[from]!![to] = rate
            lastFetchTime[cacheKey] = System.currentTimeMillis()
        }
        saveCachedData()
    }

    private suspend fun fetchRateFromAPI(from: String, to: String): Double {
        val fromIsFiat = fiatCurrencies.contains(from)
        val toIsFiat = fiatCurrencies.contains(to)

        return try {
            when {
                // Fiat to Fiat: cross-convert through USDT
                fromIsFiat && toIsFiat -> fetchCrossRate(from, to, "USDT")

                // Crypto to Fiat: direct rate
                !fromIsFiat && toIsFiat -> fetchDirectRate(from, to)

                // Fiat to Crypto: inverse of Crypto to Fiat
                fromIsFiat && !toIsFiat -> {
                    val cryptoInFiat = fetchDirectRate(to, from)
                    if (cryptoInFiat <= 0) throw ExchangeRateException.RateNotAvailable
                    1.0 / cryptoInFiat
                }

                // Crypto to Crypto: convert via USD
                else -> fetchCryptoToCryptoRateViaUSD(from, to)
            }
        } catch (e: IOException) {
            throw ExchangeRateException.NetworkError
        } catch (e: ExchangeRateException) {
            throw e
        } catch (e: Exception) {
            throw ExchangeRateException.RateNotAvailable
        }
    }

    private suspend fun fetchDirectRate(from: String, to: String): Double {
        val fromId = coinGeckoId(from)

        try {
            val response = coinGeckoApi.getSimplePrice(
                ids = fromId,
                vsCurrencies = to.lowercase()
            )

            response[fromId]?.get(to.lowercase())?.let { return it }

            // Fallback to markets endpoint
            return fetchRateFromMarkets(fromId, to)
                ?: throw ExchangeRateException.RateNotAvailable

        } catch (e: retrofit2.HttpException) {
            when (e.code()) {
                429 -> throw ExchangeRateException.RateLimitExceeded
                401, 403 -> throw ExchangeRateException.ApiKeyMissing
                else -> throw ExchangeRateException.RateNotAvailable
            }
        }
    }

    private suspend fun fetchCryptoToCryptoRateViaUSD(from: String, to: String): Double {
        val fromId = coinGeckoId(from)
        val toId = coinGeckoId(to)

        try {
            val response = coinGeckoApi.getSimplePrice(
                ids = "$fromId,$toId",
                vsCurrencies = "usd"
            )

            val fromUsd = response[fromId]?.get("usd")
                ?: throw ExchangeRateException.RateNotAvailable
            val toUsd = response[toId]?.get("usd")
                ?: throw ExchangeRateException.RateNotAvailable

            if (fromUsd <= 0 || toUsd <= 0) {
                throw ExchangeRateException.RateNotAvailable
            }

            return fromUsd / toUsd

        } catch (e: retrofit2.HttpException) {
            when (e.code()) {
                429 -> throw ExchangeRateException.RateLimitExceeded
                401, 403 -> throw ExchangeRateException.ApiKeyMissing
                else -> throw ExchangeRateException.RateNotAvailable
            }
        }
    }

    private suspend fun fetchRateFromMarkets(id: String, to: String): Double? {
        if (id.isEmpty()) return null

        return try {
            val response = coinGeckoApi.getCoinMarkets(
                vsCurrency = to.lowercase(),
                ids = id
            )

            response.firstOrNull()?.current_price?.takeIf { it > 0 }
        } catch (e: Exception) {
            null
        }
    }

    private suspend fun fetchCrossRate(from: String, to: String, intermediary: String): Double {
        val intermediaryId = if (intermediary == "USDT") "tether" else intermediary.lowercase()

        try {
            val response = coinGeckoApi.getSimplePrice(
                ids = intermediaryId,
                vsCurrencies = "${from.lowercase()},${to.lowercase()}"
            )

            val rates = response[intermediaryId]
                ?: throw ExchangeRateException.RateNotAvailable

            val fromRate = rates[from.lowercase()]
                ?: throw ExchangeRateException.RateNotAvailable
            val toRate = rates[to.lowercase()]
                ?: throw ExchangeRateException.RateNotAvailable

            if (fromRate <= 0) throw ExchangeRateException.RateNotAvailable

            // Cross rate: from -> to = toRate / fromRate
            return toRate / fromRate

        } catch (e: retrofit2.HttpException) {
            when (e.code()) {
                429 -> throw ExchangeRateException.RateLimitExceeded
                401, 403 -> throw ExchangeRateException.ApiKeyMissing
                else -> throw ExchangeRateException.RateNotAvailable
            }
        }
    }

    private fun coinGeckoId(symbol: String): String {
        val upper = symbol.uppercase()
        return cryptoIdMap[upper] ?: upper.lowercase()
    }

    private fun saveCachedData() {
        try {
            val ratesJson = Json.encodeToString(cachedRates.mapValues { it.value.toMap() })
            val timesJson = Json.encodeToString(lastFetchTime.toMap())

            prefs.edit()
                .putString("cached_rates", ratesJson)
                .putString("cached_times", timesJson)
                .apply()
        } catch (e: Exception) {
            // Ignore cache save errors
        }
    }

    private fun loadCachedData() {
        try {
            prefs.getString("cached_rates", null)?.let { ratesJson ->
                val rates: Map<String, Map<String, Double>> = Json.decodeFromString(ratesJson)
                rates.forEach { (from, toRates) ->
                    cachedRates[from] = toRates.toMutableMap()
                }
            }

            prefs.getString("cached_times", null)?.let { timesJson ->
                val times: Map<String, Long> = Json.decodeFromString(timesJson)
                lastFetchTime.putAll(times)
            }
        } catch (e: Exception) {
            // Ignore cache load errors
        }
    }
}
