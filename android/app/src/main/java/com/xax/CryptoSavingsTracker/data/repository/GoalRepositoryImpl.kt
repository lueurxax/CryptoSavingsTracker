package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.GoalDao
import com.xax.CryptoSavingsTracker.data.repository.GoalMapper.toDomain
import com.xax.CryptoSavingsTracker.data.repository.GoalMapper.toDomainList
import com.xax.CryptoSavingsTracker.data.repository.GoalMapper.toEntity
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Implementation of GoalRepository using Room database.
 */
@Singleton
class GoalRepositoryImpl @Inject constructor(
    private val goalDao: GoalDao
) : GoalRepository {

    override fun getAllGoals(): Flow<List<Goal>> {
        return goalDao.getAllGoals().map { entities ->
            entities.toDomainList()
        }
    }

    override fun getGoalsByStatus(status: GoalLifecycleStatus): Flow<List<Goal>> {
        return goalDao.getGoalsByStatus(status.name.lowercase()).map { entities ->
            entities.toDomainList()
        }
    }

    override fun getActiveGoals(): Flow<List<Goal>> {
        return goalDao.getActiveGoals().map { entities ->
            entities.toDomainList()
        }
    }

    override suspend fun getGoalById(id: String): Goal? {
        return goalDao.getGoalByIdOnce(id)?.toDomain()
    }

    override fun getGoalByIdFlow(id: String): Flow<Goal?> {
        return goalDao.getGoalById(id).map { entity ->
            entity?.toDomain()
        }
    }

    override suspend fun insertGoal(goal: Goal) {
        goalDao.insert(goal.toEntity())
    }

    override suspend fun updateGoal(goal: Goal) {
        goalDao.update(goal.toEntity())
    }

    override suspend fun deleteGoal(id: String) {
        goalDao.deleteById(id)
    }

    override suspend fun deleteGoal(goal: Goal) {
        goalDao.delete(goal.toEntity())
    }

    override suspend fun updateGoalStatus(id: String, status: GoalLifecycleStatus) {
        val now = System.currentTimeMillis()
        goalDao.updateLifecycleStatus(id, status.name.lowercase(), now, now)
    }

    override fun getActiveGoalCount(): Flow<Int> {
        // Since DAO returns suspend Int, we need to wrap it in a flow
        return goalDao.getActiveGoals().map { it.size }
    }
}
