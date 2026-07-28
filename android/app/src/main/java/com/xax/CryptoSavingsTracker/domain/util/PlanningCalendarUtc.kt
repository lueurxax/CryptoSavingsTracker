package com.xax.CryptoSavingsTracker.domain.util

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.math.max
import kotlin.math.min

/**
 * Canonical calendar boundary for persisted monthly planning identity.
 *
 * Month labels, payment periods, and automated execution all use UTC. Device
 * timezone remains a presentation/scheduling concern and cannot change which
 * persisted month or payment period an instant belongs to.
 */
object PlanningCalendarUtc {
    fun today(): LocalDate = dateFromMillis(System.currentTimeMillis())

    fun dateFromMillis(millis: Long): LocalDate {
        return LocalDate.ofInstant(Instant.ofEpochMilli(millis), ZoneOffset.UTC)
    }

    fun nextPaymentDate(
        today: LocalDate,
        paymentDay: Int
    ): LocalDate {
        val normalizedPaymentDay = paymentDay.coerceIn(1, 28)
        val thisMonthDate = today.withDayOfMonth(
            min(normalizedPaymentDay, today.lengthOfMonth())
        )
        if (thisMonthDate.isAfter(today)) return thisMonthDate

        val nextMonth = today.plusMonths(1)
        return nextMonth.withDayOfMonth(
            min(normalizedPaymentDay, nextMonth.lengthOfMonth())
        )
    }

    fun paymentPeriodsRemaining(
        startDate: LocalDate,
        endDate: LocalDate,
        paymentDay: Int
    ): Int {
        var paymentDate = nextPaymentDate(startDate, paymentDay)
        var count = 0
        while (!paymentDate.isAfter(endDate)) {
            count += 1
            paymentDate = paymentDate.plusMonths(1)
        }
        return max(1, count)
    }
}
