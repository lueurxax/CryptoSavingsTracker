import Testing
@testable import CryptoSavingsTracker

@MainActor
struct CloudKitMigrationStatusTests {

    @Test("current snapshot reports local-only runtime and blocked migration")
    func currentSnapshotReflectsBlockedState() {
        let snapshot = CloudKitMigrationStatusSnapshot.current()

        #expect(snapshot.runtimeState == .localOnly)
        #expect(snapshot.readinessState == .blocked)
        #expect(snapshot.isMigrationActionAvailable == false)
        #expect(snapshot.blockers.count >= 4)
        #expect(snapshot.exitCriteria.count == 4)
    }

    @Test("migration attempt is rejected while prerequisites remain open")
    func migrationAttemptBlocked() {
        let controller = CloudKitMigrationController(snapshot: .current())

        #expect(throws: CloudKitMigrationControllerError.self) {
            try controller.attemptMigration()
        }
    }
}
