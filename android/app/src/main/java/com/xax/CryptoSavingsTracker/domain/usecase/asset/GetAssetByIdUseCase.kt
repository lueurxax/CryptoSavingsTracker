package com.xax.CryptoSavingsTracker.domain.usecase.asset

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

/**
 * Use case for retrieving a single asset by ID
 */
class GetAssetByIdUseCase @Inject constructor(
    private val repository: AssetRepository
) {
    /**
     * Get asset by ID (suspend)
     */
    suspend operator fun invoke(id: String): Asset? {
        return repository.getAssetById(id)
    }

    /**
     * Get asset by ID as Flow for reactive updates
     */
    fun asFlow(id: String): Flow<Asset?> {
        return repository.getAssetByIdFlow(id)
    }

    /**
     * Get asset by wallet address
     */
    suspend fun byAddress(address: String): Asset? {
        return repository.getAssetByAddress(address)
    }
}
