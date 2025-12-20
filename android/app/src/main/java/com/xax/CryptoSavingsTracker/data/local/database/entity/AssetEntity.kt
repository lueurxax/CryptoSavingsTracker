package com.xax.CryptoSavingsTracker.data.local.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * Asset entity - represents a cryptocurrency wallet or fiat account.
 */
@Entity(
    tableName = "assets",
    indices = [
        Index(value = ["currency"]),
        Index(value = ["address"], unique = true)
    ]
)
data class AssetEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "currency")
    val currency: String,

    @ColumnInfo(name = "address")
    val address: String? = null,

    @ColumnInfo(name = "chain_id")
    val chainId: String? = null,

    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "last_modified_at_utc_millis")
    val lastModifiedAtUtcMillis: Long = System.currentTimeMillis()
)
