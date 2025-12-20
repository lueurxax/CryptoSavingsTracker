package com.xax.CryptoSavingsTracker.data.remote.api

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * Tatum API interface for fetching blockchain balances.
 * Supports both v3 (legacy) and v4 API endpoints.
 */
interface TatumApi {

    // ==================== V4 Data API ====================

    /**
     * Get wallet portfolio data (v4 API).
     * Used for EVM chains with native and fungible token balances.
     */
    @GET("v4/data/wallet/portfolio")
    suspend fun getWalletPortfolio(
        @Query("chain") chain: String,
        @Query("addresses") addresses: String,
        @Query("tokenTypes") tokenTypes: String
    ): TatumV4PortfolioResponse

    // ==================== V3 Legacy API ====================

    /**
     * Get Bitcoin address balance.
     */
    @GET("v3/bitcoin/address/balance/{address}")
    suspend fun getBitcoinBalance(@Path("address") address: String): TatumUTXOBalance

    /**
     * Get Litecoin address balance.
     */
    @GET("v3/litecoin/address/balance/{address}")
    suspend fun getLitecoinBalance(@Path("address") address: String): TatumUTXOBalance

    /**
     * Get Bitcoin Cash address balance.
     */
    @GET("v3/bcash/address/balance/{address}")
    suspend fun getBitcoinCashBalance(@Path("address") address: String): TatumUTXOBalance

    /**
     * Get Dogecoin address balance.
     */
    @GET("v3/dogecoin/address/balance/{address}")
    suspend fun getDogecoinBalance(@Path("address") address: String): TatumUTXOBalance

    /**
     * Get XRP account balance.
     */
    @GET("v3/xrp/account/{address}/balance")
    suspend fun getXrpBalance(@Path("address") address: String): TatumXrpBalanceResponse

    /**
     * Get Tron account info.
     */
    @GET("v3/tron/account/{address}")
    suspend fun getTronAccount(@Path("address") address: String): TatumTronAccountResponse

    /**
     * Get Cardano account info.
     */
    @GET("v3/ada/account/{address}")
    suspend fun getCardanoAccount(@Path("address") address: String): List<TatumAdaBalanceResponse>

    /**
     * Get Solana account balance.
     */
    @GET("v3/solana/account/balance/{address}")
    suspend fun getSolanaBalance(@Path("address") address: String): TatumSolBalanceResponse

    /**
     * Get EVM chain balance (legacy API).
     */
    @GET("v3/{chain}/address/balance/{address}")
    suspend fun getEvmBalance(
        @Path("chain") chain: String,
        @Path("address") address: String
    ): TatumEvmBalanceResponse
}

// ==================== V4 Response Models ====================

@Serializable
data class TatumV4PortfolioResponse(
    val result: List<TatumV4BalanceItem> = emptyList()
)

@Serializable
data class TatumV4BalanceItem(
    val type: String = "",
    val balance: String = "0",
    @SerialName("denominatedBalance")
    val denominatedBalance: String = "0",
    val decimals: Int = 18,
    val tokenSymbol: String? = null,
    val tokenName: String? = null,
    val tokenAddress: String? = null
) {
    /**
     * Get human-readable balance, handling both raw and denominated values.
     */
    fun getHumanReadableBalance(): Double {
        val denominated = denominatedBalance.toDoubleOrNull() ?: 0.0
        return if (denominated > 1000) {
            // Raw value, needs to be divided by 10^decimals
            denominated / Math.pow(10.0, decimals.toDouble())
        } else {
            // Already human-readable
            denominated
        }
    }
}

// ==================== V3 Response Models ====================

@Serializable
data class TatumUTXOBalance(
    val incoming: String = "0",
    val outgoing: String = "0"
) {
    val confirmedBalance: Double
        get() = (incoming.toDoubleOrNull() ?: 0.0) - (outgoing.toDoubleOrNull() ?: 0.0)
}

@Serializable
data class TatumXrpBalanceResponse(
    val balance: String = "0"
) {
    // XRP balance is in drops (1 XRP = 1,000,000 drops)
    val balanceInXrp: Double
        get() = (balance.toDoubleOrNull() ?: 0.0) / 1_000_000.0
}

@Serializable
data class TatumTronAccountResponse(
    val balance: Long = 0,
    val trc20: List<TatumTrc20Balance> = emptyList()
) {
    // TRX balance is in SUN (1 TRX = 1,000,000 SUN)
    val balanceTrx: Double
        get() = balance.toDouble() / 1_000_000.0

    fun getTokenBalance(symbol: String): Double {
        return trc20.find { it.symbol.equals(symbol, ignoreCase = true) }?.balance?.toDoubleOrNull() ?: 0.0
    }
}

@Serializable
data class TatumTrc20Balance(
    val symbol: String = "",
    val balance: String = "0"
)

@Serializable
data class TatumAdaBalanceResponse(
    val value: String = "0",
    val currency: TatumAdaCurrency = TatumAdaCurrency()
) {
    // ADA balance is in lovelace (1 ADA = 1,000,000 lovelace)
    val humanReadableBalance: Double
        get() = (value.toDoubleOrNull() ?: 0.0) / 1_000_000.0
}

@Serializable
data class TatumAdaCurrency(
    val symbol: String = "ADA"
)

@Serializable
data class TatumSolBalanceResponse(
    val balance: String = "0"
) {
    // SOL balance is in lamports (1 SOL = 1,000,000,000 lamports)
    val solBalance: Double
        get() = (balance.toDoubleOrNull() ?: 0.0) / 1_000_000_000.0
}

@Serializable
data class TatumEvmBalanceResponse(
    val balance: String = "0"
) {
    // Balance is typically in wei for ETH-like chains
    val humanReadableBalance: Double
        get() = (balance.toDoubleOrNull() ?: 0.0) / 1e18
}
