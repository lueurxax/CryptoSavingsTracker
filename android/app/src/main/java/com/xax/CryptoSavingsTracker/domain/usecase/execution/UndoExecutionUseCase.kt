package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletionEventRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import kotlinx.coroutines.flow.first
import javax.inject.Inject

class UndoExecutionUseCase @Inject constructor(
    private val executionRecordRepository: ExecutionRecordRepository,
    private val completedExecutionRepository: CompletedExecutionRepository,
    private val completionEventRepository: CompletionEventRepository,
    private val transactionRunner: ExecutionTransitionTransactionRunner
) {
    suspend operator fun invoke(recordId: String): Result<Unit> = runCatching {
        val executing = executionRecordRepository.getCurrentExecutingRecord().first()
        if (executing != null && executing.id != recordId) {
            throw IllegalStateException(
                ExecutionActionCopyCatalog.startBlockedAlreadyExecuting(executing.monthLabel)
            )
        }

        val targetRecord = executionRecordRepository.getRecordById(recordId)
            ?: throw IllegalStateException(ExecutionActionCopyCatalog.recordConflict())
        val month = targetRecord.monthLabel

        val now = System.currentTimeMillis()
        val latestOpenEvent = completionEventRepository.getLatestOpenByRecordId(recordId)
            ?: throw IllegalStateException(ExecutionActionCopyCatalog.undoCompletionExpired(month))
        val completed = completedExecutionRepository
            .getActiveByCompletionEventId(latestOpenEvent.id)
            .first()
        if (completed.isEmpty()) {
            throw IllegalStateException(ExecutionActionCopyCatalog.undoCompletionExpired(month))
        }
        val canUndo = completed.all { it.canUndoUntilMillis > now }
        if (!canUndo) {
            throw IllegalStateException(ExecutionActionCopyCatalog.undoCompletionExpired(month))
        }

        transactionRunner.run {
            completionEventRepository.markUndone(latestOpenEvent.id, now, "manualUndo")
            completedExecutionRepository.markUndoneByCompletionEventId(latestOpenEvent.id, now, "manualUndo")
            executionRecordRepository.reopen(recordId)
        }
    }
}
