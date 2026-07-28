package com.xax.CryptoSavingsTracker.domain.model

/**
 * One source of truth for currencies that can participate in financial
 * conversion. UI selection, addressed-route validation, and provider routing
 * must not advertise a currency without an explicit provider identifier.
 */
object ExchangeRateCurrencyCatalog {
    val goalCurrencies = listOf(
        "USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "CNY", "INR", "BRL"
    )

    val fiatCurrencies: Set<String> = goalCurrencies.toSet()

    private val cryptoProviderIds = mapOf(
        "BTC" to "bitcoin",
        "ETH" to "ethereum",
        "USDT" to "tether",
        "BNB" to "binancecoin",
        "SOL" to "solana",
        "USDC" to "usd-coin",
        "XRP" to "ripple",
        "ADA" to "cardano",
        "DOGE" to "dogecoin",
        "TRX" to "tron",
        "AVAX" to "avalanche-2",
        "DOT" to "polkadot",
        "MATIC" to "polygon-ecosystem-token",
        "POL" to "polygon-ecosystem-token",
        "LINK" to "chainlink",
        "SHIB" to "shiba-inu",
        "LTC" to "litecoin",
        "BCH" to "bitcoin-cash",
        "ALGO" to "algorand",
        "XLM" to "stellar",
        "UNI" to "uniswap",
        "DAI" to "dai",
        "WETH" to "weth",
        "AAVE" to "aave",
        "APE" to "apecoin",
        "CRV" to "curve-dao-token",
        "MKR" to "maker",
        "SNX" to "havven",
        "COMP" to "compound-governance-token",
        "YFI" to "yearn-finance",
        "SUSHI" to "sushi",
        "BUSD" to "binance-usd",
        "CAKE" to "pancakeswap-token",
        "BAKE" to "bakerytoken",
        "WMATIC" to "wrapped-matic",
        "QUICK" to "quickswap"
    )

    val cryptoCurrencies: Set<String> = cryptoProviderIds.keys

    fun providerId(symbol: String): String? = cryptoProviderIds[symbol.uppercase()]

    fun supports(symbol: String): Boolean {
        val canonical = symbol.uppercase()
        return canonical in fiatCurrencies || canonical in cryptoCurrencies
    }
}
