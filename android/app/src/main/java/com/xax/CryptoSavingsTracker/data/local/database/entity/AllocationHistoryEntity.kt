package com.xax.CryptoSavingsTracker.data.local.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * AllocationHistory entity - snapshots of allocation state for execution tracking.
 */
@Entity(
    tableName = "allocation_history",
    foreignKeys = [
        ForeignKey(
            entity = AssetEntity::class,
            parentColumns = ["id"],
            childColumns = ["asset_id"],
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
        Index(value = ["asset_id"]),
        Index(value = ["goal_id"]),
        Index(value = ["month_label"]),
        Index(value = ["timestamp_utc_millis"])
    ]
)
data class AllocationHistoryEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "asset_id")
    val assetId: String,

    @ColumnInfo(name = "goal_id")
    val goalId: String,

    @ColumnInfo(name = "amount")
    val amount: Double,

    @ColumnInfo(name = "month_label")
    val monthLabel: String,

    @ColumnInfo(name = "timestamp_utc_millis")
    val timestampUtcMillis: Long,

    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis()
)
