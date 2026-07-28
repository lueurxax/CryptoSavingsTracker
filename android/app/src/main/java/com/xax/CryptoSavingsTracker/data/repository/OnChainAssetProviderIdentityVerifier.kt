package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainAssetProviderIdentityV1
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Re-reads an addressed asset at the persistence boundary so a suspended provider request
 * cannot commit against an address, network, or currency that has since changed.
 */
@Singleton
class OnChainAssetProviderIdentityVerifier @Inject constructor(
    private val assetRepository: AssetRepository
) {
    suspend fun assertUnchanged(expectedAsset: Asset) {
        val currentAsset = checkNotNull(assetRepository.getAssetById(expectedAsset.id)) {
            "Asset provider identity changed while provider data was loading"
        }
        check(
            OnChainAssetProviderIdentityV1.from(currentAsset) ==
                OnChainAssetProviderIdentityV1.from(expectedAsset)
        ) {
            "Asset provider identity changed while provider data was loading"
        }
    }
}
