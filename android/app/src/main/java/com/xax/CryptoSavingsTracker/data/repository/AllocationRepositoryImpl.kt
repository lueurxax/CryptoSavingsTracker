package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.AllocationDao
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Implementation of AllocationRepository using Room DAO.
 */
@Singleton
class AllocationRepositoryImpl @Inject constructor(
    private val allocationDao: AllocationDao
) : AllocationRepository {

    override suspend fun getTotalAllocatedForGoal(goalId: String): Double {
        return allocationDao.getTotalAllocatedForGoal(goalId) ?: 0.0
    }

    override suspend fun getTotalAllocatedForAsset(assetId: String): Double {
        return allocationDao.getTotalAllocatedForAsset(assetId) ?: 0.0
    }

    override fun getAllocationsForGoalFlow(goalId: String): Flow<Double> {
        return allocationDao.getAllocationsByGoalId(goalId).map { allocations ->
            allocations.sumOf { it.amount }
        }
    }
}
