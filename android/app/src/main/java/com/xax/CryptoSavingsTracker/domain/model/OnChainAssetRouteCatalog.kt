package com.xax.CryptoSavingsTracker.domain.model

internal data class SupportedEvmAssetRoute(
    val tokenContracts: Set<String>
) {
    val isNative: Boolean
        get() = tokenContracts.isEmpty()
}

/**
 * Provider-neutral catalog of addressed asset identities the app can resolve unambiguously.
 * Persistence validation and provider routing both delegate here.
 */
internal object OnChainAssetRouteCatalog {
    const val TRON_USDT_CONTRACT = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
    const val LEGACY_QUICK_POLYGON_CONTRACT = "0x831753DD7087CaC61aB5644b308642cc1c33Dc13"
    const val LEGACY_QUICK_PERSISTENCE_CURRENCY = "QUICK_LEGACY"

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

    val evmChainIds = setOf(
        "ethereum",
        "polygon",
        "bsc",
        "arbitrum",
        "optimism",
        "base",
        "avax"
    )

    private val nativeCurrencies = mapOf(
        "ethereum" to setOf("ETH"),
        "polygon" to setOf("MATIC", "POL"),
        "bsc" to setOf("BNB"),
        "arbitrum" to setOf("ETH"),
        "optimism" to setOf("ETH"),
        "base" to setOf("ETH"),
        "avax" to setOf("AVAX")
    )

    private val tokenContracts = mapOf(
        "ethereum" to mapOf(
            "USDT" to setOf("0xdAC17F958D2ee523a2206206994597C13D831ec7"),
            "USDC" to setOf("0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"),
            "DAI" to setOf("0x6B175474E89094C44Da98b954EedeAC495271d0F"),
            "WETH" to setOf("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
            "UNI" to setOf("0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984"),
            "LINK" to setOf("0x514910771AF9Ca656af840dff83E8264EcF986CA"),
            "AAVE" to setOf("0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2dDaE9"),
            "SHIB" to setOf("0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE"),
            "APE" to setOf("0x4d224452801ACEd8B2F0aEBE155379bb5D594381"),
            "CRV" to setOf("0xD533a949740bb3306d119CC777fa900bA034cd52"),
            "MKR" to setOf("0x9f8F72aA9304c8B593d555F12ef6589cC3A579A2"),
            "SNX" to setOf("0xC011A72400E58ecD99Ee497CF89E3775d4bd732F"),
            "COMP" to setOf("0xc00e94Cb662C3520282E6f5717214004A7f26888"),
            "YFI" to setOf("0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e"),
            "SUSHI" to setOf("0x6B3595068778DD592e39A122f4f5a5CF09C90fE2")
        ),
        "bsc" to mapOf(
            "BUSD" to setOf("0xe9e7CEA3DedcA5984780BAfc599bD69ADd087D56"),
            "CAKE" to setOf("0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82"),
            "BAKE" to setOf("0xE02dF9e3e622DeBdD69fb838bB799E3F168902c5")
        ),
        "polygon" to mapOf(
            "WMATIC" to setOf("0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"),
            // Old QUICK (0x831753...) uses a different 1:1000-denominated unit. It is not an
            // additive alias and must not be routed as current QUICK.
            "QUICK" to setOf("0xB5C064F955D8e7F38fE0460C556a72987494eE17")
        )
    )

    private val nonEvmCurrencies = mapOf(
        "bitcoin" to setOf("BTC"),
        "litecoin" to setOf("LTC"),
        "bitcoin-cash" to setOf("BCH"),
        "dogecoin" to setOf("DOGE"),
        "solana" to setOf("SOL"),
        "xrp" to setOf("XRP"),
        "tron" to setOf("TRX", "USDT", TRON_USDT_CONTRACT.uppercase()),
        "cardano" to setOf("ADA")
    )

    val supportedPersistenceCurrencies: Set<String> by lazy {
        buildSet {
            nativeCurrencies.forEach { (chain, currencies) ->
                currencies.forEach {
                    add(canonicalPersistenceCurrency(chain, it))
                }
            }
            tokenContracts.forEach { (chain, currencies) ->
                currencies.keys.forEach {
                    add(canonicalPersistenceCurrency(chain, it))
                }
            }
            nonEvmCurrencies.forEach { (chain, currencies) ->
                currencies.forEach {
                    add(canonicalPersistenceCurrency(chain, it))
                }
            }
        }.filterNotTo(mutableSetOf()) {
            it == LEGACY_QUICK_PERSISTENCE_CURRENCY
        }
    }

    fun normalizeChainId(chainId: String): String {
        val normalized = chainId.trim().lowercase()
        return chainAliases[normalized] ?: normalized
    }

    fun normalizeCurrencyIdentifier(chainId: String?, currencyOrContract: String): String {
        return canonicalPersistenceCurrency(chainId, currencyOrContract)
    }

    /**
     * Returns the one identifier persisted for an on-chain route.
     *
     * Provider contracts and legacy symbols remain valid inputs, but persistence uses the
     * provider-neutral symbol so aliases cannot create separate financial identities.
     */
    fun canonicalPersistenceCurrency(chainId: String?, currencyOrContract: String): String {
        val normalizedChainId = chainId
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.let(::normalizeChainId)
        val trimmed = currencyOrContract.trim()
        val uppercaseIdentifier = trimmed.uppercase()

        if (
            normalizedChainId == "tron" &&
            (
                uppercaseIdentifier == "USDT" ||
                    trimmed.equals(TRON_USDT_CONTRACT, ignoreCase = true)
                )
        ) {
            return "USDT"
        }

        if (
            normalizedChainId == "polygon" &&
            (
                uppercaseIdentifier == LEGACY_QUICK_PERSISTENCE_CURRENCY ||
                    trimmed.equals(LEGACY_QUICK_POLYGON_CONTRACT, ignoreCase = true)
                )
        ) {
            return LEGACY_QUICK_PERSISTENCE_CURRENCY
        }

        if (normalizedChainId in evmChainIds) {
            val native = nativeCurrencies[normalizedChainId].orEmpty()
            if (uppercaseIdentifier in native) {
                return if (normalizedChainId == "polygon") "POL" else native.first()
            }

            tokenContracts[normalizedChainId].orEmpty().forEach { (symbol, contracts) ->
                if (
                    uppercaseIdentifier == symbol ||
                    contracts.any { contract -> contract.equals(trimmed, ignoreCase = true) }
                ) {
                    return symbol
                }
            }
        }

        return uppercaseIdentifier
    }

    fun isLegacyQuick(chainId: String?, currencyOrContract: String): Boolean {
        return normalizeChainId(chainId.orEmpty()) == "polygon" &&
            canonicalPersistenceCurrency(chainId, currencyOrContract) ==
            LEGACY_QUICK_PERSISTENCE_CURRENCY
    }

    fun resolveEvm(chainId: String, currencyOrContract: String): SupportedEvmAssetRoute {
        val normalizedChainId = normalizeChainId(chainId)
        require(normalizedChainId in evmChainIds) {
            "Unsupported EVM chain: $chainId"
        }
        val normalizedIdentifier = currencyOrContract.trim()
        if (normalizedIdentifier.uppercase() in nativeCurrencies[normalizedChainId].orEmpty()) {
            return SupportedEvmAssetRoute(tokenContracts = emptySet())
        }

        val supportedTokens = tokenContracts[normalizedChainId].orEmpty()
        supportedTokens[normalizedIdentifier.uppercase()]?.let { contracts ->
            return SupportedEvmAssetRoute(tokenContracts = contracts)
        }
        val canonicalContract = supportedTokens.values
            .asSequence()
            .flatten()
            .firstOrNull { it.equals(normalizedIdentifier, ignoreCase = true) }
        require(canonicalContract != null) {
            "Unsupported asset $currencyOrContract on $chainId; no canonical token contract is configured"
        }
        return SupportedEvmAssetRoute(tokenContracts = setOf(canonicalContract))
    }

    fun requireAddressedRoute(chainId: String, currencyOrContract: String) {
        val normalizedChainId = normalizeChainId(chainId)
        val canonicalCurrency = canonicalPersistenceCurrency(normalizedChainId, currencyOrContract)
        if (normalizedChainId in evmChainIds) {
            resolveEvm(normalizedChainId, canonicalCurrency)
            return
        }
        val supported = nonEvmCurrencies[normalizedChainId].orEmpty()
        require(canonicalCurrency in supported) {
            val displayIdentifiers = supported
                .filterNot { it == TRON_USDT_CONTRACT.uppercase() }
                .sorted()
                .joinToString(", ")
            "Unsupported asset $currencyOrContract on $chainId; supported: $displayIdentifiers"
        }
    }

    fun supportedEvmIdentifiers(): Map<String, Set<String>> {
        return evmChainIds.associateWith { chainId ->
            buildSet {
                addAll(nativeCurrencies[chainId].orEmpty())
                tokenContracts[chainId].orEmpty().forEach { (symbol, contracts) ->
                    add(symbol)
                    addAll(contracts)
                }
            }
        }
    }
}
