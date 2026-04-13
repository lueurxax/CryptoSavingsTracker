import Foundation
import Testing
import SwiftData
@testable import CryptoSavingsTracker

@MainActor
struct LocalBridgeFoundationTests {
    private var cloudKitPrimarySnapshot: PersistenceRuntimeSnapshot {
        PersistenceRuntimeSnapshot(
            activeMode: .cloudKitPrimary,
            selectedMode: .cloudKitPrimary,
            activeStoreKind: .cloudPrimary,
            localStorePath: nil,
            cloudStorePath: "/dev/null",
            cloudKitEnabled: true,
            migrationBlockers: [],
            lastModeUpdatedAt: .now
        )
    }

    @Test("identifier presentation exposes the full package ID to accessibility")
    func identifierPresentationPreservesFullValue() {
        let presentation = LocalBridgeIdentifierPresentation.metadata(
            title: "Package ID",
            value: "ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890"
        )

        #expect(presentation.label == "Package ID")
        #expect(presentation.value == "ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890")
        #expect(presentation.hint == "Shows the full package ID across multiple lines.")
    }

    @Test("identifier presentation keeps field-specific copy for pairing IDs")
    func identifierPresentationUsesFieldSpecificHint() {
        let presentation = LocalBridgeIdentifierPresentation.metadata(
            title: "Pairing ID",
            value: "550E8400-E29B-41D4-A716-446655440000"
        )

        #expect(presentation.label == "Pairing ID")
        #expect(presentation.value == "550E8400-E29B-41D4-A716-446655440000")
        #expect(presentation.hint == "Shows the full pairing ID across multiple lines.")
    }

    @Test("bridge snapshot requires pairing when CloudKit is active and no trusted devices exist")
    func pairingRequiredWithoutTrustedDevices() {
        let snapshot = LocalBridgeSyncStatusSnapshot.make(
            persistenceSnapshot: cloudKitPrimarySnapshot,
            trustedDevices: [],
            lastSyncOutcome: .neverSynced,
            pendingAction: .pairMac,
            importReviewStatus: .none,
            sessionState: .idle,
            capabilityManifest: .current(bundle: .main)
        )

        #expect(snapshot.availabilityState == .pairingRequired)
        #expect(snapshot.pendingAction == .pairMac)
    }

    @Test("bridge snapshot becomes ready when CloudKit is active and trust exists")
    func readyWithTrustedDevice() {
        let device = TrustedBridgeDevice(
            id: UUID(),
            displayName: "MacBook Pro",
            fingerprint: "ABCDEF1234567890",
            addedAt: .now,
            lastSuccessfulSyncAt: nil,
            trustState: .active
        )
        let sessionState = BridgeSessionState(
            sessionID: UUID(),
            transportState: .idle,
            workspaceState: .empty,
            compatibilityState: .compatible,
            cloudKitReconciliationState: .reconciled,
            liveStoreMutationAllowed: false,
            activePairingMethod: nil,
            bootstrapToken: nil,
            lastImportedPackageID: nil
        )
        let snapshot = LocalBridgeSyncStatusSnapshot.make(
            persistenceSnapshot: cloudKitPrimarySnapshot,
            trustedDevices: [device],
            lastSyncOutcome: .neverSynced,
            pendingAction: .syncNow,
            importReviewStatus: .none,
            sessionState: sessionState,
            capabilityManifest: .current(bundle: .main)
        )

        #expect(snapshot.availabilityState == .ready)
        #expect(snapshot.trustedDevices.count == 1)
        #expect(snapshot.topLevelSummary.contains("Ready"))
    }

    @Test("bridge snapshot surfaces review-required state when import review is pending")
    func reviewRequiredState() {
        let device = TrustedBridgeDevice(
            id: UUID(),
            displayName: "Mac mini",
            fingerprint: "1234567890ABCDEF",
            addedAt: .now,
            lastSuccessfulSyncAt: nil,
            trustState: .active
        )
        let review = BridgeImportReviewStatus(
            summary: "Review pending",
            requiresOperatorReview: true,
            validationStatus: .warnings,
            driftStatus: .none,
            operatorDecision: .awaitingDecision,
            importReviewSummary: nil,
            reviewSummaryDTO: nil,
            validationWarnings: [],
            blockingIssues: []
        )
        let snapshot = LocalBridgeSyncStatusSnapshot.make(
            persistenceSnapshot: cloudKitPrimarySnapshot,
            trustedDevices: [device],
            lastSyncOutcome: .succeeded,
            pendingAction: .reviewImport,
            importReviewStatus: review,
            sessionState: .idle,
            capabilityManifest: .current(bundle: .main)
        )

        #expect(snapshot.availabilityState == .reviewRequired)
        #expect(snapshot.pendingAction == .reviewImport)
    }

    @Test("bridge snapshot prioritizes update-required over review-required when compatibility blocks apply")
    func updateRequiredOverridesReviewRequired() {
        let device = TrustedBridgeDevice(
            id: UUID(),
            displayName: "Mac mini",
            fingerprint: "1234567890ABCDEF",
            addedAt: .now,
            lastSuccessfulSyncAt: nil,
            trustState: .active
        )
        let review = BridgeImportReviewStatus(
            summary: "Review blocked until compatibility is updated.",
            requiresOperatorReview: true,
            validationStatus: .failed,
            driftStatus: .conflicting,
            operatorDecision: .awaitingDecision,
            importReviewSummary: nil,
            reviewSummaryDTO: nil,
            validationWarnings: [],
            blockingIssues: ["Package canonical encoding bridge-snapshot-v999 is incompatible with this build."]
        )
        let sessionState = BridgeSessionState(
            sessionID: UUID(),
            transportState: .awaitingImportReview,
            workspaceState: .loadedTransientWorkspace,
            compatibilityState: .updateRequired,
            cloudKitReconciliationState: .blockedPendingCloudSync,
            liveStoreMutationAllowed: false,
            activePairingMethod: nil,
            bootstrapToken: nil,
            lastImportedPackageID: nil
        )
        let snapshot = LocalBridgeSyncStatusSnapshot.make(
            persistenceSnapshot: cloudKitPrimarySnapshot,
            trustedDevices: [device],
            lastSyncOutcome: .failed,
            pendingAction: .updateRequired,
            importReviewStatus: review,
            sessionState: sessionState,
            capabilityManifest: .current(bundle: .main)
        )

        #expect(snapshot.availabilityState == .updateRequired)
        #expect(snapshot.pendingAction == .updateRequired)
    }

    @Test("bridge snapshot is unavailable before CloudKit runtime is complete")
    func unavailableBeforeCloudKitRuntime() {
        let persistence = PersistenceRuntimeSnapshot(
            activeMode: .localOnly,
            selectedMode: .localOnly,
            activeStoreKind: .localPrimary,
            localStorePath: nil,
            cloudStorePath: nil,
            cloudKitEnabled: false,
            migrationBlockers: [],
            lastModeUpdatedAt: nil
        )
        let snapshot = LocalBridgeSyncStatusSnapshot.make(
            persistenceSnapshot: persistence,
            trustedDevices: [],
            lastSyncOutcome: .neverSynced,
            pendingAction: .pairMac,
            importReviewStatus: .none,
            sessionState: .idle,
            capabilityManifest: .current(bundle: .main)
        )

        #expect(snapshot.availabilityState == .unavailable)
    }

    @Test("bridge snapshot preserves trust-revoked pending action in the top-level row")
    func trustRevokedStatePreserved() {
        let snapshot = LocalBridgeSyncStatusSnapshot.make(
            persistenceSnapshot: cloudKitPrimarySnapshot,
            trustedDevices: [],
            lastSyncOutcome: .failed,
            pendingAction: .trustRevoked,
            importReviewStatus: .none,
            sessionState: BridgeSessionState(
                sessionID: UUID(),
                transportState: .trustRevoked,
                workspaceState: .discarded,
                compatibilityState: .unknown,
                cloudKitReconciliationState: .unknown,
                liveStoreMutationAllowed: false,
                activePairingMethod: .enterCodeManually,
                bootstrapToken: nil,
                lastImportedPackageID: nil
            ),
            capabilityManifest: .current(bundle: .main)
        )

        #expect(snapshot.availabilityState == .pairingRequired)
        #expect(snapshot.pendingAction == .trustRevoked)
        #expect(snapshot.topLevelSummary.contains("Trust Revoked"))
    }

    @Test("capability manifest advertises canonical and snapshot schema versions")
    func capabilityManifestShape() {
        let manifest = BridgeCapabilityManifest.current(bundle: .main)

        #expect(manifest.bridgeProtocolVersion == 1)
        #expect(manifest.minimumSupportedCanonicalEncodingVersion == "bridge-snapshot-v1")
        #expect(manifest.maximumSupportedSnapshotSchemaVersion == 1)
        #expect(manifest.appModelSchemaVersion == "cloudkit-model-v1")
    }

    @Test("manual bootstrap token roundtrip restores trusted device identity")
    func manualBootstrapTokenRoundtrip() throws {
        let identityStore = LocalBridgeIdentityStore(userDefaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        let token = try identityStore.makeBootstrapToken(displayName: "Bridge Mac")
        let encoded = try token.encodedManualEntryToken()
        let decoded = try BridgeBootstrapToken.decodeManualEntryToken(encoded)
        let trustedDevice = try identityStore.trustedDevice(from: decoded)

        #expect(decoded.deviceName == "Bridge Mac")
        #expect(trustedDevice.displayName == "Bridge Mac")
        #expect(trustedDevice.signingKeyID == token.signingKeyID)
        #expect(trustedDevice.publicKeyRepresentation == token.publicKeyRepresentation)
        #expect(trustedDevice.fingerprint == token.fingerprint)
    }

    @Test("manual pairing code roundtrip decodes to the original bootstrap token")
    func manualPairingCodeRoundtrip() throws {
        let identityStore = LocalBridgeIdentityStore(userDefaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        let token = try identityStore.makeBootstrapToken(displayName: "Bridge Mac")
        let pairingCode = try token.encodedPairingCode()
        let decoded = try BridgeBootstrapToken.decodePairingCode(pairingCode)

        #expect(decoded == token)
        #expect(pairingCode.contains("."))
    }

    @Test("bootstrap token redaction hides full secret by default")
    func bootstrapTokenRedaction() throws {
        let identityStore = LocalBridgeIdentityStore(userDefaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        let token = try identityStore.makeBootstrapToken(displayName: "Bridge Mac")
        let encoded = try token.encodedManualEntryToken()
        let redacted = BridgeObservabilityRedactor.redactedBootstrapToken(encoded)

        #expect(redacted != encoded)
        #expect(redacted.contains("…"))
        #expect(redacted.hasPrefix(String(encoded.prefix(8))))
        #expect(redacted.hasSuffix(String(encoded.suffix(8))))
    }

    @Test("snapshot export builds deterministic entity counts from in-memory authoritative dataset")
    func snapshotExportShape() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let expectedCounts = try TestDataFactory.createFullCutoverTestData(in: context)
        let exporter = LocalBridgeSnapshotExportService()

        let snapshot = try exporter.exportSnapshot(from: context)

        #expect(snapshot.goals.count == expectedCounts["Goal"])
        #expect(snapshot.assets.count == expectedCounts["Asset"])
        #expect(snapshot.transactions.count == expectedCounts["Transaction"])
        #expect(snapshot.assetAllocations.count == expectedCounts["AssetAllocation"])
        #expect(snapshot.allocationHistories.count == expectedCounts["AllocationHistory"])
        #expect(snapshot.monthlyPlans.count == expectedCounts["MonthlyPlan"])
        #expect(snapshot.monthlyExecutionRecords.count == expectedCounts["MonthlyExecutionRecord"])
        #expect(snapshot.manifest.baseDatasetFingerprint.isEmpty == false)
    }

    @Test("snapshot export keeps dataset fingerprint stable across repeated exports of unchanged data")
    func snapshotExportFingerprintIsStableForUnchangedDataset() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)
        let exporter = LocalBridgeSnapshotExportService()

        let first = try exporter.exportSnapshot(from: ModelContext(container))
        let second = try exporter.exportSnapshot(from: ModelContext(container))

        #expect(first.manifest.baseDatasetFingerprint == second.manifest.baseDatasetFingerprint)
    }
}
