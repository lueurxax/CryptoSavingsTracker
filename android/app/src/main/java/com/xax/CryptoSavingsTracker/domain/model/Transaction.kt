package com.xax.CryptoSavingsTracker.domain.model

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Domain model representing a transaction (deposit or withdrawal).
 */
data class Transaction(
    val id: String,
    val assetId: String,
    val amount: Double,
    val dateMillis: Long,
    val source: TransactionSource,
    val externalId: String?,
    val counterparty: String?,
    val comment: String?,
    val createdAt: Long
) {
    /**
     * Whether this is a deposit (positive amount) or withdrawal (negative amount)
     */
    val isDeposit: Boolean
        get() = amount >= 0

    /**
     * Absolute value of the amount
     */
    val absoluteAmount: Double
        get() = kotlin.math.abs(amount)

    /**
     * Get the date as LocalDateTime
     */
    fun dateTime(zone: ZoneId = ZoneId.systemDefault()): LocalDateTime {
        return Instant.ofEpochMilli(dateMillis).atZone(zone).toLocalDateTime()
    }

    /**
     * Format the date for display
     */
    fun formattedDate(pattern: String = "MMM d, yyyy", zone: ZoneId = ZoneId.systemDefault()): String {
        return dateTime(zone).format(DateTimeFormatter.ofPattern(pattern))
    }

    /**
     * Format the date and time for display
     */
    fun formattedDateTime(
        pattern: String = "MMM d, yyyy 'at' h:mm a",
        zone: ZoneId = ZoneId.systemDefault()
    ): String {
        return dateTime(zone).format(DateTimeFormatter.ofPattern(pattern))
    }
}

/**
 * Source of the transaction.
 * iOS has: manual, onChain
 * Android extends with: import (for CSV import feature)
 */
enum class TransactionSource(val rawValue: String) {
    MANUAL("manual"),
    ON_CHAIN("onChain"),
    IMPORT("import");  // Android extension - not in iOS

    companion object {
        fun fromString(value: String): TransactionSource {
            return entries.find {
                it.rawValue.equals(value, ignoreCase = true) ||
                it.name.equals(value, ignoreCase = true)
            } ?: MANUAL
        }
    }

    fun displayName(): String = when (this) {
        MANUAL -> "Manual Entry"
        ON_CHAIN -> "On-Chain"
        IMPORT -> "Imported"
    }
}
