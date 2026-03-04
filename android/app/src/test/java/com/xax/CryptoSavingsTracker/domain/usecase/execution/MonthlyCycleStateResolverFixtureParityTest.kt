package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.CycleConflictReason
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.model.PlanningSource
import com.xax.CryptoSavingsTracker.domain.model.UiCycleState
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import io.mockk.mockk
import java.io.File
import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Test

class MonthlyCycleStateResolverFixtureParityTest {

    private val recordRepository = mockk<ExecutionRecordRepository>(relaxed = true)
    private val resolver = MonthlyCycleStateResolverUseCase(recordRepository)
    private val json = Json { ignoreUnknownKeys = false }

    @Test
    fun resolve_matchesSharedFixtures() {
        val fixtures = fixtureFiles()
        assertThat(fixtures).isNotEmpty()

        fixtures.forEach { file ->
            val fixture = json.decodeFromString<Fixture>(file.readText())
            fixture.expected.validateUnion()
            ZoneId.of(fixture.displayTimeZone)

            val actual = resolver.resolve(
                records = fixture.records.mapIndexed { index, record -> record.toExecutionRecord(index) },
                currentStorageMonthLabelUtc = fixture.currentStorageMonthLabelUtc,
                nowUtcMillis = Instant.parse(fixture.nowUtc).toEpochMilli()
            )
            val expected = fixture.expected.toUiState()

            assertThat(actual).isEqualTo(expected)
        }
    }

    @Test
    fun expectedUnionValidator_rejectsMixedStatePayload() {
        val mixed = FixtureExpected(
            state = "planning",
            planning = FixtureExpectedPlanning(month = "2026-03", source = "currentMonth"),
            executing = FixtureExpectedExecuting(month = "2026-03", canFinish = true, canUndoStart = true),
            closed = null,
            conflict = null
        )

        var threw = false
        try {
            mixed.validateUnion()
        } catch (_: IllegalArgumentException) {
            threw = true
        }
        assertThat(threw).isTrue()
    }

    private fun fixtureFiles(): List<File> {
        val root = File(System.getProperty("user.dir") ?: ".")
        val candidates = listOf(
            File(root, "../shared-test-fixtures/monthly-cycle"),
            File(root, "shared-test-fixtures/monthly-cycle"),
            File(root, "../../shared-test-fixtures/monthly-cycle")
        )
        val dir = candidates.firstOrNull { it.exists() && it.isDirectory }
            ?: error("Shared fixtures directory not found. Checked: ${candidates.joinToString { it.absolutePath }}")

        return dir.listFiles { file -> file.isFile && file.extension.lowercase() == "json" }
            ?.sortedBy { it.name }
            ?: emptyList()
    }
}

@Serializable
private data class Fixture(
    val displayTimeZone: String,
    val nowUtc: String,
    val currentStorageMonthLabelUtc: String,
    val undoWindowSeconds: Double,
    val records: List<FixtureRecord>,
    val expected: FixtureExpected
)

@Serializable
private data class FixtureRecord(
    val monthLabel: String,
    val status: String,
    val startedAt: String? = null,
    val completedAt: String? = null,
    val canUndoUntil: String? = null
) {
    fun toExecutionRecord(index: Int): ExecutionRecord {
        val parsedStatus = when (status.lowercase()) {
            "draft" -> ExecutionStatus.DRAFT
            "executing" -> ExecutionStatus.EXECUTING
            "closed" -> ExecutionStatus.CLOSED
            else -> throw IllegalArgumentException("Unknown fixture status: $status")
        }

        return ExecutionRecord(
            id = "$monthLabel-$index",
            planId = "plan-$monthLabel",
            monthLabel = monthLabel,
            status = parsedStatus,
            startedAtMillis = startedAt?.let { Instant.parse(it).toEpochMilli() },
            closedAtMillis = completedAt?.let { Instant.parse(it).toEpochMilli() },
            canUndoUntilMillis = canUndoUntil?.let { Instant.parse(it).toEpochMilli() },
            createdAtMillis = 0L,
            updatedAtMillis = 0L
        )
    }
}

@Serializable
private data class FixtureExpected(
    val state: String,
    val planning: FixtureExpectedPlanning? = null,
    val executing: FixtureExpectedExecuting? = null,
    val closed: FixtureExpectedClosed? = null,
    val conflict: FixtureExpectedConflict? = null
) {
    fun validateUnion() {
        val count = listOf(planning, executing, closed, conflict).count { it != null }
        require(count == 1) { "Expected payload must contain exactly one state object" }
        when (state) {
            "planning" -> require(planning != null && executing == null && closed == null && conflict == null)
            "executing" -> require(planning == null && executing != null && closed == null && conflict == null)
            "closed" -> require(planning == null && executing == null && closed != null && conflict == null)
            "conflict" -> require(planning == null && executing == null && closed == null && conflict != null)
            else -> error("Unknown expected state: $state")
        }
    }

    fun toUiState(): UiCycleState {
        return when (state) {
            "planning" -> {
                val payload = requireNotNull(planning)
                UiCycleState.Planning(
                    monthLabel = payload.month,
                    source = when (payload.source) {
                        "currentMonth" -> PlanningSource.CURRENT_MONTH
                        "nextMonthAfterClosed" -> PlanningSource.NEXT_MONTH_AFTER_CLOSED
                        else -> error("Unknown planning source: ${payload.source}")
                    }
                )
            }
            "executing" -> {
                val payload = requireNotNull(executing)
                UiCycleState.Executing(
                    monthLabel = payload.month,
                    canFinish = payload.canFinish,
                    canUndoStart = payload.canUndoStart
                )
            }
            "closed" -> {
                val payload = requireNotNull(closed)
                UiCycleState.Closed(
                    monthLabel = payload.month,
                    canUndoCompletion = payload.canUndoCompletion
                )
            }
            "conflict" -> {
                val payload = requireNotNull(conflict)
                UiCycleState.Conflict(
                    monthLabel = payload.month,
                    reason = when (payload.reason) {
                        "duplicateActiveRecords" -> CycleConflictReason.DUPLICATE_ACTIVE_RECORDS
                        "invalidMonthLabel" -> CycleConflictReason.INVALID_MONTH_LABEL
                        "futureRecord" -> CycleConflictReason.FUTURE_RECORD
                        else -> error("Unknown conflict reason: ${payload.reason}")
                    }
                )
            }
            else -> error("Unknown expected state: $state")
        }
    }
}

@Serializable
private data class FixtureExpectedPlanning(
    val month: String,
    val source: String
)

@Serializable
private data class FixtureExpectedExecuting(
    val month: String,
    val canFinish: Boolean,
    val canUndoStart: Boolean
)

@Serializable
private data class FixtureExpectedClosed(
    val month: String,
    val canUndoCompletion: Boolean
)

@Serializable
private data class FixtureExpectedConflict(
    val month: String? = null,
    val reason: String
)
