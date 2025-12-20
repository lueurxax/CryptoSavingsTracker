package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import kotlinx.coroutines.flow.first
import javax.inject.Inject

class UndoExecutionUseCase @Inject constructor(
    private val executionRecordRepository: ExecutionRecordRepository,
    private val completedExecutionRepository: CompletedExecutionRepository
) {
    suspend operator fun invoke(recordId: String): Result<Unit> = runCatching {
        val now = System.currentTimeMillis()
        val completed = completedExecutionRepository.getByRecordId(recordId).first()
        if (completed.isEmpty()) {
            throw IllegalStateException("Nothing to undo")
        }
        val canUndo = completed.all { it.canUndoUntilMillis > now }
        if (!canUndo) {
            throw IllegalStateException("Undo window has expired")
        }

        completedExecutionRepository.deleteByRecordId(recordId)
        executionRecordRepository.reopen(recordId)
    }
}

