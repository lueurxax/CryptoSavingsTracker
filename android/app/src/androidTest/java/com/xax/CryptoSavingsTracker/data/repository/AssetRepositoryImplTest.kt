package com.xax.CryptoSavingsTracker.data.repository

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.domain.model.Asset
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AssetRepositoryImplTest {
    private lateinit var db: AppDatabase
    private lateinit var repo: AssetRepositoryImpl

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repo = AssetRepositoryImpl(db.assetDao())
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun insertAsset_thenFetchById() = runBlocking {
        val asset = Asset(
            id = "asset-1",
            currency = "BTC",
            address = "bc1qexample",
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 1L
        )

        repo.insertAsset(asset)

        val fetched = repo.getAssetById(asset.id)
        assertEquals(asset, fetched)

        val flowFetched = repo.getAssetByIdFlow(asset.id).first()
        assertEquals(asset, flowFetched)
    }
}

