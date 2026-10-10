package com.xax.CryptoSavingsTracker.data.repository

import android.content.Context
import android.content.SharedPreferences
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.data.remote.api.TatumApi
import com.xax.CryptoSavingsTracker.data.remote.api.TatumUTXOBalance
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.util.TokenBucketRateLimiter
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.io.IOException
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class OnChainBalanceRepositoryChangesTest {
    @Test
    fun `fresh fetch and forced refresh publish changes but a cache hit does not`() = runTest {
        val fixture = Fixture()
        val repository = fixture.repository
        assertThat(repository.balanceChanges.value).isEqualTo(0L)

        assertThat(repository.getBalance(fixture.asset).getOrThrow().balance).isEqualTo(50.0)
        assertThat(repository.balanceChanges.value).isEqualTo(1L)
        fixture.networkBalance = 100.0
        assertThat(repository.getBalance(fixture.asset).getOrThrow().balance).isEqualTo(50.0)
        assertThat(repository.balanceChanges.value).isEqualTo(1L)

        assertThat(repository.getBalance(fixture.asset, forceRefresh = true).getOrThrow().balance).isEqualTo(100.0)
        assertThat(repository.balanceChanges.value).isEqualTo(2L)
    }

    @Test
    fun `cache invalidation publishes a change and discards the old balance`() = runTest {
        val fixture = Fixture()
        fixture.repository.getBalance(fixture.asset).getOrThrow()

        fixture.repository.clearCache()
        fixture.networkBalance = 80.0

        assertThat(fixture.repository.balanceChanges.value).isEqualTo(2L)
        assertThat(fixture.repository.getBalance(fixture.asset).getOrThrow().balance).isEqualTo(80.0)
    }

    @Test
    fun `failed refresh keeps fallback balance and does not publish a cache change`() = runTest {
        val fixture = Fixture()
        fixture.repository.getBalance(fixture.asset).getOrThrow()
        fixture.failNetwork = true

        val result = fixture.repository.getBalance(fixture.asset, forceRefresh = true).getOrThrow()

        assertThat(result.balance).isEqualTo(50.0)
        assertThat(result.isStale).isTrue()
        assertThat(fixture.repository.balanceChanges.value).isEqualTo(1L)
    }

    private class Fixture {
        val asset = Asset("asset", "BTC", "fixture-address", "bitcoin", 1L, 1L)
        var networkBalance = 50.0
        var failNetwork = false
        val repository: OnChainBalanceRepositoryImpl

        init {
            val values = mutableMapOf<String, String?>()
            val context = mockk<Context>()
            val prefs = mockk<SharedPreferences>()
            val editor = mockk<SharedPreferences.Editor>(relaxed = true)
            every { context.getSharedPreferences("onchain_balance_cache_v3", Context.MODE_PRIVATE) } returns prefs
            every { prefs.getString(any(), null) } answers { values[firstArg()] }
            every { prefs.edit() } returns editor
            every { editor.putString(any(), any()) } answers {
                values[firstArg()] = secondArg()
                editor
            }
            every { editor.clear() } answers { values.clear(); editor }
            val keys = mockk<ApiKeyStore>()
            every { keys.getTatumApiKey() } returns "fixture-only-key"
            val api = mockk<TatumApi>()
            coEvery { api.getBitcoinBalance(asset.address!!) } coAnswers {
                if (failNetwork) throw IOException("Fixture network failure")
                TatumUTXOBalance(incoming = networkBalance.toString(), outgoing = "0")
            }
            repository = OnChainBalanceRepositoryImpl(
                api, TokenBucketRateLimiter(10.0, 10.0), keys, context,
                mockk<OnChainAssetProviderIdentityVerifier> {
                    coEvery { assertUnchanged(asset) } returns Unit
                }
            )
        }
    }
}
