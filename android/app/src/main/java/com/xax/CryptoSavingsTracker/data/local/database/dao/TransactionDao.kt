package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.xax.CryptoSavingsTracker.data.local.database.entity.TransactionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface TransactionDao {

    @Query("SELECT * FROM transactions ORDER BY date_utc_millis DESC")
    fun getAllTransactions(): Flow<List<TransactionEntity>>

    @Query("SELECT * FROM transactions WHERE asset_id = :assetId ORDER BY date_utc_millis DESC")
    fun getTransactionsByAssetId(assetId: String): Flow<List<TransactionEntity>>

    @Query("SELECT * FROM transactions WHERE id = :id")
    fun getTransactionById(id: String): Flow<TransactionEntity?>

    @Query("SELECT * FROM transactions WHERE id = :id")
    suspend fun getTransactionByIdOnce(id: String): TransactionEntity?

    @Query("SELECT * FROM transactions WHERE external_id = :externalId")
    suspend fun getTransactionByExternalId(externalId: String): TransactionEntity?

    @Query("SELECT * FROM transactions WHERE asset_id = :assetId AND date_utc_millis >= :startMillis AND date_utc_millis < :endMillis ORDER BY date_utc_millis ASC")
    fun getTransactionsInRange(assetId: String, startMillis: Long, endMillis: Long): Flow<List<TransactionEntity>>

    @Query("SELECT SUM(amount) FROM transactions WHERE asset_id = :assetId")
    suspend fun getTotalAmountForAsset(assetId: String): Double?

    @Query("SELECT SUM(amount) FROM transactions WHERE asset_id = :assetId AND date_utc_millis >= :startMillis")
    suspend fun getTotalAmountForAssetSince(assetId: String, startMillis: Long): Double?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(transaction: TransactionEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(transactions: List<TransactionEntity>)

    @Update
    suspend fun update(transaction: TransactionEntity)

    @Delete
    suspend fun delete(transaction: TransactionEntity)

    @Query("DELETE FROM transactions WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("SELECT COUNT(*) FROM transactions")
    suspend fun getTransactionCount(): Int

    @Query("SELECT COUNT(*) FROM transactions WHERE asset_id = :assetId")
    suspend fun getTransactionCountForAsset(assetId: String): Int
}
