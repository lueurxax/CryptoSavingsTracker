package com.xax.CryptoSavingsTracker.data.repository

import android.content.Context
import android.content.SharedPreferences
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.data.remote.api.TatumApi
import com.xax.CryptoSavingsTracker.data.remote.api.TatumTransactionDto
import com.xax.CryptoSavingsTracker.data.remote.api.TatumUTXOTransaction
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainTransactionRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.util.MonthLabelUtils
import com.xax.CryptoSavingsTracker.domain.util.TokenBucketRateLimiter
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton
import kotlin.math.abs
import kotlin.math.max

@Serializable
private data class TransactionsCacheEntry(
    val fetchedAtMillis: Long
)

@Singleton
class OnChainTransactionRepositoryImpl @Inject constructor(
    private val tatumApi: TatumApi,
    @Named("TatumRateLimiter") private val rateLimiter: TokenBucketRateLimiter,
    private val apiKeyStore: ApiKeyStore,
    private val transactionRepository: TransactionRepository,
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    @ApplicationContext private val context: Context
) : OnChainTransactionRepository {

    private val mutex = Mutex()
    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences("onchain_transaction_cache", Context.MODE_PRIVATE)
    }
    private val json = Json { ignoreUnknownKeys = true }
    private val cacheTtlMillis = 5 * 60 * 1000L

    override suspend fun refresh(asset: Asset, limit: Int, forceRefresh: Boolean): Result<Int> = runCatching {
        val address = asset.address?.trim().orEmpty()
        val chainId = asset.chainId?.trim().orEmpty()
        require(address.isNotEmpty() && chainId.isNotEmpty()) { "Asset has no on-chain configuration" }

        val cacheKey = cacheKey(chainId, address, asset.currency)
        val now = System.currentTimeMillis()
        val cached = getCacheEntry(cacheKey)
        if (!forceRefresh && cached != null && now - cached.fetchedAtMillis < cacheTtlMillis) {
            return@runCatching 0
        }

        // iOS parity: allow offline behavior when key missing (UI can still show already imported tx).
        if (apiKeyStore.getTatumApiKey().isBlank()) {
            return@runCatching 0
        }

        rateLimiter.acquire()

        val trackedAddress = address.lowercase()
        val fetched = fetchTransactions(chainId = chainId, address = address, currency = asset.currency, limit = limit)
        val mapped = fetched.mapNotNull {
            it.toOnChainTransaction(
                assetId = asset.id,
                trackedAddress = trackedAddress,
                assetCurrency = asset.currency
            )
        }

        // Upsert only new transactions (stable id = externalId).
        val newOnes = mutableListOf<Transaction>()
        for (tx in mapped) {
            val externalId = tx.externalId ?: continue
            val existing = transactionRepository.getTransactionByExternalId(externalId)
            if (existing == null) newOnes.add(tx)
        }

        if (newOnes.isNotEmpty()) {
            transactionRepository.insertTransactions(newOnes)
            applyDedicatedAutoAllocationIfNeeded(asset = asset, insertedTransactions = newOnes)
        }

        putCacheEntry(cacheKey, TransactionsCacheEntry(fetchedAtMillis = now))
        newOnes.size
    }

    private suspend fun fetchTransactions(chainId: String, address: String, currency: String, limit: Int): List<Any> {
        return when (chainId.lowercase()) {
            "bitcoin" -> tatumApi.getBitcoinTransactions(address = address, pageSize = limit)
            "litecoin" -> tatumApi.getLitecoinTransactions(address = address, pageSize = limit)
            "bcash", "bitcoin-cash" -> tatumApi.getBitcoinCashTransactions(address = address, pageSize = limit)
            "dogecoin" -> tatumApi.getDogecoinTransactions(address = address, pageSize = limit)
            else -> {
                val v4Chain = tatumV4Chain(chainId)
                runCatching {
                    tatumApi.getTransactionHistoryV4(chain = v4Chain, addresses = address, pageSize = limit).result
                }.getOrElse {
                    // Fallback for unsupported v4 chains.
                    tatumApi.getEvmTransactionsLegacy(address = address, chain = chainId.uppercase(), pageSize = limit)
                }
            }
        }
    }

    private fun Any.toOnChainTransaction(assetId: String, trackedAddress: String, assetCurrency: String): Transaction? {
        return when (this) {
            is TatumUTXOTransaction -> this.toTransaction(assetId = assetId, trackedAddress = trackedAddress)
            is TatumTransactionDto -> this.toTransaction(assetId = assetId, trackedAddress = trackedAddress, assetCurrency = assetCurrency)
            else -> null
        }
    }

    private fun TatumUTXOTransaction.toTransaction(assetId: String, trackedAddress: String): Transaction? {
        val epsilon = 1e-10
        var netAmount = 0.0
        var fromAddress: String? = null
        var toAddress: String? = null

        val addressLower = trackedAddress

        // Spending inputs.
        inputs.orEmpty().forEach { input ->
            val addresses = input.prevout?.scriptPubKey?.addresses.orEmpty().map { it.lowercase() }
            if (addresses.contains(addressLower)) {
                val value = input.prevout?.valueNumber ?: 0.0
                netAmount -= value / 100_000_000.0
                fromAddress = addressLower
            }
        }

        // Receiving outputs.
        outputs.orEmpty().forEach { output ->
            val outputAddress = output.address ?: output.scriptPubKey?.addresses?.firstOrNull()
            val outputLower = outputAddress?.lowercase()
            if (outputLower != null && outputLower == addressLower) {
                val amount = output.humanReadableValue
                netAmount += amount
                toAddress = addressLower
            } else if (toAddress == null && outputLower != null) {
                toAddress = outputLower
            }
        }

        if (abs(netAmount) <= epsilon) return null

        val signedAmount = netAmount
        val timestampMillis = (time ?: 0L) * 1000L
        val counterparty = if (signedAmount >= 0) (fromAddress ?: toAddress) else (toAddress ?: fromAddress)

        return Transaction(
            id = hash, // stable id for upsert
            assetId = assetId,
            amount = signedAmount,
            dateMillis = if (timestampMillis > 0) timestampMillis else System.currentTimeMillis(),
            source = TransactionSource.ON_CHAIN,
            externalId = hash,
            counterparty = counterparty,
            comment = "On-chain",
            createdAt = System.currentTimeMillis()
        )
    }

    private fun TatumTransactionDto.toTransaction(assetId: String, trackedAddress: String, assetCurrency: String): Transaction? {
        val epsilon = 1e-10
        val normalizedSymbol = assetCurrency.uppercase()

        val baseAmount = run {
            val nativeAmount = run {
                val amountValue = amount?.toDoubleOrNull()
                if (amountValue != null) abs(amountValue) else abs(value?.toDoubleOrNull()?.let { it / 1e18 } ?: 0.0)
            }

            if (tokenTransfers.isNullOrEmpty()) return@run nativeAmount

            val match = tokenTransfers.firstOrNull { (it.tokenSymbol ?: "").uppercase() == normalizedSymbol }
            val tokenAmount = abs(
                match?.value
                    ?.toDoubleOrNull()
                    ?.let { raw ->
                        val decimals = match.tokenDecimals ?: 18
                        raw / Math.pow(10.0, decimals.toDouble())
                    }
                    ?: 0.0
            )

            if (tokenAmount > 0.0) tokenAmount else nativeAmount
        }

        if (baseAmount <= epsilon) return null

        val subtype = transactionSubtype?.lowercase().orEmpty()
        val toLower = to?.lowercase()
        val fromLower = from?.lowercase()
        val signedAmount = when {
            subtype.contains("receive") -> baseAmount
            subtype.contains("sent") -> -baseAmount
            toLower != null && toLower == trackedAddress -> baseAmount
            fromLower != null && fromLower == trackedAddress -> -baseAmount
            else -> return null
        }

        val ts = timestamp ?: 0L
        val timestampMillis = if (ts > 1_000_000_000_000L) ts else ts * 1000L

        return Transaction(
            id = hash,
            assetId = assetId,
            amount = signedAmount,
            dateMillis = if (timestampMillis > 0) timestampMillis else System.currentTimeMillis(),
            source = TransactionSource.ON_CHAIN,
            externalId = hash,
            counterparty = counterAddress ?: from ?: to,
            comment = "On-chain",
            createdAt = System.currentTimeMillis()
        )
    }

    /**
     * iOS parity: if an asset is fully allocated to exactly one goal, new deposits should keep it fully allocated.
     * For partially allocated or shared assets, deposits remain unallocated.
     */
    private suspend fun applyDedicatedAutoAllocationIfNeeded(asset: Asset, insertedTransactions: List<Transaction>) {
        val epsilon = 1e-7
        val allocations = allocationRepository.getAllocationsForAsset(asset.id)
        if (allocations.size != 1) return
        val allocation = allocations.first()

        val deposits = insertedTransactions
            .filter { it.source == TransactionSource.ON_CHAIN && it.amount > epsilon }
            .sortedBy { it.dateMillis }
        if (deposits.isEmpty()) return

        val manual = transactionRepository.getManualBalanceForAsset(asset.id)
        val cachedOnChain = onChainBalanceRepository.getBalance(asset, forceRefresh = false).getOrNull()?.balance ?: 0.0
        val total = manual + cachedOnChain

        val unallocatedNow = max(0.0, total - allocation.amount)
        val depositsSum = deposits.sumOf { it.amount }
        val tolerance = max(epsilon, max(unallocatedNow, depositsSum) * 0.000001)
        if (abs(unallocatedNow - depositsSum) > tolerance) return

        var runningTarget = allocation.amount
        for (deposit in deposits) {
            runningTarget += deposit.amount
            val updatedAllocation = allocation.copy(
                amount = runningTarget,
                lastModifiedAt = System.currentTimeMillis()
            )
            allocationRepository.upsertAllocation(updatedAllocation)
            allocationHistoryRepository.insert(
                AllocationHistory(
                    id = UUID.randomUUID().toString(),
                    assetId = allocation.assetId,
                    goalId = allocation.goalId,
                    amount = runningTarget,
                    monthLabel = MonthLabelUtils.fromMillisUtc(deposit.dateMillis),
                    timestamp = deposit.dateMillis,
                    createdAt = System.currentTimeMillis()
                )
            )
        }
    }

    private fun tatumV4Chain(chainId: String): String {
        return when (chainId.lowercase()) {
            "ethereum" -> "ethereum"
            "polygon" -> "polygon"
            "bsc" -> "bsc"
            "arbitrum" -> "arbitrum"
            "optimism" -> "optimism"
            "base" -> "base"
            else -> chainId.lowercase()
        }
    }

    private fun cacheKey(chainId: String, address: String, currency: String): String {
        return "${chainId.lowercase()}:${address.lowercase()}:${currency.uppercase()}"
    }

    private suspend fun getCacheEntry(key: String): TransactionsCacheEntry? {
        return mutex.withLock {
            prefs.getString(key, null)?.let { runCatching { json.decodeFromString<TransactionsCacheEntry>(it) }.getOrNull() }
        }
    }

    private suspend fun putCacheEntry(key: String, entry: TransactionsCacheEntry) {
        mutex.withLock {
            prefs.edit().putString(key, json.encodeToString(entry)).apply()
        }
    }
}
