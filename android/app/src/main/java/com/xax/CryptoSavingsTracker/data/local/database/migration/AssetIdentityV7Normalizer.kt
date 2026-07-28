package com.xax.CryptoSavingsTracker.data.local.database.migration

import com.xax.CryptoSavingsTracker.domain.model.OnChainAddressIdentityV1

/**
 * Immutable snapshot of the on-chain aliases understood when schema version 7 shipped.
 *
 * Historical migrations must not delegate to the live route catalog: adding or changing a runtime
 * route later must not silently change the result of an already-released migration.
 */
internal object AssetIdentityV7Normalizer {
    private val chainAliases = mapOf(
        "eth" to "ethereum",
        "ethereum" to "ethereum",
        "matic" to "polygon",
        "pol" to "polygon",
        "polygon" to "polygon",
        "bnb" to "bsc",
        "bsc" to "bsc",
        "binance-smart-chain" to "bsc",
        "arb" to "arbitrum",
        "arbitrum" to "arbitrum",
        "arbitrum-one" to "arbitrum",
        "op" to "optimism",
        "optimism" to "optimism",
        "base" to "base",
        "avax" to "avax",
        "avalanche" to "avax",
        "avalanche-c" to "avax",
        "btc" to "bitcoin",
        "bitcoin" to "bitcoin",
        "ltc" to "litecoin",
        "litecoin" to "litecoin",
        "bch" to "bitcoin-cash",
        "bcash" to "bitcoin-cash",
        "bitcoin-cash" to "bitcoin-cash",
        "doge" to "dogecoin",
        "dogecoin" to "dogecoin",
        "sol" to "solana",
        "solana" to "solana",
        "xrp" to "xrp",
        "trx" to "tron",
        "tron" to "tron",
        "ada" to "cardano",
        "cardano" to "cardano"
    )

    private val currencyAliasesByChain = mapOf(
        "ethereum" to mapOf(
            "ETH" to "ETH",
            "USDT" to "USDT",
            "0XDAC17F958D2EE523A2206206994597C13D831EC7" to "USDT",
            "USDC" to "USDC",
            "0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48" to "USDC",
            "DAI" to "DAI",
            "0X6B175474E89094C44DA98B954EEDEAC495271D0F" to "DAI",
            "WETH" to "WETH",
            "0XC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2" to "WETH",
            "UNI" to "UNI",
            "0X1F9840A85D5AF5BF1D1762F925BDADDC4201F984" to "UNI",
            "LINK" to "LINK",
            "0X514910771AF9CA656AF840DFF83E8264ECF986CA" to "LINK",
            "AAVE" to "AAVE",
            "0X7FC66500C84A76AD7E9C93437BFC5AC33E2DDAE9" to "AAVE",
            "SHIB" to "SHIB",
            "0X95AD61B0A150D79219DCF64E1E6CC01F0B64C4CE" to "SHIB",
            "APE" to "APE",
            "0X4D224452801ACED8B2F0AEBE155379BB5D594381" to "APE",
            "CRV" to "CRV",
            "0XD533A949740BB3306D119CC777FA900BA034CD52" to "CRV",
            "MKR" to "MKR",
            "0X9F8F72AA9304C8B593D555F12EF6589CC3A579A2" to "MKR",
            "SNX" to "SNX",
            "0XC011A72400E58ECD99EE497CF89E3775D4BD732F" to "SNX",
            "COMP" to "COMP",
            "0XC00E94CB662C3520282E6F5717214004A7F26888" to "COMP",
            "YFI" to "YFI",
            "0X0BC529C00C6401AEF6D220BE8C6EA1667F6AD93E" to "YFI",
            "SUSHI" to "SUSHI",
            "0X6B3595068778DD592E39A122F4F5A5CF09C90FE2" to "SUSHI"
        ),
        "polygon" to mapOf(
            "MATIC" to "POL",
            "POL" to "POL",
            "WMATIC" to "WMATIC",
            "0X0D500B1D8E8EF31E21C99D1DB9A6444D3ADF1270" to "WMATIC",
            "QUICK" to "QUICK",
            "0XB5C064F955D8E7F38FE0460C556A72987494EE17" to "QUICK",
            "QUICK_LEGACY" to "QUICK_LEGACY",
            "0X831753DD7087CAC61AB5644B308642CC1C33DC13" to "QUICK_LEGACY"
        ),
        "bsc" to mapOf(
            "BNB" to "BNB",
            "BUSD" to "BUSD",
            "0XE9E7CEA3DEDCA5984780BAFC599BD69ADD087D56" to "BUSD",
            "CAKE" to "CAKE",
            "0X0E09FABB73BD3ADE0A17ECC321FD13A19E81CE82" to "CAKE",
            "BAKE" to "BAKE",
            "0XE02DF9E3E622DEBDD69FB838BB799E3F168902C5" to "BAKE"
        ),
        "arbitrum" to mapOf("ETH" to "ETH"),
        "optimism" to mapOf("ETH" to "ETH"),
        "base" to mapOf("ETH" to "ETH"),
        "avax" to mapOf("AVAX" to "AVAX"),
        "bitcoin" to mapOf("BTC" to "BTC"),
        "litecoin" to mapOf("LTC" to "LTC"),
        "bitcoin-cash" to mapOf("BCH" to "BCH"),
        "dogecoin" to mapOf("DOGE" to "DOGE"),
        "solana" to mapOf("SOL" to "SOL"),
        "xrp" to mapOf("XRP" to "XRP"),
        "tron" to mapOf(
            "TRX" to "TRX",
            "USDT" to "USDT",
            "TR7NHQJEKQXGTCI8Q8ZY4PL8OTSZGJLJ6T" to "USDT"
        ),
        "cardano" to mapOf("ADA" to "ADA")
    )

    data class CanonicalFields(
        val currency: String,
        val address: String?,
        val chainId: String?,
        val hasMalformedAddress: Boolean = false
    )

    fun canonicalize(
        currency: String,
        address: String?,
        chainId: String?
    ): CanonicalFields {
        val canonicalChainId = chainId
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.lowercase()
            ?.let { chainAliases[it] ?: it }
        val uppercaseCurrency = currency.trim().uppercase()
        val canonicalCurrency = currencyAliasesByChain[canonicalChainId]
            ?.get(uppercaseCurrency)
            ?: uppercaseCurrency
        val trimmedAddress = address?.trim()?.takeIf { it.isNotEmpty() }
        var hasMalformedAddress = false
        val canonicalAddress = trimmedAddress?.let { candidate ->
            try {
                OnChainAddressIdentityV1.canonicalize(canonicalChainId, candidate)
            } catch (_: IllegalArgumentException) {
                // Schema upgrades must remain total over legacy rows. Runtime
                // add/update validation stays strict; migration callers use this
                // marker to quarantine the preserved malformed identity.
                hasMalformedAddress = true
                candidate
            }
        }

        return CanonicalFields(
            currency = canonicalCurrency,
            address = canonicalAddress,
            chainId = canonicalChainId,
            hasMalformedAddress = hasMalformedAddress
        )
    }
}
