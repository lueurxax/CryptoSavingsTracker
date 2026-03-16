//
//  CloudKitMigrationStatus.swift
//  CryptoSavingsTracker
//
//  Created by Codex on 15/03/2026.
//

import Foundation
import Combine

enum CloudKitRuntimeState: String, Equatable, Sendable {
    case localOnly = "Local only"
    case cloudKitPrimary = "CloudKit primary"
    case cloudKitOnlyReady = "CloudKit-only ready"
}

enum CloudKitMigrationReadinessState: String, Equatable, Sendable {
    case blocked = "Blocked"
    case ready = "Ready"
    case complete = "Complete"

    var isActionAvailable: Bool {
        self == .ready
    }
}

struct CloudKitMigrationStatusSnapshot: Equatable, Sendable {
    let runtimeState: CloudKitRuntimeState
    let readinessState: CloudKitMigrationReadinessState
    let blockers: [PersistenceRuntimeBlocker]
    let exitCriteria: [String]
    let lastEvaluatedAt: Date
    let persistence: PersistenceRuntimeSnapshot

    var migrationActionTitle: String {
        readinessState == .complete ? "Migration Complete" : "Migrate to iCloud"
    }

    var statusSummary: String {
        readinessState.rawValue
    }

    var diagnosticsSummary: String {
        blockers.isEmpty ? "No blocking prerequisites" : "\(blockers.count) blockers"
    }

    var bridgeGatingSummary: String {
        runtimeState == .cloudKitOnlyReady
            ? "Bridge can be implemented in a later phase."
            : "Bridge remains unavailable until the runtime is CloudKit-only."
    }

    var isMigrationActionAvailable: Bool {
        readinessState.isActionAvailable
    }

    @MainActor
    static func current() -> Self {
        let persistence = PersistenceController.shared.snapshot
        let runtimeState: CloudKitRuntimeState
        switch persistence.activeMode {
        case .localOnly:
            runtimeState = .localOnly
        case .cloudPrimaryWithLocalMirror:
            runtimeState = persistence.migrationBlockers.isEmpty ? .cloudKitOnlyReady : .cloudKitPrimary
        case .cloudRollbackBlocked:
            runtimeState = .cloudKitPrimary
        }

        let readinessState: CloudKitMigrationReadinessState
        if persistence.cloudKitEnabled && persistence.migrationBlockers.isEmpty {
            readinessState = .complete
        } else if persistence.migrationBlockers.isEmpty {
            readinessState = .ready
        } else {
            readinessState = .blocked
        }

        return CloudKitMigrationStatusSnapshot(
            runtimeState: runtimeState,
            readinessState: readinessState,
            blockers: persistence.migrationBlockers,
            exitCriteria: [
                "Close the remaining CloudKit model-compatibility blockers from CLOUDKIT_MIGRATION_PLAN.md.",
                "Validate the schema in the CloudKit development container.",
                "Implement and verify migration from the existing local store without data loss.",
                "Switch production runtime to CloudKit before any bridge work becomes visible."
            ],
            lastEvaluatedAt: Date(),
            persistence: persistence
        )
    }
}

enum CloudKitMigrationControllerError: LocalizedError {
    case blocked

    var errorDescription: String? {
        switch self {
        case .blocked:
            return "CloudKit migration is still blocked. Resolve the model-compatibility, container-validation, and local-store migration prerequisites first."
        }
    }
}

@MainActor
final class CloudKitMigrationController: ObservableObject {
    static let shared = CloudKitMigrationController(snapshot: .current())

    @Published private(set) var snapshot: CloudKitMigrationStatusSnapshot

    init(snapshot: CloudKitMigrationStatusSnapshot) {
        self.snapshot = snapshot
    }

    func refresh() {
        PersistenceController.shared.refresh()
        snapshot = .current()
    }

    func attemptMigration() throws {
        refresh()

        guard snapshot.isMigrationActionAvailable else {
            AppLog.warning("Blocked CloudKit migration attempt while prerequisites remain open", category: .swiftData)
            throw CloudKitMigrationControllerError.blocked
        }

        do {
            try PersistenceController.shared.activate(mode: .cloudPrimaryWithLocalMirror)
            AppLog.info("CloudKit migration requested", category: .swiftData)
        } catch {
            AppLog.warning("Blocked CloudKit migration activation attempt: \(error)", category: .swiftData)
            throw CloudKitMigrationControllerError.blocked
        }
    }
}
