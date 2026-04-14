import XCTest
@testable import CryptoSavingsTracker

@MainActor
final class FamilyShareProjectionMutationObserverTests: XCTestCase {
    private struct StubRemoteConfigProvider: FamilyShareRemoteConfigProviding {
        let values: [String: Bool]

        func boolValue(for key: String) -> Bool? {
            values[key]
        }
    }

    private struct RecordingTelemetryProvider: FamilyShareTelemetryProviding {
        func track(event: String, payload: [String: String]) {}
    }

    func testObserverDoesNotRegisterWhenPublicMVPHiddenRuntimeIsOff() async {
        let suiteName = "FamilyShareProjectionMutationObserverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let rollout = FamilyShareRollout(
            remoteConfigProvider: StubRemoteConfigProvider(values: [:]),
            telemetryProvider: RecordingTelemetryProvider(),
            userDefaults: defaults,
            runtimeMode: .publicMVP
        )
        let observer = FamilyShareProjectionMutationObserver(rollout: rollout)
        let expectation = expectation(description: "mutation ignored")
        expectation.isInverted = true

        observer.start { _ in
            expectation.fulfill()
        }

        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": [UUID()],
                "reason": "transactionMutation"
            ]
        )

        await fulfillment(of: [expectation], timeout: 0.2)
        observer.teardown()
    }
}
