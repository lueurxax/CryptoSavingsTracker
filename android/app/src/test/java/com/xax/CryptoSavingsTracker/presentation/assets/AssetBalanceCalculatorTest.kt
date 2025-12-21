package com.xax.CryptoSavingsTracker.presentation.assets

import com.google.common.truth.Truth.assertThat
import org.junit.jupiter.api.Test

class AssetBalanceCalculatorTest {
    @Test
    fun totalBalance_includesOnChainBalance_whenHasOnChain() {
        val total = AssetBalanceCalculator.totalBalance(
            manualBalance = 0.0,
            onChainBalance = 0.004106,
            hasOnChain = true
        )

        assertThat(total).isWithin(0.0000001).of(0.004106)
    }

    @Test
    fun totalBalance_ignoresOnChainBalance_whenNoOnChain() {
        val total = AssetBalanceCalculator.totalBalance(
            manualBalance = 1.25,
            onChainBalance = 999.0,
            hasOnChain = false
        )

        assertThat(total).isWithin(0.0000001).of(1.25)
    }
}
