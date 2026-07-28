package com.xax.CryptoSavingsTracker.domain.model

import com.google.common.truth.Truth.assertThat
import org.junit.jupiter.api.Named
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.Arguments
import org.junit.jupiter.params.provider.MethodSource

class ChainServiceTest {
    @ParameterizedTest(name = "{0}")
    @MethodSource("officialV4Chains")
    fun `V4-capable metadata exposes an official chain identifier`(
        @Suppress("UNUSED_PARAMETER") description: String,
        chainId: String,
        officialV4Name: String
    ) {
        assertThat(ChainService.getV4ChainName(chainId)).isEqualTo(officialV4Name)
        assertThat(ChainService.supportsV4Api(chainId)).isTrue()
    }

    @Test
    fun `Fantom metadata fails closed because Tatum V4 does not expose that chain`() {
        assertThat(ChainService.getV4ChainName("FTM")).isNull()
        assertThat(ChainService.supportsV4Api("FTM")).isFalse()
    }

    @Test
    fun `Avalanche native currency is selectable and predictable`() {
        assertThat(ChainIds.allChains).contains(ChainIds.AVALANCHE)
        assertThat(ChainIds.predictChain("AVAX")).isEqualTo(ChainIds.AVALANCHE)
    }

    @Test
    fun `Polygon registries expose POL as the canonical native currency`() {
        val polygon = ChainService.getChain("POLYGON")

        assertThat(polygon?.nativeCurrencySymbol).isEqualTo("POL")
        assertThat(ChainIds.predictChain("POL")).isEqualTo(ChainIds.POLYGON)
        assertThat(Cryptocurrencies.common.map { it.first }).contains("POL")
        assertThat(Cryptocurrencies.common.map { it.first }).doesNotContain("MATIC")
    }

    private companion object {
        @JvmStatic
        fun officialV4Chains() = listOf(
            Arguments.of(Named.of("Ethereum", "ETH"), "ETH", "ethereum-mainnet"),
            Arguments.of(Named.of("BNB Smart Chain", "BSC"), "BSC", "bsc-mainnet"),
            Arguments.of(Named.of("Polygon", "POLYGON"), "POLYGON", "polygon-mainnet"),
            Arguments.of(Named.of("Avalanche", "AVAX"), "AVAX", "avax-mainnet"),
            Arguments.of(Named.of("Arbitrum One", "ARBITRUM"), "ARBITRUM", "arb-one-mainnet"),
            Arguments.of(Named.of("Optimism", "OPTIMISM"), "OPTIMISM", "optimism-mainnet"),
            Arguments.of(Named.of("Base", "BASE"), "BASE", "base-mainnet")
        )
    }
}
