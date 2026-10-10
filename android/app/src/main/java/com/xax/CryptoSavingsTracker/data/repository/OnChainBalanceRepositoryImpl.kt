package com.xax.CryptoSavingsTracker.data.repository

import android.content.Context
import android.content.SharedPreferences
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.data.remote.api.TatumApi
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainAddressIdentityV1
import com.xax.CryptoSavingsTracker.domain.model.OnChainAssetRouteCatalog
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.util.TokenBucketRateLimiter
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
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
    @ApplicationContext private val context: Context,
    private val assetProviderIdentityVerifier: OnChainAssetProviderIdentityVerifier
) : OnChainBalanceRepository {

    private val mutex = Mutex()
    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences(CACHE_NAMESPACE, Context.MODE_PRIVATE)
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val cacheTtlMillis = 5 * 60 * 1000L
    private val latestRequestGenerationByKey = mutableMapOf<String, Long>()
    private var cacheEpoch: Long = 0L
    private val balanceInvalidationVersion = MutableStateFlow(0L)

    override val balanceChanges = balanceInvalidationVersion.asStateFlow()

    override fun observeBalanceInvalidations(): Flow<Long> =
        balanceInvalidationVersion.asStateFlow()

    override suspend fun getBalance(
        asset: Asset,
        forceRefresh: Boolean
    ): Result<OnChainBalance> = loadBalance(
        asset = asset,
        forceRefresh = forceRefresh,
        publishToCache = true
    )

    override suspend fun getFreshBalanceForPreflight(
        asset: Asset
    ): Result<OnChainBalance> = loadBalance(
        asset = asset,
        forceRefresh = true,
        publishToCache = false
    )

    private suspend fun loadBalance(
        asset: Asset,
        forceRefresh: Boolean,
        publishToCache: Boolean
    ): Result<OnChainBalance> = runCatching {
        val invocationCacheEpoch = if (publishToCache) {
            currentCacheEpoch()
        } else {
            null
        }
        val address = asset.address ?: throw IllegalArgumentException("Asset has no address")
        val rawChainId = asset.chainId ?: throw IllegalArgumentException("Asset has no chainId")
        val chainId = OnChainAssetRouteCatalog.normalizeChainId(rawChainId)

        validateCurrencyForChain(chainId = chainId, currency = asset.currency)

        val key = cacheKey(chainId, address, asset.currency)
        val now = System.currentTimeMillis()
        val cached = getCacheEntry(key, now)

        if (!forceRefresh && cached != null && now - cached.fetchedAtMillis < cacheTtlMillis) {
            requireCurrentProviderIdentity(asset)
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

        // iOS parity: allow returning cached balances even when the API key is missing (offline / key removed).
        if (apiKeyStore.getTatumApiKey().isBlank()) {
            if (staleBalance != null) {
                requireCurrentProviderIdentity(asset)
                return@runCatching staleBalance
            }
            throw IllegalStateException(
                    "On-chain balance requires a Tatum API key. Add it in Settings or bundle it via Config.properties."
                )
        }

        val requestToken = if (publishToCache) {
            beginNetworkRequest(
                key = key,
                requestCacheEpoch = checkNotNull(invocationCacheEpoch)
            )
        } else {
            null
        }
        val balance = try {
            rateLimiter.acquire()
            fetchBalanceFromNetwork(
                chainId = chainId,
                currency = asset.currency,
                address = address
            )
        } catch (e: Exception) {
            if (staleBalance != null) {
                requireCurrentProviderIdentity(asset)
                return@runCatching staleBalance
            }
            throw e
        }
        check(balance.isFinite() && balance >= 0.0) {
            "On-chain balance response is invalid"
        }
        requireCurrentProviderIdentity(asset)
        val fetchedAtMillis = System.currentTimeMillis()
        val entry = BalanceCacheEntry(
            balance = balance,
            fetchedAtMillis = fetchedAtMillis
        )
        if (publishToCache) {
            val cacheUpdated = putCacheEntryIfLatest(
                key = key,
                requestToken = requestToken,
                entry = entry
            )
            if (cacheUpdated) {
                balanceInvalidationVersion.update { it + 1L }
            }
        }
        OnChainBalance(
            assetId = asset.id,
            chainId = chainId,
            address = address,
            currency = asset.currency,
            balance = balance,
            fetchedAtMillis = fetchedAtMillis,
            isStale = false
        )
    }

    override suspend fun clearCache() {
        mutex.withLock {
            cacheEpoch += 1L
            latestRequestGenerationByKey.clear()
            prefs.edit().clear().apply()
        }
        balanceInvalidationVersion.update { it + 1L }
    }

    private suspend fun getCacheEntry(key: String, nowMillis: Long): BalanceCacheEntry? {
        return mutex.withLock {
            prefs.getString(key, null)
                ?.let { runCatching { json.decodeFromString<BalanceCacheEntry>(it) }.getOrNull() }
                ?.takeIf { entry ->
                    entry.balance.isFinite() &&
                        entry.balance >= 0.0 &&
                        entry.fetchedAtMillis in 1L..nowMillis
                }
        }
    }

    private suspend fun currentCacheEpoch(): Long = mutex.withLock { cacheEpoch }

    private suspend fun beginNetworkRequest(
        key: String,
        requestCacheEpoch: Long
    ): CacheRequestToken? {
        return mutex.withLock {
            if (cacheEpoch != requestCacheEpoch) {
                return@withLock null
            }
            val nextGeneration = (latestRequestGenerationByKey[key] ?: 0L) + 1L
            latestRequestGenerationByKey[key] = nextGeneration
            CacheRequestToken(
                cacheEpoch = requestCacheEpoch,
                requestGeneration = nextGeneration
            )
        }
    }

    private suspend fun putCacheEntryIfLatest(
        key: String,
        requestToken: CacheRequestToken?,
        entry: BalanceCacheEntry
    ): Boolean {
        return mutex.withLock {
            if (
                requestToken == null ||
                cacheEpoch != requestToken.cacheEpoch ||
                latestRequestGenerationByKey[key] != requestToken.requestGeneration
            ) {
                return@withLock false
            }
            prefs.edit().putString(key, json.encodeToString(entry)).apply()
            true
        }
    }

    private suspend fun requireCurrentProviderIdentity(asset: Asset) {
        assetProviderIdentityVerifier.assertUnchanged(asset)
    }

    private data class CacheRequestToken(
        val cacheEpoch: Long,
        val requestGeneration: Long
    )

    private fun cacheKey(chainId: String, address: String, currency: String): String {
        val normalizedAddress = OnChainAddressIdentityV1.canonicalize(chainId, address)
        return "${chainId.lowercase()}:$normalizedAddress:${currency.uppercase()}"
    }

    private suspend fun fetchBalanceFromNetwork(chainId: String, currency: String, address: String): Double {
        return try {
            when (chainId.lowercase()) {
                "bitcoin" -> tatumApi.getBitcoinBalance(address).confirmedBalance
                "litecoin" -> tatumApi.getLitecoinBalance(address).confirmedBalance
                "bcash", "bitcoin-cash" -> tatumApi.getBitcoinCashBalance(address).confirmedBalance
                "dogecoin" -> tatumApi.getDogecoinBalance(address).confirmedBalance
                "solana" -> tatumApi.getSolanaBalance(address).solBalance
                "xrp" -> tatumApi.getXrpBalance(address).balanceInXrp
                "tron" -> tatumApi.getTronAccount(address).let { account ->
                    if (currency.equals("TRX", ignoreCase = true)) {
                        account.balanceTrx
                    } else {
                        account.getTokenBalance(currency)
                    }
                }
                "cardano" -> tatumApi.getCardanoAccount(address)
                    .filter { it.currency.symbol.equals(currency, ignoreCase = true) }
                    .sumOf { it.humanReadableBalance }
                in EvmAssetRouting.chainIds -> fetchEvmBalance(
                    chainId = chainId,
                    currencyOrContract = currency,
                    address = address
                )
                else -> throw IllegalArgumentException("Unsupported on-chain balance chain: $chainId")
            }
        } catch (e: HttpException) {
            throw e
        } catch (e: IOException) {
            throw e
        }
    }

    private fun validateCurrencyForChain(chainId: String, currency: String) {
        OnChainAssetRouteCatalog.requireAddressedRoute(
            chainId = chainId,
            currencyOrContract = currency
        )
    }

    private suspend fun fetchEvmBalance(
        chainId: String,
        currencyOrContract: String,
        address: String
    ): Double {
        val route = EvmAssetRouting.resolve(
            chainId = chainId,
            currencyOrContract = currencyOrContract
        )
        if (route.isNative) {
            return tatumApi.getNativeBalance(
                chain = route.tatumChain,
                address = address
            ).humanReadableBalance
        }

        repeat(MAX_PORTFOLIO_PAGES) { pageIndex ->
            if (pageIndex > 0) {
                rateLimiter.acquire()
            }
            val page = tatumApi.getWalletPortfolio(
                chain = route.tatumChain,
                addresses = address,
                tokenTypes = "fungible",
                pageSize = PORTFOLIO_PAGE_SIZE,
                offset = pageIndex * PORTFOLIO_PAGE_SIZE
            ).result
            val token = page.firstOrNull { item ->
                item.type.equals("fungible", ignoreCase = true) &&
                    route.tokenContracts.any { contract ->
                        item.tokenAddress.equals(contract, ignoreCase = true)
                    }
            }
            if (token != null) {
                return token.getHumanReadableBalance()
            }
            if (page.size < PORTFOLIO_PAGE_SIZE) {
                // Wallet portfolio omits zero-balance tokens. Exhausting the result without the
                // canonical contract is therefore a proven zero, not a provider failure.
                return 0.0
            }
        }

        throw IllegalStateException(
            "Token balance unavailable: wallet portfolio exceeded $MAX_PORTFOLIO_PAGES pages"
        )
    }

    private companion object {
        const val CACHE_NAMESPACE = "onchain_balance_cache_v3"
        const val PORTFOLIO_PAGE_SIZE = 50
        const val MAX_PORTFOLIO_PAGES = 20
    }
}
