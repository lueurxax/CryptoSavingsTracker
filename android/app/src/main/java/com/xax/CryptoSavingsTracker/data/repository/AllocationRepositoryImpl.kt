package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.AllocationDao
import com.xax.CryptoSavingsTracker.data.repository.AllocationMapper.toDomain
import com.xax.CryptoSavingsTracker.data.repository.AllocationMapper.toDomainList
import com.xax.CryptoSavingsTracker.data.repository.AllocationMapper.toEntity
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
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

    override suspend fun getAllocationsForGoal(goalId: String): List<Allocation> {
        return allocationDao.getAllocationsByGoalId(goalId).first().toDomainList()
    }

    override fun getAllocationsForGoalListFlow(goalId: String): Flow<List<Allocation>> {
        return allocationDao.getAllocationsByGoalId(goalId).map { it.toDomainList() }
    }

    override suspend fun getAllocationsForAsset(assetId: String): List<Allocation> {
        return allocationDao.getAllocationsByAssetId(assetId).first().toDomainList()
    }

    override suspend fun getAllocationByAssetAndGoal(assetId: String, goalId: String): Allocation? {
        return allocationDao.getAllocationByAssetAndGoal(assetId, goalId)?.toDomain()
    }

    override suspend fun upsertAllocation(allocation: Allocation) {
        allocationDao.insert(allocation.toEntity())
    }

    override suspend fun deleteAllocation(id: String) {
        allocationDao.deleteById(id)
    }

    override suspend fun deleteAllocationsForGoal(goalId: String) {
        allocationDao.deleteByGoalId(goalId)
    }

    override suspend fun deleteAllocationsForAsset(assetId: String) {
        allocationDao.deleteByAssetId(assetId)
    }
}
