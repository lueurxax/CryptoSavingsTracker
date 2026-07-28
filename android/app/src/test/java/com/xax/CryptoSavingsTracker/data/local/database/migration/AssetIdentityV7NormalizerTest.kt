package com.xax.CryptoSavingsTracker.data.local.database.migration

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.OnChainAssetRouteCatalog
import com.xax.CryptoSavingsTracker.domain.usecase.asset.AddressedAssetRoutePolicy
import org.junit.jupiter.api.Test

class AssetIdentityV7NormalizerTest {
    @Test
    fun `legacy QUICK is quarantined as a distinct persistence currency`() {
        val legacyContract = "0x831753DD7087CaC61aB5644b308642cc1c33Dc13"

        val frozen = AssetIdentityV7Normalizer.canonicalize(
            currency = legacyContract,
            address = "0xLegacyQuickWallet",
            chainId = "polygon"
        )
        val runtime = OnChainAssetRouteCatalog.canonicalPersistenceCurrency(
            chainId = "polygon",
            currencyOrContract = legacyContract
        )

        assertThat(frozen.currency).isEqualTo("QUICK_LEGACY")
        assertThat(runtime).isEqualTo("QUICK_LEGACY")
        assertThat(frozen.currency).isNotEqualTo("QUICK")
    }

    @Test
    fun `frozen v7 EVM identifiers match current persistence policy`() {
        OnChainAssetRouteCatalog.supportedEvmIdentifiers().forEach { (chainId, identifiers) ->
            identifiers.forEach { identifier ->
                assertParity(
                    currency = identifier,
                    address = " 0xAbCd ",
                    chainId = chainId
                )
            }
        }
    }

    @Test
    fun `frozen v7 chain and non-EVM aliases match current persistence policy`() {
        listOf(
            Triple("ETH", "0xAbCd", "ETH"),
            Triple("MATIC", "0xAbCd", "MATIC"),
            Triple("POL", "0xAbCd", "POL"),
            Triple("BNB", "0xAbCd", "BNB"),
            Triple("AVAX", "0xAbCd", "avalanche"),
            Triple("BTC", "BcCaseSensitive", "BTC"),
            Triple("LTC", "MWWunwFdsSzsi44wARi2zJJGju6VqMMGtN", "LTC"),
            Triple("BCH", "BchCaseSensitive", "bcash"),
            Triple("DOGE", "DogeCaseSensitive", "DOGE"),
            Triple("SOL", "SolCaseSensitive", "SOL"),
            Triple("XRP", "XrpCaseSensitive", "XRP"),
            Triple("TRX", "TCaseSensitive", "TRX"),
            Triple("TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", "TCaseSensitive", "TRON"),
            Triple("ADA", "AdaCaseSensitive", "ADA")
        ).forEach { (currency, address, chainId) ->
            assertParity(currency, address, chainId)
        }
    }

    @Test
    fun `frozen v7 canonicalizes one-case bech32 and Bitcoin Cash aliases`() {
        val bitcoinUppercase = AssetIdentityV7Normalizer.canonicalize(
            currency = "BTC",
            address = "BC1QEXAMPLEADDRESS",
            chainId = "bitcoin"
        )
        val litecoinUppercase = AssetIdentityV7Normalizer.canonicalize(
            currency = "LTC",
            address = "LTC1QEXAMPLEADDRESS",
            chainId = "litecoin"
        )
        val bitcoinCashUnprefixed = AssetIdentityV7Normalizer.canonicalize(
            currency = "BCH",
            address = "QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A",
            chainId = "bitcoin-cash"
        )

        assertThat(bitcoinUppercase.address).isEqualTo("bc1qexampleaddress")
        assertThat(litecoinUppercase.address).isEqualTo("ltc1qexampleaddress")
        assertThat(bitcoinCashUnprefixed.address)
            .isEqualTo("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        assertParity("BTC", "BC1QEXAMPLEADDRESS", "bitcoin")
        assertParity("LTC", "LTC1QEXAMPLEADDRESS", "litecoin")
        assertParity(
            "BCH",
            "QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A",
            "bitcoin-cash"
        )
    }

    @Test
    fun `frozen v7 groups cross encoding UTXO addresses before uniqueness reconciliation`() {
        val bitcoinCashLegacy = AssetIdentityV7Normalizer.canonicalize(
            currency = "BCH",
            address = "1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu",
            chainId = "bitcoin-cash"
        )
        val bitcoinCashCashAddr = AssetIdentityV7Normalizer.canonicalize(
            currency = "BCH",
            address = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a",
            chainId = "bitcoin-cash"
        )
        val litecoinLegacy = AssetIdentityV7Normalizer.canonicalize(
            currency = "LTC",
            address = "3QJmV3qfvL9SuYo34YihAf3sRCW3qSinyC",
            chainId = "litecoin"
        )
        val litecoinModern = AssetIdentityV7Normalizer.canonicalize(
            currency = "LTC",
            address = "MWWunwFdsSzsi44wARi2zJJGju6VqMMGtN",
            chainId = "litecoin"
        )

        assertThat(bitcoinCashLegacy).isEqualTo(bitcoinCashCashAddr)
        assertThat(bitcoinCashLegacy.address)
            .isEqualTo("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        assertThat(litecoinLegacy).isEqualTo(litecoinModern)
        assertThat(litecoinLegacy.address).isEqualTo("MWWunwFdsSzsi44wARi2zJJGju6VqMMGtN")
    }

    private fun assertParity(
        currency: String,
        address: String?,
        chainId: String?
    ) {
        val frozen = AssetIdentityV7Normalizer.canonicalize(currency, address, chainId)
        val runtime = AddressedAssetRoutePolicy.normalize(currency, address, chainId)

        assertThat(frozen.currency).isEqualTo(runtime.currency)
        assertThat(frozen.address).isEqualTo(runtime.address)
        assertThat(frozen.chainId).isEqualTo(runtime.chainId)
    }
}
