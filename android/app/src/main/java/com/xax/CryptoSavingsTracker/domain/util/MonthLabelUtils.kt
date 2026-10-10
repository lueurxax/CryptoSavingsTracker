package com.xax.CryptoSavingsTracker.domain.util

import java.time.format.DateTimeFormatter

object MonthLabelUtils {
    private val formatter = DateTimeFormatter.ofPattern("yyyy-MM")

    fun nowUtc(): String = fromMillisUtc(System.currentTimeMillis())

    fun fromMillisUtc(millis: Long): String {
        return PlanningCalendarUtc.dateFromMillis(millis).format(formatter)
    }
}
