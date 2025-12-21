package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlan
import kotlinx.coroutines.flow.Flow

interface MonthlyGoalPlanRepository {
    fun getPlansFlow(monthLabel: String): Flow<List<MonthlyGoalPlan>>

    suspend fun getPlansOnce(monthLabel: String): List<MonthlyGoalPlan>

    suspend fun getPlanOnce(monthLabel: String, goalId: String): MonthlyGoalPlan?

    suspend fun upsertAll(plans: List<MonthlyGoalPlan>)

    suspend fun upsert(plan: MonthlyGoalPlan)
}

