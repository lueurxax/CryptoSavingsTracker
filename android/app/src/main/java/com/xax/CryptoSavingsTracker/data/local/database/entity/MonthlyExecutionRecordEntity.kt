package com.xax.CryptoSavingsTracker.data.local.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * MonthlyExecutionRecord entity - tracks execution state for a month.
 */
@Entity(
    tableName = "monthly_execution_records",
    foreignKeys = [
        ForeignKey(
            entity = MonthlyPlanEntity::class,
            parentColumns = ["id"],
            childColumns = ["plan_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["plan_id"]),
        Index(value = ["month_label"], unique = true),
        Index(value = ["status"])
    ]
)
data class MonthlyExecutionRecordEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "plan_id")
    val planId: String,

    @ColumnInfo(name = "month_label")
    val monthLabel: String,

    @ColumnInfo(name = "status")
    val status: String,

    @ColumnInfo(name = "started_at_utc_millis")
    val startedAtUtcMillis: Long? = null,

    @ColumnInfo(name = "closed_at_utc_millis")
    val closedAtUtcMillis: Long? = null,

    @ColumnInfo(name = "can_undo_until_utc_millis")
    val canUndoUntilUtcMillis: Long? = null,

    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "last_modified_at_utc_millis")
    val lastModifiedAtUtcMillis: Long = System.currentTimeMillis()
)
