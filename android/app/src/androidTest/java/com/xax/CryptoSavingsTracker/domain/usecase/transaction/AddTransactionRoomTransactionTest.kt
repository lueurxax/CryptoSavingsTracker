package com.xax.CryptoSavingsTracker.domain.usecase.transaction

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetAllocationEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.GoalEntity
import com.xax.CryptoSavingsTracker.data.repository.AllocationHistoryRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.AllocationRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.AssetRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.ExecutionTransitionTransactionRunnerImpl
import com.xax.CryptoSavingsTracker.data.repository.TransactionRepositoryImpl
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationHistoryService
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AddTransactionRoomTransactionTest {
    private lateinit var database: AppDatabase
    private lateinit var transactionRepository: TransactionRepositoryImpl
    private lateinit var allocationRepository: AllocationRepositoryImpl
    private lateinit var assetRepository: AssetRepositoryImpl
    private lateinit var transactionRunner: ExecutionTransitionTransactionRunnerImpl

    @Before
    fun setUp() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        database = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        transactionRepository = TransactionRepositoryImpl(database.transactionDao())
        allocationRepository = AllocationRepositoryImpl(database.allocationDao())
        assetRepository = AssetRepositoryImpl(database.assetDao())
        transactionRunner = ExecutionTransitionTransactionRunnerImpl(database)

        database.assetDao().insert(
            AssetEntity(
                id = ASSET_ID,
                currency = "USD",
                address = null,
                chainId = null,
                createdAtUtcMillis = 1L,
                lastModifiedAtUtcMillis = 1L
            )
        )
        database.goalDao().insert(
            GoalEntity(
                id = GOAL_ID,
                name = "Goal",
                currency = "USD",
                targetAmount = 100.0,
                deadlineEpochDay = 30_000,
                startDateEpochDay = 20_000,
                lifecycleStatus = "active",
                createdAtUtcMillis = 1L,
                lastModifiedAtUtcMillis = 1L
            )
        )
        database.allocationDao().insert(
            AssetAllocationEntity(
                id = ALLOCATION_ID,
                assetId = ASSET_ID,
                goalId = GOAL_ID,
                amount = 10.0,
                createdAtUtcMillis = 1L,
                lastModifiedAtUtcMillis = 1L
            )
        )
        database.transactionDao().insert(
            com.xax.CryptoSavingsTracker.data.local.database.entity.TransactionEntity(
                id = "opening-balance",
                assetId = ASSET_ID,
                amount = 10.0,
                dateUtcMillis = 1L,
                source = "manual",
                createdAtUtcMillis = 1L
            )
        )
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun historyFailureRollsBackTransactionAndAllocationThenRetryCommitsAll() = runBlocking {
        val failingHistory = mockk<AllocationHistoryService>()
        coEvery {
            failingHistory.createSnapshot(any(), timestampMillis = TRANSACTION_DATE)
        } throws IllegalStateException("simulated history failure")

        val failure = runCatching {
            useCase(failingHistory)(transaction)
        }.exceptionOrNull()

        assertEquals("simulated history failure", failure?.message)
        assertNull(database.transactionDao().getTransactionByIdOnce(TRANSACTION_ID))
        assertEquals(
            10.0,
            database.allocationDao().getAllocationById(ALLOCATION_ID)?.amount ?: Double.NaN,
            0.0
        )
        assertNull(
            database.allocationHistoryDao().getByAssetGoalMonth(
                ASSET_ID,
                GOAL_ID,
                "1970-01"
            )
        )

        val realHistory = AllocationHistoryService(
            AllocationHistoryRepositoryImpl(database.allocationHistoryDao())
        )
        useCase(realHistory)(transaction)

        assertEquals(2, database.transactionDao().getTransactionCountForAsset(ASSET_ID))
        assertEquals(
            11.0,
            database.allocationDao().getAllocationById(ALLOCATION_ID)?.amount ?: Double.NaN,
            0.0
        )
        assertEquals(
            11.0,
            database.allocationHistoryDao()
                .getByAssetGoalMonth(ASSET_ID, GOAL_ID, "1970-01")
                ?.amount ?: Double.NaN,
            0.0
        )
    }

    private fun useCase(
        historyService: AllocationHistoryService
    ) = AddTransactionUseCase(
        transactionRepository = transactionRepository,
        allocationRepository = allocationRepository,
        allocationHistoryService = historyService,
        assetRepository = assetRepository,
        onChainBalanceRepository = mockk<OnChainBalanceRepository>(relaxed = true),
        transactionRunner = transactionRunner
    )

    private val transaction
        get() = Transaction(
            id = TRANSACTION_ID,
            assetId = ASSET_ID,
            amount = 1.0,
            dateMillis = TRANSACTION_DATE,
            source = TransactionSource.MANUAL,
            externalId = null,
            counterparty = null,
            comment = null,
            createdAt = TRANSACTION_DATE
        )

    private companion object {
        const val ASSET_ID = "asset-1"
        const val GOAL_ID = "goal-1"
        const val ALLOCATION_ID = "allocation-1"
        const val TRANSACTION_ID = "transaction-1"
        const val TRANSACTION_DATE = 2L
    }
}
