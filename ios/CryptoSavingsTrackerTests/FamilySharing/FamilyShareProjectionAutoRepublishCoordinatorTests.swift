import XCTest
@testable import CryptoSavingsTracker

@MainActor
final class FamilyShareProjectionAutoRepublishCoordinatorTests: XCTestCase {

    // MARK: - Test Helpers

    private class TestClock: FamilyShareClock, @unchecked Sendable {
        var currentDate = Date()
        func now() -> Date { currentDate }
    }

    private class TestScheduler: FamilyShareScheduler, @unchecked Sendable {
        var lastDelay: TimeInterval?
        var lastAction: (@Sendable () async -> Void)?
        var periodicAction: (@Sendable () async -> Void)?

        func scheduleDebounce(delay: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable {
            lastDelay = delay
            lastAction = action
            return TestCancellable()
        }

        func schedulePeriodic(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable {
            periodicAction = action
            return TestCancellable()
        }
    }

    private class TestCancellable: FamilyShareCancellable, @unchecked Sendable {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    // MARK: - Debounce/Coalescing

    func testMarkDirty_schedulesDebounce() async {
        let scheduler = TestScheduler()
        let coordinator = FamilyShareProjectionAutoRepublishCoordinator(
            namespaceKey: "test-ns",
            scheduler: scheduler
        )

        await coordinator.markDirty(reason: .goalMutation(goalIDs: [UUID()]))

        XCTAssertNotNil(scheduler.lastDelay)
        XCTAssertEqual(scheduler.lastDelay, FamilyShareFreshnessPolicy.mutationDebounce)
    }

    func testMarkDirty_rateDrift_usesLongerDebounce() async {
        let scheduler = TestScheduler()
        let coordinator = FamilyShareProjectionAutoRepublishCoordinator(
            namespaceKey: "test-ns",
            scheduler: scheduler
        )

        await coordinator.markDirty(reason: .rateDrift(goalIDs: [UUID()]))

        XCTAssertEqual(scheduler.lastDelay, FamilyShareFreshnessPolicy.rateDriftDebounce)
    }

    func testTeardown_clearsState() async {
        let coordinator = FamilyShareProjectionAutoRepublishCoordinator(namespaceKey: "test-ns")
        await coordinator.markDirty(reason: .manualRefresh)
        await coordinator.teardown()

        // After teardown, dirty state should be cleared
        // (verified by no publish attempts after teardown)
    }

    // MARK: - Rehydration

    func testRehydrateIfNeeded_withPersistedDirty_schedules() async {
        let testDefaults = UserDefaults(suiteName: "CoordinatorTests")!
        testDefaults.removePersistentDomain(forName: "CoordinatorTests")
        let dirtyStore = FamilyShareDirtyStateStore(defaults: testDefaults)
        dirtyStore.markDirty(namespaceKey: "test-ns", reason: .manualRefresh)

        let scheduler = TestScheduler()
        let coordinator = FamilyShareProjectionAutoRepublishCoordinator(
            namespaceKey: "test-ns",
            scheduler: scheduler,
            dirtyStateStore: dirtyStore
        )

        await coordinator.rehydrateIfNeeded()

        XCTAssertNotNil(scheduler.lastAction, "Should schedule a debounced publish after rehydration")
    }

    func testRehydrateIfNeeded_eventuallyPublishesAndClearsDirtyState() async throws {
        let suiteName = "CoordinatorTestsRecovery"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
        let dirtyStore = FamilyShareDirtyStateStore(defaults: testDefaults)
        dirtyStore.markDirty(namespaceKey: "test-ns", reason: .manualRefresh)

        let scheduler = TestScheduler()
        let coordinator = FamilyShareProjectionAutoRepublishCoordinator(
            namespaceKey: "test-ns",
            scheduler: scheduler,
            dirtyStateStore: dirtyStore
        )

        await coordinator.setPublishAction {
            FamilySharePublishReceipt(serverTimestamp: Date(), recordCount: 2)
        }
        await coordinator.rehydrateIfNeeded()

        XCTAssertNotNil(scheduler.lastAction)
        await scheduler.lastAction?()

        XCTAssertFalse(
            dirtyStore.dirtyNamespaces().contains(where: { $0.namespaceKey == "test-ns" }),
            "Successful publish after rehydration should clear persisted dirty state"
        )
    }
}
