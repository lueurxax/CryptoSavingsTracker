package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import kotlin.math.max

class ExecutionProgressCalculator {
    private data class AllocationKey(val assetId: String, val goalId: String)

    private data class SnapshotCandidate(
        val amount: Double,
        val timestamp: Long,
        val createdAt: Long
    )

    fun calculateForSnapshots(
        snapshots: List<ExecutionSnapshot>,
        transactions: List<Transaction>,
        allocationHistory: List<AllocationHistory>,
        startedAtMillis: Long,
        nowMillis: Long = System.currentTimeMillis()
    ): List<ExecutionGoalProgress> {
        val goalIds = snapshots.map { it.goalId }.toSet()
        val manualTransactions = transactions
            .filter { it.source == TransactionSource.MANUAL }
            .filter { it.dateMillis <= nowMillis }

        val baselineBalancesByAsset = manualTransactions
            .filter { it.dateMillis < startedAtMillis }
            .groupBy { it.assetId }
            .mapValues { (_, txs) -> txs.sumOf { it.amount } }

        val currentBalancesByAsset = manualTransactions
            .groupBy { it.assetId }
            .mapValues { (_, txs) -> txs.sumOf { it.amount } }

        val relevantHistory = allocationHistory.filter { it.goalId in goalIds }
        val baselineTargets = targetsAtCutoff(relevantHistory, cutoffMillis = startedAtMillis)
        val currentTargets = targetsAtCutoff(relevantHistory, cutoffMillis = nowMillis + 1)

        val baselineFunded = fundedByGoal(
            targets = baselineTargets,
            balancesByAsset = baselineBalancesByAsset
        )
        val currentFunded = fundedByGoal(
            targets = currentTargets,
            balancesByAsset = currentBalancesByAsset
        )

        return snapshots.map { snapshot ->
            val baseline = baselineFunded[snapshot.goalId] ?: 0.0
            val current = currentFunded[snapshot.goalId] ?: 0.0
            ExecutionGoalProgress(
                snapshot = snapshot,
                baselineFunded = baseline,
                currentFunded = current,
                deltaSinceStart = current - baseline
            )
        }.sortedBy { it.snapshot.goalName }
    }

    private fun targetsAtCutoff(
        histories: List<AllocationHistory>,
        cutoffMillis: Long
    ): Map<AllocationKey, Double> {
        val grouped = mutableMapOf<AllocationKey, SnapshotCandidate>()
        for (history in histories) {
            if (history.timestamp >= cutoffMillis) continue
            val key = AllocationKey(assetId = history.assetId, goalId = history.goalId)
            val candidate = SnapshotCandidate(
                amount = history.amount,
                timestamp = history.timestamp,
                createdAt = history.createdAt
            )

            val existing = grouped[key]
            if (existing == null) {
                grouped[key] = candidate
            } else {
                val shouldReplace = candidate.timestamp > existing.timestamp ||
                    (candidate.timestamp == existing.timestamp && candidate.createdAt > existing.createdAt)
                if (shouldReplace) grouped[key] = candidate
            }
        }

        return grouped.mapValues { it.value.amount }
    }

    private fun fundedByGoal(
        targets: Map<AllocationKey, Double>,
        balancesByAsset: Map<String, Double>
    ): Map<String, Double> {
        val targetsByAsset = targets.entries.groupBy { it.key.assetId }
        val fundedByGoal = mutableMapOf<String, Double>()

        for ((assetId, entries) in targetsByAsset) {
            val balance = max(0.0, balancesByAsset[assetId] ?: 0.0)
            val positiveTargets = entries.map { (it.value).coerceAtLeast(0.0) }
            val totalAllocated = positiveTargets.sum()
            if (totalAllocated <= 0.0 || balance <= 0.0) continue

            val ratio = if (balance >= totalAllocated) 1.0 else balance / totalAllocated

            for (entry in entries) {
                val goalId = entry.key.goalId
                val target = entry.value.coerceAtLeast(0.0)
                if (target == 0.0) continue
                val funded = target * ratio
                fundedByGoal[goalId] = (fundedByGoal[goalId] ?: 0.0) + funded
            }
        }

        return fundedByGoal
    }
}

