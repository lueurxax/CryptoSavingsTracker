package com.xax.CryptoSavingsTracker.domain.navigation

import android.util.Log
import javax.inject.Inject
import javax.inject.Singleton

enum class NavigationTelemetryEvent(val wireName: String) {
    FLOW_STARTED("nav_flow_started"),
    FLOW_COMPLETED("nav_flow_completed"),
    CANCELLED("nav_cancelled"),
    DISCARD_CONFIRMED("nav_discard_confirmed"),
    RECOVERY_COMPLETED("nav_recovery_completed")
}

object NavigationJourney {
    const val GOAL_CREATE_EDIT = "goal-create-edit"
    const val MONTHLY_BUDGET_ADJUST = "monthly-budget-adjust"
    const val DESTRUCTIVE_DELETE_CONFIRMATION = "destructive-delete-confirmation"
    const val GOAL_CONTRIBUTION_EDIT_CANCEL = "goal-contribution-edit-cancel"
    const val PLANNING_FLOW_CANCEL_RECOVERY = "planning-flow-cancel-recovery"

    val TOP_5: Set<String> = setOf(
        GOAL_CREATE_EDIT,
        MONTHLY_BUDGET_ADJUST,
        DESTRUCTIVE_DELETE_CONFIRMATION,
        GOAL_CONTRIBUTION_EDIT_CANCEL,
        PLANNING_FLOW_CANCEL_RECOVERY
    )
}

data class NavigationTelemetryPayload(
    val event: NavigationTelemetryEvent,
    val journeyId: String,
    val platform: String,
    val entryPoint: String? = null,
    val durationMs: Long? = null,
    val result: String? = null,
    val isDirty: Boolean? = null,
    val cancelStage: String? = null,
    val formType: String? = null,
    val recoveryPath: String? = null,
    val success: Boolean? = null
) {
    fun properties(): Map<String, String> {
        val values = linkedMapOf(
            "journey_id" to journeyId,
            "platform" to platform
        )
        entryPoint?.let { values["entry_point"] = it }
        durationMs?.let { values["duration_ms"] = it.toString() }
        result?.let { values["result"] = it }
        isDirty?.let { values["is_dirty"] = it.toString() }
        cancelStage?.let { values["cancel_stage"] = it }
        formType?.let { values["form_type"] = it }
        recoveryPath?.let { values["recovery_path"] = it }
        success?.let { values["success"] = it.toString() }
        return values
    }

    fun requiredFieldViolations(): List<String> {
        val required = when (event) {
            NavigationTelemetryEvent.FLOW_STARTED -> listOf("journey_id", "platform", "entry_point")
            NavigationTelemetryEvent.FLOW_COMPLETED -> listOf("journey_id", "platform", "duration_ms", "result")
            NavigationTelemetryEvent.CANCELLED -> listOf("journey_id", "platform", "is_dirty", "cancel_stage")
            NavigationTelemetryEvent.DISCARD_CONFIRMED -> listOf("journey_id", "platform", "form_type")
            NavigationTelemetryEvent.RECOVERY_COMPLETED -> listOf("journey_id", "platform", "recovery_path", "success")
        }
        val props = properties()
        return required.filter { key -> props[key].isNullOrBlank() }
    }
}

interface NavigationTelemetryProvider {
    fun track(payload: NavigationTelemetryPayload)
}

@Singleton
class LogcatNavigationTelemetryProvider @Inject constructor() : NavigationTelemetryProvider {
    override fun track(payload: NavigationTelemetryPayload) {
        val serialized = payload.properties()
            .toSortedMap()
            .entries
            .joinToString(separator = ",") { "${it.key}=${it.value}" }

        val violations = payload.requiredFieldViolations()
        if (violations.isNotEmpty()) {
            Log.w(
                "NavigationTelemetry",
                "[${payload.event.wireName}] schema_violation=${violations.joinToString("|")} $serialized"
            )
        }

        Log.i("NavigationTelemetry", "[${payload.event.wireName}] $serialized")
    }
}

@Singleton
class NavigationTelemetryTracker @Inject constructor(
    private val provider: NavigationTelemetryProvider
) {
    private val flowStartTimes: MutableMap<String, Long> = mutableMapOf()
    private val lastEventByFingerprint: MutableMap<String, Long> = mutableMapOf()

    var dedupeWindowMs: Long = 800L
    internal var clock: () -> Long = { System.currentTimeMillis() }

    fun flowStarted(journeyId: String, entryPoint: String) {
        flowStartTimes[journeyId] = clock()
        emit(
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.FLOW_STARTED,
                journeyId = journeyId,
                platform = "android",
                entryPoint = entryPoint
            )
        )
    }

    fun flowCompleted(journeyId: String, result: String = "success") {
        val now = clock()
        val startedAt = flowStartTimes.remove(journeyId) ?: now
        emit(
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.FLOW_COMPLETED,
                journeyId = journeyId,
                platform = "android",
                durationMs = (now - startedAt).coerceAtLeast(0L),
                result = result
            )
        )
    }

    fun cancelled(journeyId: String, isDirty: Boolean, cancelStage: String) {
        emit(
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.CANCELLED,
                journeyId = journeyId,
                platform = "android",
                isDirty = isDirty,
                cancelStage = cancelStage
            )
        )
    }

    fun discardConfirmed(journeyId: String, formType: String) {
        emit(
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.DISCARD_CONFIRMED,
                journeyId = journeyId,
                platform = "android",
                formType = formType
            )
        )
    }

    fun recoveryCompleted(journeyId: String, recoveryPath: String, success: Boolean) {
        emit(
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.RECOVERY_COMPLETED,
                journeyId = journeyId,
                platform = "android",
                recoveryPath = recoveryPath,
                success = success
            )
        )
    }

    private fun emit(payload: NavigationTelemetryPayload) {
        val now = clock()
        val fingerprint = buildString {
            append(payload.event.wireName)
            payload.properties()
                .toSortedMap()
                .forEach { (key, value) ->
                    append('|').append(key).append('=').append(value)
                }
        }

        val previous = lastEventByFingerprint[fingerprint]
        if (previous != null && (now - previous) < dedupeWindowMs) {
            return
        }

        lastEventByFingerprint[fingerprint] = now
        provider.track(payload)
    }
}
