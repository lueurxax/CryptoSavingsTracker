package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetEntity
import com.xax.CryptoSavingsTracker.domain.model.Asset

/**
 * Mapper functions to convert between AssetEntity (data layer) and Asset (domain layer)
 */
object AssetMapper {

    fun AssetEntity.toDomain(): Asset {
        return Asset(
            id = id,
            currency = currency,
            address = address,
            chainId = chainId,
            createdAt = createdAtUtcMillis,
            updatedAt = lastModifiedAtUtcMillis
        )
    }

    fun Asset.toEntity(): AssetEntity {
        return AssetEntity(
            id = id,
            currency = currency,
            address = address,
            chainId = chainId,
            createdAtUtcMillis = createdAt,
            lastModifiedAtUtcMillis = updatedAt
        )
    }

    fun List<AssetEntity>.toDomainList(): List<Asset> {
        return map { it.toDomain() }
    }
}
