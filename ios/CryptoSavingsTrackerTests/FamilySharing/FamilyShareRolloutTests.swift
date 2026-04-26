import XCTest
@testable import CryptoSavingsTracker

final class FamilyShareRolloutTests: XCTestCase {
    private struct StubRemoteConfigProvider: FamilyShareRemoteConfigProviding {
        let values: [String: Bool]

        func boolValue(for key: String) -> Bool? {
            values[key]
        }
    }

    private struct RecordingTelemetryProvider: FamilyShareTelemetryProviding {
        func track(event: String, payload: [String: String]) {}
    }

    func testPublicMVPModeDefaultsFamilySharingOff() {
        let suiteName = "FamilyShareRolloutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let rollout = FamilyShareRollout(
            remoteConfigProvider: StubRemoteConfigProvider(values: [:]),
            telemetryProvider: RecordingTelemetryProvider(),
            userDefaults: defaults,
            runtimeMode: .publicMVP
        )

        XCTAssertFalse(rollout.isEnabled())
        XCTAssertFalse(rollout.isFreshnessPipelineEnabled())
        XCTAssertEqual(FamilyShareTelemetryRedactor.coarseReason(for: "assetMutation"), "assetmutation")
        XCTAssertEqual(FamilyShareTelemetryRedactor.coarseReason(for: "manualRefresh"), "manualrefresh")
    }

    func testPublicMVPModeStillHonorsExplicitDebugOverride() {
        let suiteName = "FamilyShareRolloutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let rollout = FamilyShareRollout(
            remoteConfigProvider: StubRemoteConfigProvider(values: [:]),
            telemetryProvider: RecordingTelemetryProvider(),
            userDefaults: defaults,
            runtimeMode: .publicMVP
        )
        rollout.setDebugOverride(true)

        XCTAssertTrue(rollout.isEnabled())
        XCTAssertTrue(rollout.isFreshnessPipelineEnabled())
    }
}
