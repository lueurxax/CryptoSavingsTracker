package com.xax.CryptoSavingsTracker.domain.usecase.allocation

import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

/**
 * Use case to get all allocations for a specific goal.
 */
class GetAllocationsForGoalUseCase @Inject constructor(
    private val allocationRepository: AllocationRepository
) {
    /**
     * Get allocations for a goal as a Flow for reactive updates.
     */
    operator fun invoke(goalId: String): Flow<List<Allocation>> {
        return allocationRepository.getAllocationsForGoalListFlow(goalId)
    }

    /**
     * Get allocations for a goal once (suspend function).
     */
    suspend fun getOnce(goalId: String): List<Allocation> {
        return allocationRepository.getAllocationsForGoal(goalId)
    }
}

/**
 * Use case to get all allocations for a specific asset.
 */
class GetAllocationsForAssetUseCase @Inject constructor(
    private val allocationRepository: AllocationRepository
) {
    /**
     * Get allocations for an asset.
     */
    suspend operator fun invoke(assetId: String): List<Allocation> {
        return allocationRepository.getAllocationsForAsset(assetId)
    }
}
