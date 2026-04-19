import Testing
@testable import CryptoSavingsTracker

@MainActor
struct CloudKitHealthMonitorTests {
    @Test("CloudKit monitor skips CloudKit access in UI test launches")
    func cloudKitMonitorSkipsUITestLaunches() {
        let uiTestContext = BootstrapLaunchContext(
            arguments: ["CryptoSavingsTracker", "UITEST_UI_FLOW"],
            environment: [:]
        )

        #expect(CloudKitHealthMonitor.shouldSkipCloudKitAccess(for: uiTestContext))
    }

    @Test("CloudKit monitor allows CloudKit access in production launches")
    func cloudKitMonitorAllowsProductionLaunches() {
        let productionContext = BootstrapLaunchContext(
            arguments: ["CryptoSavingsTracker"],
            environment: [:]
        )

        #expect(!CloudKitHealthMonitor.shouldSkipCloudKitAccess(for: productionContext))
    }
}
