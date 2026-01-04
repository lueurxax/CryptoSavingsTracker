package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.entity.MonthlyExecutionRecordEntity
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus

object ExecutionRecordMapper {
    fun MonthlyExecutionRecordEntity.toDomain(): ExecutionRecord = ExecutionRecord(
        id = id,
        planId = planId,
        monthLabel = monthLabel,
        status = ExecutionStatus.fromString(status),
        startedAtMillis = startedAtUtcMillis,
        closedAtMillis = closedAtUtcMillis,
        canUndoUntilMillis = canUndoUntilUtcMillis,
        createdAtMillis = createdAtUtcMillis,
        updatedAtMillis = lastModifiedAtUtcMillis
    )

    fun ExecutionRecord.toEntity(): MonthlyExecutionRecordEntity = MonthlyExecutionRecordEntity(
        id = id,
        planId = planId,
        monthLabel = monthLabel,
        status = status.rawValue,
        startedAtUtcMillis = startedAtMillis,
        closedAtUtcMillis = closedAtMillis,
        canUndoUntilUtcMillis = canUndoUntilMillis,
        createdAtUtcMillis = createdAtMillis,
        lastModifiedAtUtcMillis = updatedAtMillis
    )
}

