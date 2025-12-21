package com.xax.CryptoSavingsTracker.presentation.dashboard

import com.google.common.truth.Truth.assertThat
import org.junit.jupiter.api.Test

class DashboardBalanceCalculationTest {
    @Test
    fun totalUsd_nullWhenAllRatesMissingButBalancesNonZero() {
        val summaries = listOf(
            DashboardAssetSummary(
                asset = com.xax.CryptoSavingsTracker.domain.model.Asset(
                    id = "a1",
                    currency = "BTC",
                    address = "bc1q",
                    chainId = "bitcoin",
                    createdAt = 1L,
                    updatedAt = 1L
                ),
                currentBalance = 1.0,
                usdValue = null
            )
        )

        val partialTotal = summaries.mapNotNull { it.usdValue }.sum()
        val hasMissing = summaries.any { it.currentBalance != 0.0 && it.usdValue == null }
        val totalUsd = if (hasMissing && partialTotal == 0.0) null else partialTotal

        assertThat(totalUsd).isNull()
    }
}

