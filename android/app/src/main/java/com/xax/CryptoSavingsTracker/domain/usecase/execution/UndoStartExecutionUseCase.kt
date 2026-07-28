package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import javax.inject.Inject

/**
 * Undo start tracking (executing -> draft) within a 24 hour grace period.
 * Mirrors iOS undoStartTracking behavior.
 */
class UndoStartExecutionUseCase @Inject constructor(
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val executionAssetRateRepository: ExecutionAssetRateRepository,
    private val attributionRecoveryPolicy: ExecutionAttributionRecoveryPolicy,
    private val transactionRunner: ExecutionTransitionTransactionRunner
) {
    suspend operator fun invoke(recordId: String): Result<Unit> = runCatching {
        transactionRunner.run {
            val record = executionRecordRepository.getRecordById(recordId)
                ?: throw IllegalStateException("Execution record not found")
            if (record.status != ExecutionStatus.EXECUTING) {
                throw IllegalStateException(ExecutionActionCopyCatalog.undoStartExpired(record.monthLabel))
            }

            val startedAt = record.startedAtMillis?.takeIf { it > 0L }
            val fallbackUndoUntil = startedAt?.let {
                runCatching { Math.addExact(it, UNDO_WINDOW_MILLIS) }.getOrNull()
            }
            val canUndoUntil = record.canUndoUntilMillis
                ?.takeIf { startedAt != null }
                ?: fallbackUndoUntil
            val isWithinNormalUndoWindow =
                canUndoUntil != null && System.currentTimeMillis() < canUndoUntil
            if (
                !isWithinNormalUndoWindow &&
                !attributionRecoveryPolicy.requiresExpiredUndoRecovery(record)
            ) {
                throw IllegalStateException(ExecutionActionCopyCatalog.undoStartExpired(record.monthLabel))
            }

            executionSnapshotRepository.deleteByRecordId(recordId)
            executionAssetRateRepository.deleteByRecordId(recordId)
            executionRecordRepository.revertToDraft(recordId)
        }
    }

    private companion object {
        const val UNDO_WINDOW_MILLIS: Long = 24L * 60L * 60L * 1000L
    }
}
