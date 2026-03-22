import XCTest
@testable import CryptoSavingsTracker

final class FamilyShareFreshnessPolicyTests: XCTestCase {

    // MARK: - Test Clock

    class TestClock: FamilyShareClock {
        var currentDate: Date = Date()
        func now() -> Date { currentDate }
    }

    // MARK: - Tier Resolution

    func testActiveTier_withinThreshold() {
        let clock = TestClock()
        let policy = FamilyShareFreshnessPolicy(clock: clock)
        let publishedAt = clock.now().addingTimeInterval(-10 * 60) // 10 minutes ago

        let tier = policy.tier(forEffectiveAge: policy.effectiveAge(publishedAt: publishedAt, rateSnapshotAt: publishedAt))
        XCTAssertEqual(tier, .active)
    }

    func testRecentlyStaleTier() {
        let clock = TestClock()
        let policy = FamilyShareFreshnessPolicy(clock: clock)
        let publishedAt = clock.now().addingTimeInterval(-2 * 3600) // 2 hours ago

        let tier = policy.tier(forEffectiveAge: policy.effectiveAge(publishedAt: publishedAt, rateSnapshotAt: publishedAt))
        XCTAssertEqual(tier, .recentlyStale)
    }

    func testStaleTier() {
        let clock = TestClock()
        let policy = FamilyShareFreshnessPolicy(clock: clock)
        let publishedAt = clock.now().addingTimeInterval(-8 * 3600) // 8 hours ago

        let tier = policy.tier(forEffectiveAge: policy.effectiveAge(publishedAt: publishedAt, rateSnapshotAt: publishedAt))
        XCTAssertEqual(tier, .stale)
    }

    func testMateriallyOutdatedTier() {
        let clock = TestClock()
        let policy = FamilyShareFreshnessPolicy(clock: clock)
        let publishedAt = clock.now().addingTimeInterval(-48 * 3600) // 48 hours ago

        let tier = policy.tier(forEffectiveAge: policy.effectiveAge(publishedAt: publishedAt, rateSnapshotAt: publishedAt))
        XCTAssertEqual(tier, .materiallyOutdated)
    }

    // MARK: - Composite Age (max of publish and rate age)

    func testCompositeAge_rateAgeGoverns() {
        let clock = TestClock()
        let policy = FamilyShareFreshnessPolicy(clock: clock)
        let publishedAt = clock.now().addingTimeInterval(-5 * 60) // 5 minutes ago (active)
        let rateSnapshotAt = clock.now().addingTimeInterval(-6 * 3600) // 6 hours old (stale)

        let effectiveAge = policy.effectiveAge(publishedAt: publishedAt, rateSnapshotAt: rateSnapshotAt)
        let tier = policy.tier(forEffectiveAge: effectiveAge)

        XCTAssertEqual(tier, .stale) // Rate age governs
    }

    func testGoverningDependency_rateAge() {
        let clock = TestClock()
        let policy = FamilyShareFreshnessPolicy(clock: clock)
        let publishedAt = clock.now().addingTimeInterval(-5 * 60)
        let rateSnapshotAt = clock.now().addingTimeInterval(-6 * 3600)

        let governing = policy.governingDependency(publishedAt: publishedAt, rateSnapshotAt: rateSnapshotAt)
        XCTAssertEqual(governing, .rateAge)
    }

    func testGoverningDependency_publishAge() {
        let clock = TestClock()
        let policy = FamilyShareFreshnessPolicy(clock: clock)
        let publishedAt = clock.now().addingTimeInterval(-6 * 3600)
        let rateSnapshotAt = clock.now().addingTimeInterval(-5 * 60)

        let governing = policy.governingDependency(publishedAt: publishedAt, rateSnapshotAt: rateSnapshotAt)
        XCTAssertEqual(governing, .publishAge)
    }

    // MARK: - Clock Skew

    func testClockSkew_futureTimestamp_clamped() {
        let clock = TestClock()
        let policy = FamilyShareFreshnessPolicy(clock: clock)
        let futureTimestamp = clock.now().addingTimeInterval(120) // 2 minutes in the future

        let (age, skewDetected) = policy.clampedAge(for: futureTimestamp)
        XCTAssertEqual(age, 0)
        XCTAssertTrue(skewDetected)
    }

    func testClockSkew_withinTolerance_noSkew() {
        let clock = TestClock()
        let policy = FamilyShareFreshnessPolicy(clock: clock)
        let slightlyFuture = clock.now().addingTimeInterval(30) // 30s in the future

        let (age, skewDetected) = policy.clampedAge(for: slightlyFuture)
        XCTAssertEqual(age, 0)
        XCTAssertFalse(skewDetected)
    }

    // MARK: - Backoff

    func testBackoffDelay_increasesWithFailures() {
        let policy = FamilyShareFreshnessPolicy()
        XCTAssertEqual(policy.backoffDelay(forFailureCount: 0), 5)
        XCTAssertEqual(policy.backoffDelay(forFailureCount: 1), 15)
        XCTAssertEqual(policy.backoffDelay(forFailureCount: 2), 60)
        XCTAssertEqual(policy.backoffDelay(forFailureCount: 3), 300)
        XCTAssertEqual(policy.backoffDelay(forFailureCount: 10), 300) // Capped
    }
}
