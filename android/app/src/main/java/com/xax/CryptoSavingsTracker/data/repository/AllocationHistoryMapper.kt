package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.entity.AllocationHistoryEntity
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory

/**
 * Mapper for converting between AllocationHistoryEntity and AllocationHistory domain model.
 */
object AllocationHistoryMapper {

    fun AllocationHistoryEntity.toDomain(): AllocationHistory = AllocationHistory(
        id = id,
        assetId = assetId,
        goalId = goalId,
        amount = amount,
        monthLabel = monthLabel,
        timestamp = timestampUtcMillis,
        createdAt = createdAtUtcMillis
    )

    fun List<AllocationHistoryEntity>.toDomainList(): List<AllocationHistory> = map { it.toDomain() }

    fun AllocationHistory.toEntity(): AllocationHistoryEntity = AllocationHistoryEntity(
        id = id,
        assetId = assetId,
        goalId = goalId,
        amount = amount,
        monthLabel = monthLabel,
        timestampUtcMillis = timestamp,
        createdAtUtcMillis = createdAt
    )
}
