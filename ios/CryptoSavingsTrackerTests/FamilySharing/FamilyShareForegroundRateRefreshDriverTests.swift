import XCTest
@testable import CryptoSavingsTracker

@MainActor
final class FamilyShareForegroundRateRefreshDriverTests: XCTestCase {
    private final class MockExchangeRateService: ExchangeRateServiceProtocol, @unchecked Sendable {
        private(set) var refreshCalls = 0

        func fetchRate(from: String, to: String) async throws -> Double { 1 }
        func hasValidConfiguration() -> Bool { true }
        func setOfflineMode(_ offline: Bool) {}
        func refreshRatesIfStale() async {
            refreshCalls += 1
        }
    }

    private final class TestScheduler: FamilyShareScheduler, @unchecked Sendable {
        var debounceDelays: [TimeInterval] = []
        var periodicIntervals: [TimeInterval] = []
        private var periodicActions: [TimeInterval: @Sendable () async -> Void] = [:]

        func scheduleDebounce(delay: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable {
            debounceDelays.append(delay)
            return TestCancellable()
        }

        func schedulePeriodic(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable {
            periodicIntervals.append(interval)
            periodicActions[interval] = action
            return TestCancellable()
        }

        func fire(interval: TimeInterval) async {
            await periodicActions[interval]?()
        }
    }

    private final class TestClock: FamilyShareClock, @unchecked Sendable {
        var currentDate = Date()
        func now() -> Date { currentDate }
    }

    private struct TestCancellable: FamilyShareCancellable {
        func cancel() {}
    }

    private func flushAsyncWork(iterations: Int = 10) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    func testStartWhenSharingInactiveDoesNotScheduleOrRefresh() async throws {
        let service = MockExchangeRateService()
        let scheduler = TestScheduler()
        let clock = TestClock()
        let sut = FamilyShareForegroundRateRefreshDriver(
            exchangeRateService: service,
            clock: clock,
            scheduler: scheduler,
            hasActiveSharing: { false }
        )

        sut.start()
        await flushAsyncWork()

        XCTAssertEqual(service.refreshCalls, 0)
        XCTAssertTrue(scheduler.periodicIntervals.isEmpty)
    }

    func testStartWhenSharingActiveRefreshesImmediatelyAndSchedulesTimers() async throws {
        let service = MockExchangeRateService()
        let scheduler = TestScheduler()
        let clock = TestClock()
        let sut = FamilyShareForegroundRateRefreshDriver(
            exchangeRateService: service,
            clock: clock,
            scheduler: scheduler,
            hasActiveSharing: { true }
        )

        sut.start()
        await flushAsyncWork()

        XCTAssertEqual(service.refreshCalls, 1)
        XCTAssertTrue(scheduler.periodicIntervals.contains(FamilyShareFreshnessPolicy.rateCacheTTL))
        XCTAssertTrue(scheduler.periodicIntervals.contains(FamilyShareFreshnessPolicy.periodicGuardInterval))
    }

    func testGuardTimerRefreshesWhenPrimaryRefreshWasMissed() async {
        let service = MockExchangeRateService()
        let scheduler = TestScheduler()
        let clock = TestClock()
        let sut = FamilyShareForegroundRateRefreshDriver(
            exchangeRateService: service,
            clock: clock,
            scheduler: scheduler,
            hasActiveSharing: { true }
        )

        sut.start()
        await flushAsyncWork()
        XCTAssertEqual(service.refreshCalls, 1)

        clock.currentDate.addTimeInterval(FamilyShareFreshnessPolicy.periodicGuardInterval)
        await scheduler.fire(interval: FamilyShareFreshnessPolicy.periodicGuardInterval)
        await flushAsyncWork()

        XCTAssertEqual(service.refreshCalls, 2)
    }
}
