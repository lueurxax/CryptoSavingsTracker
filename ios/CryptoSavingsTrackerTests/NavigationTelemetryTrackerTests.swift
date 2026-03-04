import Testing
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct NavigationTelemetryTrackerTests {

    @Test("payload required fields are complete per contract")
    func payloadCompleteness() {
        let samples: [NavigationTelemetryPayload] = [
            NavigationTelemetryPayload(
                event: .flowStarted,
                journeyID: NavigationJourney.goalCreateEdit,
                platform: "ios",
                entryPoint: "unit_test",
                durationMs: nil,
                result: nil,
                isDirty: nil,
                cancelStage: nil,
                formType: nil,
                recoveryPath: nil,
                success: nil
            ),
            NavigationTelemetryPayload(
                event: .flowCompleted,
                journeyID: NavigationJourney.goalCreateEdit,
                platform: "ios",
                entryPoint: nil,
                durationMs: 123,
                result: "saved",
                isDirty: nil,
                cancelStage: nil,
                formType: nil,
                recoveryPath: nil,
                success: nil
            ),
            NavigationTelemetryPayload(
                event: .cancelled,
                journeyID: NavigationJourney.goalCreateEdit,
                platform: "ios",
                entryPoint: nil,
                durationMs: nil,
                result: nil,
                isDirty: true,
                cancelStage: "toolbar_cancel",
                formType: nil,
                recoveryPath: nil,
                success: nil
            ),
            NavigationTelemetryPayload(
                event: .discardConfirmed,
                journeyID: NavigationJourney.goalCreateEdit,
                platform: "ios",
                entryPoint: nil,
                durationMs: nil,
                result: nil,
                isDirty: nil,
                cancelStage: nil,
                formType: "goal_edit",
                recoveryPath: nil,
                success: nil
            ),
            NavigationTelemetryPayload(
                event: .recoveryCompleted,
                journeyID: NavigationJourney.planningFlowCancelRecovery,
                platform: "ios",
                entryPoint: nil,
                durationMs: nil,
                result: nil,
                isDirty: nil,
                cancelStage: nil,
                formType: nil,
                recoveryPath: "validation_fix",
                success: true
            ),
            NavigationTelemetryPayload(
                event: .goalDashboardOpened,
                journeyID: NavigationJourney.goalDashboard,
                platform: "ios",
                entryPoint: "goal_detail",
                durationMs: nil,
                result: nil,
                isDirty: nil,
                cancelStage: nil,
                formType: nil,
                recoveryPath: nil,
                success: nil,
                goalID: "goal-1",
                resolverState: nil,
                ctaID: nil
            ),
            NavigationTelemetryPayload(
                event: .goalDashboardPrimaryCtaShown,
                journeyID: NavigationJourney.goalDashboard,
                platform: "ios",
                entryPoint: nil,
                durationMs: nil,
                result: nil,
                isDirty: nil,
                cancelStage: nil,
                formType: nil,
                recoveryPath: nil,
                success: nil,
                goalID: "goal-1",
                resolverState: "on_track",
                ctaID: "log_contribution"
            ),
            NavigationTelemetryPayload(
                event: .goalDashboardPrimaryCtaTapped,
                journeyID: NavigationJourney.goalDashboard,
                platform: "ios",
                entryPoint: nil,
                durationMs: nil,
                result: nil,
                isDirty: nil,
                cancelStage: nil,
                formType: nil,
                recoveryPath: nil,
                success: nil,
                goalID: "goal-1",
                resolverState: "on_track",
                ctaID: "log_contribution"
            )
        ]

        for payload in samples {
            #expect(payload.requiredFieldViolations().isEmpty)
        }
    }

    @Test("flow completion includes duration from tracked start time")
    func durationSemantics() {
        var now = Date(timeIntervalSince1970: 1000)
        let provider = CapturingTelemetryProvider()
        let tracker = NavigationTelemetryTracker(
            provider: provider,
            clock: { now },
            dedupeWindowMs: 0
        )

        tracker.flowStarted(journeyID: NavigationJourney.monthlyBudgetAdjust, entryPoint: "sheet")
        now = Date(timeIntervalSince1970: 1001.5)
        tracker.flowCompleted(journeyID: NavigationJourney.monthlyBudgetAdjust, result: "saved")

        let completed = provider.payloads.first(where: { $0.event == .flowCompleted })
        #expect(completed != nil)
        #expect(completed?.durationMs == 1500)
    }

    @Test("dedupe suppresses rapid duplicate events")
    func dedupeSemantics() {
        let start = Date(timeIntervalSince1970: 1000)
        var now = start
        let provider = CapturingTelemetryProvider()
        let tracker = NavigationTelemetryTracker(
            provider: provider,
            clock: { now },
            dedupeWindowMs: 800
        )

        tracker.cancelled(
            journeyID: NavigationJourney.goalCreateEdit,
            isDirty: true,
            cancelStage: "toolbar_cancel"
        )
        tracker.cancelled(
            journeyID: NavigationJourney.goalCreateEdit,
            isDirty: true,
            cancelStage: "toolbar_cancel"
        )

        now = start.addingTimeInterval(1.0)
        tracker.cancelled(
            journeyID: NavigationJourney.goalCreateEdit,
            isDirty: true,
            cancelStage: "toolbar_cancel"
        )

        let cancelled = provider.payloads.filter { $0.event == .cancelled }
        #expect(cancelled.count == 2)
    }

    @Test("goal dashboard telemetry proxy emits all required events")
    func goalDashboardProxyEvents() {
        let provider = CapturingTelemetryProvider()
        let tracker = NavigationTelemetryTracker(provider: provider, dedupeWindowMs: 0)

        tracker.goalDashboardOpened(goalID: "goal-1", entryPoint: "goal_detail")
        tracker.goalDashboardPrimaryCtaShown(goalID: "goal-1", resolverState: "on_track", ctaID: "log_contribution")
        tracker.goalDashboardPrimaryCtaTapped(goalID: "goal-1", resolverState: "on_track", ctaID: "log_contribution")

        #expect(provider.payloads.contains(where: { $0.event == .goalDashboardOpened }))
        #expect(provider.payloads.contains(where: { $0.event == .goalDashboardPrimaryCtaShown }))
        #expect(provider.payloads.contains(where: { $0.event == .goalDashboardPrimaryCtaTapped }))
    }
}

private final class CapturingTelemetryProvider: NavigationTelemetryProvider {
    private(set) var payloads: [NavigationTelemetryPayload] = []

    func track(_ payload: NavigationTelemetryPayload) {
        payloads.append(payload)
    }
}
