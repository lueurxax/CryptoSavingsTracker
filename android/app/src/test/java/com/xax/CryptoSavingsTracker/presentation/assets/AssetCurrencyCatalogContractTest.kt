package com.xax.CryptoSavingsTracker.presentation.assets

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.ExchangeRateCurrencyCatalog
import org.junit.jupiter.api.Test

class AssetCurrencyCatalogContractTest {
    @Test
    fun `fiat asset picker uses the shared exchange rate catalog`() {
        assertThat(AddEditAssetViewModel.availableFiatCurrencies)
            .containsExactlyElementsIn(ExchangeRateCurrencyCatalog.goalCurrencies)
            .inOrder()
    }
}
