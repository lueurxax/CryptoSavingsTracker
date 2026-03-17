import Foundation

@MainActor
final class LocalBridgeImportValidationService {
    private let snapshotExportService: LocalBridgeSnapshotExportService
    private let capabilityManifest: BridgeCapabilityManifest

    init(
        snapshotExportService: LocalBridgeSnapshotExportService,
        capabilityManifest: BridgeCapabilityManifest
    ) {
        self.snapshotExportService = snapshotExportService
        self.capabilityManifest = capabilityManifest
    }

    convenience init(snapshotExportService: LocalBridgeSnapshotExportService) {
        self.init(
            snapshotExportService: snapshotExportService,
            capabilityManifest: .current()
        )
    }

    convenience init() {
        self.init(
            snapshotExportService: LocalBridgeSnapshotExportService(),
            capabilityManifest: .current()
        )
    }

    func makePlaceholderPackage(
        from snapshotEnvelope: SnapshotEnvelope,
        trustedDevice: TrustedBridgeDevice?
    ) throws -> SignedImportPackage {
        let editedSnapshot = try snapshotEnvelope.withComputedFingerprint()
        let signingKeyID = trustedDevice?.id.uuidString ?? "unpaired-placeholder"
        let packageBody = [
            editedSnapshot.manifest.snapshotID.uuidString,
            editedSnapshot.manifest.baseDatasetFingerprint,
            editedSnapshot.manifest.baseDatasetFingerprint,
            signingKeyID
        ].joined(separator: "|")

        return SignedImportPackage(
            packageID: BudgetSnapshotIdentity.sha256(packageBody),
            snapshotID: editedSnapshot.manifest.snapshotID,
            canonicalEncodingVersion: editedSnapshot.manifest.canonicalEncodingVersion,
            baseDatasetFingerprint: editedSnapshot.manifest.baseDatasetFingerprint,
            editedDatasetFingerprint: editedSnapshot.manifest.baseDatasetFingerprint,
            snapshotEnvelope: editedSnapshot,
            signingKeyID: signingKeyID,
            signedAt: Date(),
            signature: "placeholder-signature-\(signingKeyID)"
        )
    }

    func review(
        package: SignedImportPackage,
        trustedDevice: TrustedBridgeDevice?,
        currentSnapshot: SnapshotEnvelope? = nil
    ) throws -> BridgeImportReviewStatus {
        let currentSnapshot = if let currentSnapshot {
            currentSnapshot
        } else {
            try snapshotExportService.exportAuthoritativeSnapshot()
        }

        var warnings: [String] = []
        var blockingIssues: [String] = []

        if package.canonicalEncodingVersion != capabilityManifest.maximumSupportedCanonicalEncodingVersion {
            blockingIssues.append("Package canonical encoding \(package.canonicalEncodingVersion) is incompatible with this build.")
        }

        let incomingSchema = package.snapshotEnvelope.manifest.snapshotSchemaVersion
        if incomingSchema < capabilityManifest.minimumSupportedSnapshotSchemaVersion ||
            incomingSchema > capabilityManifest.maximumSupportedSnapshotSchemaVersion {
            blockingIssues.append("Snapshot schema v\(incomingSchema) is outside the supported range \(capabilityManifest.minimumSupportedSnapshotSchemaVersion)-\(capabilityManifest.maximumSupportedSnapshotSchemaVersion).")
        }

        if package.snapshotID != package.snapshotEnvelope.manifest.snapshotID {
            blockingIssues.append("Signed package snapshot identity does not match the embedded snapshot manifest.")
        }

        let driftStatus: BridgeImportDriftStatus
        if package.baseDatasetFingerprint == currentSnapshot.manifest.baseDatasetFingerprint {
            driftStatus = .none
        } else {
            driftStatus = .conflicting
            blockingIssues.append("The authoritative CloudKit dataset changed since this bridge snapshot was exported.")
        }

        warnings.append("Cryptographic signature verification is not implemented in this build; package trust is modeled only.")

        let entityDeltas = [
            makeDelta(entityName: "Goal", incoming: package.snapshotEnvelope.goals, existing: currentSnapshot.goals, id: \.id),
            makeDelta(entityName: "Asset", incoming: package.snapshotEnvelope.assets, existing: currentSnapshot.assets, id: \.id),
            makeDelta(entityName: "Transaction", incoming: package.snapshotEnvelope.transactions, existing: currentSnapshot.transactions, id: \.id),
            makeDelta(entityName: "AssetAllocation", incoming: package.snapshotEnvelope.assetAllocations, existing: currentSnapshot.assetAllocations, id: \.id),
            makeDelta(entityName: "AllocationHistory", incoming: package.snapshotEnvelope.allocationHistories, existing: currentSnapshot.allocationHistories, id: \.id),
            makeDelta(entityName: "MonthlyPlan", incoming: package.snapshotEnvelope.monthlyPlans, existing: currentSnapshot.monthlyPlans, id: \.id),
            makeDelta(entityName: "MonthlyExecutionRecord", incoming: package.snapshotEnvelope.monthlyExecutionRecords, existing: currentSnapshot.monthlyExecutionRecords, id: \.id)
        ]

        let changedEntityCounts = Dictionary(uniqueKeysWithValues: entityDeltas.map { ($0.entityName, $0.changedCount) })
        if (changedEntityCounts["Goal"] ?? 0) > 0 {
            warnings.append("Goal metadata or target amounts would change if this package were applied.")
        }
        if (changedEntityCounts["Transaction"] ?? 0) > 0 {
            warnings.append("Transaction history would change if this package were applied.")
        }
        if (changedEntityCounts["AssetAllocation"] ?? 0) > 0 || (changedEntityCounts["AllocationHistory"] ?? 0) > 0 {
            warnings.append("Allocation state would change if this package were applied.")
        }
        if (changedEntityCounts["MonthlyPlan"] ?? 0) > 0 || (changedEntityCounts["MonthlyExecutionRecord"] ?? 0) > 0 {
            warnings.append("Monthly planning or execution records would change if this package were applied.")
        }

        let validationStatus: BridgeImportValidationStatus = blockingIssues.isEmpty
            ? (warnings.isEmpty ? .passed : .warnings)
            : .failed

        let sourceDeviceName = trustedDevice?.displayName ?? "Trusted Mac"
        let sourceFingerprint = trustedDevice?.shortFingerprint ?? "unknown"
        let packageBytes = try Int64(package.canonicalEncodingData().count)
        let reviewSummary = BridgeImportReviewSummaryDTO(
            package: BridgeSignedImportPackageSummaryDTO(
                packageID: package.snapshotID,
                packageVersion: "bridge-import-v1",
                canonicalEncodingVersion: package.canonicalEncodingVersion,
                sourceDeviceName: sourceDeviceName,
                sourceDeviceFingerprint: sourceFingerprint,
                producedAt: package.snapshotEnvelope.manifest.exportedAt,
                expiresAt: package.signedAt.addingTimeInterval(30 * 60),
                payloadBytes: packageBytes,
                digestHexPrefix: String(package.packageID.prefix(12)),
                signatureStatus: .notVerified
            ),
            validationStatus: validationStatus,
            driftStatus: driftStatus,
            warnings: warnings,
            blockingIssues: blockingIssues,
            entityDeltas: entityDeltas
        )

        let importReviewSummary = ImportReviewSummary(
            package: package,
            sourceDeviceName: sourceDeviceName,
            reviewDTO: reviewSummary
        )

        return BridgeImportReviewStatus(
            summary: blockingIssues.isEmpty
                ? "Signed import package is structurally valid. Operator review is required before apply."
                : "Signed import package is blocked until validation issues are resolved.",
            requiresOperatorReview: blockingIssues.isEmpty,
            validationStatus: validationStatus,
            driftStatus: driftStatus,
            operatorDecision: .awaitingDecision,
            importReviewSummary: importReviewSummary,
            reviewSummaryDTO: reviewSummary,
            validationWarnings: warnings,
            blockingIssues: blockingIssues
        )
    }

    private func makeDelta<Snapshot: Equatable>(
        entityName: String,
        incoming: [Snapshot],
        existing: [Snapshot],
        id: KeyPath<Snapshot, UUID>
    ) -> BridgeImportEntityDeltaDTO {
        let incomingByID = Dictionary(uniqueKeysWithValues: incoming.map { ($0[keyPath: id], $0) })
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0[keyPath: id], $0) })
        let allIDs = Set(incomingByID.keys).union(existingByID.keys)

        let changedCount = allIDs.reduce(into: 0) { partial, entityID in
            switch (incomingByID[entityID], existingByID[entityID]) {
            case let (incomingValue?, existingValue?):
                if incomingValue != existingValue {
                    partial += 1
                }
            case (.some, .none), (.none, .some):
                partial += 1
            case (.none, .none):
                break
            }
        }

        return BridgeImportEntityDeltaDTO(
            entityName: entityName,
            incomingCount: incoming.count,
            existingCount: existing.count,
            changedCount: changedCount
        )
    }
}
