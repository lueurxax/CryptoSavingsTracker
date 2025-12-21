package com.xax.CryptoSavingsTracker.data.repository

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TransactionRepositoryImplTest {
    private lateinit var db: AppDatabase
    private lateinit var assetRepo: AssetRepositoryImpl
    private lateinit var txRepo: TransactionRepositoryImpl

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        assetRepo = AssetRepositoryImpl(db.assetDao())
        txRepo = TransactionRepositoryImpl(db.transactionDao())
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun manualBalance_sumsOnlyManualTransactions() = runBlocking {
        val asset = Asset(
            id = "asset-1",
            currency = "BTC",
            address = "bc1qexample",
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 1L
        )
        assetRepo.insertAsset(asset)

        txRepo.insertTransactions(
            listOf(
                Transaction(
                    id = "t1",
                    assetId = asset.id,
                    amount = 1.0,
                    dateMillis = 1L,
                    source = TransactionSource.MANUAL,
                    externalId = null,
                    counterparty = null,
                    comment = null,
                    createdAt = 1L
                ),
                Transaction(
                    id = "t2",
                    assetId = asset.id,
                    amount = 10.0,
                    dateMillis = 2L,
                    source = TransactionSource.ON_CHAIN,
                    externalId = "ext",
                    counterparty = null,
                    comment = null,
                    createdAt = 2L
                )
            )
        )

        val manual = txRepo.getManualBalanceForAsset(asset.id)
        assertEquals(1.0, manual, 0.0000001)
    }
}

