package com.xax.CryptoSavingsTracker.presentation.dashboard

import com.google.common.truth.Truth.assertThat
import java.nio.file.Files
import java.nio.file.Path
import org.junit.jupiter.api.Test
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class GoalDashboardSceneFixtureContractTest {
    @Test
    fun sceneFixtureMatchesWireContractBasics() {
        val path = sceneFixturePath()
        assertThat(path).isNotNull()
        val raw = String(Files.readAllBytes(checkNotNull(path)))
        val payload = Json.parseToJsonElement(raw).jsonObject
        val scene = GoalDashboardSceneWireCodec.decodeScene(raw)

        listOf(
            "goalId",
            "goalLifecycle",
            "currency",
            "generatedAt",
            "freshness",
            "snapshot",
            "nextAction",
            "forecastRisk",
            "contributionActivity",
            "allocationHealth",
            "utilities",
            "telemetryContext"
        ).forEach { key ->
            assertThat(payload.containsKey(key)).isTrue()
        }

        val decimalRegex = Regex("^-?(0|[1-9][0-9]*)(\\.[0-9]{1,18})?$")
        val utcMillisRegex = Regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$")

        val snapshot = payload.requireObject("snapshot")
        assertThat(decimalRegex.matches(snapshot.requireString("currentAmount"))).isTrue()
        assertThat(decimalRegex.matches(snapshot.requireString("targetAmount"))).isTrue()
        assertThat(decimalRegex.matches(snapshot.requireString("remainingAmount"))).isTrue()

        assertThat(utcMillisRegex.matches(payload.requireString("generatedAt"))).isTrue()
        assertThat(utcMillisRegex.matches(payload.requireObject("forecastRisk").requireString("targetDate"))).isTrue()

        val nextAction = payload.requireObject("nextAction")
        assertThat(nextAction.containsKey("primaryCta")).isTrue()
        assertThat(nextAction.containsKey("reasonCopyKey")).isTrue()
        assertThat(scene.nextAction.primaryCta.id).isNotEmpty()
        assertThat(scene.snapshot.currentAmount.toPlainString()).isEqualTo("1500.25")
    }

    private fun sceneFixturePath(): Path? {
        val candidates = listOf(
            Path.of("shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_scene_model.v1.json"),
            Path.of("../shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_scene_model.v1.json"),
            Path.of("../../shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_scene_model.v1.json")
        )
        return candidates.firstOrNull { Files.exists(it) }
    }
}

private fun JsonObject.requireObject(key: String): JsonObject =
    this[key]?.jsonObject ?: error("Missing object field: $key")

private fun JsonObject.requireString(key: String): String =
    this[key]?.jsonPrimitive?.content ?: error("Missing string field: $key")
