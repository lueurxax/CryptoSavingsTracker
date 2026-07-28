package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.usecase.execution.FundedDeltaAttribution
import com.xax.CryptoSavingsTracker.domain.usecase.execution.FundedDeltaAttributionCalculator
import javax.inject.Inject
import kotlin.math.abs
import kotlin.math.max

/**
 * Selects the complete shared-asset allocation graph needed to prove a
 * goal-specific contribution attribution. Current allocations must agree with
 * their latest history rows; otherwise historical attribution is unavailable.
 */
class GoalContributionAttributionCalculator @Inject constructor(
    private val fundedDeltaCalculator: FundedDeltaAttributionCalculator
) {
    fun calculate(
        goalId: String,
        currentAllocations: List<Allocation>,
        transactions: List<Transaction>,
        allocationHistory: List<AllocationHistory>,
        nowMillis: Long = System.currentTimeMillis()
    ): List<FundedDeltaAttribution> {
        val relevantAssetIds = buildSet {
            currentAllocations.filterTo(mutableListOf()) { it.goalId == goalId }
                .mapTo(this) { it.assetId }
            allocationHistory.filterTo(mutableListOf()) { it.goalId == goalId }
                .mapTo(this) { it.assetId }
        }
        if (relevantAssetIds.isEmpty()) return emptyList()

        val relevantAllocations = currentAllocations.filter { it.assetId in relevantAssetIds }
        val relevantHistory = allocationHistory.filter { it.assetId in relevantAssetIds }
        requireProvableCurrentState(
            currentAllocations = relevantAllocations,
            allocationHistory = relevantHistory,
            nowMillis = nowMillis
        )

        val relevantTransactions = transactions.filter { it.assetId in relevantAssetIds }
        val attributionGoalIds = buildSet {
            add(goalId)
            relevantAllocations.mapTo(this) { it.goalId }
            relevantHistory.mapTo(this) { it.goalId }
        }
        val firstTimelineTimestamp = (
            relevantTransactions.map { it.dateMillis } +
                relevantHistory.map { it.timestamp }
            )
            .minOrNull()
            ?.coerceAtLeast(1L)
            ?: return emptyList()

        return fundedDeltaCalculator.calculate(
            goalIds = attributionGoalIds,
            transactions = relevantTransactions,
            allocationHistory = relevantHistory,
            startedAtMillis = firstTimelineTimestamp,
            nowMillis = nowMillis
        ).filter { it.goalId == goalId }
    }

    private fun requireProvableCurrentState(
        currentAllocations: List<Allocation>,
        allocationHistory: List<AllocationHistory>,
        nowMillis: Long
    ) {
        if (
            currentAllocations.any {
                !it.amount.isFinite() || it.amount <= 0.0 || it.lastModifiedAt > nowMillis
            } ||
            allocationHistory.any {
                !it.amount.isFinite() ||
                    it.amount < 0.0 ||
                    it.timestamp < 0L ||
                    it.timestamp > nowMillis ||
                    it.createdAt < 0L
            }
        ) {
            throw UnprovenGoalContributionAttributionException()
        }

        val allocationsByKey = currentAllocations.groupBy { it.assetId to it.goalId }
        if (allocationsByKey.any { (_, values) -> values.size != 1 }) {
            throw UnprovenGoalContributionAttributionException()
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
                ?: throw UnprovenGoalContributionAttributionException()
            if (!amountsEqual(current.amount, latest.amount)) {
                throw UnprovenGoalContributionAttributionException()
            }
        }
        for ((key, latest) in latestHistoryByKey) {
            val current = allocationsByKey[key]?.singleOrNull()
            if (latest.amount > ATTRIBUTION_EPSILON && current == null) {
                throw UnprovenGoalContributionAttributionException()
            }
        }
    }

    private fun amountsEqual(first: Double, second: Double): Boolean {
        val scale = max(1.0, max(abs(first), abs(second)))
        return abs(first - second) <= ATTRIBUTION_EPSILON * scale
    }

    private companion object {
        const val ATTRIBUTION_EPSILON = 1e-9
    }
}

class UnprovenGoalContributionAttributionException : IllegalStateException(
    "Goal contribution attribution is unavailable because allocation history is incomplete"
)
