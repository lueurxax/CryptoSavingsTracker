package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.ReminderFrequency
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationHistoryService
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import java.time.LocalDate

class UpdateGoalUseCaseTest {
    @Test
    fun `updating rejects non-finite target amount before persistence`() = runTest {
        listOf(
            Double.NaN,
            Double.POSITIVE_INFINITY,
            Double.NEGATIVE_INFINITY
        ).forEach { invalidAmount ->
            val original = goal()
            val repository = LifecycleGoalRepository(original)
            val useCase = UpdateGoalUseCase(
                repository = repository,
                reminderScheduler = RecordingReminderScheduler(),
                allocationRepository = mockk(relaxed = true),
                allocationHistoryService = mockk(relaxed = true),
                executionRecordRepository = mockk(relaxed = true),
                executionSnapshotRepository = mockk(relaxed = true),
                executionAssetRateRepository = mockk(relaxed = true),
                transactionRunner = DirectLifecycleTransactionRunner
            )

            val result = useCase(original.copy(targetAmount = invalidAmount))

            assertThat(result.isFailure).isTrue()
            assertThat(result.exceptionOrNull()).hasMessageThat().contains("finite")
            assertThat(repository.getGoalById(GOAL_ID)?.targetAmount)
                .isEqualTo(original.targetAmount)
        }
    }

    @Test
    fun `cancelling a goal retires its persisted reminder state`() = runTest {
        val repository = LifecycleGoalRepository(goal())
        val scheduler = RecordingReminderScheduler()
        val allocations = mockk<AllocationRepository>(relaxed = true)
        coEvery { allocations.getAllocationsForGoal(GOAL_ID) } returns emptyList()
        val records = mockk<ExecutionRecordRepository>(relaxed = true)
        every { records.getCurrentExecutingRecord() } returns flowOf(null)
        val useCase = UpdateGoalUseCase(
            repository = repository,
            reminderScheduler = scheduler,
            allocationRepository = allocations,
            allocationHistoryService = mockk<AllocationHistoryService>(relaxed = true),
            executionRecordRepository = records,
            executionSnapshotRepository = mockk<ExecutionSnapshotRepository>(relaxed = true),
            executionAssetRateRepository = mockk<ExecutionAssetRateRepository>(relaxed = true),
            transactionRunner = DirectLifecycleTransactionRunner
        )

        val result = useCase.updateStatus(GOAL_ID, GoalLifecycleStatus.CANCELLED)

        assertThat(result.isSuccess).isTrue()
        val durableGoal = checkNotNull(repository.getGoalById(GOAL_ID))
        assertThat(durableGoal.lifecycleStatus).isEqualTo(GoalLifecycleStatus.CANCELLED)
        assertThat(durableGoal.reminderFrequency).isNull()
        assertThat(durableGoal.reminderTimeMillis).isNull()
        assertThat(durableGoal.firstReminderDate).isNull()
        assertThat(scheduler.cancelledGoalIds).containsExactly(GOAL_ID)
    }

    private fun goal() = Goal(
        id = GOAL_ID,
        name = "Lifecycle goal",
        currency = "USD",
        targetAmount = 100.0,
        deadline = LocalDate.of(2027, 1, 1),
        startDate = LocalDate.of(2026, 1, 1),
        lifecycleStatus = GoalLifecycleStatus.ACTIVE,
        lifecycleStatusChangedAt = null,
        emoji = null,
        description = null,
        link = null,
        reminderFrequency = ReminderFrequency.WEEKLY,
        reminderTimeMillis = 1_000L,
        firstReminderDate = LocalDate.of(2026, 7, 27),
        createdAt = 1L,
        updatedAt = 1L
    )

    private companion object {
        const val GOAL_ID = "goal-1"
    }
}

private object DirectLifecycleTransactionRunner : ExecutionTransitionTransactionRunner {
    override suspend fun <T> run(block: suspend () -> T): T = block()
}

private class LifecycleGoalRepository(initialGoal: Goal) : GoalRepository {
    private val goals = MutableStateFlow(mapOf(initialGoal.id to initialGoal))

    override fun getAllGoals(): Flow<List<Goal>> = goals.map { it.values.toList() }

    override fun getGoalsByStatus(status: GoalLifecycleStatus): Flow<List<Goal>> =
        goals.map { values -> values.values.filter { it.lifecycleStatus == status } }

    override fun getActiveGoals(): Flow<List<Goal>> =
        getGoalsByStatus(GoalLifecycleStatus.ACTIVE)

    override suspend fun getGoalById(id: String): Goal? = goals.value[id]

    override fun getGoalByIdFlow(id: String): Flow<Goal?> = goals.map { it[id] }

    override suspend fun insertGoal(goal: Goal) {
        goals.value += goal.id to goal
    }

    override suspend fun updateGoal(goal: Goal) {
        goals.value += goal.id to goal
    }

    override suspend fun deleteGoal(id: String) {
        goals.value -= id
    }

    override suspend fun deleteGoal(goal: Goal) {
        deleteGoal(goal.id)
    }

    override suspend fun updateGoalStatus(id: String, status: GoalLifecycleStatus) {
        val goal = goals.value[id] ?: return
        goals.value += id to goal.copy(lifecycleStatus = status)
    }

    override fun getActiveGoalCount(): Flow<Int> =
        goals.map { values -> values.values.count { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE } }
}

private class RecordingReminderScheduler : GoalReminderScheduler {
    val cancelledGoalIds = mutableListOf<String>()

    override fun schedule(goal: Goal) = Unit

    override fun cancel(goalId: String) {
        cancelledGoalIds += goalId
    }
}
