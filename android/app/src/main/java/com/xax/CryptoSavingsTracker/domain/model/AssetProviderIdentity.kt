package com.xax.CryptoSavingsTracker.domain.model

internal data class AssetProviderIdentity(
    val currency: String,
    val address: String?,
    val chainId: String?
)

internal fun Asset.providerIdentity(): AssetProviderIdentity {
    val normalizedChainId = chainId
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
        ?.let(OnChainAssetRouteCatalog::normalizeChainId)
    val normalizedAddress = address
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
        ?.let { OnChainAddressIdentityV1.canonicalize(normalizedChainId, it) }
    return AssetProviderIdentity(
        currency = OnChainAssetRouteCatalog.normalizeCurrencyIdentifier(
            normalizedChainId,
            currency
        ),
        address = normalizedAddress,
        chainId = normalizedChainId
    )
}

internal fun Asset.hasSameProviderIdentityAs(other: Asset): Boolean {
    return id == other.id && providerIdentity() == other.providerIdentity()
}
