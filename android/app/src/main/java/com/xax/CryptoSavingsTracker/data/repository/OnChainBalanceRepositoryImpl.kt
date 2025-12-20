package com.xax.CryptoSavingsTracker.data.repository

import android.content.Context
import android.content.SharedPreferences
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.data.remote.api.TatumApi
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.util.TokenBucketRateLimiter
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import retrofit2.HttpException
import java.io.IOException
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

@Serializable
private data class BalanceCacheEntry(
    val balance: Double,
    val fetchedAtMillis: Long
)

@Singleton
class OnChainBalanceRepositoryImpl @Inject constructor(
    private val tatumApi: TatumApi,
    @Named("TatumRateLimiter") private val rateLimiter: TokenBucketRateLimiter,
    private val apiKeyStore: ApiKeyStore,
    @ApplicationContext private val context: Context
) : OnChainBalanceRepository {

    private val mutex = Mutex()
    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences("onchain_balance_cache", Context.MODE_PRIVATE)
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val cacheTtlMillis = 5 * 60 * 1000L

    override suspend fun getBalance(asset: Asset, forceRefresh: Boolean): Result<OnChainBalance> = runCatching {
        if (apiKeyStore.getTatumApiKey().isBlank()) {
            throw IllegalStateException("On-chain balance requires a Tatum API key. Add it in Settings or bundle it via Config.properties.")
        }
        val address = asset.address ?: throw IllegalArgumentException("Asset has no address")
        val chainId = asset.chainId ?: throw IllegalArgumentException("Asset has no chainId")

        val key = cacheKey(chainId, address, asset.currency)
        val cached = getCacheEntry(key)
        val now = System.currentTimeMillis()

        if (!forceRefresh && cached != null && now - cached.fetchedAtMillis < cacheTtlMillis) {
            return@runCatching OnChainBalance(
                assetId = asset.id,
                chainId = chainId,
                address = address,
                currency = asset.currency,
                balance = cached.balance,
                fetchedAtMillis = cached.fetchedAtMillis,
                isStale = false
            )
        }

        val staleBalance = cached?.let {
            OnChainBalance(
                assetId = asset.id,
                chainId = chainId,
                address = address,
                currency = asset.currency,
                balance = it.balance,
                fetchedAtMillis = it.fetchedAtMillis,
                isStale = true
            )
        }

        return@runCatching try {
            rateLimiter.acquire()
            val balance = fetchBalanceFromNetwork(chainId = chainId, currency = asset.currency, address = address)
            val entry = BalanceCacheEntry(balance = balance, fetchedAtMillis = now)
            putCacheEntry(key, entry)
            OnChainBalance(
                assetId = asset.id,
                chainId = chainId,
                address = address,
                currency = asset.currency,
                balance = balance,
                fetchedAtMillis = now,
                isStale = false
            )
        } catch (e: Exception) {
            staleBalance ?: throw e
        }
    }

    override suspend fun clearCache() {
        mutex.withLock { prefs.edit().clear().apply() }
    }

    private suspend fun getCacheEntry(key: String): BalanceCacheEntry? {
        return mutex.withLock {
            prefs.getString(key, null)?.let { runCatching { json.decodeFromString<BalanceCacheEntry>(it) }.getOrNull() }
        }
    }

    private suspend fun putCacheEntry(key: String, entry: BalanceCacheEntry) {
        mutex.withLock {
            prefs.edit().putString(key, json.encodeToString(entry)).apply()
        }
    }

    private fun cacheKey(chainId: String, address: String, currency: String): String {
        return "${chainId.lowercase()}:${address.lowercase()}:${currency.uppercase()}"
    }

    private suspend fun fetchBalanceFromNetwork(chainId: String, currency: String, address: String): Double {
        return try {
            when (chainId.lowercase()) {
                "bitcoin" -> tatumApi.getBitcoinBalance(address).confirmedBalance
                "litecoin" -> tatumApi.getLitecoinBalance(address).confirmedBalance
                "bcash" -> tatumApi.getBitcoinCashBalance(address).confirmedBalance
                "dogecoin" -> tatumApi.getDogecoinBalance(address).confirmedBalance
                "solana" -> tatumApi.getSolanaBalance(address).solBalance
                else -> {
                    val tatumChain = tatumEvmChain(chainId)
                    tatumApi.getEvmBalance(chain = tatumChain, address = address).humanReadableBalance
                }
            }
        } catch (e: HttpException) {
            throw e
        } catch (e: IOException) {
            throw e
        }
    }

    private fun tatumEvmChain(chainId: String): String {
        return when (chainId.lowercase()) {
            "ethereum" -> "ethereum"
            "polygon" -> "polygon"
            "bsc" -> "bsc"
            "arbitrum" -> "arbitrum-one"
            "optimism" -> "optimism"
            "base" -> "base"
            else -> chainId.lowercase()
        }
    }
}
