package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import javax.inject.Inject

@OptIn(ExperimentalCoroutinesApi::class)
class GetExecutionSessionUseCase @Inject constructor(
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository,
    private val transactionRepository: TransactionRepository,
    private val assetRepository: AssetRepository,
    private val calculateProgress: CalculateExecutionProgressUseCase
) {
    private val refreshRevision = MutableStateFlow(0L)

    /** Retry valuation explicitly without requiring a transaction or an asset edit. */
    fun refresh() {
        refreshRevision.update { it + 1L }
    }

    fun currentExecuting(): Flow<ExecutionSession?> {
        return executionRecordRepository.getCurrentExecutingRecord().flatMapLatest { record ->
            if (record == null) {
                flowOf(null)
            } else {
                sessionForRecord(record.id, startedAtMillis = record.startedAtMillis ?: 0L).map { goals ->
                    ExecutionSession(record = record, goals = goals)
                }
            }
        }
    }

    fun sessionForRecord(recordId: String, startedAtMillis: Long): Flow<List<ExecutionGoalProgress>> {
        return combine(
            executionSnapshotRepository.getByRecordId(recordId),
            transactionRepository.getAllTransactions(),
            allocationHistoryRepository.getAll(),
            assetRepository.getAllAssets(),
            refreshRevision
        ) { snapshots, transactions, allocationHistory, assets, _ ->
            if (snapshots.isEmpty() || startedAtMillis <= 0L) {
                emptyList()
            } else {
                calculateProgress(
                    snapshots = snapshots,
                    transactions = transactions,
                    allocationHistory = allocationHistory,
                    assets = assets,
                    startedAtMillis = startedAtMillis
                )
            }
        }
    }
}
