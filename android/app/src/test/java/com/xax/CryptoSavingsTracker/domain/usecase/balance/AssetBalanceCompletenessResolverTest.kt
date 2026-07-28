package com.xax.CryptoSavingsTracker.domain.usecase.balance

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class AssetBalanceCompletenessResolverTest {
    private val repository = mockk<OnChainBalanceRepository>()

    @Test
    fun `manual asset is complete without a provider call`() = runTest {
        val result = AssetBalanceCompletenessResolver.resolve(
            asset = asset(address = null, chainId = null),
            manualBalance = 12.5,
            repository = repository,
            nowMillis = 1_000L
        )

        assertThat(result.totalBalanceOrNull).isEqualTo(12.5)
        assertThat(result.issueOrNull).isNull()
        coVerify(exactly = 0) { repository.getBalance(any(), any()) }
    }

    @Test
    fun `address free crypto asset remains a complete manual asset`() = runTest {
        val result = AssetBalanceCompletenessResolver.resolve(
            asset = asset(address = null, chainId = "bitcoin"),
            manualBalance = 12.5,
            repository = repository,
            nowMillis = 1_000L
        )

        assertThat(result.totalBalanceOrNull).isEqualTo(12.5)
        assertThat(result.issueOrNull).isNull()
        coVerify(exactly = 0) { repository.getBalance(any(), any()) }
    }

    @Test
    fun `provider failure makes an addressed asset unavailable instead of manual only`() = runTest {
        val asset = asset()
        coEvery { repository.getBalance(asset, forceRefresh = false) } returns
            Result.failure(IllegalStateException("provider offline"))

        val result = AssetBalanceCompletenessResolver.resolve(
            asset = asset,
            manualBalance = 4.0,
            repository = repository,
            nowMillis = 1_000L
        )

        assertThat(result.totalBalanceOrNull).isNull()
        assertThat(result.issueOrNull).contains("BTC")
        assertThat(result.issueOrNull).contains("Refresh")
    }

    @Test
    fun `quarantined migration identity is unavailable instead of a plausible manual total`() =
        runTest {
            val quarantined = asset(
                address = "0xrate",
                chainId = "legacy-rate-conflict:ethereum:rate-contract"
            ).copy(currency = "USDC")
            coEvery {
                repository.getBalance(quarantined, forceRefresh = false)
            } returns Result.failure(
                IllegalArgumentException("Unsupported on-chain balance chain")
            )

            val result = AssetBalanceCompletenessResolver.resolve(
                asset = quarantined,
                manualBalance = 4.0,
                repository = repository,
                nowMillis = 1_000L
            )

            assertThat(result).isInstanceOf(AssetBalanceCompleteness.Unavailable::class.java)
            assertThat(result.totalBalanceOrNull).isNull()
            assertThat(result.totalBalanceOrNull).isNotEqualTo(4.0)
            coVerify(exactly = 1) {
                repository.getBalance(quarantined, forceRefresh = false)
            }
        }

    @Test
    fun `stale provider snapshot is never authoritative`() = runTest {
        val asset = asset()
        coEvery { repository.getBalance(asset, forceRefresh = false) } returns
            Result.success(balance(asset = asset, isStale = true))

        val result = AssetBalanceCompletenessResolver.resolve(
            asset = asset,
            manualBalance = 4.0,
            repository = repository,
            nowMillis = 1_000L
        )

        assertThat(result.totalBalanceOrNull).isNull()
        assertThat(result.issueOrNull).contains("stale")
    }

    @Test
    fun `future dated provider snapshot is rejected`() = runTest {
        val asset = asset()
        coEvery { repository.getBalance(asset, forceRefresh = false) } returns
            Result.success(balance(asset = asset, fetchedAtMillis = 1_001L))

        val result = AssetBalanceCompletenessResolver.resolve(
            asset = asset,
            manualBalance = 4.0,
            repository = repository,
            nowMillis = 1_000L
        )

        assertThat(result.totalBalanceOrNull).isNull()
        assertThat(result.issueOrNull).contains("invalid")
    }

    @Test
    fun `mismatched provider identity is rejected`() = runTest {
        val asset = asset()
        coEvery { repository.getBalance(asset, forceRefresh = false) } returns
            Result.success(balance(asset = asset).copy(assetId = "another-asset"))

        val result = AssetBalanceCompletenessResolver.resolve(
            asset = asset,
            manualBalance = 4.0,
            repository = repository,
            nowMillis = 1_000L
        )

        assertThat(result.totalBalanceOrNull).isNull()
        assertThat(result.issueOrNull).contains("invalid")
    }

    @Test
    fun `fresh matching provider snapshot completes the total`() = runTest {
        val asset = asset()
        coEvery { repository.getBalance(asset, forceRefresh = false) } returns
            Result.success(balance(asset = asset, balance = 6.5))

        val result = AssetBalanceCompletenessResolver.resolve(
            asset = asset,
            manualBalance = 4.0,
            repository = repository,
            nowMillis = 1_000L
        )

        assertThat(result.totalBalanceOrNull).isEqualTo(10.5)
        assertThat(result.issueOrNull).isNull()
    }

    @Test
    fun `canonical chain and address aliases remain the same provider identity`() = runTest {
        val asset = asset(
            address = "0xABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD",
            chainId = "ETH"
        ).copy(currency = "ETH")
        coEvery { repository.getBalance(asset, forceRefresh = false) } returns Result.success(
            OnChainBalance(
                assetId = asset.id,
                chainId = "ethereum",
                address = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                currency = "ETH",
                balance = 6.5,
                fetchedAtMillis = 999L,
                isStale = false
            )
        )

        val result = AssetBalanceCompletenessResolver.resolve(
            asset = asset,
            manualBalance = 4.0,
            repository = repository,
            nowMillis = 1_000L
        )

        assertThat(result.totalBalanceOrNull).isEqualTo(10.5)
        assertThat(result.issueOrNull).isNull()
    }

    private fun asset(
        address: String? = "bc1qwallet",
        chainId: String? = "bitcoin"
    ) = Asset(
        id = "asset-1",
        currency = "BTC",
        address = address,
        chainId = chainId,
        createdAt = 1L,
        updatedAt = 1L
    )

    private fun balance(
        asset: Asset,
        balance: Double = 6.0,
        fetchedAtMillis: Long = 999L,
        isStale: Boolean = false
    ) = OnChainBalance(
        assetId = asset.id,
        chainId = checkNotNull(asset.chainId),
        address = checkNotNull(asset.address),
        currency = asset.currency,
        balance = balance,
        fetchedAtMillis = fetchedAtMillis,
        isStale = isStale
    )
}
