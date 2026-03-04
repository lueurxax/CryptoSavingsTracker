package com.xax.CryptoSavingsTracker.presentation.dashboard

import com.fasterxml.jackson.databind.ObjectMapper
import com.google.common.truth.Truth.assertThat
import com.networknt.schema.JsonSchemaFactory
import com.networknt.schema.SpecVersion
import java.nio.file.Files
import java.nio.file.Path
import org.junit.jupiter.api.Test

class GoalDashboardSceneWireCodecTest {
    private val objectMapper = ObjectMapper()

    @Test
    fun sceneFixtureRoundTripPreservesCanonicalWireFields() {
        val payload = String(Files.readAllBytes(checkNotNull(sceneFixturePath())))
        val scene = GoalDashboardSceneWireCodec.decodeScene(payload)
        val encoded = GoalDashboardSceneWireCodec.encodeScene(scene)
        val wire = GoalDashboardSceneWireCodec.decodeWireModel(encoded)

        assertThat(wire.currency).isEqualTo("USD")
        assertThat(wire.snapshot.currentAmount).isEqualTo("1500.25")
        assertThat(wire.forecastRisk.projectedAmount).isEqualTo("3200")
        assertThat(wire.generatedAt.endsWith("Z")).isTrue()
    }

    @Test
    fun encodedScenePayloadValidatesAgainstSharedSchema() {
        val payload = String(Files.readAllBytes(checkNotNull(sceneFixturePath())))
        val scene = GoalDashboardSceneWireCodec.decodeScene(payload)
        val encoded = GoalDashboardSceneWireCodec.encodeScene(scene)

        val schemaJson = objectMapper.readTree(String(Files.readAllBytes(checkNotNull(schemaPath()))))
        val payloadJson = objectMapper.readTree(encoded)

        val factory = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012)
        val schema = factory.getSchema(schemaJson)
        val violations = schema.validate(payloadJson)

        assertThat(violations).isEmpty()
    }

    private fun sceneFixturePath(): Path? {
        val candidates = listOf(
            Path.of("shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_scene_model.v1.json"),
            Path.of("../shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_scene_model.v1.json"),
            Path.of("../../shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_scene_model.v1.json")
        )
        return candidates.firstOrNull { Files.exists(it) }
    }

    private fun schemaPath(): Path? {
        val candidates = listOf(
            Path.of("shared-test-fixtures/goal-dashboard/schemas/goal_dashboard_scene_model.v1.schema.json"),
            Path.of("../shared-test-fixtures/goal-dashboard/schemas/goal_dashboard_scene_model.v1.schema.json"),
            Path.of("../../shared-test-fixtures/goal-dashboard/schemas/goal_dashboard_scene_model.v1.schema.json")
        )
        return candidates.firstOrNull { Files.exists(it) }
    }
}
