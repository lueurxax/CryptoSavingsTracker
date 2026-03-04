package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.CompletedExecution
import com.xax.CryptoSavingsTracker.domain.model.CompletionEvent
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletionEventRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import kotlinx.coroutines.flow.first
import java.security.MessageDigest
import java.util.UUID
import javax.inject.Inject

class CompleteExecutionUseCase @Inject constructor(
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val completedExecutionRepository: CompletedExecutionRepository,
    private val completionEventRepository: CompletionEventRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository,
    private val transactionRepository: TransactionRepository,
    private val transactionRunner: ExecutionTransitionTransactionRunner
) {
    private val calculator = ExecutionProgressCalculator()

    suspend operator fun invoke(recordId: String): Result<Unit> = runCatching {
        val record = executionRecordRepository.getRecordById(recordId)
            ?: throw IllegalStateException("Execution record not found")
        if (record.status != ExecutionStatus.EXECUTING) {
            throw IllegalStateException(ExecutionActionCopyCatalog.finishBlockedNoExecuting())
        }
        val startedAtMillis = record.startedAtMillis
            ?: throw IllegalStateException("Execution record missing startedAt")

        val snapshots = executionSnapshotRepository.getByRecordId(recordId).first()
        if (snapshots.isEmpty()) {
            throw IllegalStateException("No execution snapshots found")
        }

        val completedAt = System.currentTimeMillis()
        val canUndoUntil = completedAt + 24L * 60L * 60L * 1000L
        val sequence = completionEventRepository.getNextSequence(recordId)

        val progress = calculator.calculateForSnapshots(
            snapshots = snapshots,
            transactions = transactionRepository.getAllTransactions().first(),
            allocationHistory = allocationHistoryRepository.getAll().first(),
            startedAtMillis = startedAtMillis,
            nowMillis = completedAt
        )

        val completionRows = progress.map { item ->
            val snapshot = item.snapshot
            val actual = item.contributed

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

        val sourceDiscriminator = buildSourceDiscriminator(completionRows, completedAt)
        val completionEventId = UUID.randomUUID().toString()
        val completionEvent = CompletionEvent(
            id = completionEventId,
            executionRecordId = recordId,
            monthLabel = record.monthLabel,
            sequence = sequence,
            sourceDiscriminator = sourceDiscriminator,
            completedAtMillis = completedAt,
            completionSnapshotRef = completionEventId,
            createdAtMillis = completedAt
        )

        val completed = completionRows.map { it.copy(completionEventId = completionEventId) }

        transactionRunner.run {
            completionEventRepository.insert(completionEvent)
            completedExecutionRepository.append(completed)
            executionRecordRepository.close(recordId, completedAt, canUndoUntil)
        }
    }

    private fun buildSourceDiscriminator(
        rows: List<CompletedExecution>,
        completedAtMillis: Long
    ): String {
        val rowIds = rows.map { it.id }.sorted().joinToString(",")
        val goalIds = rows.map { it.goalId }.sorted().joinToString(",")
        val payload = "$rowIds|$goalIds|${rows.size}|$completedAtMillis"
        val hashBytes = MessageDigest.getInstance("SHA-256")
            .digest(payload.toByteArray(Charsets.UTF_8))
        return hashBytes.joinToString("") { "%02x".format(it) }
    }
}
