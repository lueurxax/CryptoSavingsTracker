package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.entity.CompletedExecutionEntity
import com.xax.CryptoSavingsTracker.domain.model.CompletedExecution

object CompletedExecutionMapper {
    fun CompletedExecutionEntity.toDomain(): CompletedExecution = CompletedExecution(
        id = id,
        executionRecordId = executionRecordId,
        goalId = goalId,
        goalName = goalName,
        currency = currency,
        requiredAmount = requiredAmount,
        actualAmount = actualAmount,
        completedAtMillis = completedAtUtcMillis,
        canUndoUntilMillis = canUndoUntilUtcMillis,
        createdAtMillis = createdAtUtcMillis
    )

    fun CompletedExecution.toEntity(): CompletedExecutionEntity = CompletedExecutionEntity(
        id = id,
        executionRecordId = executionRecordId,
        goalId = goalId,
        goalName = goalName,
        currency = currency,
        requiredAmount = requiredAmount,
        actualAmount = actualAmount,
        completedAtUtcMillis = completedAtMillis,
        canUndoUntilUtcMillis = canUndoUntilMillis,
        createdAtUtcMillis = createdAtMillis
    )
}

