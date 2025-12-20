package com.xax.CryptoSavingsTracker.domain.usecase.asset

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import javax.inject.Inject

/**
 * Use case for deleting an asset
 */
class DeleteAssetUseCase @Inject constructor(
    private val repository: AssetRepository
) {
    /**
     * Delete an asset by ID
     */
    suspend operator fun invoke(assetId: String): Result<Unit> {
        return try {
            repository.deleteAsset(assetId)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Delete an asset
     */
    suspend fun delete(asset: Asset): Result<Unit> {
        return try {
            repository.deleteAsset(asset)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
