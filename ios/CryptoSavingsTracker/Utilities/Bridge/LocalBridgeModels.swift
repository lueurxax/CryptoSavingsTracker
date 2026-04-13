import Foundation

enum BridgeBootstrapTokenError: LocalizedError {
    case invalidEncoding
    case invalidPayload
    case invalidPairingCode

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "The pairing token could not be decoded."
        case .invalidPayload:
            return "The pairing token payload is invalid."
        case .invalidPairingCode:
            return "The pairing code is invalid."
        }
    }
}

enum BridgeRecordState: String, Codable, Equatable, Sendable {
    case active
    case deleted
}

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

struct LocalBridgeIdentifierMetadata: Equatable, Sendable {
    let label: String
    let value: String
    let hint: String
}

enum LocalBridgeIdentifierPresentation {
    static func metadata(title: String, value: String) -> LocalBridgeIdentifierMetadata {
        let spokenTitle = title.prefix(1).lowercased() + title.dropFirst()
        return LocalBridgeIdentifierMetadata(
            label: title,
            value: value,
            hint: "Shows the full \(spokenTitle) across multiple lines."
        )
    }
}

enum BridgeObservabilityRedactor {
    static func redactedBootstrapToken(_ token: String) -> String {
        guard token.count > 20 else {
            return String(repeating: "•", count: max(8, token.count))
        }
        let prefix = token.prefix(8)
        let suffix = token.suffix(8)
        return "\(prefix)…\(suffix)"
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
    let signingKeyID: String
    let publicKeyRepresentation: String
    let signingAlgorithm: String
    let fingerprint: String

    var isExpired: Bool {
        expiresAt <= Date()
    }

    func encodedPairingCode() throws -> String {
        let base64 = try encodedManualEntryToken()
        let base64URL = base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var groups: [String] = []
        var index = base64URL.startIndex
        while index < base64URL.endIndex {
            let end = base64URL.index(index, offsetBy: 4, limitedBy: base64URL.endIndex) ?? base64URL.endIndex
            groups.append(String(base64URL[index..<end]))
            index = end
        }
        return groups.joined(separator: ".")
    }

    func encodedManualEntryToken() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self).base64EncodedString()
    }

    static func decodePairingCode(_ code: String) throws -> Self {
        let normalized = code
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")

        guard normalized.isEmpty == false else {
            throw BridgeBootstrapTokenError.invalidPairingCode
        }

        let base64 = normalized
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingCount = (4 - (base64.count % 4)) % 4
        let padded = base64 + String(repeating: "=", count: paddingCount)

        guard let data = Data(base64Encoded: padded) else {
            throw BridgeBootstrapTokenError.invalidPairingCode
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        do {
            return try decoder.decode(Self.self, from: data)
        } catch {
            throw BridgeBootstrapTokenError.invalidPairingCode
        }
    }

    static func decodeManualEntryToken(_ token: String) throws -> Self {
        guard let data = Data(base64Encoded: token) else {
            throw BridgeBootstrapTokenError.invalidEncoding
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        do {
            return try decoder.decode(Self.self, from: data)
        } catch {
            throw BridgeBootstrapTokenError.invalidPayload
        }
    }
}

enum BridgeTrustState: String, Codable, Equatable, Sendable {
    case active
    case revoked
    case expired
}

enum BridgeValidationOutcome: String, Codable, Equatable, Sendable {
    case passed
    case warnings
    case failed

    var displayTitle: String {
        switch self {
        case .passed: return "Passed"
        case .warnings: return "Warnings"
        case .failed: return "Failed"
        }
    }
}

struct TrustedBridgeDevice: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var fingerprint: String
    var signingKeyID: String? = nil
    var publicKeyRepresentation: String? = nil
    var signingAlgorithm: String? = nil
    var addedAt: Date
    var lastSuccessfulSyncAt: Date?
    var lastValidationOutcome: BridgeValidationOutcome? = nil
    var lastValidationAt: Date? = nil
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
    let recordState: BridgeRecordState
    let name: String
    let currency: String
    let targetAmount: Double
    let deadline: Date
    let startDate: Date
    let lifecycleStatusRawValue: String
    let emoji: String?
    let goalDescription: String?
    let link: String?

    init(
        id: UUID,
        recordState: BridgeRecordState = .active,
        name: String,
        currency: String,
        targetAmount: Double,
        deadline: Date,
        startDate: Date,
        lifecycleStatusRawValue: String,
        emoji: String?,
        goalDescription: String?,
        link: String?
    ) {
        self.id = id
        self.recordState = recordState
        self.name = name
        self.currency = currency
        self.targetAmount = targetAmount
        self.deadline = deadline
        self.startDate = startDate
        self.lifecycleStatusRawValue = lifecycleStatusRawValue
        self.emoji = emoji
        self.goalDescription = goalDescription
        self.link = link
    }
}

struct BridgeAssetSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let recordState: BridgeRecordState
    let currency: String
    let address: String?
    let chainId: String?

    init(
        id: UUID,
        recordState: BridgeRecordState = .active,
        currency: String,
        address: String?,
        chainId: String?
    ) {
        self.id = id
        self.recordState = recordState
        self.currency = currency
        self.address = address
        self.chainId = chainId
    }
}

struct BridgeTransactionSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let recordState: BridgeRecordState
    let assetId: UUID?
    let amount: Double
    let date: Date
    let sourceRawValue: String
    let externalId: String?
    let counterparty: String?
    let comment: String?

    init(
        id: UUID,
        recordState: BridgeRecordState = .active,
        assetId: UUID?,
        amount: Double,
        date: Date,
        sourceRawValue: String,
        externalId: String?,
        counterparty: String?,
        comment: String?
    ) {
        self.id = id
        self.recordState = recordState
        self.assetId = assetId
        self.amount = amount
        self.date = date
        self.sourceRawValue = sourceRawValue
        self.externalId = externalId
        self.counterparty = counterparty
        self.comment = comment
    }
}

struct BridgeAssetAllocationSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let recordState: BridgeRecordState
    let assetId: UUID?
    let goalId: UUID?
    let amount: Double
    let createdDate: Date
    let lastModifiedDate: Date

    init(
        id: UUID,
        recordState: BridgeRecordState = .active,
        assetId: UUID?,
        goalId: UUID?,
        amount: Double,
        createdDate: Date,
        lastModifiedDate: Date
    ) {
        self.id = id
        self.recordState = recordState
        self.assetId = assetId
        self.goalId = goalId
        self.amount = amount
        self.createdDate = createdDate
        self.lastModifiedDate = lastModifiedDate
    }
}

struct BridgeAllocationHistorySnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let recordState: BridgeRecordState
    let assetId: UUID?
    let goalId: UUID?
    let amount: Double
    let timestamp: Date
    let createdAt: Date
    let monthLabel: String

    init(
        id: UUID,
        recordState: BridgeRecordState = .active,
        assetId: UUID?,
        goalId: UUID?,
        amount: Double,
        timestamp: Date,
        createdAt: Date,
        monthLabel: String
    ) {
        self.id = id
        self.recordState = recordState
        self.assetId = assetId
        self.goalId = goalId
        self.amount = amount
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.monthLabel = monthLabel
    }
}

struct BridgeMonthlyPlanSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let recordState: BridgeRecordState
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

    init(
        id: UUID,
        recordState: BridgeRecordState = .active,
        goalId: UUID,
        monthLabel: String,
        requiredMonthly: Double,
        remainingAmount: Double,
        monthsRemaining: Int,
        currency: String,
        statusRawValue: String,
        stateRawValue: String,
        executionRecordId: UUID?,
        flexStateRawValue: String,
        customAmount: Double?,
        isProtected: Bool,
        isSkipped: Bool,
        createdDate: Date,
        lastModifiedDate: Date
    ) {
        self.id = id
        self.recordState = recordState
        self.goalId = goalId
        self.monthLabel = monthLabel
        self.requiredMonthly = requiredMonthly
        self.remainingAmount = remainingAmount
        self.monthsRemaining = monthsRemaining
        self.currency = currency
        self.statusRawValue = statusRawValue
        self.stateRawValue = stateRawValue
        self.executionRecordId = executionRecordId
        self.flexStateRawValue = flexStateRawValue
        self.customAmount = customAmount
        self.isProtected = isProtected
        self.isSkipped = isSkipped
        self.createdDate = createdDate
        self.lastModifiedDate = lastModifiedDate
    }
}

struct BridgeMonthlyExecutionRecordSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let recordState: BridgeRecordState
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

    init(
        id: UUID,
        recordState: BridgeRecordState = .active,
        monthLabel: String,
        statusRawValue: String,
        createdAt: Date,
        startedAt: Date?,
        completedAt: Date?,
        canUndoUntil: Date?,
        goalIds: [UUID],
        snapshotId: UUID?,
        completedExecutionId: UUID?,
        planIds: [UUID],
        completionEventIds: [UUID]
    ) {
        self.id = id
        self.recordState = recordState
        self.monthLabel = monthLabel
        self.statusRawValue = statusRawValue
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.canUndoUntil = canUndoUntil
        self.goalIds = goalIds
        self.snapshotId = snapshotId
        self.completedExecutionId = completedExecutionId
        self.planIds = planIds
        self.completionEventIds = completionEventIds
    }
}

struct BridgeCompletedExecutionSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let recordState: BridgeRecordState
    let executionRecordId: UUID
    let monthLabel: String
    let completedAt: Date
    let exchangeRatesSnapshot: [String: Double]
    let goalSnapshots: [ExecutionGoalSnapshot]
    let contributionSnapshots: [CompletedExecutionContributionSnapshot]

    init(
        id: UUID,
        recordState: BridgeRecordState = .active,
        executionRecordId: UUID,
        monthLabel: String,
        completedAt: Date,
        exchangeRatesSnapshot: [String: Double],
        goalSnapshots: [ExecutionGoalSnapshot],
        contributionSnapshots: [CompletedExecutionContributionSnapshot]
    ) {
        self.id = id
        self.recordState = recordState
        self.executionRecordId = executionRecordId
        self.monthLabel = monthLabel
        self.completedAt = completedAt
        self.exchangeRatesSnapshot = exchangeRatesSnapshot
        self.goalSnapshots = goalSnapshots
        self.contributionSnapshots = contributionSnapshots
    }
}

struct BridgeExecutionSnapshotPayload: Codable, Equatable, Sendable {
    let id: UUID
    let recordState: BridgeRecordState
    let executionRecordId: UUID
    let capturedAt: Date
    let totalPlanned: Double
    let goalSnapshots: [ExecutionGoalSnapshot]

    init(
        id: UUID,
        recordState: BridgeRecordState = .active,
        executionRecordId: UUID,
        capturedAt: Date,
        totalPlanned: Double,
        goalSnapshots: [ExecutionGoalSnapshot]
    ) {
        self.id = id
        self.recordState = recordState
        self.executionRecordId = executionRecordId
        self.capturedAt = capturedAt
        self.totalPlanned = totalPlanned
        self.goalSnapshots = goalSnapshots
    }
}

struct BridgeCompletionEventSnapshot: Codable, Equatable, Sendable {
    let eventId: UUID
    let recordState: BridgeRecordState
    let executionRecordId: UUID
    let completionSnapshotId: UUID
    let monthLabel: String
    let sequence: Int
    let sourceDiscriminator: String
    let completedAt: Date
    let undoneAt: Date?
    let undoReason: String?
    let createdAt: Date

    init(
        eventId: UUID,
        recordState: BridgeRecordState = .active,
        executionRecordId: UUID,
        completionSnapshotId: UUID,
        monthLabel: String,
        sequence: Int,
        sourceDiscriminator: String,
        completedAt: Date,
        undoneAt: Date?,
        undoReason: String?,
        createdAt: Date
    ) {
        self.eventId = eventId
        self.recordState = recordState
        self.executionRecordId = executionRecordId
        self.completionSnapshotId = completionSnapshotId
        self.monthLabel = monthLabel
        self.sequence = sequence
        self.sourceDiscriminator = sourceDiscriminator
        self.completedAt = completedAt
        self.undoneAt = undoneAt
        self.undoReason = undoReason
        self.createdAt = createdAt
    }
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

private let bridgeFingerprintNeutralSnapshotID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
private let bridgeFingerprintNeutralExportedAt = Date(timeIntervalSince1970: 0)

struct SnapshotEnvelope: Codable, Equatable, Sendable {
    let manifest: SnapshotManifest
    let goals: [BridgeGoalSnapshot]
    let assets: [BridgeAssetSnapshot]
    let transactions: [BridgeTransactionSnapshot]
    let assetAllocations: [BridgeAssetAllocationSnapshot]
    let allocationHistories: [BridgeAllocationHistorySnapshot]
    let monthlyPlans: [BridgeMonthlyPlanSnapshot]
    let monthlyExecutionRecords: [BridgeMonthlyExecutionRecordSnapshot]
    let completedExecutions: [BridgeCompletedExecutionSnapshot]
    let executionSnapshots: [BridgeExecutionSnapshotPayload]
    let completionEvents: [BridgeCompletionEventSnapshot]

    init(
        manifest: SnapshotManifest,
        goals: [BridgeGoalSnapshot],
        assets: [BridgeAssetSnapshot],
        transactions: [BridgeTransactionSnapshot],
        assetAllocations: [BridgeAssetAllocationSnapshot],
        allocationHistories: [BridgeAllocationHistorySnapshot],
        monthlyPlans: [BridgeMonthlyPlanSnapshot],
        monthlyExecutionRecords: [BridgeMonthlyExecutionRecordSnapshot],
        completedExecutions: [BridgeCompletedExecutionSnapshot] = [],
        executionSnapshots: [BridgeExecutionSnapshotPayload] = [],
        completionEvents: [BridgeCompletionEventSnapshot] = []
    ) {
        self.manifest = manifest
        self.goals = goals
        self.assets = assets
        self.transactions = transactions
        self.assetAllocations = assetAllocations
        self.allocationHistories = allocationHistories
        self.monthlyPlans = monthlyPlans
        self.monthlyExecutionRecords = monthlyExecutionRecords
        self.completedExecutions = completedExecutions
        self.executionSnapshots = executionSnapshots
        self.completionEvents = completionEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifest = try container.decode(SnapshotManifest.self, forKey: .manifest)
        goals = try container.decode([BridgeGoalSnapshot].self, forKey: .goals)
        assets = try container.decode([BridgeAssetSnapshot].self, forKey: .assets)
        transactions = try container.decode([BridgeTransactionSnapshot].self, forKey: .transactions)
        assetAllocations = try container.decode([BridgeAssetAllocationSnapshot].self, forKey: .assetAllocations)
        allocationHistories = try container.decode([BridgeAllocationHistorySnapshot].self, forKey: .allocationHistories)
        monthlyPlans = try container.decode([BridgeMonthlyPlanSnapshot].self, forKey: .monthlyPlans)
        monthlyExecutionRecords = try container.decode([BridgeMonthlyExecutionRecordSnapshot].self, forKey: .monthlyExecutionRecords)
        completedExecutions = try container.decodeIfPresent([BridgeCompletedExecutionSnapshot].self, forKey: .completedExecutions) ?? []
        executionSnapshots = try container.decodeIfPresent([BridgeExecutionSnapshotPayload].self, forKey: .executionSnapshots) ?? []
        completionEvents = try container.decodeIfPresent([BridgeCompletionEventSnapshot].self, forKey: .completionEvents) ?? []
    }

    var entityCounts: [BridgeEntityCount] {
        [
            BridgeEntityCount(name: "Goal", count: goals.count),
            BridgeEntityCount(name: "Asset", count: assets.count),
            BridgeEntityCount(name: "Transaction", count: transactions.count),
            BridgeEntityCount(name: "AssetAllocation", count: assetAllocations.count),
            BridgeEntityCount(name: "AllocationHistory", count: allocationHistories.count),
            BridgeEntityCount(name: "MonthlyPlan", count: monthlyPlans.count),
            BridgeEntityCount(name: "MonthlyExecutionRecord", count: monthlyExecutionRecords.count),
            BridgeEntityCount(name: "CompletedExecution", count: completedExecutions.count),
            BridgeEntityCount(name: "ExecutionSnapshot", count: executionSnapshots.count),
            BridgeEntityCount(name: "CompletionEvent", count: completionEvents.count)
        ]
    }

    func canonicalEncodingData(forFingerprinting: Bool = false) throws -> Data {
        bridgeAppendixCanonicalData(forFingerprinting: forFingerprinting)
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
            monthlyExecutionRecords: monthlyExecutionRecords,
            completedExecutions: completedExecutions,
            executionSnapshots: executionSnapshots,
            completionEvents: completionEvents
        )
    }

    func normalizedForCanonicalEncoding() -> SnapshotEnvelope {
        SnapshotEnvelope(
            manifest: manifest,
            goals: goals.sorted { $0.id.uuidString < $1.id.uuidString },
            assets: assets.sorted {
                if $0.currency.uppercased() != $1.currency.uppercased() {
                    return $0.currency.uppercased() < $1.currency.uppercased()
                }
                if ($0.chainId ?? "").lowercased() != ($1.chainId ?? "").lowercased() {
                    return ($0.chainId ?? "").lowercased() < ($1.chainId ?? "").lowercased()
                }
                if ($0.address ?? "").lowercased() != ($1.address ?? "").lowercased() {
                    return ($0.address ?? "").lowercased() < ($1.address ?? "").lowercased()
                }
                return $0.id.uuidString < $1.id.uuidString
            },
            transactions: transactions.sorted {
                let lhsAsset = $0.assetId?.uuidString ?? ""
                let rhsAsset = $1.assetId?.uuidString ?? ""
                if lhsAsset != rhsAsset { return lhsAsset < rhsAsset }
                if $0.date != $1.date { return $0.date < $1.date }
                if $0.amount != $1.amount { return $0.amount < $1.amount }
                if $0.sourceRawValue != $1.sourceRawValue { return $0.sourceRawValue < $1.sourceRawValue }
                if ($0.externalId ?? "") != ($1.externalId ?? "") { return ($0.externalId ?? "") < ($1.externalId ?? "") }
                return $0.id.uuidString < $1.id.uuidString
            },
            assetAllocations: assetAllocations.sorted {
                let lhsGoal = $0.goalId?.uuidString ?? ""
                let rhsGoal = $1.goalId?.uuidString ?? ""
                if lhsGoal != rhsGoal { return lhsGoal < rhsGoal }
                let lhsAsset = $0.assetId?.uuidString ?? ""
                let rhsAsset = $1.assetId?.uuidString ?? ""
                if lhsAsset != rhsAsset { return lhsAsset < rhsAsset }
                return $0.id.uuidString < $1.id.uuidString
            },
            allocationHistories: allocationHistories.sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                let lhsAsset = $0.assetId?.uuidString ?? ""
                let rhsAsset = $1.assetId?.uuidString ?? ""
                if lhsAsset != rhsAsset { return lhsAsset < rhsAsset }
                let lhsGoal = $0.goalId?.uuidString ?? ""
                let rhsGoal = $1.goalId?.uuidString ?? ""
                if lhsGoal != rhsGoal { return lhsGoal < rhsGoal }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            },
            monthlyPlans: monthlyPlans.sorted {
                if $0.monthLabel != $1.monthLabel { return $0.monthLabel < $1.monthLabel }
                let lhsGoal = $0.goalId.uuidString
                let rhsGoal = $1.goalId.uuidString
                if lhsGoal != rhsGoal { return lhsGoal < rhsGoal }
                return $0.id.uuidString < $1.id.uuidString
            },
            monthlyExecutionRecords: monthlyExecutionRecords.sorted {
                if $0.monthLabel != $1.monthLabel { return $0.monthLabel < $1.monthLabel }
                return $0.id.uuidString < $1.id.uuidString
            },
            completedExecutions: completedExecutions.sorted {
                if $0.monthLabel != $1.monthLabel { return $0.monthLabel < $1.monthLabel }
                return $0.id.uuidString < $1.id.uuidString
            },
            executionSnapshots: executionSnapshots.sorted {
                if $0.capturedAt != $1.capturedAt { return $0.capturedAt < $1.capturedAt }
                return $0.id.uuidString < $1.id.uuidString
            },
            completionEvents: completionEvents.sorted {
                if $0.monthLabel != $1.monthLabel { return $0.monthLabel < $1.monthLabel }
                if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                return $0.eventId.uuidString < $1.eventId.uuidString
            }
        )
    }

    func normalizedForFingerprinting() -> SnapshotEnvelope {
        SnapshotEnvelope(
            manifest: manifest
                .normalizedForDatasetFingerprinting()
                .withBaseDatasetFingerprint(""),
            goals: goals.sorted { $0.id.uuidString < $1.id.uuidString },
            assets: assets.sorted {
                if $0.currency.uppercased() != $1.currency.uppercased() {
                    return $0.currency.uppercased() < $1.currency.uppercased()
                }
                if ($0.chainId ?? "").lowercased() != ($1.chainId ?? "").lowercased() {
                    return ($0.chainId ?? "").lowercased() < ($1.chainId ?? "").lowercased()
                }
                if ($0.address ?? "").lowercased() != ($1.address ?? "").lowercased() {
                    return ($0.address ?? "").lowercased() < ($1.address ?? "").lowercased()
                }
                return $0.id.uuidString < $1.id.uuidString
            },
            transactions: transactions.sorted {
                let lhsAsset = $0.assetId?.uuidString ?? ""
                let rhsAsset = $1.assetId?.uuidString ?? ""
                if lhsAsset != rhsAsset { return lhsAsset < rhsAsset }
                if $0.date != $1.date { return $0.date < $1.date }
                if $0.amount != $1.amount { return $0.amount < $1.amount }
                if $0.sourceRawValue != $1.sourceRawValue { return $0.sourceRawValue < $1.sourceRawValue }
                if ($0.externalId ?? "") != ($1.externalId ?? "") { return ($0.externalId ?? "") < ($1.externalId ?? "") }
                return $0.id.uuidString < $1.id.uuidString
            },
            assetAllocations: assetAllocations.sorted {
                let lhsGoal = $0.goalId?.uuidString ?? ""
                let rhsGoal = $1.goalId?.uuidString ?? ""
                if lhsGoal != rhsGoal { return lhsGoal < rhsGoal }
                let lhsAsset = $0.assetId?.uuidString ?? ""
                let rhsAsset = $1.assetId?.uuidString ?? ""
                if lhsAsset != rhsAsset { return lhsAsset < rhsAsset }
                return $0.id.uuidString < $1.id.uuidString
            },
            allocationHistories: allocationHistories.sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                let lhsAsset = $0.assetId?.uuidString ?? ""
                let rhsAsset = $1.assetId?.uuidString ?? ""
                if lhsAsset != rhsAsset { return lhsAsset < rhsAsset }
                let lhsGoal = $0.goalId?.uuidString ?? ""
                let rhsGoal = $1.goalId?.uuidString ?? ""
                if lhsGoal != rhsGoal { return lhsGoal < rhsGoal }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            },
            monthlyPlans: monthlyPlans.sorted {
                if $0.monthLabel != $1.monthLabel { return $0.monthLabel < $1.monthLabel }
                let lhsGoal = $0.goalId.uuidString
                let rhsGoal = $1.goalId.uuidString
                if lhsGoal != rhsGoal { return lhsGoal < rhsGoal }
                return $0.id.uuidString < $1.id.uuidString
            },
            monthlyExecutionRecords: monthlyExecutionRecords.sorted {
                if $0.monthLabel != $1.monthLabel { return $0.monthLabel < $1.monthLabel }
                return $0.id.uuidString < $1.id.uuidString
            },
            completedExecutions: completedExecutions.sorted {
                if $0.monthLabel != $1.monthLabel { return $0.monthLabel < $1.monthLabel }
                return $0.id.uuidString < $1.id.uuidString
            },
            executionSnapshots: executionSnapshots.sorted {
                if $0.capturedAt != $1.capturedAt { return $0.capturedAt < $1.capturedAt }
                return $0.id.uuidString < $1.id.uuidString
            },
            completionEvents: completionEvents.sorted {
                if $0.monthLabel != $1.monthLabel { return $0.monthLabel < $1.monthLabel }
                if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                return $0.eventId.uuidString < $1.eventId.uuidString
            }
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
    let signingAlgorithm: String
    let signerPublicKeyRepresentation: String
    let signedAt: Date
    let signature: String

    init(
        packageID: String,
        snapshotID: UUID,
        canonicalEncodingVersion: String,
        baseDatasetFingerprint: String,
        editedDatasetFingerprint: String,
        snapshotEnvelope: SnapshotEnvelope,
        signingKeyID: String,
        signingAlgorithm: String,
        signerPublicKeyRepresentation: String,
        signedAt: Date,
        signature: String
    ) {
        self.packageID = packageID
        self.snapshotID = snapshotID
        self.canonicalEncodingVersion = canonicalEncodingVersion
        self.baseDatasetFingerprint = baseDatasetFingerprint
        self.editedDatasetFingerprint = editedDatasetFingerprint
        self.snapshotEnvelope = snapshotEnvelope
        self.signingKeyID = signingKeyID
        self.signingAlgorithm = signingAlgorithm
        self.signerPublicKeyRepresentation = signerPublicKeyRepresentation
        self.signedAt = signedAt
        self.signature = signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packageID = try container.decode(String.self, forKey: .packageID)
        snapshotID = try container.decode(UUID.self, forKey: .snapshotID)
        canonicalEncodingVersion = try container.decode(String.self, forKey: .canonicalEncodingVersion)
        baseDatasetFingerprint = try container.decode(String.self, forKey: .baseDatasetFingerprint)
        editedDatasetFingerprint = try container.decode(String.self, forKey: .editedDatasetFingerprint)
        snapshotEnvelope = try container.decode(SnapshotEnvelope.self, forKey: .snapshotEnvelope)
        signingKeyID = try container.decode(String.self, forKey: .signingKeyID)
        signingAlgorithm = try container.decodeIfPresent(String.self, forKey: .signingAlgorithm) ?? "legacy-unsigned"
        signerPublicKeyRepresentation = try container.decodeIfPresent(String.self, forKey: .signerPublicKeyRepresentation) ?? ""
        signedAt = try container.decode(Date.self, forKey: .signedAt)
        signature = try container.decode(String.self, forKey: .signature)
    }

    func canonicalEncodingData() throws -> Data {
        bridgeAppendixCanonicalData(includePackageID: true, signatureValue: .string(signature))
    }

    func signingPayloadData() throws -> Data {
        bridgeAppendixCanonicalData(includePackageID: true, signatureValue: .null)
    }

    func canonicalPackageBodyData() throws -> Data {
        bridgeAppendixCanonicalData(includePackageID: false, signatureValue: nil)
    }

    func computedPackageID() throws -> String {
        BudgetSnapshotIdentity.sha256(String(decoding: try canonicalPackageBodyData(), as: UTF8.self))
    }

    var signerFingerprint: String {
        guard let publicKeyData = Data(base64Encoded: signerPublicKeyRepresentation) else {
            return ""
        }
        return LocalBridgeIdentityStore.fingerprint(publicKeyData: publicKeyData)
    }
}

struct LocalBridgeTransientWorkspaceArtifact: Equatable, Sendable {
    let workspaceID: UUID
    let createdAt: Date
    let fileURL: URL

    var displayName: String {
        fileURL.lastPathComponent
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

        if pendingAction == .trustRevoked {
            return Self(
                availabilityState: .pairingRequired,
                pendingAction: .trustRevoked,
                lastSyncOutcome: lastSyncOutcome,
                trustedDevices: trustedDevices,
                importReviewStatus: importReviewStatus,
                capabilityManifest: capabilityManifest,
                sessionState: sessionState,
                detail: "Trust was revoked for the last bridge peer. Re-pair before any later snapshot exchange."
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

        return Self(
            availabilityState: .ready,
            pendingAction: pendingAction,
            lastSyncOutcome: lastSyncOutcome,
            trustedDevices: trustedDevices,
            importReviewStatus: importReviewStatus,
            capabilityManifest: capabilityManifest,
            sessionState: sessionState,
            detail: "CloudKit runtime is active. Local Bridge Sync can export a shareable snapshot artifact and validate a returned import package from Files."
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

    func normalizedForDatasetFingerprinting() -> SnapshotManifest {
        SnapshotManifest(
            snapshotID: bridgeFingerprintNeutralSnapshotID,
            canonicalEncodingVersion: canonicalEncodingVersion,
            snapshotSchemaVersion: snapshotSchemaVersion,
            exportedAt: bridgeFingerprintNeutralExportedAt,
            appModelSchemaVersion: appModelSchemaVersion,
            entityCounts: entityCounts,
            baseDatasetFingerprint: baseDatasetFingerprint
        )
    }
}
