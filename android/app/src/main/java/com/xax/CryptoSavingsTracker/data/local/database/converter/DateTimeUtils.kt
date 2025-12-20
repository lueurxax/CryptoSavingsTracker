package com.xax.CryptoSavingsTracker.data.local.database.converter

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.YearMonth
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/**
 * DATE vs TIMESTAMP STORAGE RULES
 *
 * DATE-ONLY FIELDS (deadline, startDate, firstReminderDate):
 *   - Stored as Int using LocalDate.toEpochDay() (days since 1970-01-01)
 *   - Timezone-agnostic: "2025-01-15" is the same epoch day everywhere
 *   - No risk of shifting across timezone boundaries
 *
 * TIMESTAMP FIELDS (createdAt, lastModifiedAt, reminderTime, transaction dates):
 *   - Stored as Long using epoch milliseconds UTC
 *   - Represents a specific instant in time
 *   - Converted to local timezone only for display
 *
 * MONTH LABELS (for execution tracking):
 *   - Stored as String "yyyy-MM" in UTC
 *   - Consistent across timezones for grouping
 */
object DateTimeUtils {

    // ========== DATE-ONLY CONVERSIONS (epoch day) ==========

    fun LocalDate.toEpochDayInt(): Int = this.toEpochDay().toInt()

    fun Int.toLocalDate(): LocalDate = LocalDate.ofEpochDay(this.toLong())

    // ========== TIMESTAMP CONVERSIONS (epoch millis) ==========

    fun Instant.toUtcMillis(): Long = this.toEpochMilli()

    fun Long.toInstant(): Instant = Instant.ofEpochMilli(this)

    fun Long.toLocalDateTime(zone: ZoneId = ZoneId.systemDefault()): LocalDateTime {
        return Instant.ofEpochMilli(this).atZone(zone).toLocalDateTime()
    }

    fun Long.toZonedDateTime(zone: ZoneId = ZoneId.systemDefault()): ZonedDateTime {
        return Instant.ofEpochMilli(this).atZone(zone)
    }

    // ========== MONTH LABEL UTILITIES ==========

    private val monthFormatter = DateTimeFormatter.ofPattern("yyyy-MM")

    fun monthLabelFromMillis(millis: Long): String {
        return Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).format(monthFormatter)
    }

    fun currentMonthLabel(): String = monthLabelFromMillis(System.currentTimeMillis())

    fun parseMonthLabel(label: String): YearMonth = YearMonth.parse(label)

    // ========== DISPLAY FORMATTING ==========

    fun formatDate(epochDay: Int): String {
        return epochDay.toLocalDate().format(DateTimeFormatter.ISO_LOCAL_DATE)
    }

    fun formatDateTime(epochMillis: Long, zone: ZoneId = ZoneId.systemDefault()): String {
        return epochMillis.toZonedDateTime(zone)
            .format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm"))
    }
}
