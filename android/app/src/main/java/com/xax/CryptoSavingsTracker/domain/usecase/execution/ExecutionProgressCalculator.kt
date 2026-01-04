package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import kotlin.math.max

/**
 * Calculates execution progress by deriving contribution events from transactions
 * and allocation history changes. This matches the iOS ExecutionProgressCalculator
 * approach of tracking actual contribution deltas rather than comparing static
 * funded amounts.
 */
class ExecutionProgressCalculator {
    private data class AllocationKey(val assetId: String, val goalId: String)

    private data class HistoryCandidate(
        val amount: Double,
        val timestamp: Long,
        val createdAt: Long
    )

    private data class TimestampEvent(
        val timestamp: Long,
        val transactionDelta: Double?, // null if no transaction at this timestamp
        val allocationUpdates: Map<String, Double>? // goalId -> new target
    )

    /**
     * Calculate progress for each goal snapshot.
     * Returns contribution-based progress that tracks actual transaction deltas
     * that benefit each goal (matching iOS behavior).
     */
    fun calculateForSnapshots(
        snapshots: List<ExecutionSnapshot>,
        transactions: List<Transaction>,
        allocationHistory: List<AllocationHistory>,
        startedAtMillis: Long,
        nowMillis: Long = System.currentTimeMillis()
    ): List<ExecutionGoalProgress> {
        val goalIds = snapshots.map { it.goalId }.toSet()
        if (goalIds.isEmpty() || startedAtMillis <= 0L) {
            return snapshots.map { snapshot ->
                ExecutionGoalProgress(
                    snapshot = snapshot,
                    contributed = 0.0,
                    plannedAmount = snapshot.requiredAmount,
                    isFulfilled = false
                )
            }
        }

        // Calculate contributions per goal by processing assets
        val contributionsByGoal = mutableMapOf<String, Double>()

        // Group allocation history by asset
        val relevantHistory = allocationHistory.filter { it.goalId in goalIds }
        val historyByAsset = relevantHistory.groupBy { it.assetId }

        // Get unique asset IDs from both transactions and allocation history
        val assetIds = (transactions.map { it.assetId } + historyByAsset.keys).toSet()

        for (assetId in assetIds) {
            val assetTransactions = transactions.filter { it.assetId == assetId && it.dateMillis <= nowMillis }
            val assetHistories = historyByAsset[assetId] ?: emptyList()

            calculateAssetContributions(
                assetId = assetId,
                assetTransactions = assetTransactions,
                assetHistories = assetHistories,
                goalIds = goalIds,
                startedAtMillis = startedAtMillis,
                nowMillis = nowMillis,
                contributionsByGoal = contributionsByGoal
            )
        }

        return snapshots.map { snapshot ->
            val contributed = contributionsByGoal[snapshot.goalId] ?: 0.0
            val plannedAmount = snapshot.requiredAmount
            val isFulfilled = plannedAmount > 0 && contributed >= plannedAmount
            ExecutionGoalProgress(
                snapshot = snapshot,
                contributed = contributed,
                plannedAmount = plannedAmount,
                isFulfilled = isFulfilled
            )
        }.sortedBy { it.snapshot.goalName }
    }

    /**
     * Process a single asset to calculate contribution deltas for each goal.
     * This matches the iOS approach of replaying transactions and allocation
     * changes chronologically to derive contribution events.
     */
    private fun calculateAssetContributions(
        assetId: String,
        assetTransactions: List<Transaction>,
        assetHistories: List<AllocationHistory>,
        goalIds: Set<String>,
        startedAtMillis: Long,
        nowMillis: Long,
        contributionsByGoal: MutableMap<String, Double>
    ) {
        // Compute balance at start by summing all transactions before start
        val balanceAtStart = assetTransactions
            .filter { it.dateMillis < startedAtMillis }
            .sumOf { it.amount }
            .coerceAtLeast(0.0)

        // Determine allocation targets at start (latest history <= startedAtMillis for each goal)
        val targetsByGoalAtStart = mutableMapOf<String, Double>()
        for (goalId in goalIds) {
            val latestBefore = assetHistories
                .filter { it.goalId == goalId && it.timestamp < startedAtMillis }
                .maxByOrNull { if (it.timestamp != 0L) it.timestamp else it.createdAt }
            if (latestBefore != null) {
                targetsByGoalAtStart[goalId] = latestBefore.amount.coerceAtLeast(0.0)
            }
        }

        // If no history found for a goal but asset has current allocation to it,
        // use the current allocation as the baseline (fallback for missing history)
        // This is handled by the allocation history lookup at current time

        // Current state tracking
        var balance = balanceAtStart
        var targetsByGoal = targetsByGoalAtStart.toMutableMap()
        var fundedByGoal = computeFundedAmounts(balance, targetsByGoal)

        // Collect events during the execution window
        val transactionsByTimestamp = assetTransactions
            .filter { it.dateMillis in startedAtMillis..nowMillis }
            .groupBy { it.dateMillis }
            .mapValues { (_, txs) -> txs.sumOf { it.amount } }

        val allocationUpdatesByTimestamp = mutableMapOf<Long, MutableMap<String, Double>>()
        for (history in assetHistories) {
            if (history.timestamp !in startedAtMillis..nowMillis) continue
            if (history.goalId !in goalIds) continue

            val updates = allocationUpdatesByTimestamp.getOrPut(history.timestamp) { mutableMapOf() }
            val existingCreatedAt = updates[history.goalId]?.let { existing ->
                assetHistories.find {
                    it.goalId == history.goalId &&
                    it.timestamp == history.timestamp &&
                    it.amount == existing
                }?.createdAt ?: 0L
            } ?: 0L

            if (history.createdAt > existingCreatedAt) {
                updates[history.goalId] = history.amount.coerceAtLeast(0.0)
            }
        }

        // Process events chronologically
        val allTimestamps = (transactionsByTimestamp.keys + allocationUpdatesByTimestamp.keys).sorted()

        for (timestamp in allTimestamps) {
            // Apply allocation updates first
            allocationUpdatesByTimestamp[timestamp]?.let { updates ->
                for ((goalId, newTarget) in updates) {
                    targetsByGoal[goalId] = newTarget
                }
                val newFunded = computeFundedAmounts(balance, targetsByGoal)
                applyFundedDeltas(fundedByGoal, newFunded, contributionsByGoal)
                fundedByGoal = newFunded
            }

            // Then apply transaction
            transactionsByTimestamp[timestamp]?.let { txDelta ->
                balance = (balance + txDelta).coerceAtLeast(0.0)
                val newFunded = computeFundedAmounts(balance, targetsByGoal)
                applyFundedDeltas(fundedByGoal, newFunded, contributionsByGoal)
                fundedByGoal = newFunded
            }
        }
    }

    /**
     * Compute funded amounts for each goal given current balance and targets.
     * If balance >= total targets, each goal gets its full target.
     * Otherwise, pro-rate based on target proportions.
     */
    private fun computeFundedAmounts(
        balance: Double,
        targetsByGoal: Map<String, Double>
    ): Map<String, Double> {
        if (balance <= 0 || targetsByGoal.isEmpty()) {
            return targetsByGoal.mapValues { 0.0 }
        }

        val totalTargets = targetsByGoal.values.sum()
        if (totalTargets <= 0) return emptyMap()

        return if (balance >= totalTargets) {
            targetsByGoal.toMap()
        } else {
            targetsByGoal.mapValues { (_, target) ->
                val ratio = target / totalTargets
                balance * ratio
            }
        }
    }

    /**
     * Calculate deltas between old and new funded amounts,
     * and add positive deltas to contribution totals.
     */
    private fun applyFundedDeltas(
        oldFunded: Map<String, Double>,
        newFunded: Map<String, Double>,
        contributionsByGoal: MutableMap<String, Double>
    ) {
        val allGoals = oldFunded.keys + newFunded.keys
        for (goalId in allGoals) {
            val oldAmount = oldFunded[goalId] ?: 0.0
            val newAmount = newFunded[goalId] ?: 0.0
            val delta = newAmount - oldAmount
            // Only count positive deltas as contributions (deposits, not withdrawals)
            if (delta > 0.0001) {
                contributionsByGoal[goalId] = (contributionsByGoal[goalId] ?: 0.0) + delta
            }
        }
    }
}
