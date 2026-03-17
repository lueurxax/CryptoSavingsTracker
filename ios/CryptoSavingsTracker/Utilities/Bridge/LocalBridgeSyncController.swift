import Foundation
import Combine

@MainActor
final class LocalBridgeSyncController: ObservableObject {
    static let shared = LocalBridgeSyncController()

    @Published private(set) var trustedDevices: [TrustedBridgeDevice]
    @Published private(set) var lastSyncOutcome: LocalBridgeLastSyncOutcome
    @Published private(set) var pendingAction: LocalBridgePendingAction
    @Published private(set) var importReviewStatus: BridgeImportReviewStatus
    @Published private(set) var operatorMessage: String?
    @Published private(set) var sessionState: BridgeSessionState

    private let trustStore: BridgeTrustStoring
    private let snapshotExportService: LocalBridgeSnapshotExportService
    private let importValidationService: LocalBridgeImportValidationService

    private var latestExportedSnapshot: SnapshotEnvelope?
    private var latestPreparedImportPackage: SignedImportPackage?

    convenience init() {
        let exportService = LocalBridgeSnapshotExportService()
        self.init(
            trustStore: BridgeTrustStore(),
            snapshotExportService: exportService,
            importValidationService: LocalBridgeImportValidationService(
                snapshotExportService: exportService
            )
        )
    }

    init(
        trustStore: BridgeTrustStoring,
        snapshotExportService: LocalBridgeSnapshotExportService,
        importValidationService: LocalBridgeImportValidationService
    ) {
        let initialTrustedDevices = trustStore.loadTrustedDevices()
        self.trustStore = trustStore
        self.snapshotExportService = snapshotExportService
        self.importValidationService = importValidationService
        self.trustedDevices = initialTrustedDevices
        self.lastSyncOutcome = .neverSynced
        self.pendingAction = initialTrustedDevices.isEmpty ? .pairMac : .syncNow
        self.importReviewStatus = .none
        self.sessionState = initialTrustedDevices.isEmpty
            ? BridgeSessionState(
                sessionID: UUID(),
                transportState: .pairingRequired,
                workspaceState: .empty,
                compatibilityState: .unknown,
                cloudKitReconciliationState: .unknown,
                liveStoreMutationAllowed: false,
                activePairingMethod: nil,
                bootstrapToken: nil,
                lastImportedPackageID: nil
            )
            : BridgeSessionState(
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
    }

    var capabilityManifest: BridgeCapabilityManifest {
        .current()
    }

    func statusSnapshot(persistenceSnapshot: PersistenceRuntimeSnapshot) -> LocalBridgeSyncStatusSnapshot {
        LocalBridgeSyncStatusSnapshot.make(
            persistenceSnapshot: persistenceSnapshot,
            trustedDevices: trustedDevices.filter { $0.trustState == .active },
            lastSyncOutcome: lastSyncOutcome,
            pendingAction: pendingAction,
            importReviewStatus: importReviewStatus,
            sessionState: sessionState,
            capabilityManifest: capabilityManifest
        )
    }

    func refresh() {
        trustedDevices = trustStore.loadTrustedDevices()
        if trustedDevices.filter({ $0.trustState == .active }).isEmpty {
            pendingAction = .pairMac
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .pairingRequired,
                workspaceState: .empty,
                compatibilityState: .unknown,
                cloudKitReconciliationState: .unknown,
                liveStoreMutationAllowed: false,
                activePairingMethod: nil,
                bootstrapToken: nil,
                lastImportedPackageID: nil
            )
            latestExportedSnapshot = nil
            latestPreparedImportPackage = nil
            importReviewStatus = .none
        }
    }

    func pairMac(using method: BridgePairingMethod = .scanQR) {
        let token = BridgeBootstrapToken(
            pairingID: UUID(),
            deviceName: "CryptoSavingsTracker Mac",
            expiresAt: Date().addingTimeInterval(10 * 60),
            oneTimeSecretReference: UUID().uuidString,
            ephemeralPublicKey: UUID().uuidString.replacingOccurrences(of: "-", with: "")
        )
        sessionState = BridgeSessionState(
            sessionID: UUID(),
            transportState: .pairingTokenReady,
            workspaceState: .empty,
            compatibilityState: .unknown,
            cloudKitReconciliationState: .reconciled,
            liveStoreMutationAllowed: false,
            activePairingMethod: method,
            bootstrapToken: token,
            lastImportedPackageID: sessionState.lastImportedPackageID
        )
        operatorMessage = "Bootstrap token prepared for \(method.displayTitle). QR scanning and Multipeer handshake are not implemented in this build yet."
        pendingAction = .pairMac
    }

    func syncNow() {
        sessionState = BridgeSessionState(
            sessionID: sessionState.sessionID,
            transportState: .exportingSnapshot,
            workspaceState: .empty,
            compatibilityState: trustedDevices.isEmpty ? .unknown : .compatible,
            cloudKitReconciliationState: .reconciled,
            liveStoreMutationAllowed: false,
            activePairingMethod: sessionState.activePairingMethod,
            bootstrapToken: sessionState.bootstrapToken,
            lastImportedPackageID: sessionState.lastImportedPackageID
        )

        do {
            let exportedSnapshot = try snapshotExportService.exportAuthoritativeSnapshot()
            latestExportedSnapshot = exportedSnapshot
            latestPreparedImportPackage = nil
            importReviewStatus = .none
            lastSyncOutcome = .succeeded
            pendingAction = .syncNow
            sessionState = BridgeSessionState(
                sessionID: sessionState.sessionID,
                transportState: .waitingForEditedSnapshot,
                workspaceState: .exported,
                compatibilityState: trustedDevices.isEmpty ? .unknown : .compatible,
                cloudKitReconciliationState: .reconciled,
                liveStoreMutationAllowed: false,
                activePairingMethod: sessionState.activePairingMethod,
                bootstrapToken: sessionState.bootstrapToken,
                lastImportedPackageID: sessionState.lastImportedPackageID
            )
            let totalRecords = exportedSnapshot.entityCounts.reduce(0) { $0 + $1.count }
            operatorMessage = "Authoritative snapshot \(exportedSnapshot.manifest.snapshotID.uuidString) exported from CloudKit-backed data with \(totalRecords) records. Transport is still disabled, so the next supported step is local import review scaffolding."
        } catch {
            lastSyncOutcome = .failed
            pendingAction = trustedDevices.filter({ $0.trustState == .active }).isEmpty ? .pairMac : .syncNow
            operatorMessage = "Failed to export authoritative bridge snapshot: \(error.localizedDescription)"
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .idle,
                workspaceState: .discarded,
                compatibilityState: trustedDevices.isEmpty ? .unknown : .compatible,
                cloudKitReconciliationState: .blockedPendingCloudSync,
                liveStoreMutationAllowed: false,
                activePairingMethod: sessionState.activePairingMethod,
                bootstrapToken: sessionState.bootstrapToken,
                lastImportedPackageID: sessionState.lastImportedPackageID
            )
        }
    }

    func openImportReview() {
        do {
            if latestExportedSnapshot == nil {
                latestExportedSnapshot = try snapshotExportService.exportAuthoritativeSnapshot()
            }
            guard let latestExportedSnapshot else {
                operatorMessage = "No bridge snapshot is available for review."
                return
            }

            let trustedDevice = trustedDevices.first(where: { $0.trustState == .active })
            let package = try importValidationService.makePlaceholderPackage(
                from: latestExportedSnapshot,
                trustedDevice: trustedDevice
            )
            latestPreparedImportPackage = package
            importReviewStatus = try importValidationService.review(
                package: package,
                trustedDevice: trustedDevice
            )
            pendingAction = .reviewImport
            sessionState = BridgeSessionState(
                sessionID: sessionState.sessionID,
                transportState: .awaitingImportReview,
                workspaceState: .exported,
                compatibilityState: trustedDevices.isEmpty ? .unknown : .compatible,
                cloudKitReconciliationState: .reconciled,
                liveStoreMutationAllowed: false,
                activePairingMethod: sessionState.activePairingMethod,
                bootstrapToken: sessionState.bootstrapToken,
                lastImportedPackageID: package.packageID
            )
            operatorMessage = "Import review is backed by the current authoritative snapshot contract. Signature verification, transport I/O, and apply remain intentionally disabled."
        } catch {
            importReviewStatus = .none
            pendingAction = trustedDevices.filter({ $0.trustState == .active }).isEmpty ? .pairMac : .syncNow
            operatorMessage = "Failed to prepare import review: \(error.localizedDescription)"
        }
    }

    func markImportDecision(_ decision: BridgeImportOperatorDecisionState) {
        guard importReviewStatus.reviewSummaryDTO != nil else {
            operatorMessage = "No signed import package is currently pending review."
            return
        }

        switch decision {
        case .approvedPlaceholder:
            importReviewStatus.operatorDecision = .approvedPlaceholder
            importReviewStatus.requiresOperatorReview = false
            operatorMessage = "Decision recorded as approved, but import apply is intentionally disabled in this build."
        case .rejected:
            importReviewStatus.operatorDecision = .rejected
            importReviewStatus.requiresOperatorReview = false
            lastSyncOutcome = .cancelled
            sessionState = BridgeSessionState(
                sessionID: sessionState.sessionID,
                transportState: .importRejectedDueToDrift,
                workspaceState: .discarded,
                compatibilityState: sessionState.compatibilityState,
                cloudKitReconciliationState: sessionState.cloudKitReconciliationState,
                liveStoreMutationAllowed: false,
                activePairingMethod: sessionState.activePairingMethod,
                bootstrapToken: sessionState.bootstrapToken,
                lastImportedPackageID: sessionState.lastImportedPackageID
            )
            operatorMessage = "Import package rejected by operator. No data was written."
        case .awaitingDecision:
            importReviewStatus.operatorDecision = .awaitingDecision
            importReviewStatus.requiresOperatorReview = true
            operatorMessage = "Operator decision reset to pending."
        case .notRequired:
            importReviewStatus.operatorDecision = .notRequired
            importReviewStatus.requiresOperatorReview = false
            operatorMessage = "Import review marked as not required."
        }
    }

    func dismissImportReview() {
        importReviewStatus = .none
        latestPreparedImportPackage = nil
        pendingAction = trustedDevices.filter({ $0.trustState == .active }).isEmpty ? .pairMac : .syncNow
        sessionState = BridgeSessionState(
            sessionID: sessionState.sessionID,
            transportState: .idle,
            workspaceState: .discarded,
            compatibilityState: trustedDevices.isEmpty ? .unknown : .compatible,
            cloudKitReconciliationState: .reconciled,
            liveStoreMutationAllowed: false,
            activePairingMethod: sessionState.activePairingMethod,
            bootstrapToken: sessionState.bootstrapToken,
            lastImportedPackageID: sessionState.lastImportedPackageID
        )
        operatorMessage = "Import review dismissed. No authoritative data was mutated."
    }

    func revokeTrust(deviceID: UUID) {
        do {
            try trustStore.revoke(deviceID: deviceID)
            refresh()
            pendingAction = trustedDevices.filter({ $0.trustState == .active }).isEmpty ? .pairMac : .syncNow
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .trustRevoked,
                workspaceState: .empty,
                compatibilityState: .unknown,
                cloudKitReconciliationState: .unknown,
                liveStoreMutationAllowed: false,
                activePairingMethod: nil,
                bootstrapToken: nil,
                lastImportedPackageID: nil
            )
            operatorMessage = "Trust revoked for the selected device. The peer must re-pair before any later bridge session."
        } catch {
            operatorMessage = "Failed to revoke trusted device: \(error.localizedDescription)"
        }
    }
}
