import Foundation

@MainActor
final class LocalBridgeImportValidationService {
    private let snapshotExportService: LocalBridgeSnapshotExportService
    private let capabilityManifest: BridgeCapabilityManifest
    private let signingService: BridgePackageSigning

    init(
        snapshotExportService: LocalBridgeSnapshotExportService,
        capabilityManifest: BridgeCapabilityManifest,
        signingService: BridgePackageSigning
    ) {
        self.snapshotExportService = snapshotExportService
        self.capabilityManifest = capabilityManifest
        self.signingService = signingService
    }

    convenience init(snapshotExportService: LocalBridgeSnapshotExportService) {
        self.init(
            snapshotExportService: snapshotExportService,
            capabilityManifest: BridgeCapabilityManifest.current(),
            signingService: LocalBridgeIdentityStore()
        )
    }

    convenience init() {
        self.init(
            snapshotExportService: LocalBridgeSnapshotExportService(),
            capabilityManifest: BridgeCapabilityManifest.current(),
            signingService: LocalBridgeIdentityStore()
        )
    }

    func makeSignedPackage(
        from snapshotEnvelope: SnapshotEnvelope,
        trustedDevice: TrustedBridgeDevice?
    ) throws -> SignedImportPackage {
        let baseDatasetFingerprint = snapshotEnvelope.manifest.baseDatasetFingerprint
        let editedSnapshot = try snapshotEnvelope.withComputedFingerprint()
        let signingKeyID = trustedDevice?.signingKeyID ?? trustedDevice?.id.uuidString ?? "unpaired-placeholder"
        let signingIdentity = try signingService.identity(for: signingKeyID)
        let unsignedPackage = SignedImportPackage(
            packageID: "",
            snapshotID: editedSnapshot.manifest.snapshotID,
            canonicalEncodingVersion: editedSnapshot.manifest.canonicalEncodingVersion,
            baseDatasetFingerprint: baseDatasetFingerprint,
            editedDatasetFingerprint: editedSnapshot.manifest.baseDatasetFingerprint,
            snapshotEnvelope: editedSnapshot,
            signingKeyID: signingIdentity.signingKeyID,
            signingAlgorithm: signingIdentity.algorithm,
            signerPublicKeyRepresentation: signingIdentity.publicKeyRepresentation,
            signedAt: Date(),
            signature: ""
        )
        let packageBody = try unsignedPackage.canonicalPackageBodyData()
        let packageID = BudgetSnapshotIdentity.sha256(String(decoding: packageBody, as: UTF8.self))
        let bodyPackage = SignedImportPackage(
            packageID: packageID,
            snapshotID: unsignedPackage.snapshotID,
            canonicalEncodingVersion: unsignedPackage.canonicalEncodingVersion,
            baseDatasetFingerprint: unsignedPackage.baseDatasetFingerprint,
            editedDatasetFingerprint: unsignedPackage.editedDatasetFingerprint,
            snapshotEnvelope: unsignedPackage.snapshotEnvelope,
            signingKeyID: unsignedPackage.signingKeyID,
            signingAlgorithm: unsignedPackage.signingAlgorithm,
            signerPublicKeyRepresentation: unsignedPackage.signerPublicKeyRepresentation,
            signedAt: unsignedPackage.signedAt,
            signature: ""
        )
        let signature = try signingService.sign(
            bodyPackage.signingPayloadData(),
            keyID: signingIdentity.signingKeyID
        )

        return SignedImportPackage(
            packageID: packageID,
            snapshotID: bodyPackage.snapshotID,
            canonicalEncodingVersion: bodyPackage.canonicalEncodingVersion,
            baseDatasetFingerprint: bodyPackage.baseDatasetFingerprint,
            editedDatasetFingerprint: bodyPackage.editedDatasetFingerprint,
            snapshotEnvelope: bodyPackage.snapshotEnvelope,
            signingKeyID: bodyPackage.signingKeyID,
            signingAlgorithm: bodyPackage.signingAlgorithm,
            signerPublicKeyRepresentation: bodyPackage.signerPublicKeyRepresentation,
            signedAt: bodyPackage.signedAt,
            signature: signature
        )
    }

    func makePlaceholderPackage(
        from snapshotEnvelope: SnapshotEnvelope,
        trustedDevice: TrustedBridgeDevice?
    ) throws -> SignedImportPackage {
        try makeSignedPackage(from: snapshotEnvelope, trustedDevice: trustedDevice)
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

        let computedPackageID = try package.computedPackageID()
        if package.packageID != computedPackageID {
            blockingIssues.append("Signed package package ID does not match the canonical package body.")
        }

        let computedEditedFingerprint = try package.snapshotEnvelope.computedDatasetFingerprint()
        if package.editedDatasetFingerprint != computedEditedFingerprint {
            blockingIssues.append("Signed package edited dataset fingerprint does not match the embedded snapshot payload.")
        }

        let expectedPackageID = BudgetSnapshotIdentity.sha256(String(decoding: try package.canonicalPackageBodyData(), as: UTF8.self))
        if package.packageID != expectedPackageID {
            blockingIssues.append("Signed package identifier does not match the canonical package body.")
        }

        if package.snapshotEnvelope.manifest.baseDatasetFingerprint != computedEditedFingerprint {
            blockingIssues.append("Embedded snapshot manifest fingerprint does not match the canonical bridge payload.")
        }

        let (signatureStatus, trustStatus) = evaluateSignatureStatus(
            package: package,
            trustedDevice: trustedDevice,
            warnings: &warnings,
            blockingIssues: &blockingIssues
        )

        let driftStatus: BridgeImportDriftStatus
        if package.baseDatasetFingerprint == currentSnapshot.manifest.baseDatasetFingerprint {
            driftStatus = .none
        } else {
            driftStatus = .conflicting
            blockingIssues.append("The authoritative CloudKit dataset changed since this bridge snapshot was exported.")
        }

        let entityDeltas = [
            makeDelta(entityName: "Goal", incoming: package.snapshotEnvelope.goals, existing: currentSnapshot.goals, id: \.id),
            makeDelta(entityName: "Asset", incoming: package.snapshotEnvelope.assets, existing: currentSnapshot.assets, id: \.id),
            makeDelta(entityName: "Transaction", incoming: package.snapshotEnvelope.transactions, existing: currentSnapshot.transactions, id: \.id),
            makeDelta(entityName: "AssetAllocation", incoming: package.snapshotEnvelope.assetAllocations, existing: currentSnapshot.assetAllocations, id: \.id),
            makeDelta(entityName: "AllocationHistory", incoming: package.snapshotEnvelope.allocationHistories, existing: currentSnapshot.allocationHistories, id: \.id),
            makeDelta(entityName: "MonthlyPlan", incoming: package.snapshotEnvelope.monthlyPlans, existing: currentSnapshot.monthlyPlans, id: \.id),
            makeDelta(entityName: "MonthlyExecutionRecord", incoming: package.snapshotEnvelope.monthlyExecutionRecords, existing: currentSnapshot.monthlyExecutionRecords, id: \.id),
            makeDelta(entityName: "CompletedExecution", incoming: package.snapshotEnvelope.completedExecutions, existing: currentSnapshot.completedExecutions, id: \.id),
            makeDelta(entityName: "ExecutionSnapshot", incoming: package.snapshotEnvelope.executionSnapshots, existing: currentSnapshot.executionSnapshots, id: \.id),
            makeDelta(entityName: "CompletionEvent", incoming: package.snapshotEnvelope.completionEvents, existing: currentSnapshot.completionEvents, id: \.eventId)
        ]
        let concreteDiffs =
            makeGoalDiffs(incoming: package.snapshotEnvelope.goals, existing: currentSnapshot.goals) +
            makeTransactionDiffs(incoming: package.snapshotEnvelope.transactions, existing: currentSnapshot.transactions) +
            makeAllocationDiffs(incoming: package.snapshotEnvelope.assetAllocations, existing: currentSnapshot.assetAllocations) +
            makeMonthlyPlanDiffs(incoming: package.snapshotEnvelope.monthlyPlans, existing: currentSnapshot.monthlyPlans)

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
        if (changedEntityCounts["CompletedExecution"] ?? 0) > 0 ||
            (changedEntityCounts["ExecutionSnapshot"] ?? 0) > 0 ||
            (changedEntityCounts["CompletionEvent"] ?? 0) > 0 {
            warnings.append("Execution history snapshots would change if this package were applied.")
        }

        let validationStatus: BridgeImportValidationStatus = blockingIssues.isEmpty
            ? (warnings.isEmpty ? .passed : .warnings)
            : .failed

        let sourceDeviceName = trustedDevice?.displayName ?? "Trusted Mac"
        let sourceFingerprint = shortFingerprint(trustedDevice?.fingerprint ?? package.signerFingerprint)
        let packageBytes = try Int64(package.canonicalEncodingData().count)
        let reviewSummary = BridgeImportReviewSummaryDTO(
            package: BridgeSignedImportPackageSummaryDTO(
                packageID: package.packageID,
                packageVersion: "bridge-import-v1",
                canonicalEncodingVersion: package.canonicalEncodingVersion,
                sourceDeviceName: sourceDeviceName,
                sourceDeviceFingerprint: sourceFingerprint,
                producedAt: package.snapshotEnvelope.manifest.exportedAt,
                expiresAt: package.signedAt.addingTimeInterval(30 * 60),
                payloadBytes: packageBytes,
                digestHexPrefix: String(package.packageID.prefix(12)),
                signatureStatus: signatureStatus,
                trustStatus: trustStatus
            ),
            validationStatus: validationStatus,
            driftStatus: driftStatus,
            warnings: warnings,
            blockingIssues: blockingIssues,
            entityDeltas: entityDeltas,
            concreteDiffs: concreteDiffs
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

    private func evaluateSignatureStatus(
        package: SignedImportPackage,
        trustedDevice: TrustedBridgeDevice?,
        warnings: inout [String],
        blockingIssues: inout [String]
    ) -> (BridgeImportSignatureStatus, BridgeImportTrustStatus) {
        guard let trustedDevice else {
            blockingIssues.append("Bridge package signer is not an active trusted device on this install.")
            return (.signerUntrusted, .signerUntrusted)
        }

        guard trustedDevice.trustState == .active else {
            blockingIssues.append("Bridge package signer is not an active trusted device on this install.")
            return (.signerUntrusted, .trustRevoked)
        }

        let expectedSigningKeyID = trustedDevice.signingKeyID ?? trustedDevice.id.uuidString
        guard package.signingKeyID == expectedSigningKeyID else {
            blockingIssues.append("Bridge package signing key does not match the selected trusted device.")
            return (.signerUntrusted, .signerUntrusted)
        }

        guard let pinnedPublicKey = trustedDevice.publicKeyRepresentation, pinnedPublicKey.isEmpty == false else {
            blockingIssues.append("Trusted device is missing pinned bridge signing material on this install.")
            return (.signerUntrusted, .signerUntrusted)
        }

        do {
            try signingService.verify(
                signature: package.signature,
                payload: try package.signingPayloadData(),
                publicKeyRepresentation: pinnedPublicKey
            )
        } catch {
            blockingIssues.append("Bridge package signature verification failed: \(error.localizedDescription)")
            return (.invalid, .signerUntrusted)
        }

        if !package.signerFingerprint.isEmpty &&
            trustedDevice.fingerprint.caseInsensitiveCompare(package.signerFingerprint) != .orderedSame {
            warnings.append("Trusted device fingerprint metadata does not match the package signing key fingerprint; review the pairing record before enabling apply.")
        }

        return (.valid, .activeTrusted)
    }

    private func shortFingerprint(_ fingerprint: String) -> String {
        fingerprint.count > 12 ? String(fingerprint.prefix(12)) + "…" : fingerprint
    }

    private func isoTimestamp(_ date: Date) -> String {
        date.ISO8601Format(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false))
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

    private func makeGoalDiffs(
        incoming: [BridgeGoalSnapshot],
        existing: [BridgeGoalSnapshot]
    ) -> [BridgeImportConcreteDiffDTO] {
        makeConcreteDiffs(entityName: "Goal", incoming: incoming, existing: existing, id: \.id) { goal in
            "\(goal.name) • \(goal.targetAmount.formatted()) \(goal.currency) • deadline \(isoTimestamp(goal.deadline)) • status \(goal.lifecycleStatusRawValue)"
        } title: { goal in
            "Goal \(goal.name)"
        }
    }

    private func makeTransactionDiffs(
        incoming: [BridgeTransactionSnapshot],
        existing: [BridgeTransactionSnapshot]
    ) -> [BridgeImportConcreteDiffDTO] {
        makeConcreteDiffs(entityName: "Transaction", incoming: incoming, existing: existing, id: \.id) { transaction in
            let asset = transaction.assetId?.uuidString ?? "unassigned"
            return "\(transaction.amount.formatted()) on \(isoTimestamp(transaction.date)) • asset \(asset) • source \(transaction.sourceRawValue)"
        } title: { transaction in
            "Transaction \(transaction.id.uuidString.prefix(8))"
        }
    }

    private func makeAllocationDiffs(
        incoming: [BridgeAssetAllocationSnapshot],
        existing: [BridgeAssetAllocationSnapshot]
    ) -> [BridgeImportConcreteDiffDTO] {
        makeConcreteDiffs(entityName: "AssetAllocation", incoming: incoming, existing: existing, id: \.id) { allocation in
            let asset = allocation.assetId?.uuidString ?? "missing-asset"
            let goal = allocation.goalId?.uuidString ?? "missing-goal"
            return "asset \(asset) • goal \(goal) • amount \(allocation.amount.formatted())"
        } title: { allocation in
            "Allocation \(allocation.id.uuidString.prefix(8))"
        }
    }

    private func makeMonthlyPlanDiffs(
        incoming: [BridgeMonthlyPlanSnapshot],
        existing: [BridgeMonthlyPlanSnapshot]
    ) -> [BridgeImportConcreteDiffDTO] {
        makeConcreteDiffs(entityName: "MonthlyPlan", incoming: incoming, existing: existing, id: \.id) { plan in
            "goal \(plan.goalId.uuidString) • month \(plan.monthLabel) • required \(plan.requiredMonthly.formatted()) • remaining \(plan.remainingAmount.formatted()) • state \(plan.stateRawValue)"
        } title: { plan in
            "Monthly Plan \(plan.monthLabel)"
        }
    }

    private func makeConcreteDiffs<Snapshot: Equatable>(
        entityName: String,
        incoming: [Snapshot],
        existing: [Snapshot],
        id: KeyPath<Snapshot, UUID>,
        summary: (Snapshot) -> String,
        title: (Snapshot) -> String
    ) -> [BridgeImportConcreteDiffDTO] {
        let incomingByID = Dictionary(uniqueKeysWithValues: incoming.map { ($0[keyPath: id], $0) })
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0[keyPath: id], $0) })
        let allIDs = Set(incomingByID.keys).union(existingByID.keys).sorted { $0.uuidString < $1.uuidString }

        return allIDs.compactMap { entityID in
            switch (incomingByID[entityID], existingByID[entityID]) {
            case let (incomingValue?, existingValue?):
                guard incomingValue != existingValue else { return nil }
                return BridgeImportConcreteDiffDTO(
                    entityName: entityName,
                    entityID: entityID,
                    changeKind: .updated,
                    title: title(incomingValue),
                    beforeSummary: summary(existingValue),
                    afterSummary: summary(incomingValue)
                )
            case let (incomingValue?, nil):
                return BridgeImportConcreteDiffDTO(
                    entityName: entityName,
                    entityID: entityID,
                    changeKind: .added,
                    title: title(incomingValue),
                    beforeSummary: nil,
                    afterSummary: summary(incomingValue)
                )
            case let (nil, existingValue?):
                return BridgeImportConcreteDiffDTO(
                    entityName: entityName,
                    entityID: entityID,
                    changeKind: .deleted,
                    title: title(existingValue),
                    beforeSummary: summary(existingValue),
                    afterSummary: nil
                )
            case (nil, nil):
                return nil
            }
        }
    }
}
