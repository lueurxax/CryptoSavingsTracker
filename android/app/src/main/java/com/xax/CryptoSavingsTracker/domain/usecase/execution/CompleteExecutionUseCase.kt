package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.CompletedExecution
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import kotlinx.coroutines.flow.first
import java.util.UUID
import javax.inject.Inject

class CompleteExecutionUseCase @Inject constructor(
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val completedExecutionRepository: CompletedExecutionRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository,
    private val transactionRepository: TransactionRepository
) {
    private val calculator = ExecutionProgressCalculator()

    suspend operator fun invoke(recordId: String): Result<Unit> = runCatching {
        val record = executionRecordRepository.getRecordById(recordId)
            ?: throw IllegalStateException("Execution record not found")
        val startedAtMillis = record.startedAtMillis
            ?: throw IllegalStateException("Execution record missing startedAt")

        val snapshots = executionSnapshotRepository.getByRecordId(recordId).first()
        if (snapshots.isEmpty()) {
            throw IllegalStateException("No execution snapshots found")
        }

        val completedAt = System.currentTimeMillis()
        val canUndoUntil = completedAt + 24L * 60L * 60L * 1000L

        val progress = calculator.calculateForSnapshots(
            snapshots = snapshots,
            transactions = transactionRepository.getAllTransactions().first(),
            allocationHistory = allocationHistoryRepository.getAll().first(),
            startedAtMillis = startedAtMillis,
            nowMillis = completedAt
        )

        val completed = progress.map { item ->
            val snapshot = item.snapshot
            val actual = item.deltaSinceStart

            CompletedExecution(
                id = UUID.randomUUID().toString(),
                executionRecordId = recordId,
                goalId = snapshot.goalId,
                goalName = snapshot.goalName,
                currency = snapshot.currency,
                requiredAmount = snapshot.requiredAmount,
                actualAmount = actual,
                completedAtMillis = completedAt,
                canUndoUntilMillis = canUndoUntil,
                createdAtMillis = completedAt
            )
        }

        completedExecutionRepository.replaceForRecord(recordId, completed)
        executionRecordRepository.close(recordId, completedAt)
    }
}
