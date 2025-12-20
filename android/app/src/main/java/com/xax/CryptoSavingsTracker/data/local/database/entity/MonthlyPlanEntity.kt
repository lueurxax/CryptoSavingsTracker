package com.xax.CryptoSavingsTracker.data.local.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * MonthlyPlan entity - stores monthly planning configuration and requirements.
 */
@Entity(
    tableName = "monthly_plans",
    indices = [
        Index(value = ["month_label"], unique = true),
        Index(value = ["status"])
    ]
)
data class MonthlyPlanEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "month_label")
    val monthLabel: String,

    @ColumnInfo(name = "status")
    val status: String,

    @ColumnInfo(name = "flex_percentage")
    val flexPercentage: Double = 1.0,

    @ColumnInfo(name = "total_required")
    val totalRequired: Double = 0.0,

    @ColumnInfo(name = "requirements_json")
    val requirementsJson: String = "[]",

    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "last_modified_at_utc_millis")
    val lastModifiedAtUtcMillis: Long = System.currentTimeMillis()
)
