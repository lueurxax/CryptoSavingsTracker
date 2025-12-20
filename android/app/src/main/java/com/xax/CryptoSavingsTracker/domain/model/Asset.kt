package com.xax.CryptoSavingsTracker.domain.model

/**
 * Domain model representing a cryptocurrency wallet or fiat account.
 */
data class Asset(
    val id: String,
    val currency: String,
    val address: String?,
    val chainId: String?,
    val createdAt: Long,
    val updatedAt: Long
) {
    /**
     * Check if this is a crypto asset (has an address)
     */
    val isCryptoAsset: Boolean
        get() = address != null

    /**
     * Get display name for the asset
     */
    fun displayName(): String {
        return if (address != null) {
            "${currency} (${address.take(6)}...${address.takeLast(4)})"
        } else {
            currency
        }
    }

    /**
     * Get shortened address for display
     */
    fun shortAddress(): String? {
        return address?.let {
            if (it.length > 12) {
                "${it.take(6)}...${it.takeLast(4)}"
            } else {
                it
            }
        }
    }
}

/**
 * Common cryptocurrency chains
 */
object ChainIds {
    const val ETHEREUM = "ethereum"
    const val BITCOIN = "bitcoin"
    const val POLYGON = "polygon"
    const val SOLANA = "solana"
    const val ARBITRUM = "arbitrum"
    const val OPTIMISM = "optimism"
    const val BASE = "base"
    const val BSC = "bsc"

    fun displayName(chainId: String?): String = when (chainId) {
        ETHEREUM -> "Ethereum"
        BITCOIN -> "Bitcoin"
        POLYGON -> "Polygon"
        SOLANA -> "Solana"
        ARBITRUM -> "Arbitrum"
        OPTIMISM -> "Optimism"
        BASE -> "Base"
        BSC -> "BNB Chain"
        else -> chainId ?: "Unknown"
    }

    val allChains = listOf(
        ETHEREUM, BITCOIN, POLYGON, SOLANA, ARBITRUM, OPTIMISM, BASE, BSC
    )
}

/**
 * Common cryptocurrencies
 */
object Cryptocurrencies {
    val common = listOf(
        "BTC" to "Bitcoin",
        "ETH" to "Ethereum",
        "USDT" to "Tether",
        "USDC" to "USD Coin",
        "SOL" to "Solana",
        "MATIC" to "Polygon",
        "DAI" to "Dai",
        "LINK" to "Chainlink",
        "UNI" to "Uniswap",
        "AAVE" to "Aave"
    )
}
