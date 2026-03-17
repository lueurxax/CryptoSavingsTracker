import Foundation
import Testing
import SwiftData
@testable import CryptoSavingsTracker

@MainActor
struct LocalBridgeFoundationTests {

    @Test("bridge snapshot requires pairing when CloudKit is active and no trusted devices exist")
    func pairingRequiredWithoutTrustedDevices() {
        let persistenceSnapshot = PersistenceController.shared.snapshot
        let snapshot = LocalBridgeSyncStatusSnapshot.make(
            persistenceSnapshot: persistenceSnapshot,
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
        let persistenceSnapshot = PersistenceController.shared.snapshot
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
            persistenceSnapshot: persistenceSnapshot,
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
        let persistenceSnapshot = PersistenceController.shared.snapshot
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
            persistenceSnapshot: persistenceSnapshot,
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

    @Test("capability manifest advertises canonical and snapshot schema versions")
    func capabilityManifestShape() {
        let manifest = BridgeCapabilityManifest.current(bundle: .main)

        #expect(manifest.bridgeProtocolVersion == 1)
        #expect(manifest.minimumSupportedCanonicalEncodingVersion == "bridge-snapshot-v1")
        #expect(manifest.maximumSupportedSnapshotSchemaVersion == 1)
        #expect(manifest.appModelSchemaVersion == "cloudkit-model-v1")
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
}
