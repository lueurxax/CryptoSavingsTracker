package com.xax.CryptoSavingsTracker.domain.usecase.asset

import com.xax.CryptoSavingsTracker.domain.model.OnChainAssetRouteCatalog
import com.xax.CryptoSavingsTracker.domain.model.OnChainAddressIdentityV1

internal data class NormalizedAssetFields(
    val currency: String,
    val address: String?,
    val chainId: String?
)

/**
 * Persistence-boundary normalization shared by add and update.
 */
internal object AddressedAssetRoutePolicy {
    fun normalize(
        currency: String,
        address: String?,
        chainId: String?
    ): NormalizedAssetFields {
        val normalizedChainId = chainId
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.let(OnChainAssetRouteCatalog::normalizeChainId)
        val normalizedCurrency = OnChainAssetRouteCatalog.normalizeCurrencyIdentifier(
            normalizedChainId,
            currency
        )
        require(normalizedCurrency.isNotEmpty()) { "Currency cannot be empty" }
        val trimmedAddress = address?.trim()?.takeIf { it.isNotEmpty() }
        val normalizedAddress = trimmedAddress?.let { candidate ->
            OnChainAddressIdentityV1.canonicalize(normalizedChainId, candidate)
        }

        if (normalizedAddress != null) {
            val route = normalizedChainId
            require(route != null) {
                "automatic balance tracking requires a network; remove the wallet address to track it manually"
            }
            runCatching {
                OnChainAssetRouteCatalog.requireAddressedRoute(route, normalizedCurrency)
            }.getOrElse {
                throw IllegalArgumentException(
                    "automatic balance tracking is unavailable for $normalizedCurrency on $route; " +
                        "remove the wallet address to track it manually",
                    it
                )
            }
        }

        return NormalizedAssetFields(
            currency = normalizedCurrency,
            address = normalizedAddress,
            chainId = normalizedChainId
        )
    }
}
