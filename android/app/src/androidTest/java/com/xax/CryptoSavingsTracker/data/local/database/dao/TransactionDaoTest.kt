package com.xax.CryptoSavingsTracker.data.local.database.dao

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.TransactionEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Comprehensive tests for TransactionDao.
 * Tests all CRUD operations and queries with 100% coverage.
 */
@RunWith(AndroidJUnit4::class)
class TransactionDaoTest {

    private lateinit var database: AppDatabase
    private lateinit var transactionDao: TransactionDao
    private lateinit var assetDao: AssetDao

    // Pre-created asset for foreign key constraint
    private val testAsset = AssetEntity(
        id = "test-asset-1",
        currency = "BTC",
        address = "0xTestAddress"
    )

    private val testAsset2 = AssetEntity(
        id = "test-asset-2",
        currency = "ETH",
        address = "0xTestAddress2"
    )

    @Before
    fun createDb() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(
            context,
            AppDatabase::class.java
        ).allowMainThreadQueries().build()
        transactionDao = database.transactionDao()
        assetDao = database.assetDao()

        // Insert test assets for foreign key constraints
        kotlinx.coroutines.runBlocking {
            assetDao.insert(testAsset)
            assetDao.insert(testAsset2)
        }
    }

    @After
    fun closeDb() {
        database.close()
    }

    // ========== Test Data Helpers ==========

    private fun createTransactionEntity(
        id: String = "tx-1",
        assetId: String = testAsset.id,
        amount: Double = 1.5,
        dateUtcMillis: Long = System.currentTimeMillis(),
        source: String = "manual",
        externalId: String? = null,
        counterparty: String? = null,
        comment: String? = null
    ) = TransactionEntity(
        id = id,
        assetId = assetId,
        amount = amount,
        dateUtcMillis = dateUtcMillis,
        source = source,
        externalId = externalId,
        counterparty = counterparty,
        comment = comment
    )

    // ========== Insert Tests ==========

    @Test
    fun insert_singleTransaction_success() = runTest {
        val tx = createTransactionEntity()
        transactionDao.insert(tx)

        val result = transactionDao.getTransactionByIdOnce(tx.id)
        assertNotNull(result)
        assertEquals(tx.amount, result?.amount)
    }

    @Test
    fun insertAll_multipleTransactions_success() = runTest {
        val now = System.currentTimeMillis()
        val transactions = listOf(
            createTransactionEntity(id = "tx-1", dateUtcMillis = now, externalId = "ext1"),
            createTransactionEntity(id = "tx-2", dateUtcMillis = now + 1000, externalId = "ext2"),
            createTransactionEntity(id = "tx-3", dateUtcMillis = now + 2000, externalId = "ext3")
        )
        transactionDao.insertAll(transactions)

        val count = transactionDao.getTransactionCount()
        assertEquals(3, count)
    }

    @Test
    fun insert_replaceOnConflict_success() = runTest {
        val tx = createTransactionEntity(amount = 1.0)
        transactionDao.insert(tx)

        val updated = tx.copy(amount = 2.0)
        transactionDao.insert(updated)

        val result = transactionDao.getTransactionByIdOnce(tx.id)
        assertEquals(2.0, result?.amount)
    }

    // ========== Query Tests ==========

    @Test
    fun getAllTransactions_empty_returnsEmptyList() = runTest {
        val transactions = transactionDao.getAllTransactions().first()
        assertTrue(transactions.isEmpty())
    }

    @Test
    fun getAllTransactions_withData_returnsSortedByDateDescending() = runTest {
        val now = System.currentTimeMillis()
        val transactions = listOf(
            createTransactionEntity(id = "tx-2", dateUtcMillis = now - 1000, externalId = "ext2"),
            createTransactionEntity(id = "tx-3", dateUtcMillis = now - 2000, externalId = "ext3"),
            createTransactionEntity(id = "tx-1", dateUtcMillis = now, externalId = "ext1")
        )
        transactionDao.insertAll(transactions)

        val result = transactionDao.getAllTransactions().first()
        assertEquals(3, result.size)
        assertEquals("tx-1", result[0].id) // Most recent first
        assertEquals("tx-2", result[1].id)
        assertEquals("tx-3", result[2].id)
    }

    @Test
    fun getTransactionsByAssetId_filtersCorrectly() = runTest {
        val transactions = listOf(
            createTransactionEntity(id = "tx-1", assetId = testAsset.id, externalId = "ext1"),
            createTransactionEntity(id = "tx-2", assetId = testAsset2.id, externalId = "ext2"),
            createTransactionEntity(id = "tx-3", assetId = testAsset.id, externalId = "ext3")
        )
        transactionDao.insertAll(transactions)

        val result = transactionDao.getTransactionsByAssetId(testAsset.id).first()
        assertEquals(2, result.size)
        assertTrue(result.all { it.assetId == testAsset.id })
    }

    @Test
    fun getTransactionById_flow_emitsUpdates() = runTest {
        val tx = createTransactionEntity()
        transactionDao.insert(tx)

        val flow = transactionDao.getTransactionById(tx.id)
        val initial = flow.first()
        assertEquals(1.5, initial?.amount)

        // Update and verify flow emits new value
        transactionDao.update(tx.copy(amount = 3.0))
        val updated = flow.first()
        assertEquals(3.0, updated?.amount)
    }

    @Test
    fun getTransactionByIdOnce_existingTransaction_returnsTransaction() = runTest {
        val tx = createTransactionEntity()
        transactionDao.insert(tx)

        val result = transactionDao.getTransactionByIdOnce(tx.id)
        assertNotNull(result)
        assertEquals(tx.id, result?.id)
    }

    @Test
    fun getTransactionByIdOnce_nonExistentTransaction_returnsNull() = runTest {
        val result = transactionDao.getTransactionByIdOnce("non-existent-id")
        assertNull(result)
    }

    @Test
    fun getTransactionByExternalId_existingExternalId_returnsTransaction() = runTest {
        val tx = createTransactionEntity(externalId = "blockchain-tx-123")
        transactionDao.insert(tx)

        val result = transactionDao.getTransactionByExternalId("blockchain-tx-123")
        assertNotNull(result)
        assertEquals(tx.id, result?.id)
    }

    @Test
    fun getTransactionByExternalId_nonExistentExternalId_returnsNull() = runTest {
        val result = transactionDao.getTransactionByExternalId("non-existent-external-id")
        assertNull(result)
    }

    @Test
    fun getTransactionsInRange_returnsOnlyMatchingTransactions() = runTest {
        val baseTime = System.currentTimeMillis()
        val transactions = listOf(
            createTransactionEntity(id = "tx-1", dateUtcMillis = baseTime - 2000, externalId = "ext1"),
            createTransactionEntity(id = "tx-2", dateUtcMillis = baseTime, externalId = "ext2"),
            createTransactionEntity(id = "tx-3", dateUtcMillis = baseTime + 1000, externalId = "ext3"),
            createTransactionEntity(id = "tx-4", dateUtcMillis = baseTime + 3000, externalId = "ext4")
        )
        transactionDao.insertAll(transactions)

        // Get transactions from baseTime to baseTime + 2000 (exclusive)
        val result = transactionDao.getTransactionsInRange(
            testAsset.id,
            baseTime,
            baseTime + 2000
        ).first()

        assertEquals(2, result.size)
        assertEquals("tx-2", result[0].id) // Sorted by date ASC
        assertEquals("tx-3", result[1].id)
    }

    // ========== Aggregation Tests ==========

    @Test
    fun getTotalAmountForAsset_empty_returnsNull() = runTest {
        val result = transactionDao.getTotalAmountForAsset(testAsset.id)
        assertNull(result)
    }

    @Test
    fun getTotalAmountForAsset_withData_returnsSumOfAmounts() = runTest {
        val transactions = listOf(
            createTransactionEntity(id = "tx-1", amount = 10.0, externalId = "ext1"),
            createTransactionEntity(id = "tx-2", amount = 5.0, externalId = "ext2"),
            createTransactionEntity(id = "tx-3", amount = -3.0, externalId = "ext3") // Withdrawal
        )
        transactionDao.insertAll(transactions)

        val result = transactionDao.getTotalAmountForAsset(testAsset.id)
        assertEquals(12.0, result ?: 0.0, 0.001)
    }

    @Test
    fun getTotalAmountForAssetSince_returnsCorrectSum() = runTest {
        val baseTime = System.currentTimeMillis()
        val transactions = listOf(
            createTransactionEntity(id = "tx-1", amount = 5.0, dateUtcMillis = baseTime - 2000, externalId = "ext1"),
            createTransactionEntity(id = "tx-2", amount = 10.0, dateUtcMillis = baseTime, externalId = "ext2"),
            createTransactionEntity(id = "tx-3", amount = 3.0, dateUtcMillis = baseTime + 1000, externalId = "ext3")
        )
        transactionDao.insertAll(transactions)

        val result = transactionDao.getTotalAmountForAssetSince(testAsset.id, baseTime)
        assertEquals(13.0, result ?: 0.0, 0.001) // Only tx-2 and tx-3
    }

    // ========== Update Tests ==========

    @Test
    fun update_existingTransaction_success() = runTest {
        val tx = createTransactionEntity()
        transactionDao.insert(tx)

        val updated = tx.copy(
            amount = 5.0,
            comment = "Updated comment"
        )
        transactionDao.update(updated)

        val result = transactionDao.getTransactionByIdOnce(tx.id)
        assertEquals(5.0, result?.amount)
        assertEquals("Updated comment", result?.comment)
    }

    // ========== Delete Tests ==========

    @Test
    fun delete_existingTransaction_success() = runTest {
        val tx = createTransactionEntity()
        transactionDao.insert(tx)

        transactionDao.delete(tx)

        val result = transactionDao.getTransactionByIdOnce(tx.id)
        assertNull(result)
    }

    @Test
    fun deleteById_existingTransaction_success() = runTest {
        val tx = createTransactionEntity()
        transactionDao.insert(tx)

        transactionDao.deleteById(tx.id)

        val result = transactionDao.getTransactionByIdOnce(tx.id)
        assertNull(result)
    }

    @Test
    fun deleteById_nonExistentTransaction_noError() = runTest {
        // Should not throw
        transactionDao.deleteById("non-existent-id")
    }

    // ========== Count Tests ==========

    @Test
    fun getTransactionCount_empty_returnsZero() = runTest {
        val count = transactionDao.getTransactionCount()
        assertEquals(0, count)
    }

    @Test
    fun getTransactionCount_withData_returnsCorrectCount() = runTest {
        val transactions = listOf(
            createTransactionEntity(id = "tx-1", externalId = "ext1"),
            createTransactionEntity(id = "tx-2", externalId = "ext2"),
            createTransactionEntity(id = "tx-3", externalId = "ext3")
        )
        transactionDao.insertAll(transactions)

        val count = transactionDao.getTransactionCount()
        assertEquals(3, count)
    }

    @Test
    fun getTransactionCountForAsset_returnsCorrectCount() = runTest {
        val transactions = listOf(
            createTransactionEntity(id = "tx-1", assetId = testAsset.id, externalId = "ext1"),
            createTransactionEntity(id = "tx-2", assetId = testAsset2.id, externalId = "ext2"),
            createTransactionEntity(id = "tx-3", assetId = testAsset.id, externalId = "ext3"),
            createTransactionEntity(id = "tx-4", assetId = testAsset.id, externalId = "ext4")
        )
        transactionDao.insertAll(transactions)

        val countAsset1 = transactionDao.getTransactionCountForAsset(testAsset.id)
        val countAsset2 = transactionDao.getTransactionCountForAsset(testAsset2.id)

        assertEquals(3, countAsset1)
        assertEquals(1, countAsset2)
    }

    // ========== Edge Cases ==========

    @Test
    fun insert_transactionWithAllFields_preservesAllData() = runTest {
        val now = System.currentTimeMillis()
        val tx = TransactionEntity(
            id = "tx-full",
            assetId = testAsset.id,
            amount = 123.456,
            dateUtcMillis = now,
            source = "on_chain",
            externalId = "blockchain-tx-hash-123",
            counterparty = "0xSenderAddress",
            comment = "Test transaction with all fields",
            createdAtUtcMillis = now
        )
        transactionDao.insert(tx)

        val result = transactionDao.getTransactionByIdOnce(tx.id)
        assertNotNull(result)
        assertEquals(tx.id, result?.id)
        assertEquals(tx.assetId, result?.assetId)
        assertEquals(tx.amount, result?.amount)
        assertEquals(tx.dateUtcMillis, result?.dateUtcMillis)
        assertEquals(tx.source, result?.source)
        assertEquals(tx.externalId, result?.externalId)
        assertEquals(tx.counterparty, result?.counterparty)
        assertEquals(tx.comment, result?.comment)
        assertEquals(tx.createdAtUtcMillis, result?.createdAtUtcMillis)
    }

    @Test
    fun update_nullableFieldsToNull_preservesCorrectly() = runTest {
        val tx = createTransactionEntity(
            externalId = "original-external-id",
            counterparty = "original-counterparty",
            comment = "original-comment"
        )
        transactionDao.insert(tx)

        val updated = tx.copy(
            externalId = null,
            counterparty = null,
            comment = null
        )
        transactionDao.update(updated)

        val result = transactionDao.getTransactionByIdOnce(tx.id)
        assertNull(result?.externalId)
        assertNull(result?.counterparty)
        assertNull(result?.comment)
    }

    @Test
    fun cascadeDelete_whenAssetDeleted_deletesTransactions() = runTest {
        val transactions = listOf(
            createTransactionEntity(id = "tx-1", assetId = testAsset.id, externalId = "ext1"),
            createTransactionEntity(id = "tx-2", assetId = testAsset.id, externalId = "ext2")
        )
        transactionDao.insertAll(transactions)

        // Verify transactions exist
        assertEquals(2, transactionDao.getTransactionCountForAsset(testAsset.id))

        // Delete the asset - should cascade delete transactions
        assetDao.delete(testAsset)

        // Verify transactions are deleted
        assertEquals(0, transactionDao.getTransactionCountForAsset(testAsset.id))
    }

    @Test
    fun negativeAmount_withdrawal_handledCorrectly() = runTest {
        val deposit = createTransactionEntity(id = "tx-1", amount = 100.0, externalId = "ext1")
        val withdrawal = createTransactionEntity(id = "tx-2", amount = -30.0, externalId = "ext2")
        transactionDao.insertAll(listOf(deposit, withdrawal))

        val total = transactionDao.getTotalAmountForAsset(testAsset.id)
        assertEquals(70.0, total ?: 0.0, 0.001)
    }
}
