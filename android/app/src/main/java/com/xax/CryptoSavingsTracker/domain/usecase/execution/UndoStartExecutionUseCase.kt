package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import javax.inject.Inject

/**
 * Undo start tracking (executing -> draft) within a 24 hour grace period.
 * Mirrors iOS undoStartTracking behavior.
 */
class UndoStartExecutionUseCase @Inject constructor(
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionSnapshotRepository: ExecutionSnapshotRepository
) {
    suspend operator fun invoke(recordId: String): Result<Unit> = runCatching {
        val record = executionRecordRepository.getRecordById(recordId)
            ?: throw IllegalStateException("Execution record not found")
        if (record.status != ExecutionStatus.EXECUTING) {
            throw IllegalStateException("Execution is not active")
        }

        val startedAt = record.startedAtMillis ?: throw IllegalStateException("Execution record missing startedAt")
        val now = System.currentTimeMillis()
        val canUndoUntil = startedAt + UNDO_WINDOW_MILLIS
        if (now >= canUndoUntil) {
            throw IllegalStateException("Undo window has expired")
        }

        executionSnapshotRepository.deleteByRecordId(recordId)
        executionRecordRepository.revertToDraft(recordId)
    }

    private companion object {
        const val UNDO_WINDOW_MILLIS: Long = 24L * 60L * 60L * 1000L
    }
}

