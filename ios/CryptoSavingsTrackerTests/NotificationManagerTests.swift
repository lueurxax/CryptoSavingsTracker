import UserNotifications
import XCTest
@testable import CryptoSavingsTracker

@MainActor
final class NotificationManagerTests: XCTestCase {
    @MainActor
    private final class SpyNotificationManager: NotificationManager {
        var requestAuthorizationCallCount = 0
        var addedRequests: [UNNotificationRequest] = []
        var removedIdentifiers: [String] = []
        var stubPendingRequests: [UNNotificationRequest] = []

        init(runtimeMode: HiddenRuntimeMode) {
            super.init(runtimeMode: runtimeMode, isUITestRunProvider: { false })
        }

        override func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
            requestAuthorizationCallCount += 1
            return true
        }

        override func pendingNotificationRequests() async -> [UNNotificationRequest] {
            stubPendingRequests
        }

        override func addPendingNotificationRequest(_ request: UNNotificationRequest) async throws {
            addedRequests.append(request)
        }

        override func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
            removedIdentifiers.append(contentsOf: identifiers)
        }
    }

    func testRequestPermissionSkipsAuthorizationWhenPublicMVPHiddenRuntimeIsOff() async {
        let manager = SpyNotificationManager(runtimeMode: .publicMVP)

        let granted = await manager.requestPermission()

        XCTAssertFalse(granted)
        XCTAssertEqual(manager.requestAuthorizationCallCount, 0)
    }

    func testScheduleRemindersCancelsExistingRequestsButDoesNotCreateNewOnesInPublicMVP() async {
        let manager = SpyNotificationManager(runtimeMode: .publicMVP)
        let goal = TestDataFactory.createSampleGoal(name: "Reminder Goal")
        let futureDate = Date().addingTimeInterval(3600)
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = futureDate
        goal.firstReminderDate = futureDate

        manager.stubPendingRequests = [
            makeRequest(identifier: "\(goal.id.uuidString)-reminder-existing"),
            makeRequest(identifier: "unrelated")
        ]

        await manager.scheduleReminders(for: goal)

        XCTAssertEqual(manager.removedIdentifiers, ["\(goal.id.uuidString)-reminder-existing"])
        XCTAssertTrue(manager.addedRequests.isEmpty)
    }

    private func makeRequest(identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: identifier,
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        )
    }
}
