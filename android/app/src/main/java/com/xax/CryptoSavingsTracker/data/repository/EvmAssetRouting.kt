package com.xax.CryptoSavingsTracker.data.repository

import com.xax.CryptoSavingsTracker.domain.model.OnChainAssetRouteCatalog

internal data class EvmAssetRoute(
    val canonicalChainId: String,
    val tatumChain: String,
    val tokenContracts: Set<String>
) {
    val isNative: Boolean
        get() = tokenContracts.isEmpty()

    val transactionType: String
        get() = if (isNative) "native" else "fungible"
}

/**
 * Single source of truth for the EVM chains and assets that this app can identify unambiguously.
 */
internal object EvmAssetRouting {
    val chainIds: Set<String> = OnChainAssetRouteCatalog.evmChainIds

    fun resolve(chainId: String, currencyOrContract: String): EvmAssetRoute {
        val normalizedChainId = OnChainAssetRouteCatalog.normalizeChainId(chainId)
        val tatumChain = when (normalizedChainId) {
            "ethereum" -> "ethereum-mainnet"
            "polygon" -> "polygon-mainnet"
            "bsc" -> "bsc-mainnet"
            "arbitrum" -> "arb-one-mainnet"
            "optimism" -> "optimism-mainnet"
            "base" -> "base-mainnet"
            "avax" -> "avax-mainnet"
            else -> throw IllegalArgumentException("Unsupported EVM chain: $chainId")
        }

        val route = OnChainAssetRouteCatalog.resolveEvm(
            chainId = normalizedChainId,
            currencyOrContract = currencyOrContract
        )
        return EvmAssetRoute(
            canonicalChainId = normalizedChainId,
            tatumChain = tatumChain,
            tokenContracts = route.tokenContracts
        )
    }
}
