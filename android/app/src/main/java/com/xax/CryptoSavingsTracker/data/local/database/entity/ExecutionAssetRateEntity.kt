package com.xax.CryptoSavingsTracker.data.local.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

@Entity(
    tableName = "execution_asset_rates",
    primaryKeys = ["execution_record_id", "asset_id", "snapshot_currency"],
    foreignKeys = [
        ForeignKey(
            entity = MonthlyExecutionRecordEntity::class,
            parentColumns = ["id"],
            childColumns = ["execution_record_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index(value = ["execution_record_id"])]
)
data class ExecutionAssetRateEntity(
    @ColumnInfo(name = "execution_record_id")
    val executionRecordId: String,
    @ColumnInfo(name = "asset_id")
    val assetId: String,
    @ColumnInfo(name = "snapshot_currency")
    val snapshotCurrency: String,
    @ColumnInfo(name = "rate")
    val rate: Double,
    @ColumnInfo(name = "captured_at_utc_millis")
    val capturedAtUtcMillis: Long
)
