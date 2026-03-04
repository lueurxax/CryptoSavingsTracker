package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.entity.CompletionEventEntity
import com.xax.CryptoSavingsTracker.domain.model.CompletionEvent

object CompletionEventMapper {
    fun CompletionEventEntity.toDomain(): CompletionEvent = CompletionEvent(
        id = id,
        executionRecordId = executionRecordId,
        monthLabel = monthLabel,
        sequence = sequence,
        sourceDiscriminator = sourceDiscriminator,
        completedAtMillis = completedAtUtcMillis,
        completionSnapshotRef = completionSnapshotRef,
        createdAtMillis = createdAtUtcMillis,
        undoneAtMillis = undoneAtUtcMillis,
        undoReason = undoReason
    )

    fun CompletionEvent.toEntity(): CompletionEventEntity = CompletionEventEntity(
        id = id,
        executionRecordId = executionRecordId,
        monthLabel = monthLabel,
        sequence = sequence,
        sourceDiscriminator = sourceDiscriminator,
        completedAtUtcMillis = completedAtMillis,
        completionSnapshotRef = completionSnapshotRef,
        createdAtUtcMillis = createdAtMillis,
        undoneAtUtcMillis = undoneAtMillis,
        undoReason = undoReason
    )
}
