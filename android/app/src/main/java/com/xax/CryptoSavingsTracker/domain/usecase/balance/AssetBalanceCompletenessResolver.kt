package com.xax.CryptoSavingsTracker.domain.usecase.balance

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainAddressIdentityV1
import com.xax.CryptoSavingsTracker.domain.model.OnChainAssetRouteCatalog
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository

sealed interface AssetBalanceCompleteness {
    val manualBalance: Double

    data class Complete(
        override val manualBalance: Double,
        val onChainBalance: Double?,
        val totalBalance: Double
    ) : AssetBalanceCompleteness

    data class Unavailable(
        override val manualBalance: Double,
        val issue: String
    ) : AssetBalanceCompleteness

    val totalBalanceOrNull: Double?
        get() = (this as? Complete)?.totalBalance

    val issueOrNull: String?
        get() = (this as? Unavailable)?.issue

    fun requireTotalBalance(): Double {
        return totalBalanceOrNull ?: throw AssetBalanceUnavailableException(
            issueOrNull ?: "Asset balance is unavailable. Refresh the wallet balance and retry."
        )
    }
}

class AssetBalanceUnavailableException(message: String) : IllegalStateException(message)

/**
 * Resolves whether an asset balance is safe to use for a financial decision.
 *
 * Addressed assets are complete only when their provider snapshot is fresh, finite, non-negative,
 * and belongs to the requested persistence identity. A provider failure never promotes the known
 * manual portion to an authoritative total.
 */
object AssetBalanceCompletenessResolver {
    suspend fun resolve(
        asset: Asset,
        manualBalance: Double,
        repository: OnChainBalanceRepository,
        forceRefresh: Boolean = false,
        nowMillis: Long? = null
    ): AssetBalanceCompleteness {
        if (!manualBalance.isFinite()) {
            return unavailable(asset, manualBalance, "has an invalid manual balance")
        }

        val address = asset.address?.trim().orEmpty()
        val chainId = asset.chainId?.trim().orEmpty()
        if (address.isEmpty()) {
            return AssetBalanceCompleteness.Complete(
                manualBalance = manualBalance,
                onChainBalance = null,
                totalBalance = manualBalance
            )
        }
        if (chainId.isEmpty()) {
            return unavailable(asset, manualBalance, "has incomplete wallet configuration")
        }

        val providerBalance = runCatching {
            repository.getBalance(asset, forceRefresh = forceRefresh).getOrThrow()
        }.getOrElse {
            return unavailable(asset, manualBalance, "is unavailable")
        }

        return resolveSnapshot(
            asset = asset,
            manualBalance = manualBalance,
            providerBalance = providerBalance,
            nowMillis = nowMillis
        )
    }

    fun resolveSnapshot(
        asset: Asset,
        manualBalance: Double,
        providerBalance: OnChainBalance?,
        nowMillis: Long? = null
    ): AssetBalanceCompleteness {
        if (!manualBalance.isFinite()) {
            return unavailable(asset, manualBalance, "has an invalid manual balance")
        }

        val address = asset.address?.trim().orEmpty()
        val chainId = asset.chainId?.trim().orEmpty()
        if (address.isEmpty()) {
            return AssetBalanceCompleteness.Complete(
                manualBalance = manualBalance,
                onChainBalance = null,
                totalBalance = manualBalance
            )
        }
        if (chainId.isEmpty()) {
            return unavailable(asset, manualBalance, "has incomplete wallet configuration")
        }
        if (providerBalance == null) {
            return unavailable(asset, manualBalance, "is unavailable")
        }
        if (providerBalance.isStale) {
            return unavailable(asset, manualBalance, "is unavailable or stale")
        }
        val validationNowMillis = nowMillis ?: System.currentTimeMillis()
        if (!providerBalance.isValidFor(asset = asset, nowMillis = validationNowMillis)) {
            return unavailable(asset, manualBalance, "is invalid")
        }

        val totalBalance = manualBalance + providerBalance.balance
        if (!totalBalance.isFinite()) {
            return unavailable(asset, manualBalance, "is invalid")
        }

        return AssetBalanceCompleteness.Complete(
            manualBalance = manualBalance,
            onChainBalance = providerBalance.balance,
            totalBalance = totalBalance
        )
    }

    private fun OnChainBalance.isValidFor(asset: Asset, nowMillis: Long): Boolean {
        val expectedChainId = OnChainAssetRouteCatalog.normalizeChainId(checkNotNull(asset.chainId))
        val actualChainId = OnChainAssetRouteCatalog.normalizeChainId(chainId)
        val expectedAddress = OnChainAddressIdentityV1.canonicalize(expectedChainId, checkNotNull(asset.address))
        val actualAddress = OnChainAddressIdentityV1.canonicalize(actualChainId, address)
        val expectedCurrency = OnChainAssetRouteCatalog.normalizeCurrencyIdentifier(
            expectedChainId,
            asset.currency
        )
        val actualCurrency = OnChainAssetRouteCatalog.normalizeCurrencyIdentifier(
            actualChainId,
            currency
        )

        return assetId == asset.id &&
            actualChainId == expectedChainId &&
            actualAddress == expectedAddress &&
            actualCurrency == expectedCurrency &&
            balance.isFinite() &&
            balance >= 0.0 &&
            fetchedAtMillis in 1L..nowMillis
    }

    private fun unavailable(
        asset: Asset,
        manualBalance: Double,
        reason: String
    ): AssetBalanceCompleteness.Unavailable {
        return AssetBalanceCompleteness.Unavailable(
            manualBalance = manualBalance,
            issue = "On-chain balance for ${asset.currency} $reason. Refresh the wallet balance and retry."
        )
    }
}
