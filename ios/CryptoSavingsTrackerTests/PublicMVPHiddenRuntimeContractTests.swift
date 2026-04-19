import Foundation
import Testing
@testable import CryptoSavingsTracker

struct PublicMVPHiddenRuntimeContractTests {
    @Test("Public MVP hidden runtime defaults automation and family sharing off")
    func publicMVPHiddenRuntimeDefaultsOff() throws {
        let root = repositoryRoot()
        let rollout = try readSource(root, "ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareRollout.swift")
        let runtime = try readSource(root, "ios/CryptoSavingsTracker/Utilities/MVPContainmentRuntime.swift")
        let notificationManager = try readSource(root, "ios/CryptoSavingsTracker/Utilities/NotificationManager.swift")
        let automationScheduler = try readSource(root, "ios/CryptoSavingsTracker/Services/AutomationScheduler.swift")
        let familyShareServices = try readSource(root, "ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift")

        #expect(runtime.contains("case publicMVP = \"release_mvp\""))
        #expect(runtime.contains("#if DEBUG\n        let processInfo = ProcessInfo.processInfo"))
        #expect(runtime.contains("if let explicit = HiddenRuntimeMode(rawValue: processInfo.environment[\"CST_RUNTIME_MODE\"] ?? \"\")"))
        #expect(runtime.contains("environment[\"VISUAL_CAPTURE_MODE\"] != nil"))
        #expect(runtime.contains("environment[\"VISUAL_CAPTURE_COMPONENT\"] != nil"))
        #expect(runtime.contains("return isTestHarness ? .debugInternal : .publicMVP"))
        #expect(runtime.contains("#else\n        return .publicMVP\n        #endif"))
        #expect(runtime.contains("var allowsFamilySharing"))
        #expect(rollout.contains("let releaseDefault = runtimeMode.hiddenRuntimeEnabledByDefault"))
        #expect(notificationManager.contains("var isReminderRuntimeSchedulingEnabled: Bool"))
        #expect(notificationManager.contains("var isNotificationPromptEnabled: Bool"))
        #expect(notificationManager.contains("var isAutomationSchedulerEnabled: Bool"))
        #expect(notificationManager.contains("guard isNotificationPromptEnabled else { return false }"))
        #expect(notificationManager.contains("await cancelNotifications(for: goal)"))
        #expect(notificationManager.contains("guard isReminderRuntimeSchedulingEnabled else { return }"))
        #expect(automationScheduler.contains("guard notificationManager.isAutomationSchedulerEnabled else { return }"))
        #expect(familyShareServices.contains("guard rollout.isEnabled() else {"))
        #expect(familyShareServices.contains("await teardownFreshnessPipelineIfNeeded()"))
        #expect(familyShareServices.contains("if rollout.isFreshnessPipelineEnabled(), freshnessPipelineActive == false {"))
        #expect(familyShareServices.contains("await startFreshnessPipeline()"))
    }

    @Test("Public MVP release build does not declare or compile camera access")
    func publicMVPReleaseDoesNotDeclareOrCompileCameraAccess() throws {
        let root = repositoryRoot()
        let infoPlist = try readSource(root, "ios/CryptoSavingsTracker/Info.plist")
        let localBridgeSyncView = try readSource(root, "ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift")
        let qrScannerView = try readSource(root, "ios/CryptoSavingsTracker/Views/Settings/LocalBridgeQRScannerView.swift")

        #expect(!infoPlist.contains("NSCameraUsageDescription"))
        #expect(qrScannerView.contains("#if DEBUG && os(iOS)"))
        #expect(localBridgeSyncView.contains("#elseif DEBUG\n        [.enterCodeManually, .scanQR, .pasteBootstrapToken]\n#else\n        [.enterCodeManually, .pasteBootstrapToken]\n#endif"))
        #expect(localBridgeSyncView.contains("#if DEBUG && os(iOS)\n        .sheet(isPresented: $presentsQRScanner)"))
        #expect(localBridgeSyncView.contains("#if DEBUG && os(iOS)\n            presentsQRScanner = true\n#else\n            pairingTokenInput = \"\""))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readSource(_ root: URL, _ relativePath: String) throws -> String {
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
