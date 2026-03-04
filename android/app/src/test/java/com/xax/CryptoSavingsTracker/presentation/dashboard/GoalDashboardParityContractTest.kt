package com.xax.CryptoSavingsTracker.presentation.dashboard

import com.google.common.truth.Truth.assertThat
import java.nio.file.Files
import java.nio.file.Path
import org.junit.jupiter.api.Test
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class GoalDashboardParityContractTest {
    @Test
    fun parityArtifactMatchesAndroidContractExactly() {
        val path = parityFixturePath()
        assertThat(path).isNotNull()
        val existingPath = checkNotNull(path)

        val payload = Json.parseToJsonElement(String(Files.readAllBytes(existingPath))).jsonObject
        assertThat(payload["version"]?.jsonPrimitive?.content).isEqualTo(GoalDashboardParityContract.VERSION)
        assertThat(payload.stringList("moduleIds")).containsExactlyElementsIn(GoalDashboardParityContract.moduleIds).inOrder()
        assertThat(payload.stringList("stateIds")).containsExactlyElementsIn(GoalDashboardParityContract.stateIds).inOrder()
        assertThat(payload.stringList("resolverStateIds")).containsExactlyElementsIn(GoalDashboardParityContract.resolverStateIds).inOrder()
        assertThat(payload.stringList("copyKeys")).containsExactlyElementsIn(GoalDashboardParityContract.copyKeys).inOrder()
        assertThat(payload.stringList("statusChipIds")).containsExactlyElementsIn(GoalDashboardParityContract.statusChipIds).inOrder()
    }

    private fun parityFixturePath(): Path? {
        val candidates = listOf(
            Path.of("shared-test-fixtures/goal-dashboard/goal_dashboard_parity.v1.json"),
            Path.of("../shared-test-fixtures/goal-dashboard/goal_dashboard_parity.v1.json"),
            Path.of("../../shared-test-fixtures/goal-dashboard/goal_dashboard_parity.v1.json")
        )
        return candidates.firstOrNull { Files.exists(it) }
    }
}

private fun kotlinx.serialization.json.JsonObject.stringList(field: String): List<String> {
    return this[field]?.jsonArray?.map { it.jsonPrimitive.content }
        ?: error("Missing array field: $field")
}
