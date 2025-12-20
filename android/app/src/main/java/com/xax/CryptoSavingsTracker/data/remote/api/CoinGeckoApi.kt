package com.xax.CryptoSavingsTracker.data.remote.api

import kotlinx.serialization.Serializable
import retrofit2.http.GET
import retrofit2.http.Query

/**
 * CoinGecko API interface for fetching cryptocurrency prices.
 * Uses the demo API with x-cg-demo-api-key header.
 */
interface CoinGeckoApi {

    /**
     * Get simple price for one or more coins.
     * Response format: { "bitcoin": { "usd": 45000 } }
     */
    @GET("simple/price")
    suspend fun getSimplePrice(
        @Query("ids") ids: String,
        @Query("vs_currencies") vsCurrencies: String
    ): Map<String, Map<String, Double>>

    /**
     * Get coin market data.
     * Response format: [{ "id": "bitcoin", "current_price": 45000, ... }]
     */
    @GET("coins/markets")
    suspend fun getCoinMarkets(
        @Query("vs_currency") vsCurrency: String,
        @Query("ids") ids: String,
        @Query("order") order: String = "market_cap_desc",
        @Query("per_page") perPage: Int = 1,
        @Query("page") page: Int = 1,
        @Query("sparkline") sparkline: Boolean = false
    ): List<CoinMarketData>
}

@Serializable
data class CoinMarketData(
    val id: String,
    val symbol: String,
    val name: String,
    val current_price: Double?
)
