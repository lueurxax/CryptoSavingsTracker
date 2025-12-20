package com.xax.CryptoSavingsTracker.domain.usecase.asset

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

/**
 * Use case for retrieving assets
 */
class GetAssetsUseCase @Inject constructor(
    private val repository: AssetRepository
) {
    /**
     * Get all assets
     */
    operator fun invoke(): Flow<List<Asset>> {
        return repository.getAllAssets()
    }

    /**
     * Get assets by currency
     */
    fun byCurrency(currency: String): Flow<List<Asset>> {
        return repository.getAssetsByCurrency(currency)
    }
}
