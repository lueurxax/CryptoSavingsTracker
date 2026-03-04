package com.xax.CryptoSavingsTracker.presentation.dashboard

import com.google.common.truth.Truth.assertThat
import java.nio.file.Files
import java.nio.file.Path
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Test

class GoalDashboardWireCodecTest {
    @Test
    fun decimalAndDateRoundTripMatchesFixture() {
        val fixture = loadWireRoundTripFixture()

        fixture["decimals"]!!.jsonArray.forEach { element ->
            val raw = element.jsonPrimitive.content
            val decoded = GoalDashboardWireCodec.decodeDecimal(raw)
            val encoded = GoalDashboardWireCodec.encodeDecimal(decoded)
            val decodedAgain = GoalDashboardWireCodec.decodeDecimal(encoded)
            assertThat(decodedAgain).isEqualTo(decoded)
        }

        fixture["datesUtcMillis"]!!.jsonArray.forEach { element ->
            val raw = element.jsonPrimitive.content
            val decoded = GoalDashboardWireCodec.decodeDate(raw)
            val encoded = GoalDashboardWireCodec.encodeDate(decoded)
            assertThat(encoded).isEqualTo(raw)
        }
    }

    private fun loadWireRoundTripFixture() =
        Json.parseToJsonElement(
            String(
                Files.readAllBytes(checkNotNull(fixturePath()))
            )
        ).jsonObject

    private fun fixturePath(): Path? {
        val candidates = listOf(
            Path.of("shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_wire_roundtrip.v1.json"),
            Path.of("../shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_wire_roundtrip.v1.json"),
            Path.of("../../shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_wire_roundtrip.v1.json")
        )
        return candidates.firstOrNull { Files.exists(it) }
    }
}
