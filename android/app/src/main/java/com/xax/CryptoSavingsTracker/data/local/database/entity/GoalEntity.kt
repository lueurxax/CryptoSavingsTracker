package com.xax.CryptoSavingsTracker.data.local.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * Goal entity for Room database.
 *
 * DATE vs TIMESTAMP STORAGE STRATEGY:
 * - DATE-ONLY fields (deadline, startDate, firstReminderDate):
 *   Stored as Int using LocalDate.toEpochDay() - days since 1970-01-01.
 *   This avoids timezone shifting issues with midnight UTC.
 *
 * - TIMESTAMP fields (createdAt, lastModifiedAt, reminderTime):
 *   Stored as Long using epoch milliseconds UTC.
 */
@Entity(
    tableName = "goals",
    indices = [
        Index(value = ["name"], unique = false),
        Index(value = ["lifecycle_status"]),
        Index(value = ["deadline_epoch_day"])
    ]
)
data class GoalEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "currency")
    val currency: String,

    @ColumnInfo(name = "target_amount")
    val targetAmount: Double,

    @ColumnInfo(name = "deadline_epoch_day")
    val deadlineEpochDay: Int,

    @ColumnInfo(name = "start_date_epoch_day")
    val startDateEpochDay: Int,

    @ColumnInfo(name = "lifecycle_status")
    val lifecycleStatus: String,

    @ColumnInfo(name = "lifecycle_status_changed_at_utc_millis")
    val lifecycleStatusChangedAtUtcMillis: Long? = null,

    @ColumnInfo(name = "emoji")
    val emoji: String? = null,

    @ColumnInfo(name = "description")
    val description: String? = null,

    @ColumnInfo(name = "link")
    val link: String? = null,

    @ColumnInfo(name = "reminder_frequency")
    val reminderFrequency: String? = null,

    @ColumnInfo(name = "reminder_time_utc_millis")
    val reminderTimeUtcMillis: Long? = null,

    @ColumnInfo(name = "first_reminder_epoch_day")
    val firstReminderEpochDay: Int? = null,

    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "last_modified_at_utc_millis")
    val lastModifiedAtUtcMillis: Long = System.currentTimeMillis()
)
