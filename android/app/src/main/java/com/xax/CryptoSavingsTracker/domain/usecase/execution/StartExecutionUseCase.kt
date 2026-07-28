package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlan
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlan
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.MonthlyPlanRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyGoalPlanService
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningSnapshot
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningService
import com.xax.CryptoSavingsTracker.domain.util.MonthLabelUtils
import kotlinx.coroutines.flow.first
import java.util.UUID
import javax.inject.Inject

class StartExecutionUseCase @Inject constructor(
    private val monthlyPlanRepository: MonthlyPlanRepository,
    private val executionRecordRepository: ExecutionRecordRepository,
    private val executionSnapshotRepository: ExecutionSnapshotRepository,
    private val executionAssetRateRepository: ExecutionAssetRateRepository,
    private val assetRepository: AssetRepository,
    private val transactionRepository: TransactionRepository,
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository,
    private val assetRateResolver: ExecutionAssetRateResolver,
    private val transactionRunner: ExecutionTransitionTransactionRunner,
    private val monthlyGoalPlanService: MonthlyGoalPlanService,
    private val monthlyPlanningService: MonthlyPlanningService
) {
    suspend operator fun invoke(monthLabel: String = MonthLabelUtils.nowUtc()): Result<ExecutionRecord> = runCatching {
        val existingExecuting = executionRecordRepository.getCurrentExecutingRecord().first()
        if (existingExecuting != null) {
            throw IllegalStateException(
                ExecutionActionCopyCatalog.startBlockedAlreadyExecuting(existingExecuting.monthLabel)
            )
        }
        val existing = executionRecordRepository.getRecordByMonthLabelOnce(monthLabel)
        if (existing?.status == ExecutionStatus.CLOSED) {
            throw IllegalStateException(ExecutionActionCopyCatalog.startBlockedClosedMonth())
        }

        val initialPlanning = monthlyPlanningService.calculateExecutionSnapshot()
        initialPlanning.requireComplete()
        if (initialPlanning.requirements.isEmpty()) {
            throw IllegalStateException(ExecutionActionCopyCatalog.startBlockedMissingPlan())
        }
        val plan = transactionRunner.run {
            val competingExecution = executionRecordRepository.getCurrentExecutingRecord().first()
            if (competingExecution != null) {
                throw IllegalStateException(
                    ExecutionActionCopyCatalog.startBlockedAlreadyExecuting(competingExecution.monthLabel)
                )
            }
            requireUnchangedMonthRecord(monthLabel, existing)
            requireProvableExecutionLedger(
                captureExecutionLedgerScope(
                    eligibleGoalIds = initialPlanning.goals.mapTo(hashSetOf()) { it.id }
                )
            )
            val currentPlan = monthlyPlanRepository.getOrCreatePlan(monthLabel)
            monthlyGoalPlanService.syncPlans(monthLabel, initialPlanning.requirements)
            monthlyGoalPlanService.applyFlexAdjustment(monthLabel, initialPlanning.flexAdjustment)
            currentPlan
        }

        val sourceInput = transactionRunner.run {
            val competingExecution = executionRecordRepository.getCurrentExecutingRecord().first()
            if (competingExecution != null) {
                throw IllegalStateException(
                    ExecutionActionCopyCatalog.startBlockedAlreadyExecuting(competingExecution.monthLabel)
                )
            }
            captureStartInput(
                monthLabel = monthLabel,
                fallbackPlan = plan
            )
        }
        validateSourcePlanOutput(sourceInput.planning, sourceInput.goalPlans)
        requireProvableExecutionLedger(
            CapturedExecutionLedgerScope(
                rateScope = sourceInput.rateScope,
                requiredAssetIds = sourceInput.requiredAssetIds,
                onChainTransactionAssetIds = sourceInput.onChainTransactionAssetIds
            )
        )

        val now = System.currentTimeMillis()
        val planId = sourceInput.monthlyPlan.id
        // A persisted DRAFT has never entered execution. Legacy rows may still
        // contain a stale or zero timestamp, so every actual start begins now.
        val startedAtMillis = now
        val canUndoUntilMillis = startedAtMillis +
            sourceInput.planning.undoGracePeriodHours.toLong() * MILLIS_PER_HOUR
        val record = if (existing == null) {
            ExecutionRecord(
                id = UUID.randomUUID().toString(),
                planId = planId,
                monthLabel = monthLabel,
                status = ExecutionStatus.EXECUTING,
                startedAtMillis = startedAtMillis,
                closedAtMillis = null,
                canUndoUntilMillis = canUndoUntilMillis,
                createdAtMillis = now,
                updatedAtMillis = now
            )
        } else {
            existing.copy(
                planId = planId,
                status = ExecutionStatus.EXECUTING,
                startedAtMillis = startedAtMillis,
                closedAtMillis = null,
                canUndoUntilMillis = canUndoUntilMillis,
                updatedAtMillis = now,
                legacyRateSnapshotPending = false
            )
        }

        val requirementsByGoalId = sourceInput.planning.requirements.associateBy { it.goalId }
        val perGoalPlans = sourceInput.goalPlans.associateBy { it.goalId }
        val snapshots = sourceInput.planning.goals.map { goal ->
            val requirement = checkNotNull(requirementsByGoalId[goal.id]) {
                "Execution source missing requirement for ${goal.id}"
            }
            val goalPlan = checkNotNull(perGoalPlans[goal.id]) {
                "Execution source missing monthly plan for ${goal.id}"
            }

            ExecutionSnapshot(
                id = UUID.randomUUID().toString(),
                executionRecordId = record.id,
                goalId = goal.id,
                goalName = goal.name,
                currency = goal.currency,
                targetAmount = goal.targetAmount,
                currentTotalAtStart = requirement.currentTotal,
                requiredAmount = goalPlan.effectiveAmount,
                isProtected = goalPlan.isProtected,
                isSkipped = goalPlan.isSkipped,
                customAmount = goalPlan.customAmount,
                createdAtMillis = now
            )
        }

        val assetRates = assetRateResolver.capture(
            assetIds = sourceInput.requiredAssetIds,
            snapshotCurrencies = snapshots.map { it.currency }.toSet(),
            capturedAtMillis = now
        )
        validateCapturedRates(
            assetRates = assetRates,
            expectedAssetIds = sourceInput.requiredAssetIds,
            snapshotCurrencies = snapshots.mapTo(hashSetOf()) { it.currency.uppercase() }
        )

        transactionRunner.run {
            val competingExecution = executionRecordRepository.getCurrentExecutingRecord().first()
            if (competingExecution != null) {
                throw IllegalStateException(
                    ExecutionActionCopyCatalog.startBlockedAlreadyExecuting(competingExecution.monthLabel)
                )
            }
            requireUnchangedMonthRecord(monthLabel, existing)
            val commitInput = captureStartInput(
                monthLabel = monthLabel,
                fallbackPlan = null
            )
            check(commitInput.fingerprint == sourceInput.fingerprint) {
                "Execution inputs changed while rates were captured; retry"
            }
            validateSourcePlanOutput(commitInput.planning, commitInput.goalPlans)
            if (existing == null) {
                executionRecordRepository.insert(record)
            } else {
                executionRecordRepository.update(record)
            }
            executionSnapshotRepository.replaceForRecord(record.id, snapshots)
            executionAssetRateRepository.replaceForRecord(record.id, assetRates)
        }
        record
    }

    private suspend fun requireUnchangedMonthRecord(
        monthLabel: String,
        expected: ExecutionRecord?
    ) {
        val latest = executionRecordRepository.getRecordByMonthLabelOnce(monthLabel)
        when {
            expected == null && latest != null -> {
                if (latest.status == ExecutionStatus.CLOSED) {
                    throw IllegalStateException(ExecutionActionCopyCatalog.startBlockedClosedMonth())
                }
                throw IllegalStateException(ExecutionActionCopyCatalog.recordConflict())
            }
            expected != null && latest != expected -> {
                if (latest?.status == ExecutionStatus.CLOSED) {
                    throw IllegalStateException(ExecutionActionCopyCatalog.startBlockedClosedMonth())
                }
                throw IllegalStateException(ExecutionActionCopyCatalog.recordConflict())
            }
        }
    }

    private suspend fun captureStartInput(
        monthLabel: String,
        fallbackPlan: MonthlyPlan?
    ): CapturedExecutionStartInput {
        val planning = monthlyPlanningService.calculateExecutionSnapshot()
        planning.requireComplete()
        val monthlyPlan = monthlyPlanRepository.getPlanFlow(monthLabel).first()
            ?: fallbackPlan
            ?: throw IllegalStateException("Execution inputs changed while rates were captured; retry")
        val goalPlans = monthlyGoalPlanService.getPlansOnce(monthLabel)
        val ledgerScope = captureExecutionLedgerScope(
            eligibleGoalIds = planning.goals.mapTo(hashSetOf()) { it.id }
        )
        return CapturedExecutionStartInput(
            planning = planning,
            monthlyPlan = monthlyPlan,
            goalPlans = goalPlans,
            rateScope = ledgerScope.rateScope,
            requiredAssetIds = ledgerScope.requiredAssetIds,
            onChainTransactionAssetIds = ledgerScope.onChainTransactionAssetIds,
            fingerprint = executionStartInputFingerprint(
                planning = planning,
                monthlyPlan = monthlyPlan,
                goalPlans = goalPlans,
                rateScope = ledgerScope.rateScope,
                requiredAssetIds = ledgerScope.requiredAssetIds,
                onChainTransactionAssetIds = ledgerScope.onChainTransactionAssetIds
            )
        )
    }

    private suspend fun captureExecutionLedgerScope(
        eligibleGoalIds: Set<String>
    ): CapturedExecutionLedgerScope {
        val allocationHistory = allocationHistoryRepository.getAll().first()
        val rateScope = captureExecutionRateScopeFingerprint(
            assetRepository = assetRepository,
            allocationRepository = allocationRepository,
            eligibleGoalIds = eligibleGoalIds,
            historicalAllocations = allocationHistory
        )
        val attributionNowMillis = System.currentTimeMillis()
        val requiredAssetIds = ExecutionAttributionScopeValidator.requiredAssetIds(
            goalIds = eligibleGoalIds,
            currentAllocations = allocationRepository.getAllAllocationsFlow().first(),
            allocationHistory = allocationHistory,
            startedAtMillis = attributionNowMillis,
            nowMillis = attributionNowMillis
        )
        // rateScope remains intentionally broader: it fingerprints historical
        // inputs whose mutation could change the derived required set, while
        // only requiredAssetIds participate in FX capture and attribution.
        val onChainTransactionAssetIds = transactionRepository
            .getAllTransactions()
            .first()
            .asSequence()
            .filter {
                it.source == TransactionSource.ON_CHAIN &&
                    it.assetId in requiredAssetIds
            }
            .mapTo(hashSetOf()) { it.assetId }
        return CapturedExecutionLedgerScope(
            rateScope = rateScope,
            requiredAssetIds = requiredAssetIds,
            onChainTransactionAssetIds = onChainTransactionAssetIds
        )
    }

    private fun requireProvableExecutionLedger(scope: CapturedExecutionLedgerScope) {
        ExecutionAttributionScopeValidator.requireProvableTransactionLedger(
            requiredAssetIds = scope.requiredAssetIds,
            knownAssetIds = scope.rateScope.assetIds,
            addressedAssetIds = scope.rateScope.assets
                .asSequence()
                .filter { !it.address.isNullOrBlank() }
                .mapTo(hashSetOf()) { it.id },
            onChainTransactionAssetIds = scope.onChainTransactionAssetIds
        )
    }

    private fun validateSourcePlanOutput(
        planning: MonthlyPlanningSnapshot,
        goalPlans: List<MonthlyGoalPlan>
    ) {
        val requirements = planning.requirements.associateBy { it.goalId }
        val plans = goalPlans.associateBy { it.goalId }
        check(requirements.keys == planning.goals.mapTo(hashSetOf()) { it.id }) {
            "Execution planning requirements changed; retry"
        }
        check(plans.keys.containsAll(requirements.keys)) {
            "Execution monthly goal plans changed; retry"
        }
        for ((goalId, requirement) in requirements) {
            val goalPlan = checkNotNull(plans[goalId])
            check(
                goalPlan.requiredMonthly.toBits() == requirement.requiredMonthly.toBits() &&
                    goalPlan.remainingAmount.toBits() == requirement.remainingAmount.toBits() &&
                    goalPlan.monthsRemaining == requirement.monthsRemaining &&
                    goalPlan.currency.equals(requirement.currency, ignoreCase = true) &&
                    goalPlan.status == requirement.status
            ) {
                "Execution monthly goal plan is stale for $goalId; retry"
            }
        }
    }

    private fun validateCapturedRates(
        assetRates: List<com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate>,
        expectedAssetIds: Set<String>,
        snapshotCurrencies: Set<String>
    ) {
        val expectedKeys = expectedAssetIds.flatMapTo(hashSetOf()) { assetId ->
            snapshotCurrencies.map { currency -> assetId to currency }
        }
        val actualKeys = assetRates.map { rate ->
            rate.assetId to rate.snapshotCurrency.uppercase()
        }
        check(actualKeys.size == actualKeys.toSet().size && actualKeys.toSet() == expectedKeys) {
            "Execution FX snapshot is incomplete or ambiguous; retry"
        }
        check(assetRates.all { it.rate.isFinite() && it.rate > 0.0 && it.capturedAtMillis >= 0L }) {
            "Execution FX snapshot contains invalid provenance; retry"
        }
    }

    private data class CapturedExecutionStartInput(
        val planning: MonthlyPlanningSnapshot,
        val monthlyPlan: MonthlyPlan,
        val goalPlans: List<MonthlyGoalPlan>,
        val rateScope: ExecutionRateScopeFingerprint,
        val requiredAssetIds: Set<String>,
        val onChainTransactionAssetIds: Set<String>,
        val fingerprint: ExecutionStartInputFingerprint
    )

    private data class CapturedExecutionLedgerScope(
        val rateScope: ExecutionRateScopeFingerprint,
        val requiredAssetIds: Set<String>,
        val onChainTransactionAssetIds: Set<String>
    )

    private companion object {
        const val MILLIS_PER_HOUR = 60L * 60L * 1000L
    }
}
