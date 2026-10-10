package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.transformLatest
import javax.inject.Inject

@OptIn(ExperimentalCoroutinesApi::class)
class GetExecutionSessionUseCase @Inject constructor(
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository,
    private val transactionRepository: TransactionRepository,
    private val assetRepository: AssetRepository,
    private val executionAssetRateRepository: ExecutionAssetRateRepository,
    private val legacyRateSnapshotBackfill: LegacyExecutionRateSnapshotBackfill
) {
    private val calculator = ExecutionProgressCalculator()
    private val refreshRevision = MutableStateFlow(0L)

    fun refresh() {
        refreshRevision.update { it + 1L }
    }

    fun currentExecuting(): Flow<ExecutionSession?> {
        return executionRecordRepository.getCurrentExecutingRecord().flatMapLatest { record ->
            if (record == null) {
                flowOf(null)
            } else {
                calculationForRecord(
                    recordId = record.id,
                    startedAtMillis = record.startedAtMillis ?: 0L,
                    legacyRecord = record.takeIf { it.legacyRateSnapshotPending }
                ).map { calculation ->
                    calculation?.let {
                        ExecutionSession(
                            record = record,
                            goals = it.goals,
                            assetRates = it.assetRates
                        )
                    } ?: ExecutionSession(
                        record = record,
                        goals = emptyList(),
                        assetRates = emptyList(),
                        isProgressAvailable = false
                    )
                }
            }
        }
    }

    fun sessionForRecord(
        recordId: String,
        startedAtMillis: Long,
        legacyRecord: ExecutionRecord? = null
    ): Flow<List<ExecutionGoalProgress>> {
        return calculationForRecord(
            recordId = recordId,
            startedAtMillis = startedAtMillis,
            legacyRecord = legacyRecord
        ).mapNotNull { it?.goals }
    }

    private fun calculationForRecord(
        recordId: String,
        startedAtMillis: Long,
        legacyRecord: ExecutionRecord?
    ): Flow<ExecutionCalculation?> {
        val financialInputs = combine(
            executionSnapshotRepository.getByRecordId(recordId),
            transactionRepository.getAllTransactions(),
            allocationHistoryRepository.getAll(),
            executionAssetRateRepository.getByRecordId(recordId),
            allocationRepository.getAllAllocationsFlow()
        ) { snapshots, transactions, allocationHistory, assetRates, currentAllocations ->
            ExecutionCalculationInputs(
                snapshots = snapshots,
                transactions = transactions,
                allocationHistory = allocationHistory,
                assetRates = assetRates,
                currentAllocations = currentAllocations
            )
        }
        val aggregateInputs = combine(
            financialInputs,
            assetRepository.getAllAssets(),
            refreshRevision
        ) { inputs, assets, _ ->
            inputs.copy(
                knownAssetIds = assets.mapTo(hashSetOf()) { it.id },
                addressedAssetIds = assets
                    .asSequence()
                    .filter { !it.address.isNullOrBlank() }
                    .mapTo(hashSetOf()) { it.id }
            )
        }
        return aggregateInputs.transformLatest { inputs ->
            try {
                emit(
                    calculate(
                        inputs = inputs,
                        startedAtMillis = startedAtMillis,
                        legacyRecord = legacyRecord
                    )
                )
            } catch (error: Exception) {
                if (!error.isRecoverableSourceIncoherence()) {
                    throw error
                }
                // Room repositories publish independently. A hybrid aggregate
                // can therefore be temporarily incoherent even though a later
                // emission will be valid. Publish explicit unavailability to
                // current-session observers, keep the flow alive, and let the
                // next aggregate snapshot drive a fresh calculation.
                emit(null)
            }
        }
    }

    private suspend fun calculate(
        inputs: ExecutionCalculationInputs,
        startedAtMillis: Long,
        legacyRecord: ExecutionRecord?
    ): ExecutionCalculation {
        if (inputs.snapshots.isEmpty()) {
            throw UnprovenExecutionContributionAttributionException(
                "Execution contribution attribution is unavailable because execution snapshots are missing"
            )
        }
        if (startedAtMillis <= 0L) {
            throw UnprovenExecutionContributionAttributionException(
                "Execution contribution attribution is unavailable because the execution start is invalid"
            )
        }
        val nowMillis = System.currentTimeMillis()
        val goalIds = inputs.snapshots.mapTo(hashSetOf()) { it.goalId }
        val relevantAssetIds = ExecutionAttributionScopeValidator.requiredAssetIds(
            goalIds = goalIds,
            currentAllocations = inputs.currentAllocations,
            allocationHistory = inputs.allocationHistory,
            startedAtMillis = startedAtMillis,
            nowMillis = nowMillis
        )
        ExecutionAttributionScopeValidator.requireProvableTransactionLedger(
            requiredAssetIds = relevantAssetIds,
            knownAssetIds = inputs.knownAssetIds,
            addressedAssetIds = inputs.addressedAssetIds,
            onChainTransactionAssetIds = inputs.transactions
                .asSequence()
                .filter { it.source == TransactionSource.ON_CHAIN }
                .mapTo(hashSetOf()) { it.assetId }
        )
        val ratesForCalculation = legacyRecord?.let { record ->
            legacyRateSnapshotBackfill.resolve(
                record,
                inputs.snapshots,
                inputs.allocationHistory
            )
        } ?: inputs.assetRates
        ExecutionAttributionScopeValidator.requireCompleteRateMatrix(
            requiredAssetIds = relevantAssetIds,
            snapshotCurrencies = inputs.snapshots.mapTo(hashSetOf()) { it.currency.uppercase() },
            assetRates = ratesForCalculation
        )
        val relevantTransactions = inputs.transactions.filter { it.assetId in relevantAssetIds }
        val relevantAllocationHistory = inputs.allocationHistory.filter {
            it.assetId in relevantAssetIds
        }
        return ExecutionCalculation(
            goals = calculator.calculateForSnapshots(
                snapshots = inputs.snapshots,
                transactions = relevantTransactions,
                allocationHistory = relevantAllocationHistory,
                assetRates = ratesForCalculation,
                startedAtMillis = startedAtMillis,
                nowMillis = nowMillis
            ),
            assetRates = ratesForCalculation
        )
    }

    private fun Exception.isRecoverableSourceIncoherence(): Boolean {
        return this is UnprovenExecutionContributionAttributionException ||
            this is MissingExecutionAssetRateException
    }

    private data class ExecutionCalculationInputs(
        val snapshots: List<ExecutionSnapshot>,
        val transactions: List<Transaction>,
        val allocationHistory: List<AllocationHistory>,
        val assetRates: List<ExecutionAssetRate>,
        val currentAllocations: List<Allocation>,
        val knownAssetIds: Set<String> = emptySet(),
        val addressedAssetIds: Set<String> = emptySet()
    )

    private data class ExecutionCalculation(
        val goals: List<ExecutionGoalProgress>,
        val assetRates: List<ExecutionAssetRate>
    )

}
