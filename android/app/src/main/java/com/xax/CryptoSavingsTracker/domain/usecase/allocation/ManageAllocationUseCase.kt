package com.xax.CryptoSavingsTracker.domain.usecase.allocation

import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import java.util.UUID
import javax.inject.Inject

/**
 * Use case to add a new allocation linking an asset to a goal.
 * Creates an AllocationHistory snapshot when the allocation is added.
 */
class AddAllocationUseCase @Inject constructor(
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryService: AllocationHistoryService,
    private val validationService: AllocationValidationService
) {
    /**
     * Add a new allocation.
     * @param assetId The asset to allocate from
     * @param goalId The goal to allocate to
     * @param amount The amount to allocate
     * @return Result with the created allocation or error
     */
    suspend operator fun invoke(
        assetId: String,
        goalId: String,
        amount: Double
    ): Result<Allocation> = runCatching {
        require(amount > 0) { "Allocation amount must be positive" }

        validationService.validateAllocation(
            assetId = assetId,
            goalId = goalId,
            amount = amount
        )?.let { message ->
            throw IllegalStateException(message)
        }

        // Check if allocation already exists for this asset-goal pair
        val existingAllocation = allocationRepository.getAllocationByAssetAndGoal(assetId, goalId)
        if (existingAllocation != null) {
            throw IllegalStateException("Allocation already exists for this asset and goal")
        }

        val now = System.currentTimeMillis()
        val allocation = Allocation(
            id = UUID.randomUUID().toString(),
            assetId = assetId,
            goalId = goalId,
            amount = amount,
            createdAt = now,
            lastModifiedAt = now
        )

        allocationRepository.upsertAllocation(allocation)

        // Create history snapshot for execution tracking
        allocationHistoryService.createSnapshot(allocation)

        allocation
    }
}

/**
 * Use case to update an existing allocation.
 * Creates an AllocationHistory snapshot when the allocation is updated.
 */
class UpdateAllocationUseCase @Inject constructor(
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryService: AllocationHistoryService,
    private val validationService: AllocationValidationService
) {
    /**
     * Update an allocation with full details.
     */
    suspend operator fun invoke(allocation: Allocation): Result<Allocation> = runCatching {
        require(allocation.amount > 0) { "Allocation amount must be positive" }
        validationService.validateAllocation(
            assetId = allocation.assetId,
            goalId = allocation.goalId,
            amount = allocation.amount,
            excludeAllocationId = allocation.id
        )?.let { message ->
            throw IllegalStateException(message)
        }

        val updatedAllocation = allocation.copy(
            lastModifiedAt = System.currentTimeMillis()
        )

        allocationRepository.upsertAllocation(updatedAllocation)

        // Create history snapshot for execution tracking
        allocationHistoryService.createSnapshot(updatedAllocation)

        updatedAllocation
    }
}

/**
 * Use case to delete an allocation.
 * Creates an AllocationHistory snapshot with amount=0 when the allocation is deleted.
 */
class DeleteAllocationUseCase @Inject constructor(
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryService: AllocationHistoryService
) {
    /**
     * Delete an allocation by ID.
     * @param allocationId The ID of the allocation to delete
     * @param assetId The asset ID (for history tracking)
     * @param goalId The goal ID (for history tracking)
     */
    suspend operator fun invoke(
        allocationId: String,
        assetId: String? = null,
        goalId: String? = null
    ): Result<Unit> = runCatching {
        // Create deletion snapshot if asset/goal IDs are provided
        if (assetId != null && goalId != null) {
            allocationHistoryService.createDeletionSnapshot(assetId, goalId)
        }
        allocationRepository.deleteAllocation(allocationId)
    }

    /**
     * Delete all allocations for a goal.
     */
    suspend fun deleteForGoal(goalId: String): Result<Unit> = runCatching {
        // Get allocations before deleting to create history snapshots
        val allocations = allocationRepository.getAllocationsForGoal(goalId)
        for (allocation in allocations) {
            allocationHistoryService.createDeletionSnapshot(allocation.assetId, allocation.goalId)
        }
        allocationRepository.deleteAllocationsForGoal(goalId)
    }

    /**
     * Delete all allocations for an asset.
     */
    suspend fun deleteForAsset(assetId: String): Result<Unit> = runCatching {
        // Get allocations before deleting to create history snapshots
        val allocations = allocationRepository.getAllocationsForAsset(assetId)
        for (allocation in allocations) {
            allocationHistoryService.createDeletionSnapshot(allocation.assetId, allocation.goalId)
        }
        allocationRepository.deleteAllocationsForAsset(assetId)
    }
}
