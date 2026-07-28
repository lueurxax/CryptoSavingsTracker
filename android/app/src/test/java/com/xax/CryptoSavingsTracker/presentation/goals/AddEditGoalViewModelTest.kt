package com.xax.CryptoSavingsTracker.presentation.goals

import androidx.lifecycle.SavedStateHandle
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionAssetRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationHistoryService
import com.xax.CryptoSavingsTracker.domain.usecase.goal.AddGoalUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.UpdateGoalUseCase
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AddEditGoalViewModelTest {
    @Test
    fun `oversized target amount stays in the form and is not persisted`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val repository = ViewModelGoalRepository()
            val scheduler = FailingOnceReminderScheduler()
            val viewModel = AddEditGoalViewModel(
                savedStateHandle = SavedStateHandle(),
                addGoalUseCase = AddGoalUseCase(repository, scheduler),
                updateGoalUseCase = UpdateGoalUseCase(
                    repository = repository,
                    reminderScheduler = scheduler,
                    allocationRepository = mockk<AllocationRepository>(relaxed = true),
                    allocationHistoryService = mockk<AllocationHistoryService>(relaxed = true),
                    executionRecordRepository = mockk<ExecutionRecordRepository>(relaxed = true),
                    executionSnapshotRepository = mockk<ExecutionSnapshotRepository>(relaxed = true),
                    executionAssetRateRepository = mockk<ExecutionAssetRateRepository>(relaxed = true),
                    transactionRunner = DirectViewModelTransactionRunner
                ),
                getGoalByIdUseCase = GetGoalByIdUseCase(repository)
            )

            viewModel.updateName("Overflow")
            viewModel.updateTargetAmount("9".repeat(400))
            viewModel.saveGoal()
            advanceUntilIdle()

            assertThat(viewModel.uiState.value.targetAmountError).isNotNull()
            assertThat(viewModel.uiState.value.isSaved).isFalse()
            assertThat(repository.insertedGoals).isEmpty()
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `create retry reuses SavedState session id and does not insert a second goal`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val repository = ViewModelGoalRepository()
            val scheduler = FailingOnceReminderScheduler()
            val savedStateHandle = SavedStateHandle()
            val viewModel = AddEditGoalViewModel(
                savedStateHandle = savedStateHandle,
                addGoalUseCase = AddGoalUseCase(repository, scheduler),
                updateGoalUseCase = UpdateGoalUseCase(
                    repository = repository,
                    reminderScheduler = scheduler,
                    allocationRepository = mockk<AllocationRepository>(relaxed = true),
                    allocationHistoryService = mockk<AllocationHistoryService>(relaxed = true),
                    executionRecordRepository = mockk<ExecutionRecordRepository>(relaxed = true),
                    executionSnapshotRepository = mockk<ExecutionSnapshotRepository>(relaxed = true),
                    executionAssetRateRepository = mockk<ExecutionAssetRateRepository>(relaxed = true),
                    transactionRunner = DirectViewModelTransactionRunner
                ),
                getGoalByIdUseCase = GetGoalByIdUseCase(repository)
            )

            viewModel.updateName("Stable retry")
            viewModel.updateTargetAmount("100")
            viewModel.saveGoal()
            advanceUntilIdle()

            assertThat(viewModel.uiState.value.isSaved).isFalse()
            assertThat(viewModel.uiState.value.error).isEqualTo("scheduler unavailable")
            assertThat(repository.insertedGoals).hasSize(1)
            val persistedId = repository.insertedGoals.single().id
            assertThat(savedStateHandle.get<String>("createSessionGoalId")).isEqualTo(persistedId)

            viewModel.clearError()
            viewModel.updateTargetAmount("250")
            viewModel.saveGoal()
            advanceUntilIdle()

            assertThat(viewModel.uiState.value.isSaved).isTrue()
            assertThat(repository.insertedGoals).hasSize(1)
            assertThat(repository.getGoalById(persistedId)?.targetAmount).isEqualTo(250.0)
            assertThat(scheduler.attemptedGoals.last().targetAmount).isEqualTo(250.0)
            assertThat(scheduler.attemptedGoalIds)
                .containsExactly(persistedId, persistedId)
                .inOrder()
        } finally {
            Dispatchers.resetMain()
        }
    }
}

private object DirectViewModelTransactionRunner : ExecutionTransitionTransactionRunner {
    override suspend fun <T> run(block: suspend () -> T): T = block()
}

private class ViewModelGoalRepository : GoalRepository {
    val insertedGoals = mutableListOf<Goal>()
    private val goals = MutableStateFlow<Map<String, Goal>>(emptyMap())

    override fun getAllGoals(): Flow<List<Goal>> = goals.map { it.values.toList() }

    override fun getGoalsByStatus(status: GoalLifecycleStatus): Flow<List<Goal>> =
        goals.map { values -> values.values.filter { it.lifecycleStatus == status } }

    override fun getActiveGoals(): Flow<List<Goal>> =
        getGoalsByStatus(GoalLifecycleStatus.ACTIVE)

    override suspend fun getGoalById(id: String): Goal? = goals.value[id]

    override fun getGoalByIdFlow(id: String): Flow<Goal?> = goals.map { it[id] }

    override suspend fun insertGoal(goal: Goal) {
        insertedGoals += goal
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
        goals.map { values ->
            values.values.count { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
        }
}

private class FailingOnceReminderScheduler : GoalReminderScheduler {
    val attemptedGoals = mutableListOf<Goal>()
    val attemptedGoalIds = mutableListOf<String>()
    private var shouldFail = true

    override fun schedule(goal: Goal) {
        attemptedGoals += goal
        attemptedGoalIds += goal.id
        if (shouldFail) {
            shouldFail = false
            throw IllegalStateException("scheduler unavailable")
        }
    }

    override fun cancel(goalId: String) = Unit
}
