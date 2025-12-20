package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetAllocationEntity
import com.xax.CryptoSavingsTracker.domain.model.Allocation

/**
 * Mapper for converting between AssetAllocationEntity and Allocation domain model.
 */
object AllocationMapper {

    fun AssetAllocationEntity.toDomain(): Allocation = Allocation(
        id = id,
        assetId = assetId,
        goalId = goalId,
        amount = amount,
        createdAt = createdAtUtcMillis,
        lastModifiedAt = lastModifiedAtUtcMillis
    )

    fun List<AssetAllocationEntity>.toDomainList(): List<Allocation> = map { it.toDomain() }

    fun Allocation.toEntity(): AssetAllocationEntity = AssetAllocationEntity(
        id = id,
        assetId = assetId,
        goalId = goalId,
        amount = amount,
        createdAtUtcMillis = createdAt,
        lastModifiedAtUtcMillis = lastModifiedAt
    )
}
