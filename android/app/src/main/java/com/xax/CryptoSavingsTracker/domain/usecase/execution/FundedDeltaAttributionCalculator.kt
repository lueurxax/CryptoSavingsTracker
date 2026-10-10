package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import javax.inject.Inject

enum class FundedDeltaSource {
    ALLOCATION_CHANGE,
    TRANSACTION
}

data class FundedDeltaAttribution(
    val goalId: String,
    val assetId: String,
    val amount: Double,
    val timestampMillis: Long,
    val source: FundedDeltaSource,
    val sourceId: String,
    val comment: String?
)

/**
 * Replays asset balances and allocation targets to attribute signed funded
 * deltas to each goal. Both execution progress and goal dashboards use
 * this timeline so a shared transaction is never copied wholesale to every
 * goal that references the asset.
 */
class FundedDeltaAttributionCalculator @Inject constructor() {
    fun calculate(
        goalIds: Set<String>,
        transactions: List<Transaction>,
        allocationHistory: List<AllocationHistory>,
        startedAtMillis: Long,
        nowMillis: Long = System.currentTimeMillis()
    ): List<FundedDeltaAttribution> {
        if (goalIds.isEmpty() || startedAtMillis <= 0L || nowMillis < startedAtMillis) {
            return emptyList()
        }

        require(transactions.all { it.amount.isFinite() && it.dateMillis >= 0L }) {
            "Contribution attribution contains an invalid transaction"
        }
        require(
            allocationHistory.all {
                it.amount.isFinite() &&
                    it.amount >= 0.0 &&
                    it.timestamp >= 0L &&
                    it.createdAt >= 0L
            }
        ) {
            "Contribution attribution contains invalid allocation history"
        }

        val relevantHistory = allocationHistory.filter { it.goalId in goalIds }
        val historyByAsset = relevantHistory.groupBy { it.assetId }
        val assetIds = (transactions.map { it.assetId } + historyByAsset.keys).toSortedSet()
        val events = mutableListOf<FundedDeltaAttribution>()

        for (assetId in assetIds) {
            calculateAssetDeltas(
                assetId = assetId,
                transactions = transactions.filter {
                    it.assetId == assetId && it.dateMillis <= nowMillis
                },
                allocationHistory = historyByAsset[assetId].orEmpty(),
                goalIds = goalIds,
                startedAtMillis = startedAtMillis,
                nowMillis = nowMillis,
                destination = events
            )
        }

        return events.sortedWith(
            compareBy<FundedDeltaAttribution>(
                { it.timestampMillis },
                { it.source.ordinal },
                { it.assetId },
                { it.goalId },
                { it.sourceId }
            )
        )
    }

    private fun calculateAssetDeltas(
        assetId: String,
        transactions: List<Transaction>,
        allocationHistory: List<AllocationHistory>,
        goalIds: Set<String>,
        startedAtMillis: Long,
        nowMillis: Long,
        destination: MutableList<FundedDeltaAttribution>
    ) {
        val balanceAtStart = transactions
            .asSequence()
            .filter { it.dateMillis < startedAtMillis }
            .sumOf { it.amount }
            .also { require(it.isFinite()) { "Contribution attribution balance overflowed" } }

        val targetsAtStart = goalIds.mapNotNull { goalId ->
            allocationHistory
                .asSequence()
                .filter { it.goalId == goalId && it.timestamp < startedAtMillis }
                .maxWithOrNull(
                    compareBy<AllocationHistory>({ it.timestamp }, { it.createdAt }, { it.id })
                )
                ?.let { goalId to it.amount.coerceAtLeast(0.0) }
        }.toMap(mutableMapOf())

        var balance = balanceAtStart
        val targetsByGoal = targetsAtStart.toMutableMap()
        var fundedByGoal = computeFundedAmounts(balance, targetsByGoal)

        val transactionsByTimestamp = transactions
            .filter { it.dateMillis in startedAtMillis..nowMillis }
            .groupBy { it.dateMillis }
        val allocationUpdatesByTimestamp = allocationHistory
            .filter { it.timestamp in startedAtMillis..nowMillis && it.goalId in goalIds }
            .groupBy { it.timestamp }
            .mapValues { (_, historiesAtTimestamp) ->
                historiesAtTimestamp
                    .groupBy { it.goalId }
                    .mapValues { (_, candidates) ->
                        candidates.maxWith(
                            compareBy<AllocationHistory>({ it.createdAt }, { it.id })
                        )
                    }
            }

        val timestamps = (transactionsByTimestamp.keys + allocationUpdatesByTimestamp.keys).sorted()
        for (timestamp in timestamps) {
            allocationUpdatesByTimestamp[timestamp]?.let { updates ->
                updates.forEach { (goalId, history) ->
                    targetsByGoal[goalId] = history.amount.coerceAtLeast(0.0)
                }
                val newFunded = computeFundedAmounts(balance, targetsByGoal)
                appendSignedDeltas(
                    assetId = assetId,
                    timestamp = timestamp,
                    source = FundedDeltaSource.ALLOCATION_CHANGE,
                    sourceId = "allocation:$assetId:$timestamp",
                    comment = null,
                    oldFunded = fundedByGoal,
                    newFunded = newFunded,
                    destination = destination
                )
                fundedByGoal = newFunded
            }

            transactionsByTimestamp[timestamp]?.let { transactionsAtTimestamp ->
                val transactionDelta = transactionsAtTimestamp
                    .sumOf { it.amount }
                    .also { require(it.isFinite()) { "Contribution attribution delta overflowed" } }
                balance = (balance + transactionDelta)
                    .also { require(it.isFinite()) { "Contribution attribution balance overflowed" } }
                val newFunded = computeFundedAmounts(balance, targetsByGoal)
                val singleTransaction = transactionsAtTimestamp.singleOrNull()
                appendSignedDeltas(
                    assetId = assetId,
                    timestamp = timestamp,
                    source = FundedDeltaSource.TRANSACTION,
                    sourceId = singleTransaction?.id ?: "transactions:$assetId:$timestamp",
                    comment = singleTransaction?.comment,
                    oldFunded = fundedByGoal,
                    newFunded = newFunded,
                    destination = destination
                )
                fundedByGoal = newFunded
            }
        }
    }

    private fun computeFundedAmounts(
        balance: Double,
        targetsByGoal: Map<String, Double>
    ): Map<String, Double> {
        if (balance <= 0.0 || targetsByGoal.isEmpty()) {
            return targetsByGoal.mapValues { 0.0 }
        }
        val totalTargets = targetsByGoal.values
            .sum()
            .also { require(it.isFinite()) { "Contribution attribution targets overflowed" } }
        if (totalTargets <= 0.0) return emptyMap()

        return if (balance >= totalTargets) {
            targetsByGoal.toMap()
        } else {
            targetsByGoal.mapValues { (_, target) -> balance * (target / totalTargets) }
        }
    }

    private fun appendSignedDeltas(
        assetId: String,
        timestamp: Long,
        source: FundedDeltaSource,
        sourceId: String,
        comment: String?,
        oldFunded: Map<String, Double>,
        newFunded: Map<String, Double>,
        destination: MutableList<FundedDeltaAttribution>
    ) {
        for (goalId in (oldFunded.keys + newFunded.keys).sorted()) {
            val delta = (newFunded[goalId] ?: 0.0) - (oldFunded[goalId] ?: 0.0)
            // Raw units can represent valuable tiny crypto contributions.
            if (delta != 0.0) {
                destination += FundedDeltaAttribution(
                    goalId = goalId,
                    assetId = assetId,
                    amount = delta,
                    timestampMillis = timestamp,
                    source = source,
                    sourceId = sourceId,
                    comment = comment
                )
            }
        }
    }

}
