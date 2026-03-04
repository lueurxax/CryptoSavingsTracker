package com.xax.CryptoSavingsTracker.presentation.config

import android.content.Context
import android.content.SharedPreferences
import android.util.Log

enum class VisualSystemFlow(
    val flowName: String,
    val waveName: String,
    val flagKey: String
) {
    PLANNING(
        flowName = "planning",
        waveName = "wave1",
        flagKey = VisualSystemRollout.FLAG_WAVE1_PLANNING
    ),
    DASHBOARD(
        flowName = "dashboard",
        waveName = "wave2",
        flagKey = VisualSystemRollout.FLAG_WAVE2_DASHBOARD
    ),
    SETTINGS(
        flowName = "settings",
        waveName = "wave3",
        flagKey = VisualSystemRollout.FLAG_WAVE3_SETTINGS
    )
}

interface VisualSystemRemoteConfigAdapter {
    fun boolValue(key: String): Boolean?
}

class NullVisualSystemRemoteConfigAdapter : VisualSystemRemoteConfigAdapter {
    override fun boolValue(key: String): Boolean? = null
}

interface VisualSystemTelemetrySink {
    fun track(event: String, payload: Map<String, String>)
}

class LogcatVisualSystemTelemetrySink : VisualSystemTelemetrySink {
    override fun track(event: String, payload: Map<String, String>) {
        val serialized = payload.toSortedMap().entries.joinToString(",") { "${it.key}=${it.value}" }
        Log.i("VisualSystemRollout", "[$event] $serialized")
    }
}

class VisualSystemRollout(
    private val remoteConfigAdapter: VisualSystemRemoteConfigAdapter,
    private val telemetrySink: VisualSystemTelemetrySink,
    private val prefs: SharedPreferences,
    private val nowMillis: () -> Long = { System.currentTimeMillis() }
) {
    companion object {
        const val FLAG_WAVE1_PLANNING = "visual_system.wave1_planning"
        const val FLAG_WAVE2_DASHBOARD = "visual_system.wave2_dashboard"
        const val FLAG_WAVE3_SETTINGS = "visual_system.wave3_settings"
        private const val PREFS_NAME = "visual_system_rollout"
        private const val DEBUG_PREFIX = "visual_system.debug_override."

        fun from(
            context: Context,
            remoteConfigAdapter: VisualSystemRemoteConfigAdapter = NullVisualSystemRemoteConfigAdapter(),
            telemetrySink: VisualSystemTelemetrySink = LogcatVisualSystemTelemetrySink()
        ): VisualSystemRollout {
            return VisualSystemRollout(
                remoteConfigAdapter = remoteConfigAdapter,
                telemetrySink = telemetrySink,
                prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            )
        }
    }

    private enum class Source(val wireName: String) {
        RELEASE_DEFAULT("release_default"),
        REMOTE_CONFIG("remote_config"),
        DEBUG_OVERRIDE("debug_override")
    }

    private val releaseDefaults: Map<VisualSystemFlow, Boolean> = mapOf(
        VisualSystemFlow.PLANNING to false,
        VisualSystemFlow.DASHBOARD to false,
        VisualSystemFlow.SETTINGS to false
    )
    private val lastEvaluatedValues: MutableMap<VisualSystemFlow, Boolean> = mutableMapOf()

    fun isEnabled(flow: VisualSystemFlow): Boolean {
        val (value, source) = resolveValue(flow)
        emit("vsu_flag_evaluated", flow, source)

        val previous = lastEvaluatedValues[flow]
        if (previous == true && !value) {
            emit("vsu_wave_rollback_triggered", flow, source)
            emit("vsu_wave_rollback_completed", flow, source)
        }
        lastEvaluatedValues[flow] = value
        return value
    }

    fun setDebugOverride(flow: VisualSystemFlow, value: Boolean?) {
        val key = debugKey(flow)
        prefs.edit().apply {
            if (value == null) remove(key) else putBoolean(key, value)
        }.apply()
    }

    private fun resolveValue(flow: VisualSystemFlow): Pair<Boolean, Source> {
        var value = releaseDefaults[flow] ?: false
        var source = Source.RELEASE_DEFAULT

        remoteConfigAdapter.boolValue(flow.flagKey)?.let {
            value = it
            source = Source.REMOTE_CONFIG
        }

        if (prefs.contains(debugKey(flow))) {
            value = prefs.getBoolean(debugKey(flow), value)
            source = Source.DEBUG_OVERRIDE
        }
        return value to source
    }

    private fun debugKey(flow: VisualSystemFlow): String = "$DEBUG_PREFIX${flow.flagKey}"

    private fun emit(event: String, flow: VisualSystemFlow, source: Source) {
        telemetrySink.track(
            event = event,
            payload = mapOf(
                "wave" to flow.waveName,
                "flow" to flow.flowName,
                "source" to source.wireName,
                "timestamp" to nowMillis().toString()
            )
        )
    }
}
