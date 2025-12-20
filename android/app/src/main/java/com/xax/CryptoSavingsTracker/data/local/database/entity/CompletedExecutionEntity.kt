package com.xax.CryptoSavingsTracker.data.local.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * CompletedExecution entity - records completed goal execution for history.
 */
@Entity(
    tableName = "completed_executions",
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
        Index(value = ["completed_at_utc_millis"])
    ]
)
data class CompletedExecutionEntity(
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

    @ColumnInfo(name = "required_amount")
    val requiredAmount: Double,

    @ColumnInfo(name = "actual_amount")
    val actualAmount: Double,

    @ColumnInfo(name = "completed_at_utc_millis")
    val completedAtUtcMillis: Long,

    @ColumnInfo(name = "can_undo_until_utc_millis")
    val canUndoUntilUtcMillis: Long,

    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis()
)
