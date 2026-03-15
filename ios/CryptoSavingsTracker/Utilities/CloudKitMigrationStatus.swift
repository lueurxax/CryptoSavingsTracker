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

struct CloudKitMigrationBlocker: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
}

struct CloudKitMigrationStatusSnapshot: Equatable, Sendable {
    let runtimeState: CloudKitRuntimeState
    let readinessState: CloudKitMigrationReadinessState
    let blockers: [CloudKitMigrationBlocker]
    let exitCriteria: [String]
    let lastEvaluatedAt: Date

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

    static func current() -> Self {
        // Keep this status in sync with the live ModelConfiguration while CloudKit remains disabled
        // via `cloudKitDatabase: .none` in CryptoSavingsTrackerApp.
        let blockers = [
            CloudKitMigrationBlocker(
                id: "runtime-disabled",
                title: "CloudKit runtime is still disabled",
                detail: "The live app still mounts the SwiftData container with local-only storage."
            ),
            CloudKitMigrationBlocker(
                id: "model-compatibility",
                title: "SwiftData model compatibility blockers remain open",
                detail: "Unique constraints, non-optional properties without defaults, and missing inverse relationships still need CloudKit-safe changes."
            ),
            CloudKitMigrationBlocker(
                id: "container-validation",
                title: "CloudKit development-container validation is incomplete",
                detail: "Schema deployment and validation in the development container must pass before migration can start."
            ),
            CloudKitMigrationBlocker(
                id: "local-migration-path",
                title: "Local-store migration path is not implemented",
                detail: "Existing local data still needs a verified migration flow into the CloudKit-backed runtime without data loss."
            )
        ]

        return CloudKitMigrationStatusSnapshot(
            runtimeState: .localOnly,
            readinessState: .blocked,
            blockers: blockers,
            exitCriteria: [
                "Close the remaining CloudKit model-compatibility blockers from CLOUDKIT_MIGRATION_PLAN.md.",
                "Validate the schema in the CloudKit development container.",
                "Implement and verify migration from the existing local store without data loss.",
                "Switch production runtime to CloudKit before any bridge work becomes visible."
            ],
            lastEvaluatedAt: Date()
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
        snapshot = .current()
    }

    func attemptMigration() throws {
        refresh()

        guard snapshot.isMigrationActionAvailable else {
            AppLog.warning("Blocked CloudKit migration attempt while prerequisites remain open", category: .swiftData)
            throw CloudKitMigrationControllerError.blocked
        }

        AppLog.info("CloudKit migration requested", category: .swiftData)
    }
}
