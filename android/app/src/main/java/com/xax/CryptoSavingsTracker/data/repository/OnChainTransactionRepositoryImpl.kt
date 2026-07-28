package com.xax.CryptoSavingsTracker.data.repository

import android.content.Context
import android.content.SharedPreferences
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.data.remote.api.TatumEvmJsonRpcReceiptResponse
import com.xax.CryptoSavingsTracker.data.remote.api.TatumEvmJsonRpcRequest
import com.xax.CryptoSavingsTracker.data.remote.api.TatumScriptPubKey
import com.xax.CryptoSavingsTracker.data.remote.api.TatumApi
import com.xax.CryptoSavingsTracker.data.remote.api.TatumTransactionDto
import com.xax.CryptoSavingsTracker.data.remote.api.TatumUTXOCoin
import com.xax.CryptoSavingsTracker.data.remote.api.TatumUTXOInput
import com.xax.CryptoSavingsTracker.data.remote.api.TatumUTXOPrevout
import com.xax.CryptoSavingsTracker.data.remote.api.TatumUTXOTransaction
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainAddressIdentityV1
import com.xax.CryptoSavingsTracker.domain.model.OnChainAssetRouteCatalog
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainTransactionRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.util.MonthLabelUtils
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompletenessResolver
import com.xax.CryptoSavingsTracker.domain.util.TokenBucketRateLimiter
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import java.math.BigInteger
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

@Serializable
private data class ProviderAbsenceEvidence(
    val rowFingerprints: List<String>
)

private data class RefreshCommitResult(
    val insertedCount: Int,
    val shouldPublishCache: Boolean,
    val pendingAbsence: ProviderAbsenceEvidence?
)

private data class NativeReceiptGas(
    val fee: Double,
    val isSuccessful: Boolean
)

private sealed interface TransactionFetchRoute

private enum class UtxoTransactionChain {
    BITCOIN,
    LITECOIN,
    BITCOIN_CASH,
    DOGECOIN
}

private data class UtxoTransactionRoute(
    val chain: UtxoTransactionChain
) : TransactionFetchRoute

private data class EvmTransactionRoute(
    val assetRoute: EvmAssetRoute
) : TransactionFetchRoute

private data class MappedOnChainTransaction(
    val transaction: Transaction,
    val legacyGroupKey: String,
    val legacyExternalIds: Set<String>,
    val utxoProviderIdentity: UtxoProviderIdentity?,
    val providerRecordKey: String?,
    val providerRecordBaseKey: String?,
    val providerTransactionIndex: Int?,
    val providerLogIndex: Int?
)

private data class ProviderTransactionCorrection(
    val previous: Transaction,
    val corrected: Transaction
)

private data class UtxoProviderIdentity(
    val assetId: String,
    val canonicalHash: String,
    val providerHashAliases: Set<String>,
    val hasDurableAliasMetadata: Boolean
) {
    val allProviderHashes: Set<String>
        get() = providerHashAliases + canonicalHash

    val externalId: String
        get() {
            check(
                assetId.isNotBlank() &&
                    !assetId.contains(UTXO_PROVIDER_RECORD_SEPARATOR) &&
                    canonicalHash.isNotBlank() &&
                    !canonicalHash.contains(UTXO_PROVIDER_RECORD_SEPARATOR) &&
                    providerHashAliases.none {
                        it.isBlank() || it.contains(UTXO_PROVIDER_RECORD_SEPARATOR)
                    }
            ) {
                "UTXO provider identity contains an invalid blank or separator"
            }
            if (providerHashAliases.isEmpty()) {
                return "utxo:$assetId:$canonicalHash"
            }
            val aliases = providerHashAliases.sorted()
            return buildList {
                add(UTXO_PROVIDER_RECORD_MARKER)
                add(assetId)
                add(canonicalHash)
                add(UTXO_PROVIDER_ALIAS_MARKER)
                add(aliases.size.toString())
                addAll(aliases)
            }.joinToString(UTXO_PROVIDER_RECORD_SEPARATOR)
        }

    fun reconciledWith(installed: UtxoProviderIdentity): UtxoProviderIdentity {
        check(assetId == installed.assetId) {
            "UTXO provider identity belongs to another asset"
        }
        check(allProviderHashes.intersect(installed.allProviderHashes).isNotEmpty()) {
            "UTXO provider identities do not share a durable hash"
        }
        check(
            allProviderHashes.contains(installed.canonicalHash) ||
                installed.allProviderHashes.contains(canonicalHash)
        ) {
            "UTXO transaction alias maps ambiguously to distinct canonical txids"
        }

        val reconciledCanonicalHash = when {
            installed.hasDurableAliasMetadata &&
                installed.allProviderHashes.contains(canonicalHash) &&
                !allProviderHashes.contains(installed.canonicalHash) ->
                installed.canonicalHash
            allProviderHashes.contains(installed.canonicalHash) &&
                !installed.allProviderHashes.contains(canonicalHash) ->
                canonicalHash
            installed.hasDurableAliasMetadata ->
                installed.canonicalHash
            else ->
                canonicalHash
        }
        return UtxoProviderIdentity(
            assetId = assetId,
            canonicalHash = reconciledCanonicalHash,
            providerHashAliases = allProviderHashes
                .union(installed.allProviderHashes)
                .minus(reconciledCanonicalHash),
            hasDurableAliasMetadata = allProviderHashes
                .union(installed.allProviderHashes)
                .minus(reconciledCanonicalHash)
                .isNotEmpty()
        )
    }
}

private data class InstalledProviderRecordIdentity(
    val strongKey: String,
    val baseKey: String,
    val transactionIndex: Int?,
    val logIndex: Int?
)

internal const val MAX_UTXO_PREVOUT_LOOKUPS = 100
private const val UTXO_PROVIDER_RECORD_MARKER = "utxo-record-v2"
private const val UTXO_PROVIDER_ALIAS_MARKER = "aliases-v1"
private const val UTXO_PROVIDER_RECORD_SEPARATOR = "|"

@Singleton
class OnChainTransactionRepositoryImpl @Inject constructor(
    private val tatumApi: TatumApi,
    @Named("TatumRateLimiter") private val rateLimiter: TokenBucketRateLimiter,
    private val apiKeyStore: ApiKeyStore,
    private val transactionRepository: TransactionRepository,
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    private val assetProviderIdentityVerifier: OnChainAssetProviderIdentityVerifier,
    private val transactionRunner: ExecutionTransitionTransactionRunner,
    @ApplicationContext private val context: Context
) : OnChainTransactionRepository {

    private val mutex = Mutex()
    private var nextRefreshSequence = 0L
    private val latestRefreshSequenceByCacheKey = mutableMapOf<String, Long>()
    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences("onchain_transaction_cache", Context.MODE_PRIVATE)
    }
    private val json = Json { ignoreUnknownKeys = true }
    private val cacheTtlMillis = 5 * 60 * 1000L

    override suspend fun refresh(asset: Asset, limit: Int, forceRefresh: Boolean): Result<Int> = runCatching {
        val address = asset.address?.trim().orEmpty()
        val rawChainId = asset.chainId?.trim().orEmpty()
        require(address.isNotEmpty() && rawChainId.isNotEmpty()) { "Asset has no on-chain configuration" }
        val chainId = OnChainAssetRouteCatalog.normalizeChainId(rawChainId)
        val route = transactionRoute(chainId = chainId, currency = asset.currency)

        val cacheKey = cacheKey(
            route = route,
            assetId = asset.id,
            chainId = chainId,
            address = address,
            currency = asset.currency
        )
        val now = System.currentTimeMillis()
        val cached = getCacheEntry(cacheKey)
        val hasFreshValidCache = cached != null &&
            cached.fetchedAtMillis in 1L..now &&
            now - cached.fetchedAtMillis < cacheTtlMillis
        if (!forceRefresh && hasFreshValidCache) {
            return@runCatching 0
        }

        // iOS parity: allow offline behavior when key missing (UI can still show already imported tx).
        if (apiKeyStore.getTatumApiKey().isBlank()) {
            return@runCatching 0
        }

        val refreshSequence = registerRefresh(cacheKey)
        rateLimiter.acquire()

        val trackedAddress = route.normalizeAddressForComparison(address)
        val fetched = fetchTransactions(route = route, address = address, limit = limit)
        val nativeGasChargeByProviderRecordKey = if (
            route is EvmTransactionRoute &&
            route.assetRoute.isNative
        ) {
            resolveNativeGasCharges(
                route = route.assetRoute,
                trackedAddress = trackedAddress,
                transactions = fetched.filterIsInstance<TatumTransactionDto>()
            )
        } else {
            emptyMap()
        }
        val rawMapped = fetched.mapNotNull {
            it.toOnChainTransaction(
                route = route,
                assetId = asset.id,
                trackedAddress = trackedAddress,
                nativeGasChargeByProviderRecordKey = nativeGasChargeByProviderRecordKey
            )
        }
        val mapped = reconcileSameBatchProviderEnrichment(rawMapped)

        val duplicateCanonicalIds = mapped
            .groupingBy { checkNotNull(it.transaction.externalId) }
            .eachCount()
            .filterValues { count -> count > 1 }
            .keys
        check(duplicateCanonicalIds.isEmpty()) {
            "Transaction history contains indistinguishable movements without stable event indices"
        }
        if (!isLatestRefresh(cacheKey, refreshSequence)) {
            return@runCatching 0
        }

        val hasPotentialDedicatedDeposit = mapped.any { mappedTransaction ->
            mappedTransaction.transaction.amount > AUTO_ALLOCATION_EPSILON
        }
        val preflightAllocations = if (hasPotentialDedicatedDeposit) {
            allocationRepository.getAllocationsForAsset(asset.id)
        } else {
            emptyList()
        }
        // Preserve refresh ordering across the suspending allocation read. Once an
        // older refresh crosses this fence first, OnChainBalanceRepository's own
        // per-key request generation prevents it from publishing after a newer call.
        if (!isLatestRefresh(cacheKey, refreshSequence)) {
            return@runCatching 0
        }
        val cachedOnChainBalance = if (preflightAllocations.size == 1) {
            AssetBalanceCompletenessResolver.resolveSnapshot(
                asset = asset,
                manualBalance = 0.0,
                providerBalance = onChainBalanceRepository
                    .getFreshBalanceForPreflight(asset)
                    .getOrNull()
            ).requireTotalBalance()
        } else {
            null
        }

        val commitResult = try {
            transactionRunner.run commit@ {
                if (!isLatestRefresh(cacheKey, refreshSequence)) {
                    return@commit RefreshCommitResult(
                        insertedCount = 0,
                        shouldPublishCache = false,
                        pendingAbsence = null
                    )
                }
                // Re-read every identity inside the same Room transaction that performs all writes.
            assetProviderIdentityVerifier.assertUnchanged(asset)
            val installedOnChainRows = transactionRepository
                .getTransactionsByAssetIdOnce(asset.id)
                .filter { it.source == TransactionSource.ON_CHAIN }
            val installedProviderRows = installedOnChainRows
                .asSequence()
                .mapNotNull { row ->
                    providerRecordIdentityFromInstalledExternalId(row.externalId)?.let { identity ->
                        Triple(identity.strongKey, identity, row)
                    }
                }
                .toList()
            val installedRowsByProviderRecordKey = installedProviderRows.groupBy(
                keySelector = { it.first },
                valueTransform = { it.third }
            )
            check(installedRowsByProviderRecordKey.values.none { it.size > 1 }) {
                "Installed provider transaction identity is ambiguous"
            }
            val installedRowsByProviderBaseKey = installedProviderRows.groupBy(
                keySelector = { it.second.baseKey }
            )
            val mappedByProviderBaseKey = mapped
                .filter { it.providerRecordBaseKey != null }
                .groupBy { checkNotNull(it.providerRecordBaseKey) }

            fun installedProviderCandidates(
                mappedTransaction: MappedOnChainTransaction
            ): List<Transaction> {
                val strongKey = mappedTransaction.providerRecordKey ?: return emptyList()
                val exactStrongRows = installedRowsByProviderRecordKey[strongKey].orEmpty()
                if (exactStrongRows.isNotEmpty()) return exactStrongRows

                val baseKey = mappedTransaction.providerRecordBaseKey ?: return emptyList()
                val baseRows = installedRowsByProviderBaseKey[baseKey].orEmpty()
                val compatibleRows = baseRows.filter { installed ->
                    installed.second.indicesAreCompatibleWith(mappedTransaction)
                }
                if (compatibleRows.isEmpty()) return emptyList()

                val enrichmentRows = compatibleRows.filter { installed ->
                    installed.second.canBeEnrichedBy(mappedTransaction)
                }
                check(enrichmentRows.size == compatibleRows.size) {
                    "Provider event indices disappeared and cannot be reconciled safely"
                }
                val compatibleMappedRows = mappedByProviderBaseKey[baseKey]
                    .orEmpty()
                    .filter { candidate ->
                        enrichmentRows.any { installed ->
                            installed.second.indicesAreCompatibleWith(candidate)
                        }
                    }
                check(
                    enrichmentRows.size == 1 &&
                        compatibleMappedRows.size == 1
                ) {
                    "Provider event-index enrichment maps ambiguously"
                }
                return listOf(enrichmentRows.single().third)
            }

            val installedUtxoRows = if (route is UtxoTransactionRoute) {
                installedOnChainRows.mapNotNull { row ->
                    installedUtxoIdentityFromExternalId(
                        externalId = row.externalId,
                        assetId = asset.id
                    )?.let { identity -> identity to row }
                }
            } else {
                emptyList()
            }

            val newOnes = mutableListOf<Transaction>()
            val rowsToUpdate = mutableListOf<Transaction>()
            val providerCorrections = mutableListOf<ProviderTransactionCorrection>()
            val canonicalRowsToDelete = linkedSetOf<String>()
            val matchedInstalledRowIds = linkedSetOf<String>()

            fun recordRowUpdate(previous: Transaction, corrected: Transaction) {
                rowsToUpdate += corrected
                if (
                    previous.amount != corrected.amount ||
                    previous.dateMillis != corrected.dateMillis
                ) {
                    providerCorrections += ProviderTransactionCorrection(
                        previous = previous,
                        corrected = corrected
                    )
                }
            }

            for ((_, sameHashMovements) in mapped.groupBy { it.legacyGroupKey }) {
                val canonicalRowsByExternalId = sameHashMovements.associate { mappedTransaction ->
                    val externalId = checkNotNull(mappedTransaction.transaction.externalId)
                    externalId to transactionRepository.getTransactionsByExternalId(externalId)
                }
                canonicalRowsByExternalId.forEach { (_, rows) ->
                    check(rows.size <= 1) {
                        "Canonical transaction identity is duplicated"
                    }
                }
                val legacyExternalIds = sameHashMovements
                    .flatMapTo(linkedSetOf()) { it.legacyExternalIds }

                val utxoMovement = sameHashMovements.singleOrNull()
                    ?.takeIf { it.utxoProviderIdentity != null }
                if (utxoMovement != null) {
                    check(route is UtxoTransactionRoute) {
                        "UTXO provider identity was mapped through a non-UTXO route"
                    }
                    val incomingIdentity = checkNotNull(utxoMovement.utxoProviderIdentity)
                    val canonical = utxoMovement.transaction
                    val canonicalExternalId = checkNotNull(canonical.externalId)
                    val directlyQueriedRows = (legacyExternalIds + canonicalExternalId)
                        .flatMap { externalId ->
                            transactionRepository.getTransactionsByExternalId(externalId)
                        }
                    val installedAliasRows = installedUtxoRows
                        .filter { (identity, _) ->
                            identity.allProviderHashes
                                .intersect(incomingIdentity.allProviderHashes)
                                .isNotEmpty()
                        }
                        .map { it.second }
                    val matchingRows = (directlyQueriedRows + installedAliasRows)
                        .filter { candidate ->
                            candidate.source == TransactionSource.ON_CHAIN &&
                                candidate.assetId == asset.id
                        }
                        .distinctBy { it.id }
                        .filter { candidate ->
                            val installedIdentity = installedUtxoIdentityFromExternalId(
                                externalId = candidate.externalId,
                                assetId = asset.id
                            )
                            installedIdentity != null &&
                                installedIdentity.allProviderHashes
                                    .intersect(incomingIdentity.allProviderHashes)
                                    .isNotEmpty()
                        }
                    matchedInstalledRowIds += matchingRows.map { it.id }
                    check(matchingRows.size <= 2) {
                        "UTXO transaction alias maps ambiguously to installed rows"
                    }
                    check(
                        matchingRows
                            .mapNotNull { candidate ->
                                installedUtxoIdentityFromExternalId(
                                    externalId = candidate.externalId,
                                    assetId = asset.id
                                )?.canonicalHash
                            }
                            .distinct()
                            .size == matchingRows.size
                    ) {
                        "UTXO transaction alias maps ambiguously to duplicate installed rows"
                    }

                    var reconciledIdentity = incomingIdentity
                    matchingRows.forEach { installed ->
                        val installedIdentity = checkNotNull(
                            installedUtxoIdentityFromExternalId(
                                externalId = installed.externalId,
                                assetId = asset.id
                            )
                        )
                        reconciledIdentity = reconciledIdentity.reconciledWith(installedIdentity)
                    }

                    val survivor = when (matchingRows.size) {
                        0 -> null
                        1 -> matchingRows.single()
                        else -> {
                            val exactCanonicalRows = matchingRows.filter { candidate ->
                                installedUtxoIdentityFromExternalId(
                                    externalId = candidate.externalId,
                                    assetId = asset.id
                                )?.canonicalHash == incomingIdentity.canonicalHash
                            }
                            check(exactCanonicalRows.size <= 1) {
                                "UTXO canonical transaction identity is duplicated"
                            }
                            val retained = exactCanonicalRows.singleOrNull()
                                ?: matchingRows.minWith(
                                    compareBy<Transaction> { it.createdAt }.thenBy { it.id }
                                )
                            val removed = matchingRows.single { it.id != retained.id }
                            assertUtxoMetadataCanMerge(
                                retained = retained,
                                removed = removed,
                                route = route
                            )
                            canonicalRowsToDelete += removed.id
                            retained.copy(
                                comment = retained.preferredCommentWith(removed, canonical),
                                counterparty = retained.preferredCounterpartyWith(removed, canonical)
                            )
                        }
                    }

                    if (survivor == null) {
                        newOnes += canonical.copy(
                            id = reconciledIdentity.externalId,
                            externalId = reconciledIdentity.externalId
                        )
                    } else {
                        val corrected = survivor.copy(
                            amount = canonical.amount,
                            dateMillis = canonical.dateMillis,
                            externalId = reconciledIdentity.externalId,
                            counterparty = survivor.counterparty
                                ?.takeIf { it.isNotBlank() }
                                ?: canonical.counterparty,
                            comment = survivor.comment
                                ?.takeIf { it.isNotBlank() }
                                ?: canonical.comment
                        )
                        if (corrected != survivor || matchingRows.size == 2) {
                            recordRowUpdate(previous = survivor, corrected = corrected)
                        }
                    }
                    continue
                }

                val exactLegacyRows = legacyExternalIds.flatMap { legacyExternalId ->
                    transactionRepository.getTransactionsByExternalId(legacyExternalId)
                }
                val normalizedInstalledLegacyRows = installedOnChainRows.filter { candidate ->
                    candidate.externalId?.let { installedExternalId ->
                        legacyExternalIds.any { legacyExternalId ->
                            installedExternalId.equals(legacyExternalId, ignoreCase = true)
                        }
                    } == true
                }
                val currentAssetLegacyRows = (exactLegacyRows + normalizedInstalledLegacyRows)
                    .filter { candidate ->
                        candidate.source == TransactionSource.ON_CHAIN &&
                            candidate.externalId?.let { installedExternalId ->
                                legacyExternalIds.any { legacyExternalId ->
                                    installedExternalId.equals(
                                        legacyExternalId,
                                        ignoreCase = true
                                    )
                                }
                            } == true &&
                            candidate.assetId == asset.id
                    }
                    .distinctBy { it.id }

                if (currentAssetLegacyRows.isNotEmpty()) {
                    check(currentAssetLegacyRows.size == 1 && sameHashMovements.size == 1) {
                        "Legacy transaction identity maps ambiguously to canonical movements"
                    }
                    val legacy = currentAssetLegacyRows.single()
                    val canonical = sameHashMovements.single().transaction
                    val canonicalExternalId = checkNotNull(canonical.externalId)
                    check(canonicalExternalId != legacy.externalId) {
                        "Canonical transaction identity must differ from its legacy hash"
                    }
                    val providerRows = installedProviderCandidates(sameHashMovements.single())
                    val canonicalCandidates = (
                        canonicalRowsByExternalId.getValue(canonicalExternalId) +
                            providerRows
                        )
                        .distinctBy { it.id }
                    check(canonicalCandidates.size <= 1) {
                        "Legacy transaction identity maps ambiguously to installed provider rows"
                    }
                    val existingCanonical = canonicalCandidates.singleOrNull()
                    if (existingCanonical != null) {
                        check(
                            existingCanonical.assetId == asset.id &&
                                existingCanonical.source == TransactionSource.ON_CHAIN
                        ) {
                            "Canonical transaction identity belongs to another movement"
                        }
                        check(existingCanonical.id != legacy.id) {
                            "Legacy and canonical identities unexpectedly share one row"
                        }
                        matchedInstalledRowIds += existingCanonical.id
                        canonicalRowsToDelete += existingCanonical.id
                    }
                    matchedInstalledRowIds += legacy.id
                    val corrected = legacy.copy(
                        amount = canonical.amount,
                        dateMillis = canonical.dateMillis,
                        externalId = canonicalExternalId,
                        counterparty = legacy.counterparty
                            ?.takeIf { it.isNotBlank() }
                            ?: canonical.counterparty
                    )
                    recordRowUpdate(previous = legacy, corrected = corrected)
                } else {
                    sameHashMovements.forEach { mappedTransaction ->
                        val canonical = mappedTransaction.transaction
                        val canonicalExternalId = checkNotNull(canonical.externalId)
                        val providerRows = installedProviderCandidates(mappedTransaction)
                        val canonicalCandidates = (
                            canonicalRowsByExternalId.getValue(canonicalExternalId) +
                                providerRows
                            )
                            .distinctBy { it.id }
                        check(canonicalCandidates.size <= 1) {
                            "Provider transaction identity maps ambiguously to installed rows"
                        }
                        val existingCanonical = canonicalCandidates.singleOrNull()
                        if (existingCanonical == null) {
                            newOnes += canonical
                        } else {
                            check(
                                existingCanonical.assetId == asset.id &&
                                    existingCanonical.source == TransactionSource.ON_CHAIN
                            ) {
                                "Canonical transaction identity belongs to another movement"
                            }
                            matchedInstalledRowIds += existingCanonical.id
                            val corrected = existingCanonical.copy(
                                amount = canonical.amount,
                                dateMillis = canonical.dateMillis,
                                externalId = canonicalExternalId,
                                counterparty = canonical.counterparty
                            )
                            if (corrected != existingCanonical) {
                                recordRowUpdate(
                                    previous = existingCanonical,
                                    corrected = corrected
                                )
                            }
                        }
                    }
                }
            }

            val missingCanonicalRows = installedOnChainRows
                .filter { installed ->
                    installed.isCanonicalProviderRowFor(
                        route = route,
                        assetId = asset.id,
                        trackedAddress = trackedAddress
                    ) &&
                        installed.id !in matchedInstalledRowIds &&
                        installed.id !in canonicalRowsToDelete
                }
            val absenceEvidence = missingCanonicalRows
                .takeIf { it.isNotEmpty() }
                ?.toProviderAbsenceEvidence()
            val isConfirmedAbsence = absenceEvidence != null &&
                getPendingProviderAbsence(cacheKey) == absenceEvidence
            if (isConfirmedAbsence) {
                missingCanonicalRows.forEach { missing ->
                    canonicalRowsToDelete += missing.id
                    providerCorrections += ProviderTransactionCorrection(
                        previous = missing,
                        corrected = missing.copy(amount = 0.0)
                    )
                }
            }

            canonicalRowsToDelete.forEach { transactionRepository.deleteTransaction(it) }
            rowsToUpdate.forEach { transactionRepository.updateTransaction(it) }
            reconcileDedicatedAutoAllocationCorrectionsIfNeeded(
                asset = asset,
                corrections = providerCorrections,
                cachedOnChainBalance = cachedOnChainBalance
            )
            if (newOnes.isNotEmpty()) {
                transactionRepository.insertTransactions(newOnes)
                applyDedicatedAutoAllocationIfNeeded(
                    asset = asset,
                    insertedTransactions = newOnes,
                    cachedOnChainBalance = cachedOnChainBalance
                )
            }
            RefreshCommitResult(
                insertedCount = newOnes.size,
                shouldPublishCache = absenceEvidence == null || isConfirmedAbsence,
                pendingAbsence = absenceEvidence.takeUnless { isConfirmedAbsence }
            )
            }
        } catch (error: Throwable) {
            removeCacheEntryIfLatest(cacheKey, refreshSequence)
            throw error
        }
        publishRefreshStateIfLatest(
            key = cacheKey,
            refreshSequence = refreshSequence,
            entry = TransactionsCacheEntry(fetchedAtMillis = now),
            commitResult = commitResult
        )
        commitResult.insertedCount
    }

    private suspend fun fetchTransactions(
        route: TransactionFetchRoute,
        address: String,
        limit: Int
    ): List<Any> {
        return when (route) {
            is UtxoTransactionRoute -> {
                val pageSize = limit.coerceIn(1, MAX_UTXO_PAGE_SIZE)
                val transactions = mutableListOf<TatumUTXOTransaction>()
                for (pageIndex in 0 until MAX_UTXO_HISTORY_PAGES) {
                    if (pageIndex > 0) {
                        rateLimiter.acquire()
                    }
                    val offset = pageIndex * pageSize
                    val page = when (route.chain) {
                        UtxoTransactionChain.BITCOIN ->
                            tatumApi.getBitcoinTransactions(
                                address = address,
                                pageSize = pageSize,
                                offset = offset
                            )
                        UtxoTransactionChain.LITECOIN ->
                            tatumApi.getLitecoinTransactions(
                                address = address,
                                pageSize = pageSize,
                                offset = offset
                            )
                        UtxoTransactionChain.BITCOIN_CASH ->
                            tatumApi.getBitcoinCashTransactions(
                                address = address,
                                pageSize = pageSize,
                                offset = offset
                            )
                        UtxoTransactionChain.DOGECOIN ->
                            tatumApi.getDogecoinTransactions(
                                address = address,
                                pageSize = pageSize,
                                offset = offset
                            )
                    }
                    transactions += page
                    if (page.size < pageSize) {
                        break
                    }
                    check(pageIndex < MAX_UTXO_HISTORY_PAGES - 1) {
                        "Transaction history unavailable: exceeded $MAX_UTXO_HISTORY_PAGES pages"
                    }
                }
                resolveUtxoInputs(
                    route = route,
                    transactions = deduplicateUtxoPageOverlap(transactions)
                )
            }
            is EvmTransactionRoute -> {
                val assetRoute = route.assetRoute
                val pageSize = limit.coerceIn(1, MAX_EVM_PAGE_SIZE)
                val contracts: List<String?> = if (assetRoute.isNative) {
                    listOf(null)
                } else {
                    assetRoute.tokenContracts.sorted()
                }
                val transactions = mutableListOf<TatumTransactionDto>()
                var hasMadeEvmRequest = false
                for (tokenContract in contracts) {
                    for (pageIndex in 0 until MAX_EVM_HISTORY_PAGES) {
                        if (hasMadeEvmRequest) {
                            rateLimiter.acquire()
                        }
                        hasMadeEvmRequest = true
                        val page = tatumApi.getTransactionHistoryV4(
                            chain = assetRoute.tatumChain,
                            addresses = address,
                            transactionTypes = assetRoute.transactionType,
                            tokenAddress = tokenContract,
                            sort = "ASC",
                            pageSize = pageSize,
                            offset = pageIndex * pageSize
                        ).result
                        transactions += page
                        if (page.size < pageSize) {
                            break
                        }
                        check(pageIndex < MAX_EVM_HISTORY_PAGES - 1) {
                            "Transaction history unavailable: exceeded $MAX_EVM_HISTORY_PAGES pages"
                        }
                    }
                }
                transactions.sortedByDescending { it.timestamp ?: 0L }
            }
        }
    }

    private fun deduplicateUtxoPageOverlap(
        transactions: List<TatumUTXOTransaction>
    ): List<TatumUTXOTransaction> {
        val identityComponents = mutableListOf<MutableList<TatumUTXOTransaction>>()
        transactions.forEach { transaction ->
            val providerHashes = transaction.normalizedProviderHashes
            check(providerHashes.isNotEmpty()) {
                "UTXO transaction history contains a transaction without a hash"
            }

            val matchingComponentIndexes = identityComponents.indices.filter { index ->
                identityComponents[index].any { existing ->
                    existing.normalizedProviderHashes.intersect(providerHashes).isNotEmpty()
                }
            }
            if (matchingComponentIndexes.isEmpty()) {
                identityComponents += mutableListOf(transaction)
            } else {
                val retainedIndex = matchingComponentIndexes.first()
                identityComponents[retainedIndex] += transaction
                matchingComponentIndexes.drop(1).asReversed().forEach { mergedIndex ->
                    identityComponents[retainedIndex] += identityComponents.removeAt(mergedIndex)
                }
            }
        }

        return identityComponents.map { sameIdentityTransactions ->
            val explicitCanonicalTxids = sameIdentityTransactions
                .mapNotNull { transaction ->
                    transaction.txid
                        ?.trim()
                        ?.takeIf { it.isNotEmpty() }
                        ?.lowercase()
                }
                .distinct()
            check(explicitCanonicalTxids.size <= 1) {
                "UTXO transaction alias maps to multiple canonical txids"
            }

            val retained = explicitCanonicalTxids.singleOrNull()?.let { canonicalTxid ->
                sameIdentityTransactions.first {
                    it.txid?.trim()?.equals(canonicalTxid, ignoreCase = true) == true
                }
            } ?: sameIdentityTransactions.first()
            check(
                sameIdentityTransactions.all { candidate ->
                    candidate.sameMovementIgnoringProviderHashes(retained)
                }
            ) {
                "UTXO transaction ${retained.resolvedHash} changed between pages"
            }
            retained
        }
    }

    private val TatumUTXOTransaction.normalizedProviderHashes: Set<String>
        get() = legacyHashAliases
            .mapTo(linkedSetOf()) { it.trim().lowercase() }
            .filterTo(linkedSetOf()) { it.isNotEmpty() }

    private fun TatumUTXOTransaction.sameMovementIgnoringProviderHashes(
        other: TatumUTXOTransaction
    ): Boolean {
        return copy(hash = "", txid = null) == other.copy(hash = "", txid = null)
    }

    private fun reconcileSameBatchProviderEnrichment(
        mapped: List<MappedOnChainTransaction>
    ): List<MappedOnChainTransaction> {
        val providerRows = mapped.filter { it.providerRecordBaseKey != null }
        val retainedProviderRows = providerRows
            .groupBy { checkNotNull(it.providerRecordBaseKey) }
            .flatMap { (_, sameBaseRows) ->
                val retained = sameBaseRows.filterIndexed { index, candidate ->
                    val strictEnrichments = sameBaseRows
                        .filterIndexed { otherIndex, other ->
                            otherIndex != index && other.strictlyEnriches(candidate)
                        }
                    val maximalEnrichments = strictEnrichments.filter { possibleMaximum ->
                        strictEnrichments.none { other ->
                            other !== possibleMaximum &&
                                other.strictlyEnriches(possibleMaximum)
                        }
                    }
                    check(maximalEnrichments.size <= 1) {
                        "Provider same-batch event-index enrichment maps ambiguously"
                    }
                    maximalEnrichments.isEmpty()
                }

                retained.forEachIndexed { index, candidate ->
                    retained.drop(index + 1).forEach { other ->
                        check(
                            !candidate.indicesAreCompatibleWith(other) ||
                                candidate.providerRecordKey == other.providerRecordKey
                        ) {
                            "Provider same-batch event-index enrichment maps ambiguously"
                        }
                    }
                }
                retained
            }
        return mapped.filter { it.providerRecordBaseKey == null } + retainedProviderRows
    }

    private suspend fun resolveUtxoInputs(
        route: UtxoTransactionRoute,
        transactions: List<TatumUTXOTransaction>
    ): List<TatumUTXOTransaction> {
        val previousTransactionsByHash = linkedMapOf<String, TatumUTXOTransaction>()

        return transactions.map { transaction ->
            val inputs = transaction.resolvedInputs
            check(inputs.isNotEmpty()) {
                "Cannot prove UTXO net amount for ${transaction.resolvedHash}: missing inputs"
            }
            val enrichedInputs = inputs.map { input ->
                if (input.isCoinbaseInput() || input.hasExactValueAndAddress()) {
                    input
                } else {
                    val previousHash = (input.txid ?: input.prevout?.hash)
                        ?.takeIf { it.isNotBlank() }
                        ?: error(
                            "Cannot prove UTXO net amount for ${transaction.resolvedHash}: " +
                                "input has no previous transaction hash"
                        )
                    val previousOutputIndex = input.vout ?: input.prevout?.index
                        ?: error(
                            "Cannot prove UTXO net amount for ${transaction.resolvedHash}: " +
                                "input has no previous output index"
                        )
                    val normalizedPreviousHash = previousHash.lowercase()
                    val previousTransaction = previousTransactionsByHash[normalizedPreviousHash]
                        ?: run {
                            check(previousTransactionsByHash.size < MAX_UTXO_PREVOUT_LOOKUPS) {
                                "UTXO prevout lookup limit of $MAX_UTXO_PREVOUT_LOOKUPS exceeded"
                            }
                            rateLimiter.acquire()
                            val fetched = tatumApi.getBlockchainTransaction(
                                chain = route.chain.tatumChainId,
                                hash = previousHash
                            )
                            check(fetched.resolvedHash.equals(previousHash, ignoreCase = true)) {
                                "Previous transaction lookup returned a mismatched hash"
                            }
                            previousTransactionsByHash[normalizedPreviousHash] = fetched
                            fetched
                        }
                    val previousOutput = previousTransaction.outputAt(previousOutputIndex)
                        ?: error(
                            "Previous transaction $previousHash has no output at index " +
                                previousOutputIndex
                        )
                    val previousValue = previousOutput.valueNumber
                        ?.takeIf { it.isFinite() && it >= 0.0 }
                        ?: error(
                            "Previous transaction $previousHash output $previousOutputIndex " +
                                "has no valid value"
                        )
                    val previousAddresses = previousOutput.allAddresses()
                    check(previousAddresses.isNotEmpty()) {
                        "Previous transaction $previousHash output $previousOutputIndex has no address"
                    }
                    val mapperValue = previousValue.toMapperInputUnits(
                        chain = route.chain,
                        parentUsesRawOutputs = previousTransaction.vout != null
                    )
                    input.copy(
                        coin = TatumUTXOCoin(
                            valueNumber = mapperValue,
                            address = previousAddresses.first()
                        ),
                        prevout = TatumUTXOPrevout(
                            valueNumber = mapperValue,
                            scriptPubKey = TatumScriptPubKey(addresses = previousAddresses),
                            hash = previousHash,
                            index = previousOutputIndex
                        )
                    )
                }
            }
            transaction.copy(inputs = enrichedInputs)
        }
    }

    private fun TatumUTXOInput.isCoinbaseInput(): Boolean =
        !coinbase.isNullOrBlank() || coin?.coinbase == true

    private fun TatumUTXOInput.hasExactValueAndAddress(): Boolean {
        val value = coin?.valueNumber ?: prevout?.valueNumber
        return value != null && value.isFinite() && value >= 0.0 && allAddresses().isNotEmpty()
    }

    private fun TatumUTXOInput.allAddresses(): List<String> = buildList {
        address?.let(::add)
        coin?.address?.let(::add)
        prevout?.scriptPubKey?.address?.let(::add)
        addAll(prevout?.scriptPubKey?.addresses.orEmpty())
    }.filter { it.isNotBlank() }.distinct()

    private fun com.xax.CryptoSavingsTracker.data.remote.api.TatumUTXOOutput.allAddresses(): List<String> =
        buildList {
            address?.let(::add)
            scriptPubKey?.address?.let(::add)
            addAll(scriptPubKey?.addresses.orEmpty())
        }.filter { it.isNotBlank() }.distinct()

    private fun TatumUTXOTransaction.outputAt(index: Int) =
        if (vout != null) {
            vout.singleOrNull { output -> (output.n ?: output.index) == index }
        } else {
            val normalizedOutputs = outputs.orEmpty()
            val explicitlyIndexed = normalizedOutputs.filter { output ->
                (output.n ?: output.index) == index
            }
            when {
                explicitlyIndexed.size == 1 -> explicitlyIndexed.single()
                explicitlyIndexed.size > 1 -> null
                else -> normalizedOutputs.getOrNull(index)
            }
        }

    private fun Double.toMapperInputUnits(
        chain: UtxoTransactionChain,
        parentUsesRawOutputs: Boolean
    ): Double {
        if (parentUsesRawOutputs) return this
        return when (chain) {
            UtxoTransactionChain.BITCOIN -> this
            UtxoTransactionChain.LITECOIN,
            UtxoTransactionChain.BITCOIN_CASH,
            UtxoTransactionChain.DOGECOIN -> this / SATOSHIS_PER_BITCOIN
        }
    }

    private val UtxoTransactionChain.tatumChainId: String
        get() = when (this) {
            UtxoTransactionChain.BITCOIN -> "bitcoin-mainnet"
            UtxoTransactionChain.LITECOIN -> "litecoin-mainnet"
            UtxoTransactionChain.BITCOIN_CASH -> "bch-mainnet"
            UtxoTransactionChain.DOGECOIN -> "doge-mainnet"
        }

    private fun requireProviderTimestampMillis(
        rawTimestamp: Long?,
        recordDescription: String
    ): Long {
        check(rawTimestamp != null && rawTimestamp > 0L) {
            "$recordDescription requires a positive authoritative timestamp"
        }
        val timestampMillis = if (rawTimestamp > PROVIDER_MILLIS_TIMESTAMP_THRESHOLD) {
            rawTimestamp
        } else {
            try {
                Math.multiplyExact(rawTimestamp, MILLIS_PER_SECOND)
            } catch (error: ArithmeticException) {
                throw IllegalStateException(
                    "$recordDescription timestamp overflows milliseconds",
                    error
                )
            }
        }
        check(timestampMillis in 1L..MAX_SUPPORTED_PROVIDER_TIMESTAMP_MILLIS) {
            "$recordDescription timestamp is outside the supported range"
        }
        check(timestampMillis <= System.currentTimeMillis()) {
            "$recordDescription timestamp is in the future"
        }
        return timestampMillis
    }

    private suspend fun resolveNativeGasCharges(
        route: EvmAssetRoute,
        trackedAddress: String,
        transactions: List<TatumTransactionDto>
    ): Map<String, Double> {
        val routedMovementsByHash = linkedMapOf<String, MutableList<TatumTransactionDto>>()
        transactions
            .asSequence()
            .filter { transaction -> transaction.matchesRoute(route, trackedAddress) }
            .forEach { transaction ->
                val amount = transaction.amount
                    ?.trim()
                    ?.toDoubleOrNull()
                check(amount != null && amount.isFinite()) {
                    "Routed EVM transaction requires a finite signed amount"
                }
                val subtype = transaction.normalizedEvmSubtype()
                when (subtype) {
                    "incoming" -> check(amount > 0.0) {
                        "EVM incoming transaction requires a positive provider amount"
                    }
                    "outgoing" -> check(amount < 0.0) {
                        "EVM outgoing transaction requires a negative provider amount"
                    }
                    "zero-transfer" -> check(amount == 0.0) {
                        "EVM zero-transfer transaction requires a zero provider amount"
                    }
                    else -> error(
                        "Routed EVM transaction requires an incoming, outgoing, or " +
                            "zero-transfer subtype"
                    )
                }
                val canonicalHash = transaction.hash.trim()
                check(canonicalHash.isNotEmpty()) {
                    "EVM transaction requires a non-blank provider hash"
                }
                check(
                    (transaction.transactionIndex == null || transaction.transactionIndex >= 0) &&
                        (transaction.logIndex == null || transaction.logIndex >= 0)
                ) {
                    "Provider event indices must be non-negative"
                }
                routedMovementsByHash
                    .getOrPut(canonicalHash.lowercase()) { mutableListOf() }
                    .add(transaction)
            }

        val chargeByProviderRecordKey = linkedMapOf<String, Double>()
        routedMovementsByHash.forEach { (normalizedHash, duplicateRows) ->
            val allRows = duplicateRows.distinctBy { row -> row.stableProviderRecordKey() }
            val senderRows = allRows.filter { row ->
                row.normalizedEvmSubtype() != "incoming"
            }
            if (senderRows.isEmpty()) {
                return@forEach
            }
            senderRows.forEach { row ->
                chargeByProviderRecordKey[row.stableProviderRecordKey()] = 0.0
            }

            val zeroTransfers = senderRows.filter {
                it.normalizedEvmSubtype() == "zero-transfer"
            }
            check(zeroTransfers.size <= 1) {
                "Native sender gas attribution is ambiguous for transaction hash $normalizedHash"
            }
            val chargeTarget = zeroTransfers.singleOrNull() ?: senderRows
                .filter { it.normalizedEvmSubtype() == "outgoing" }
                .singleOrNull()
            check(chargeTarget != null) {
                "Native sender gas attribution is ambiguous for transaction hash $normalizedHash"
            }

            rateLimiter.acquire()
            val detail = tatumApi.getEvmTransactionReceipt(
                chain = route.tatumChain,
                request = TatumEvmJsonRpcRequest(
                    params = listOf(chargeTarget.hash.trim())
                )
            )
            val receiptGas = detail.requireNativeGasFee(
                requestedHash = normalizedHash,
                trackedAddress = trackedAddress
            )
            if (!receiptGas.isSuccessful) {
                check(
                    allRows.all { row ->
                        row.normalizedEvmSubtype() == "zero-transfer" &&
                            row.amount?.trim()?.toDoubleOrNull() == 0.0
                    }
                ) {
                    "Failed EVM receipt contradicts a nonzero routed movement"
                }
            }
            chargeByProviderRecordKey[chargeTarget.stableProviderRecordKey()] = receiptGas.fee
        }
        return chargeByProviderRecordKey
    }

    private fun TatumTransactionDto.normalizedEvmSubtype(): String {
        return transactionSubtype
            ?.trim()
            ?.lowercase()
            ?.replace('_', '-')
            .orEmpty()
    }

    private fun TatumEvmJsonRpcReceiptResponse.requireNativeGasFee(
        requestedHash: String,
        trackedAddress: String
    ): NativeReceiptGas {
        check(error == null) {
            "EVM transaction receipt RPC returned an error: ${error?.message.orEmpty()}"
        }
        check(jsonrpc == "2.0" && id == 1) {
            "EVM transaction receipt returned an invalid JSON-RPC envelope"
        }
        val receipt = checkNotNull(result) {
            "EVM transaction receipt result is unavailable"
        }
        val authoritativeHash = requireNonBlankReceiptText(
            field = "hash",
            value = receipt.transactionHash
        )
        check(authoritativeHash == requestedHash.lowercase()) {
            "EVM transaction detail returned a mismatched hash"
        }

        val authoritativeSender = requireNonBlankReceiptText(
            field = "sender",
            value = receipt.from
        )
        check(authoritativeSender == trackedAddress.lowercase()) {
            "EVM transaction detail returned a mismatched sender"
        }

        val receiptStatus = receipt.status
        check(receiptStatus != null) {
            "EVM transaction receipt requires an authoritative status"
        }
        val isSuccessful = requireRecognizedEvmStatus(receiptStatus)

        val gasUsedUnits = receipt.gasUsed?.let {
            requireUnsignedQuantity(it, "gasUsed")
        } ?: error("EVM transaction receipt requires authoritative gasUsed evidence")
        val effectiveGasPriceUnits = receipt.effectiveGasPrice?.let {
            requireUnsignedQuantity(it, "effectiveGasPrice")
        } ?: error(
            "EVM transaction receipt requires authoritative effectiveGasPrice evidence"
        )
        val feeInNativeUnits = BigDecimal(
            gasUsedUnits.multiply(effectiveGasPriceUnits)
        ).movePointLeft(18)
        val fee = feeInNativeUnits.toDouble()
        check(
            fee.isFinite() &&
                fee >= 0.0 &&
                (feeInNativeUnits.signum() == 0 || fee > 0.0)
        ) {
            "EVM transaction receipt gas fee cannot be represented safely"
        }
        return NativeReceiptGas(
            fee = fee,
            isSuccessful = isSuccessful
        )
    }

    private fun requireNonBlankReceiptText(
        field: String,
        value: String?
    ): String {
        val normalized = value?.trim()?.lowercase()
        check(!normalized.isNullOrEmpty()) {
            "EVM transaction receipt requires authoritative $field evidence"
        }
        return normalized
    }

    private fun requireRecognizedEvmStatus(element: JsonElement): Boolean {
        val normalized = (element as? JsonPrimitive)
            ?.content
            ?.trim()
            ?.lowercase()
        return when (normalized) {
            "true", "1", "0x1" -> true
            "false", "0", "0x0" -> false
            else -> error("EVM transaction receipt contains an invalid status")
        }
    }

    private fun requireUnsignedQuantity(
        element: JsonElement,
        field: String
    ): BigInteger {
        val raw = (element as? JsonPrimitive)
            ?.content
            ?.trim()
            .orEmpty()
        val parsed = when {
            raw.startsWith("0x", ignoreCase = true) && raw.length > 2 ->
                runCatching { BigInteger(raw.drop(2), 16) }.getOrNull()
            else -> raw.toBigIntegerOrNull()
        }
        check(parsed != null && parsed.signum() >= 0) {
            "EVM transaction receipt contains invalid gas quantity $field"
        }
        return parsed
    }

    private fun Any.toOnChainTransaction(
        route: TransactionFetchRoute,
        assetId: String,
        trackedAddress: String,
        nativeGasChargeByProviderRecordKey: Map<String, Double>
    ): MappedOnChainTransaction? {
        return when (this) {
            is TatumUTXOTransaction -> if (route is UtxoTransactionRoute) {
                val canonicalHash = resolvedHash.trim().lowercase()
                check(canonicalHash.isNotEmpty()) {
                    "UTXO transaction requires a non-blank provider hash"
                }
                val timestampMillis = requireProviderTimestampMillis(
                    rawTimestamp = resolvedTime,
                    recordDescription = "UTXO transaction $canonicalHash"
                )
                val providerIdentity = UtxoProviderIdentity(
                    assetId = assetId,
                    canonicalHash = canonicalHash,
                    providerHashAliases = normalizedProviderHashes.minus(canonicalHash),
                    hasDurableAliasMetadata = normalizedProviderHashes.minus(canonicalHash).isNotEmpty()
                )
                this.toTransaction(
                    route = route,
                    assetId = assetId,
                    trackedAddress = trackedAddress,
                    externalId = providerIdentity.externalId,
                    timestampMillis = timestampMillis
                )?.let { transaction ->
                    MappedOnChainTransaction(
                        transaction = transaction,
                        legacyGroupKey = "utxo:$assetId:$canonicalHash",
                        legacyExternalIds = buildSet {
                            providerIdentity.allProviderHashes.forEach { providerHash ->
                                add(providerHash)
                                val scopedHash = "utxo:$assetId:$providerHash"
                                if (scopedHash != transaction.externalId) {
                                    add(scopedHash)
                                }
                            }
                        },
                        utxoProviderIdentity = providerIdentity,
                        providerRecordKey = null,
                        providerRecordBaseKey = null,
                        providerTransactionIndex = null,
                        providerLogIndex = null
                    )
                }
            } else {
                null
            }
            is TatumTransactionDto -> if (
                route is EvmTransactionRoute &&
                matchesRoute(route.assetRoute, trackedAddress)
            ) {
                val providerAmount = amount
                    ?.trim()
                    ?.toDoubleOrNull()
                check(providerAmount != null && providerAmount.isFinite()) {
                    "Routed EVM transaction requires a finite signed amount"
                }
                val normalizedSubtype = normalizedEvmSubtype()
                when (normalizedSubtype) {
                    "incoming" -> check(providerAmount > 0.0) {
                        "EVM incoming transaction requires a positive provider amount"
                    }
                    "outgoing" -> check(providerAmount < 0.0) {
                        "EVM outgoing transaction requires a negative provider amount"
                    }
                    "zero-transfer" -> check(providerAmount == 0.0) {
                        "EVM zero-transfer transaction requires a zero provider amount"
                    }
                    else -> error(
                        "Routed EVM transaction requires an incoming, outgoing, or " +
                            "zero-transfer subtype"
                    )
                }
                if (!route.assetRoute.isNative && normalizedSubtype == "zero-transfer") {
                    return null
                }

                val canonicalHash = hash.trim()
                check(canonicalHash.isNotEmpty()) {
                    "EVM transaction requires a non-blank provider hash"
                }
                check(
                    (transactionIndex == null || transactionIndex >= 0) &&
                        (logIndex == null || logIndex >= 0)
                ) {
                    "Provider event indices must be non-negative"
                }
                val timestampMillis = requireProviderTimestampMillis(
                    rawTimestamp = timestamp,
                    recordDescription = "EVM transaction $canonicalHash"
                )
                this.toTransaction(
                    route = route.assetRoute,
                    assetId = assetId,
                    trackedAddress = trackedAddress,
                    providerAmount = providerAmount,
                    timestampMillis = timestampMillis,
                    nativeGasCharge = nativeGasChargeByProviderRecordKey[
                        stableProviderRecordKey()
                    ]
                )?.let { transaction ->
                    MappedOnChainTransaction(
                        transaction = transaction,
                        legacyGroupKey = "evm:$assetId:${canonicalHash.lowercase()}",
                        legacyExternalIds = setOf(
                            canonicalHash,
                            canonicalHash.lowercase()
                        ),
                        utxoProviderIdentity = null,
                        providerRecordKey = stableProviderRecordKey(),
                        providerRecordBaseKey = stableProviderRecordBaseKey(),
                        providerTransactionIndex = transactionIndex,
                        providerLogIndex = logIndex
                    )
                }
            } else {
                null
            }
            else -> null
        }
    }

    private fun TatumUTXOTransaction.toTransaction(
        route: UtxoTransactionRoute,
        assetId: String,
        trackedAddress: String,
        externalId: String,
        timestampMillis: Long
    ): Transaction? {
        val epsilon = 1e-10
        var netAmount = 0.0
        var externalInputAddress: String? = null
        var externalOutputAddress: String? = null

        val transactionHash = resolvedHash.takeIf { it.isNotBlank() } ?: return null

        // Spending inputs.
        resolvedInputs.forEach { input ->
            if (input.isCoinbaseInput()) {
                return@forEach
            }
            val inputAddresses = input.allAddresses()
            val value = (input.coin?.valueNumber ?: input.prevout?.valueNumber)
                ?.takeIf { it.isFinite() && it >= 0.0 }
                ?: error("Cannot prove UTXO net amount for $transactionHash: unresolved input value")
            check(inputAddresses.isNotEmpty()) {
                "Cannot prove UTXO net amount for $transactionHash: unresolved input address"
            }
            if (inputAddresses.any { route.chain.addressesEqual(it, trackedAddress) }) {
                netAmount = checkedFiniteSum(
                    left = netAmount,
                    right = -value.toHumanReadableAmount(route.chain),
                    description = "Cannot prove UTXO net amount for $transactionHash"
                )
            } else if (externalInputAddress == null) {
                externalInputAddress = inputAddresses.firstOrNull()
            }
        }

        // Receiving outputs.
        resolvedOutputs.forEach { output ->
            val outputAddresses = output.allAddresses()
            if (outputAddresses.any { route.chain.addressesEqual(it, trackedAddress) }) {
                val outputValue = output.valueNumber
                    ?.takeIf { it.isFinite() && it >= 0.0 }
                    ?: error(
                        "Cannot prove UTXO net amount for $transactionHash: " +
                            "tracked output has no valid value"
                    )
                val amount = outputValue.toHumanReadableAmount(route.chain)
                netAmount = checkedFiniteSum(
                    left = netAmount,
                    right = amount,
                    description = "Cannot prove UTXO net amount for $transactionHash"
                )
            }
            if (externalOutputAddress == null) {
                externalOutputAddress = outputAddresses.firstOrNull {
                    !route.chain.addressesEqual(it, trackedAddress)
                }
            }
        }

        if (abs(netAmount) <= epsilon) return null

        val signedAmount = netAmount
        val counterparty = if (signedAmount >= 0) {
            externalInputAddress ?: externalOutputAddress
        } else {
            externalOutputAddress ?: externalInputAddress
        }
        return Transaction(
            id = externalId,
            assetId = assetId,
            amount = signedAmount,
            dateMillis = timestampMillis,
            source = TransactionSource.ON_CHAIN,
            externalId = externalId,
            counterparty = counterparty,
            comment = "On-chain",
            createdAt = System.currentTimeMillis()
        )
    }

    private fun checkedFiniteSum(
        left: Double,
        right: Double,
        description: String
    ): Double {
        val sum = left + right
        check(left.isFinite() && right.isFinite() && sum.isFinite()) {
            "$description requires a finite aggregate"
        }
        return sum
    }

    private fun Transaction.isCanonicalProviderRowFor(
        route: TransactionFetchRoute,
        assetId: String,
        trackedAddress: String
    ): Boolean {
        if (source != TransactionSource.ON_CHAIN || this.assetId != assetId) return false
        val providerExternalId = externalId?.trim()?.takeIf { it.isNotEmpty() } ?: return false
        return when (route) {
            is UtxoTransactionRoute -> {
                providerExternalId.startsWith("utxo:$assetId:", ignoreCase = true) ||
                    providerExternalId.startsWith(
                        "$UTXO_PROVIDER_RECORD_MARKER$UTXO_PROVIDER_RECORD_SEPARATOR" +
                            "$assetId$UTXO_PROVIDER_RECORD_SEPARATOR"
                    )
            }
            is EvmTransactionRoute -> {
                val components = providerExternalId.split(':').map(String::trim)
                components.size == EVM_PROVIDER_RECORD_COMPONENT_COUNT &&
                    components[0].equals(EVM_PROVIDER_RECORD_MARKER, ignoreCase = true) &&
                    components[1].equals(route.assetRoute.tatumChain, ignoreCase = true) &&
                    components[3].equals(route.assetRoute.transactionType, ignoreCase = true) &&
                    components[5].equals(trackedAddress, ignoreCase = true) &&
                    if (route.assetRoute.isNative) {
                        components[4].equals("native", ignoreCase = true)
                    } else {
                        route.assetRoute.tokenContracts.any { contract ->
                            components[4].equals(contract, ignoreCase = true)
                        }
                    }
            }
        }
    }

    private fun List<Transaction>.toProviderAbsenceEvidence(): ProviderAbsenceEvidence {
        return ProviderAbsenceEvidence(
            rowFingerprints = map { transaction ->
                listOf(
                    transaction.id,
                    checkNotNull(transaction.externalId),
                    transaction.amount.toBits().toString(),
                    transaction.dateMillis.toString(),
                    transaction.createdAt.toString()
                ).joinToString(separator = "\u001f")
            }.sorted()
        )
    }

    private fun Double.toHumanReadableAmount(chain: UtxoTransactionChain): Double {
        return when (chain) {
            UtxoTransactionChain.BITCOIN -> this / SATOSHIS_PER_BITCOIN
            UtxoTransactionChain.LITECOIN,
            UtxoTransactionChain.BITCOIN_CASH,
            UtxoTransactionChain.DOGECOIN -> this
        }
    }

    private fun installedUtxoIdentityFromExternalId(
        externalId: String?,
        assetId: String
    ): UtxoProviderIdentity? {
        val value = externalId?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        if (value.startsWith("$UTXO_PROVIDER_RECORD_MARKER$UTXO_PROVIDER_RECORD_SEPARATOR")) {
            val components = value.split(UTXO_PROVIDER_RECORD_SEPARATOR)
            check(
                components.size >= 6 &&
                    components[0] == UTXO_PROVIDER_RECORD_MARKER &&
                    components[1] == assetId &&
                    components[2].isNotBlank() &&
                    components[3] == UTXO_PROVIDER_ALIAS_MARKER
            ) {
                "Installed UTXO provider identity is malformed"
            }
            val aliasCount = components[4].toIntOrNull()
            check(aliasCount != null && aliasCount > 0 && components.size == 5 + aliasCount) {
                "Installed UTXO provider alias metadata is malformed"
            }
            val canonicalHash = components[2].trim().lowercase()
            val aliases = components.drop(5)
                .mapTo(linkedSetOf()) { it.trim().lowercase() }
            check(
                aliases.size == aliasCount &&
                    aliases.none { it.isBlank() || it == canonicalHash }
            ) {
                "Installed UTXO provider alias metadata is ambiguous"
            }
            return UtxoProviderIdentity(
                assetId = assetId,
                canonicalHash = canonicalHash,
                providerHashAliases = aliases,
                hasDurableAliasMetadata = true
            )
        }

        val scopedPrefix = "utxo:$assetId:"
        if (value.startsWith(scopedPrefix, ignoreCase = true)) {
            val canonicalHash = value.substring(scopedPrefix.length).trim().lowercase()
            return canonicalHash.takeIf { it.isNotEmpty() }?.let {
                UtxoProviderIdentity(
                    assetId = assetId,
                    canonicalHash = it,
                    providerHashAliases = emptySet(),
                    hasDurableAliasMetadata = false
                )
            }
        }
        if (
            value.startsWith("utxo:", ignoreCase = true) ||
            value.startsWith(EVM_PROVIDER_RECORD_MARKER, ignoreCase = true) ||
            value.contains(UTXO_PROVIDER_RECORD_SEPARATOR)
        ) {
            return null
        }
        return UtxoProviderIdentity(
            assetId = assetId,
            canonicalHash = value.lowercase(),
            providerHashAliases = emptySet(),
            hasDurableAliasMetadata = false
        )
    }

    private fun assertUtxoMetadataCanMerge(
        retained: Transaction,
        removed: Transaction,
        route: UtxoTransactionRoute
    ) {
        val retainedUserComment = retained.userComment
        val removedUserComment = removed.userComment
        check(
            retainedUserComment == null ||
                removedUserComment == null ||
                retainedUserComment == removedUserComment
        ) {
            "UTXO canonical and legacy transaction metadata conflicts"
        }

        val retainedCounterparty = retained.counterparty?.trim()?.takeIf { it.isNotEmpty() }
        val removedCounterparty = removed.counterparty?.trim()?.takeIf { it.isNotEmpty() }
        check(
            retainedCounterparty == null ||
                removedCounterparty == null ||
                route.chain.addressesEqual(retainedCounterparty, removedCounterparty)
        ) {
            "UTXO canonical and legacy transaction metadata conflicts"
        }
    }

    private val Transaction.userComment: String?
        get() = comment
            ?.trim()
            ?.takeIf { it.isNotEmpty() && !it.equals("On-chain", ignoreCase = true) }

    private fun Transaction.preferredCommentWith(
        other: Transaction,
        provider: Transaction
    ): String? {
        return userComment
            ?: other.userComment
            ?: comment?.takeIf { it.isNotBlank() }
            ?: other.comment?.takeIf { it.isNotBlank() }
            ?: provider.comment
    }

    private fun Transaction.preferredCounterpartyWith(
        other: Transaction,
        provider: Transaction
    ): String? {
        return counterparty?.takeIf { it.isNotBlank() }
            ?: other.counterparty?.takeIf { it.isNotBlank() }
            ?: provider.counterparty
    }

    private fun TransactionFetchRoute.normalizeAddressForComparison(address: String): String {
        return when (this) {
            is EvmTransactionRoute ->
                OnChainAddressIdentityV1.canonicalize(assetRoute.canonicalChainId, address)
            is UtxoTransactionRoute ->
                OnChainAddressIdentityV1.canonicalize(chain.persistenceChainId, address)
        }
    }

    private fun UtxoTransactionChain.addressesEqual(left: String, right: String): Boolean {
        return OnChainAddressIdentityV1.canonicalize(persistenceChainId, left) ==
            OnChainAddressIdentityV1.canonicalize(persistenceChainId, right)
    }

    private val UtxoTransactionChain.persistenceChainId: String
        get() = when (this) {
            UtxoTransactionChain.BITCOIN -> "bitcoin"
            UtxoTransactionChain.LITECOIN -> "litecoin"
            UtxoTransactionChain.BITCOIN_CASH -> "bitcoin-cash"
            UtxoTransactionChain.DOGECOIN -> "dogecoin"
        }

    private fun TatumTransactionDto.toTransaction(
        route: EvmAssetRoute,
        assetId: String,
        trackedAddress: String,
        providerAmount: Double,
        timestampMillis: Long,
        nativeGasCharge: Double?
    ): Transaction? {
        check(matchesRoute(route, trackedAddress)) {
            "EVM transaction route changed during mapping"
        }
        val subtype = transactionSubtype
            ?.trim()
            ?.lowercase()
            ?.replace('_', '-')
            .orEmpty()
        val signedAmount = when {
            subtype == "incoming" -> providerAmount
            subtype == "outgoing" && route.isNative -> {
                checkedFiniteSum(
                    left = providerAmount,
                    right = -requireNotNull(nativeGasCharge) {
                        "Native sender movement requires authoritative receipt gas"
                    },
                    description = "Native outgoing transaction"
                )
            }
            subtype == "outgoing" -> providerAmount
            subtype == "zero-transfer" && route.isNative -> {
                -requireNotNull(nativeGasCharge) {
                    "Native sender movement requires authoritative receipt gas"
                }
            }
            else -> return null
        }
        if (signedAmount == 0.0) return null

        val externalEventId = stableEventExternalId()

        return Transaction(
            id = externalEventId,
            assetId = assetId,
            amount = signedAmount,
            dateMillis = timestampMillis,
            source = TransactionSource.ON_CHAIN,
            externalId = externalEventId,
            counterparty = counterAddress,
            comment = "On-chain",
            createdAt = System.currentTimeMillis()
        )
    }

    private fun TatumTransactionDto.matchesRoute(
        route: EvmAssetRoute,
        trackedAddress: String
    ): Boolean {
        if (!chain.equals(route.tatumChain, ignoreCase = true)) return false
        if (!address.equals(trackedAddress, ignoreCase = true)) return false
        if (!transactionType.equals(route.transactionType, ignoreCase = true)) return false
        return if (route.isNative) {
            tokenAddress.isNullOrBlank()
        } else {
            route.tokenContracts.any { contract ->
                tokenAddress.equals(contract, ignoreCase = true)
            }
        }
    }

    private fun TatumTransactionDto.stableEventExternalId(): String {
        return stableProviderRecordKey()
    }

    private fun TatumTransactionDto.stableProviderRecordKey(): String {
        return listOf(
            EVM_PROVIDER_RECORD_MARKER,
            chain.orEmpty(),
            hash,
            transactionType.orEmpty(),
            tokenAddress ?: "native",
            address.orEmpty(),
            tokenId ?: "no-token-id",
            transactionIndex?.toString() ?: "no-transaction-index",
            logIndex?.toString() ?: "no-log-index"
        ).joinToString(separator = ":") { it.trim().lowercase() }
    }

    private fun TatumTransactionDto.stableProviderRecordBaseKey(): String {
        return listOf(
            EVM_PROVIDER_RECORD_BASE_MARKER,
            chain.orEmpty(),
            hash,
            transactionType.orEmpty(),
            tokenAddress ?: "native",
            address.orEmpty(),
            tokenId ?: "no-token-id"
        ).joinToString(separator = ":") { it.trim().lowercase() }
    }

    private fun providerRecordIdentityFromInstalledExternalId(
        externalId: String?
    ): InstalledProviderRecordIdentity? {
        val components = externalId
            ?.split(':')
            ?.map(String::trim)
            ?: return null
        if (
            components.size == EVM_PROVIDER_RECORD_COMPONENT_COUNT &&
            components.first().equals(EVM_PROVIDER_RECORD_MARKER, ignoreCase = true)
        ) {
            val transactionIndex = components[7].parseProviderIndex(
                missingMarker = "no-transaction-index"
            ) ?: if (components[7].equals("no-transaction-index", ignoreCase = true)) {
                null
            } else {
                return null
            }
            val logIndex = components[8].parseProviderIndex(
                missingMarker = "no-log-index"
            ) ?: if (components[8].equals("no-log-index", ignoreCase = true)) {
                null
            } else {
                return null
            }
            return InstalledProviderRecordIdentity(
                strongKey = components.joinToString(":") { it.lowercase() },
                baseKey = listOf(
                    EVM_PROVIDER_RECORD_BASE_MARKER,
                    components[1],
                    components[2],
                    components[3],
                    components[4],
                    components[5],
                    components[6]
                ).joinToString(":") { it.lowercase() },
                transactionIndex = transactionIndex,
                logIndex = logIndex
            )
        }
        if (components.size != LEGACY_MUTABLE_EVM_COMPONENT_COUNT) return null
        val transactionIndex = components[9].parseProviderIndex(
            missingMarker = "no-transaction-index"
        ) ?: if (components[9].equals("no-transaction-index", ignoreCase = true)) {
            null
        } else {
            return null
        }
        val logIndex = components[10].parseProviderIndex(
            missingMarker = "no-log-index"
        ) ?: if (components[10].equals("no-log-index", ignoreCase = true)) {
            null
        } else {
            return null
        }

        return InstalledProviderRecordIdentity(
            strongKey = listOf(
                EVM_PROVIDER_RECORD_MARKER,
                components[0],
                components[1],
                components[2],
                components[3],
                components[4],
                components[8],
                components[9],
                components[10]
            ).joinToString(":") { it.lowercase() },
            baseKey = listOf(
                EVM_PROVIDER_RECORD_BASE_MARKER,
                components[0],
                components[1],
                components[2],
                components[3],
                components[4],
                components[8]
            ).joinToString(":") { it.lowercase() },
            transactionIndex = transactionIndex,
            logIndex = logIndex
        )
    }

    private fun InstalledProviderRecordIdentity.indicesAreCompatibleWith(
        mapped: MappedOnChainTransaction
    ): Boolean {
        return indicesAreCompatible(
            firstTransactionIndex = transactionIndex,
            firstLogIndex = logIndex,
            secondTransactionIndex = mapped.providerTransactionIndex,
            secondLogIndex = mapped.providerLogIndex
        )
    }

    private fun InstalledProviderRecordIdentity.canBeEnrichedBy(
        mapped: MappedOnChainTransaction
    ): Boolean {
        return (transactionIndex == null || transactionIndex == mapped.providerTransactionIndex) &&
            (logIndex == null || logIndex == mapped.providerLogIndex)
    }

    private fun MappedOnChainTransaction.indicesAreCompatibleWith(
        other: MappedOnChainTransaction
    ): Boolean {
        return indicesAreCompatible(
            firstTransactionIndex = providerTransactionIndex,
            firstLogIndex = providerLogIndex,
            secondTransactionIndex = other.providerTransactionIndex,
            secondLogIndex = other.providerLogIndex
        )
    }

    private fun MappedOnChainTransaction.strictlyEnriches(
        weaker: MappedOnChainTransaction
    ): Boolean {
        if (!indicesAreCompatibleWith(weaker)) return false
        if (
            weaker.providerTransactionIndex != null &&
            providerTransactionIndex != weaker.providerTransactionIndex
        ) {
            return false
        }
        if (weaker.providerLogIndex != null && providerLogIndex != weaker.providerLogIndex) {
            return false
        }
        return providerIndexSpecificity > weaker.providerIndexSpecificity
    }

    private val MappedOnChainTransaction.providerIndexSpecificity: Int
        get() = listOf(providerTransactionIndex, providerLogIndex).count { it != null }

    private fun indicesAreCompatible(
        firstTransactionIndex: Int?,
        firstLogIndex: Int?,
        secondTransactionIndex: Int?,
        secondLogIndex: Int?
    ): Boolean {
        val transactionIndicesMatch = firstTransactionIndex == null ||
            secondTransactionIndex == null ||
            firstTransactionIndex == secondTransactionIndex
        val logIndicesMatch = firstLogIndex == null ||
            secondLogIndex == null ||
            firstLogIndex == secondLogIndex
        return transactionIndicesMatch && logIndicesMatch
    }

    private fun String.parseProviderIndex(missingMarker: String): Int? {
        if (equals(missingMarker, ignoreCase = true)) return null
        return toIntOrNull()?.takeIf { it >= 0 }
    }

    /**
     * iOS parity: if an asset is fully allocated to exactly one goal, new deposits should keep it fully allocated.
     * For partially allocated or shared assets, deposits remain unallocated.
     */
    private suspend fun reconcileDedicatedAutoAllocationCorrectionsIfNeeded(
        asset: Asset,
        corrections: List<ProviderTransactionCorrection>,
        cachedOnChainBalance: Double?
    ) {
        val relevantCorrections = corrections.filter { correction ->
            correction.previous.source == TransactionSource.ON_CHAIN &&
                correction.corrected.source == TransactionSource.ON_CHAIN &&
                (
                    correction.previous.depositContribution > AUTO_ALLOCATION_EPSILON ||
                        correction.corrected.depositContribution > AUTO_ALLOCATION_EPSILON
                )
        }
        if (relevantCorrections.isEmpty()) return

        val correctedRowIds = relevantCorrections.mapTo(hashSetOf()) { correction ->
            correction.previous.id
        }
        val priorDepositTimestamps = relevantCorrections
            .filter { correction ->
                correction.previous.depositContribution > AUTO_ALLOCATION_EPSILON
            }
            .mapTo(hashSetOf()) { correction -> correction.previous.dateMillis }
        val duplicatePriorDepositTimestamps = relevantCorrections
            .filter { correction ->
                correction.previous.depositContribution > AUTO_ALLOCATION_EPSILON
            }
            .groupingBy { correction -> correction.previous.dateMillis }
            .eachCount()
            .filterValues { count -> count > 1 }
            .keys
        check(duplicatePriorDepositTimestamps.isEmpty()) {
            "Dedicated auto-allocation provider correction has ambiguous same-timestamp provenance"
        }
        val hasUnprovenSameTimestampSibling = transactionRepository
            .getTransactionsByAssetIdOnce(asset.id)
            .any { remaining ->
                remaining.id !in correctedRowIds &&
                    remaining.source == TransactionSource.ON_CHAIN &&
                    remaining.amount > AUTO_ALLOCATION_EPSILON &&
                    remaining.dateMillis in priorDepositTimestamps
            }
        check(!hasUnprovenSameTimestampSibling) {
            "Dedicated auto-allocation provider correction has ambiguous same-timestamp provenance"
        }

        val allocations = allocationRepository.getAllocationsForAsset(asset.id)
        if (allocations.size != 1) {
            val histories = allocationHistoryRepository
                .getByAssetId(asset.id)
                .first()
            val hasPriorAutoAllocationEvidence = relevantCorrections.any { correction ->
                correction.previous.depositContribution > AUTO_ALLOCATION_EPSILON &&
                    histories.any { history ->
                        history.timestamp == correction.previous.dateMillis &&
                            history.monthLabel ==
                            MonthLabelUtils.fromMillisUtc(correction.previous.dateMillis)
                    }
            }
            check(!hasPriorAutoAllocationEvidence) {
                "Dedicated auto-allocation provider correction ownership is ambiguous"
            }
            return
        }
        val allocation = allocations.single()
        if (relevantCorrections.size > 1) {
            reconcileDedicatedRemovalBatch(
                allocation = allocation,
                corrections = relevantCorrections
            )
            return
        }
        val correction = relevantCorrections.single()
        val previousContribution = correction.previous.depositContribution
        val correctedContribution = correction.corrected.depositContribution
        val goalHistories = allocationHistoryRepository
            .getByAssetId(allocation.assetId)
            .first()
            .filter { history -> history.goalId == allocation.goalId }
        val previousMonth = MonthLabelUtils.fromMillisUtc(correction.previous.dateMillis)
        val previousHistory = if (previousContribution > AUTO_ALLOCATION_EPSILON) {
            val exactPreviousCandidates = goalHistories.filter { history ->
                history.monthLabel == previousMonth &&
                    history.timestamp == correction.previous.dateMillis
            }
            check(exactPreviousCandidates.size <= 1) {
                "Dedicated auto-allocation correction has ambiguous movement evidence"
            }
            exactPreviousCandidates.singleOrNull() ?: return
        } else {
            null
        }
        if (previousHistory != null) {
            val latestHistory = goalHistories.maxWithOrNull(
                compareBy<AllocationHistory> { it.timestamp }
                    .thenBy { it.createdAt }
                    .thenBy { it.id }
            )
            check(latestHistory?.id == previousHistory.id) {
                "Dedicated auto-allocation correction evidence is not the latest history"
            }
            val evidenceTolerance = max(
                AUTO_ALLOCATION_EPSILON,
                max(abs(previousHistory.amount), abs(allocation.amount)) * 0.000001
            )
            check(
                previousHistory.timestamp == correction.previous.dateMillis &&
                    abs(previousHistory.amount - allocation.amount) <= evidenceTolerance
            ) {
                "Dedicated auto-allocation correction evidence does not match current allocation"
            }
        }

        val delta = checkedFiniteSum(
            left = correctedContribution,
            right = -previousContribution,
            description = "Dedicated auto-allocation provider correction"
        )
        val correctedTarget = checkedFiniteSum(
            left = allocation.amount,
            right = delta,
            description = "Dedicated auto-allocation corrected target"
        )
        if (correctedContribution > AUTO_ALLOCATION_EPSILON) {
            val manual = transactionRepository.getManualBalanceForAsset(asset.id)
            val cachedOnChain = checkNotNull(cachedOnChainBalance) {
                "On-chain balance is unavailable for dedicated auto-allocation correction"
            }
            val total = checkedFiniteSum(
                left = manual,
                right = cachedOnChain,
                description = "Dedicated auto-allocation corrected balance"
            )
            val balanceTolerance = max(
                AUTO_ALLOCATION_EPSILON,
                max(abs(total), abs(correctedTarget)) * 0.000001
            )
            if (abs(total - correctedTarget) > balanceTolerance) return
        }

        val correctedMonth = MonthLabelUtils.fromMillisUtc(correction.corrected.dateMillis)
        val conflictingTargetHistory = goalHistories.firstOrNull { history ->
            history.monthLabel == correctedMonth &&
                history.timestamp == correction.corrected.dateMillis &&
                history.id != previousHistory?.id
        }
        check(conflictingTargetHistory == null) {
            "Dedicated auto-allocation correction conflicts with target month history"
        }
        if (previousHistory != null) {
            check(
                goalHistories.none { history ->
                    history.id != previousHistory.id &&
                        history.timestamp > correction.corrected.dateMillis
                }
            ) {
                "Dedicated auto-allocation correction would violate history chronology"
            }
        }

        val now = System.currentTimeMillis()
        allocationRepository.upsertAllocation(
            allocation.copy(
                amount = correctedTarget,
                lastModifiedAt = now
            )
        )
        allocationHistoryRepository.insert(
            previousHistory?.copy(
                amount = correctedTarget,
                monthLabel = correctedMonth,
                timestamp = correction.corrected.dateMillis
            ) ?: AllocationHistory(
                id = UUID.randomUUID().toString(),
                assetId = allocation.assetId,
                goalId = allocation.goalId,
                amount = correctedTarget,
                monthLabel = correctedMonth,
                timestamp = correction.corrected.dateMillis,
                createdAt = now
            )
        )
    }

    private suspend fun reconcileDedicatedRemovalBatch(
        allocation: Allocation,
        corrections: List<ProviderTransactionCorrection>
    ) {
        check(corrections.all { correction ->
            correction.previous.depositContribution > AUTO_ALLOCATION_EPSILON &&
                correction.corrected.depositContribution <= AUTO_ALLOCATION_EPSILON
        }) {
            "Dedicated auto-allocation provider correction batch is ambiguous"
        }
        val contributionByTimestamp = corrections
            .groupBy { correction -> correction.previous.dateMillis }
            .mapValues { (_, timestampCorrections) ->
                timestampCorrections.fold(0.0) { sum, correction ->
                    checkedFiniteSum(
                        left = sum,
                        right = correction.previous.depositContribution,
                        description = "Dedicated auto-allocation removal batch"
                    )
                }
            }
        val goalHistories = allocationHistoryRepository
            .getByAssetId(allocation.assetId)
            .first()
            .filter { history -> history.goalId == allocation.goalId }
        val historyByTimestamp = contributionByTimestamp.mapValues { (timestamp, _) ->
            val candidates = goalHistories.filter { history ->
                history.timestamp == timestamp &&
                    history.monthLabel == MonthLabelUtils.fromMillisUtc(timestamp)
            }
            check(candidates.size <= 1) {
                "Dedicated auto-allocation removal has ambiguous movement evidence"
            }
            candidates.singleOrNull()
        }
        val evidenceHistories = historyByTimestamp.values.filterNotNull()
        if (evidenceHistories.isEmpty()) return
        check(evidenceHistories.size == contributionByTimestamp.size) {
            "Dedicated auto-allocation removal evidence is incomplete"
        }

        val historyOrder = compareBy<AllocationHistory> { it.timestamp }
            .thenBy { it.createdAt }
            .thenBy { it.id }
        val orderedGoalHistories = goalHistories.sortedWith(historyOrder)
        val orderedEvidence = evidenceHistories.sortedWith(historyOrder)
        check(
            orderedGoalHistories.takeLast(orderedEvidence.size).map { it.id } ==
                orderedEvidence.map { it.id }
        ) {
            "Dedicated auto-allocation removal evidence is not the latest history suffix"
        }

        var correctedTarget = allocation.amount
        contributionByTimestamp.entries
            .sortedByDescending { it.key }
            .forEach { (timestamp, contribution) ->
                val evidence = checkNotNull(historyByTimestamp.getValue(timestamp))
                val evidenceTolerance = max(
                    AUTO_ALLOCATION_EPSILON,
                    max(abs(evidence.amount), abs(correctedTarget)) * 0.000001
                )
                check(abs(evidence.amount - correctedTarget) <= evidenceTolerance) {
                    "Dedicated auto-allocation removal evidence does not match current allocation"
                }
                correctedTarget = checkedFiniteSum(
                    left = correctedTarget,
                    right = -contribution,
                    description = "Dedicated auto-allocation removal target"
                )
            }

        val now = System.currentTimeMillis()
        allocationRepository.upsertAllocation(
            allocation.copy(
                amount = correctedTarget,
                lastModifiedAt = now
            )
        )
        val retainedEvidence = orderedEvidence.last()
        orderedEvidence.dropLast(1).forEach { history ->
            allocationHistoryRepository.deleteById(history.id)
        }
        allocationHistoryRepository.insert(
            retainedEvidence.copy(amount = correctedTarget)
        )
    }

    private val Transaction.depositContribution: Double
        get() = amount.takeIf { it > AUTO_ALLOCATION_EPSILON } ?: 0.0

    private suspend fun applyDedicatedAutoAllocationIfNeeded(
        asset: Asset,
        insertedTransactions: List<Transaction>,
        cachedOnChainBalance: Double?
    ) {
        val epsilon = AUTO_ALLOCATION_EPSILON
        val allocations = allocationRepository.getAllocationsForAsset(asset.id)
        if (allocations.size != 1) return
        val allocation = allocations.first()

        val deposits = insertedTransactions
            .filter { it.source == TransactionSource.ON_CHAIN && it.amount > epsilon }
            .sortedBy { it.dateMillis }
        if (deposits.isEmpty()) return
        val goalHistories = allocationHistoryRepository
            .getByAssetId(allocation.assetId)
            .firstOrNull()
            .orEmpty()
            .filter { history -> history.goalId == allocation.goalId }
        val latestHistoryTimestamp = goalHistories
            .asSequence()
            .maxOfOrNull { history -> history.timestamp }
        if (
            latestHistoryTimestamp != null &&
            deposits.any { deposit -> deposit.dateMillis <= latestHistoryTimestamp }
        ) {
            // Without transaction-to-history provenance, an equal timestamp may
            // already represent a different provider movement from an earlier refresh.
            return
        }
        val depositsByTimestamp = deposits
            .groupBy { deposit -> deposit.dateMillis }
            .map { (timestamp, sameTimestampDeposits) ->
                timestamp to sameTimestampDeposits.fold(0.0) { sum, deposit ->
                    checkedFiniteSum(
                        left = sum,
                        right = deposit.amount,
                        description = "Dedicated auto-allocation timestamp group"
                    )
                }
            }
            .sortedBy { (timestamp, _) -> timestamp }

        val manual = transactionRepository.getManualBalanceForAsset(asset.id)
        val cachedOnChain = checkNotNull(cachedOnChainBalance) {
            "On-chain balance is unavailable for dedicated auto-allocation"
        }
        val total = checkedFiniteSum(
            left = manual,
            right = cachedOnChain,
            description = "Dedicated auto-allocation balance"
        )

        val unallocatedNow = max(
            0.0,
            checkedFiniteSum(
                left = total,
                right = -allocation.amount,
                description = "Dedicated auto-allocation remainder"
            )
        )
        val depositsSum = depositsByTimestamp.fold(0.0) { sum, (_, depositAmount) ->
            checkedFiniteSum(
                left = sum,
                right = depositAmount,
                description = "Dedicated auto-allocation deposits"
            )
        }
        val tolerance = max(epsilon, max(unallocatedNow, depositsSum) * 0.000001)
        if (abs(unallocatedNow - depositsSum) > tolerance) return

        var runningTarget = allocation.amount
        for ((timestamp, depositAmount) in depositsByTimestamp) {
            runningTarget = checkedFiniteSum(
                left = runningTarget,
                right = depositAmount,
                description = "Dedicated auto-allocation target"
            )
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
                    monthLabel = MonthLabelUtils.fromMillisUtc(timestamp),
                    timestamp = timestamp,
                    createdAt = System.currentTimeMillis()
                )
            )
        }
    }

    private fun transactionRoute(chainId: String, currency: String): TransactionFetchRoute {
        fun requireNativeCurrency(expectedCurrency: String): Unit = require(
            currency.equals(expectedCurrency, ignoreCase = true)
        ) {
            "Unsupported asset $currency on $chainId; only native $expectedCurrency transactions are supported"
        }

        return when (chainId.lowercase()) {
            "bitcoin" -> {
                requireNativeCurrency("BTC")
                UtxoTransactionRoute(UtxoTransactionChain.BITCOIN)
            }
            "litecoin" -> {
                requireNativeCurrency("LTC")
                UtxoTransactionRoute(UtxoTransactionChain.LITECOIN)
            }
            "bcash", "bitcoin-cash" -> {
                requireNativeCurrency("BCH")
                UtxoTransactionRoute(UtxoTransactionChain.BITCOIN_CASH)
            }
            "dogecoin" -> {
                requireNativeCurrency("DOGE")
                UtxoTransactionRoute(UtxoTransactionChain.DOGECOIN)
            }
            in EvmAssetRouting.chainIds -> EvmTransactionRoute(
                EvmAssetRouting.resolve(chainId = chainId, currencyOrContract = currency)
            )
            else -> throw IllegalArgumentException("Unsupported on-chain transaction chain: $chainId")
        }
    }

    private fun cacheKey(
        route: TransactionFetchRoute,
        assetId: String,
        chainId: String,
        address: String,
        currency: String
    ): String {
        val normalizedAddress = route.normalizeAddressForComparison(address)
        return "transactions_v3:$assetId:${chainId.lowercase()}:$normalizedAddress:${currency.uppercase()}"
    }

    private suspend fun getCacheEntry(key: String): TransactionsCacheEntry? {
        return mutex.withLock {
            prefs.getString(key, null)?.let {
                runCatching { json.decodeFromString<TransactionsCacheEntry>(it) }.getOrNull()
            }
        }
    }

    private suspend fun getPendingProviderAbsence(key: String): ProviderAbsenceEvidence? {
        return mutex.withLock {
            prefs.getString(providerAbsenceKey(key), null)?.let {
                runCatching { json.decodeFromString<ProviderAbsenceEvidence>(it) }.getOrNull()
            }
        }
    }

    private suspend fun registerRefresh(key: String): Long {
        return mutex.withLock {
            nextRefreshSequence = Math.incrementExact(nextRefreshSequence)
            nextRefreshSequence.also { sequence ->
                latestRefreshSequenceByCacheKey[key] = sequence
            }
        }
    }

    private suspend fun isLatestRefresh(key: String, refreshSequence: Long): Boolean {
        return mutex.withLock {
            latestRefreshSequenceByCacheKey[key] == refreshSequence
        }
    }

    private suspend fun publishRefreshStateIfLatest(
        key: String,
        refreshSequence: Long,
        entry: TransactionsCacheEntry,
        commitResult: RefreshCommitResult
    ) {
        mutex.withLock {
            if (latestRefreshSequenceByCacheKey[key] == refreshSequence) {
                val editor = prefs.edit()
                if (commitResult.shouldPublishCache) {
                    editor.putString(key, json.encodeToString(entry))
                } else {
                    editor.remove(key)
                }
                commitResult.pendingAbsence?.let { pending ->
                    editor.putString(providerAbsenceKey(key), json.encodeToString(pending))
                } ?: editor.remove(providerAbsenceKey(key))
                editor.apply()
            }
        }
    }

    private suspend fun removeCacheEntryIfLatest(key: String, refreshSequence: Long) {
        mutex.withLock {
            if (latestRefreshSequenceByCacheKey[key] == refreshSequence) {
                prefs.edit().remove(key).apply()
            }
        }
    }

    private fun providerAbsenceKey(cacheKey: String): String = "provider_absence_v1:$cacheKey"

    private companion object {
        const val MAX_EVM_PAGE_SIZE = 50
        const val MAX_EVM_HISTORY_PAGES = 20
        const val MAX_UTXO_PAGE_SIZE = 50
        const val MAX_UTXO_HISTORY_PAGES = 20
        const val AUTO_ALLOCATION_EPSILON = 1e-7
        const val SATOSHIS_PER_BITCOIN = 100_000_000.0
        const val EVM_PROVIDER_RECORD_MARKER = "evm-record-v1"
        const val EVM_PROVIDER_RECORD_BASE_MARKER = "evm-record-base-v1"
        const val EVM_PROVIDER_RECORD_COMPONENT_COUNT = 9
        const val LEGACY_MUTABLE_EVM_COMPONENT_COUNT = 11
        const val PROVIDER_MILLIS_TIMESTAMP_THRESHOLD = 1_000_000_000_000L
        const val MILLIS_PER_SECOND = 1_000L
        const val MAX_SUPPORTED_PROVIDER_TIMESTAMP_MILLIS = 253_402_300_799_999L
    }
}
