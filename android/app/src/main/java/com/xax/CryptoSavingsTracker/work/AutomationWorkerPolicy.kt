package com.xax.CryptoSavingsTracker.work

import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UnprovenExecutionContributionAttributionException
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Canonical time/result boundary shared by every monthly automation worker.
 */
internal object AutomationWorkerPolicy {
    fun utcDate(instant: Instant = Instant.now()): LocalDate {
        return LocalDate.ofInstant(instant, ZoneOffset.UTC)
    }

    fun monthLabel(instant: Instant = Instant.now()): String {
        return utcDate(instant).format(DateTimeFormatter.ofPattern("yyyy-MM"))
    }

    fun <T> requireSuccess(result: kotlin.Result<T>): T = result.getOrThrow()

    fun shouldAutoComplete(
        record: ExecutionRecord,
        session: ExecutionSession?
    ): Boolean {
        return record.status == ExecutionStatus.EXECUTING &&
            session != null &&
            session.record.id == record.id &&
            session.isProgressAvailable
    }

    fun isTerminalExecutionUnavailable(error: Exception): Boolean {
        return error is UnprovenExecutionContributionAttributionException
    }
}
