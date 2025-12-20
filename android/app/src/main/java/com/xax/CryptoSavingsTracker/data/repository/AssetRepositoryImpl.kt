package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.dao.AssetDao
import com.xax.CryptoSavingsTracker.data.repository.AssetMapper.toDomain
import com.xax.CryptoSavingsTracker.data.repository.AssetMapper.toDomainList
import com.xax.CryptoSavingsTracker.data.repository.AssetMapper.toEntity
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Implementation of AssetRepository using Room database.
 */
@Singleton
class AssetRepositoryImpl @Inject constructor(
    private val assetDao: AssetDao
) : AssetRepository {

    override fun getAllAssets(): Flow<List<Asset>> {
        return assetDao.getAllAssets().map { entities ->
            entities.toDomainList()
        }
    }

    override fun getAssetsByCurrency(currency: String): Flow<List<Asset>> {
        return assetDao.getAssetsByCurrency(currency).map { entities ->
            entities.toDomainList()
        }
    }

    override suspend fun getAssetById(id: String): Asset? {
        return assetDao.getAssetByIdOnce(id)?.toDomain()
    }

    override fun getAssetByIdFlow(id: String): Flow<Asset?> {
        return assetDao.getAssetById(id).map { entity ->
            entity?.toDomain()
        }
    }

    override suspend fun getAssetByAddress(address: String): Asset? {
        return assetDao.getAssetByAddress(address)?.toDomain()
    }

    override suspend fun insertAsset(asset: Asset) {
        assetDao.insert(asset.toEntity())
    }

    override suspend fun updateAsset(asset: Asset) {
        assetDao.update(asset.toEntity())
    }

    override suspend fun deleteAsset(id: String) {
        assetDao.deleteById(id)
    }

    override suspend fun deleteAsset(asset: Asset) {
        assetDao.delete(asset.toEntity())
    }

    override suspend fun getAssetCount(): Int {
        return assetDao.getAssetCount()
    }
}
