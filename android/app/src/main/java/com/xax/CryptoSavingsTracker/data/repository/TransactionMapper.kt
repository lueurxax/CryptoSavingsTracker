package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.data.local.database.entity.TransactionEntity
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource

/**
 * Mapper functions to convert between TransactionEntity (data layer) and Transaction (domain layer)
 */
object TransactionMapper {

    fun TransactionEntity.toDomain(): Transaction {
        return Transaction(
            id = id,
            assetId = assetId,
            amount = amount,
            dateMillis = dateUtcMillis,
            source = TransactionSource.fromString(source),
            externalId = externalId,
            counterparty = counterparty,
            comment = comment,
            createdAt = createdAtUtcMillis
        )
    }

    fun Transaction.toEntity(): TransactionEntity {
        return TransactionEntity(
            id = id,
            assetId = assetId,
            amount = amount,
            dateUtcMillis = dateMillis,
            source = source.name.lowercase(),
            externalId = externalId,
            counterparty = counterparty,
            comment = comment,
            createdAtUtcMillis = createdAt
        )
    }

    fun List<TransactionEntity>.toDomainList(): List<Transaction> {
        return map { it.toDomain() }
    }
}
