package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import org.junit.jupiter.api.Test

class ExecutionModelsTest {
    @Test
    fun `overall progress averages dimensionless goal completion across currencies`() {
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
        val usdGoal = progress(
            recordId = record.id,
            goalId = "usd-goal",
            currency = "USD",
            planned = 100.0,
            contributed = 100.0
        )
        val btcGoal = progress(
            recordId = record.id,
            goalId = "btc-goal",
            currency = "BTC",
            planned = 1.0,
            contributed = 0.0
        )

        val session = ExecutionSession(record, listOf(usdGoal, btcGoal))

        assertThat(session.overallProgress).isEqualTo(50.0)
    }

    private fun progress(
        recordId: String,
        goalId: String,
        currency: String,
        planned: Double,
        contributed: Double
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
            contributed = contributed,
            plannedAmount = planned,
            isFulfilled = contributed >= planned
        )
    }
}
