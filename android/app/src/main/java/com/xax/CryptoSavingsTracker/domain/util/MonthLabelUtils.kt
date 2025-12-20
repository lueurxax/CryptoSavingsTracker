package com.xax.CryptoSavingsTracker.domain.util

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

object MonthLabelUtils {
    private val formatter = DateTimeFormatter.ofPattern("yyyy-MM")

    fun nowUtc(): String = fromMillisUtc(System.currentTimeMillis())

    fun fromMillisUtc(millis: Long): String {
        val instant = Instant.ofEpochMilli(millis)
        val localDate = LocalDate.ofInstant(instant, ZoneOffset.UTC)
        return localDate.format(formatter)
    }
}

