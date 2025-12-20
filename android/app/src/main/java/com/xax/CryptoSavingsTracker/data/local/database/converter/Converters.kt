package com.xax.CryptoSavingsTracker.data.local.database.converter

import androidx.room.TypeConverter
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Room type converters for date/time and other complex types.
 */
class Converters {

    // ========== LocalDate (epoch day) ==========

    @TypeConverter
    fun fromLocalDate(date: LocalDate?): Int? {
        return date?.toEpochDay()?.toInt()
    }

    @TypeConverter
    fun toLocalDate(epochDay: Int?): LocalDate? {
        return epochDay?.let { LocalDate.ofEpochDay(it.toLong()) }
    }

    // ========== Instant (epoch millis) ==========

    @TypeConverter
    fun fromInstant(instant: Instant?): Long? {
        return instant?.toEpochMilli()
    }

    @TypeConverter
    fun toInstant(epochMillis: Long?): Instant? {
        return epochMillis?.let { Instant.ofEpochMilli(it) }
    }

    // ========== YearMonth (string) ==========

    @TypeConverter
    fun fromYearMonth(yearMonth: YearMonth?): String? {
        return yearMonth?.format(DateTimeFormatter.ofPattern("yyyy-MM"))
    }

    @TypeConverter
    fun toYearMonth(value: String?): YearMonth? {
        return value?.let { YearMonth.parse(it) }
    }

    // ========== List<String> (JSON) ==========

    @TypeConverter
    fun fromStringList(list: List<String>?): String {
        return list?.joinToString(",") ?: ""
    }

    @TypeConverter
    fun toStringList(value: String?): List<String> {
        return value?.takeIf { it.isNotBlank() }?.split(",") ?: emptyList()
    }
}
