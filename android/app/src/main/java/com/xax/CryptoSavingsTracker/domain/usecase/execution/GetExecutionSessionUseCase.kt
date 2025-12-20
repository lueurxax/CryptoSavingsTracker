package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import javax.inject.Inject

@OptIn(ExperimentalCoroutinesApi::class)
class GetExecutionSessionUseCase @Inject constructor(
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository,
    private val transactionRepository: TransactionRepository
) {
    private val calculator = ExecutionProgressCalculator()

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
            allocationHistoryRepository.getAll()
        ) { snapshots, transactions, allocationHistory ->
            if (snapshots.isEmpty() || startedAtMillis <= 0L) {
                emptyList()
            } else {
                calculator.calculateForSnapshots(
                    snapshots = snapshots,
                    transactions = transactions,
                    allocationHistory = allocationHistory,
                    startedAtMillis = startedAtMillis
                )
            }
        }
    }
}
