package com.xax.CryptoSavingsTracker.data.remote.api

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Test

class TatumTronAccountResponseTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun tronAccountResponse_decodesTrc20BalancesAsContractAddressMaps() {
        val response = json.decodeFromString<TatumTronAccountResponse>(TRON_ACCOUNT_RESPONSE_JSON)

        assertThat(response.trc20).containsExactly(
            mapOf(USDT_CONTRACT_ADDRESS to "12345678"),
            mapOf("TSdZwNqpHofzP6BsBKGQUWdBeJphLmF6id" to "4749000000")
        ).inOrder()
    }

    @Test
    fun tronAccountResponse_normalizesKnownTokenAtomicBalance() {
        val response = json.decodeFromString<TatumTronAccountResponse>(TRON_ACCOUNT_RESPONSE_JSON)

        assertThat(response.getTokenBalance("USDT")).isWithin(0.0000001).of(12.345678)
        assertThat(response.getTokenBalance(USDT_CONTRACT_ADDRESS))
            .isWithin(0.0000001)
            .of(12.345678)
    }

    private companion object {
        const val USDT_CONTRACT_ADDRESS = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"

        const val TRON_ACCOUNT_RESPONSE_JSON = """
            {
              "assetIssuedId": "31303031333838",
              "assetIssuedName": "4f5a595f544f4e",
              "balance": 29127653860,
              "createTime": 1668192183000,
              "trc10": [
                {
                  "value": 992000000000,
                  "key": "1001388"
                }
              ],
              "trc20": [
                {
                  "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t": "12345678"
                },
                {
                  "TSdZwNqpHofzP6BsBKGQUWdBeJphLmF6id": "4749000000"
                }
              ],
              "freeNetLimit": 600,
              "bandwidth": 600
            }
        """
    }
}
