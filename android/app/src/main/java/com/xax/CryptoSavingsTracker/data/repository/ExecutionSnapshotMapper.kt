package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.entity.ExecutionSnapshotEntity
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot

object ExecutionSnapshotMapper {
    fun ExecutionSnapshotEntity.toDomain(): ExecutionSnapshot = ExecutionSnapshot(
        id = id,
        executionRecordId = executionRecordId,
        goalId = goalId,
        goalName = goalName,
        currency = currency,
        targetAmount = targetAmount,
        currentTotalAtStart = currentTotalAtStart,
        requiredAmount = requiredAmount,
        isProtected = isProtected,
        isSkipped = isSkipped,
        customAmount = customAmount,
        createdAtMillis = createdAtUtcMillis
    )

    fun ExecutionSnapshot.toEntity(): ExecutionSnapshotEntity = ExecutionSnapshotEntity(
        id = id,
        executionRecordId = executionRecordId,
        goalId = goalId,
        goalName = goalName,
        currency = currency,
        targetAmount = targetAmount,
        currentTotalAtStart = currentTotalAtStart,
        requiredAmount = requiredAmount,
        isProtected = isProtected,
        isSkipped = isSkipped,
        customAmount = customAmount,
        createdAtUtcMillis = createdAtMillis
    )
}

