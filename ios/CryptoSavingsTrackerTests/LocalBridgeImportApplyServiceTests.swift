import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct LocalBridgeImportApplyServiceTests {
    @Test("Controller can load a signed package, surface review, and record approval")
    func controllerLoadsPackageAndApprovesReview() throws {
        let runtimeController = try makePhase2BridgeRuntimeController()
        let context = runtimeController.activeMainContext
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = Phase2BridgeSigningService()
        let trustedDevice = signingService.makeTrustedDevice(displayName: "Bridge Mac")
        let exportService = LocalBridgeSnapshotExportService(
            persistenceController: runtimeController,
            capabilityManifest: .current()
        )
        let validationService = LocalBridgeImportValidationService(
            snapshotExportService: exportService,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let trustStore = Phase2BridgeTrustStore(devices: [trustedDevice])
        let identityStore = LocalBridgeIdentityStore()
        let importApplyService = LocalBridgeImportApplyService(
            persistenceController: runtimeController,
            snapshotExportService: exportService,
            validationService: validationService,
            receiptStore: InMemoryBridgeImportReceiptStore()
        )
        let artifactRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let artifactStore = LocalBridgeArtifactStore(appSupportURL: artifactRoot)
        let controller = LocalBridgeSyncController(
            trustStore: trustStore,
            identityStore: identityStore,
            snapshotExportService: exportService,
            importValidationService: validationService,
            importApplyService: importApplyService,
            artifactStore: artifactStore
        )

        let baseSnapshot = try exportService.exportAuthoritativeSnapshot()
        let editedSnapshot = try makePhase2BridgeEditedSnapshot(from: baseSnapshot)
        let package = try makePhase2BridgeSignedPackage(
            from: editedSnapshot,
            baseDatasetFingerprint: baseSnapshot.manifest.baseDatasetFingerprint,
            trustedDevice: trustedDevice,
            signingService: signingService
        )
        let packageURL = artifactRoot.appendingPathComponent("bridge-import.json")
        try package.canonicalEncodingData().write(to: packageURL, options: .atomic)

        controller.loadImportPackage(from: packageURL)

        #expect(controller.latestImportArtifact != nil)
        #expect(controller.importReviewStatus.reviewSummaryDTO?.package.signatureStatus == .valid)
        #expect(controller.importReviewStatus.requiresOperatorReview)
        #expect(controller.pendingAction == LocalBridgePendingAction.reviewImport)

        controller.markImportDecision(BridgeImportOperatorDecisionState.approved)

        #expect(controller.importReviewStatus.operatorDecision == BridgeImportOperatorDecisionState.approved)
        #expect(controller.operatorMessage?.contains("approved") == true)
    }

    @Test("Apply through the authoritative runtime API mutates the CloudKit-backed dataset")
    func applyReviewedPackageToAuthoritativeDatasetWritesSnapshot() throws {
        let runtimeController = try makePhase2BridgeRuntimeController()
        let context = runtimeController.activeMainContext
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = Phase2BridgeSigningService()
        let trustedDevice = signingService.makeTrustedDevice(displayName: "Bridge Mac")
        let exportService = LocalBridgeSnapshotExportService(
            persistenceController: runtimeController,
            capabilityManifest: .current()
        )
        let validationService = LocalBridgeImportValidationService(
            snapshotExportService: exportService,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let receiptStore = InMemoryBridgeImportReceiptStore()
        let applyService = LocalBridgeImportApplyService(
            persistenceController: runtimeController,
            snapshotExportService: exportService,
            validationService: validationService,
            receiptStore: receiptStore
        )

        let baseSnapshot = try exportService.exportAuthoritativeSnapshot()
        let editedSnapshot = try makePhase2BridgeEditedSnapshot(from: baseSnapshot)
        let package = try makePhase2BridgeSignedPackage(
            from: editedSnapshot,
            baseDatasetFingerprint: baseSnapshot.manifest.baseDatasetFingerprint,
            trustedDevice: trustedDevice,
            signingService: signingService
        )
        let review = try validationService.review(
            package: package,
            trustedDevice: trustedDevice,
            currentSnapshot: baseSnapshot
        )

        let result = try applyService.applyReviewedPackageToAuthoritativeDataset(
            package,
            trustedDevice: trustedDevice,
            reviewStatus: approved(review)
        )
        let finalSnapshot = try exportService.exportAuthoritativeSnapshot()

        #expect(result.disposition == .applied)
        #expect(finalSnapshot.manifest.baseDatasetFingerprint == package.editedDatasetFingerprint)
        #expect(finalSnapshot.assets.count == baseSnapshot.assets.count + 1)
        #expect(finalSnapshot.transactions.count == baseSnapshot.transactions.count + 1)
        #expect(try receiptStore.receipt(for: package.packageID) != nil)
    }

    @Test("Apply writes an approved signed package into the authoritative dataset")
    func applyReviewedPackageWritesSnapshot() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgeSigningService()
        let trustedDevice = signingService.makeTrustedDevice(displayName: "Bridge Mac")
        let exportService = LocalBridgeSnapshotExportService()
        let validationService = LocalBridgeImportValidationService(
            snapshotExportService: exportService,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let receiptStore = InMemoryBridgeImportReceiptStore()
        let applyService = LocalBridgeImportApplyService(
            snapshotExportService: exportService,
            validationService: validationService,
            receiptStore: receiptStore
        )

        let baseSnapshot = try exportService.exportSnapshot(from: ModelContext(container))
        let editedSnapshot = try makeEditedSnapshot(from: baseSnapshot)
        let package = try makeSignedPackage(
            from: editedSnapshot,
            baseDatasetFingerprint: baseSnapshot.manifest.baseDatasetFingerprint,
            trustedDevice: trustedDevice,
            signingService: signingService
        )
        let review = try validationService.review(
            package: package,
            trustedDevice: trustedDevice,
            currentSnapshot: baseSnapshot
        )

        let result = try applyService.applyReviewedPackage(
            package,
            trustedDevice: trustedDevice,
            reviewStatus: approved(review),
            in: container
        )

        let finalSnapshot = try exportService.exportSnapshot(from: ModelContext(container))

        #expect(result.disposition == .applied)
        #expect(finalSnapshot.manifest.baseDatasetFingerprint == package.editedDatasetFingerprint)
        #expect(finalSnapshot.assets.count == baseSnapshot.assets.count + 1)
        #expect(finalSnapshot.transactions.count == baseSnapshot.transactions.count + 1)
        #expect(try receiptStore.receipt(for: package.packageID) != nil)
    }

    @Test("Replaying an already applied package is a no-op")
    func replayedPackageReturnsAlreadyApplied() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgeSigningService()
        let trustedDevice = signingService.makeTrustedDevice(displayName: "Bridge Mac")
        let exportService = LocalBridgeSnapshotExportService()
        let validationService = LocalBridgeImportValidationService(
            snapshotExportService: exportService,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let receiptStore = InMemoryBridgeImportReceiptStore()
        let applyService = LocalBridgeImportApplyService(
            snapshotExportService: exportService,
            validationService: validationService,
            receiptStore: receiptStore
        )

        let baseSnapshot = try exportService.exportSnapshot(from: ModelContext(container))
        let editedSnapshot = try makeEditedSnapshot(from: baseSnapshot)
        let package = try makeSignedPackage(
            from: editedSnapshot,
            baseDatasetFingerprint: baseSnapshot.manifest.baseDatasetFingerprint,
            trustedDevice: trustedDevice,
            signingService: signingService
        )
        let review = try validationService.review(
            package: package,
            trustedDevice: trustedDevice,
            currentSnapshot: baseSnapshot
        )
        let approvedReview = approved(review)

        _ = try applyService.applyReviewedPackage(
            package,
            trustedDevice: trustedDevice,
            reviewStatus: approvedReview,
            in: container
        )
        let replay = try applyService.applyReviewedPackage(
            package,
            trustedDevice: trustedDevice,
            reviewStatus: approvedReview,
            in: container
        )

        #expect(replay.disposition == .acceptedAlreadyApplied)
    }

    @Test("Apply is blocked until operator review is approved")
    func applyRequiresApproval() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgeSigningService()
        let trustedDevice = signingService.makeTrustedDevice(displayName: "Bridge Mac")
        let exportService = LocalBridgeSnapshotExportService()
        let validationService = LocalBridgeImportValidationService(
            snapshotExportService: exportService,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let applyService = LocalBridgeImportApplyService(
            snapshotExportService: exportService,
            validationService: validationService,
            receiptStore: InMemoryBridgeImportReceiptStore()
        )

        let baseSnapshot = try exportService.exportSnapshot(from: ModelContext(container))
        let package = try makeSignedPackage(
            from: baseSnapshot,
            baseDatasetFingerprint: baseSnapshot.manifest.baseDatasetFingerprint,
            trustedDevice: trustedDevice,
            signingService: signingService
        )
        let review = try validationService.review(
            package: package,
            trustedDevice: trustedDevice,
            currentSnapshot: baseSnapshot
        )

        #expect(throws: LocalBridgeImportApplyError.self) {
            try applyService.applyReviewedPackage(
                package,
                trustedDevice: trustedDevice,
                reviewStatus: review,
                in: container
            )
        }
    }

    @Test("Apply rejects packages that try to re-key an existing logical entity")
    func applyRejectsLogicalKeyRekey() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgeSigningService()
        let trustedDevice = signingService.makeTrustedDevice(displayName: "Bridge Mac")
        let exportService = LocalBridgeSnapshotExportService()
        let validationService = LocalBridgeImportValidationService(
            snapshotExportService: exportService,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let applyService = LocalBridgeImportApplyService(
            snapshotExportService: exportService,
            validationService: validationService,
            receiptStore: InMemoryBridgeImportReceiptStore()
        )

        let baseSnapshot = try exportService.exportSnapshot(from: ModelContext(container))
        let editedSnapshot = try makeRekeyedAssetSnapshot(from: baseSnapshot)
        let package = try makeSignedPackage(
            from: editedSnapshot,
            baseDatasetFingerprint: baseSnapshot.manifest.baseDatasetFingerprint,
            trustedDevice: trustedDevice,
            signingService: signingService
        )
        let review = try validationService.review(
            package: package,
            trustedDevice: trustedDevice,
            currentSnapshot: baseSnapshot
        )

        #expect(throws: LocalBridgeImportApplyError.self) {
            try applyService.applyReviewedPackage(
                package,
                trustedDevice: trustedDevice,
                reviewStatus: approved(review),
                in: container
            )
        }

        let finalSnapshot = try exportService.exportSnapshot(from: ModelContext(container))
        #expect(finalSnapshot.manifest.baseDatasetFingerprint == baseSnapshot.manifest.baseDatasetFingerprint)
        #expect(finalSnapshot.assets.count == baseSnapshot.assets.count)
    }

    private func approved(_ review: BridgeImportReviewStatus) -> BridgeImportReviewStatus {
        var approvedReview = review
        approvedReview.operatorDecision = .approved
        approvedReview.requiresOperatorReview = false
        return approvedReview
    }

    private func makeEditedSnapshot(from baseSnapshot: SnapshotEnvelope) throws -> SnapshotEnvelope {
        let newAssetID = UUID()
        let newAsset = BridgeAssetSnapshot(
            id: newAssetID,
            currency: "ETH",
            address: "0xbridge000000000000000000000000000000000001",
            chainId: "eth"
        )
        let newTransaction = BridgeTransactionSnapshot(
            id: UUID(),
            assetId: newAssetID,
            amount: 1.25,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sourceRawValue: TransactionSource.manual.rawValue,
            externalId: "bridge-import-transaction",
            counterparty: "Bridge Import",
            comment: "Applied from signed bridge package"
        )

        let assets = (baseSnapshot.assets + [newAsset]).sorted { $0.id.uuidString < $1.id.uuidString }
        let transactions = (baseSnapshot.transactions + [newTransaction]).sorted { $0.id.uuidString < $1.id.uuidString }
        let manifest = SnapshotManifest(
            snapshotID: baseSnapshot.manifest.snapshotID,
            canonicalEncodingVersion: baseSnapshot.manifest.canonicalEncodingVersion,
            snapshotSchemaVersion: baseSnapshot.manifest.snapshotSchemaVersion,
            exportedAt: baseSnapshot.manifest.exportedAt,
            appModelSchemaVersion: baseSnapshot.manifest.appModelSchemaVersion,
            entityCounts: [
                BridgeEntityCount(name: "Goal", count: baseSnapshot.goals.count),
                BridgeEntityCount(name: "Asset", count: assets.count),
                BridgeEntityCount(name: "Transaction", count: transactions.count),
                BridgeEntityCount(name: "AssetAllocation", count: baseSnapshot.assetAllocations.count),
                BridgeEntityCount(name: "AllocationHistory", count: baseSnapshot.allocationHistories.count),
                BridgeEntityCount(name: "MonthlyPlan", count: baseSnapshot.monthlyPlans.count),
                BridgeEntityCount(name: "MonthlyExecutionRecord", count: baseSnapshot.monthlyExecutionRecords.count)
            ],
            baseDatasetFingerprint: ""
        )

        return try SnapshotEnvelope(
            manifest: manifest,
            goals: baseSnapshot.goals,
            assets: assets,
            transactions: transactions,
            assetAllocations: baseSnapshot.assetAllocations,
            allocationHistories: baseSnapshot.allocationHistories,
            monthlyPlans: baseSnapshot.monthlyPlans,
            monthlyExecutionRecords: baseSnapshot.monthlyExecutionRecords
        ).withComputedFingerprint()
    }

    private func makeRekeyedAssetSnapshot(from baseSnapshot: SnapshotEnvelope) throws -> SnapshotEnvelope {
        guard let originalAsset = baseSnapshot.assets.first else {
            throw NSError(domain: "LocalBridgeImportApplyServiceTests", code: 2)
        }

        let rekeyedAssetID = UUID()
        let assets = baseSnapshot.assets.map { asset in
            if asset.id == originalAsset.id {
                return BridgeAssetSnapshot(
                    id: rekeyedAssetID,
                    currency: asset.currency,
                    address: asset.address,
                    chainId: asset.chainId
                )
            }
            return asset
        }
        let transactions = baseSnapshot.transactions.map { transaction in
            BridgeTransactionSnapshot(
                id: transaction.id,
                assetId: transaction.assetId == originalAsset.id ? rekeyedAssetID : transaction.assetId,
                amount: transaction.amount,
                date: transaction.date,
                sourceRawValue: transaction.sourceRawValue,
                externalId: transaction.externalId,
                counterparty: transaction.counterparty,
                comment: transaction.comment
            )
        }
        let assetAllocations = baseSnapshot.assetAllocations.map { allocation in
            BridgeAssetAllocationSnapshot(
                id: allocation.id,
                assetId: allocation.assetId == originalAsset.id ? rekeyedAssetID : allocation.assetId,
                goalId: allocation.goalId,
                amount: allocation.amount,
                createdDate: allocation.createdDate,
                lastModifiedDate: allocation.lastModifiedDate
            )
        }
        let allocationHistories = baseSnapshot.allocationHistories.map { history in
            BridgeAllocationHistorySnapshot(
                id: history.id,
                assetId: history.assetId == originalAsset.id ? rekeyedAssetID : history.assetId,
                goalId: history.goalId,
                amount: history.amount,
                timestamp: history.timestamp,
                createdAt: history.createdAt,
                monthLabel: history.monthLabel
            )
        }

        return try SnapshotEnvelope(
            manifest: baseSnapshot.manifest,
            goals: baseSnapshot.goals,
            assets: assets,
            transactions: transactions,
            assetAllocations: assetAllocations,
            allocationHistories: allocationHistories,
            monthlyPlans: baseSnapshot.monthlyPlans,
            monthlyExecutionRecords: baseSnapshot.monthlyExecutionRecords
        ).withComputedFingerprint()
    }

    private func makeSignedPackage(
        from snapshot: SnapshotEnvelope,
        baseDatasetFingerprint: String,
        trustedDevice: TrustedBridgeDevice,
        signingService: TestBridgeSigningService
    ) throws -> SignedImportPackage {
        guard
            let signingKeyID = trustedDevice.signingKeyID,
            let publicKeyRepresentation = trustedDevice.publicKeyRepresentation,
            let signingAlgorithm = trustedDevice.signingAlgorithm
        else {
            throw NSError(domain: "LocalBridgeImportApplyServiceTests", code: 1)
        }

        let unsignedPackage = SignedImportPackage(
            packageID: BudgetSnapshotIdentity.sha256([
                snapshot.manifest.snapshotID.uuidString,
                baseDatasetFingerprint,
                snapshot.manifest.baseDatasetFingerprint,
                signingKeyID,
                trustedDevice.fingerprint
            ].joined(separator: "|")),
            snapshotID: snapshot.manifest.snapshotID,
            canonicalEncodingVersion: snapshot.manifest.canonicalEncodingVersion,
            baseDatasetFingerprint: baseDatasetFingerprint,
            editedDatasetFingerprint: snapshot.manifest.baseDatasetFingerprint,
            snapshotEnvelope: snapshot,
            signingKeyID: signingKeyID,
            signingAlgorithm: signingAlgorithm,
            signerPublicKeyRepresentation: publicKeyRepresentation,
            signedAt: Date(timeIntervalSince1970: 1_700_000_500),
            signature: ""
        )
        let signature = try signingService.sign(unsignedPackage.signingPayloadData(), keyID: signingKeyID)

        return SignedImportPackage(
            packageID: unsignedPackage.packageID,
            snapshotID: unsignedPackage.snapshotID,
            canonicalEncodingVersion: unsignedPackage.canonicalEncodingVersion,
            baseDatasetFingerprint: unsignedPackage.baseDatasetFingerprint,
            editedDatasetFingerprint: unsignedPackage.editedDatasetFingerprint,
            snapshotEnvelope: unsignedPackage.snapshotEnvelope,
            signingKeyID: unsignedPackage.signingKeyID,
            signingAlgorithm: unsignedPackage.signingAlgorithm,
            signerPublicKeyRepresentation: unsignedPackage.signerPublicKeyRepresentation,
            signedAt: unsignedPackage.signedAt,
            signature: signature
        )
    }
}

private final class InMemoryBridgeImportReceiptStore: BridgeImportReceiptStoring {
    private var receipts: [String: BridgeImportReceipt] = [:]

    func receipt(for packageID: String) throws -> BridgeImportReceipt? {
        receipts[packageID]
    }

    func save(_ receipt: BridgeImportReceipt) throws {
        receipts[receipt.packageID] = receipt
    }
}

private final class TestBridgeSigningService: BridgePackageSigning {
    private var privateKeys: [String: P256.Signing.PrivateKey] = [:]

    func makeTrustedDevice(displayName: String) -> TrustedBridgeDevice {
        let keyID = UUID().uuidString
        let privateKey = P256.Signing.PrivateKey()
        privateKeys[keyID] = privateKey
        let publicKeyData = privateKey.publicKey.x963Representation
        let fingerprint = SHA256.hash(data: publicKeyData).map { String(format: "%02X", $0) }.joined()

        return TrustedBridgeDevice(
            id: UUID(),
            displayName: displayName,
            fingerprint: fingerprint,
            signingKeyID: keyID,
            publicKeyRepresentation: publicKeyData.base64EncodedString(),
            signingAlgorithm: "P256.Signing.ECDSA.SHA256",
            addedAt: .now,
            lastSuccessfulSyncAt: nil,
            trustState: .active
        )
    }

    func identity(for signingKeyID: String) throws -> BridgeSigningIdentitySnapshot {
        let privateKey = privateKeys[signingKeyID] ?? {
            let privateKey = P256.Signing.PrivateKey()
            privateKeys[signingKeyID] = privateKey
            return privateKey
        }()
        let publicKeyData = privateKey.publicKey.x963Representation
        let fingerprint = SHA256.hash(data: publicKeyData).map { String(format: "%02X", $0) }.joined()

        return BridgeSigningIdentitySnapshot(
            signingKeyID: signingKeyID,
            algorithm: "P256.Signing.ECDSA.SHA256",
            publicKeyRepresentation: publicKeyData.base64EncodedString(),
            fingerprint: fingerprint
        )
    }

    func sign(_ data: Data, keyID: String) throws -> String {
        let privateKey = privateKeys[keyID] ?? {
            let privateKey = P256.Signing.PrivateKey()
            privateKeys[keyID] = privateKey
            return privateKey
        }()
        return try privateKey.signature(for: data).derRepresentation.base64EncodedString()
    }

    func verify(signature: String, payload: Data, publicKeyRepresentation: String) throws {
        guard
            let publicKeyData = Data(base64Encoded: publicKeyRepresentation),
            let signatureData = Data(base64Encoded: signature)
        else {
            throw LocalBridgeIdentityStoreError.invalidSignatureEncoding
        }

        let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
        let signatureValue = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        guard publicKey.isValidSignature(signatureValue, for: payload) else {
            throw LocalBridgeIdentityStoreError.invalidSignature
        }
    }
}
