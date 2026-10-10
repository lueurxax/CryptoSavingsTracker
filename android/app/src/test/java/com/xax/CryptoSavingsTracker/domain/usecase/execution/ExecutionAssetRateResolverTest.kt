package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateQuote
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class ExecutionAssetRateResolverTest {
    @Test
    fun `captures the asset rate in each snapshot currency`() = runTest {
        val assetRepository = mockk<AssetRepository>()
        val exchangeRateRepository = mockk<ExchangeRateRepository>()
        coEvery { assetRepository.getAssetById("btc-asset") } returns Asset(
            id = "btc-asset",
            currency = "BTC",
            address = null,
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 1L
        )
        coEvery {
            exchangeRateRepository.fetchRateForImmutableSnapshot(
                "BTC",
                "USD",
                5 * 60 * 1000L
            )
        } returns ExchangeRateQuote(
            rate = 10_000.0,
            fetchedAtMillis = 123L
        )

        val rates = ExecutionAssetRateResolver(
            assetRepository = assetRepository,
            exchangeRateRepository = exchangeRateRepository
        ).capture(
            assetIds = setOf("btc-asset"),
            snapshotCurrencies = setOf("USD"),
            capturedAtMillis = 456L
        )

        assertThat(rates).containsExactly(
            ExecutionAssetRate(
                assetId = "btc-asset",
                snapshotCurrency = "USD",
                rate = 10_000.0,
                capturedAtMillis = 123L
            )
        )
    }

    @Test
    fun `rate lookup failure is propagated instead of being treated as a missing contribution`() = runTest {
        val assetRepository = mockk<AssetRepository>()
        val exchangeRateRepository = mockk<ExchangeRateRepository>()
        coEvery { assetRepository.getAssetById("btc-asset") } returns Asset(
            id = "btc-asset",
            currency = "BTC",
            address = null,
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 1L
        )
        coEvery {
            exchangeRateRepository.fetchRateForImmutableSnapshot(
                "BTC",
                "USD",
                5 * 60 * 1000L
            )
        } throws IllegalStateException("rate unavailable")

        val failure = runCatching {
            ExecutionAssetRateResolver(
                assetRepository = assetRepository,
                exchangeRateRepository = exchangeRateRepository
            ).capture(
                assetIds = setOf("btc-asset"),
                snapshotCurrencies = setOf("USD")
            )
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IllegalStateException::class.java)
        assertThat(failure).hasMessageThat().contains("rate unavailable")
    }
}
