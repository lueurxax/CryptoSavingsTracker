package com.xax.CryptoSavingsTracker.presentation.common

import com.google.common.truth.Truth.assertThat
import org.junit.jupiter.api.Test
import java.util.Locale

class AmountFormattersTest {
    @Test
    fun formatDisplayAmount_fiatWholeNumbersHideDecimals() {
        val original = Locale.getDefault()
        try {
            Locale.setDefault(Locale.US)
            assertThat(AmountFormatters.formatDisplayAmount(10.0, isCrypto = false)).isEqualTo("10")
            assertThat(AmountFormatters.formatDisplayAmount(10.5, isCrypto = false)).isEqualTo("10.50")
        } finally {
            Locale.setDefault(original)
        }
    }
}

