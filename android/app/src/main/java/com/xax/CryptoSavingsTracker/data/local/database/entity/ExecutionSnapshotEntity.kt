package com.xax.CryptoSavingsTracker.data.local.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * ExecutionSnapshot entity - captures goal state at execution start.
 */
@Entity(
    tableName = "execution_snapshots",
    foreignKeys = [
        ForeignKey(
            entity = MonthlyExecutionRecordEntity::class,
            parentColumns = ["id"],
            childColumns = ["execution_record_id"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = GoalEntity::class,
            parentColumns = ["id"],
            childColumns = ["goal_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["execution_record_id"]),
        Index(value = ["goal_id"]),
        Index(value = ["execution_record_id", "goal_id"], unique = true)
    ]
)
data class ExecutionSnapshotEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "execution_record_id")
    val executionRecordId: String,

    @ColumnInfo(name = "goal_id")
    val goalId: String,

    @ColumnInfo(name = "goal_name")
    val goalName: String,

    @ColumnInfo(name = "currency")
    val currency: String,

    @ColumnInfo(name = "target_amount")
    val targetAmount: Double,

    @ColumnInfo(name = "current_total_at_start")
    val currentTotalAtStart: Double,

    @ColumnInfo(name = "required_amount")
    val requiredAmount: Double,

    @ColumnInfo(name = "is_protected")
    val isProtected: Boolean = false,

    @ColumnInfo(name = "is_skipped")
    val isSkipped: Boolean = false,

    @ColumnInfo(name = "custom_amount")
    val customAmount: Double? = null,

    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis()
)
