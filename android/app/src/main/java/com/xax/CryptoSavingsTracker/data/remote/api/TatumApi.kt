package com.xax.CryptoSavingsTracker.data.remote.api

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
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
     * Used for fungible token balances on EVM chains.
     */
    @GET("v4/data/wallet/portfolio")
    suspend fun getWalletPortfolio(
        @Query("chain") chain: String,
        @Query("addresses") addresses: String,
        @Query("tokenTypes") tokenTypes: String,
        @Query("pageSize") pageSize: Int = 50,
        @Query("offset") offset: Int = 0
    ): TatumV4PortfolioResponse

    /**
     * Get a human-readable native balance for a v4 blockchain identifier.
     */
    @GET("v4/data/blockchains/balance")
    suspend fun getNativeBalance(
        @Query("chain") chain: String,
        @Query("address") address: String
    ): TatumV4NativeBalanceResponse

    /**
     * Get a single raw or normalized blockchain transaction by hash.
     * Used to resolve spent outputs referenced by raw UTXO vin entries.
     */
    @GET("v4/data/blockchains/transaction")
    suspend fun getBlockchainTransaction(
        @Query("chain") chain: String,
        @Query("hash") hash: String
    ): TatumUTXOTransaction

    /**
     * Fetch the documented EVM JSON-RPC transaction receipt. Address history
     * is normalized and does not carry authoritative sender-paid gas fields.
     */
    @POST("v3/blockchain/node/{chain}/")
    suspend fun getEvmTransactionReceipt(
        @Path("chain") chain: String,
        @Body request: TatumEvmJsonRpcRequest
    ): TatumEvmJsonRpcReceiptResponse

    /**
     * Get transaction history (v4 API).
     * Used for EVM chains supported by v4.
     */
    @GET("v4/data/transaction/history")
    suspend fun getTransactionHistoryV4(
        @Query("chain") chain: String,
        @Query("addresses") addresses: String,
        @Query("transactionTypes") transactionTypes: String,
        @Query("tokenAddress") tokenAddress: String? = null,
        @Query("sort") sort: String = "DESC",
        @Query("pageSize") pageSize: Int = 20,
        @Query("offset") offset: Int = 0
    ): TatumV4TransactionResponse

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
     * Get Bitcoin transaction history for an address.
     */
    @GET("v3/bitcoin/transaction/address/{address}")
    suspend fun getBitcoinTransactions(
        @Path("address") address: String,
        @Query("pageSize") pageSize: Int = 20,
        @Query("offset") offset: Int = 0
    ): List<TatumUTXOTransaction>

    /**
     * Get Litecoin transaction history for an address.
     */
    @GET("v3/litecoin/transaction/address/{address}")
    suspend fun getLitecoinTransactions(
        @Path("address") address: String,
        @Query("pageSize") pageSize: Int = 20,
        @Query("offset") offset: Int = 0
    ): List<TatumUTXOTransaction>

    /**
     * Get Bitcoin Cash transaction history for an address.
     */
    @GET("v3/bcash/transaction/address/{address}")
    suspend fun getBitcoinCashTransactions(
        @Path("address") address: String,
        @Query("pageSize") pageSize: Int = 20,
        @Query("offset") offset: Int = 0
    ): List<TatumUTXOTransaction>

    /**
     * Get Dogecoin transaction history for an address.
     */
    @GET("v3/dogecoin/transaction/address/{address}")
    suspend fun getDogecoinTransactions(
        @Path("address") address: String,
        @Query("pageSize") pageSize: Int = 20,
        @Query("offset") offset: Int = 0
    ): List<TatumUTXOTransaction>

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

}

// ==================== V4 Response Models ====================

@Serializable
data class TatumV4PortfolioResponse(
    val result: List<TatumV4BalanceItem>
)

@Serializable
data class TatumV4NativeBalanceResponse(
    val balance: String
) {
    val humanReadableBalance: Double
        get() = balance.requireNonNegativeFiniteBalance("native balance")
}

@Serializable
data class TatumV4BalanceItem(
    val type: String,
    val balance: String = "0",
    @SerialName("denominatedBalance")
    val denominatedBalance: String,
    val decimals: Int,
    val tokenSymbol: String? = null,
    val tokenName: String? = null,
    val tokenAddress: String? = null
) {
    /**
     * Convert the API's atomic-unit balance using the token decimals.
     */
    fun getHumanReadableBalance(): Double {
        require(decimals in 0..MAX_TOKEN_DECIMALS) {
            "Invalid token decimals: $decimals"
        }
        val denominated = denominatedBalance.requireNonNegativeFiniteBalance(
            "token atomic balance"
        )
        val divisor = Math.pow(10.0, decimals.toDouble())
        val converted = denominated / divisor
        check(converted.isFinite() && converted >= 0.0) {
            "Invalid token balance conversion"
        }
        check(denominated == 0.0 || converted > 0.0) {
            "Token balance is outside supported numeric range"
        }
        return converted
    }

    private companion object {
        const val MAX_TOKEN_DECIMALS = 255
    }
}

// ==================== Transaction Response Models ====================

@Serializable
data class TatumV4TransactionResponse(
    val result: List<TatumTransactionDto> = emptyList(),
    val prevPage: String? = null,
    val nextPage: String? = null
)

@Serializable
data class TatumTransactionDto(
    val hash: String,
    val blockNumber: Long? = null,
    val timestamp: Long? = null,
    val from: String? = null,
    val to: String? = null,
    val value: String? = null,
    val gasUsed: String? = null,
    val gasPrice: String? = null,
    val chain: String? = null,
    val address: String? = null,
    val transactionType: String? = null,
    val transactionSubtype: String? = null,
    val amount: String? = null,
    val tokenAddress: String? = null,
    val tokenId: String? = null,
    val transactionIndex: Int? = null,
    val logIndex: Int? = null,
    val counterAddress: String? = null,
    val tokenTransfers: List<TatumTokenTransferDto>? = null
)

@Serializable
data class TatumEvmJsonRpcRequest(
    val jsonrpc: String = "2.0",
    val method: String = "eth_getTransactionReceipt",
    val params: List<String>,
    val id: Int = 1
)

@Serializable
data class TatumEvmJsonRpcReceiptResponse(
    val jsonrpc: String? = null,
    val id: Int? = null,
    val result: TatumEvmTransactionReceipt? = null,
    val error: TatumEvmJsonRpcError? = null
)

@Serializable
data class TatumEvmTransactionReceipt(
    val transactionHash: String? = null,
    val from: String? = null,
    val status: JsonElement? = null,
    val gasUsed: JsonElement? = null,
    val effectiveGasPrice: JsonElement? = null
)

@Serializable
data class TatumEvmJsonRpcError(
    val code: Int? = null,
    val message: String? = null
)

@Serializable
data class TatumTokenTransferDto(
    val from: String? = null,
    val to: String? = null,
    val value: String? = null,
    val tokenAddress: String? = null,
    val tokenSymbol: String? = null,
    val tokenName: String? = null,
    val tokenDecimals: Int? = null
)

// ==================== UTXO Transaction Models ====================

@Serializable
data class TatumUTXOTransaction(
    val hash: String = "",
    val txid: String? = null,
    val time: Long? = null,
    val ts: Long? = null,
    val inputs: List<TatumUTXOInput>? = null,
    val outputs: List<TatumUTXOOutput>? = null,
    val vin: List<TatumUTXOInput>? = null,
    val vout: List<TatumUTXOOutput>? = null
) {
    val resolvedHash: String
        get() = txid?.trim()?.takeIf { it.isNotEmpty() } ?: hash.trim()

    val legacyHashAliases: Set<String>
        get() = buildSet {
            hash.trim().takeIf { it.isNotEmpty() }?.let(::add)
            txid?.trim()?.takeIf { it.isNotEmpty() }?.let(::add)
        }

    val resolvedTime: Long?
        get() = time ?: ts

    val resolvedInputs: List<TatumUTXOInput>
        get() = inputs ?: vin.orEmpty()

    val resolvedOutputs: List<TatumUTXOOutput>
        get() = outputs ?: vout.orEmpty()
}

@Serializable
data class TatumUTXOInput(
    val prevout: TatumUTXOPrevout? = null,
    val coin: TatumUTXOCoin? = null,
    val address: String? = null,
    val txid: String? = null,
    val vout: Int? = null,
    val coinbase: String? = null
)

@Serializable
data class TatumUTXOCoin(
    @SerialName("value")
    @Serializable(with = FlexibleNullableDoubleSerializer::class)
    val valueNumber: Double? = null,
    val address: String? = null,
    val coinbase: Boolean? = null
)

@Serializable
data class TatumUTXOOutput(
    @SerialName("value")
    @Serializable(with = FlexibleNullableDoubleSerializer::class)
    val valueNumber: Double? = null,
    val address: String? = null,
    val scriptPubKey: TatumScriptPubKey? = null,
    val n: Int? = null,
    val index: Int? = null
) {
    val humanReadableValue: Double
        get() = (valueNumber ?: 0.0) / 100_000_000.0
}

@Serializable
data class TatumUTXOPrevout(
    @SerialName("value")
    @Serializable(with = FlexibleNullableDoubleSerializer::class)
    val valueNumber: Double? = null,
    val scriptPubKey: TatumScriptPubKey? = null,
    val hash: String? = null,
    val index: Int? = null
)

@Serializable
data class TatumScriptPubKey(
    val addresses: List<String>? = null,
    val address: String? = null
)

internal object FlexibleNullableDoubleSerializer : kotlinx.serialization.KSerializer<Double?> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("FlexibleNullableDouble", PrimitiveKind.DOUBLE)

    override fun deserialize(decoder: Decoder): Double? {
        if (decoder is JsonDecoder) {
            val element = decoder.decodeJsonElement()
            if (element is JsonNull) return null
            return (element as? JsonPrimitive)?.doubleOrNull
        }
        return decoder.decodeDouble()
    }

    override fun serialize(encoder: Encoder, value: Double?) {
        if (encoder is JsonEncoder) {
            encoder.encodeJsonElement(value?.let(::JsonPrimitive) ?: JsonNull)
        } else {
            encoder.encodeDouble(value ?: 0.0)
        }
    }
}

// ==================== V3 Response Models ====================

@Serializable
data class TatumUTXOBalance(
    val incoming: String,
    val outgoing: String
) {
    val confirmedBalance: Double
        get() {
            val confirmed = incoming.requireNonNegativeFiniteBalance("incoming UTXO balance") -
                outgoing.requireNonNegativeFiniteBalance("outgoing UTXO balance")
            check(confirmed.isFinite() && confirmed >= 0.0) {
                "Invalid confirmed UTXO balance"
            }
            return confirmed
        }
}

@Serializable
data class TatumXrpBalanceResponse(
    val balance: String
) {
    // XRP balance is in drops (1 XRP = 1,000,000 drops)
    val balanceInXrp: Double
        get() = balance.requireNonNegativeFiniteBalance("XRP balance") / 1_000_000.0
}

@Serializable
data class TatumTronAccountResponse(
    val balance: Long,
    val trc20: List<Map<String, String>> = emptyList()
) {
    // TRX balance is in SUN (1 TRX = 1,000,000 SUN)
    val balanceTrx: Double
        get() {
            require(balance >= 0L) { "Invalid TRX balance: $balance" }
            return balance.toDouble() / 1_000_000.0
        }

    fun getTokenBalance(symbolOrContractAddress: String): Double {
        val token = KNOWN_TRC20_TOKENS.firstOrNull { metadata ->
            metadata.symbol.equals(symbolOrContractAddress, ignoreCase = true) ||
                metadata.contractAddress == symbolOrContractAddress
        } ?: throw IllegalArgumentException(
            "Unsupported TRC-20 token: $symbolOrContractAddress"
        )

        val atomicBalance = trc20.firstNotNullOfOrNull { balances ->
            balances[token.contractAddress]
        } ?: return 0.0

        val parsed = atomicBalance.toBigDecimalOrNull()
            ?.takeIf { it.signum() >= 0 }
            ?: throw IllegalStateException(
                "Invalid ${token.symbol} atomic balance: $atomicBalance"
            )
        val converted = parsed.movePointLeft(token.decimals).toDouble()
        check(converted.isFinite() && converted >= 0.0) {
            "Invalid ${token.symbol} atomic balance: $atomicBalance"
        }
        check(parsed.signum() == 0 || converted > 0.0) {
            "${token.symbol} balance is outside supported numeric range"
        }
        return converted
    }

    private data class TokenMetadata(
        val symbol: String,
        val contractAddress: String,
        val decimals: Int
    )

    private companion object {
        val KNOWN_TRC20_TOKENS = listOf(
            TokenMetadata(
                symbol = "USDT",
                contractAddress = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
                decimals = 6
            )
        )
    }
}

@Serializable
data class TatumAdaBalanceResponse(
    val value: String,
    val currency: TatumAdaCurrency
) {
    // ADA balance is in lovelace (1 ADA = 1,000,000 lovelace)
    val humanReadableBalance: Double
        get() = value.requireNonNegativeFiniteBalance("Cardano balance") / 1_000_000.0
}

@Serializable
data class TatumAdaCurrency(
    val symbol: String
)

@Serializable
data class TatumSolBalanceResponse(
    val balance: String
) {
    // SOL balance is in lamports (1 SOL = 1,000,000,000 lamports)
    val solBalance: Double
        get() = balance.requireNonNegativeFiniteBalance("Solana balance") / 1_000_000_000.0
}

private fun String.requireNonNegativeFiniteBalance(fieldName: String): Double {
    val parsed = toDoubleOrNull()
    require(parsed != null && parsed.isFinite() && parsed >= 0.0) {
        "Invalid $fieldName: $this"
    }
    return parsed
}
