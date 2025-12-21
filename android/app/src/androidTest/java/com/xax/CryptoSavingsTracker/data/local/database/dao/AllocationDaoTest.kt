package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.data.local.database.TestDatabaseFactory
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetAllocationEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetEntity
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
class AllocationDaoTest {

    private lateinit var db: AppDatabase
    private lateinit var allocationDao: AllocationDao
    private lateinit var assetDao: AssetDao
    private lateinit var goalDao: GoalDao

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        db = TestDatabaseFactory.create(context)
        allocationDao = db.allocationDao()
        assetDao = db.assetDao()
        goalDao = db.goalDao()
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun insertAndQueryByGoalId_returnsAllocation() = runBlocking {
        assetDao.insert(AssetEntity(id = "asset", currency = "USD"))
        goalDao.insert(
            GoalEntity(
                id = "goal",
                name = "Goal",
                currency = "USD",
                targetAmount = 100.0,
                deadlineEpochDay = 20_000,
                startDateEpochDay = 19_000,
                lifecycleStatus = "active"
            )
        )

        val allocation = AssetAllocationEntity(
            id = "alloc",
            assetId = "asset",
            goalId = "goal",
            amount = 12.34
        )
        allocationDao.insert(allocation)

        val forGoal = allocationDao.getAllocationsByGoalId("goal").first()
        assertEquals(1, forGoal.size)
        assertEquals(12.34, forGoal.first().amount, 0.000001)

        val lookup = allocationDao.getAllocationByAssetAndGoal("asset", "goal")
        assertNotNull(lookup)
        assertEquals("alloc", lookup?.id)
    }
}
