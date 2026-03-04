package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.CycleConflictReason
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.model.PlanningSource
import com.xax.CryptoSavingsTracker.domain.model.UiCycleState
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import io.mockk.mockk
import org.junit.jupiter.api.Test

class MonthlyCycleStateResolverUseCaseTest {

    private val recordRepository = mockk<ExecutionRecordRepository>(relaxed = true)
    private val resolver = MonthlyCycleStateResolverUseCase(recordRepository)

    @Test
    fun resolve_returnsExecuting_whenActiveRecordExists() {
        val now = 1_700_000_000_000L
        val state = resolver.resolve(
            records = listOf(
                record(
                    month = "2026-03",
                    status = ExecutionStatus.EXECUTING,
                    startedAtMillis = now - 60_000,
                    canUndoUntilMillis = now + 60_000
                )
            ),
            currentStorageMonthLabelUtc = "2026-03",
            nowUtcMillis = now
        )

        assertThat(state).isEqualTo(
            UiCycleState.Executing(
                monthLabel = "2026-03",
                canFinish = true,
                canUndoStart = true
            )
        )
    }

    @Test
    fun resolve_returnsClosed_whenClosedUndoWindowIsActive() {
        val now = 1_700_000_000_000L
        val state = resolver.resolve(
            records = listOf(
                record(
                    month = "2026-02",
                    status = ExecutionStatus.CLOSED,
                    closedAtMillis = now - 1_000,
                    canUndoUntilMillis = now + 60_000
                )
            ),
            currentStorageMonthLabelUtc = "2026-03",
            nowUtcMillis = now
        )

        assertThat(state).isEqualTo(
            UiCycleState.Closed(
                monthLabel = "2026-02",
                canUndoCompletion = true
            )
        )
    }

    @Test
    fun resolve_returnsPlanningNextMonth_whenClosedUndoWindowExpired() {
        val now = 1_700_000_000_000L
        val state = resolver.resolve(
            records = listOf(
                record(
                    month = "2026-02",
                    status = ExecutionStatus.CLOSED,
                    closedAtMillis = now - 90_000,
                    canUndoUntilMillis = now - 1_000
                )
            ),
            currentStorageMonthLabelUtc = "2026-03",
            nowUtcMillis = now
        )

        assertThat(state).isEqualTo(
            UiCycleState.Planning(
                monthLabel = "2026-03",
                source = PlanningSource.NEXT_MONTH_AFTER_CLOSED
            )
        )
    }

    @Test
    fun resolve_returnsPlanningCurrentMonth_whenOnlyDraftRecordsExist() {
        val now = 1_700_000_000_000L
        val state = resolver.resolve(
            records = listOf(
                record(
                    month = "2026-03",
                    status = ExecutionStatus.DRAFT
                )
            ),
            currentStorageMonthLabelUtc = "2026-03",
            nowUtcMillis = now
        )

        assertThat(state).isEqualTo(
            UiCycleState.Planning(
                monthLabel = "2026-03",
                source = PlanningSource.CURRENT_MONTH
            )
        )
    }

    @Test
    fun resolve_returnsConflict_forMalformedMonthLabel() {
        val now = 1_700_000_000_000L
        val state = resolver.resolve(
            records = listOf(record(month = "bad-month", status = ExecutionStatus.EXECUTING)),
            currentStorageMonthLabelUtc = "2026-03",
            nowUtcMillis = now
        )

        assertThat(state).isEqualTo(
            UiCycleState.Conflict(
                monthLabel = null,
                reason = CycleConflictReason.INVALID_MONTH_LABEL
            )
        )
    }

    @Test
    fun resolve_returnsConflict_forDuplicateExecutingMonth() {
        val now = 1_700_000_000_000L
        val state = resolver.resolve(
            records = listOf(
                record(month = "2026-03", status = ExecutionStatus.EXECUTING),
                record(month = "2026-03", status = ExecutionStatus.EXECUTING)
            ),
            currentStorageMonthLabelUtc = "2026-03",
            nowUtcMillis = now
        )

        assertThat(state).isEqualTo(
            UiCycleState.Conflict(
                monthLabel = "2026-03",
                reason = CycleConflictReason.DUPLICATE_ACTIVE_RECORDS
            )
        )
    }

    @Test
    fun resolve_futureBoundary_plusOneMonthIsValid() {
        val now = 1_700_000_000_000L
        val state = resolver.resolve(
            records = listOf(record(month = "2026-04", status = ExecutionStatus.DRAFT)),
            currentStorageMonthLabelUtc = "2026-03",
            nowUtcMillis = now
        )

        assertThat(state).isEqualTo(
            UiCycleState.Planning(
                monthLabel = "2026-03",
                source = PlanningSource.CURRENT_MONTH
            )
        )
    }

    @Test
    fun resolve_futureBoundary_plusTwoMonthsIsConflict() {
        val now = 1_700_000_000_000L
        val state = resolver.resolve(
            records = listOf(record(month = "2026-05", status = ExecutionStatus.DRAFT)),
            currentStorageMonthLabelUtc = "2026-03",
            nowUtcMillis = now
        )

        assertThat(state).isEqualTo(
            UiCycleState.Conflict(
                monthLabel = "2026-05",
                reason = CycleConflictReason.FUTURE_RECORD
            )
        )
    }

    private fun record(
        month: String,
        status: ExecutionStatus,
        startedAtMillis: Long? = null,
        closedAtMillis: Long? = null,
        canUndoUntilMillis: Long? = null
    ): ExecutionRecord = ExecutionRecord(
        id = "$month-$status-${startedAtMillis ?: closedAtMillis ?: 0}",
        planId = "plan-$month",
        monthLabel = month,
        status = status,
        startedAtMillis = startedAtMillis,
        closedAtMillis = closedAtMillis,
        canUndoUntilMillis = canUndoUntilMillis,
        createdAtMillis = 1_700_000_000_000L,
        updatedAtMillis = 1_700_000_000_000L
    )
}
