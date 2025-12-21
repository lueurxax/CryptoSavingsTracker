package com.xax.CryptoSavingsTracker.domain.usecase.allocation

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import kotlinx.coroutines.flow.first
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.abs

/**
 * Data class representing the allocation status of an asset.
 * Matches iOS behavior for detecting over-allocation.
 */
data class AssetAllocationStatus(
    val asset: Asset,
    val totalBalance: Double,           // Manual balance of the asset
    val totalAllocated: Double,         // Sum of all allocations
    val allocationDelta: Double,        // Balance - allocated (can be negative)
    val unallocatedAmount: Double,      // Remaining unallocated (never negative)
    val isFullyAllocated: Boolean,      // When delta is near zero
    val isOverAllocated: Boolean        // When delta is negative
) {
    val overAllocatedAmount: Double
        get() = if (isOverAllocated) abs(allocationDelta) else 0.0
}

/**
 * Service for validating allocations and detecting over-allocation.
 * Matches iOS behavior for allocation validation.
 */
@Singleton
class AllocationValidationService @Inject constructor(
    private val allocationRepository: AllocationRepository,
    private val transactionRepository: TransactionRepository,
    private val assetRepository: AssetRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository
) {
    companion object {
        private const val EPSILON = 0.0000001
    }

    /**
     * Get allocation status for a specific asset.
     */
    suspend fun getAssetAllocationStatus(assetId: String): AssetAllocationStatus? {
        val asset = assetRepository.getAssetById(assetId) ?: return null
        return calculateAssetAllocationStatus(asset)
    }

    /**
     * Get allocation status for all assets.
     */
    suspend fun getAllAssetAllocationStatuses(): List<AssetAllocationStatus> {
        val assets = assetRepository.getAllAssets().first()
        return assets.map { calculateAssetAllocationStatus(it) }
    }

    /**
     * Get only over-allocated assets.
     */
    suspend fun getOverAllocatedAssets(): List<AssetAllocationStatus> {
        return getAllAssetAllocationStatuses().filter { it.isOverAllocated }
    }

    /**
     * Check if any asset is over-allocated.
     */
    suspend fun hasOverAllocatedAssets(): Boolean {
        return getOverAllocatedAssets().isNotEmpty()
    }

    /**
     * Validate if an allocation amount is valid for an asset.
     * Returns error message if invalid, null if valid.
     */
    suspend fun validateAllocation(
        assetId: String,
        goalId: String,
        amount: Double,
        excludeAllocationId: String? = null
    ): String? {
        if (amount <= 0) {
            return "Allocation amount must be positive"
        }

        val asset = assetRepository.getAssetById(assetId)
            ?: return "Asset not found"
        val balance = bestKnownBalance(asset)
        val allocations = allocationRepository.getAllocationsForAsset(assetId)

        // Sum allocations, excluding the one being updated if specified
        val existingAllocated = allocations
            .filter { it.id != excludeAllocationId }
            .sumOf { it.amount }

        val availableBalance = balance - existingAllocated

        if (amount > availableBalance + EPSILON) {
            val pattern = if (asset.isCryptoAsset) "%,.6f" else "%,.2f"
            val formattedAvailable = String.format(Locale.getDefault(), pattern, availableBalance)
            return "Amount exceeds available balance ($formattedAvailable)"
        }

        // Check if allocation already exists for this asset-goal pair (for new allocations)
        if (excludeAllocationId == null) {
            val existingForGoal = allocationRepository.getAllocationByAssetAndGoal(assetId, goalId)
            if (existingForGoal != null) {
                return "Allocation already exists for this asset and goal"
            }
        }

        return null
    }

    /**
     * Calculate allocation status for an asset.
     */
    private suspend fun calculateAssetAllocationStatus(asset: Asset): AssetAllocationStatus {
        val totalBalance = bestKnownBalance(asset)
        val allocations = allocationRepository.getAllocationsForAsset(asset.id)
        val totalAllocated = allocations.sumOf { it.amount }

        val allocationDelta = totalBalance - totalAllocated
        val unallocatedAmount = maxOf(0.0, allocationDelta)
        val isFullyAllocated = abs(allocationDelta) <= EPSILON
        val isOverAllocated = allocationDelta < -EPSILON

        return AssetAllocationStatus(
            asset = asset,
            totalBalance = totalBalance,
            totalAllocated = totalAllocated,
            allocationDelta = allocationDelta,
            unallocatedAmount = unallocatedAmount,
            isFullyAllocated = isFullyAllocated,
            isOverAllocated = isOverAllocated
        )
    }

    private suspend fun bestKnownBalance(asset: Asset): Double {
        val manual = transactionRepository.getManualBalanceForAsset(asset.id)
        val hasOnChain = asset.isCryptoAsset && asset.address != null && asset.chainId != null
        if (!hasOnChain) return manual

        val onChain = runCatching {
            onChainBalanceRepository.getBalance(asset, forceRefresh = false).getOrNull()?.balance ?: 0.0
        }.getOrElse { 0.0 }

        return manual + onChain
    }
}
