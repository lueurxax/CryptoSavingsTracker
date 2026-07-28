package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.ReminderFrequency
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.runTest
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import org.junit.jupiter.api.Test

class AddGoalUseCaseTest {
    @Test
    fun addsGoal_andDefaultsReminderTimeTo0900_whenFrequencyProvided() = runTest {
        val repo = FakeGoalRepository()
        val scheduler = FakeGoalReminderScheduler()
        val useCase = AddGoalUseCase(repository = repo, reminderScheduler = scheduler)

        val deadline = LocalDate.now().plusDays(30)
        val result = useCase(
            goalId = "goal-session-1",
            name = "My Goal",
            currency = "USD",
            targetAmount = 100.0,
            deadline = deadline,
            reminderFrequency = ReminderFrequency.WEEKLY,
            reminderTimeMillis = null,
            firstReminderDate = null
        )

        assertThat(result.isSuccess).isTrue()
        val goal = result.getOrThrow()
        assertThat(repo.insertedGoals).hasSize(1)
        assertThat(scheduler.scheduledGoals).hasSize(1)
        assertThat(goal.reminderTimeMillis).isNotNull()
        assertThat(goal.reminderFrequency).isEqualTo(ReminderFrequency.WEEKLY)

        val time = Instant.ofEpochMilli(goal.reminderTimeMillis!!).atZone(ZoneId.systemDefault()).toLocalTime()
        assertThat(time.hour).isEqualTo(LocalTime.of(9, 0).hour)
        assertThat(time.minute).isEqualTo(LocalTime.of(9, 0).minute)
    }

    @Test
    fun rejectsEmptyName() = runTest {
        val useCase = AddGoalUseCase(repository = FakeGoalRepository(), reminderScheduler = FakeGoalReminderScheduler())
        val result = useCase(
            goalId = "invalid-name-session",
            name = "   ",
            currency = "USD",
            targetAmount = 100.0,
            deadline = LocalDate.now().plusDays(1)
        )
        assertThat(result.isFailure).isTrue()
    }

    @Test
    fun `rejects non-finite target amount before persistence`() = runTest {
        listOf(
            Double.NaN,
            Double.POSITIVE_INFINITY,
            Double.NEGATIVE_INFINITY
        ).forEachIndexed { index, invalidAmount ->
            val repository = FakeGoalRepository()
            val useCase = AddGoalUseCase(
                repository = repository,
                reminderScheduler = FakeGoalReminderScheduler()
            )

            val result = useCase(
                goalId = "invalid-amount-$index",
                name = "Invalid amount",
                currency = "USD",
                targetAmount = invalidAmount,
                deadline = LocalDate.now().plusDays(1)
            )

            assertThat(result.isFailure).isTrue()
            assertThat(result.exceptionOrNull()).hasMessageThat().contains("finite")
            assertThat(repository.insertedGoals).isEmpty()
        }
    }

    @Test
    fun `retry after scheduler failure reuses session id and schedules persisted goal`() = runTest {
        val repo = FakeGoalRepository()
        val scheduler = FakeGoalReminderScheduler(failuresRemaining = 1)
        val useCase = AddGoalUseCase(repository = repo, reminderScheduler = scheduler)
        val deadline = LocalDate.now().plusDays(30)

        val first = useCase(
            goalId = "stable-create-session",
            name = "Retry Goal",
            currency = "USD",
            targetAmount = 100.0,
            deadline = deadline,
            reminderFrequency = ReminderFrequency.WEEKLY
        )
        val lifecycleChangedAt = 1_700_000_000_000L
        repo.updateGoal(
            checkNotNull(repo.getGoalById("stable-create-session")).copy(
                lifecycleStatus = GoalLifecycleStatus.FINISHED,
                lifecycleStatusChangedAt = lifecycleChangedAt
            )
        )
        val retry = useCase(
            goalId = "stable-create-session",
            name = "Edited Retry Goal",
            currency = "USD",
            targetAmount = 250.0,
            deadline = deadline,
            reminderFrequency = ReminderFrequency.WEEKLY
        )

        assertThat(first.isFailure).isTrue()
        assertThat(retry.isSuccess).isTrue()
        assertThat(retry.getOrThrow().id).isEqualTo("stable-create-session")
        assertThat(retry.getOrThrow().name).isEqualTo("Edited Retry Goal")
        assertThat(retry.getOrThrow().targetAmount).isEqualTo(250.0)
        assertThat(retry.getOrThrow().lifecycleStatus).isEqualTo(GoalLifecycleStatus.FINISHED)
        assertThat(retry.getOrThrow().lifecycleStatusChangedAt).isEqualTo(lifecycleChangedAt)
        assertThat(repo.getGoalById("stable-create-session")?.targetAmount).isEqualTo(250.0)
        assertThat(repo.insertedGoals).hasSize(1)
        assertThat(scheduler.scheduleAttempts.map { it.id })
            .containsExactly("stable-create-session", "stable-create-session")
        assertThat(scheduler.scheduleAttempts.last().targetAmount).isEqualTo(250.0)
    }
}

private class FakeGoalRepository : GoalRepository {
    val insertedGoals = mutableListOf<Goal>()
    private val goals = MutableStateFlow<Map<String, Goal>>(emptyMap())

    override fun getAllGoals(): Flow<List<Goal>> = goals.map { it.values.toList() }

    override fun getGoalsByStatus(status: GoalLifecycleStatus): Flow<List<Goal>> =
        goals.map { it.values.filter { goal -> goal.lifecycleStatus == status } }

    override fun getActiveGoals(): Flow<List<Goal>> =
        goals.map { it.values.filter { goal -> goal.lifecycleStatus == GoalLifecycleStatus.ACTIVE } }

    override suspend fun getGoalById(id: String): Goal? = goals.value[id]
    override fun getGoalByIdFlow(id: String): Flow<Goal?> = goals.map { it[id] }

    override suspend fun insertGoal(goal: Goal) {
        insertedGoals += goal
        goals.value = goals.value + (goal.id to goal)
    }

    override suspend fun updateGoal(goal: Goal) {
        goals.value = goals.value + (goal.id to goal)
    }

    override suspend fun deleteGoal(id: String) {
        goals.value = goals.value - id
    }

    override suspend fun deleteGoal(goal: Goal) {
        deleteGoal(goal.id)
    }

    override suspend fun updateGoalStatus(id: String, status: GoalLifecycleStatus) {
        val goal = goals.value[id] ?: return
        goals.value = goals.value + (id to goal.copy(lifecycleStatus = status))
    }

    override fun getActiveGoalCount(): Flow<Int> = goals.map { it.values.count { g -> g.lifecycleStatus == GoalLifecycleStatus.ACTIVE } }
}

private class FakeGoalReminderScheduler(
    var failuresRemaining: Int = 0
) : GoalReminderScheduler {
    val scheduledGoals = mutableListOf<Goal>()
    val scheduleAttempts = mutableListOf<Goal>()
    val canceledGoalIds = mutableListOf<String>()

    override fun schedule(goal: Goal) {
        scheduleAttempts += goal
        if (failuresRemaining > 0) {
            failuresRemaining -= 1
            throw IllegalStateException("scheduler unavailable")
        }
        scheduledGoals += goal
    }

    override fun cancel(goalId: String) {
        canceledGoalIds += goalId
    }
}
