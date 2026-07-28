package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import org.junit.jupiter.api.Test

class ExecutionContributionCalculatorUseCaseTest {
    @Test
    fun `close month suggestion agrees with frozen progress rate when live FX diverges`() {
        val startedAt = 1_000L
        val frozenRates = listOf(
            ExecutionAssetRate(
                assetId = "btc-asset",
                snapshotCurrency = "USD",
                rate = 100.0,
                capturedAtMillis = startedAt
            )
        )
        val progress = ExecutionProgressCalculator().calculateForSnapshots(
            snapshots = listOf(snapshot(requiredAmount = 200.0)),
            transactions = listOf(transaction(amount = 1.0, dateMillis = startedAt + 1L)),
            allocationHistory = listOf(history(amount = 2.0, timestamp = startedAt - 1L)),
            assetRates = frozenRates,
            startedAtMillis = startedAt,
            nowMillis = startedAt + 2L
        ).single()

        val suggestion = ExecutionContributionCalculatorUseCase()
            .remainingToCloseInAsset(
                goalProgress = progress,
                assetId = "btc-asset",
                assetRates = frozenRates
            )

        // Frozen 1 BTC = 100 USD yields 1 BTC. A live 1 BTC = 200 USD quote
        // would incorrectly yield 0.5 BTC.
        assertThat(progress.contributed).isEqualTo(100.0)
        assertThat(suggestion).isEqualTo(1.0)
    }

    @Test
    fun `missing frozen asset rate fails closed`() {
        val progress = ExecutionGoalProgress(
            snapshot = snapshot(requiredAmount = 100.0),
            contributed = 0.0,
            plannedAmount = 100.0,
            isFulfilled = false
        )

        val suggestion = ExecutionContributionCalculatorUseCase()
            .remainingToCloseInAsset(
                goalProgress = progress,
                assetId = "btc-asset",
                assetRates = emptyList()
            )

        assertThat(suggestion).isNull()
    }

    @Test
    fun `duplicate or non-finite frozen asset rate fails closed`() {
        val progress = ExecutionGoalProgress(
            snapshot = snapshot(requiredAmount = 100.0),
            contributed = 0.0,
            plannedAmount = 100.0,
            isFulfilled = false
        )
        val duplicateRates = listOf(
            ExecutionAssetRate("btc-asset", "USD", 100.0),
            ExecutionAssetRate("btc-asset", "usd", 200.0)
        )
        val corruptRates = listOf(
            ExecutionAssetRate("btc-asset", "USD", Double.NaN)
        )
        val calculator = ExecutionContributionCalculatorUseCase()

        assertThat(
            calculator.remainingToCloseInAsset(progress, "btc-asset", duplicateRates)
        ).isNull()
        assertThat(
            calculator.remainingToCloseInAsset(progress, "btc-asset", corruptRates)
        ).isNull()
    }

    private fun snapshot(requiredAmount: Double) = ExecutionSnapshot(
        id = "snapshot-1",
        executionRecordId = "record-1",
        goalId = "goal-1",
        goalName = "USD goal",
        currency = "USD",
        targetAmount = 1_000.0,
        currentTotalAtStart = 0.0,
        requiredAmount = requiredAmount,
        isProtected = false,
        isSkipped = false,
        customAmount = null,
        createdAtMillis = 1_000L
    )

    private fun transaction(amount: Double, dateMillis: Long) = Transaction(
        id = "transaction-1",
        assetId = "btc-asset",
        amount = amount,
        dateMillis = dateMillis,
        source = TransactionSource.MANUAL,
        externalId = null,
        counterparty = null,
        comment = null,
        createdAt = dateMillis
    )

    private fun history(amount: Double, timestamp: Long) = AllocationHistory(
        id = "history-1",
        assetId = "btc-asset",
        goalId = "goal-1",
        amount = amount,
        monthLabel = "2026-07",
        timestamp = timestamp,
        createdAt = timestamp
    )
}
