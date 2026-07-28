package com.xax.CryptoSavingsTracker.domain.util

import com.google.common.truth.Truth.assertThat
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.LocalDate
import java.util.TimeZone

class PlanningCalendarUtcTest {
    @Test
    fun `UTC planning date and storage month ignore the device timezone at month boundary`() {
        val instant = Instant.parse("2026-08-01T00:30:00Z")
        val previous = TimeZone.getDefault()

        try {
            for (zoneId in listOf("Pacific/Honolulu", "Pacific/Kiritimati")) {
                TimeZone.setDefault(TimeZone.getTimeZone(zoneId))

                assertThat(PlanningCalendarUtc.dateFromMillis(instant.toEpochMilli()))
                    .isEqualTo(LocalDate.of(2026, 8, 1))
                assertThat(MonthLabelUtils.fromMillisUtc(instant.toEpochMilli()))
                    .isEqualTo("2026-08")
            }
        } finally {
            TimeZone.setDefault(previous)
        }
    }

    @Test
    fun `payment periods include a payment that falls exactly on the deadline`() {
        val today = LocalDate.of(2026, 7, 31)

        assertThat(PlanningCalendarUtc.nextPaymentDate(today, paymentDay = 1))
            .isEqualTo(LocalDate.of(2026, 8, 1))
        assertThat(
            PlanningCalendarUtc.paymentPeriodsRemaining(
                startDate = today,
                endDate = LocalDate.of(2026, 9, 1),
                paymentDay = 1
            )
        ).isEqualTo(2)
    }
}
