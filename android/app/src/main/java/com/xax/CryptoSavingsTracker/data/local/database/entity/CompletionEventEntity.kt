package com.xax.CryptoSavingsTracker.data.local.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

@Entity(
    tableName = "completion_events",
    foreignKeys = [
        ForeignKey(
            entity = MonthlyExecutionRecordEntity::class,
            parentColumns = ["id"],
            childColumns = ["execution_record_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["execution_record_id"]),
        Index(value = ["month_label"]),
        Index(value = ["execution_record_id", "sequence"], unique = true),
        Index(value = ["execution_record_id", "source_discriminator"], unique = true)
    ]
)
data class CompletionEventEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "execution_record_id")
    val executionRecordId: String,

    @ColumnInfo(name = "month_label")
    val monthLabel: String,

    @ColumnInfo(name = "sequence")
    val sequence: Int,

    @ColumnInfo(name = "source_discriminator")
    val sourceDiscriminator: String,

    @ColumnInfo(name = "completed_at_utc_millis")
    val completedAtUtcMillis: Long,

    @ColumnInfo(name = "completion_snapshot_ref")
    val completionSnapshotRef: String?,

    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "undone_at_utc_millis")
    val undoneAtUtcMillis: Long? = null,

    @ColumnInfo(name = "undo_reason")
    val undoReason: String? = null
)
