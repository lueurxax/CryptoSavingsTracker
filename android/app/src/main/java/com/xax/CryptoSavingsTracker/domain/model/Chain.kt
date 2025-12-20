package com.xax.CryptoSavingsTracker.domain.model

/**
 * Represents a blockchain/network supported by the app.
 */
data class Chain(
    val id: String,
    val name: String,
    val nativeCurrencySymbol: String,
    val chainType: ChainType,
    val v4ApiName: String? = null // Name used in v4 API, if supported
) {
    val supportsV4Api: Boolean
        get() = v4ApiName != null
}

/**
 * Type of blockchain.
 */
enum class ChainType {
    EVM,    // Ethereum-compatible chains
    UTXO,   // Bitcoin-like chains (UTXO model)
    OTHER   // Other chains (XRP, TRX, ADA, SOL, etc.)
}

/**
 * Service for managing chain metadata.
 */
object ChainService {

    private val chains = listOf(
        // EVM Chains (support v4 API)
        Chain("ETH", "Ethereum", "ETH", ChainType.EVM, "ethereum-mainnet"),
        Chain("BSC", "BNB Smart Chain", "BNB", ChainType.EVM, "bsc-mainnet"),
        Chain("POLYGON", "Polygon", "MATIC", ChainType.EVM, "polygon-mainnet"),
        Chain("AVAX", "Avalanche", "AVAX", ChainType.EVM, "avalanche-c-mainnet"),
        Chain("FTM", "Fantom", "FTM", ChainType.EVM, "fantom-mainnet"),
        Chain("ARBITRUM", "Arbitrum", "ETH", ChainType.EVM, "arbitrum-mainnet"),
        Chain("OPTIMISM", "Optimism", "ETH", ChainType.EVM, "optimism-mainnet"),
        Chain("BASE", "Base", "ETH", ChainType.EVM, "base-mainnet"),

        // UTXO Chains
        Chain("BTC", "Bitcoin", "BTC", ChainType.UTXO),
        Chain("LTC", "Litecoin", "LTC", ChainType.UTXO),
        Chain("BCH", "Bitcoin Cash", "BCH", ChainType.UTXO),
        Chain("DOGE", "Dogecoin", "DOGE", ChainType.UTXO),

        // Other Chains
        Chain("XRP", "XRP Ledger", "XRP", ChainType.OTHER),
        Chain("TRX", "Tron", "TRX", ChainType.OTHER),
        Chain("ADA", "Cardano", "ADA", ChainType.OTHER),
        Chain("SOL", "Solana", "SOL", ChainType.OTHER)
    )

    private val chainMap = chains.associateBy { it.id.uppercase() }

    /**
     * Get chain by ID.
     */
    fun getChain(chainId: String): Chain? {
        return chainMap[chainId.uppercase()]
    }

    /**
     * Get all supported chains.
     */
    fun getAllChains(): List<Chain> = chains

    /**
     * Get v4 API chain name for a chain ID.
     */
    fun getV4ChainName(chainId: String): String? {
        return chainMap[chainId.uppercase()]?.v4ApiName
    }

    /**
     * Check if chain supports v4 API.
     */
    fun supportsV4Api(chainId: String): Boolean {
        return chainMap[chainId.uppercase()]?.supportsV4Api == true
    }

    /**
     * Check if a symbol is the native currency for a chain.
     */
    fun isNativeCurrency(chainId: String, symbol: String): Boolean {
        val chain = chainMap[chainId.uppercase()] ?: return false
        return chain.nativeCurrencySymbol.equals(symbol, ignoreCase = true)
    }
}
