package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface AssetDao {

    @Query("SELECT * FROM assets ORDER BY currency ASC")
    fun getAllAssets(): Flow<List<AssetEntity>>

    @Query("SELECT * FROM assets WHERE id = :id")
    fun getAssetById(id: String): Flow<AssetEntity?>

    @Query("SELECT * FROM assets WHERE id = :id")
    suspend fun getAssetByIdOnce(id: String): AssetEntity?

    @Query("SELECT * FROM assets WHERE address = :address")
    suspend fun getAssetByAddress(address: String): AssetEntity?

    @Query("SELECT * FROM assets WHERE currency = :currency")
    fun getAssetsByCurrency(currency: String): Flow<List<AssetEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(asset: AssetEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(assets: List<AssetEntity>)

    @Update
    suspend fun update(asset: AssetEntity)

    @Delete
    suspend fun delete(asset: AssetEntity)

    @Query("DELETE FROM assets WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("SELECT COUNT(*) FROM assets")
    suspend fun getAssetCount(): Int
}
