package com.xax.CryptoSavingsTracker.domain.model

/**
 * Immutable provider-facing identity of an addressed asset.
 */
internal data class OnChainAssetProviderIdentityV1(
    val assetId: String,
    val currency: String,
    val chainId: String,
    val address: String
) {
    companion object {
        fun from(asset: Asset): OnChainAssetProviderIdentityV1 {
            val chainId = asset.chainId
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?.let(OnChainAssetRouteCatalog::normalizeChainId)
                ?: error("Asset provider identity has no network")
            val address = asset.address
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?: error("Asset provider identity has no wallet address")
            return OnChainAssetProviderIdentityV1(
                assetId = asset.id,
                currency = OnChainAssetRouteCatalog.normalizeCurrencyIdentifier(
                    chainId,
                    asset.currency
                ),
                chainId = chainId,
                address = OnChainAddressIdentityV1.canonicalize(chainId, address)
            )
        }
    }
}
