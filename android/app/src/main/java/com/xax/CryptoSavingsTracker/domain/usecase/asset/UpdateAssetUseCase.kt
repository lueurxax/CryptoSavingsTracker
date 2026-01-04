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
        val normalizedAsset = asset.copy(
            address = asset.address?.trim()?.takeIf { it.isNotBlank() },
            chainId = asset.chainId?.trim()?.takeIf { it.isNotBlank() }
        )
        // Validation
        if (normalizedAsset.currency.isBlank()) {
            return Result.failure(IllegalArgumentException("Currency cannot be empty"))
        }

        // Check for duplicate address if changed
        if (normalizedAsset.address != null) {
            val existingAsset = repository.getAssetByAddress(normalizedAsset.address)
            if (existingAsset != null && existingAsset.id != normalizedAsset.id) {
                return Result.failure(IllegalArgumentException("An asset with this address already exists"))
            }
        }

        val updatedAsset = normalizedAsset.copy(updatedAt = System.currentTimeMillis())

        return try {
            repository.updateAsset(updatedAsset)
            Result.success(updatedAsset)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
