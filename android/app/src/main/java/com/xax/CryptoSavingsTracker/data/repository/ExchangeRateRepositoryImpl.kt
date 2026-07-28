package com.xax.CryptoSavingsTracker.data.repository

import android.content.Context
import android.content.SharedPreferences
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.data.remote.api.CoinGeckoApi
import com.xax.CryptoSavingsTracker.domain.model.ExchangeRateCurrencyCatalog
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateException
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateQuote
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
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
class ExchangeRateRepositoryImpl internal constructor(
    private val coinGeckoApi: CoinGeckoApi,
    private val rateLimiter: TokenBucketRateLimiter,
    private val apiKeyStore: ApiKeyStore,
    private val context: Context,
    private val currentTimeMillis: () -> Long
) : ExchangeRateRepository {

    @Inject
    constructor(
        coinGeckoApi: CoinGeckoApi,
        @Named("CoinGeckoRateLimiter") rateLimiter: TokenBucketRateLimiter,
        apiKeyStore: ApiKeyStore,
        @ApplicationContext context: Context
    ) : this(
        coinGeckoApi = coinGeckoApi,
        rateLimiter = rateLimiter,
        apiKeyStore = apiKeyStore,
        context = context,
        currentTimeMillis = System::currentTimeMillis
    )

    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences("exchange_rate_cache", Context.MODE_PRIVATE)
    }

    private val mutex = Mutex()
    private val cachedRates = mutableMapOf<String, MutableMap<String, Double>>()
    private val lastFetchTime = mutableMapOf<String, Long>()
    private val latestRequestGenerationByKey = mutableMapOf<String, Long>()
    private var cacheEpoch: Long = 0L
    private val rateInvalidationVersion = MutableStateFlow(0L)

    private val cacheExpirationMs = 5 * 60 * 1000L // 5 minutes

    private val usdPegged = setOf("USD", "USDT", "USDC")

    init {
        loadCachedData()
    }

    override fun observeRateInvalidations(): Flow<Long> =
        rateInvalidationVersion.asStateFlow()

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
        val requestCacheEpoch = currentCacheEpoch()
        getCachedRate(canonicalFrom, canonicalTo)?.let { return it }
        val requestToken = beginNetworkRequest(
            from = canonicalFrom,
            to = canonicalTo,
            requestCacheEpoch = requestCacheEpoch
        )

        // Fetch from API
        return try {
            rateLimiter.acquire()
            val rate = requireValidRate(
                fetchRateFromAPI(canonicalFrom, canonicalTo)
            )
            cacheRateIfLatest(
                from = canonicalFrom,
                to = canonicalTo,
                rate = rate,
                requestToken = requestToken
            )
            rate
        } catch (e: Exception) {
            getCachedRate(canonicalFrom, canonicalTo) ?: throw e
        }
    }

    override suspend fun fetchRateForImmutableSnapshot(
        from: String,
        to: String,
        maximumAgeMillis: Long
    ): ExchangeRateQuote {
        require(maximumAgeMillis >= 0) { "maximumAgeMillis must be non-negative" }
        val canonicalFrom = from.uppercase()
        val canonicalTo = to.uppercase()
        val now = currentTimeMillis()

        if (canonicalFrom == canonicalTo ||
            (canonicalFrom in usdPegged && canonicalTo in usdPegged)
        ) {
            return ExchangeRateQuote(rate = 1.0, fetchedAtMillis = now)
        }

        val requestCacheEpoch = currentCacheEpoch()
        getCachedQuote(canonicalFrom, canonicalTo, maximumAgeMillis, now)?.let {
            return it
        }
        val requestToken = beginNetworkRequest(
            from = canonicalFrom,
            to = canonicalTo,
            requestCacheEpoch = requestCacheEpoch
        )

        return try {
            rateLimiter.acquire()
            val rate = requireValidRate(
                fetchRateFromAPI(canonicalFrom, canonicalTo)
            )
            val fetchedAtMillis = currentTimeMillis()
            cacheRateIfLatest(
                from = canonicalFrom,
                to = canonicalTo,
                rate = rate,
                fetchedAtMillis = fetchedAtMillis,
                requestToken = requestToken
            )
            ExchangeRateQuote(rate = rate, fetchedAtMillis = fetchedAtMillis)
        } catch (error: Exception) {
            getCachedQuote(
                from = canonicalFrom,
                to = canonicalTo,
                maximumAgeMillis = maximumAgeMillis,
                nowMillis = currentTimeMillis()
            ) ?: throw error
        }
    }

    override fun hasValidConfiguration(): Boolean {
        return apiKeyStore.getCoinGeckoApiKey().isNotEmpty()
    }

    override suspend fun clearCache() {
        mutex.withLock {
            cacheEpoch += 1L
            latestRequestGenerationByKey.clear()
            cachedRates.clear()
            lastFetchTime.clear()
            prefs.edit().clear().apply()
        }
        rateInvalidationVersion.update { it + 1L }
    }

    private suspend fun getCachedRate(from: String, to: String): Double? {
        return getCachedQuote(
            from = from,
            to = to,
            maximumAgeMillis = cacheExpirationMs,
            nowMillis = currentTimeMillis()
        )?.rate
    }

    private suspend fun getCachedQuote(
        from: String,
        to: String,
        maximumAgeMillis: Long,
        nowMillis: Long
    ): ExchangeRateQuote? {
        val cacheKey = "$from-$to"
        return mutex.withLock {
            val lastFetch = lastFetchTime[cacheKey] ?: return@withLock null
            val rate = cachedRates[from]?.get(to) ?: return@withLock null
            if (nowMillis < lastFetch || nowMillis - lastFetch > maximumAgeMillis) {
                return@withLock null
            }
            if (!rate.isValidExchangeRate()) {
                return@withLock null
            }
            ExchangeRateQuote(rate = rate, fetchedAtMillis = lastFetch)
        }
    }

    private suspend fun currentCacheEpoch(): Long = mutex.withLock { cacheEpoch }

    private suspend fun beginNetworkRequest(
        from: String,
        to: String,
        requestCacheEpoch: Long
    ): CacheRequestToken? {
        val cacheKey = "$from-$to"
        return mutex.withLock {
            if (cacheEpoch != requestCacheEpoch) {
                return@withLock null
            }
            val nextGeneration = (latestRequestGenerationByKey[cacheKey] ?: 0L) + 1L
            latestRequestGenerationByKey[cacheKey] = nextGeneration
            CacheRequestToken(
                cacheEpoch = requestCacheEpoch,
                requestGeneration = nextGeneration
            )
        }
    }

    private suspend fun cacheRateIfLatest(
        from: String,
        to: String,
        rate: Double,
        requestToken: CacheRequestToken?,
        fetchedAtMillis: Long = currentTimeMillis()
    ): Boolean {
        requireValidRate(rate)
        val cacheKey = "$from-$to"
        val cacheUpdated = mutex.withLock {
            if (
                requestToken == null ||
                cacheEpoch != requestToken.cacheEpoch ||
                latestRequestGenerationByKey[cacheKey] != requestToken.requestGeneration
            ) {
                return@withLock false
            }
            if (cachedRates[from] == null) {
                cachedRates[from] = mutableMapOf()
            }
            cachedRates[from]!![to] = rate
            lastFetchTime[cacheKey] = fetchedAtMillis
            saveCachedData()
            true
        }
        if (cacheUpdated) {
            rateInvalidationVersion.update { it + 1L }
        }
        return cacheUpdated
    }

    private suspend fun fetchRateFromAPI(from: String, to: String): Double {
        val fromIsFiat = ExchangeRateCurrencyCatalog.fiatCurrencies.contains(from)
        val toIsFiat = ExchangeRateCurrencyCatalog.fiatCurrencies.contains(to)

        return try {
            when {
                // Fiat to Fiat: cross-convert through USDT
                fromIsFiat && toIsFiat -> fetchCrossRate(from, to, "USDT")

                // Crypto to Fiat: direct rate
                !fromIsFiat && toIsFiat -> fetchDirectRate(from, to)

                // Fiat to Crypto: inverse of Crypto to Fiat
                fromIsFiat && !toIsFiat -> {
                    val cryptoInFiat = requireValidRate(fetchDirectRate(to, from))
                    requireValidRate(1.0 / cryptoInFiat)
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

            response[fromId]?.get(to.lowercase())?.let {
                return requireValidRate(it)
            }

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

            return requireValidRate(
                requireValidRate(fromUsd) / requireValidRate(toUsd)
            )

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

            response.firstOrNull()?.current_price?.takeIf { it.isValidExchangeRate() }
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

            // Cross rate: from -> to = toRate / fromRate
            return requireValidRate(
                requireValidRate(toRate) / requireValidRate(fromRate)
            )

        } catch (e: retrofit2.HttpException) {
            when (e.code()) {
                429 -> throw ExchangeRateException.RateLimitExceeded
                401, 403 -> throw ExchangeRateException.ApiKeyMissing
                else -> throw ExchangeRateException.RateNotAvailable
            }
        }
    }

    private fun coinGeckoId(symbol: String): String {
        return ExchangeRateCurrencyCatalog.providerId(symbol)
            ?: throw ExchangeRateException.RateNotAvailable
    }

    private fun requireValidRate(rate: Double): Double {
        if (!rate.isValidExchangeRate()) {
            throw ExchangeRateException.RateNotAvailable
        }
        return rate
    }

    private fun Double.isValidExchangeRate(): Boolean = isFinite() && this > 0.0

    private data class CacheRequestToken(
        val cacheEpoch: Long,
        val requestGeneration: Long
    )

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
