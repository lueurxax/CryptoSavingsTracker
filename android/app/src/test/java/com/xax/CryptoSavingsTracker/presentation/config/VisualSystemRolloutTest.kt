package com.xax.CryptoSavingsTracker.presentation.config

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VisualSystemRolloutTest {

    @Test
    fun releaseDefault_isFalse() {
        val telemetry = CapturingTelemetrySink()
        val rollout = VisualSystemRollout(
            remoteConfigAdapter = StaticRemoteConfig(emptyMap()),
            telemetrySink = telemetry,
            prefs = FakeSharedPreferences(),
            nowMillis = { 0L }
        )

        assertFalse(rollout.isEnabled(VisualSystemFlow.PLANNING))
        assertEquals("vsu_flag_evaluated", telemetry.events.first().event)
    }

    @Test
    fun remoteConfig_overridesReleaseDefault() {
        val rollout = VisualSystemRollout(
            remoteConfigAdapter = StaticRemoteConfig(
                mapOf(VisualSystemRollout.FLAG_WAVE1_PLANNING to true)
            ),
            telemetrySink = CapturingTelemetrySink(),
            prefs = FakeSharedPreferences()
        )

        assertTrue(rollout.isEnabled(VisualSystemFlow.PLANNING))
    }

    @Test
    fun debugOverride_hasHighestPriority() {
        val prefs = FakeSharedPreferences()
        val rollout = VisualSystemRollout(
            remoteConfigAdapter = StaticRemoteConfig(
                mapOf(VisualSystemRollout.FLAG_WAVE1_PLANNING to true)
            ),
            telemetrySink = CapturingTelemetrySink(),
            prefs = prefs
        )

        rollout.setDebugOverride(VisualSystemFlow.PLANNING, false)
        assertFalse(rollout.isEnabled(VisualSystemFlow.PLANNING))
    }

    @Test
    fun rollbackEvents_emittedOnTrueToFalseTransition() {
        val telemetry = CapturingTelemetrySink()
        val rollout = VisualSystemRollout(
            remoteConfigAdapter = StaticRemoteConfig(
                mapOf(VisualSystemRollout.FLAG_WAVE1_PLANNING to true)
            ),
            telemetrySink = telemetry,
            prefs = FakeSharedPreferences()
        )

        assertTrue(rollout.isEnabled(VisualSystemFlow.PLANNING))
        rollout.setDebugOverride(VisualSystemFlow.PLANNING, false)
        assertFalse(rollout.isEnabled(VisualSystemFlow.PLANNING))

        val names = telemetry.events.map { it.event }
        assertTrue(names.contains("vsu_wave_rollback_triggered"))
        assertTrue(names.contains("vsu_wave_rollback_completed"))
    }

    private data class TelemetryEvent(val event: String, val payload: Map<String, String>)

    private class CapturingTelemetrySink : VisualSystemTelemetrySink {
        val events: MutableList<TelemetryEvent> = mutableListOf()

        override fun track(event: String, payload: Map<String, String>) {
            events += TelemetryEvent(event, payload)
        }
    }

    private class StaticRemoteConfig(
        private val values: Map<String, Boolean>
    ) : VisualSystemRemoteConfigAdapter {
        override fun boolValue(key: String): Boolean? = values[key]
    }

    private class FakeSharedPreferences : SharedPreferences {
        private val map = mutableMapOf<String, Any>()

        override fun getAll(): MutableMap<String, *> = map

        override fun getString(key: String?, defValue: String?): String? {
            val value = map[key] as? String
            return value ?: defValue
        }

        override fun getStringSet(
            key: String?,
            defValues: MutableSet<String>?
        ): MutableSet<String>? {
            @Suppress("UNCHECKED_CAST")
            val value = map[key] as? MutableSet<String>
            return value ?: defValues
        }

        override fun getInt(key: String?, defValue: Int): Int {
            return map[key] as? Int ?: defValue
        }

        override fun getLong(key: String?, defValue: Long): Long {
            return map[key] as? Long ?: defValue
        }

        override fun getFloat(key: String?, defValue: Float): Float {
            return map[key] as? Float ?: defValue
        }

        override fun getBoolean(key: String?, defValue: Boolean): Boolean {
            return map[key] as? Boolean ?: defValue
        }

        override fun contains(key: String?): Boolean = map.containsKey(key)

        override fun edit(): SharedPreferences.Editor = EditorImpl(map)

        override fun registerOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?
        ) = Unit

        override fun unregisterOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?
        ) = Unit
    }

    private class EditorImpl(
        private val map: MutableMap<String, Any>
    ) : SharedPreferences.Editor {
        override fun putString(key: String?, value: String?): SharedPreferences.Editor {
            if (key != null && value != null) map[key] = value
            return this
        }

        override fun putStringSet(
            key: String?,
            values: MutableSet<String>?
        ): SharedPreferences.Editor {
            if (key != null && values != null) map[key] = values
            return this
        }

        override fun putInt(key: String?, value: Int): SharedPreferences.Editor {
            if (key != null) map[key] = value
            return this
        }

        override fun putLong(key: String?, value: Long): SharedPreferences.Editor {
            if (key != null) map[key] = value
            return this
        }

        override fun putFloat(key: String?, value: Float): SharedPreferences.Editor {
            if (key != null) map[key] = value
            return this
        }

        override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor {
            if (key != null) map[key] = value
            return this
        }

        override fun remove(key: String?): SharedPreferences.Editor {
            if (key != null) map.remove(key)
            return this
        }

        override fun clear(): SharedPreferences.Editor {
            map.clear()
            return this
        }

        override fun commit(): Boolean = true

        override fun apply() = Unit
    }
}
