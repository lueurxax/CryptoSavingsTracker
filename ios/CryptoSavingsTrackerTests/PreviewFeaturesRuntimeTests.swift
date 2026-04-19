import Foundation
import Testing
@testable import CryptoSavingsTracker

struct PreviewFeaturesRuntimeTests {
    @Test("Preview Features opt-in switches retained runtime gates to internal mode")
    func previewFeaturesOptInSwitchesRetainedRuntimeGates() {
        let suiteName = "PreviewFeaturesRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(PreviewFeaturesRuntime.isEnabled(userDefaults: defaults) == false)
        #expect(HiddenRuntimeMode.resolved(environment: [:], arguments: [], userDefaults: defaults) == .publicMVP)

        PreviewFeaturesRuntime.setEnabled(true, userDefaults: defaults)

        let enabledMode = HiddenRuntimeMode.resolved(environment: [:], arguments: [], userDefaults: defaults)
        #expect(enabledMode == .debugInternal)
        #expect(enabledMode.allowsFamilySharing)
        #expect(enabledMode.allowsShortcuts)
        #expect(enabledMode.showsForecastModules)
    }

    @Test("Explicit runtime mode wins over Preview Features opt-in")
    func explicitRuntimeModeWinsOverPreviewFeaturesOptIn() {
        let suiteName = "PreviewFeaturesRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PreviewFeaturesRuntime.setEnabled(true, userDefaults: defaults)

        let explicitPublicMode = HiddenRuntimeMode.resolved(
            environment: ["CST_RUNTIME_MODE": HiddenRuntimeMode.publicMVP.rawValue],
            arguments: [],
            userDefaults: defaults
        )

        #expect(explicitPublicMode == .publicMVP)
    }
}
