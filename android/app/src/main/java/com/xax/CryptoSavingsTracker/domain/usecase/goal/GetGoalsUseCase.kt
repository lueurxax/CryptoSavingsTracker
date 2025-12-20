package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

/**
 * Use case for retrieving goals
 */
class GetGoalsUseCase @Inject constructor(
    private val repository: GoalRepository
) {
    /**
     * Get all goals
     */
    operator fun invoke(): Flow<List<Goal>> {
        return repository.getAllGoals()
    }

    /**
     * Get goals filtered by status
     */
    fun byStatus(status: GoalLifecycleStatus): Flow<List<Goal>> {
        return repository.getGoalsByStatus(status)
    }

    /**
     * Get active goals only
     */
    fun activeOnly(): Flow<List<Goal>> {
        return repository.getActiveGoals()
    }
}
