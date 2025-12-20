package com.xax.CryptoSavingsTracker.domain.usecase.asset

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import java.util.UUID
import javax.inject.Inject

/**
 * Use case for adding a new asset
 */
class AddAssetUseCase @Inject constructor(
    private val repository: AssetRepository
) {
    /**
     * Add a new asset with the provided parameters
     */
    suspend operator fun invoke(
        currency: String,
        address: String? = null,
        chainId: String? = null
    ): Result<Asset> {
        // Validation
        if (currency.isBlank()) {
            return Result.failure(IllegalArgumentException("Currency cannot be empty"))
        }

        // Check for duplicate address if provided
        if (address != null) {
            val existingAsset = repository.getAssetByAddress(address)
            if (existingAsset != null) {
                return Result.failure(IllegalArgumentException("An asset with this address already exists"))
            }
        }

        val now = System.currentTimeMillis()
        val asset = Asset(
            id = UUID.randomUUID().toString(),
            currency = currency.uppercase().trim(),
            address = address?.trim(),
            chainId = chainId,
            createdAt = now,
            updatedAt = now
        )

        return try {
            repository.insertAsset(asset)
            Result.success(asset)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
