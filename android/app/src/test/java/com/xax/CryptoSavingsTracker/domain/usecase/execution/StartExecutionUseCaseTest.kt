package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.repository.MonthlyGoalPlanRepository
import com.xax.CryptoSavingsTracker.domain.usecase.planning.FlexAdjustmentService
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.ExecutionAssetRate
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlan
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlanState
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlan
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanSettings
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.domain.model.Transaction
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
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningIssue
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningIssueReason
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningService
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningSnapshot
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.coVerifyOrder
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import java.time.LocalDate

class StartExecutionUseCaseTest {
    @Test
    fun `start rejects a competing execution before any planning write`() = runTest {
        val monthlyPlans = mockk<MonthlyPlanRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val goalPlans = mockk<MonthlyGoalPlanService>(relaxed = true)
        val planning = mockk<MonthlyPlanningService>(relaxed = true)
        val competingRecord = com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord(
            id = "active-record",
            planId = "active-plan",
            monthLabel = "2026-06",
            status = com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus.EXECUTING,
            startedAtMillis = 900L,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = 900L,
            updatedAtMillis = 900L
        )
        coEvery { records.getCurrentExecutingRecord() } returns flowOf(competingRecord)

        val result = StartExecutionUseCase(
            monthlyPlanRepository = monthlyPlans,
            executionRecordRepository = records,
            executionSnapshotRepository = mockk(relaxed = true),
            executionAssetRateRepository = mockk(relaxed = true),
            assetRepository = mockk(),
            transactionRepository = mockk(relaxed = true),
            allocationRepository = mockk(),
            allocationHistoryRepository = mockk(),
            assetRateResolver = mockk(),
            transactionRunner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            },
            monthlyGoalPlanService = goalPlans,
            monthlyPlanningService = planning
        )("2026-07")

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("2026-06")
        coVerify(exactly = 0) { records.getRecordByMonthLabelOnce(any()) }
        coVerify(exactly = 0) { planning.calculateExecutionSnapshot() }
        coVerify(exactly = 0) { monthlyPlans.getOrCreatePlan(any()) }
        coVerify(exactly = 0) { goalPlans.syncPlans(any(), any()) }
        coVerify(exactly = 0) { goalPlans.applyFlexAdjustment(any(), any()) }
    }

    @Test
    fun `start rejects an execution that appears during planning before any plan write`() = runTest {
        val month = "2026-07"
        val goal = testGoal()
        val requirement = MonthlyRequirement(
            id = "requirement-1",
            goalId = goal.id,
            goalName = goal.name,
            currency = goal.currency,
            targetAmount = goal.targetAmount,
            currentTotal = 0.0,
            remainingAmount = goal.targetAmount,
            monthsRemaining = 10,
            requiredMonthly = 10.0,
            progress = 0.0,
            deadline = goal.deadline,
            status = RequirementStatus.ON_TRACK
        )
        val competingRecord = com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord(
            id = "active-record",
            planId = "active-plan",
            monthLabel = "2026-06",
            status = com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus.EXECUTING,
            startedAtMillis = 900L,
            closedAtMillis = null,
            canUndoUntilMillis = null,
            createdAtMillis = 900L,
            updatedAtMillis = 900L
        )
        val monthlyPlans = mockk<MonthlyPlanRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val goalPlans = mockk<MonthlyGoalPlanService>(relaxed = true)
        val planning = mockk<MonthlyPlanningService>()
        coEvery { records.getCurrentExecutingRecord() } returnsMany listOf(
            flowOf(null),
            flowOf(competingRecord)
        )
        var existingMonthRecord: com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord? = null
        coEvery { records.getRecordByMonthLabelOnce(month) } answers { existingMonthRecord }
        coEvery { planning.calculateExecutionSnapshot() } returns MonthlyPlanningSnapshot(
            goals = listOf(goal),
            requirements = listOf(requirement),
            fundingEvidence = emptyList(),
            paymentDay = 1,
            flexAdjustment = 1.0,
            displayCurrency = "USD",
            issues = emptyList()
        )

        val result = StartExecutionUseCase(
            monthlyPlanRepository = monthlyPlans,
            executionRecordRepository = records,
            executionSnapshotRepository = mockk(relaxed = true),
            executionAssetRateRepository = mockk(relaxed = true),
            assetRepository = mockk(),
            transactionRepository = mockk(relaxed = true),
            allocationRepository = mockk(),
            allocationHistoryRepository = mockk(),
            assetRateResolver = mockk(),
            transactionRunner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            },
            monthlyGoalPlanService = goalPlans,
            monthlyPlanningService = planning
        )(month)

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("2026-06")
        coVerify(exactly = 0) { monthlyPlans.getOrCreatePlan(any()) }
        coVerify(exactly = 0) { goalPlans.syncPlans(any(), any()) }
        coVerify(exactly = 0) { goalPlans.applyFlexAdjustment(any(), any()) }
    }

    @Test
    fun `start rejects an already closed month before any planning write`() = runTest {
        val month = "2026-07"
        val now = 1_000L
        val goal = testGoal()
        val requirement = MonthlyRequirement(
            id = "requirement-1",
            goalId = goal.id,
            goalName = goal.name,
            currency = goal.currency,
            targetAmount = goal.targetAmount,
            currentTotal = 0.0,
            remainingAmount = goal.targetAmount,
            monthsRemaining = 10,
            requiredMonthly = 10.0,
            progress = 0.0,
            deadline = goal.deadline,
            status = RequirementStatus.ON_TRACK
        )
        val closedRecord = com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord(
            id = "closed-record",
            planId = "plan-1",
            monthLabel = month,
            status = com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus.CLOSED,
            startedAtMillis = now - 100L,
            closedAtMillis = now,
            canUndoUntilMillis = now + 1_000L,
            createdAtMillis = now - 100L,
            updatedAtMillis = now
        )
        val monthlyPlans = mockk<MonthlyPlanRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val goalPlans = mockk<MonthlyGoalPlanService>(relaxed = true)
        val planning = mockk<MonthlyPlanningService>()
        coEvery { records.getCurrentExecutingRecord() } returns flowOf(null)
        coEvery { records.getRecordByMonthLabelOnce(month) } returns closedRecord
        coEvery { planning.calculateExecutionSnapshot() } returns MonthlyPlanningSnapshot(
            goals = listOf(goal),
            requirements = listOf(requirement),
            fundingEvidence = emptyList(),
            paymentDay = 1,
            flexAdjustment = 1.0,
            displayCurrency = "USD",
            issues = emptyList()
        )

        val result = StartExecutionUseCase(
            monthlyPlanRepository = monthlyPlans,
            executionRecordRepository = records,
            executionSnapshotRepository = mockk(relaxed = true),
            executionAssetRateRepository = mockk(relaxed = true),
            assetRepository = mockk(),
            transactionRepository = mockk(relaxed = true),
            allocationRepository = mockk(),
            allocationHistoryRepository = mockk(),
            assetRateResolver = mockk(),
            transactionRunner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            },
            monthlyGoalPlanService = goalPlans,
            monthlyPlanningService = planning
        )(month)

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("closed")
        coVerify(exactly = 0) { monthlyPlans.getOrCreatePlan(any()) }
        coVerify(exactly = 0) { goalPlans.syncPlans(any(), any()) }
        coVerify(exactly = 0) { goalPlans.applyFlexAdjustment(any(), any()) }
    }

    @Test
    fun `start rejects incomplete same-currency balance snapshot before any persistence write`() = runTest {
        val monthlyPlans = mockk<MonthlyPlanRepository>(relaxed = true)
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val snapshots = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val executionRates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val planning = mockk<MonthlyPlanningService>()
        val goal = testGoal()
        coEvery { records.getCurrentExecutingRecord() } returns flowOf(null)
        coEvery { planning.calculateExecutionSnapshot() } returns MonthlyPlanningSnapshot(
            goals = listOf(goal),
            requirements = emptyList(),
            fundingEvidence = emptyList(),
            paymentDay = 1,
            flexAdjustment = 1.0,
            displayCurrency = "USD",
            issues = listOf(
                MonthlyPlanningIssue(
                    reason = MonthlyPlanningIssueReason.STALE_ON_CHAIN_BALANCE,
                    goalId = goal.id,
                    assetId = "usd-wallet"
                )
            )
        )

        val result = StartExecutionUseCase(
            monthlyPlanRepository = monthlyPlans,
            executionRecordRepository = records,
            executionSnapshotRepository = snapshots,
            executionAssetRateRepository = executionRates,
            assetRepository = mockk(),
            transactionRepository = mockk(relaxed = true),
            allocationRepository = mockk(),
            allocationHistoryRepository = mockk(),
            assetRateResolver = mockk(),
            transactionRunner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            },
            monthlyGoalPlanService = mockk(),
            monthlyPlanningService = planning
        )("2026-07")

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("incomplete")
        coVerify(exactly = 0) { monthlyPlans.getOrCreatePlan(any()) }
        coVerify(exactly = 0) { records.insert(any()) }
        coVerify(exactly = 0) { records.update(any()) }
        coVerify(exactly = 0) { snapshots.replaceForRecord(any(), any()) }
        coVerify(exactly = 0) { executionRates.replaceForRecord(any(), any()) }
    }

    @Test
    fun `start rejects changed rate scope or edited goal inputs before commit`() = runTest {
        val monthlyPlans = mockk<MonthlyPlanRepository>()
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val snapshots = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val executionRates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val assets = mockk<AssetRepository>()
        val transactions = mockk<TransactionRepository>()
        val allocations = mockk<AllocationRepository>()
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val rateResolver = mockk<ExecutionAssetRateResolver>()
        val goalPlans = mockk<MonthlyGoalPlanService>()
        val planning = mockk<MonthlyPlanningService>()
        val month = "2026-07"
        val now = 1_000L

        val goal = Goal(
            id = "goal-1",
            name = "USD goal",
            currency = "USD",
            targetAmount = 100.0,
            deadline = LocalDate.of(2026, 12, 31),
            startDate = LocalDate.of(2026, 1, 1),
            lifecycleStatus = GoalLifecycleStatus.ACTIVE,
            lifecycleStatusChangedAt = null,
            emoji = null,
            description = null,
            link = null,
            reminderFrequency = null,
            reminderTimeMillis = null,
            firstReminderDate = null,
            createdAt = now,
            updatedAt = now
        )
        val requirement = MonthlyRequirement(
            id = "requirement-1",
            goalId = goal.id,
            goalName = goal.name,
            currency = goal.currency,
            targetAmount = goal.targetAmount,
            currentTotal = 0.0,
            remainingAmount = 100.0,
            monthsRemaining = 5,
            requiredMonthly = 20.0,
            progress = 0.0,
            deadline = goal.deadline,
            status = RequirementStatus.ON_TRACK
        )
        val plan = MonthlyPlan(
            id = "plan-1",
            monthLabel = month,
            status = MonthlyPlanStatus.DRAFT,
            flexPercentage = 1.0,
            totalRequired = 20.0,
            settings = MonthlyPlanSettings(),
            createdAtUtcMillis = now,
            lastModifiedAtUtcMillis = now
        )
        val goalPlan = MonthlyGoalPlan(
            id = "goal-plan-1",
            goalId = goal.id,
            monthLabel = month,
            requiredMonthly = 20.0,
            remainingAmount = 100.0,
            monthsRemaining = 5,
            currency = "USD",
            status = RequirementStatus.ON_TRACK,
            state = MonthlyGoalPlanState.DRAFT,
            customAmount = null,
            isProtected = false,
            isSkipped = false,
            createdAtUtcMillis = now,
            lastModifiedAtUtcMillis = now
        )
        val capturedRates = listOf(
            ExecutionAssetRate(
                assetId = "btc-asset",
                snapshotCurrency = "USD",
                rate = 10_000.0,
                capturedAtMillis = now
            ),
            ExecutionAssetRate(
                assetId = "eth-asset",
                snapshotCurrency = "USD",
                rate = 2_000.0,
                capturedAtMillis = now
            )
        )

        coEvery { records.getCurrentExecutingRecord() } returns flowOf(null)
        coEvery { monthlyPlans.getOrCreatePlan(month) } returns plan
        every { monthlyPlans.getPlanFlow(month) } returns flowOf(plan)
        var planningGoal = goal
        var planningGoalRetired = false
        var planningUndoGracePeriodHours = 24
        coEvery { planning.calculateExecutionSnapshot() } answers {
            MonthlyPlanningSnapshot(
                goals = if (planningGoalRetired) emptyList() else listOf(planningGoal),
                requirements = if (planningGoalRetired) {
                    emptyList()
                } else {
                    listOf(
                        requirement.copy(
                            targetAmount = planningGoal.targetAmount,
                            remainingAmount = planningGoal.targetAmount
                        )
                    )
                },
                fundingEvidence = emptyList(),
                paymentDay = 1,
                flexAdjustment = 1.0,
                displayCurrency = "USD",
                issues = emptyList(),
                undoGracePeriodHours = planningUndoGracePeriodHours
            )
        }
        coEvery { planning.flexAdjustment } returns 1.0
        coEvery { goalPlans.syncPlans(month, listOf(requirement)) } returns listOf(goalPlan)
        coEvery { goalPlans.applyFlexAdjustment(month, any()) } returns listOf(goalPlan)
        coEvery { goalPlans.getPlansOnce(month) } returns listOf(goalPlan)
        var existingMonthRecord: com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord? = null
        coEvery { records.getRecordByMonthLabelOnce(month) } answers { existingMonthRecord }
        val assetsState = MutableStateFlow(
            listOf(
                Asset(
                    id = "btc-asset",
                    currency = "BTC",
                    address = "btc-address",
                    chainId = "bitcoin",
                    createdAt = now,
                    updatedAt = now
                ),
                Asset(
                    id = "eth-asset",
                    currency = "ETH",
                    address = "eth-address",
                    chainId = "ethereum",
                    createdAt = now,
                    updatedAt = now
                ),
                Asset(
                    id = "unused-at-start",
                    currency = "USDC",
                    address = "usdc-address",
                    chainId = "ethereum",
                    createdAt = now,
                    updatedAt = now
                ),
                Asset(
                    id = "history-only-asset",
                    currency = "SOL",
                    address = "sol-address",
                    chainId = "solana",
                    createdAt = now,
                    updatedAt = now
                )
            )
        )
        coEvery { assets.getAllAssets() } returns assetsState
        val transactionState = MutableStateFlow<List<Transaction>>(emptyList())
        every { transactions.getAllTransactions() } returns transactionState
        val btcAllocation = Allocation(
            id = "btc-allocation",
            assetId = "btc-asset",
            goalId = goal.id,
            amount = 1.0,
            createdAt = now,
            lastModifiedAt = now
        )
        val ethAllocation = Allocation(
            id = "eth-allocation",
            assetId = "eth-asset",
            goalId = goal.id,
            amount = 1.0,
            createdAt = now,
            lastModifiedAt = now
        )
        coEvery { allocations.getAllocationsForAsset("btc-asset") } returns
            listOf(btcAllocation)
        coEvery { allocations.getAllocationsForAsset("eth-asset") } returns
            listOf(ethAllocation)
        coEvery { allocations.getAllocationsForAsset("unused-at-start") } returns listOf(
            Allocation(
                id = "archived-goal-allocation",
                assetId = "unused-at-start",
                goalId = "archived-goal",
                amount = 1.0,
                createdAt = now,
                lastModifiedAt = now
            )
        )
        coEvery { allocations.getAllocationsForAsset("history-only-asset") } returns emptyList()
        every { allocations.getAllAllocationsFlow() } returns
            flowOf(listOf(btcAllocation, ethAllocation))
        val allocationHistoryState = MutableStateFlow(
            listOf(
                AllocationHistory(
                    id = "btc-history",
                    assetId = btcAllocation.assetId,
                    goalId = btcAllocation.goalId,
                    amount = btcAllocation.amount,
                    monthLabel = month,
                    timestamp = btcAllocation.lastModifiedAt,
                    createdAt = btcAllocation.lastModifiedAt
                ),
                AllocationHistory(
                    id = "eth-history",
                    assetId = ethAllocation.assetId,
                    goalId = ethAllocation.goalId,
                    amount = ethAllocation.amount,
                    monthLabel = month,
                    timestamp = ethAllocation.lastModifiedAt,
                    createdAt = ethAllocation.lastModifiedAt
                ),
                AllocationHistory(
                    id = "history-1",
                    assetId = "history-only-asset",
                    goalId = goal.id,
                    amount = 0.25,
                    monthLabel = "2026-06",
                    timestamp = now - 100L,
                    createdAt = now - 100L
                ),
                AllocationHistory(
                    id = "history-deallocated",
                    assetId = "history-only-asset",
                    goalId = goal.id,
                    amount = 0.0,
                    monthLabel = "2026-06",
                    timestamp = now - 50L,
                    createdAt = now - 50L
                )
            )
        )
        every { allocationHistory.getAll() } returns allocationHistoryState
        var mutateScopeDuringCapture = false
        var mutateHistoricalScopeDuringCapture = false
        var mutateUndoGracePeriodDuringCapture = false
        var mutateGoalDuringCapture = false
        var retireGoalDuringCapture = false
        var mutateOnChainRowsDuringCapture = false
        coEvery {
            rateResolver.capture(
                setOf("btc-asset", "eth-asset"),
                setOf("USD"),
                any()
            )
        } answers {
            if (mutateScopeDuringCapture) {
                assetsState.value = assetsState.value.map { asset ->
                    if (asset.id == "btc-asset") asset.copy(currency = "ETH") else asset
                }
            }
            if (mutateHistoricalScopeDuringCapture) {
                allocationHistoryState.value = allocationHistoryState.value.map { history ->
                    if (history.id == "history-1") {
                        history.copy(
                            amount = history.amount + 0.1,
                            timestamp = history.timestamp + 1
                        )
                    } else {
                        history
                    }
                }
            }
            if (mutateUndoGracePeriodDuringCapture) {
                planningUndoGracePeriodHours = 48
            }
            if (mutateGoalDuringCapture) {
                planningGoal = planningGoal.copy(
                    targetAmount = planningGoal.targetAmount + 100.0,
                    updatedAt = planningGoal.updatedAt + 1
                )
            }
            if (retireGoalDuringCapture) {
                planningGoalRetired = true
            }
            if (mutateOnChainRowsDuringCapture) {
                transactionState.value = listOf(
                    executionInputTransaction(source = TransactionSource.ON_CHAIN)
                )
            }
            capturedRates
        }

        val transactionRunner = object : ExecutionTransitionTransactionRunner {
            override suspend fun <T> run(block: suspend () -> T): T = block()
        }
        val useCase = StartExecutionUseCase(
            monthlyPlanRepository = monthlyPlans,
            executionRecordRepository = records,
            executionSnapshotRepository = snapshots,
            executionAssetRateRepository = executionRates,
            assetRepository = assets,
            transactionRepository = transactions,
            allocationRepository = allocations,
            allocationHistoryRepository = allocationHistory,
            assetRateResolver = rateResolver,
            transactionRunner = transactionRunner,
            monthlyGoalPlanService = goalPlans,
            monthlyPlanningService = planning
        )
        val unprovenProviderLedgerResult = useCase(month)

        assertThat(unprovenProviderLedgerResult.exceptionOrNull())
            .isInstanceOf(UnprovenExecutionContributionAttributionException::class.java)
        assertThat(unprovenProviderLedgerResult.exceptionOrNull())
            .hasMessageThat()
            .contains("on-chain ledger")
        coVerify(exactly = 0) { rateResolver.capture(any(), any(), any()) }
        coVerify(exactly = 0) { records.insert(any()) }
        coVerify(exactly = 0) { snapshots.replaceForRecord(any(), any()) }
        coVerify(exactly = 0) { executionRates.replaceForRecord(any(), any()) }
        coVerify(exactly = 0) { monthlyPlans.getOrCreatePlan(any()) }
        coVerify(exactly = 0) { goalPlans.syncPlans(any(), any()) }
        coVerify(exactly = 0) { goalPlans.applyFlexAdjustment(any(), any()) }

        assetsState.value = assetsState.value.map { asset ->
            if (asset.id in setOf("btc-asset", "eth-asset", "history-only-asset")) {
                // Chain-only crypto assets are valid manual ledgers. They have
                // no provider wallet identity and must remain executable.
                asset.copy(address = null)
            } else {
                asset
            }
        }
        transactionState.value = listOf(
            executionInputTransaction(source = TransactionSource.MANUAL)
        )
        val result = useCase(month)

        assertThat(result.isSuccess).isTrue()
        val record = result.getOrThrow()
        assertThat(record.canUndoUntilMillis)
            .isEqualTo(record.startedAtMillis!! + 24L * 60L * 60L * 1000L)
        coVerifyOrder {
            rateResolver.capture(
                setOf("btc-asset", "eth-asset"),
                setOf("USD"),
                any()
            )
            records.insert(record)
            snapshots.replaceForRecord(record.id, any())
            executionRates.replaceForRecord(record.id, capturedRates)
        }
        coVerify(exactly = 1) { executionRates.replaceForRecord(record.id, capturedRates) }

        val coherentHistory = allocationHistoryState.value
        allocationHistoryState.value = coherentHistory.filterNot { it.id == "btc-history" }
        val missingAllocationHistoryResult = useCase(month)

        assertThat(missingAllocationHistoryResult.exceptionOrNull())
            .isInstanceOf(UnprovenExecutionContributionAttributionException::class.java)
        coVerify(exactly = 1) { monthlyPlans.getOrCreatePlan(any()) }
        coVerify(exactly = 1) { goalPlans.syncPlans(any(), any()) }
        coVerify(exactly = 0) { goalPlans.applyFlexAdjustment(any(), any()) }
        coVerify(exactly = 1) { rateResolver.capture(any(), any(), any()) }
        coVerify(exactly = 1) { records.insert(any()) }
        coVerify(exactly = 1) { snapshots.replaceForRecord(any(), any()) }
        coVerify(exactly = 1) { executionRates.replaceForRecord(any(), any()) }
        allocationHistoryState.value = coherentHistory

        transactionState.value = listOf(
            executionInputTransaction(source = TransactionSource.ON_CHAIN)
        )
        val legacyOnChainResult = useCase(month)

        assertThat(legacyOnChainResult.exceptionOrNull())
            .isInstanceOf(UnprovenExecutionContributionAttributionException::class.java)
        coVerify(exactly = 1) {
            rateResolver.capture(any(), any(), any())
        }
        coVerify(exactly = 1) { records.insert(any()) }
        coVerify(exactly = 1) { snapshots.replaceForRecord(any(), any()) }
        coVerify(exactly = 1) { executionRates.replaceForRecord(any(), any()) }
        coVerify(exactly = 1) { monthlyPlans.getOrCreatePlan(any()) }
        coVerify(exactly = 1) { goalPlans.syncPlans(any(), any()) }
        coVerify(exactly = 0) { goalPlans.applyFlexAdjustment(any(), any()) }

        transactionState.value = listOf(
            executionInputTransaction(source = TransactionSource.MANUAL)
        )
        mutateOnChainRowsDuringCapture = true
        val providerRowRaceResult = useCase(month)

        assertThat(providerRowRaceResult.exceptionOrNull())
            .hasMessageThat()
            .contains("inputs changed")
        coVerify(exactly = 1) { records.insert(any()) }
        coVerify(exactly = 1) { snapshots.replaceForRecord(any(), any()) }
        coVerify(exactly = 1) { executionRates.replaceForRecord(any(), any()) }
        mutateOnChainRowsDuringCapture = false
        transactionState.value = listOf(
            executionInputTransaction(source = TransactionSource.MANUAL)
        )

        mutateScopeDuringCapture = true
        val changedScopeResult = useCase(month)

        assertThat(changedScopeResult.isFailure).isTrue()
        assertThat(changedScopeResult.exceptionOrNull()).hasMessageThat().contains("inputs changed")
        coVerify(exactly = 1) { records.insert(any()) }
        coVerify(exactly = 1) { executionRates.replaceForRecord(any(), any()) }

        mutateScopeDuringCapture = false
        assetsState.value = assetsState.value.map { asset ->
            if (asset.id == "btc-asset") asset.copy(currency = "BTC") else asset
        }
        mutateHistoricalScopeDuringCapture = true

        val changedHistoricalScopeResult = useCase(month)

        assertThat(changedHistoricalScopeResult.isFailure).isTrue()
        assertThat(changedHistoricalScopeResult.exceptionOrNull()).hasMessageThat().contains("inputs changed")
        coVerify(exactly = 1) { records.insert(any()) }
        coVerify(exactly = 1) { executionRates.replaceForRecord(any(), any()) }

        mutateHistoricalScopeDuringCapture = false
        allocationHistoryState.value = allocationHistoryState.value.map { history ->
            if (history.id == "history-1") {
                history.copy(amount = 0.25, timestamp = now - 100L)
            } else {
                history
            }
        }
        mutateUndoGracePeriodDuringCapture = true

        val changedUndoGracePeriodResult = useCase(month)

        assertThat(changedUndoGracePeriodResult.isFailure).isTrue()
        assertThat(changedUndoGracePeriodResult.exceptionOrNull()).hasMessageThat().contains("inputs changed")
        coVerify(exactly = 1) { records.insert(any()) }
        coVerify(exactly = 1) { executionRates.replaceForRecord(any(), any()) }

        mutateUndoGracePeriodDuringCapture = false
        planningUndoGracePeriodHours = 24
        mutateScopeDuringCapture = false
        mutateGoalDuringCapture = true

        val editedGoalResult = useCase(month)

        assertThat(editedGoalResult.isFailure).isTrue()
        assertThat(editedGoalResult.exceptionOrNull()).hasMessageThat().contains("inputs changed")
        coVerify(exactly = 1) { records.insert(any()) }
        coVerify(exactly = 1) { executionRates.replaceForRecord(any(), any()) }

        mutateGoalDuringCapture = false
        planningGoal = goal
        retireGoalDuringCapture = true

        val retiredGoalResult = useCase(month)

        assertThat(retiredGoalResult.isFailure).isTrue()
        assertThat(retiredGoalResult.exceptionOrNull()).hasMessageThat().contains("inputs changed")
        coVerify(exactly = 1) { records.insert(any()) }
        coVerify(exactly = 1) { executionRates.replaceForRecord(any(), any()) }

        retireGoalDuringCapture = false
        for (configuredHours in listOf(0, 48)) {
            planningGoalRetired = false
            planningUndoGracePeriodHours = configuredHours

            val configuredGraceResult = useCase(month)

            assertThat(configuredGraceResult.isSuccess).isTrue()
            val configuredRecord = configuredGraceResult.getOrThrow()
            assertThat(configuredRecord.canUndoUntilMillis).isEqualTo(
                configuredRecord.startedAtMillis!! +
                    configuredHours.toLong() * 60L * 60L * 1000L
            )
        }

        planningUndoGracePeriodHours = 24
        val legacyDraft = com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord(
            id = "legacy-draft-record",
            planId = plan.id,
            monthLabel = month,
            status = com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus.DRAFT,
            startedAtMillis = 0L,
            closedAtMillis = null,
            canUndoUntilMillis = 1L,
            createdAtMillis = 1L,
            updatedAtMillis = 1L
        )
        existingMonthRecord = legacyDraft
        val beforeDraftStart = System.currentTimeMillis()

        val resumedDraftResult = useCase(month)

        val afterDraftStart = System.currentTimeMillis()
        assertThat(resumedDraftResult.isSuccess).isTrue()
        val resumedDraft = resumedDraftResult.getOrThrow()
        val resumedStartedAt = checkNotNull(resumedDraft.startedAtMillis)
        assertThat(resumedDraft.id).isEqualTo(legacyDraft.id)
        assertThat(resumedStartedAt).isAtLeast(beforeDraftStart)
        assertThat(resumedStartedAt).isAtMost(afterDraftStart)
        assertThat(resumedDraft.canUndoUntilMillis).isEqualTo(
            resumedStartedAt + 24L * 60L * 60L * 1000L
        )
        coVerify(exactly = 1) {
            records.update(match { updated ->
                updated.id == legacyDraft.id &&
                    updated.startedAtMillis != legacyDraft.startedAtMillis
            })
        }
    }

    private fun executionInputTransaction(source: TransactionSource): Transaction = Transaction(
        id = "execution-input-${source.rawValue}",
        assetId = "btc-asset",
        amount = 1.0,
        dateMillis = 1_000L,
        source = source,
        externalId = if (source == TransactionSource.ON_CHAIN) "provider-row" else null,
        counterparty = null,
        comment = null,
        createdAt = 1_000L
    )

    @Test
    fun `stale start cannot replace a month closed while rates were captured`() = runTest {
        val monthlyPlans = mockk<MonthlyPlanRepository>()
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        val snapshots = mockk<ExecutionSnapshotRepository>(relaxed = true)
        val executionRates = mockk<ExecutionAssetRateRepository>(relaxed = true)
        val assets = mockk<AssetRepository>()
        val allocations = mockk<AllocationRepository>(relaxed = true)
        val allocationHistory = mockk<AllocationHistoryRepository>()
        val rateResolver = mockk<ExecutionAssetRateResolver>()
        val goalPlans = mockk<MonthlyGoalPlanService>()
        val planning = mockk<MonthlyPlanningService>()
        val month = "2026-07"
        val now = 1_000L
        val goal = testGoal()
        val plan = MonthlyPlan(
            id = "plan-1",
            monthLabel = month,
            status = MonthlyPlanStatus.DRAFT,
            flexPercentage = 1.0,
            totalRequired = 10.0,
            settings = MonthlyPlanSettings(),
            createdAtUtcMillis = now,
            lastModifiedAtUtcMillis = now
        )
        val requirement = MonthlyRequirement(
            id = "requirement-1",
            goalId = goal.id,
            goalName = goal.name,
            currency = goal.currency,
            targetAmount = goal.targetAmount,
            currentTotal = 0.0,
            remainingAmount = goal.targetAmount,
            monthsRemaining = 10,
            requiredMonthly = 10.0,
            progress = 0.0,
            deadline = goal.deadline,
            status = RequirementStatus.ON_TRACK
        )
        val goalPlan = MonthlyGoalPlan(
            id = "goal-plan-1",
            goalId = goal.id,
            monthLabel = month,
            requiredMonthly = requirement.requiredMonthly,
            remainingAmount = requirement.remainingAmount,
            monthsRemaining = requirement.monthsRemaining,
            currency = requirement.currency,
            status = requirement.status,
            state = MonthlyGoalPlanState.DRAFT,
            customAmount = null,
            isProtected = false,
            isSkipped = false,
            createdAtUtcMillis = now,
            lastModifiedAtUtcMillis = now
        )
        val closedRecord = com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord(
            id = "closed-record",
            planId = plan.id,
            monthLabel = month,
            status = com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus.CLOSED,
            startedAtMillis = now - 100L,
            closedAtMillis = now,
            canUndoUntilMillis = now + 1_000L,
            createdAtMillis = now - 100L,
            updatedAtMillis = now
        )

        coEvery { records.getCurrentExecutingRecord() } returns flowOf(null)
        coEvery { records.getRecordByMonthLabelOnce(month) } returnsMany listOf(
            null,
            null,
            closedRecord
        )
        coEvery { monthlyPlans.getOrCreatePlan(month) } returns plan
        every { monthlyPlans.getPlanFlow(month) } returns flowOf(plan)
        coEvery { planning.calculateExecutionSnapshot() } returns MonthlyPlanningSnapshot(
            goals = listOf(goal),
            requirements = listOf(requirement),
            fundingEvidence = emptyList(),
            paymentDay = 1,
            flexAdjustment = 1.0,
            displayCurrency = "USD",
            issues = emptyList()
        )
        coEvery { planning.flexAdjustment } returns 1.0
        coEvery { goalPlans.syncPlans(month, any()) } returns listOf(goalPlan)
        coEvery { goalPlans.applyFlexAdjustment(month, any()) } returns listOf(goalPlan)
        coEvery { goalPlans.getPlansOnce(month) } returns listOf(goalPlan)
        coEvery { assets.getAllAssets() } returns flowOf(emptyList())
        every { allocations.getAllAllocationsFlow() } returns flowOf(emptyList())
        every { allocationHistory.getAll() } returns flowOf(emptyList())
        coEvery { rateResolver.capture(emptySet(), setOf("USD"), any()) } returns emptyList()

        val useCase = StartExecutionUseCase(
            monthlyPlanRepository = monthlyPlans,
            executionRecordRepository = records,
            executionSnapshotRepository = snapshots,
            executionAssetRateRepository = executionRates,
            assetRepository = assets,
            transactionRepository = mockk<TransactionRepository> {
                every { getAllTransactions() } returns flowOf(emptyList())
            },
            allocationRepository = allocations,
            allocationHistoryRepository = allocationHistory,
            assetRateResolver = rateResolver,
            transactionRunner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            },
            monthlyGoalPlanService = goalPlans,
            monthlyPlanningService = planning
        )

        val result = useCase(month)

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).hasMessageThat().contains("closed")
        coVerify(exactly = 0) { records.insert(any()) }
        coVerify(exactly = 0) { records.update(any()) }
        coVerify(exactly = 0) { snapshots.replaceForRecord(any(), any()) }
        coVerify(exactly = 0) { executionRates.replaceForRecord(any(), any()) }
    }

    private fun testGoal() = Goal(
        id = "goal-1",
        name = "USD goal",
        currency = "USD",
        targetAmount = 100.0,
        deadline = LocalDate.of(2026, 12, 31),
        startDate = LocalDate.of(2026, 1, 1),
        lifecycleStatus = GoalLifecycleStatus.ACTIVE,
        lifecycleStatusChangedAt = null,
        emoji = null,
        description = null,
        link = null,
        reminderFrequency = null,
        reminderTimeMillis = null,
        firstReminderDate = null,
        createdAt = 1_000L,
        updatedAt = 1_000L
    )
    @Test
    fun `start preserves an explicit custom amount at default flex`() = runTest {
        val fixture = PreservedAmountsFixture(customAmount = 60.0, flex = 1.0)

        assertThat(fixture.useCase("2026-10").isSuccess).isTrue()

        assertThat(fixture.snapshots.single().requiredAmount).isEqualTo(60.0)
        assertThat(fixture.snapshots.single().customAmount).isEqualTo(60.0)
        assertThat(fixture.plans.single().customAmount).isEqualTo(60.0)
    }

    @Test
    fun `start does not apply saved flex amounts a second time`() = runTest {
        val fixture = PreservedAmountsFixture(customAmount = 50.0, flex = 0.5)

        assertThat(fixture.useCase("2026-10").isSuccess).isTrue()

        assertThat(fixture.snapshots.single().requiredAmount).isEqualTo(50.0)
        assertThat(fixture.plans.single().effectiveAmount).isEqualTo(50.0)
    }

    private class PreservedAmountsFixture(customAmount: Double, flex: Double) {
        var plans = listOf(
            MonthlyGoalPlan(
                id = "goal-plan", goalId = "goal", monthLabel = "2026-10",
                requiredMonthly = 100.0, remainingAmount = 1_000.0, monthsRemaining = 10,
                currency = "USD", status = RequirementStatus.ON_TRACK, state = MonthlyGoalPlanState.DRAFT,
                customAmount = customAmount, isProtected = false, isSkipped = false,
                createdAtUtcMillis = 1L, lastModifiedAtUtcMillis = 1L
            )
        )
        var snapshots = emptyList<ExecutionSnapshot>()
        val useCase: StartExecutionUseCase

        init {
            val goal = Goal(
                id = "goal", name = "Savings", currency = "USD", targetAmount = 1_000.0,
                deadline = LocalDate.of(2027, 8, 1), startDate = LocalDate.of(2026, 10, 1),
                lifecycleStatus = GoalLifecycleStatus.ACTIVE, lifecycleStatusChangedAt = null,
                emoji = null, description = null, link = null, reminderFrequency = null,
                reminderTimeMillis = null, firstReminderDate = null, createdAt = 1L, updatedAt = 1L
            )
            val requirement = MonthlyRequirement(
                id = "requirement", goalId = goal.id, goalName = goal.name, currency = "USD",
                targetAmount = 1_000.0, currentTotal = 0.0, remainingAmount = 1_000.0,
                monthsRemaining = 10, requiredMonthly = 100.0, progress = 0.0,
                deadline = goal.deadline, status = RequirementStatus.ON_TRACK
            )
            val planRepository = mockk<MonthlyGoalPlanRepository>()
            coEvery { planRepository.getPlansOnce("2026-10") } answers { plans }
            coEvery { planRepository.upsertAll(any()) } answers { plans = firstArg() }
            val monthlyPlanRepository = mockk<MonthlyPlanRepository>()
            val monthlyPlan = MonthlyPlan(
                "monthly-plan", "2026-10", MonthlyPlanStatus.DRAFT, flex, 100.0,
                MonthlyPlanSettings(), 1L, 1L
            )
            val recordRepository = mockk<ExecutionRecordRepository>(relaxed = true)
            every { recordRepository.getCurrentExecutingRecord() } returns flowOf(null)
            coEvery { recordRepository.getRecordByMonthLabelOnce("2026-10") } returns null
            val snapshotRepository = mockk<ExecutionSnapshotRepository>()
            coEvery { snapshotRepository.replaceForRecord(any(), any()) } answers { snapshots = secondArg() }
            val planning = mockk<MonthlyPlanningService>()
            coEvery { planning.calculateExecutionSnapshot() } returns MonthlyPlanningSnapshot(
                listOf(goal), listOf(requirement), emptyList(), 1, flex, "USD", emptyList()
            )
            every { planning.flexAdjustment } returns flex
            val runner = object : ExecutionTransitionTransactionRunner {
                override suspend fun <T> run(block: suspend () -> T): T = block()
            }
            coEvery { monthlyPlanRepository.getOrCreatePlan("2026-10") } returns monthlyPlan
            every { monthlyPlanRepository.getPlanFlow("2026-10") } returns flowOf(monthlyPlan)
            val allocations = mockk<AllocationRepository>() {
                every { getAllAllocationsFlow() } returns flowOf(emptyList())
            }
            val history = mockk<AllocationHistoryRepository>() {
                every { getAll() } returns flowOf(emptyList())
            }
            val assets = mockk<AssetRepository>() {
                every { getAllAssets() } returns flowOf(emptyList())
            }
            val transactions = mockk<TransactionRepository>() {
                every { getAllTransactions() } returns flowOf(emptyList())
            }
            val rateResolver = mockk<ExecutionAssetRateResolver>() {
                coEvery { capture(emptySet(), setOf("USD"), any()) } returns emptyList()
            }
            useCase = StartExecutionUseCase(
                monthlyPlanRepository, recordRepository, snapshotRepository,
                mockk<ExecutionAssetRateRepository>(relaxed = true), assets, transactions,
                allocations, history, rateResolver, runner,
                MonthlyGoalPlanService(planRepository, FlexAdjustmentService()), planning
            )
        }
    }
}
