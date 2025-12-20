package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.MonthlyPlanDao
import com.xax.CryptoSavingsTracker.data.local.database.entity.MonthlyPlanEntity
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlan
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanSettings
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanStatus
import com.xax.CryptoSavingsTracker.domain.repository.MonthlyPlanRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MonthlyPlanRepositoryImpl @Inject constructor(
    private val monthlyPlanDao: MonthlyPlanDao
) : MonthlyPlanRepository {

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    override suspend fun getOrCreatePlanId(monthLabel: String): String {
        return getOrCreatePlan(monthLabel).id
    }

    override suspend fun getOrCreatePlan(monthLabel: String): MonthlyPlan {
        val existing = monthlyPlanDao.getPlanByMonthLabelOnce(monthLabel)
        if (existing != null) return existing.toDomain()

        val plan = MonthlyPlanEntity(
            monthLabel = monthLabel,
            status = "draft",
            flexPercentage = 1.0,
            totalRequired = 0.0,
            requirementsJson = json.encodeToString(MonthlyPlanSettings.serializer(), MonthlyPlanSettings())
        )
        monthlyPlanDao.insert(plan)
        return plan.toDomain()
    }

    override fun getPlanFlow(monthLabel: String): Flow<MonthlyPlan?> {
        return monthlyPlanDao.getPlanByMonthLabel(monthLabel).map { it?.toDomain() }
    }

    override suspend fun upsertPlan(plan: MonthlyPlan) {
        monthlyPlanDao.insert(plan.toEntity())
    }

    private fun MonthlyPlanEntity.toDomain(): MonthlyPlan {
        val settings = runCatching {
            json.decodeFromString(MonthlyPlanSettings.serializer(), requirementsJson)
        }.getOrDefault(MonthlyPlanSettings())

        return MonthlyPlan(
            id = id,
            monthLabel = monthLabel,
            status = MonthlyPlanStatus.fromString(status),
            flexPercentage = flexPercentage,
            totalRequired = totalRequired,
            settings = settings,
            createdAtUtcMillis = createdAtUtcMillis,
            lastModifiedAtUtcMillis = lastModifiedAtUtcMillis
        )
    }

    private fun MonthlyPlan.toEntity(): MonthlyPlanEntity {
        val now = System.currentTimeMillis()
        return MonthlyPlanEntity(
            id = id,
            monthLabel = monthLabel,
            status = when (status) {
                MonthlyPlanStatus.DRAFT -> "draft"
                MonthlyPlanStatus.EXECUTING -> "executing"
                MonthlyPlanStatus.CLOSED -> "closed"
            },
            flexPercentage = flexPercentage,
            totalRequired = totalRequired,
            requirementsJson = json.encodeToString(MonthlyPlanSettings.serializer(), settings),
            createdAtUtcMillis = createdAtUtcMillis,
            lastModifiedAtUtcMillis = now
        )
    }
}
