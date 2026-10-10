package com.xax.CryptoSavingsTracker.data.repository

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.OnChainAssetRouteCatalog
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

class EvmAssetRoutingContractTest {
    @Test
    fun `every catalog accepted EVM identifier resolves through production routing`() {
        OnChainAssetRouteCatalog.supportedEvmIdentifiers().forEach { (chainId, identifiers) ->
            identifiers.forEach { identifier ->
                OnChainAssetRouteCatalog.requireAddressedRoute(chainId, identifier)

                val route = EvmAssetRouting.resolve(chainId, identifier)

                assertThat(route.tatumChain).isNotEmpty()
                if (identifier.startsWith("0x", ignoreCase = true)) {
                    assertThat(route.tokenContracts).isNotEmpty()
                }
            }
        }
    }

    @Test
    fun `catalog and production routing reject unsupported token pair`() {
        assertThrows<IllegalArgumentException> {
            OnChainAssetRouteCatalog.requireAddressedRoute("polygon", "USDT")
        }
        assertThrows<IllegalArgumentException> {
            EvmAssetRouting.resolve("polygon", "USDT")
        }
    }
}
