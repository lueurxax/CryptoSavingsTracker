package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.CompletedExecution
import com.xax.CryptoSavingsTracker.domain.model.CompletionEvent
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletionEventRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.first
import java.security.MessageDigest
import java.util.UUID
import javax.inject.Inject

class CompleteExecutionUseCase @Inject constructor(
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val completedExecutionRepository: CompletedExecutionRepository,
    private val completionEventRepository: CompletionEventRepository,
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository,
    private val transactionRepository: TransactionRepository,
    private val assetRepository: AssetRepository,
    private val transactionRunner: ExecutionTransitionTransactionRunner,
    private val executionAssetRateRepository: ExecutionAssetRateRepository,
    private val legacyRateSnapshotBackfill: LegacyExecutionRateSnapshotBackfill,
    private val planningSettings: MonthlyPlanningSettings
) {
    private val calculator = ExecutionProgressCalculator()

    suspend operator fun invoke(recordId: String): Result<Unit> = try {
        complete(recordId)
        Result.success(Unit)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        Result.failure(failure)
    }

    private suspend fun complete(recordId: String) {
        val initialRecord = executionRecordRepository.getRecordById(recordId)
            ?: throw IllegalStateException("Execution record not found")
        if (initialRecord.status != ExecutionStatus.EXECUTING) {
            throw IllegalStateException(ExecutionActionCopyCatalog.finishBlockedNoExecuting())
        }
        val initialStartedAtMillis = initialRecord.startedAtMillis
            ?: throw IllegalStateException("Execution record missing startedAt")
        if (initialStartedAtMillis <= 0L) {
            throw UnprovenExecutionContributionAttributionException(
                "Execution contribution attribution is unavailable because the execution start is invalid"
            )
        }

        val initialSnapshots = executionSnapshotRepository.getByRecordId(recordId).first()
        if (initialSnapshots.isEmpty()) {
            throw UnprovenExecutionContributionAttributionException(
                "Execution contribution attribution is unavailable because execution snapshots are missing"
            )
        }

        val initialTransactions = transactionRepository.getAllTransactions().first()
        val initialAssets = assetRepository.getAllAssets().first()
        val initialAllocations = allocationRepository.getAllAllocationsFlow().first()
        val initialAllocationHistory = allocationHistoryRepository.getAll().first()
        val initialGoalIds = initialSnapshots.mapTo(hashSetOf()) { it.goalId }
        val initialRelevantAssetIds = ExecutionAttributionScopeValidator.requiredAssetIds(
            goalIds = initialGoalIds,
            currentAllocations = initialAllocations,
            allocationHistory = initialAllocationHistory,
            startedAtMillis = initialStartedAtMillis,
            nowMillis = System.currentTimeMillis()
        )
        ExecutionAttributionScopeValidator.requireProvableTransactionLedger(
            requiredAssetIds = initialRelevantAssetIds,
            knownAssetIds = initialAssets.mapTo(hashSetOf()) { it.id },
            addressedAssetIds = initialAssets
                .asSequence()
                .filter { !it.address.isNullOrBlank() }
                .mapTo(hashSetOf()) { it.id },
            onChainTransactionAssetIds = initialTransactions
                .asSequence()
                .filter { it.source == TransactionSource.ON_CHAIN }
                .mapTo(hashSetOf()) { it.assetId }
        )

        if (initialRecord.legacyRateSnapshotPending) {
            legacyRateSnapshotBackfill.resolve(
                record = initialRecord,
                snapshots = initialSnapshots,
                allocationHistory = initialAllocationHistory
            )
        }

        transactionRunner.run {
            val record = executionRecordRepository.getRecordById(recordId)
                ?: throw IllegalStateException("Execution record not found")
            if (
                record.status != ExecutionStatus.EXECUTING ||
                record.startedAtMillis != initialStartedAtMillis
            ) {
                throw IllegalStateException(ExecutionActionCopyCatalog.finishBlockedNoExecuting())
            }
            val startedAtMillis = record.startedAtMillis
                ?: throw IllegalStateException("Execution record missing startedAt")
            if (startedAtMillis <= 0L) {
                throw UnprovenExecutionContributionAttributionException(
                    "Execution contribution attribution is unavailable because the execution start is invalid"
                )
            }
            val snapshots = executionSnapshotRepository.getByRecordId(recordId).first()
            if (snapshots.isEmpty()) {
                throw UnprovenExecutionContributionAttributionException(
                    "Execution contribution attribution is unavailable because execution snapshots are missing"
                )
            }

            val completedAt = System.currentTimeMillis()
            val canUndoUntil = completedAt +
                planningSettings.undoGracePeriodHours.toLong() * MILLIS_PER_HOUR
            val sequence = completionEventRepository.getNextSequence(recordId)
            val transactions = transactionRepository.getAllTransactions().first()
            val assets = assetRepository.getAllAssets().first()
            val currentAllocations = allocationRepository.getAllAllocationsFlow().first()
            val allocationHistory = allocationHistoryRepository.getAll().first()
            val assetRates = executionAssetRateRepository.getByRecordId(recordId).first()
            val goalIds = snapshots.mapTo(hashSetOf()) { it.goalId }
            val relevantAssetIds = ExecutionAttributionScopeValidator.requiredAssetIds(
                goalIds = goalIds,
                currentAllocations = currentAllocations,
                allocationHistory = allocationHistory,
                startedAtMillis = startedAtMillis,
                nowMillis = completedAt
            )
            ExecutionAttributionScopeValidator.requireProvableTransactionLedger(
                requiredAssetIds = relevantAssetIds,
                knownAssetIds = assets.mapTo(hashSetOf()) { it.id },
                addressedAssetIds = assets
                    .asSequence()
                    .filter { !it.address.isNullOrBlank() }
                    .mapTo(hashSetOf()) { it.id },
                onChainTransactionAssetIds = transactions
                    .asSequence()
                    .filter { it.source == TransactionSource.ON_CHAIN }
                    .mapTo(hashSetOf()) { it.assetId }
            )
            ExecutionAttributionScopeValidator.requireCompleteRateMatrix(
                requiredAssetIds = relevantAssetIds,
                snapshotCurrencies = snapshots.mapTo(hashSetOf()) { it.currency.uppercase() },
                assetRates = assetRates
            )
            val relevantTransactions = transactions.filter { it.assetId in relevantAssetIds }
            val relevantAllocationHistory = allocationHistory.filter {
                it.assetId in relevantAssetIds
            }
            val progress = calculator.calculateForSnapshots(
                snapshots = snapshots,
                transactions = relevantTransactions,
                allocationHistory = relevantAllocationHistory,
                assetRates = assetRates,
                startedAtMillis = startedAtMillis,
                nowMillis = completedAt
            )

            val completionRows = progress.map { item ->
                val snapshot = item.snapshot
                CompletedExecution(
                    id = UUID.randomUUID().toString(),
                    executionRecordId = recordId,
                    goalId = snapshot.goalId,
                    goalName = snapshot.goalName,
                    currency = snapshot.currency,
                    requiredAmount = snapshot.requiredAmount,
                    actualAmount = item.contributed,
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

    private companion object {
        const val MILLIS_PER_HOUR = 60L * 60L * 1000L
    }
}
