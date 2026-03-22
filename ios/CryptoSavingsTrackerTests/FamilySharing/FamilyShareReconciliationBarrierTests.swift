import XCTest
@testable import CryptoSavingsTracker

@MainActor
final class FamilyShareReconciliationBarrierTests: XCTestCase {
    private final class TestClock: FamilyShareClock, @unchecked Sendable {
        var currentDate: Date

        init(currentDate: Date) {
            self.currentDate = currentDate
        }

        func now() -> Date {
            currentDate
        }
    }

    private final class ControlledScheduler: FamilyShareScheduler, @unchecked Sendable {
        private final class Token: FamilyShareCancellable {
            func cancel() {}
        }

        private(set) var scheduledDebounceCount = 0
        private var scheduledAction: (@Sendable () async -> Void)?

        func scheduleDebounce(delay: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable {
            scheduledDebounceCount += 1
            scheduledAction = action
            return Token()
        }

        func schedulePeriodic(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable {
            Token()
        }

        func waitUntilScheduled(timeoutNs: UInt64 = 1_000_000_000) async {
            let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNs))
            while scheduledDebounceCount == 0 && ContinuousClock.now < deadline {
                await Task.yield()
            }
        }

        func fireScheduledAction() async {
            await scheduledAction?()
        }
    }

    override func setUp() {
        super.setUp()
        FamilyShareReconciliationBarrier.resetObservedImportsForTesting()
    }

    override func tearDown() {
        FamilyShareReconciliationBarrier.resetObservedImportsForTesting()
        super.tearDown()
    }

    func testNilRemoteDateIsSatisfiedImmediately() async {
        let barrier = FamilyShareReconciliationBarrier(
            clock: TestClock(currentDate: Date()),
            scheduler: ControlledScheduler()
        )

        let result = await barrier.checkBarrier(lastKnownRemoteChangeDate: nil)
        guard case let .satisfied(waitDurationMs, importCompleted) = result else {
            return XCTFail("Nil remote date should satisfy the barrier immediately")
        }
        XCTAssertEqual(waitDurationMs, 0)
        XCTAssertFalse(importCompleted)
    }

    func testMissingImportTimesOutAfterSchedulerFires() async {
        let now = Date()
        let clock = TestClock(currentDate: now)
        let scheduler = ControlledScheduler()
        let barrier = FamilyShareReconciliationBarrier(clock: clock, scheduler: scheduler)

        let remoteDate = now
        let task = Task { await barrier.checkBarrier(lastKnownRemoteChangeDate: remoteDate) }
        await scheduler.waitUntilScheduled()
        clock.currentDate = now.addingTimeInterval(FamilyShareFreshnessPolicy.importFenceTimeout)
        await scheduler.fireScheduledAction()
        let result = await task.value

        guard case let .timedOut(_, waitDurationMs) = result else {
            return XCTFail("Expected timeout when no import arrives")
        }
        XCTAssertEqual(waitDurationMs, Int(FamilyShareFreshnessPolicy.importFenceTimeout * 1000))
    }

    func testImportEventBeforeTimeoutSatisfiesBarrier() async {
        let now = Date()
        let clock = TestClock(currentDate: now)
        let scheduler = ControlledScheduler()
        let barrier = FamilyShareReconciliationBarrier(clock: clock, scheduler: scheduler)

        let remoteDate = now
        let task = Task { await barrier.checkBarrier(lastKnownRemoteChangeDate: remoteDate) }

        await scheduler.waitUntilScheduled()
        FamilyShareReconciliationBarrier.recordImportObservedForTesting(at: now.addingTimeInterval(1))
        clock.currentDate = now.addingTimeInterval(1)
        await scheduler.fireScheduledAction()
        let result = await task.value

        guard case let .satisfied(waitDurationMs, importCompleted) = result else {
            return XCTFail("Import completion should satisfy the barrier")
        }
        XCTAssertEqual(waitDurationMs, 1000)
        XCTAssertTrue(importCompleted)
    }
}
