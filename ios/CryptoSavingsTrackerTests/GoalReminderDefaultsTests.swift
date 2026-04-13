import Foundation
import Testing
@testable import CryptoSavingsTracker

struct GoalReminderDefaultsTests {
    @Test("Goal defaults to reminders disabled for MVP-created goals")
    func goalDefaultsToNoReminderState() {
        let goal = Goal(
            name: "MVP Goal",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )

        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)
        #expect(goal.isReminderEnabled == false)
    }

    @Test("Goal still supports explicit legacy reminder configuration when requested")
    func goalAllowsExplicitReminderConfiguration() {
        let goal = Goal(
            name: "Legacy Goal",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400),
            frequency: .weekly
        )

        #expect(goal.reminderFrequency == ReminderFrequency.weekly.rawValue)
        #expect(goal.reminderTime != nil)
        #expect(goal.isReminderEnabled == true)
    }
}
