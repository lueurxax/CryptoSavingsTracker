package com.xax.CryptoSavingsTracker.presentation.execution.components

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionGoalProgress
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import org.junit.jupiter.api.Test

class ProgressHeaderCardTest {
    @Test
    fun `mixed goal currencies never receive a default USD total label`() {
        val record = ExecutionRecord(
            id = "record-1",
            planId = "plan-1",
            monthLabel = "2026-07",
            status = ExecutionStatus.EXECUTING,
            startedAtMillis = 1_000L,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = 1_000L,
            updatedAtMillis = 1_000L
        )
        val session = ExecutionSession(
            record = record,
            goals = listOf(
                progress(record.id, "usd", "USD", 100.0),
                progress(record.id, "btc", "BTC", 1.0)
            )
        )

        assertThat(executionPlannedTotalLabel(session)).isEqualTo("Mixed currencies")
    }

    private fun progress(
        recordId: String,
        goalId: String,
        currency: String,
        planned: Double
    ): ExecutionGoalProgress {
        return ExecutionGoalProgress(
            snapshot = ExecutionSnapshot(
                id = "snapshot-$goalId",
                executionRecordId = recordId,
                goalId = goalId,
                goalName = goalId,
                currency = currency,
                targetAmount = planned,
                currentTotalAtStart = 0.0,
                requiredAmount = planned,
                isProtected = false,
                isSkipped = false,
                customAmount = null,
                createdAtMillis = 1_000L
            ),
            contributed = 0.0,
            plannedAmount = planned,
            isFulfilled = false
        )
    }
}
