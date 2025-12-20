package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.data.local.database.TestDatabaseFactory
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull

@RunWith(AndroidJUnit4::class)
class AssetDaoTest {

    private lateinit var db: AppDatabase
    private lateinit var assetDao: AssetDao

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        db = TestDatabaseFactory.create(context)
        assetDao = db.assetDao()
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun insertAndGetByIdOnce_returnsInsertedAsset() = runBlocking {
        val asset = AssetEntity(
            id = "asset-1",
            currency = "BTC",
            address = "0xabc",
            chainId = "ethereum"
        )
        assetDao.insert(asset)

        val loaded = assetDao.getAssetByIdOnce("asset-1")
        assertNotNull(loaded)
        assertEquals(asset, loaded)
    }

    @Test
    fun getAssetsByCurrency_filtersCorrectly() = runBlocking {
        assetDao.insert(AssetEntity(id = "a1", currency = "BTC"))
        assetDao.insert(AssetEntity(id = "a2", currency = "ETH"))

        val btc = assetDao.getAssetsByCurrency("BTC").first()
        assertEquals(listOf("a1"), btc.map { it.id })
    }
}
