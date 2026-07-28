package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.usecase.execution.FundedDeltaAttributionCalculator
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

class GoalContributionAttributionCalculatorTest {
    private val calculator = GoalContributionAttributionCalculator(
        fundedDeltaCalculator = FundedDeltaAttributionCalculator()
    )

    @Test
    fun `target goal receives only its funded delta from a shared asset`() {
        val allocations = listOf(
            allocation(id = "allocation-a", goalId = "goal-a", amount = 60.0),
            allocation(id = "allocation-b", goalId = "goal-b", amount = 40.0)
        )
        val histories = listOf(
            history(id = "history-a", goalId = "goal-a", amount = 60.0, timestamp = 1_000L),
            history(id = "history-b", goalId = "goal-b", amount = 40.0, timestamp = 1_000L)
        )

        val result = calculator.calculate(
            goalId = "goal-a",
            currentAllocations = allocations,
            transactions = listOf(transaction(amount = 50.0, timestamp = 2_000L)),
            allocationHistory = histories,
            nowMillis = 3_000L
        )

        assertThat(result).hasSize(1)
        assertThat(result.single().amount).isEqualTo(30.0)
    }

    @Test
    fun `current allocation without a matching latest history fails closed`() {
        val failure = assertThrows<UnprovenGoalContributionAttributionException> {
            calculator.calculate(
                goalId = "goal-a",
                currentAllocations = listOf(
                    allocation(id = "allocation-a", goalId = "goal-a", amount = 60.0)
                ),
                transactions = listOf(transaction(amount = 50.0, timestamp = 2_000L)),
                allocationHistory = emptyList(),
                nowMillis = 3_000L
            )
        }

        assertThat(failure).hasMessageThat().contains("attribution")
    }

    private fun allocation(id: String, goalId: String, amount: Double) = Allocation(
        id = id,
        assetId = "shared-asset",
        goalId = goalId,
        amount = amount,
        createdAt = 900L,
        lastModifiedAt = 1_000L
    )

    private fun transaction(amount: Double, timestamp: Long) = Transaction(
        id = "deposit",
        assetId = "shared-asset",
        amount = amount,
        dateMillis = timestamp,
        source = TransactionSource.MANUAL,
        externalId = null,
        counterparty = null,
        comment = "deposit",
        createdAt = timestamp
    )

    private fun history(id: String, goalId: String, amount: Double, timestamp: Long) =
        AllocationHistory(
            id = id,
            assetId = "shared-asset",
            goalId = goalId,
            amount = amount,
            monthLabel = "2026-07",
            timestamp = timestamp,
            createdAt = timestamp
        )
}
