import XCTest
@testable import CryptoSavingsTracker

@MainActor
final class FamilyShareInviteeRefreshSchedulerTests: XCTestCase {
    private final class TestClock: FamilyShareClock, @unchecked Sendable {
        var currentDate = Date()
        func now() -> Date { currentDate }
    }

    private final class TestScheduler: FamilyShareScheduler, @unchecked Sendable {
        var lastDelay: TimeInterval?
        private var scheduledDebounce: (@Sendable () async -> Void)?

        func scheduleDebounce(delay: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable {
            lastDelay = delay
            scheduledDebounce = action
            return TestCancellable()
        }

        func schedulePeriodic(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable {
            TestCancellable()
        }

        func fireDebounce() async {
            await scheduledDebounce?()
        }
    }

    private struct TestCancellable: FamilyShareCancellable {
        func cancel() {}
    }

    private func flushAsyncWork(iterations: Int = 10) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    func testManualRefreshWithinCooldownSetsCooldownAndSkipsSecondRequest() async {
        let clock = TestClock()
        let scheduler = TestScheduler()
        let sut = FamilyShareInviteeRefreshScheduler(clock: clock, scheduler: scheduler)

        let refreshExpectation = expectation(description: "first refresh")
        var refreshCount = 0
        sut.setRefreshAction { _ in
            refreshCount += 1
            refreshExpectation.fulfill()
            return .noNewData
        }

        sut.onManualRefresh(namespaceKey: "namespace")
        await fulfillment(of: [refreshExpectation], timeout: 1)

        sut.onManualRefresh(namespaceKey: "namespace")

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(sut.substateByNamespace["namespace"], .cooldown)
        XCTAssertEqual(scheduler.lastDelay, FamilyShareFreshnessPolicy.refreshCooldown)
    }

    func testForegroundRefreshRequestsUpdateAndSetsCheckedNoNewData() async {
        let scheduler = TestScheduler()
        let sut = FamilyShareInviteeRefreshScheduler(clock: TestClock(), scheduler: scheduler)
        let refreshExpectation = expectation(description: "foreground refresh")
        sut.setRefreshAction { _ in
            refreshExpectation.fulfill()
            return .noNewData
        }

        sut.onForegroundEntry(namespaceKeys: ["namespace"])
        await fulfillment(of: [refreshExpectation], timeout: 1)
        await flushAsyncWork()

        XCTAssertEqual(sut.substateByNamespace["namespace"], .checkedNoNewData)
    }

    func testFirstVisibilityRefreshFailureSetsRefreshFailedAndAutoDismisses() async {
        let scheduler = TestScheduler()
        let sut = FamilyShareInviteeRefreshScheduler(clock: TestClock(), scheduler: scheduler)
        let refreshExpectation = expectation(description: "first visibility refresh")
        sut.setRefreshAction { _ in
            refreshExpectation.fulfill()
            return .failure(FamilyShareCloudKitError.sharedProjectionMissing)
        }

        sut.onFirstVisibility(namespaceKey: "namespace")
        await fulfillment(of: [refreshExpectation], timeout: 1)
        await flushAsyncWork()

        XCTAssertEqual(sut.substateByNamespace["namespace"], .refreshFailed)
        XCTAssertEqual(scheduler.lastDelay, FamilyShareFreshnessPolicy.refreshFailedAutoDismiss)

        await scheduler.fireDebounce()
        await flushAsyncWork()

        XCTAssertEqual(sut.substateByNamespace["namespace"], .idle)
    }
}
