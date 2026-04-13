import Foundation
import CryptoKit
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct BridgeImportValidationServiceTests {
    @Test("Validation returns review-required status for package built from authoritative snapshot")
    func trustedSignedPackageProducesReview() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgePackageSigningService()
        let exporter = LocalBridgeSnapshotExportService()
        let snapshot = try exporter.exportSnapshot(from: context)
        let trusted = try makeTrustedDevice(displayName: "MacBook Pro", signingService: signingService)
        let service = LocalBridgeImportValidationService(
            snapshotExportService: exporter,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let package = try service.makePlaceholderPackage(from: snapshot, trustedDevice: trusted)

        let status = try service.review(
            package: package,
            trustedDevice: trusted,
            currentSnapshot: snapshot
        )

        #expect(status.requiresOperatorReview)
        #expect(status.validationStatus == .warnings || status.validationStatus == .passed)
        #expect(status.reviewSummaryDTO != nil)
        #expect(status.importReviewSummary != nil)
        #expect(status.driftStatus == .none)
        #expect(status.reviewSummaryDTO?.package.signatureStatus == .valid)
        #expect(status.validationWarnings.contains(where: { $0.contains("Cryptographic signature verification is not implemented") }) == false)
    }

    @Test("Validation marks packages as signer-untrusted when the trusted device does not match")
    func signerMismatchIsUntrusted() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgePackageSigningService()
        let exporter = LocalBridgeSnapshotExportService()
        let snapshot = try exporter.exportSnapshot(from: context)
        let signingTrustedDevice = try makeTrustedDevice(displayName: "Signing Mac", signingService: signingService)
        let reviewerTrustedDevice = try makeTrustedDevice(displayName: "Review Mac", signingService: signingService)
        let service = LocalBridgeImportValidationService(
            snapshotExportService: exporter,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let package = try service.makePlaceholderPackage(from: snapshot, trustedDevice: signingTrustedDevice)

        let status = try service.review(
            package: package,
            trustedDevice: reviewerTrustedDevice,
            currentSnapshot: snapshot
        )

        #expect(status.validationStatus == .failed)
        #expect(status.reviewSummaryDTO?.package.signatureStatus == .signerUntrusted)
        #expect(status.blockingIssues.contains(where: { $0.contains("signer is not an active trusted device") || $0.contains("signing key does not match") }))
    }

    @Test("Validation fails for canonical encoding mismatch")
    func canonicalEncodingMismatchFailsValidation() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgePackageSigningService()
        let exporter = LocalBridgeSnapshotExportService()
        let snapshot = try exporter.exportSnapshot(from: context)
        let trusted = try makeTrustedDevice(displayName: "MacBook Pro", signingService: signingService)
        let service = LocalBridgeImportValidationService(
            snapshotExportService: exporter,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let basePackage = try service.makePlaceholderPackage(from: snapshot, trustedDevice: trusted)
        let package = try reSign(
            SignedImportPackage(
                packageID: basePackage.packageID,
                snapshotID: basePackage.snapshotID,
                canonicalEncodingVersion: "bridge-snapshot-v999",
                baseDatasetFingerprint: basePackage.baseDatasetFingerprint,
                editedDatasetFingerprint: basePackage.editedDatasetFingerprint,
                snapshotEnvelope: basePackage.snapshotEnvelope,
                signingKeyID: basePackage.signingKeyID,
                signingAlgorithm: basePackage.signingAlgorithm,
                signerPublicKeyRepresentation: basePackage.signerPublicKeyRepresentation,
                signedAt: basePackage.signedAt,
                signature: ""
            ),
            signingService: signingService
        )

        let status = try service.review(
            package: package,
            trustedDevice: trusted,
            currentSnapshot: snapshot
        )

        #expect(status.validationStatus == .failed)
        #expect(status.blockingIssues.contains(where: { $0.contains("incompatible") || $0.contains("supported range") }))
    }

    @Test("Validation detects drift when base fingerprint differs from current authoritative snapshot")
    func driftConflictDetected() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgePackageSigningService()
        let exporter = LocalBridgeSnapshotExportService()
        let snapshot = try exporter.exportSnapshot(from: context)
        let trusted = try makeTrustedDevice(displayName: "MacBook Pro", signingService: signingService)
        let service = LocalBridgeImportValidationService(
            snapshotExportService: exporter,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let basePackage = try service.makePlaceholderPackage(from: snapshot, trustedDevice: trusted)
        let package = try reSign(
            SignedImportPackage(
                packageID: basePackage.packageID,
                snapshotID: basePackage.snapshotID,
                canonicalEncodingVersion: basePackage.canonicalEncodingVersion,
                baseDatasetFingerprint: "different-base-fingerprint",
                editedDatasetFingerprint: basePackage.editedDatasetFingerprint,
                snapshotEnvelope: basePackage.snapshotEnvelope,
                signingKeyID: basePackage.signingKeyID,
                signingAlgorithm: basePackage.signingAlgorithm,
                signerPublicKeyRepresentation: basePackage.signerPublicKeyRepresentation,
                signedAt: basePackage.signedAt,
                signature: ""
            ),
            signingService: signingService
        )

        let status = try service.review(
            package: package,
            trustedDevice: trusted,
            currentSnapshot: snapshot
        )

        #expect(status.driftStatus == .conflicting)
        #expect(status.blockingIssues.contains(where: { $0.contains("authoritative CloudKit dataset changed") }))
    }

    @Test("SignedImportPackage changedEntityCounts helper reflects expanded envelope payload")
    func changedEntityCountsFromEnvelope() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgePackageSigningService()
        let exporter = LocalBridgeSnapshotExportService()
        let snapshot = try exporter.exportSnapshot(from: context)
        let trusted = try makeTrustedDevice(displayName: "MacBook Pro", signingService: signingService)
        let service = LocalBridgeImportValidationService(
            snapshotExportService: exporter,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let package = try service.makePlaceholderPackage(from: snapshot, trustedDevice: trusted)

        let counts = package.changedEntityCounts

        #expect(counts["Goal"] == snapshot.goals.count)
        #expect(counts["Transaction"] == snapshot.transactions.count)
        #expect(counts["Asset"] == snapshot.assets.count)
    }

    @Test("Canonical package body omits package metadata keys")
    func canonicalPackageBodyOmitsPackageMetadata() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgePackageSigningService()
        let exporter = LocalBridgeSnapshotExportService()
        let snapshot = try exporter.exportSnapshot(from: context)
        let trusted = try makeTrustedDevice(displayName: "MacBook Pro", signingService: signingService)
        let service = LocalBridgeImportValidationService(
            snapshotExportService: exporter,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let package = try service.makePlaceholderPackage(from: snapshot, trustedDevice: trusted)

        let body = String(decoding: try package.canonicalPackageBodyData(), as: UTF8.self)
        #expect(body.contains("\"packageID\"") == false)
        #expect(body.contains("\"signature\"") == false)
        #expect(body.contains("\"signingAlgorithm\"") == false)
        #expect(body.contains("\"signerPublicKeyRepresentation\"") == false)
        let signingPayload = String(decoding: try package.signingPayloadData(), as: UTF8.self)
        #expect(signingPayload.contains("\"packageID\""))
        #expect(signingPayload.contains("\"signature\":null"))
        #expect(signingPayload.contains("\"signingAlgorithm\"") == false)
        #expect(signingPayload.contains("\"signerPublicKeyRepresentation\"") == false)
    }

    @Test("Canonical snapshot uses lexicographic nested key order and explicit null optionals")
    func canonicalSnapshotUsesLexicographicNestedKeysAndNullOptionals() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let exporter = LocalBridgeSnapshotExportService()
        let snapshot = try exporter.exportSnapshot(from: context)
        let canonical = String(
            decoding: try snapshot.canonicalEncodingData(forFingerprinting: false),
            as: UTF8.self
        )

        let goalStart = try (#require(canonical.range(of: "\"goals\":[{"))).upperBound
        let goalTail = String(canonical[goalStart...])
        let goalEndOffset = try (#require(goalTail.firstIndex(of: "}"))).utf16Offset(in: goalTail)
        let goalObject = String(goalTail.prefix(goalEndOffset))
        let goalNSString = goalObject as NSString

        let currencyRange = goalNSString.range(of: "\"currency\":")
        let deadlineRange = goalNSString.range(of: "\"deadline\":")
        let emojiRange = goalNSString.range(of: "\"emoji\":null")
        let descriptionRange = goalNSString.range(of: "\"goalDescription\":null")
        let idRange = goalNSString.range(of: "\"id\":")
        let recordStateRange = goalNSString.range(of: "\"recordState\":")
        let startDateRange = goalNSString.range(of: "\"startDate\":")

        #expect(currencyRange.location != NSNotFound)
        #expect(deadlineRange.location != NSNotFound)
        #expect(emojiRange.location != NSNotFound)
        #expect(descriptionRange.location != NSNotFound)
        #expect(idRange.location != NSNotFound)
        #expect(recordStateRange.location != NSNotFound)
        #expect(startDateRange.location != NSNotFound)
        #expect(currencyRange.location < deadlineRange.location)
        #expect(deadlineRange.location < emojiRange.location)
        #expect(emojiRange.location < descriptionRange.location)
        #expect(descriptionRange.location < idRange.location)
        #expect(recordStateRange.location < startDateRange.location)
    }

    @Test("Validation emits concrete entity delta counts for edited packages")
    func concreteEntityDeltasReflectChangedEntities() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgePackageSigningService()
        let exporter = LocalBridgeSnapshotExportService()
        let baseSnapshot = try exporter.exportSnapshot(from: context)
        let trusted = try makeTrustedDevice(displayName: "MacBook Pro", signingService: signingService)
        let service = LocalBridgeImportValidationService(
            snapshotExportService: exporter,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let editedSnapshot = try makeEditedSnapshot(from: baseSnapshot)
        let package = try reSign(
            SignedImportPackage(
                packageID: "",
                snapshotID: editedSnapshot.manifest.snapshotID,
                canonicalEncodingVersion: editedSnapshot.manifest.canonicalEncodingVersion,
                baseDatasetFingerprint: baseSnapshot.manifest.baseDatasetFingerprint,
                editedDatasetFingerprint: editedSnapshot.manifest.baseDatasetFingerprint,
                snapshotEnvelope: editedSnapshot,
                signingKeyID: trusted.signingKeyID ?? "",
                signingAlgorithm: trusted.signingAlgorithm ?? "P256.Signing.ECDSA.SHA256",
                signerPublicKeyRepresentation: trusted.publicKeyRepresentation ?? "",
                signedAt: .now,
                signature: ""
            ),
            signingService: signingService
        )

        let status = try service.review(
            package: package,
            trustedDevice: trusted,
            currentSnapshot: baseSnapshot
        )

        let deltasByName = Dictionary(uniqueKeysWithValues: status.reviewSummaryDTO?.entityDeltas.map { ($0.entityName, $0) } ?? [])
        #expect(deltasByName["Goal"]?.changedCount == 0)
        #expect(deltasByName["Asset"]?.changedCount == 1)
        #expect(deltasByName["Transaction"]?.changedCount == 1)
        #expect(deltasByName["MonthlyPlan"]?.changedCount == 0)
        #expect(status.reviewSummaryDTO?.package.signatureStatus == .valid)
    }

    @Test("Validation fails when signed import package signature is tampered")
    func tamperedSignatureFailsValidation() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgePackageSigningService()
        let exporter = LocalBridgeSnapshotExportService()
        let snapshot = try exporter.exportSnapshot(from: context)
        let trusted = try makeTrustedDevice(displayName: "MacBook Pro", signingService: signingService)
        let service = LocalBridgeImportValidationService(
            snapshotExportService: exporter,
            capabilityManifest: .current(),
            signingService: signingService
        )
        let basePackage = try service.makePlaceholderPackage(from: snapshot, trustedDevice: trusted)
        let tamperedPackage = SignedImportPackage(
            packageID: basePackage.packageID,
            snapshotID: basePackage.snapshotID,
            canonicalEncodingVersion: basePackage.canonicalEncodingVersion,
            baseDatasetFingerprint: basePackage.baseDatasetFingerprint,
            editedDatasetFingerprint: basePackage.editedDatasetFingerprint,
            snapshotEnvelope: basePackage.snapshotEnvelope,
            signingKeyID: basePackage.signingKeyID,
            signingAlgorithm: basePackage.signingAlgorithm,
            signerPublicKeyRepresentation: basePackage.signerPublicKeyRepresentation,
            signedAt: basePackage.signedAt,
            signature: Data("tampered-signature".utf8).base64EncodedString()
        )

        let status = try service.review(
            package: tamperedPackage,
            trustedDevice: trusted,
            currentSnapshot: snapshot
        )

        #expect(status.validationStatus == .failed)
        #expect(status.reviewSummaryDTO?.package.signatureStatus == .invalid)
        #expect(status.blockingIssues.contains(where: { $0.contains("signature verification failed") }))
    }
}

@MainActor
private func makeTrustedDevice(
    displayName: String,
    signingService: TestBridgePackageSigningService
) throws -> TrustedBridgeDevice {
    let deviceID = UUID()
    let identity = try signingService.identity(for: deviceID.uuidString)
    return TrustedBridgeDevice(
        id: deviceID,
        displayName: displayName,
        fingerprint: identity.fingerprint,
        signingKeyID: identity.signingKeyID,
        publicKeyRepresentation: identity.publicKeyRepresentation,
        signingAlgorithm: identity.algorithm,
        addedAt: .now,
        lastSuccessfulSyncAt: nil,
        trustState: .active
    )
}

private func reSign(
    _ package: SignedImportPackage,
    signingService: TestBridgePackageSigningService
) throws -> SignedImportPackage {
    let packageBody = try package.canonicalPackageBodyData()
    let packageID = BudgetSnapshotIdentity.sha256(String(decoding: packageBody, as: UTF8.self))
    let canonicalPackage = SignedImportPackage(
        packageID: packageID,
        snapshotID: package.snapshotID,
        canonicalEncodingVersion: package.canonicalEncodingVersion,
        baseDatasetFingerprint: package.baseDatasetFingerprint,
        editedDatasetFingerprint: package.editedDatasetFingerprint,
        snapshotEnvelope: package.snapshotEnvelope,
        signingKeyID: package.signingKeyID,
        signingAlgorithm: package.signingAlgorithm,
        signerPublicKeyRepresentation: package.signerPublicKeyRepresentation,
        signedAt: package.signedAt,
        signature: ""
    )
    let signature = try signingService.sign(try canonicalPackage.signingPayloadData(), keyID: package.signingKeyID)
    return SignedImportPackage(
        packageID: packageID,
        snapshotID: canonicalPackage.snapshotID,
        canonicalEncodingVersion: canonicalPackage.canonicalEncodingVersion,
        baseDatasetFingerprint: canonicalPackage.baseDatasetFingerprint,
        editedDatasetFingerprint: canonicalPackage.editedDatasetFingerprint,
        snapshotEnvelope: canonicalPackage.snapshotEnvelope,
        signingKeyID: canonicalPackage.signingKeyID,
        signingAlgorithm: canonicalPackage.signingAlgorithm,
        signerPublicKeyRepresentation: canonicalPackage.signerPublicKeyRepresentation,
        signedAt: canonicalPackage.signedAt,
        signature: signature
    )
}

@MainActor
private func makeEditedSnapshot(from baseSnapshot: SnapshotEnvelope) throws -> SnapshotEnvelope {
    let newAssetID = UUID()
    let newAsset = BridgeAssetSnapshot(
        id: newAssetID,
        recordState: .active,
        currency: "ETH",
        address: "0xbridge000000000000000000000000000000000001",
        chainId: "eth"
    )
    let newTransaction = BridgeTransactionSnapshot(
        id: UUID(),
        recordState: .active,
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

final class TestBridgePackageSigningService: BridgePackageSigning {
    private var privateKeys: [String: P256.Signing.PrivateKey] = [:]

    func identity(for signingKeyID: String) throws -> BridgeSigningIdentitySnapshot {
        let privateKey = privateKeys[signingKeyID] ?? {
            let newKey = P256.Signing.PrivateKey()
            privateKeys[signingKeyID] = newKey
            return newKey
        }()
        let publicKeyData = privateKey.publicKey.x963Representation
        return BridgeSigningIdentitySnapshot(
            signingKeyID: signingKeyID,
            algorithm: "P256.Signing.ECDSA.SHA256",
            publicKeyRepresentation: publicKeyData.base64EncodedString(),
            fingerprint: LocalBridgeIdentityStore.fingerprint(publicKeyData: publicKeyData)
        )
    }

    func sign(_ data: Data, keyID: String) throws -> String {
        let privateKey = privateKeys[keyID] ?? {
            let newKey = P256.Signing.PrivateKey()
            privateKeys[keyID] = newKey
            return newKey
        }()
        return try privateKey.signature(for: data).derRepresentation.base64EncodedString()
    }

    func verify(signature: String, payload: Data, publicKeyRepresentation: String) throws {
        guard let publicKeyData = Data(base64Encoded: publicKeyRepresentation) else {
            throw LocalBridgeIdentityStoreError.invalidPublicKey
        }
        guard let signatureData = Data(base64Encoded: signature) else {
            throw LocalBridgeIdentityStoreError.invalidSignatureEncoding
        }
        let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
        let signatureValue = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        guard publicKey.isValidSignature(signatureValue, for: payload) else {
            throw LocalBridgeIdentityStoreError.invalidSignature
        }
    }
}
