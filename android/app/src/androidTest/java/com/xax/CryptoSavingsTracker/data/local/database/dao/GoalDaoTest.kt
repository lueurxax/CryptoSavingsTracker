package com.xax.CryptoSavingsTracker.data.local.database.dao

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.data.local.database.entity.GoalEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.time.LocalDate

/**
 * Comprehensive tests for GoalDao.
 * Tests all CRUD operations and queries with 100% coverage.
 */
@RunWith(AndroidJUnit4::class)
class GoalDaoTest {

    private lateinit var database: AppDatabase
    private lateinit var goalDao: GoalDao

    @Before
    fun createDb() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(
            context,
            AppDatabase::class.java
        ).allowMainThreadQueries().build()
        goalDao = database.goalDao()
    }

    @After
    fun closeDb() {
        database.close()
    }

    // ========== Test Data Helpers ==========

    private fun createGoalEntity(
        id: String = "goal-1",
        name: String = "Test Goal",
        currency: String = "USD",
        targetAmount: Double = 1000.0,
        deadlineEpochDay: Int = LocalDate.now().plusMonths(6).toEpochDay().toInt(),
        startDateEpochDay: Int = LocalDate.now().toEpochDay().toInt(),
        lifecycleStatus: String = "active",
        emoji: String? = null,
        description: String? = null
    ) = GoalEntity(
        id = id,
        name = name,
        currency = currency,
        targetAmount = targetAmount,
        deadlineEpochDay = deadlineEpochDay,
        startDateEpochDay = startDateEpochDay,
        lifecycleStatus = lifecycleStatus,
        emoji = emoji,
        description = description
    )

    // ========== Insert Tests ==========

    @Test
    fun insert_singleGoal_success() = runTest {
        val goal = createGoalEntity()
        goalDao.insert(goal)

        val result = goalDao.getGoalByIdOnce(goal.id)
        assertNotNull(result)
        assertEquals(goal.name, result?.name)
    }

    @Test
    fun insertAll_multipleGoals_success() = runTest {
        val goals = listOf(
            createGoalEntity(id = "goal-1", name = "Goal 1"),
            createGoalEntity(id = "goal-2", name = "Goal 2"),
            createGoalEntity(id = "goal-3", name = "Goal 3")
        )
        goalDao.insertAll(goals)

        val count = goalDao.getGoalCount()
        assertEquals(3, count)
    }

    @Test
    fun insert_replaceOnConflict_success() = runTest {
        val goal = createGoalEntity(name = "Original")
        goalDao.insert(goal)

        val updated = goal.copy(name = "Updated")
        goalDao.insert(updated)

        val result = goalDao.getGoalByIdOnce(goal.id)
        assertEquals("Updated", result?.name)
    }

    // ========== Query Tests ==========

    @Test
    fun getAllGoals_empty_returnsEmptyList() = runTest {
        val goals = goalDao.getAllGoals().first()
        assertTrue(goals.isEmpty())
    }

    @Test
    fun getAllGoals_withData_returnsSortedByDeadline() = runTest {
        val baseDay = LocalDate.now().toEpochDay().toInt()
        val goals = listOf(
            createGoalEntity(id = "goal-3", deadlineEpochDay = baseDay + 90),
            createGoalEntity(id = "goal-1", deadlineEpochDay = baseDay + 30),
            createGoalEntity(id = "goal-2", deadlineEpochDay = baseDay + 60)
        )
        goalDao.insertAll(goals)

        val result = goalDao.getAllGoals().first()
        assertEquals(3, result.size)
        assertEquals("goal-1", result[0].id) // Earliest deadline first
        assertEquals("goal-2", result[1].id)
        assertEquals("goal-3", result[2].id)
    }

    @Test
    fun getActiveGoals_filtersCorrectly() = runTest {
        val goals = listOf(
            createGoalEntity(id = "goal-1", lifecycleStatus = "active"),
            createGoalEntity(id = "goal-2", lifecycleStatus = "cancelled"),
            createGoalEntity(id = "goal-3", lifecycleStatus = "active"),
            createGoalEntity(id = "goal-4", lifecycleStatus = "finished")
        )
        goalDao.insertAll(goals)

        val activeGoals = goalDao.getActiveGoals().first()
        assertEquals(2, activeGoals.size)
        assertTrue(activeGoals.all { it.lifecycleStatus == "active" })
    }

    @Test
    fun getGoalsByStatus_filtersCorrectly() = runTest {
        val goals = listOf(
            createGoalEntity(id = "goal-1", lifecycleStatus = "active"),
            createGoalEntity(id = "goal-2", lifecycleStatus = "cancelled"),
            createGoalEntity(id = "goal-3", lifecycleStatus = "cancelled")
        )
        goalDao.insertAll(goals)

        val cancelledGoals = goalDao.getGoalsByStatus("cancelled").first()
        assertEquals(2, cancelledGoals.size)
        assertTrue(cancelledGoals.all { it.lifecycleStatus == "cancelled" })
    }

    @Test
    fun getGoalById_flow_emitsUpdates() = runTest {
        val goal = createGoalEntity()
        goalDao.insert(goal)

        val flow = goalDao.getGoalById(goal.id)
        val initial = flow.first()
        assertEquals("Test Goal", initial?.name)

        // Update and verify flow emits new value
        goalDao.update(goal.copy(name = "Updated Name"))
        val updated = flow.first()
        assertEquals("Updated Name", updated?.name)
    }

    @Test
    fun getGoalByIdOnce_existingGoal_returnsGoal() = runTest {
        val goal = createGoalEntity()
        goalDao.insert(goal)

        val result = goalDao.getGoalByIdOnce(goal.id)
        assertNotNull(result)
        assertEquals(goal.id, result?.id)
    }

    @Test
    fun getGoalByIdOnce_nonExistentGoal_returnsNull() = runTest {
        val result = goalDao.getGoalByIdOnce("non-existent-id")
        assertNull(result)
    }

    // ========== Update Tests ==========

    @Test
    fun update_existingGoal_success() = runTest {
        val goal = createGoalEntity()
        goalDao.insert(goal)

        val updated = goal.copy(
            name = "Updated Name",
            targetAmount = 2000.0
        )
        goalDao.update(updated)

        val result = goalDao.getGoalByIdOnce(goal.id)
        assertEquals("Updated Name", result?.name)
        assertEquals(2000.0, result?.targetAmount)
    }

    @Test
    fun updateLifecycleStatus_success() = runTest {
        val goal = createGoalEntity(lifecycleStatus = "active")
        goalDao.insert(goal)

        val now = System.currentTimeMillis()
        goalDao.updateLifecycleStatus(goal.id, "finished", now, now)

        val result = goalDao.getGoalByIdOnce(goal.id)
        assertEquals("finished", result?.lifecycleStatus)
        assertEquals(now, result?.lifecycleStatusChangedAtUtcMillis)
        assertEquals(now, result?.lastModifiedAtUtcMillis)
    }

    // ========== Delete Tests ==========

    @Test
    fun delete_existingGoal_success() = runTest {
        val goal = createGoalEntity()
        goalDao.insert(goal)

        goalDao.delete(goal)

        val result = goalDao.getGoalByIdOnce(goal.id)
        assertNull(result)
    }

    @Test
    fun deleteById_existingGoal_success() = runTest {
        val goal = createGoalEntity()
        goalDao.insert(goal)

        goalDao.deleteById(goal.id)

        val result = goalDao.getGoalByIdOnce(goal.id)
        assertNull(result)
    }

    @Test
    fun deleteById_nonExistentGoal_noError() = runTest {
        // Should not throw
        goalDao.deleteById("non-existent-id")
    }

    // ========== Count Tests ==========

    @Test
    fun getGoalCount_empty_returnsZero() = runTest {
        val count = goalDao.getGoalCount()
        assertEquals(0, count)
    }

    @Test
    fun getGoalCount_withData_returnsCorrectCount() = runTest {
        val goals = listOf(
            createGoalEntity(id = "goal-1"),
            createGoalEntity(id = "goal-2"),
            createGoalEntity(id = "goal-3")
        )
        goalDao.insertAll(goals)

        val count = goalDao.getGoalCount()
        assertEquals(3, count)
    }

    @Test
    fun getActiveGoalCount_returnsOnlyActiveCount() = runTest {
        val goals = listOf(
            createGoalEntity(id = "goal-1", lifecycleStatus = "active"),
            createGoalEntity(id = "goal-2", lifecycleStatus = "cancelled"),
            createGoalEntity(id = "goal-3", lifecycleStatus = "active"),
            createGoalEntity(id = "goal-4", lifecycleStatus = "finished")
        )
        goalDao.insertAll(goals)

        val activeCount = goalDao.getActiveGoalCount()
        assertEquals(2, activeCount)
    }

    // ========== Edge Cases ==========

    @Test
    fun insert_goalWithAllFields_preservesAllData() = runTest {
        val now = System.currentTimeMillis()
        val goal = GoalEntity(
            id = "goal-full",
            name = "Full Goal",
            currency = "EUR",
            targetAmount = 5000.0,
            deadlineEpochDay = 19500,
            startDateEpochDay = 19400,
            lifecycleStatus = "active",
            lifecycleStatusChangedAtUtcMillis = now,
            emoji = "🎯",
            description = "Test description",
            link = "https://example.com",
            reminderFrequency = "weekly",
            reminderTimeUtcMillis = now,
            firstReminderEpochDay = 19410,
            createdAtUtcMillis = now,
            lastModifiedAtUtcMillis = now
        )
        goalDao.insert(goal)

        val result = goalDao.getGoalByIdOnce(goal.id)
        assertNotNull(result)
        assertEquals(goal.id, result?.id)
        assertEquals(goal.name, result?.name)
        assertEquals(goal.currency, result?.currency)
        assertEquals(goal.targetAmount, result?.targetAmount)
        assertEquals(goal.deadlineEpochDay, result?.deadlineEpochDay)
        assertEquals(goal.startDateEpochDay, result?.startDateEpochDay)
        assertEquals(goal.lifecycleStatus, result?.lifecycleStatus)
        assertEquals(goal.lifecycleStatusChangedAtUtcMillis, result?.lifecycleStatusChangedAtUtcMillis)
        assertEquals(goal.emoji, result?.emoji)
        assertEquals(goal.description, result?.description)
        assertEquals(goal.link, result?.link)
        assertEquals(goal.reminderFrequency, result?.reminderFrequency)
        assertEquals(goal.reminderTimeUtcMillis, result?.reminderTimeUtcMillis)
        assertEquals(goal.firstReminderEpochDay, result?.firstReminderEpochDay)
        assertEquals(goal.createdAtUtcMillis, result?.createdAtUtcMillis)
        assertEquals(goal.lastModifiedAtUtcMillis, result?.lastModifiedAtUtcMillis)
    }

    @Test
    fun update_preservesNullableFieldsCorrectly() = runTest {
        // Insert with emoji
        val goal = createGoalEntity(emoji = "🎯", description = "Test")
        goalDao.insert(goal)

        // Update to remove emoji
        val updated = goal.copy(emoji = null, description = null)
        goalDao.update(updated)

        val result = goalDao.getGoalByIdOnce(goal.id)
        assertNull(result?.emoji)
        assertNull(result?.description)
    }
}
