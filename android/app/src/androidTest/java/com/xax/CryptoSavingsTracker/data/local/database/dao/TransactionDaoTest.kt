package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.data.local.database.TestDatabaseFactory
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.TransactionEntity
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.assertEquals

@RunWith(AndroidJUnit4::class)
class TransactionDaoTest {

    private lateinit var db: AppDatabase
    private lateinit var assetDao: AssetDao
    private lateinit var transactionDao: TransactionDao

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        db = TestDatabaseFactory.create(context)
        assetDao = db.assetDao()
        transactionDao = db.transactionDao()
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun manualBalance_countsOnlyManualTransactions() = runBlocking {
        assetDao.insert(AssetEntity(id = "asset", currency = "USD"))

        transactionDao.insert(
            TransactionEntity(
                id = "t1",
                assetId = "asset",
                amount = 100.0,
                dateUtcMillis = 1L,
                source = "manual"
            )
        )
        transactionDao.insert(
            TransactionEntity(
                id = "t2",
                assetId = "asset",
                amount = 50.0,
                dateUtcMillis = 2L,
                source = "on_chain"
            )
        )

        assertEquals(100.0, transactionDao.getManualBalanceForAsset("asset"))
        assertEquals(150.0, transactionDao.getTotalAmountForAsset("asset"))
    }
}
