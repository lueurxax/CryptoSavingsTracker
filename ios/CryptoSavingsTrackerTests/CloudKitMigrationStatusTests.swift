import Testing
@testable import CryptoSavingsTracker

@MainActor
struct CloudKitMigrationStatusTests {

    @Test("current snapshot reports local-only runtime and ready migration")
    func currentSnapshotReflectsReadyState() {
        let snapshot = CloudKitMigrationStatusSnapshot.current()

        #expect(snapshot.runtimeState == .localOnly)
        #expect(snapshot.readinessState == .ready)
        #expect(snapshot.isMigrationActionAvailable == true)
        #expect(snapshot.exitCriteria.count == 3)
    }

    @Test("snapshot status summary returns readiness raw value")
    func snapshotStatusSummary() {
        let snapshot = CloudKitMigrationStatusSnapshot.current()
        #expect(snapshot.statusSummary == "Ready")
    }

    @Test("migration action title reflects readiness state")
    func migrationActionTitle() {
        let snapshot = CloudKitMigrationStatusSnapshot.current()
        #expect(snapshot.migrationActionTitle == "Migrate to iCloud")
    }
}
