package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.CycleConflictReason
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.model.PlanningSource
import com.xax.CryptoSavingsTracker.domain.model.UiCycleState
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.util.MonthLabelUtils
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import java.time.YearMonth
import javax.inject.Inject

class MonthlyCycleStateResolverUseCase @Inject constructor(
    private val executionRecordRepository: ExecutionRecordRepository,
    private val getExecutionSessionUseCase: GetExecutionSessionUseCase
) {
    fun observeState(): Flow<UiCycleState> {
        return combine(
            executionRecordRepository.getAllRecords(),
            getExecutionSessionUseCase.currentExecuting()
        ) { records, session ->
            val state = resolve(
                records = records,
                currentStorageMonthLabelUtc = MonthLabelUtils.nowUtc(),
                nowUtcMillis = System.currentTimeMillis()
            )
            applyExecutionAvailability(state, session)
        }
    }

    private fun applyExecutionAvailability(
        state: UiCycleState,
        session: ExecutionSession?
    ): UiCycleState {
        if (state !is UiCycleState.Executing) return state
        val matchingSession = session?.takeIf {
            it.record.status == ExecutionStatus.EXECUTING &&
                it.record.monthLabel == state.monthLabel
        }
        if (matchingSession == null) {
            return state.copy(canFinish = false)
        }
        return if (matchingSession.isProgressAvailable) {
            state
        } else {
            state.copy(canFinish = false, canUndoStart = true)
        }
    }

    fun resolve(
        records: List<ExecutionRecord>,
        currentStorageMonthLabelUtc: String,
        nowUtcMillis: Long
    ): UiCycleState {
        val currentMonth = parseMonth(currentStorageMonthLabelUtc)
            ?: return UiCycleState.Conflict(null, CycleConflictReason.INVALID_MONTH_LABEL)

        if (records.any { parseMonth(it.monthLabel) == null }) {
            return UiCycleState.Conflict(null, CycleConflictReason.INVALID_MONTH_LABEL)
        }

        val futureRecord = records.firstOrNull { record ->
            val month = parseMonth(record.monthLabel) ?: return@firstOrNull false
            month > currentMonth.plusMonths(1)
        }
        if (futureRecord != null) {
            return UiCycleState.Conflict(futureRecord.monthLabel, CycleConflictReason.FUTURE_RECORD)
        }

        val executing = records.filter { it.status == ExecutionStatus.EXECUTING }
        val duplicateExecutingMonth = executing
            .groupBy { it.monthLabel }
            .entries
            .firstOrNull { it.value.size > 1 }
            ?.key
        if (duplicateExecutingMonth != null) {
            return UiCycleState.Conflict(duplicateExecutingMonth, CycleConflictReason.DUPLICATE_ACTIVE_RECORDS)
        }

        val activeExecuting = executing.maxByOrNull { parseMonth(it.monthLabel) ?: YearMonth.of(0, 1) }
        if (activeExecuting != null) {
            return UiCycleState.Executing(
                monthLabel = activeExecuting.monthLabel,
                canFinish = true,
                canUndoStart = activeExecuting.canUndo(nowUtcMillis)
            )
        }

        val latestClosed = records
            .filter { it.status == ExecutionStatus.CLOSED }
            .maxByOrNull { parseMonth(it.monthLabel) ?: YearMonth.of(0, 1) }
        if (latestClosed != null) {
            val canUndo = latestClosed.canUndo(nowUtcMillis)
            return if (canUndo) {
                UiCycleState.Closed(monthLabel = latestClosed.monthLabel, canUndoCompletion = true)
            } else {
                val nextMonthAfterClosed = checkNotNull(parseMonth(latestClosed.monthLabel))
                    .plusMonths(1)
                val planningMonth = maxOf(currentMonth, nextMonthAfterClosed)
                UiCycleState.Planning(
                    monthLabel = planningMonth.toString(),
                    source = PlanningSource.NEXT_MONTH_AFTER_CLOSED
                )
            }
        }

        return UiCycleState.Planning(
            monthLabel = currentStorageMonthLabelUtc,
            source = PlanningSource.CURRENT_MONTH
        )
    }

    private fun parseMonth(monthLabel: String): YearMonth? = runCatching {
        YearMonth.parse(monthLabel)
    }.getOrNull()
}
