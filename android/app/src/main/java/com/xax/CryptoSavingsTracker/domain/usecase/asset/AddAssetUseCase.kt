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
        val normalized = runCatching {
            AddressedAssetRoutePolicy.normalize(currency, address, chainId)
        }.getOrElse { return Result.failure(it) }

        if (normalized.address != null) {
            val existingAsset = repository.getAssetByOnChainIdentity(
                address = normalized.address,
                chainId = checkNotNull(normalized.chainId),
                currency = normalized.currency
            )
            if (existingAsset != null) {
                return Result.failure(
                    IllegalArgumentException(
                        "This wallet is already tracked for ${normalized.currency} on ${normalized.chainId}"
                    )
                )
            }
        }

        val now = System.currentTimeMillis()
        val asset = Asset(
            id = UUID.randomUUID().toString(),
            currency = normalized.currency,
            address = normalized.address,
            chainId = normalized.chainId,
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
