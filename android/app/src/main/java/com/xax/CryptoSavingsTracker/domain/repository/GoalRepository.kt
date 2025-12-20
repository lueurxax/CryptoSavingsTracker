package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import kotlinx.coroutines.flow.Flow

/**
 * Repository interface for Goal operations.
 * Follows the repository pattern from clean architecture.
 */
interface GoalRepository {
    /**
     * Get all goals as a Flow for reactive updates
     */
    fun getAllGoals(): Flow<List<Goal>>

    /**
     * Get goals filtered by lifecycle status
     */
    fun getGoalsByStatus(status: GoalLifecycleStatus): Flow<List<Goal>>

    /**
     * Get active goals only
     */
    fun getActiveGoals(): Flow<List<Goal>>

    /**
     * Get a single goal by ID
     */
    suspend fun getGoalById(id: String): Goal?

    /**
     * Get a single goal by ID as a Flow for reactive updates
     */
    fun getGoalByIdFlow(id: String): Flow<Goal?>

    /**
     * Insert a new goal
     */
    suspend fun insertGoal(goal: Goal)

    /**
     * Update an existing goal
     */
    suspend fun updateGoal(goal: Goal)

    /**
     * Delete a goal by ID
     */
    suspend fun deleteGoal(id: String)

    /**
     * Delete a goal
     */
    suspend fun deleteGoal(goal: Goal)

    /**
     * Update goal lifecycle status
     */
    suspend fun updateGoalStatus(id: String, status: GoalLifecycleStatus)

    /**
     * Get count of active goals
     */
    fun getActiveGoalCount(): Flow<Int>
}
