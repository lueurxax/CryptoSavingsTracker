import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct BridgeImportValidationServiceTests {
    @Test("Validation returns review-required status for package built from authoritative snapshot")
    func trustedSignedPackageProducesReview() throws {
        let trusted = TrustedBridgeDevice(
            id: UUID(),
            displayName: "MacBook Pro",
            fingerprint: "ABCDEF1234567890",
            addedAt: .now,
            lastSuccessfulSyncAt: nil,
            trustState: .active
        )

        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let exporter = LocalBridgeSnapshotExportService()
        let snapshot = try exporter.exportSnapshot(from: context)
        let service = LocalBridgeImportValidationService(snapshotExportService: exporter)
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
    }

    @Test("Validation fails for canonical encoding mismatch")
    func canonicalEncodingMismatchFailsValidation() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let exporter = LocalBridgeSnapshotExportService()
        let snapshot = try exporter.exportSnapshot(from: context)
        let service = LocalBridgeImportValidationService(snapshotExportService: exporter)
        let package = SignedImportPackage(
            packageID: UUID().uuidString,
            snapshotID: snapshot.manifest.snapshotID,
            canonicalEncodingVersion: "bridge-snapshot-v999",
            baseDatasetFingerprint: snapshot.manifest.baseDatasetFingerprint,
            editedDatasetFingerprint: snapshot.manifest.baseDatasetFingerprint,
            snapshotEnvelope: snapshot,
            signingKeyID: "UNTRUSTED-KEY",
            signedAt: .now,
            signature: "deadbeefcafebabe1234"
        )

        let status = try service.review(
            package: package,
            trustedDevice: nil,
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

        let exporter = LocalBridgeSnapshotExportService()
        let snapshot = try exporter.exportSnapshot(from: context)
        let service = LocalBridgeImportValidationService(snapshotExportService: exporter)
        let package = SignedImportPackage(
            packageID: UUID().uuidString,
            snapshotID: snapshot.manifest.snapshotID,
            canonicalEncodingVersion: snapshot.manifest.canonicalEncodingVersion,
            baseDatasetFingerprint: "different-base-fingerprint",
            editedDatasetFingerprint: snapshot.manifest.baseDatasetFingerprint,
            snapshotEnvelope: snapshot,
            signingKeyID: "UNTRUSTED-KEY",
            signedAt: .now,
            signature: "deadbeefcafebabe1234"
        )

        let status = try service.review(
            package: package,
            trustedDevice: nil,
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

        let exporter = LocalBridgeSnapshotExportService()
        let snapshot = try exporter.exportSnapshot(from: context)
        let package = SignedImportPackage(
            packageID: UUID().uuidString,
            snapshotID: snapshot.manifest.snapshotID,
            canonicalEncodingVersion: snapshot.manifest.canonicalEncodingVersion,
            baseDatasetFingerprint: snapshot.manifest.baseDatasetFingerprint,
            editedDatasetFingerprint: snapshot.manifest.baseDatasetFingerprint,
            snapshotEnvelope: snapshot,
            signingKeyID: "ABCDEF1234567890",
            signedAt: .now,
            signature: "deadbeefcafebabe1234"
        )

        let counts = package.changedEntityCounts

        #expect(counts["Goal"] == snapshot.goals.count)
        #expect(counts["Transaction"] == snapshot.transactions.count)
        #expect(counts["Asset"] == snapshot.assets.count)
    }
}
