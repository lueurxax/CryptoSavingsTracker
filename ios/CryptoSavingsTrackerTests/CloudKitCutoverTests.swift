import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct CloudKitCutoverTests {

    // MARK: - CutoverState Equatable

    @Test("CutoverState cases are equatable")
    func cutoverStateEquatable() {
        let idle = CloudKitCutoverCoordinator.CutoverState.idle
        let idle2 = CloudKitCutoverCoordinator.CutoverState.idle
        #expect(idle == idle2)

        let copying1 = CloudKitCutoverCoordinator.CutoverState.copyingData(progress: 0.5, entityName: "Goals")
        let copying2 = CloudKitCutoverCoordinator.CutoverState.copyingData(progress: 0.5, entityName: "Goals")
        #expect(copying1 == copying2)

        let copying3 = CloudKitCutoverCoordinator.CutoverState.copyingData(progress: 0.7, entityName: "Assets")
        #expect(copying1 != copying3)

        let failed1 = CloudKitCutoverCoordinator.CutoverState.failed("error A")
        let failed2 = CloudKitCutoverCoordinator.CutoverState.failed("error B")
        #expect(failed1 != failed2)
    }

    // MARK: - MigrationEvidence

    @Test("MigrationEvidence is Codable roundtrip")
    func migrationEvidenceCodable() throws {
        let evidence = CloudKitCutoverCoordinator.MigrationEvidence(
            timestamp: Date(),
            entityCounts: ["Goal": 3, "Asset": 5, "Transaction": 10],
            backupPath: "/tmp/backup",
            durationSeconds: 2.5
        )

        let data = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(CloudKitCutoverCoordinator.MigrationEvidence.self, from: data)

        #expect(decoded.entityCounts == evidence.entityCounts)
        #expect(decoded.backupPath == evidence.backupPath)
        #expect(decoded.durationSeconds == evidence.durationSeconds)
    }

    // MARK: - PreflightError

    @Test("PreflightError provides localized descriptions")
    func preflightErrorDescriptions() {
        let alreadyMigrated = CloudKitCutoverCoordinator.PreflightError.alreadyMigrated
        #expect(alreadyMigrated.errorDescription?.contains("already") == true)

        let noAccount = CloudKitCutoverCoordinator.PreflightError.noICloudAccount
        #expect(noAccount.errorDescription?.contains("iCloud") == true)

        let restricted = CloudKitCutoverCoordinator.PreflightError.restrictedAccount
        #expect(restricted.errorDescription?.contains("restricted") == true)

        let checkFailed = CloudKitCutoverCoordinator.PreflightError.accountCheckFailed("timeout")
        #expect(checkFailed.errorDescription?.contains("timeout") == true)
    }

    // MARK: - Coordinator Initial State

    @Test("Coordinator starts in idle state")
    func coordinatorInitialState() {
        let coordinator = CloudKitCutoverCoordinator()
        #expect(coordinator.state == .idle)
    }

    // MARK: - Migration Evidence Persistence

    @Test("Migration evidence can be persisted and loaded from UserDefaults")
    func migrationEvidencePersistence() {
        let evidence = CloudKitCutoverCoordinator.MigrationEvidence(
            timestamp: Date(),
            entityCounts: ["Goal": 2, "Asset": 4],
            backupPath: "/backup/test",
            durationSeconds: 1.0
        )

        // Persist
        if let data = try? JSONEncoder().encode(evidence) {
            UserDefaults.standard.set(data, forKey: "CloudKit.MigrationEvidence.Test")
        }

        // Load
        if let data = UserDefaults.standard.data(forKey: "CloudKit.MigrationEvidence.Test"),
           let loaded = try? JSONDecoder().decode(CloudKitCutoverCoordinator.MigrationEvidence.self, from: data) {
            #expect(loaded.entityCounts == evidence.entityCounts)
            #expect(loaded.backupPath == evidence.backupPath)
        } else {
            Issue.record("Failed to load persisted migration evidence")
        }

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "CloudKit.MigrationEvidence.Test")
    }

    // MARK: - ValidationError

    @Test("ValidationError provides count mismatch details")
    func validationErrorDescription() {
        let error = CloudKitCutoverCoordinator.ValidationError.countMismatch(
            entity: "Goal", expected: 5, actual: 3
        )
        #expect(error.errorDescription?.contains("Goal") == true)
        #expect(error.errorDescription?.contains("5") == true)
        #expect(error.errorDescription?.contains("3") == true)
    }
}
