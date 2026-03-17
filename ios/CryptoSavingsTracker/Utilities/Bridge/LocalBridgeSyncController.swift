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
    @Published private(set) var latestExportArtifact: LocalBridgeSnapshotArtifact?
    @Published private(set) var latestImportArtifact: LocalBridgeImportPackageArtifact?

    private let trustStore: BridgeTrustStoring
    private let identityStore: LocalBridgeIdentityStore
    private let snapshotExportService: LocalBridgeSnapshotExportService
    private let importValidationService: LocalBridgeImportValidationService
    private let importApplyService: LocalBridgeImportApplyService
    private let artifactStore: LocalBridgeArtifactStore

    private var latestExportedSnapshot: SnapshotEnvelope?
    private var latestPreparedImportPackage: SignedImportPackage?

    convenience init() {
        let exportService = LocalBridgeSnapshotExportService()
        let validationService = LocalBridgeImportValidationService(snapshotExportService: exportService)
        self.init(
            trustStore: BridgeTrustStore(),
            identityStore: LocalBridgeIdentityStore(),
            snapshotExportService: exportService,
            importValidationService: validationService,
            importApplyService: LocalBridgeImportApplyService(
                snapshotExportService: exportService,
                validationService: validationService,
                receiptStore: UserDefaultsBridgeImportReceiptStore()
            ),
            artifactStore: LocalBridgeArtifactStore()
        )
    }

    init(
        trustStore: BridgeTrustStoring,
        identityStore: LocalBridgeIdentityStore,
        snapshotExportService: LocalBridgeSnapshotExportService,
        importValidationService: LocalBridgeImportValidationService,
        importApplyService: LocalBridgeImportApplyService,
        artifactStore: LocalBridgeArtifactStore
    ) {
        let initialTrustedDevices = trustStore.loadTrustedDevices()
        let latestImportPackage = artifactStore.latestImportPackageArtifact()
        self.trustStore = trustStore
        self.identityStore = identityStore
        self.snapshotExportService = snapshotExportService
        self.importValidationService = importValidationService
        self.importApplyService = importApplyService
        self.artifactStore = artifactStore
        self.trustedDevices = initialTrustedDevices
        self.lastSyncOutcome = .neverSynced
        self.pendingAction = initialTrustedDevices.isEmpty ? .pairMac : .syncNow
        self.importReviewStatus = .none
        self.latestExportArtifact = artifactStore.latestSnapshotArtifact()
        self.latestImportArtifact = latestImportPackage?.artifact
        self.latestExportedSnapshot = nil
        self.latestPreparedImportPackage = latestImportPackage?.package
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

    var hasLoadedImportPackage: Bool {
        latestPreparedImportPackage != nil
    }

    var latestLoadedImportPackageID: String? {
        latestPreparedImportPackage?.packageID
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
        latestExportArtifact = artifactStore.latestSnapshotArtifact()
        let latestImportPackage = artifactStore.latestImportPackageArtifact()
        latestImportArtifact = latestImportPackage?.artifact
        latestPreparedImportPackage = latestImportPackage?.package
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
        do {
            let device = try identityStore.createTrustedDevice(displayName: "Trusted Mac")
            try trustStore.upsert(device)
            trustedDevices = trustStore.loadTrustedDevices()
            pendingAction = .syncNow
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .connected,
                workspaceState: .empty,
                compatibilityState: .compatible,
                cloudKitReconciliationState: .reconciled,
                liveStoreMutationAllowed: false,
                activePairingMethod: method,
                bootstrapToken: token,
                lastImportedPackageID: sessionState.lastImportedPackageID
            )
            operatorMessage = "Trusted device record created for \(method.displayTitle). File-based bridge packages signed by that device can now be reviewed and applied."
        } catch {
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .pairingRequired,
                workspaceState: .empty,
                compatibilityState: .unknown,
                cloudKitReconciliationState: .unknown,
                liveStoreMutationAllowed: false,
                activePairingMethod: method,
                bootstrapToken: nil,
                lastImportedPackageID: sessionState.lastImportedPackageID
            )
            operatorMessage = "Failed to create trusted device record: \(error.localizedDescription)"
            pendingAction = .pairMac
        }
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
            let exportArtifact = try artifactStore.persist(snapshot: exportedSnapshot)
            latestExportedSnapshot = exportedSnapshot
            latestExportArtifact = exportArtifact
            latestPreparedImportPackage = nil
            latestImportArtifact = nil
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
            operatorMessage = "Authoritative snapshot \(exportedSnapshot.manifest.snapshotID.uuidString) exported with \(totalRecords) records and saved to \(exportArtifact.displayName). Share that file with the paired Mac and load the returned package from Files for review."
        } catch {
            lastSyncOutcome = .failed
            pendingAction = trustedDevices.filter({ $0.trustState == .active }).isEmpty ? .pairMac : .syncNow
            operatorMessage = "Failed to export authoritative bridge snapshot artifact: \(error.localizedDescription)"
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
            guard let latestPreparedImportPackage else {
                operatorMessage = "Load a returned bridge import package from Files before opening import review."
                return
            }

            let trustedDevice = matchingTrustedDevice(for: latestPreparedImportPackage)
            importReviewStatus = try importValidationService.review(
                package: latestPreparedImportPackage,
                trustedDevice: trustedDevice
            )
            let requiresUpdate = importReviewStatus.blockingIssues.contains {
                $0.localizedCaseInsensitiveContains("incompatible") ||
                $0.localizedCaseInsensitiveContains("outside the supported range")
            }
            pendingAction = requiresUpdate ? .updateRequired : .reviewImport
            sessionState = BridgeSessionState(
                sessionID: sessionState.sessionID,
                transportState: .awaitingImportReview,
                workspaceState: .loadedTransientWorkspace,
                compatibilityState: requiresUpdate ? .updateRequired : (trustedDevices.isEmpty ? .unknown : .compatible),
                cloudKitReconciliationState: .reconciled,
                liveStoreMutationAllowed: false,
                activePairingMethod: sessionState.activePairingMethod,
                bootstrapToken: sessionState.bootstrapToken,
                lastImportedPackageID: latestPreparedImportPackage.packageID
            )
            operatorMessage = requiresUpdate
                ? "Loaded import package requires a bridge compatibility update before review can continue."
                : "Loaded import package is ready for operator review. Signature verification is active, and apply is available after explicit approval."
        } catch {
            importReviewStatus = .none
            pendingAction = trustedDevices.filter({ $0.trustState == .active }).isEmpty ? .pairMac : .syncNow
            operatorMessage = "Failed to prepare import review: \(error.localizedDescription)"
        }
    }

    func loadImportPackage(from fileURL: URL) {
        sessionState = BridgeSessionState(
            sessionID: sessionState.sessionID,
            transportState: .validatingImport,
            workspaceState: .loadedTransientWorkspace,
            compatibilityState: trustedDevices.isEmpty ? .unknown : .compatible,
            cloudKitReconciliationState: .reconciled,
            liveStoreMutationAllowed: false,
            activePairingMethod: sessionState.activePairingMethod,
            bootstrapToken: sessionState.bootstrapToken,
            lastImportedPackageID: sessionState.lastImportedPackageID
        )

        do {
            let loadedPackage = try artifactStore.importPackage(from: fileURL)
            latestImportArtifact = loadedPackage.artifact
            latestPreparedImportPackage = loadedPackage.package
            openImportReview()
        } catch {
            importReviewStatus = .none
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
            operatorMessage = "Failed to load bridge import package: \(error.localizedDescription)"
        }
    }

    func markImportDecision(_ decision: BridgeImportOperatorDecisionState) {
        guard importReviewStatus.reviewSummaryDTO != nil else {
            operatorMessage = "No signed import package is currently pending review."
            return
        }

        switch decision {
        case .approved:
            guard let latestPreparedImportPackage else {
                operatorMessage = "No signed import package is currently loaded."
                return
            }

            importReviewStatus.operatorDecision = .approved
            importReviewStatus.requiresOperatorReview = false

            do {
                let trustedDevice = matchingTrustedDevice(for: latestPreparedImportPackage)
                let result = try importApplyService.applyReviewedPackageToAuthoritativeDataset(
                    latestPreparedImportPackage,
                    trustedDevice: trustedDevice,
                    reviewStatus: importReviewStatus
                )
                if var trustedDevice {
                    trustedDevice.lastSuccessfulSyncAt = result.receipt.appliedAt
                    try trustStore.upsert(trustedDevice)
                    trustedDevices = trustStore.loadTrustedDevices()
                }

                lastSyncOutcome = .succeeded
                pendingAction = .syncNow
                importReviewStatus = .none
                sessionState = BridgeSessionState(
                    sessionID: sessionState.sessionID,
                    transportState: .importApplied,
                    workspaceState: .discarded,
                    compatibilityState: .compatible,
                    cloudKitReconciliationState: .reconciled,
                    liveStoreMutationAllowed: false,
                    activePairingMethod: sessionState.activePairingMethod,
                    bootstrapToken: sessionState.bootstrapToken,
                    lastImportedPackageID: result.receipt.packageID
                )
                operatorMessage = "Signed import package \(result.receipt.packageID) was \(result.disposition == .applied ? "applied" : "accepted as already applied") against the CloudKit runtime."
            } catch {
                importReviewStatus.operatorDecision = .awaitingDecision
                importReviewStatus.requiresOperatorReview = true
                lastSyncOutcome = .failed
                sessionState = BridgeSessionState(
                    sessionID: sessionState.sessionID,
                    transportState: .awaitingImportReview,
                    workspaceState: .loadedTransientWorkspace,
                    compatibilityState: sessionState.compatibilityState,
                    cloudKitReconciliationState: sessionState.cloudKitReconciliationState,
                    liveStoreMutationAllowed: false,
                    activePairingMethod: sessionState.activePairingMethod,
                    bootstrapToken: sessionState.bootstrapToken,
                    lastImportedPackageID: sessionState.lastImportedPackageID
                )
                operatorMessage = "Failed to apply signed import package: \(error.localizedDescription)"
            }
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

    private func matchingTrustedDevice(for package: SignedImportPackage) -> TrustedBridgeDevice? {
        let activeDevices = trustedDevices.filter { $0.trustState == .active }
        if let keyMatch = activeDevices.first(where: { $0.signingKeyID == package.signingKeyID }) {
            return keyMatch
        }
        return activeDevices.first {
            $0.fingerprint.caseInsensitiveCompare(package.signerFingerprint) == .orderedSame
        }
    }

    func dismissImportReview() {
        importReviewStatus = .none
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
        operatorMessage = "Import review dismissed. The loaded package remains on disk and can be reopened."
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
