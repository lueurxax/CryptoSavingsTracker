package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.xax.CryptoSavingsTracker.data.local.database.entity.ExecutionAssetRateEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ExecutionAssetRateDao {
    @Query("SELECT * FROM execution_asset_rates WHERE execution_record_id = :recordId")
    fun getByRecordId(recordId: String): Flow<List<ExecutionAssetRateEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(rates: List<ExecutionAssetRateEntity>)

    @Query("DELETE FROM execution_asset_rates WHERE execution_record_id = :recordId")
    suspend fun deleteByRecordId(recordId: String)
}
