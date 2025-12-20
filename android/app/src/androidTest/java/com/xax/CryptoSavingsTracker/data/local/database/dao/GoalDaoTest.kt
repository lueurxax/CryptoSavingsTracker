package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.data.local.database.TestDatabaseFactory
import com.xax.CryptoSavingsTracker.data.local.database.entity.GoalEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull

@RunWith(AndroidJUnit4::class)
class GoalDaoTest {

    private lateinit var db: AppDatabase
    private lateinit var goalDao: GoalDao

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        db = TestDatabaseFactory.create(context)
        goalDao = db.goalDao()
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun insertAndGetByIdOnce_returnsInsertedGoal() = runBlocking {
        val goal = GoalEntity(
            id = "goal-1",
            name = "Emergency Fund",
            currency = "USD",
            targetAmount = 10_000.0,
            deadlineEpochDay = 20_000,
            startDateEpochDay = 19_000,
            lifecycleStatus = "active"
        )

        goalDao.insert(goal)

        val loaded = goalDao.getGoalByIdOnce("goal-1")
        assertNotNull(loaded)
        assertEquals(goal, loaded)
    }

    @Test
    fun updateLifecycleStatus_changesActiveGoalCount() = runBlocking {
        val goal = GoalEntity(
            id = "goal-2",
            name = "Vacation",
            currency = "USD",
            targetAmount = 2_000.0,
            deadlineEpochDay = 20_100,
            startDateEpochDay = 19_000,
            lifecycleStatus = "active"
        )
        goalDao.insert(goal)

        assertEquals(1, goalDao.getActiveGoalCount())

        goalDao.updateLifecycleStatus(
            id = "goal-2",
            status = "cancelled",
            changedAt = 1L,
            modifiedAt = 2L
        )

        assertEquals(0, goalDao.getActiveGoalCount())
        val cancelled = goalDao.getGoalsByStatus("cancelled").first()
        assertEquals(1, cancelled.size)
        assertEquals("goal-2", cancelled.first().id)
    }
}
