import SwiftData
import XCTest
@testable import CryptoSavingsTracker

@MainActor
final class AutomationSchedulerTests: XCTestCase {
    @MainActor
    private final class SpyNotificationManager: NotificationManager {
        var requestPermissionCallCount = 0

        init(runtimeMode: HiddenRuntimeMode) {
            super.init(runtimeMode: runtimeMode, isUITestRunProvider: { false })
        }

        override func requestPermission() async -> Bool {
            requestPermissionCallCount += 1
            return true
        }
    }

    func testScheduleAutomationNotificationsReturnsBeforeRequestPermissionInPublicMVP() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let settings = MonthlyPlanningSettings()
        settings.autoStartEnabled = true
        settings.autoCompleteEnabled = true
        let notificationManager = SpyNotificationManager(runtimeMode: .publicMVP)
        let scheduler = AutomationScheduler(
            settings: settings,
            notificationManager: notificationManager,
            modelContext: context
        )

        try await scheduler.scheduleAutomationNotifications()

        XCTAssertEqual(notificationManager.requestPermissionCallCount, 0)
    }
}
