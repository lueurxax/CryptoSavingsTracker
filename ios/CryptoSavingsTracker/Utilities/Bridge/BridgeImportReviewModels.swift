import Foundation

enum BridgeImportSignatureStatus: String, Codable, Equatable, Sendable {
    case notVerified
    case valid
    case invalid
    case signerUntrusted

    var displayTitle: String {
        switch self {
        case .notVerified: return "Not Verified"
        case .valid: return "Valid Signature"
        case .invalid: return "Invalid Signature"
        case .signerUntrusted: return "Signer Not Trusted"
        }
    }
}

enum BridgeImportValidationStatus: String, Codable, Equatable, Sendable {
    case notRun
    case passed
    case warnings
    case failed

    var displayTitle: String {
        switch self {
        case .notRun: return "Not Run"
        case .passed: return "Passed"
        case .warnings: return "Warnings"
        case .failed: return "Failed"
        }
    }
}

enum BridgeImportDriftStatus: String, Codable, Equatable, Sendable {
    case unknown
    case none
    case additiveOnly
    case conflicting
    case destructive

    var displayTitle: String {
        switch self {
        case .unknown: return "Unknown"
        case .none: return "No Drift"
        case .additiveOnly: return "Additive Drift"
        case .conflicting: return "Conflicting Drift"
        case .destructive: return "Destructive Drift"
        }
    }
}

enum BridgeImportOperatorDecisionState: String, Codable, Equatable, Sendable {
    case notRequired
    case awaitingDecision
    case approvedPlaceholder
    case rejected

    var displayTitle: String {
        switch self {
        case .notRequired: return "Not Required"
        case .awaitingDecision: return "Awaiting Operator Decision"
        case .approvedPlaceholder: return "Approved (Not Applied)"
        case .rejected: return "Rejected"
        }
    }
}

struct BridgeImportEntityDeltaDTO: Codable, Equatable, Sendable {
    let entityName: String
    let incomingCount: Int
    let existingCount: Int
    let changedCount: Int
}

struct BridgeSignedImportPackageSummaryDTO: Codable, Equatable, Sendable {
    let packageID: UUID
    let packageVersion: String
    let canonicalEncodingVersion: String
    let sourceDeviceName: String
    let sourceDeviceFingerprint: String
    let producedAt: Date
    let expiresAt: Date
    let payloadBytes: Int64
    let digestHexPrefix: String
    let signatureStatus: BridgeImportSignatureStatus
}

struct BridgeImportReviewSummaryDTO: Codable, Equatable, Sendable {
    let package: BridgeSignedImportPackageSummaryDTO
    let validationStatus: BridgeImportValidationStatus
    let driftStatus: BridgeImportDriftStatus
    let warnings: [String]
    let blockingIssues: [String]
    let entityDeltas: [BridgeImportEntityDeltaDTO]

    var changedEntityCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: entityDeltas.map { ($0.entityName, $0.changedCount) })
    }
}

struct ImportReviewSummary: Codable, Equatable, Sendable {
    let packageID: String
    let snapshotID: UUID
    let sourceDeviceName: String
    let signatureStatus: BridgeImportSignatureStatus
    let validationStatus: BridgeImportValidationStatus
    let driftStatus: BridgeImportDriftStatus
    let changedEntityCounts: [String: Int]
    let warnings: [String]
    let blockingIssues: [String]

    init(
        packageID: String,
        snapshotID: UUID,
        sourceDeviceName: String,
        signatureStatus: BridgeImportSignatureStatus,
        validationStatus: BridgeImportValidationStatus,
        driftStatus: BridgeImportDriftStatus,
        changedEntityCounts: [String: Int],
        warnings: [String],
        blockingIssues: [String]
    ) {
        self.packageID = packageID
        self.snapshotID = snapshotID
        self.sourceDeviceName = sourceDeviceName
        self.signatureStatus = signatureStatus
        self.validationStatus = validationStatus
        self.driftStatus = driftStatus
        self.changedEntityCounts = changedEntityCounts
        self.warnings = warnings
        self.blockingIssues = blockingIssues
    }

    init(
        package: SignedImportPackage,
        sourceDeviceName: String,
        reviewDTO: BridgeImportReviewSummaryDTO
    ) {
        self.init(
            packageID: package.packageID,
            snapshotID: package.snapshotID,
            sourceDeviceName: sourceDeviceName,
            signatureStatus: reviewDTO.package.signatureStatus,
            validationStatus: reviewDTO.validationStatus,
            driftStatus: reviewDTO.driftStatus,
            changedEntityCounts: reviewDTO.changedEntityCounts,
            warnings: reviewDTO.warnings,
            blockingIssues: reviewDTO.blockingIssues
        )
    }
}

extension SignedImportPackage {
    var changedEntityCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: snapshotEnvelope.entityCounts.map { ($0.name, $0.count) })
    }
}
