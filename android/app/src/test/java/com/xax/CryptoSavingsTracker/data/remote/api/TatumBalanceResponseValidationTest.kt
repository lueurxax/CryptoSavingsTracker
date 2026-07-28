package com.xax.CryptoSavingsTracker.data.remote.api

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Test

class TatumBalanceResponseValidationTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `missing authoritative balance fields fail decoding`() {
        assertThat(
            runCatching {
                json.decodeFromString<TatumV4PortfolioResponse>("{}")
            }.isFailure
        ).isTrue()
        assertThat(
            runCatching {
                json.decodeFromString<TatumV4NativeBalanceResponse>("{}")
            }.isFailure
        ).isTrue()
        assertThat(
            runCatching {
                json.decodeFromString<TatumUTXOBalance>("{}")
            }.isFailure
        ).isTrue()
        assertThat(
            runCatching {
                json.decodeFromString<TatumXrpBalanceResponse>("{}")
            }.isFailure
        ).isTrue()
        assertThat(
            runCatching {
                json.decodeFromString<TatumTronAccountResponse>(
                    """{"trc20":[]}"""
                )
            }.isFailure
        ).isTrue()
        assertThat(
            runCatching {
                json.decodeFromString<TatumAdaBalanceResponse>("{}")
            }.isFailure
        ).isTrue()
        assertThat(
            runCatching {
                json.decodeFromString<TatumSolBalanceResponse>("{}")
            }.isFailure
        ).isTrue()
    }

    @Test
    fun `malformed and non-finite native balances fail conversion`() {
        listOf("invalid", "NaN", "Infinity", "-1").forEach { rawBalance ->
            assertThat(
                runCatching {
                    TatumV4NativeBalanceResponse(rawBalance).humanReadableBalance
                }.isFailure
            ).isTrue()
            assertThat(
                runCatching {
                    TatumXrpBalanceResponse(rawBalance).balanceInXrp
                }.isFailure
            ).isTrue()
            assertThat(
                runCatching {
                    TatumSolBalanceResponse(rawBalance).solBalance
                }.isFailure
            ).isTrue()
        }
    }

    @Test
    fun `malformed and non-finite atomic balances fail conversion`() {
        listOf("invalid", "NaN", "Infinity", "-1").forEach { rawBalance ->
            assertThat(
                runCatching {
                    TatumUTXOBalance(
                        incoming = rawBalance,
                        outgoing = "0"
                    ).confirmedBalance
                }.isFailure
            ).isTrue()
            assertThat(
                runCatching {
                    TatumAdaBalanceResponse(
                        value = rawBalance,
                        currency = TatumAdaCurrency("ADA")
                    ).humanReadableBalance
                }.isFailure
            ).isTrue()
            assertThat(
                runCatching {
                    TatumV4BalanceItem(
                        type = "fungible",
                        denominatedBalance = rawBalance,
                        decimals = 6,
                        tokenAddress = "0xcanonical"
                    ).getHumanReadableBalance()
                }.isFailure
            ).isTrue()
        }
    }
}
