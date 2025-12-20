package com.xax.CryptoSavingsTracker.domain.usecase.asset

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import javax.inject.Inject

/**
 * Use case for updating an existing asset
 */
class UpdateAssetUseCase @Inject constructor(
    private val repository: AssetRepository
) {
    /**
     * Update an asset with new values
     */
    suspend operator fun invoke(asset: Asset): Result<Asset> {
        // Validation
        if (asset.currency.isBlank()) {
            return Result.failure(IllegalArgumentException("Currency cannot be empty"))
        }

        // Check for duplicate address if changed
        if (asset.address != null) {
            val existingAsset = repository.getAssetByAddress(asset.address)
            if (existingAsset != null && existingAsset.id != asset.id) {
                return Result.failure(IllegalArgumentException("An asset with this address already exists"))
            }
        }

        val updatedAsset = asset.copy(updatedAt = System.currentTimeMillis())

        return try {
            repository.updateAsset(updatedAsset)
            Result.success(updatedAsset)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
