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
    const val LITECOIN = "litecoin"
    const val BITCOIN_CASH = "bitcoin-cash"
    const val DOGECOIN = "dogecoin"
    const val XRP = "xrp"
    const val TRON = "tron"
    const val CARDANO = "cardano"

    fun displayName(chainId: String?): String = when (chainId) {
        ETHEREUM -> "Ethereum"
        BITCOIN -> "Bitcoin"
        POLYGON -> "Polygon"
        SOLANA -> "Solana"
        ARBITRUM -> "Arbitrum"
        OPTIMISM -> "Optimism"
        BASE -> "Base"
        BSC -> "BNB Chain"
        LITECOIN -> "Litecoin"
        BITCOIN_CASH -> "Bitcoin Cash"
        DOGECOIN -> "Dogecoin"
        XRP -> "XRP Ledger"
        TRON -> "Tron"
        CARDANO -> "Cardano"
        else -> chainId ?: "Unknown"
    }

    val allChains = listOf(
        ETHEREUM, BITCOIN, POLYGON, SOLANA, ARBITRUM, OPTIMISM, BASE, BSC,
        LITECOIN, BITCOIN_CASH, DOGECOIN, XRP, TRON, CARDANO
    )

    /**
     * Predict the blockchain network based on currency symbol.
     * Returns the chain ID if a match is found, null otherwise.
     * Matches iOS predictChain(for:) behavior.
     */
    fun predictChain(symbol: String): String? {
        val upperSymbol = symbol.uppercase()

        // Direct matches for native currencies
        return when (upperSymbol) {
            // Native chain currencies
            "BTC" -> BITCOIN
            "ETH" -> ETHEREUM
            "SOL" -> SOLANA
            "MATIC" -> POLYGON
            "BNB" -> BSC
            "LTC" -> LITECOIN
            "BCH" -> BITCOIN_CASH
            "DOGE" -> DOGECOIN
            "XRP" -> XRP
            "TRX" -> TRON
            "ADA" -> CARDANO

            // Common ERC-20 tokens (Ethereum)
            "USDT", "USDC", "DAI", "WETH", "UNI", "LINK", "AAVE", "SHIB", "APE", "CRV", "MKR", "SNX", "COMP", "YFI", "SUSHI" -> ETHEREUM

            // BSC tokens
            "BUSD", "CAKE", "BAKE" -> BSC

            // Polygon tokens
            "WMATIC", "QUICK" -> POLYGON

            else -> null
        }
    }
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
