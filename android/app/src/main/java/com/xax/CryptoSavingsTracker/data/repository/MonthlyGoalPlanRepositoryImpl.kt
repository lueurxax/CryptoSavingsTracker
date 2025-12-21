package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.MonthlyGoalPlanDao
import com.xax.CryptoSavingsTracker.data.local.database.entity.MonthlyGoalPlanEntity
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlan
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlanState
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.domain.repository.MonthlyGoalPlanRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MonthlyGoalPlanRepositoryImpl @Inject constructor(
    private val dao: MonthlyGoalPlanDao
) : MonthlyGoalPlanRepository {
    override fun getPlansFlow(monthLabel: String): Flow<List<MonthlyGoalPlan>> {
        return dao.getPlansByMonthLabel(monthLabel).map { entities -> entities.map { it.toDomain() } }
    }

    override suspend fun getPlansOnce(monthLabel: String): List<MonthlyGoalPlan> {
        return dao.getPlansByMonthLabelOnce(monthLabel).map { it.toDomain() }
    }

    override suspend fun getPlanOnce(monthLabel: String, goalId: String): MonthlyGoalPlan? {
        return dao.getPlanOnce(monthLabel, goalId)?.toDomain()
    }

    override suspend fun upsertAll(plans: List<MonthlyGoalPlan>) {
        dao.insertAll(plans.map { it.toEntity() })
    }

    override suspend fun upsert(plan: MonthlyGoalPlan) {
        dao.insert(plan.toEntity())
    }

    private fun MonthlyGoalPlanEntity.toDomain(): MonthlyGoalPlan {
        return MonthlyGoalPlan(
            id = id,
            goalId = goalId,
            monthLabel = monthLabel,
            requiredMonthly = requiredMonthly,
            remainingAmount = remainingAmount,
            monthsRemaining = monthsRemaining,
            currency = currency,
            status = RequirementStatus.fromRawValue(status),
            state = MonthlyGoalPlanState.fromString(state),
            customAmount = customAmount,
            isProtected = isProtected,
            isSkipped = isSkipped,
            createdAtUtcMillis = createdAtUtcMillis,
            lastModifiedAtUtcMillis = lastModifiedAtUtcMillis
        )
    }

    private fun MonthlyGoalPlan.toEntity(): MonthlyGoalPlanEntity {
        val now = System.currentTimeMillis()
        return MonthlyGoalPlanEntity(
            id = id,
            goalId = goalId,
            monthLabel = monthLabel,
            requiredMonthly = requiredMonthly,
            remainingAmount = remainingAmount,
            monthsRemaining = monthsRemaining,
            currency = currency,
            status = when (status) {
                RequirementStatus.COMPLETED -> "completed"
                RequirementStatus.ON_TRACK -> "on_track"
                RequirementStatus.ATTENTION -> "attention"
                RequirementStatus.CRITICAL -> "critical"
            },
            state = state.rawValue,
            customAmount = customAmount,
            isProtected = isProtected,
            isSkipped = isSkipped,
            createdAtUtcMillis = createdAtUtcMillis,
            lastModifiedAtUtcMillis = now
        )
    }
}

