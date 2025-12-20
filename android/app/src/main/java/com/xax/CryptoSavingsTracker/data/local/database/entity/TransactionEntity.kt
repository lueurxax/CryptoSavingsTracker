package com.xax.CryptoSavingsTracker.data.local.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * Transaction entity - represents a deposit or withdrawal.
 */
@Entity(
    tableName = "transactions",
    foreignKeys = [
        ForeignKey(
            entity = AssetEntity::class,
            parentColumns = ["id"],
            childColumns = ["asset_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["asset_id"]),
        Index(value = ["date_utc_millis"]),
        Index(value = ["external_id"], unique = true)
    ]
)
data class TransactionEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "asset_id")
    val assetId: String,

    @ColumnInfo(name = "amount")
    val amount: Double,

    @ColumnInfo(name = "date_utc_millis")
    val dateUtcMillis: Long,

    @ColumnInfo(name = "source")
    val source: String,

    @ColumnInfo(name = "external_id")
    val externalId: String? = null,

    @ColumnInfo(name = "counterparty")
    val counterparty: String? = null,

    @ColumnInfo(name = "comment")
    val comment: String? = null,

    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis()
)
