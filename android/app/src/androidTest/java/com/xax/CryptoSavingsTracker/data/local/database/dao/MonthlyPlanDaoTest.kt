package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.data.local.database.TestDatabaseFactory
import com.xax.CryptoSavingsTracker.data.local.database.entity.MonthlyPlanEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull

@RunWith(AndroidJUnit4::class)
class MonthlyPlanDaoTest {

    private lateinit var db: AppDatabase
    private lateinit var monthlyPlanDao: MonthlyPlanDao

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        db = TestDatabaseFactory.create(context)
        monthlyPlanDao = db.monthlyPlanDao()
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun insertAndGetPlanByMonthLabel_returnsInsertedPlan() = runBlocking {
        val plan = MonthlyPlanEntity(
            id = "plan-1",
            monthLabel = "2025-12",
            status = "draft",
            flexPercentage = 1.0,
            totalRequired = 123.0,
            requirementsJson = "{}"
        )
        monthlyPlanDao.insert(plan)

        val loaded = monthlyPlanDao.getPlanByMonthLabel("2025-12").first()
        assertNotNull(loaded)
        assertEquals("plan-1", loaded?.id)
    }

    @Test
    fun updateStatus_changesStatus() = runBlocking {
        val plan = MonthlyPlanEntity(
            id = "plan-2",
            monthLabel = "2026-01",
            status = "draft"
        )
        monthlyPlanDao.insert(plan)

        monthlyPlanDao.updateStatus(id = "plan-2", status = "executing", modifiedAt = 10L)

        val loaded = monthlyPlanDao.getPlanByMonthLabelOnce("2026-01")
        assertNotNull(loaded)
        assertEquals("executing", loaded?.status)
        assertEquals(10L, loaded?.lastModifiedAtUtcMillis)
    }
}
