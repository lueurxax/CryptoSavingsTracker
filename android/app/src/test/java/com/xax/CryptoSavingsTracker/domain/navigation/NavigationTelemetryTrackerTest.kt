package com.xax.CryptoSavingsTracker.domain.navigation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NavigationTelemetryTrackerTest {

    @Test
    fun payloadCompleteness_perEventContract() {
        val payloads = listOf(
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.FLOW_STARTED,
                journeyId = NavigationJourney.GOAL_CREATE_EDIT,
                platform = "android",
                entryPoint = "screen"
            ),
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.FLOW_COMPLETED,
                journeyId = NavigationJourney.GOAL_CREATE_EDIT,
                platform = "android",
                durationMs = 150,
                result = "saved"
            ),
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.CANCELLED,
                journeyId = NavigationJourney.GOAL_CREATE_EDIT,
                platform = "android",
                isDirty = true,
                cancelStage = "back"
            ),
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.DISCARD_CONFIRMED,
                journeyId = NavigationJourney.GOAL_CREATE_EDIT,
                platform = "android",
                formType = "goal_form"
            ),
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.RECOVERY_COMPLETED,
                journeyId = NavigationJourney.PLANNING_FLOW_CANCEL_RECOVERY,
                platform = "android",
                recoveryPath = "validation",
                success = true
            ),
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.GOAL_DASHBOARD_OPENED,
                journeyId = NavigationJourney.GOAL_DASHBOARD,
                platform = "android",
                entryPoint = "goal_detail",
                goalId = "goal-1"
            ),
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.GOAL_DASHBOARD_PRIMARY_CTA_SHOWN,
                journeyId = NavigationJourney.GOAL_DASHBOARD,
                platform = "android",
                goalId = "goal-1",
                resolverState = "on_track",
                ctaId = "log_contribution"
            ),
            NavigationTelemetryPayload(
                event = NavigationTelemetryEvent.GOAL_DASHBOARD_PRIMARY_CTA_TAPPED,
                journeyId = NavigationJourney.GOAL_DASHBOARD,
                platform = "android",
                goalId = "goal-1",
                resolverState = "on_track",
                ctaId = "log_contribution"
            )
        )

        payloads.forEach { payload ->
            assertTrue(payload.requiredFieldViolations().isEmpty())
        }
    }

    @Test
    fun flowCompleted_containsDurationFromStart() {
        val provider = CapturingProvider()
        val tracker = NavigationTelemetryTracker(provider)
        var now = 1_000L
        tracker.clock = { now }
        tracker.dedupeWindowMs = 0

        tracker.flowStarted(NavigationJourney.MONTHLY_BUDGET_ADJUST, "sheet")
        now = 2_550L
        tracker.flowCompleted(NavigationJourney.MONTHLY_BUDGET_ADJUST, "saved")

        val completed = provider.payloads.first { it.event == NavigationTelemetryEvent.FLOW_COMPLETED }
        assertEquals(1550L, completed.durationMs)
    }

    @Test
    fun duplicateEvents_areSuppressedInsideDedupeWindow() {
        val provider = CapturingProvider()
        val tracker = NavigationTelemetryTracker(provider)
        var now = 10_000L
        tracker.clock = { now }
        tracker.dedupeWindowMs = 800L

        tracker.cancelled(NavigationJourney.GOAL_CREATE_EDIT, true, "back")
        tracker.cancelled(NavigationJourney.GOAL_CREATE_EDIT, true, "back")

        now = 10_900L
        tracker.cancelled(NavigationJourney.GOAL_CREATE_EDIT, true, "back")

        val cancelledEvents = provider.payloads.filter { it.event == NavigationTelemetryEvent.CANCELLED }
        assertEquals(2, cancelledEvents.size)
    }

    @Test
    fun goalDashboardTelemetryEvents_areEmitted() {
        val provider = CapturingProvider()
        val tracker = NavigationTelemetryTracker(provider)
        tracker.dedupeWindowMs = 0

        tracker.goalDashboardOpened(goalId = "goal-1", entryPoint = "goal_detail")
        tracker.goalDashboardPrimaryCtaShown(
            goalId = "goal-1",
            resolverState = "on_track",
            ctaId = "log_contribution"
        )
        tracker.goalDashboardPrimaryCtaTapped(
            goalId = "goal-1",
            resolverState = "on_track",
            ctaId = "log_contribution"
        )

        assertTrue(provider.payloads.any { it.event == NavigationTelemetryEvent.GOAL_DASHBOARD_OPENED })
        assertTrue(provider.payloads.any { it.event == NavigationTelemetryEvent.GOAL_DASHBOARD_PRIMARY_CTA_SHOWN })
        assertTrue(provider.payloads.any { it.event == NavigationTelemetryEvent.GOAL_DASHBOARD_PRIMARY_CTA_TAPPED })
    }

    private class CapturingProvider : NavigationTelemetryProvider {
        val payloads: MutableList<NavigationTelemetryPayload> = mutableListOf()

        override fun track(payload: NavigationTelemetryPayload) {
            payloads.add(payload)
        }
    }
}
