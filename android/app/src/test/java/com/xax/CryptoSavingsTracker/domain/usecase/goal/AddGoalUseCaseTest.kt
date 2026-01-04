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
            name = "   ",
            currency = "USD",
            targetAmount = 100.0,
            deadline = LocalDate.now().plusDays(1)
        )
        assertThat(result.isFailure).isTrue()
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

private class FakeGoalReminderScheduler : GoalReminderScheduler {
    val scheduledGoals = mutableListOf<Goal>()
    val canceledGoalIds = mutableListOf<String>()

    override fun schedule(goal: Goal) {
        scheduledGoals += goal
    }

    override fun cancel(goalId: String) {
        canceledGoalIds += goalId
    }
}
