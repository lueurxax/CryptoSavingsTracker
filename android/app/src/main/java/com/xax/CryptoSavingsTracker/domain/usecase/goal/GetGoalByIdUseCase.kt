package com.xax.CryptoSavingsTracker.domain.usecase.goal

import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

/**
 * Use case for retrieving a single goal by ID
 */
class GetGoalByIdUseCase @Inject constructor(
    private val repository: GoalRepository
) {
    /**
     * Get goal by ID (suspend)
     */
    suspend operator fun invoke(id: String): Goal? {
        return repository.getGoalById(id)
    }

    /**
     * Get goal by ID as Flow for reactive updates
     */
    fun asFlow(id: String): Flow<Goal?> {
        return repository.getGoalByIdFlow(id)
    }
}
