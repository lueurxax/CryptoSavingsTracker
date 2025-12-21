package com.xax.CryptoSavingsTracker.data.local.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * Per-goal monthly plan persisted as one row per goal per month.
 * Mirrors iOS MonthlyPlan storage shape.
 */
@Entity(
    tableName = "monthly_goal_plans",
    indices = [
        Index(value = ["month_label", "goal_id"], unique = true),
        Index(value = ["month_label"]),
        Index(value = ["state"])
    ]
)
data class MonthlyGoalPlanEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "goal_id")
    val goalId: String,

    @ColumnInfo(name = "month_label")
    val monthLabel: String,

    @ColumnInfo(name = "required_monthly")
    val requiredMonthly: Double,

    @ColumnInfo(name = "remaining_amount")
    val remainingAmount: Double,

    @ColumnInfo(name = "months_remaining")
    val monthsRemaining: Int,

    @ColumnInfo(name = "currency")
    val currency: String,

    @ColumnInfo(name = "status")
    val status: String,

    @ColumnInfo(name = "state")
    val state: String = "draft",

    @ColumnInfo(name = "custom_amount")
    val customAmount: Double? = null,

    @ColumnInfo(name = "is_protected")
    val isProtected: Boolean = false,

    @ColumnInfo(name = "is_skipped")
    val isSkipped: Boolean = false,

    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "last_modified_at_utc_millis")
    val lastModifiedAtUtcMillis: Long = System.currentTimeMillis()
)

