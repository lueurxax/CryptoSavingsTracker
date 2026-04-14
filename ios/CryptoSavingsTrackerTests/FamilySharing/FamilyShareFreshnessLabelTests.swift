import XCTest
@testable import CryptoSavingsTracker

final class FamilyShareFreshnessLabelTests: XCTestCase {
    private final class CapturingTelemetry: FamilyShareTelemetryTracking, @unchecked Sendable {
        private(set) var events: [(FamilyShareTelemetryEvent, [String: String])] = []

        func track(_ event: FamilyShareTelemetryEvent, payload: [String: String]) {
            events.append((event, payload))
        }
    }

    // MARK: - Test Clock

    private final class TestClock: FamilyShareClock, @unchecked Sendable {
        var currentDate: Date = Date()
        func now() -> Date { currentDate }
    }

    private func flushAsyncWork(iterations: Int = 10) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    override func setUp() {
        super.setUp()
        FamilyShareClockSkewTelemetryDeduper.shared.reset()
    }

    // MARK: - Publish-Governed Copy

    func testActive_publishGoverned_usesSharedPrefix() {
        let clock = TestClock()
        let label = FamilyShareFreshnessLabel(
            publishedAt: clock.now().addingTimeInterval(-5 * 60),
            rateSnapshotAt: clock.now().addingTimeInterval(-5 * 60),
            clock: clock
        )
        XCTAssertEqual(label.tier, .active)
        XCTAssertTrue(label.primaryMessage.contains("Shared"))
    }

    // MARK: - Rate-Governed Copy

    func testStale_rateGoverned_leadsWithRateAge() {
        let clock = TestClock()
        let label = FamilyShareFreshnessLabel(
            publishedAt: clock.now().addingTimeInterval(-5 * 60), // 5 min ago (active)
            rateSnapshotAt: clock.now().addingTimeInterval(-8 * 3600), // 8 hours ago (stale)
            clock: clock
        )
        XCTAssertEqual(label.tier, .stale)
        XCTAssertEqual(label.governing, .rateAge)
        XCTAssertTrue(label.primaryMessage.contains("Rates are"))
        XCTAssertTrue(label.primaryMessage.contains("values may have changed"))
    }

    // MARK: - Substates

    func testCheckingSubstate_overridesPrimaryMessage() {
        let clock = TestClock()
        let label = FamilyShareFreshnessLabel(
            publishedAt: clock.now().addingTimeInterval(-5 * 60),
            rateSnapshotAt: clock.now().addingTimeInterval(-5 * 60),
            substate: .checking,
            clock: clock
        )
        XCTAssertEqual(label.primaryMessage, "Checking for updates...")
    }

    func testRefreshFailedSubstate_showsFailureCopy() {
        let clock = TestClock()
        let label = FamilyShareFreshnessLabel(
            publishedAt: clock.now().addingTimeInterval(-5 * 60),
            rateSnapshotAt: clock.now().addingTimeInterval(-5 * 60),
            substate: .refreshFailed,
            clock: clock
        )
        XCTAssertTrue(label.primaryMessage.contains("Couldn't refresh"))
    }

    func testCheckedNoNewDataSubstate_appendsSecondaryMessage() {
        let clock = TestClock()
        let label = FamilyShareFreshnessLabel(
            publishedAt: clock.now().addingTimeInterval(-5 * 60),
            rateSnapshotAt: clock.now().addingTimeInterval(-5 * 60),
            substate: .checkedNoNewData,
            clock: clock
        )
        XCTAssertNotNil(label.secondaryMessage)
        XCTAssertTrue(label.secondaryMessage!.contains("no newer update"))
    }

    // MARK: - VoiceOver

    func testVoiceOver_stale_includesWarningPrefix() {
        let clock = TestClock()
        let label = FamilyShareFreshnessLabel(
            publishedAt: clock.now().addingTimeInterval(-8 * 3600),
            rateSnapshotAt: clock.now().addingTimeInterval(-8 * 3600),
            clock: clock
        )
        XCTAssertEqual(label.tier, .stale)
        XCTAssertTrue(label.voiceOverMessage.contains("Warning"))
    }

    // MARK: - Tier Consistency

    func testFreshnessLabel_tierMatchesPolicy() {
        let clock = TestClock()
        let policy = FamilyShareFreshnessPolicy(clock: clock)
        let publishedAt = clock.now().addingTimeInterval(-2 * 3600) // 2 hours

        let label = FamilyShareFreshnessLabel(publishedAt: publishedAt, rateSnapshotAt: publishedAt, clock: clock)
        let policyResult = policy.evaluate(publishedAt: publishedAt, rateSnapshotAt: publishedAt)

        XCTAssertEqual(label.tier, policyResult.tier)
        XCTAssertEqual(label.governing, policyResult.governing)
    }

    func testClockSkewTelemetry_emitsWhenTimestampFarInFuture() async {
        let clock = TestClock()
        let telemetry = CapturingTelemetry()

        _ = FamilyShareFreshnessLabel(
            publishedAt: clock.now().addingTimeInterval(180),
            rateSnapshotAt: nil,
            clock: clock,
            namespaceKey: "owner|share",
            telemetry: telemetry
        )

        await flushAsyncWork()

        XCTAssertTrue(
            telemetry.events.contains(where: { $0.0 == .clockSkewDetected && $0.1["source"] == "publish" }),
            "Clock skew telemetry should fire for publish timestamps beyond tolerance"
        )
    }
}
