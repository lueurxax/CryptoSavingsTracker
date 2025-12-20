package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.xax.CryptoSavingsTracker.data.local.database.entity.MonthlyPlanEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface MonthlyPlanDao {

    @Query("SELECT * FROM monthly_plans ORDER BY month_label DESC")
    fun getAllPlans(): Flow<List<MonthlyPlanEntity>>

    @Query("SELECT * FROM monthly_plans WHERE month_label = :monthLabel")
    fun getPlanByMonthLabel(monthLabel: String): Flow<MonthlyPlanEntity?>

    @Query("SELECT * FROM monthly_plans WHERE month_label = :monthLabel")
    suspend fun getPlanByMonthLabelOnce(monthLabel: String): MonthlyPlanEntity?

    @Query("SELECT * FROM monthly_plans WHERE id = :id")
    suspend fun getPlanById(id: String): MonthlyPlanEntity?

    @Query("SELECT * FROM monthly_plans WHERE status = :status ORDER BY month_label DESC")
    fun getPlansByStatus(status: String): Flow<List<MonthlyPlanEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(plan: MonthlyPlanEntity)

    @Update
    suspend fun update(plan: MonthlyPlanEntity)

    @Delete
    suspend fun delete(plan: MonthlyPlanEntity)

    @Query("DELETE FROM monthly_plans WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("UPDATE monthly_plans SET status = :status, last_modified_at_utc_millis = :modifiedAt WHERE id = :id")
    suspend fun updateStatus(id: String, status: String, modifiedAt: Long)
}
