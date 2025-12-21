package com.xax.CryptoSavingsTracker.data.local.database.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.xax.CryptoSavingsTracker.data.local.database.entity.MonthlyGoalPlanEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface MonthlyGoalPlanDao {
    @Query("SELECT * FROM monthly_goal_plans WHERE month_label = :monthLabel ORDER BY goal_id")
    fun getPlansByMonthLabel(monthLabel: String): Flow<List<MonthlyGoalPlanEntity>>

    @Query("SELECT * FROM monthly_goal_plans WHERE month_label = :monthLabel")
    suspend fun getPlansByMonthLabelOnce(monthLabel: String): List<MonthlyGoalPlanEntity>

    @Query("SELECT * FROM monthly_goal_plans WHERE month_label = :monthLabel AND goal_id = :goalId LIMIT 1")
    suspend fun getPlanOnce(monthLabel: String, goalId: String): MonthlyGoalPlanEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(plans: List<MonthlyGoalPlanEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(plan: MonthlyGoalPlanEntity)
}

