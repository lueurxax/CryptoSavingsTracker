package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import org.junit.jupiter.api.Test

class FundedDeltaAttributionCalculatorTest {
    private val calculator = FundedDeltaAttributionCalculator()

    @Test
    fun `shared partial deposit creates mutually exclusive goal deltas`() {
        val events = calculator.calculate(
            goalIds = setOf("goal-a", "goal-b"),
            transactions = listOf(transaction(id = "deposit", amount = 50.0, timestamp = 2_000L)),
            allocationHistory = listOf(
                history(id = "a-start", goalId = "goal-a", amount = 60.0, timestamp = 999L),
                history(id = "b-start", goalId = "goal-b", amount = 40.0, timestamp = 999L)
            ),
            startedAtMillis = 1_000L,
            nowMillis = 3_000L
        )

        assertThat(events.filter { it.source == FundedDeltaSource.TRANSACTION })
            .containsExactly(
                FundedDeltaAttribution(
                    goalId = "goal-a",
                    assetId = "shared-asset",
                    amount = 30.0,
                    timestampMillis = 2_000L,
                    source = FundedDeltaSource.TRANSACTION,
                    sourceId = "deposit",
                    comment = "deposit"
                ),
                FundedDeltaAttribution(
                    goalId = "goal-b",
                    assetId = "shared-asset",
                    amount = 20.0,
                    timestampMillis = 2_000L,
                    source = FundedDeltaSource.TRANSACTION,
                    sourceId = "deposit",
                    comment = "deposit"
                )
            )
        assertThat(events.sumOf { it.amount }).isEqualTo(50.0)
    }

    @Test
    fun `allocation changes are replayed and each later transaction is split by its active targets`() {
        val events = calculator.calculate(
            goalIds = setOf("goal-a", "goal-b"),
            transactions = listOf(
                transaction(id = "before-change", amount = 50.0, timestamp = 1_500L),
                transaction(id = "after-change", amount = 50.0, timestamp = 2_500L)
            ),
            allocationHistory = listOf(
                history(id = "a-start", goalId = "goal-a", amount = 60.0, timestamp = 999L),
                history(id = "b-start", goalId = "goal-b", amount = 40.0, timestamp = 999L),
                history(id = "a-change", goalId = "goal-a", amount = 20.0, timestamp = 2_000L),
                history(id = "b-change", goalId = "goal-b", amount = 80.0, timestamp = 2_000L)
            ),
            startedAtMillis = 1_000L,
            nowMillis = 3_000L
        )

        val transactionEvents = events
            .filter { it.source == FundedDeltaSource.TRANSACTION }
            .groupBy { it.sourceId }
        assertThat(transactionEvents.getValue("before-change").associate { it.goalId to it.amount })
            .containsExactly("goal-a", 30.0, "goal-b", 20.0)
        assertThat(transactionEvents.getValue("after-change").associate { it.goalId to it.amount })
            .containsExactly("goal-a", 10.0, "goal-b", 40.0)
        assertThat(
            events.filter { it.source == FundedDeltaSource.ALLOCATION_CHANGE }
                .associate { it.goalId to it.amount }
        ).containsExactly("goal-a", -20.0, "goal-b", 20.0)
    }

    @Test
    fun `reallocation cannot credit more contribution than the deposited balance`() {
        val events = calculator.calculate(
            goalIds = setOf("goal-a", "goal-b"),
            transactions = listOf(
                transaction(id = "before-change", amount = 50.0, timestamp = 1_500L),
                transaction(id = "after-change", amount = 50.0, timestamp = 2_500L)
            ),
            allocationHistory = listOf(
                history(id = "a-start", goalId = "goal-a", amount = 60.0, timestamp = 999L),
                history(id = "b-start", goalId = "goal-b", amount = 40.0, timestamp = 999L),
                history(id = "a-change", goalId = "goal-a", amount = 20.0, timestamp = 2_000L),
                history(id = "b-change", goalId = "goal-b", amount = 80.0, timestamp = 2_000L)
            ),
            startedAtMillis = 1_000L,
            nowMillis = 3_000L
        )

        assertThat(events.sumOf { it.amount }).isEqualTo(100.0)
        assertThat(
            events.groupBy { it.goalId }.mapValues { (_, rows) -> rows.sumOf { it.amount } }
        ).containsExactly("goal-a", 20.0, "goal-b", 80.0)
    }

    @Test
    fun `deposit above total targets leaves residue unattributed`() {
        val events = calculator.calculate(
            goalIds = setOf("goal-a", "goal-b"),
            transactions = listOf(transaction(id = "deposit", amount = 150.0, timestamp = 2_000L)),
            allocationHistory = listOf(
                history(id = "a-start", goalId = "goal-a", amount = 60.0, timestamp = 999L),
                history(id = "b-start", goalId = "goal-b", amount = 40.0, timestamp = 999L)
            ),
            startedAtMillis = 1_000L,
            nowMillis = 3_000L
        )

        assertThat(events.associate { it.goalId to it.amount })
            .containsExactly("goal-a", 60.0, "goal-b", 40.0)
        assertThat(events.sumOf { it.amount }).isEqualTo(100.0)
    }

    @Test
    fun `deposit after an unfunded withdrawal does not create contribution`() {
        val events = calculator.calculate(
            goalIds = setOf("goal-a"),
            transactions = listOf(
                transaction(id = "withdrawal", amount = -100.0, timestamp = 1_500L),
                transaction(id = "deposit", amount = 50.0, timestamp = 2_000L)
            ),
            allocationHistory = listOf(
                history(id = "a-start", goalId = "goal-a", amount = 100.0, timestamp = 999L)
            ),
            startedAtMillis = 1_000L,
            nowMillis = 3_000L
        )

        assertThat(events).isEmpty()
    }

    private fun transaction(id: String, amount: Double, timestamp: Long) = Transaction(
        id = id,
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
