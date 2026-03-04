import Foundation
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct VisualSystemRolloutTests {
    @Test("release default is false when no remote/debug value exists")
    func releaseDefaultFalse() {
        let userDefaults = UserDefaults(suiteName: "VisualSystemRolloutTests.releaseDefaultFalse")!
        userDefaults.removePersistentDomain(forName: "VisualSystemRolloutTests.releaseDefaultFalse")

        let telemetry = CapturingVisualSystemTelemetryProvider()
        let rollout = VisualSystemRollout(
            remoteConfigProvider: StaticRemoteConfig(values: [:]),
            telemetryProvider: telemetry,
            userDefaults: userDefaults,
            nowProvider: { Date(timeIntervalSince1970: 0) }
        )

        #expect(rollout.isEnabled(flow: .planning) == false)
        #expect(telemetry.events.first?.event == "vsu_flag_evaluated")
    }

    @Test("remote config overrides release default")
    func remoteConfigOverride() {
        let userDefaults = UserDefaults(suiteName: "VisualSystemRolloutTests.remoteConfigOverride")!
        userDefaults.removePersistentDomain(forName: "VisualSystemRolloutTests.remoteConfigOverride")

        let rollout = VisualSystemRollout(
            remoteConfigProvider: StaticRemoteConfig(values: [
                VisualSystemRollout.flagWave1Planning: true
            ]),
            telemetryProvider: CapturingVisualSystemTelemetryProvider(),
            userDefaults: userDefaults
        )

        #expect(rollout.isEnabled(flow: .planning) == true)
    }

    @Test("debug override has highest priority")
    func debugOverridePriority() {
        let userDefaults = UserDefaults(suiteName: "VisualSystemRolloutTests.debugOverridePriority")!
        userDefaults.removePersistentDomain(forName: "VisualSystemRolloutTests.debugOverridePriority")

        let rollout = VisualSystemRollout(
            remoteConfigProvider: StaticRemoteConfig(values: [
                VisualSystemRollout.flagWave1Planning: true
            ]),
            telemetryProvider: CapturingVisualSystemTelemetryProvider(),
            userDefaults: userDefaults
        )

        rollout.setDebugOverride(false, for: .planning)
        #expect(rollout.isEnabled(flow: .planning) == false)
    }

    @Test("rollback telemetry events are emitted on true-to-false transition")
    func rollbackTelemetryTransition() {
        let userDefaults = UserDefaults(suiteName: "VisualSystemRolloutTests.rollbackTelemetryTransition")!
        userDefaults.removePersistentDomain(forName: "VisualSystemRolloutTests.rollbackTelemetryTransition")

        let telemetry = CapturingVisualSystemTelemetryProvider()
        let rollout = VisualSystemRollout(
            remoteConfigProvider: StaticRemoteConfig(values: [
                VisualSystemRollout.flagWave1Planning: true
            ]),
            telemetryProvider: telemetry,
            userDefaults: userDefaults
        )

        _ = rollout.isEnabled(flow: .planning)
        rollout.setDebugOverride(false, for: .planning)
        _ = rollout.isEnabled(flow: .planning)

        let names = telemetry.events.map(\.event)
        #expect(names.contains("vsu_wave_rollback_triggered"))
        #expect(names.contains("vsu_wave_rollback_completed"))
    }
}

private struct StaticRemoteConfig: VisualSystemRemoteConfigProviding {
    let values: [String: Bool]

    func boolValue(for key: String) -> Bool? {
        values[key]
    }
}

private final class CapturingVisualSystemTelemetryProvider: VisualSystemTelemetryProviding {
    private(set) var events: [(event: String, payload: [String: String])] = []

    func track(event: String, payload: [String: String]) {
        events.append((event: event, payload: payload))
    }
}
