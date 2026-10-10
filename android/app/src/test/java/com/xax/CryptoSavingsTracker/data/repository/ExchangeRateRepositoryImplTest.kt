package com.xax.CryptoSavingsTracker.data.repository

import android.content.Context
import android.content.SharedPreferences
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.data.remote.api.CoinGeckoApi
import com.xax.CryptoSavingsTracker.domain.model.ExchangeRateCurrencyCatalog
import com.xax.CryptoSavingsTracker.domain.model.OnChainAssetRouteCatalog
import com.xax.CryptoSavingsTracker.domain.util.TokenBucketRateLimiter
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import java.io.IOException

@OptIn(ExperimentalCoroutinesApi::class)
class ExchangeRateRepositoryImplTest {
    @Test
    fun `slower pre-clear quote cannot roll refreshed rate cache back`() = runTest {
        val api = mockk<CoinGeckoApi>()
        val calls = AtomicInteger(0)
        val firstStarted = CompletableDeferred<Unit>()
        val secondStarted = CompletableDeferred<Unit>()
        val firstRate = CompletableDeferred<Double>()
        val secondRate = CompletableDeferred<Double>()
        coEvery {
            api.getSimplePrice(ids = "bitcoin", vsCurrencies = "usd")
        } coAnswers {
            when (calls.incrementAndGet()) {
                1 -> {
                    firstStarted.complete(Unit)
                    mapOf("bitcoin" to mapOf("usd" to firstRate.await()))
                }
                2 -> {
                    secondStarted.complete(Unit)
                    mapOf("bitcoin" to mapOf("usd" to secondRate.await()))
                }
                else -> error("Unexpected provider quote request")
            }
        }
        val repository = repository(api)

        val preClear = async { repository.fetchRate("BTC", "USD") }
        firstStarted.await()
        repository.clearCache()
        val refreshed = async { repository.fetchRate("BTC", "USD") }
        secondStarted.await()

        secondRate.complete(20.0)
        assertThat(refreshed.await()).isEqualTo(20.0)
        firstRate.complete(10.0)
        assertThat(preClear.await()).isEqualTo(10.0)

        assertThat(repository.fetchRate("BTC", "USD")).isEqualTo(20.0)
        assertThat(calls.get()).isEqualTo(2)
        assertThat(repository.observeRateInvalidations().first()).isEqualTo(2L)
    }

    @Test
    fun `cache clear fences an older quote before it registers its request generation`() = runTest {
        val api = mockk<CoinGeckoApi>()
        val calls = AtomicInteger(0)
        coEvery {
            api.getSimplePrice(ids = "bitcoin", vsCurrencies = "usd")
        } coAnswers {
            val rate = if (calls.incrementAndGet() == 1) 10.0 else 20.0
            mapOf("bitcoin" to mapOf("usd" to rate))
        }
        val repository = repository(api)
        val repositoryMutex = repository.privateMutex()

        repositoryMutex.lock()
        val preClear = async { repository.fetchRate("BTC", "USD") }
        runCurrent()
        val clear = async { repository.clearCache() }
        runCurrent()
        repositoryMutex.unlock()

        clear.await()
        assertThat(preClear.await()).isEqualTo(10.0)

        assertThat(repository.fetchRate("BTC", "USD")).isEqualTo(20.0)
        assertThat(calls.get()).isEqualTo(2)
    }

    @Test
    fun `provider fetch and explicit cache clear publish rate invalidations`() = runTest {
        val api = mockk<CoinGeckoApi>()
        coEvery {
            api.getSimplePrice(ids = "bitcoin", vsCurrencies = "usd")
        } returns mapOf("bitcoin" to mapOf("usd" to 42_000.0))
        val repository = repository(api)

        assertThat(repository.observeRateInvalidations().first()).isEqualTo(0L)
        assertThat(repository.fetchRate("BTC", "USD")).isEqualTo(42_000.0)
        assertThat(repository.observeRateInvalidations().first()).isEqualTo(1L)

        repository.clearCache()

        assertThat(repository.observeRateInvalidations().first()).isEqualTo(2L)
    }

    @Test
    fun `every addressed route and selectable goal currency has an explicit rate contract`() {
        assertThat(
            OnChainAssetRouteCatalog.supportedPersistenceCurrencies
                .filterNot(ExchangeRateCurrencyCatalog::supports)
        ).isEmpty()
        assertThat(
            ExchangeRateCurrencyCatalog.goalCurrencies
                .filterNot { it in ExchangeRateCurrencyCatalog.fiatCurrencies }
        ).isEmpty()
        assertThat(ExchangeRateCurrencyCatalog.providerId("APE")).isEqualTo("apecoin")
    }

    @Test
    fun `POL uses the current CoinGecko Polygon Ecosystem Token id`() = runTest {
        val api = mockk<CoinGeckoApi>()
        coEvery {
            api.getSimplePrice(
                ids = "polygon-ecosystem-token",
                vsCurrencies = "usd"
            )
        } returns mapOf(
            "polygon-ecosystem-token" to mapOf("usd" to 0.42)
        )

        val rate = repository(api).fetchRate("POL", "USD")

        assertThat(rate).isEqualTo(0.42)
        coVerify(exactly = 1) {
            api.getSimplePrice(
                ids = "polygon-ecosystem-token",
                vsCurrencies = "usd"
            )
        }
    }

    @Test
    fun `legacy MATIC alias uses the current CoinGecko Polygon Ecosystem Token id`() = runTest {
        val api = mockk<CoinGeckoApi>()
        coEvery {
            api.getSimplePrice(
                ids = "polygon-ecosystem-token",
                vsCurrencies = "usd"
            )
        } returns mapOf(
            "polygon-ecosystem-token" to mapOf("usd" to 0.42)
        )

        val rate = repository(api).fetchRate("MATIC", "USD")

        assertThat(rate).isEqualTo(0.42)
        coVerify(exactly = 1) {
            api.getSimplePrice(
                ids = "polygon-ecosystem-token",
                vsCurrencies = "usd"
            )
        }
    }

    @Test
    fun `BRL is routed as fiat for a direct BTC quote`() = runTest {
        val api = mockk<CoinGeckoApi>()
        coEvery {
            api.getSimplePrice(ids = "bitcoin", vsCurrencies = "brl")
        } returns mapOf("bitcoin" to mapOf("brl" to 350_000.0))

        val rate = repository(api).fetchRate("BTC", "BRL")

        assertThat(rate).isEqualTo(350_000.0)
        coVerify(exactly = 1) {
            api.getSimplePrice(ids = "bitcoin", vsCurrencies = "brl")
        }
    }

    @Test
    fun `APE uses its explicit CoinGecko provider id`() = runTest {
        val api = mockk<CoinGeckoApi>()
        coEvery {
            api.getSimplePrice(ids = "apecoin", vsCurrencies = "usd")
        } returns mapOf("apecoin" to mapOf("usd" to 0.75))

        val rate = repository(api).fetchRate("APE", "USD")

        assertThat(rate).isEqualTo(0.75)
        coVerify(exactly = 1) {
            api.getSimplePrice(ids = "apecoin", vsCurrencies = "usd")
        }
    }

    @Test
    fun `immutable snapshot quote rejects an expired persisted fallback`() = runTest {
        val api = mockk<CoinGeckoApi>()
        coEvery {
            api.getSimplePrice(ids = "bitcoin", vsCurrencies = "usd")
        } throws IOException("offline")
        val oldTimestamp = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
        val repository = repository(
            api = api,
            cachedRatesJson = """{"BTC":{"USD":123.0}}""",
            cachedTimesJson = """{"BTC-USD":$oldTimestamp}"""
        )

        val failure = runCatching {
            repository.fetchRateForImmutableSnapshot(
                from = "BTC",
                to = "USD",
                maximumAgeMillis = 5 * 60 * 1000L
            )
        }.exceptionOrNull()

        assertThat(failure).isNotNull()
    }

    @Test
    fun `immutable fallback evaluates maximum age when the fallback is returned`() = runTest {
        val api = mockk<CoinGeckoApi>()
        val calls = AtomicInteger(0)
        val firstRequestStarted = CompletableDeferred<Unit>()
        val releaseFirstRequest = CompletableDeferred<Unit>()
        coEvery {
            api.getSimplePrice(ids = "bitcoin", vsCurrencies = "usd")
        } coAnswers {
            when (calls.incrementAndGet()) {
                1 -> {
                    firstRequestStarted.complete(Unit)
                    releaseFirstRequest.await()
                    throw IOException("offline")
                }
                2 -> mapOf("bitcoin" to mapOf("usd" to 123.0))
                else -> error("Unexpected provider quote request")
            }
        }
        val clock = MutableClock(nowMillis = 1_000L)
        val repository = repository(
            api = api,
            currentTimeMillis = clock::readMillis
        )

        val olderRequest = async {
            runCatching {
                repository.fetchRateForImmutableSnapshot(
                    from = "BTC",
                    to = "USD",
                    maximumAgeMillis = 5L
                )
            }.exceptionOrNull()
        }
        firstRequestStarted.await()

        val refreshed = repository.fetchRateForImmutableSnapshot(
            from = "BTC",
            to = "USD",
            maximumAgeMillis = 5L
        )
        assertThat(refreshed.rate).isEqualTo(123.0)
        assertThat(refreshed.fetchedAtMillis).isEqualTo(1_000L)

        clock.nowMillis = 1_006L
        releaseFirstRequest.complete(Unit)

        assertThat(olderRequest.await()).isNotNull()
    }

    @Test
    fun `provider quote rejects zero negative NaN and infinite rates`() = runTest {
        val invalidRates = listOf(
            0.0,
            -1.0,
            Double.NaN,
            Double.POSITIVE_INFINITY,
            Double.NEGATIVE_INFINITY
        )

        invalidRates.forEach { invalidRate ->
            val api = mockk<CoinGeckoApi>()
            coEvery {
                api.getSimplePrice(ids = "bitcoin", vsCurrencies = "usd")
            } returns mapOf("bitcoin" to mapOf("usd" to invalidRate))

            val failure = runCatching {
                repository(api).fetchRate("BTC", "USD")
            }.exceptionOrNull()

            assertThat(failure).isNotNull()
        }
    }

    private fun repository(
        api: CoinGeckoApi,
        cachedRatesJson: String? = null,
        cachedTimesJson: String? = null,
        currentTimeMillis: () -> Long = System::currentTimeMillis
    ): ExchangeRateRepositoryImpl {
        val context = mockk<Context>()
        val prefs = mockk<SharedPreferences>()
        val editor = mockk<SharedPreferences.Editor>(relaxed = true)
        val apiKeyStore = mockk<ApiKeyStore>(relaxed = true)

        every { context.getSharedPreferences(any(), Context.MODE_PRIVATE) } returns prefs
        every { prefs.getString("cached_rates", null) } returns cachedRatesJson
        every { prefs.getString("cached_times", null) } returns cachedTimesJson
        every { prefs.edit() } returns editor
        every { editor.putString(any(), any()) } returns editor

        return ExchangeRateRepositoryImpl(
            coinGeckoApi = api,
            rateLimiter = TokenBucketRateLimiter(
                maxTokens = 100.0,
                refillTokensPerSecond = 100.0
            ),
            apiKeyStore = apiKeyStore,
            context = context,
            currentTimeMillis = currentTimeMillis
        )
    }

    private fun ExchangeRateRepositoryImpl.privateMutex(): Mutex {
        return javaClass.getDeclaredField("mutex")
            .apply { isAccessible = true }
            .get(this) as Mutex
    }

    private class MutableClock(var nowMillis: Long) {
        fun readMillis(): Long = nowMillis
    }
}
