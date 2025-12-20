package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.Asset
import kotlinx.coroutines.flow.Flow

/**
 * Repository interface for Asset operations.
 */
interface AssetRepository {
    /**
     * Get all assets as a Flow for reactive updates
     */
    fun getAllAssets(): Flow<List<Asset>>

    /**
     * Get assets by currency
     */
    fun getAssetsByCurrency(currency: String): Flow<List<Asset>>

    /**
     * Get a single asset by ID
     */
    suspend fun getAssetById(id: String): Asset?

    /**
     * Get a single asset by ID as a Flow
     */
    fun getAssetByIdFlow(id: String): Flow<Asset?>

    /**
     * Get asset by wallet address
     */
    suspend fun getAssetByAddress(address: String): Asset?

    /**
     * Insert a new asset
     */
    suspend fun insertAsset(asset: Asset)

    /**
     * Update an existing asset
     */
    suspend fun updateAsset(asset: Asset)

    /**
     * Delete an asset by ID
     */
    suspend fun deleteAsset(id: String)

    /**
     * Delete an asset
     */
    suspend fun deleteAsset(asset: Asset)

    /**
     * Get count of assets
     */
    suspend fun getAssetCount(): Int
}
