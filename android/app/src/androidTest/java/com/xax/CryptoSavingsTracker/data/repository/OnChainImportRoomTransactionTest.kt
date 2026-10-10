package com.xax.CryptoSavingsTracker.data.repository

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.data.local.database.entity.AllocationHistoryEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetAllocationEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.GoalEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.TransactionEntity
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OnChainImportRoomTransactionTest {
    private lateinit var database: AppDatabase
    private lateinit var runner: ExecutionTransitionTransactionRunnerImpl

    @Before
    fun setUp() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        database = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        runner = ExecutionTransitionTransactionRunnerImpl(database)

        database.assetDao().insert(
            AssetEntity(
                id = ASSET_ID,
                currency = "ETH",
                address = "0xwallet",
                chainId = "ethereum",
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
        database.allocationDao().insert(initialAllocation)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun failedOnChainImportBatchRollsBackAndRetryCommitsExactlyOnce() = runBlocking {
        var failure: Throwable? = null
        try {
            runner.run {
                applyImportBatch()
                error("simulated allocation-history failure")
            }
        } catch (caught: Throwable) {
            failure = caught
        }

        assertEquals("simulated allocation-history failure", failure?.message)
        assertNull(database.transactionDao().getTransactionByIdOnce(TRANSACTION_ID))
        assertEquals(
            5.0,
            database.allocationDao().getAllocationById(ALLOCATION_ID)?.amount ?: Double.NaN,
            0.0
        )
        assertNull(database.allocationHistoryDao().getById(HISTORY_ID))

        runner.run {
            applyImportBatch()
        }

        assertEquals(1, database.transactionDao().getTransactionCountForAsset(ASSET_ID))
        assertEquals(
            6.0,
            database.allocationDao().getAllocationById(ALLOCATION_ID)?.amount ?: Double.NaN,
            0.0
        )
        assertEquals(6.0, database.allocationHistoryDao().getById(HISTORY_ID)?.amount ?: Double.NaN, 0.0)
    }

    @Test
    fun lateAliasAmbiguityRollsBackEarlierImportMutation() = runBlocking {
        val firstLegacy = TransactionEntity(
            id = "legacy-alias-a",
            assetId = ASSET_ID,
            amount = 2.0,
            dateUtcMillis = 1L,
            source = "onChain",
            externalId = "ambiguous-witness-hash",
            counterparty = "First counterparty",
            comment = "First durable note",
            createdAtUtcMillis = 1L
        )
        val secondLegacy = firstLegacy.copy(
            id = "legacy-alias-b",
            externalId = "utxo:$ASSET_ID:ambiguous-witness-hash",
            amount = 3.0,
            counterparty = "Second counterparty",
            comment = "Second durable note"
        )
        database.transactionDao().insert(firstLegacy)
        database.transactionDao().insert(secondLegacy)

        var failure: Throwable? = null
        try {
            runner.run {
                database.transactionDao().insert(
                    TransactionEntity(
                        id = "safe-earlier-import",
                        assetId = ASSET_ID,
                        amount = 1.0,
                        dateUtcMillis = 2L,
                        source = "onChain",
                        externalId = "utxo:$ASSET_ID:safe-txid",
                        createdAtUtcMillis = 2L
                    )
                )
                val installedAliasRows = mutableListOf<TransactionEntity>()
                for (externalId in listOf(
                    "ambiguous-witness-hash",
                    "utxo:$ASSET_ID:ambiguous-witness-hash"
                )) {
                    installedAliasRows += database.transactionDao()
                        .getTransactionsByExternalId(externalId)
                }
                check(installedAliasRows.distinctBy(TransactionEntity::id).size == 1) {
                    "UTXO transaction alias maps ambiguously to installed rows"
                }
            }
        } catch (caught: Throwable) {
            failure = caught
        }

        val expectedMessage = "UTXO transaction alias maps ambiguously to installed rows"
        assertNotNull(failure)
        val failureMessages = generateSequence(requireNotNull(failure)) { it.cause }
            .mapNotNull(Throwable::message)
            .toList()
        assertTrue(
            "Expected exact ambiguity failure in Room's exception chain, got $failureMessages",
            expectedMessage in failureMessages
        )
        assertNull(database.transactionDao().getTransactionByIdOnce("safe-earlier-import"))
        assertEquals(firstLegacy, database.transactionDao().getTransactionByIdOnce(firstLegacy.id))
        assertEquals(secondLegacy, database.transactionDao().getTransactionByIdOnce(secondLegacy.id))
    }

    private suspend fun applyImportBatch() {
        database.transactionDao().insert(
            TransactionEntity(
                id = TRANSACTION_ID,
                assetId = ASSET_ID,
                amount = 1.0,
                dateUtcMillis = 2L,
                source = "on_chain",
                externalId = "evm:event",
                createdAtUtcMillis = 2L
            )
        )
        database.allocationDao().update(
            initialAllocation.copy(
                amount = 6.0,
                lastModifiedAtUtcMillis = 2L
            )
        )
        database.allocationHistoryDao().insert(
            AllocationHistoryEntity(
                id = HISTORY_ID,
                assetId = ASSET_ID,
                goalId = GOAL_ID,
                amount = 6.0,
                monthLabel = "1970-01",
                timestampUtcMillis = 2L,
                createdAtUtcMillis = 2L
            )
        )
    }

    private val initialAllocation
        get() = AssetAllocationEntity(
            id = ALLOCATION_ID,
            assetId = ASSET_ID,
            goalId = GOAL_ID,
            amount = 5.0,
            createdAtUtcMillis = 1L,
            lastModifiedAtUtcMillis = 1L
        )

    private companion object {
        const val ASSET_ID = "asset-1"
        const val GOAL_ID = "goal-1"
        const val ALLOCATION_ID = "allocation-1"
        const val TRANSACTION_ID = "transaction-1"
        const val HISTORY_ID = "history-1"
    }
}
