package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.AllocationHistoryDao
import com.xax.CryptoSavingsTracker.data.repository.AllocationHistoryMapper.toDomain
import com.xax.CryptoSavingsTracker.data.repository.AllocationHistoryMapper.toDomainList
import com.xax.CryptoSavingsTracker.data.repository.AllocationHistoryMapper.toEntity
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Implementation of AllocationHistoryRepository using Room DAO.
 */
@Singleton
class AllocationHistoryRepositoryImpl @Inject constructor(
    private val allocationHistoryDao: AllocationHistoryDao
) : AllocationHistoryRepository {

    override fun getAll(): Flow<List<AllocationHistory>> {
        return allocationHistoryDao.getAll().map { it.toDomainList() }
    }

    override fun getByMonthLabel(monthLabel: String): Flow<List<AllocationHistory>> {
        return allocationHistoryDao.getByMonthLabel(monthLabel).map { it.toDomainList() }
    }

    override fun getByAssetId(assetId: String): Flow<List<AllocationHistory>> {
        return allocationHistoryDao.getByAssetId(assetId).map { it.toDomainList() }
    }

    override fun getByGoalId(goalId: String): Flow<List<AllocationHistory>> {
        return allocationHistoryDao.getByGoalId(goalId).map { it.toDomainList() }
    }

    override suspend fun getByAssetGoalMonth(
        assetId: String,
        goalId: String,
        monthLabel: String
    ): AllocationHistory? {
        return allocationHistoryDao.getByAssetGoalMonth(assetId, goalId, monthLabel)?.toDomain()
    }

    override suspend fun insert(history: AllocationHistory) {
        allocationHistoryDao.insert(history.toEntity())
    }

    override suspend fun insertAll(histories: List<AllocationHistory>) {
        allocationHistoryDao.insertAll(histories.map { it.toEntity() })
    }

    override suspend fun deleteById(id: String) {
        allocationHistoryDao.deleteById(id)
    }

    override suspend fun deleteByMonthLabel(monthLabel: String) {
        allocationHistoryDao.deleteByMonthLabel(monthLabel)
    }
}
