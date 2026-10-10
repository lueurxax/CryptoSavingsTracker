package com.xax.CryptoSavingsTracker.domain.usecase.goal

import androidx.room.Room
import androidx.room.withTransaction
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.data.local.database.entity.AllocationHistoryEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetAllocationEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.ExecutionAssetRateEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.ExecutionSnapshotEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.GoalEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.MonthlyExecutionRecordEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.MonthlyPlanEntity
import com.xax.CryptoSavingsTracker.data.repository.AllocationHistoryRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.AllocationRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.ExecutionAssetRateRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.ExecutionRecordRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.ExecutionSnapshotRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.ExecutionTransitionTransactionRunnerImpl
import com.xax.CryptoSavingsTracker.data.repository.GoalRepositoryImpl
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationHistoryService
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class UpdateGoalRoomTransactionTest {
    private lateinit var database: AppDatabase
    private lateinit var scheduler: RecordingGoalReminderScheduler

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        database = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        scheduler = RecordingGoalReminderScheduler()
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun cancelClearsReminderFreesOnlyTargetAllocationAndRemovesOnlyTargetFromExecution() = runBlocking {
        seedExecution(includeOtherGoal = true)

        val result = useCase(realTransactionRunner())
            .updateStatus(TARGET_GOAL_ID, GoalLifecycleStatus.CANCELLED)

        assertTrue(result.exceptionOrNull()?.stackTraceToString(), result.isSuccess)
        assertRetiredGoal(TARGET_GOAL_ID, "cancelled")
        assertTrue(database.allocationDao().getAllocationsByGoalId(TARGET_GOAL_ID).first().isEmpty())
        assertEquals(
            listOf(OTHER_ALLOCATION_ID),
            database.allocationDao().getAllocationsByAssetId(ASSET_ID).first().map { it.id }
        )
        val targetHistory = database.allocationHistoryDao().getByGoalId(TARGET_GOAL_ID).first()
        assertEquals(1, targetHistory.count { it.amount == 0.0 })
        assertEquals(
            listOf(OTHER_GOAL_ID),
            database.executionSnapshotDao().getSnapshotsByRecordId(RECORD_ID).first().map { it.goalId }
        )
        assertEquals("executing", database.executionRecordDao().getRecordById(RECORD_ID)?.status)
        assertEquals(1, database.executionAssetRateDao().getByRecordId(RECORD_ID).first().size)
        assertEquals(listOf(TARGET_GOAL_ID), scheduler.cancelledGoalIds)
    }

    @Test
    fun finishClearsReminderAndRemovesExecutionSnapshotButKeepsAllocations() = runBlocking {
        seedExecution(includeOtherGoal = true)

        val result = useCase(realTransactionRunner())
            .updateStatus(TARGET_GOAL_ID, GoalLifecycleStatus.FINISHED)

        assertTrue(result.exceptionOrNull()?.stackTraceToString(), result.isSuccess)
        assertRetiredGoal(TARGET_GOAL_ID, "finished")
        assertEquals(
            listOf(TARGET_ALLOCATION_ID),
            database.allocationDao().getAllocationsByGoalId(TARGET_GOAL_ID).first().map { it.id }
        )
        val targetHistory = database.allocationHistoryDao().getByGoalId(TARGET_GOAL_ID).first()
        assertFalse(targetHistory.any { it.amount == 0.0 })
        assertEquals(
            listOf(OTHER_GOAL_ID),
            database.executionSnapshotDao().getSnapshotsByRecordId(RECORD_ID).first().map { it.goalId }
        )
        assertEquals("executing", database.executionRecordDao().getRecordById(RECORD_ID)?.status)
        assertEquals(listOf(TARGET_GOAL_ID), scheduler.cancelledGoalIds)
    }

    @Test
    fun retiringSoleExecutingGoalRevertsRecordAndClearsExecutionSession() = runBlocking {
        seedExecution(includeOtherGoal = false)

        val result = useCase(realTransactionRunner())
            .updateStatus(TARGET_GOAL_ID, GoalLifecycleStatus.CANCELLED)

        assertTrue(result.exceptionOrNull()?.stackTraceToString(), result.isSuccess)
        val record = requireNotNull(database.executionRecordDao().getRecordById(RECORD_ID))
        assertEquals("draft", record.status)
        assertNull(record.startedAtUtcMillis)
        assertNull(record.canUndoUntilUtcMillis)
        assertTrue(database.executionSnapshotDao().getSnapshotsByRecordId(RECORD_ID).first().isEmpty())
        assertTrue(database.executionAssetRateDao().getByRecordId(RECORD_ID).first().isEmpty())
        assertNull(database.executionRecordDao().getCurrentExecutingRecord().first())
    }

    @Test
    fun failedLifecycleTransactionRollsBackEverythingAndOneRetryCommitsExactlyOnce() = runBlocking {
        seedExecution(includeOtherGoal = false)
        val runner = FailOnceAfterBlockTransactionRunner(database)
        val useCase = useCase(runner)

        val failure = useCase.updateStatus(TARGET_GOAL_ID, GoalLifecycleStatus.CANCELLED)

        assertTrue(failure.isFailure)
        assertEquals("simulated lifecycle failure", failure.exceptionOrNull()?.message)
        val durableGoalAfterFailure = requireNotNull(database.goalDao().getGoalByIdOnce(TARGET_GOAL_ID))
        assertEquals("active", durableGoalAfterFailure.lifecycleStatus)
        assertEquals("weekly", durableGoalAfterFailure.reminderFrequency)
        assertEquals(1, database.allocationDao().getAllocationsByGoalId(TARGET_GOAL_ID).first().size)
        assertFalse(
            database.allocationHistoryDao().getByGoalId(TARGET_GOAL_ID).first().any { it.amount == 0.0 }
        )
        assertEquals(1, database.executionSnapshotDao().getSnapshotsByRecordId(RECORD_ID).first().size)
        assertEquals("executing", database.executionRecordDao().getRecordById(RECORD_ID)?.status)
        assertEquals(1, database.executionAssetRateDao().getByRecordId(RECORD_ID).first().size)
        assertTrue(scheduler.cancelledGoalIds.isEmpty())

        val retry = useCase.updateStatus(TARGET_GOAL_ID, GoalLifecycleStatus.CANCELLED)

        assertTrue(retry.exceptionOrNull()?.stackTraceToString(), retry.isSuccess)
        assertEquals(2, runner.attempts)
        assertEquals(
            1,
            database.allocationHistoryDao().getByGoalId(TARGET_GOAL_ID).first().count { it.amount == 0.0 }
        )
        assertTrue(database.allocationDao().getAllocationsByGoalId(TARGET_GOAL_ID).first().isEmpty())
        assertTrue(database.executionSnapshotDao().getSnapshotsByRecordId(RECORD_ID).first().isEmpty())
        assertEquals("draft", database.executionRecordDao().getRecordById(RECORD_ID)?.status)
        assertEquals(listOf(TARGET_GOAL_ID), scheduler.cancelledGoalIds)
    }

    private fun useCase(
        runner: ExecutionTransitionTransactionRunner
    ): UpdateGoalUseCase {
        val allocationHistoryRepository =
            AllocationHistoryRepositoryImpl(database.allocationHistoryDao())
        return UpdateGoalUseCase(
            repository = GoalRepositoryImpl(database.goalDao()),
            reminderScheduler = scheduler,
            allocationRepository = AllocationRepositoryImpl(database.allocationDao()),
            allocationHistoryService = AllocationHistoryService(allocationHistoryRepository),
            executionRecordRepository = ExecutionRecordRepositoryImpl(database.executionRecordDao()),
            executionSnapshotRepository = ExecutionSnapshotRepositoryImpl(database.executionSnapshotDao()),
            executionAssetRateRepository = ExecutionAssetRateRepositoryImpl(database.executionAssetRateDao()),
            transactionRunner = runner
        )
    }

    private fun realTransactionRunner() =
        ExecutionTransitionTransactionRunnerImpl(database)

    private suspend fun seedExecution(includeOtherGoal: Boolean) {
        database.assetDao().insert(
            AssetEntity(
                id = ASSET_ID,
                currency = "USD",
                createdAtUtcMillis = 1L,
                lastModifiedAtUtcMillis = 1L
            )
        )
        database.goalDao().insert(goal(TARGET_GOAL_ID, "Target"))
        if (includeOtherGoal) {
            database.goalDao().insert(goal(OTHER_GOAL_ID, "Other"))
        }
        database.allocationDao().insert(
            allocation(TARGET_ALLOCATION_ID, TARGET_GOAL_ID, 40.0)
        )
        if (includeOtherGoal) {
            database.allocationDao().insert(
                allocation(OTHER_ALLOCATION_ID, OTHER_GOAL_ID, 30.0)
            )
        }
        database.allocationHistoryDao().insert(
            history("target-opening-history", TARGET_GOAL_ID, 40.0)
        )
        if (includeOtherGoal) {
            database.allocationHistoryDao().insert(
                history("other-opening-history", OTHER_GOAL_ID, 30.0)
            )
        }
        database.monthlyPlanDao().insert(
            MonthlyPlanEntity(
                id = PLAN_ID,
                monthLabel = "2026-07",
                status = "executing",
                createdAtUtcMillis = 1L,
                lastModifiedAtUtcMillis = 1L
            )
        )
        database.executionRecordDao().insert(
            MonthlyExecutionRecordEntity(
                id = RECORD_ID,
                planId = PLAN_ID,
                monthLabel = "2026-07",
                status = "executing",
                startedAtUtcMillis = 2L,
                canUndoUntilUtcMillis = Long.MAX_VALUE,
                createdAtUtcMillis = 1L,
                lastModifiedAtUtcMillis = 2L
            )
        )
        database.executionSnapshotDao().insert(snapshot("target-snapshot", TARGET_GOAL_ID))
        if (includeOtherGoal) {
            database.executionSnapshotDao().insert(snapshot("other-snapshot", OTHER_GOAL_ID))
        }
        database.executionAssetRateDao().insertAll(
            listOf(
                ExecutionAssetRateEntity(
                    executionRecordId = RECORD_ID,
                    assetId = ASSET_ID,
                    snapshotCurrency = "USD",
                    rate = 1.0,
                    capturedAtUtcMillis = 2L
                )
            )
        )
    }

    private suspend fun assertRetiredGoal(goalId: String, expectedStatus: String) {
        val goal = requireNotNull(database.goalDao().getGoalByIdOnce(goalId))
        assertEquals(expectedStatus, goal.lifecycleStatus)
        assertNull(goal.reminderFrequency)
        assertNull(goal.reminderTimeUtcMillis)
        assertNull(goal.firstReminderEpochDay)
    }

    private fun goal(id: String, name: String) = GoalEntity(
        id = id,
        name = name,
        currency = "USD",
        targetAmount = 100.0,
        deadlineEpochDay = 30_000,
        startDateEpochDay = 20_000,
        lifecycleStatus = "active",
        reminderFrequency = "weekly",
        reminderTimeUtcMillis = 1_000L,
        firstReminderEpochDay = 20_001,
        createdAtUtcMillis = 1L,
        lastModifiedAtUtcMillis = 1L
    )

    private fun allocation(id: String, goalId: String, amount: Double) =
        AssetAllocationEntity(
            id = id,
            assetId = ASSET_ID,
            goalId = goalId,
            amount = amount,
            createdAtUtcMillis = 1L,
            lastModifiedAtUtcMillis = 1L
        )

    private fun history(id: String, goalId: String, amount: Double) =
        AllocationHistoryEntity(
            id = id,
            assetId = ASSET_ID,
            goalId = goalId,
            amount = amount,
            monthLabel = "2026-07",
            timestampUtcMillis = 1L,
            createdAtUtcMillis = 1L
        )

    private fun snapshot(id: String, goalId: String) =
        ExecutionSnapshotEntity(
            id = id,
            executionRecordId = RECORD_ID,
            goalId = goalId,
            goalName = goalId,
            currency = "USD",
            targetAmount = 100.0,
            currentTotalAtStart = 40.0,
            requiredAmount = 10.0,
            createdAtUtcMillis = 2L
        )

    private companion object {
        const val ASSET_ID = "shared-asset"
        const val TARGET_GOAL_ID = "target-goal"
        const val OTHER_GOAL_ID = "other-goal"
        const val TARGET_ALLOCATION_ID = "target-allocation"
        const val OTHER_ALLOCATION_ID = "other-allocation"
        const val PLAN_ID = "plan-1"
        const val RECORD_ID = "record-1"
    }
}

private class RecordingGoalReminderScheduler : GoalReminderScheduler {
    val cancelledGoalIds = mutableListOf<String>()

    override fun schedule(goal: Goal) = Unit

    override fun cancel(goalId: String) {
        cancelledGoalIds += goalId
    }
}

private class FailOnceAfterBlockTransactionRunner(
    private val database: AppDatabase
) : ExecutionTransitionTransactionRunner {
    var attempts = 0
        private set

    override suspend fun <T> run(block: suspend () -> T): T =
        database.withTransaction {
            attempts += 1
            val result = block()
            if (attempts == 1) {
                throw IllegalStateException("simulated lifecycle failure")
            }
            result
        }
}
