package com.xax.CryptoSavingsTracker.data.local.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * AssetAllocation entity - links assets to goals with fixed allocation amounts.
 */
@Entity(
    tableName = "asset_allocations",
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
        Index(value = ["asset_id", "goal_id"], unique = true)
    ]
)
data class AssetAllocationEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "asset_id")
    val assetId: String,

    @ColumnInfo(name = "goal_id")
    val goalId: String,

    @ColumnInfo(name = "amount")
    val amount: Double,

    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "last_modified_at_utc_millis")
    val lastModifiedAtUtcMillis: Long = System.currentTimeMillis()
)
