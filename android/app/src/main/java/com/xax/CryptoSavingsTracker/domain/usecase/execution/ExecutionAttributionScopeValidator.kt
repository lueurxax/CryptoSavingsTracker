package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import kotlin.math.abs
import kotlin.math.max

internal object ExecutionAttributionScopeValidator {
    fun requiredAssetIds(
        goalIds: Set<String>,
        currentAllocations: List<Allocation>,
        allocationHistory: List<AllocationHistory>,
        startedAtMillis: Long,
        nowMillis: Long
    ): Set<String> {
        if (goalIds.isEmpty() || startedAtMillis <= 0L || nowMillis < startedAtMillis) {
            return emptySet()
        }

        val snapshotAllocations = currentAllocations.filter { it.goalId in goalIds }
        val snapshotHistory = allocationHistory.filter { it.goalId in goalIds }
        requireProvableCurrentState(
            currentAllocations = snapshotAllocations,
            allocationHistory = snapshotHistory,
            nowMillis = nowMillis
        )
        val requiredAssetIds = buildSet {
            snapshotAllocations.mapTo(this) { it.assetId }
            snapshotHistory
                .asSequence()
                .filter { it.timestamp <= nowMillis }
                .groupBy { it.assetId to it.goalId }
                .asSequence()
                .filter { (_, histories) ->
                    histories.any { it.timestamp >= startedAtMillis } ||
                        histories
                            .asSequence()
                            .filter { it.timestamp < startedAtMillis }
                            .maxWithOrNull(
                                compareBy<AllocationHistory>({ it.timestamp }, { it.createdAt }, { it.id })
                            )
                            ?.amount
                            ?.let { it > ATTRIBUTION_EPSILON } == true
                }
                .mapTo(this) { (key, _) -> key.first }
        }
        val relevantAllocations = currentAllocations.filter { it.assetId in requiredAssetIds }
        val relevantHistory = allocationHistory.filter { it.assetId in requiredAssetIds }
        requireProvableCurrentState(
            currentAllocations = relevantAllocations,
            allocationHistory = relevantHistory,
            nowMillis = nowMillis
        )

        return requiredAssetIds
    }

    fun requireCompleteRateMatrix(
        requiredAssetIds: Set<String>,
        snapshotCurrencies: Set<String>,
        assetRates: List<ExecutionAssetRate>
    ) {
        val keys = assetRates.map { rate ->
            if (
                rate.assetId.isBlank() ||
                rate.snapshotCurrency.isBlank() ||
                !rate.rate.isFinite() ||
                rate.rate <= 0.0 ||
                rate.capturedAtMillis < 0L
            ) {
                throw UnprovenExecutionContributionAttributionException(
                    "Execution contribution attribution is unavailable because the FX snapshot has invalid provenance"
                )
            }
            rate.assetId to rate.snapshotCurrency.uppercase()
        }
        if (keys.size != keys.toSet().size) {
            throw UnprovenExecutionContributionAttributionException(
                "Execution contribution attribution is unavailable because the FX snapshot is ambiguous"
            )
        }

        val availableKeys = keys.toSet()
        for (assetId in requiredAssetIds) {
            for (snapshotCurrency in snapshotCurrencies) {
                if ((assetId to snapshotCurrency.uppercase()) !in availableKeys) {
                    throw MissingExecutionAssetRateException(assetId, snapshotCurrency)
                }
            }
        }
    }

    /**
     * Execution progress can only attribute funded deltas when every required
     * asset has a complete transaction ledger. Addressed assets currently have
     * no persisted exhaustive-ledger proof, so treating their locally cached
     * provider rows as complete would silently under/over-count contributions.
     *
     * Keep execution fail-closed until a provider refresh can persist and
     * re-check an exhaustive proof atomically with start/progress/completion.
     */
    fun requireProvableTransactionLedger(
        requiredAssetIds: Set<String>,
        knownAssetIds: Set<String>,
        addressedAssetIds: Set<String>,
        onChainTransactionAssetIds: Set<String> = emptySet()
    ) {
        val missingAssetIds = requiredAssetIds - knownAssetIds
        if (missingAssetIds.isNotEmpty()) {
            throw UnprovenExecutionContributionAttributionException(
                "Execution contribution attribution is unavailable because required assets are missing"
            )
        }
        val unprovenLedgerAssetIds =
            requiredAssetIds.intersect(addressedAssetIds + onChainTransactionAssetIds)
        if (unprovenLedgerAssetIds.isNotEmpty()) {
            throw UnprovenExecutionContributionAttributionException(
                "Execution contribution attribution is unavailable because the on-chain ledger is not proven complete"
            )
        }
    }

    private fun requireProvableCurrentState(
        currentAllocations: List<Allocation>,
        allocationHistory: List<AllocationHistory>,
        nowMillis: Long
    ) {
        if (
            currentAllocations.any {
                !it.amount.isFinite() ||
                    it.amount <= 0.0 ||
                    it.createdAt < 0L ||
                    it.lastModifiedAt < 0L ||
                    it.lastModifiedAt > nowMillis
            } ||
            allocationHistory.any {
                !it.amount.isFinite() ||
                    it.amount < 0.0 ||
                    it.timestamp < 0L ||
                    it.timestamp > nowMillis ||
                    it.createdAt < 0L
            }
        ) {
            throw UnprovenExecutionContributionAttributionException()
        }

        val allocationsByKey = currentAllocations.groupBy { it.assetId to it.goalId }
        if (allocationsByKey.any { (_, values) -> values.size != 1 }) {
            throw UnprovenExecutionContributionAttributionException()
        }
        val latestHistoryByKey = allocationHistory
            .groupBy { it.assetId to it.goalId }
            .mapValues { (_, histories) ->
                histories.maxWith(
                    compareBy<AllocationHistory>({ it.timestamp }, { it.createdAt }, { it.id })
                )
            }

        for ((key, allocations) in allocationsByKey) {
            val current = allocations.single()
            val latest = latestHistoryByKey[key]
                ?: throw UnprovenExecutionContributionAttributionException()
            if (!amountsEqual(current.amount, latest.amount)) {
                throw UnprovenExecutionContributionAttributionException()
            }
        }
        for ((key, latest) in latestHistoryByKey) {
            val current = allocationsByKey[key]?.singleOrNull()
            if (latest.amount > ATTRIBUTION_EPSILON && current == null) {
                throw UnprovenExecutionContributionAttributionException()
            }
        }
    }

    private fun amountsEqual(first: Double, second: Double): Boolean {
        val scale = max(1.0, max(abs(first), abs(second)))
        return abs(first - second) <= ATTRIBUTION_EPSILON * scale
    }

    private const val ATTRIBUTION_EPSILON = 1e-9
}

class UnprovenExecutionContributionAttributionException(
    message: String =
        "Execution contribution attribution is unavailable because allocation history is incomplete"
) : IllegalStateException(message)
