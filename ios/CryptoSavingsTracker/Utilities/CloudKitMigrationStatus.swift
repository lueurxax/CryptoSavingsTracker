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
            runtimeState = .cloudKitPrimary
        case .cloudRollbackBlocked:
            runtimeState = .cloudKitOnlyReady
        }

        let readinessState: CloudKitMigrationReadinessState
        switch runtimeState {
        case .cloudKitPrimary, .cloudKitOnlyReady:
            readinessState = .complete
        case .localOnly:
            // Ready if iCloud account is available (checked at migration time)
            readinessState = .ready
        }

        let exitCriteria: [String]
        switch readinessState {
        case .complete:
            exitCriteria = ["Migration complete. CloudKit is the active persistence layer."]
        case .ready:
            exitCriteria = [
                "Tap 'Migrate to iCloud' to copy local data to CloudKit.",
                "Ensure you are signed into iCloud on this device.",
                "A backup will be created automatically before migration."
            ]
        case .blocked:
            exitCriteria = [
                "Sign in to iCloud in device Settings.",
                "Ensure a stable network connection."
            ]
        }

        return CloudKitMigrationStatusSnapshot(
            runtimeState: runtimeState,
            readinessState: readinessState,
            blockers: persistence.migrationBlockers,
            exitCriteria: exitCriteria,
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
    @Published private(set) var cutoverState: CloudKitCutoverCoordinator.CutoverState = .idle

    private lazy var cutoverCoordinator = DIContainer.shared.makeCutoverCoordinator()

    init(snapshot: CloudKitMigrationStatusSnapshot) {
        self.snapshot = snapshot
    }

    func refresh() {
        PersistenceController.shared.refresh()
        snapshot = .current()
    }

    func attemptMigration() async throws {
        refresh()

        guard snapshot.isMigrationActionAvailable else {
            AppLog.warning("Blocked CloudKit migration attempt", category: .swiftData)
            throw CloudKitMigrationControllerError.blocked
        }

        // Observe cutover coordinator state
        let coordinator = cutoverCoordinator
        let observation = coordinator.$state.sink { [weak self] newState in
            self?.cutoverState = newState
        }

        do {
            try await coordinator.performCutover(
                sourceContainer: PersistenceController.shared.activeContainer
            )
            AppLog.info("CloudKit migration completed successfully", category: .swiftData)
            refresh()
        } catch {
            AppLog.error("CloudKit migration failed: \(error)", category: .swiftData)
            refresh()
            throw error
        }

        _ = observation // Keep alive until migration completes
    }
}
