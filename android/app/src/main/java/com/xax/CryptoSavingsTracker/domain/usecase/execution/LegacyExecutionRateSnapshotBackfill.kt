package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import kotlinx.coroutines.flow.first
import javax.inject.Inject

/**
 * One-time compatibility path for execution records that existed before v6.
 *
 * New records always persist their complete rate matrix at start. The migration
 * marks v5 records that were executing, plus closed records whose undo window
 * remains open; a non-empty matrix under that marker is corruption, not a
 * reason to fetch replacement live rates.
 */
class LegacyExecutionRateSnapshotBackfill @Inject constructor(
    private val executionAssetRateRepository: ExecutionAssetRateRepository,
    private val executionRecordRepository: ExecutionRecordRepository,
    private val transactionRunner: ExecutionTransitionTransactionRunner,
    private val assetRateResolver: ExecutionAssetRateResolver,
    private val assetRepository: AssetRepository,
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository
) {
    suspend fun resolve(
        record: ExecutionRecord,
        snapshots: List<ExecutionSnapshot>,
        allocationHistory: List<AllocationHistory>
    ): List<ExecutionAssetRate> {
        if (!record.legacyRateSnapshotPending) {
            return executionAssetRateRepository.getByRecordId(record.id).first()
        }

        val preparation = transactionRunner.run {
            val persistedRates = executionAssetRateRepository.getByRecordId(record.id).first()
            val latestRecord = executionRecordRepository.getRecordById(record.id)
                ?: throw IllegalStateException("Execution record not found")
            if (!latestRecord.legacyRateSnapshotPending) {
                // The enclosing Flow can still hold the old marker while Room
                // emits the transaction's rate rows. Re-read the committed winner.
                BackfillPreparation.Complete(
                    executionAssetRateRepository.getByRecordId(record.id).first()
                )
            } else {
                if (persistedRates.isNotEmpty()) {
                    throw IllegalStateException(
                        "Legacy execution rate snapshot is partial or corrupt for ${record.id}"
                    )
                }
                BackfillPreparation.Capture(
                    captureExecutionRateScopeFingerprint(
                        assetRepository = assetRepository,
                        allocationRepository = allocationRepository,
                        eligibleGoalIds = snapshots.mapTo(hashSetOf()) { it.goalId },
                        historicalAllocations = allocationHistory
                    )
                )
            }
        }
        if (preparation is BackfillPreparation.Complete) return preparation.rates

        preparation as BackfillPreparation.Capture
        val rateScope = preparation.rateScope
        val snapshotCurrencies = snapshots.mapTo(mutableSetOf()) { it.currency.uppercase() }
        val capturedAtMillis = System.currentTimeMillis()
        val capturedRates = assetRateResolver.capture(
            assetIds = rateScope.assetIds,
            snapshotCurrencies = snapshotCurrencies,
            capturedAtMillis = capturedAtMillis
        )
        requireCompleteRateMatrix(rateScope.assetIds, snapshotCurrencies, capturedRates)

        return transactionRunner.run {
            // Capture happens outside the DB transaction. A concurrent caller may
            // have won while this one was fetching FX, so choose the persisted
            // winner instead of replacing it with a second live quote.
            val recordInsideTransaction = executionRecordRepository.getRecordById(record.id)
                ?: throw IllegalStateException("Execution record not found")
            val ratesInsideTransaction = executionAssetRateRepository.getByRecordId(record.id).first()
            if (!recordInsideTransaction.legacyRateSnapshotPending) {
                // Another transaction already committed its internally
                // validated matrix and cleared the marker atomically.
                return@run ratesInsideTransaction
            }
            if (ratesInsideTransaction.isNotEmpty()) {
                throw IllegalStateException(
                    "Legacy execution rate snapshot is partial or corrupt for ${record.id}"
                )
            }
            val commitScope = captureExecutionRateScopeFingerprint(
                assetRepository = assetRepository,
                allocationRepository = allocationRepository,
                eligibleGoalIds = snapshots.mapTo(hashSetOf()) { it.goalId },
                historicalAllocations = allocationHistoryRepository.getAll().first()
            )
            check(commitScope == rateScope) {
                "Execution rate snapshot scope changed while rates were captured; retry"
            }
            executionAssetRateRepository.replaceForRecord(record.id, capturedRates)
            executionRecordRepository.clearLegacyRateSnapshotPending(record.id)
            capturedRates
        }
    }

    private fun requireCompleteRateMatrix(
        assetIds: Set<String>,
        snapshotCurrencies: Set<String>,
        rates: List<ExecutionAssetRate>
    ) {
        val expectedPairs = assetIds.flatMap { assetId ->
            snapshotCurrencies.map { snapshotCurrency -> assetId to snapshotCurrency }
        }.toSet()
        val actualPairs = rates.map { rate ->
            rate.assetId to rate.snapshotCurrency.uppercase()
        }.toSet()
        if (actualPairs != expectedPairs || rates.any { !it.rate.isFinite() || it.rate <= 0.0 }) {
            throw IllegalStateException("Legacy execution rate snapshot is incomplete or invalid")
        }
    }

    private sealed interface BackfillPreparation {
        data class Complete(
            val rates: List<ExecutionAssetRate>
        ) : BackfillPreparation

        data class Capture(
            val rateScope: ExecutionRateScopeFingerprint
        ) : BackfillPreparation
    }
}
