package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlan
import kotlinx.coroutines.flow.Flow

/**
 * Minimal access to MonthlyPlan needed for execution tracking.
 * Phase 4 will replace/expand this.
 */
interface MonthlyPlanRepository {
    suspend fun getOrCreatePlanId(monthLabel: String): String

    suspend fun getOrCreatePlan(monthLabel: String): MonthlyPlan

    fun getPlanFlow(monthLabel: String): Flow<MonthlyPlan?>

    suspend fun upsertPlan(plan: MonthlyPlan)
}
