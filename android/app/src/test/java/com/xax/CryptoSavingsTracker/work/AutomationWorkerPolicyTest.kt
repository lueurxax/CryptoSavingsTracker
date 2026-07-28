package com.xax.CryptoSavingsTracker.work

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UnprovenExecutionContributionAttributionException
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File
import java.time.Instant
import java.time.LocalDate

class AutomationWorkerPolicyTest {
    @Test
    fun `automation date gates use the same UTC month as execution storage`() {
        val stillJulyUtc = Instant.parse("2026-07-31T10:30:00Z")
        val alreadyAugustUtc = Instant.parse("2026-08-01T11:30:00Z")

        assertThat(AutomationWorkerPolicy.utcDate(stillJulyUtc))
            .isEqualTo(LocalDate.of(2026, 7, 31))
        assertThat(AutomationWorkerPolicy.monthLabel(stillJulyUtc)).isEqualTo("2026-07")
        assertThat(AutomationWorkerPolicy.utcDate(alreadyAugustUtc))
            .isEqualTo(LocalDate.of(2026, 8, 1))
        assertThat(AutomationWorkerPolicy.monthLabel(alreadyAugustUtc)).isEqualTo("2026-08")
    }

    @Test
    fun `domain failure is thrown so WorkManager can retry`() {
        val providerFailure = IllegalStateException("rate unavailable")

        val thrown = assertThrows<IllegalStateException> {
            AutomationWorkerPolicy.requireSuccess<Unit>(
                Result.failure(providerFailure)
            )
        }

        assertThat(thrown).isSameInstanceAs(providerFailure)
    }

    @Test
    fun `automation skips unavailable execution instead of completing or retrying it`() {
        val record = record()
        val unavailable = ExecutionSession(
            record = record,
            goals = emptyList(),
            isProgressAvailable = false
        )

        assertThat(AutomationWorkerPolicy.shouldAutoComplete(record, unavailable)).isFalse()
        assertThat(
            AutomationWorkerPolicy.isTerminalExecutionUnavailable(
                UnprovenExecutionContributionAttributionException()
            )
        ).isTrue()
    }

    @Test
    fun `automation completes only matching available execution`() {
        val record = record()
        val available = ExecutionSession(record = record, goals = emptyList())
        val other = available.copy(record = record.copy(id = "other"))

        assertThat(AutomationWorkerPolicy.shouldAutoComplete(record, available)).isTrue()
        assertThat(AutomationWorkerPolicy.shouldAutoComplete(record, other)).isFalse()
        assertThat(AutomationWorkerPolicy.shouldAutoComplete(record, null)).isFalse()
    }

    @Test
    fun `workers delegate undo deadline persistence to atomic transition use cases`() {
        val candidates = listOf(
            File("src/main/java/com/xax/CryptoSavingsTracker/work/AutomationCheckWorker.kt"),
            File("app/src/main/java/com/xax/CryptoSavingsTracker/work/AutomationCheckWorker.kt"),
            File("android/app/src/main/java/com/xax/CryptoSavingsTracker/work/AutomationCheckWorker.kt")
        )
        val sourceFile = candidates.firstOrNull { it.isFile }
            ?: error("AutomationCheckWorker source not found")

        assertThat(sourceFile.readText()).doesNotContain("updateCanUndoUntil(")
    }

    private fun record() = ExecutionRecord(
        id = "execution",
        planId = "plan",
        monthLabel = "2026-07",
        status = ExecutionStatus.EXECUTING,
        startedAtMillis = 1L,
        closedAtMillis = null,
        canUndoUntilMillis = 2L,
        createdAtMillis = 1L,
        updatedAtMillis = 1L
    )
}
