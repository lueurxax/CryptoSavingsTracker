import Foundation

enum LocalBridgeAvailabilityState: String, Codable, Equatable, Sendable {
    case unavailable
    case pairingRequired
    case ready
    case reviewRequired
    case updateRequired

    var displayTitle: String {
        switch self {
        case .unavailable: return "Unavailable"
        case .pairingRequired: return "Pairing Required"
        case .ready: return "Ready"
        case .reviewRequired: return "Review Required"
        case .updateRequired: return "Update Required"
        }
    }
}

enum LocalBridgeLastSyncOutcome: String, Codable, Equatable, Sendable {
    case neverSynced
    case succeeded
    case failed
    case cancelled

    var displayTitle: String {
        switch self {
        case .neverSynced: return "Never Synced"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

enum LocalBridgePendingAction: String, Codable, Equatable, Sendable {
    case none
    case pairMac
    case syncNow
    case reviewImport
    case updateRequired
    case trustRevoked

    var displayTitle: String {
        switch self {
        case .none: return "None"
        case .pairMac: return "Pair Mac"
        case .syncNow: return "Sync Now"
        case .reviewImport: return "Review Import"
        case .updateRequired: return "Update Required"
        case .trustRevoked: return "Trust Revoked"
        }
    }
}

enum BridgeCompatibilityState: String, Codable, Equatable, Sendable {
    case unknown
    case compatible
    case updateRequired

    var displayTitle: String {
        switch self {
        case .unknown: return "Unknown"
        case .compatible: return "Compatible"
        case .updateRequired: return "Update Required"
        }
    }
}

enum BridgeCloudKitReconciliationState: String, Codable, Equatable, Sendable {
    case unknown
    case reconciling
    case reconciled
    case stale
    case blockedPendingCloudSync

    var displayTitle: String {
        switch self {
        case .unknown: return "Unknown"
        case .reconciling: return "Reconciling"
        case .reconciled: return "Reconciled"
        case .stale: return "Stale"
        case .blockedPendingCloudSync: return "Blocked Pending Cloud Sync"
        }
    }
}

enum BridgeWorkspaceState: String, Codable, Equatable, Sendable {
    case empty
    case loadedTransientWorkspace
    case edited
    case exported
    case discarded

    var displayTitle: String {
        switch self {
        case .empty: return "Empty"
        case .loadedTransientWorkspace: return "Loaded Workspace"
        case .edited: return "Edited"
        case .exported: return "Exported"
        case .discarded: return "Discarded"
        }
    }
}

enum BridgeTransportState: String, Codable, Equatable, Sendable {
    case idle
    case pairingRequired
    case pairingTokenReady
    case waitingForPeer
    case connected
    case exportingSnapshot
    case waitingForEditedSnapshot
    case validatingImport
    case awaitingImportReview
    case importCancelledByUser
    case importRejectedDueToDrift
    case importApplied
    case trustRevoked
    case trustExpired

    var displayTitle: String {
        switch self {
        case .idle: return "Idle"
        case .pairingRequired: return "Pairing Required"
        case .pairingTokenReady: return "Pairing Token Ready"
        case .waitingForPeer: return "Waiting For Peer"
        case .connected: return "Connected"
        case .exportingSnapshot: return "Exporting Snapshot"
        case .waitingForEditedSnapshot: return "Waiting For Edited Snapshot"
        case .validatingImport: return "Validating Import"
        case .awaitingImportReview: return "Awaiting Import Review"
        case .importCancelledByUser: return "Import Cancelled"
        case .importRejectedDueToDrift: return "Import Rejected Due To Drift"
        case .importApplied: return "Import Applied"
        case .trustRevoked: return "Trust Revoked"
        case .trustExpired: return "Trust Expired"
        }
    }
}

enum BridgePairingMethod: String, Codable, Equatable, Sendable {
    case scanQR
    case enterCodeManually
    case pasteBootstrapToken

    var displayTitle: String {
        switch self {
        case .scanQR: return "Scan QR"
        case .enterCodeManually: return "Enter Code Manually"
        case .pasteBootstrapToken: return "Paste Bootstrap Token"
        }
    }
}

struct BridgeCapabilityManifest: Codable, Equatable, Sendable {
    let bridgeProtocolVersion: Int
    let minimumSupportedCanonicalEncodingVersion: String
    let maximumSupportedCanonicalEncodingVersion: String
    let minimumSupportedSnapshotSchemaVersion: Int
    let maximumSupportedSnapshotSchemaVersion: Int
    let appModelSchemaVersion: String
    let appBuild: String

    static func current(bundle: Bundle = .main) -> Self {
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unknown"
        return Self(
            bridgeProtocolVersion: 1,
            minimumSupportedCanonicalEncodingVersion: "bridge-snapshot-v1",
            maximumSupportedCanonicalEncodingVersion: "bridge-snapshot-v1",
            minimumSupportedSnapshotSchemaVersion: 1,
            maximumSupportedSnapshotSchemaVersion: 1,
            appModelSchemaVersion: "cloudkit-model-v1",
            appBuild: build
        )
    }
}

struct BridgeBootstrapToken: Codable, Equatable, Sendable {
    let pairingID: UUID
    let deviceName: String
    let expiresAt: Date
    let oneTimeSecretReference: String
    let ephemeralPublicKey: String

    var isExpired: Bool {
        expiresAt <= Date()
    }
}

enum BridgeTrustState: String, Codable, Equatable, Sendable {
    case active
    case revoked
    case expired
}

struct TrustedBridgeDevice: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var fingerprint: String
    var addedAt: Date
    var lastSuccessfulSyncAt: Date?
    var trustState: BridgeTrustState

    var shortFingerprint: String {
        fingerprint.count > 12 ? String(fingerprint.prefix(12)) + "…" : fingerprint
    }
}

struct BridgeEntityCount: Codable, Equatable, Sendable {
    let name: String
    let count: Int
}

struct BridgeGoalSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let currency: String
    let targetAmount: Double
    let deadline: Date
    let startDate: Date
    let lifecycleStatusRawValue: String
    let emoji: String?
    let goalDescription: String?
    let link: String?
}

struct BridgeAssetSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let currency: String
    let address: String?
    let chainId: String?
}

struct BridgeTransactionSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let assetId: UUID?
    let amount: Double
    let date: Date
    let sourceRawValue: String
    let externalId: String?
    let counterparty: String?
    let comment: String?
}

struct BridgeAssetAllocationSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let assetId: UUID?
    let goalId: UUID?
    let amount: Double
    let createdDate: Date
    let lastModifiedDate: Date
}

struct BridgeAllocationHistorySnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let assetId: UUID?
    let goalId: UUID?
    let amount: Double
    let timestamp: Date
    let createdAt: Date
    let monthLabel: String
}

struct BridgeMonthlyPlanSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let goalId: UUID
    let monthLabel: String
    let requiredMonthly: Double
    let remainingAmount: Double
    let monthsRemaining: Int
    let currency: String
    let statusRawValue: String
    let stateRawValue: String
    let executionRecordId: UUID?
    let flexStateRawValue: String
    let customAmount: Double?
    let isProtected: Bool
    let isSkipped: Bool
    let createdDate: Date
    let lastModifiedDate: Date
}

struct BridgeMonthlyExecutionRecordSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let monthLabel: String
    let statusRawValue: String
    let createdAt: Date
    let startedAt: Date?
    let completedAt: Date?
    let canUndoUntil: Date?
    let goalIds: [UUID]
    let snapshotId: UUID?
    let completedExecutionId: UUID?
    let planIds: [UUID]
    let completionEventIds: [UUID]
}

struct SnapshotManifest: Codable, Equatable, Sendable {
    let snapshotID: UUID
    let canonicalEncodingVersion: String
    let snapshotSchemaVersion: Int
    let exportedAt: Date
    let appModelSchemaVersion: String
    let entityCounts: [BridgeEntityCount]
    let baseDatasetFingerprint: String
}

struct SnapshotEnvelope: Codable, Equatable, Sendable {
    let manifest: SnapshotManifest
    let goals: [BridgeGoalSnapshot]
    let assets: [BridgeAssetSnapshot]
    let transactions: [BridgeTransactionSnapshot]
    let assetAllocations: [BridgeAssetAllocationSnapshot]
    let allocationHistories: [BridgeAllocationHistorySnapshot]
    let monthlyPlans: [BridgeMonthlyPlanSnapshot]
    let monthlyExecutionRecords: [BridgeMonthlyExecutionRecordSnapshot]

    var entityCounts: [BridgeEntityCount] {
        [
            BridgeEntityCount(name: "Goal", count: goals.count),
            BridgeEntityCount(name: "Asset", count: assets.count),
            BridgeEntityCount(name: "Transaction", count: transactions.count),
            BridgeEntityCount(name: "AssetAllocation", count: assetAllocations.count),
            BridgeEntityCount(name: "AllocationHistory", count: allocationHistories.count),
            BridgeEntityCount(name: "MonthlyPlan", count: monthlyPlans.count),
            BridgeEntityCount(name: "MonthlyExecutionRecord", count: monthlyExecutionRecords.count)
        ]
    }

    func canonicalEncodingData(forFingerprinting: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let payload = forFingerprinting ? envelopeForFingerprinting() : self
        return try encoder.encode(payload)
    }

    func computedDatasetFingerprint() throws -> String {
        let canonicalData = try canonicalEncodingData(forFingerprinting: true)
        return BudgetSnapshotIdentity.sha256(String(decoding: canonicalData, as: UTF8.self))
    }

    func withComputedFingerprint() throws -> SnapshotEnvelope {
        let fingerprint = try computedDatasetFingerprint()
        return SnapshotEnvelope(
            manifest: manifest.withBaseDatasetFingerprint(fingerprint),
            goals: goals,
            assets: assets,
            transactions: transactions,
            assetAllocations: assetAllocations,
            allocationHistories: allocationHistories,
            monthlyPlans: monthlyPlans,
            monthlyExecutionRecords: monthlyExecutionRecords
        )
    }

    private func envelopeForFingerprinting() -> SnapshotEnvelope {
        SnapshotEnvelope(
            manifest: manifest.withBaseDatasetFingerprint(""),
            goals: goals,
            assets: assets,
            transactions: transactions,
            assetAllocations: assetAllocations,
            allocationHistories: allocationHistories,
            monthlyPlans: monthlyPlans,
            monthlyExecutionRecords: monthlyExecutionRecords
        )
    }
}

struct SignedImportPackage: Codable, Equatable, Sendable {
    let packageID: String
    let snapshotID: UUID
    let canonicalEncodingVersion: String
    let baseDatasetFingerprint: String
    let editedDatasetFingerprint: String
    let snapshotEnvelope: SnapshotEnvelope
    let signingKeyID: String
    let signedAt: Date
    let signature: String

    func canonicalEncodingData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }
}

struct BridgeImportReviewStatus: Codable, Equatable, Sendable {
    var summary: String
    var requiresOperatorReview: Bool
    var validationStatus: BridgeImportValidationStatus
    var driftStatus: BridgeImportDriftStatus
    var operatorDecision: BridgeImportOperatorDecisionState
    var importReviewSummary: ImportReviewSummary?
    var reviewSummaryDTO: BridgeImportReviewSummaryDTO?
    var validationWarnings: [String]
    var blockingIssues: [String]

    var changedEntityCounts: [String: Int] {
        reviewSummaryDTO?.changedEntityCounts ?? [:]
    }

    static let none = Self(
        summary: "No import package pending review.",
        requiresOperatorReview: false,
        validationStatus: .notRun,
        driftStatus: .unknown,
        operatorDecision: .notRequired,
        importReviewSummary: nil,
        reviewSummaryDTO: nil,
        validationWarnings: [],
        blockingIssues: []
    )
}

struct BridgeSessionState: Codable, Equatable, Sendable {
    let sessionID: UUID
    let transportState: BridgeTransportState
    let workspaceState: BridgeWorkspaceState
    let compatibilityState: BridgeCompatibilityState
    let cloudKitReconciliationState: BridgeCloudKitReconciliationState
    let liveStoreMutationAllowed: Bool
    let activePairingMethod: BridgePairingMethod?
    let bootstrapToken: BridgeBootstrapToken?
    let lastImportedPackageID: String?

    static let idle = Self(
        sessionID: UUID(),
        transportState: .idle,
        workspaceState: .empty,
        compatibilityState: .unknown,
        cloudKitReconciliationState: .unknown,
        liveStoreMutationAllowed: false,
        activePairingMethod: nil,
        bootstrapToken: nil,
        lastImportedPackageID: nil
    )
}

struct LocalBridgeSyncStatusSnapshot: Equatable, Sendable {
    let availabilityState: LocalBridgeAvailabilityState
    let pendingAction: LocalBridgePendingAction
    let lastSyncOutcome: LocalBridgeLastSyncOutcome
    let trustedDevices: [TrustedBridgeDevice]
    let importReviewStatus: BridgeImportReviewStatus
    let capabilityManifest: BridgeCapabilityManifest
    let sessionState: BridgeSessionState
    let detail: String

    var topLevelSummary: String {
        let pendingSummary = pendingAction == .none ? "No Action" : pendingAction.displayTitle
        return "\(availabilityState.displayTitle) • \(lastSyncOutcome.displayTitle) • \(pendingSummary)"
    }

    static func make(
        persistenceSnapshot: PersistenceRuntimeSnapshot,
        trustedDevices: [TrustedBridgeDevice],
        lastSyncOutcome: LocalBridgeLastSyncOutcome,
        pendingAction: LocalBridgePendingAction,
        importReviewStatus: BridgeImportReviewStatus,
        sessionState: BridgeSessionState,
        capabilityManifest: BridgeCapabilityManifest = .current()
    ) -> Self {
        let cloudKitActive = persistenceSnapshot.cloudKitEnabled
            && persistenceSnapshot.activeStoreKind == .cloudPrimary

        if !cloudKitActive {
            return Self(
                availabilityState: .unavailable,
                pendingAction: .none,
                lastSyncOutcome: lastSyncOutcome,
                trustedDevices: trustedDevices,
                importReviewStatus: importReviewStatus,
                capabilityManifest: capabilityManifest,
                sessionState: sessionState,
                detail: "CloudKit must be the active runtime before Local Bridge Sync becomes available."
            )
        }

        if pendingAction == .reviewImport || importReviewStatus.requiresOperatorReview {
            return Self(
                availabilityState: .reviewRequired,
                pendingAction: .reviewImport,
                lastSyncOutcome: lastSyncOutcome,
                trustedDevices: trustedDevices,
                importReviewStatus: importReviewStatus,
                capabilityManifest: capabilityManifest,
                sessionState: sessionState,
                detail: "A validated import package is waiting for explicit operator review."
            )
        }

        if trustedDevices.isEmpty {
            return Self(
                availabilityState: .pairingRequired,
                pendingAction: .pairMac,
                lastSyncOutcome: lastSyncOutcome,
                trustedDevices: trustedDevices,
                importReviewStatus: importReviewStatus,
                capabilityManifest: capabilityManifest,
                sessionState: sessionState,
                detail: "Pair a trusted Mac before you can exchange bridge snapshots."
            )
        }

        if pendingAction == .updateRequired || sessionState.compatibilityState == .updateRequired {
            return Self(
                availabilityState: .updateRequired,
                pendingAction: .updateRequired,
                lastSyncOutcome: lastSyncOutcome,
                trustedDevices: trustedDevices,
                importReviewStatus: importReviewStatus,
                capabilityManifest: capabilityManifest,
                sessionState: sessionState,
                detail: "Bridge compatibility must be updated on one or both devices before the next session."
            )
        }

        return Self(
            availabilityState: .ready,
            pendingAction: pendingAction,
            lastSyncOutcome: lastSyncOutcome,
            trustedDevices: trustedDevices,
            importReviewStatus: importReviewStatus,
            capabilityManifest: capabilityManifest,
            sessionState: sessionState,
            detail: "CloudKit runtime is active. Local Bridge Sync may begin from this dedicated surface when transport is implemented."
        )
    }
}

extension SnapshotManifest {
    func withBaseDatasetFingerprint(_ fingerprint: String) -> SnapshotManifest {
        SnapshotManifest(
            snapshotID: snapshotID,
            canonicalEncodingVersion: canonicalEncodingVersion,
            snapshotSchemaVersion: snapshotSchemaVersion,
            exportedAt: exportedAt,
            appModelSchemaVersion: appModelSchemaVersion,
            entityCounts: entityCounts,
            baseDatasetFingerprint: fingerprint
        )
    }
}
