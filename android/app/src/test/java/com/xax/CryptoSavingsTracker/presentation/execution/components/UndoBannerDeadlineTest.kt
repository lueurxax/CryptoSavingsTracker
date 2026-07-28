package com.xax.CryptoSavingsTracker.presentation.execution.components

import com.google.common.truth.Truth.assertThat
import org.junit.jupiter.api.Test

class UndoBannerDeadlineTest {
    @Test
    fun `label uses persisted deadline instead of a fixed twenty four hour window`() {
        val fortyEightHours = 48 * 60 * 60 * 1_000L

        assertThat(
            formatUndoTimeRemaining(
                undoDeadlineMillis = fortyEightHours,
                nowMillis = 0L
            )
        ).isEqualTo("48h 0m")
        assertThat(
            formatUndoTimeRemaining(
                undoDeadlineMillis = fortyEightHours,
                nowMillis = fortyEightHours
            )
        ).isEqualTo("Expired")
    }
}
