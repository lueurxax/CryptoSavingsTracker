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
    @Published private(set) var latestSignedPackageArtifact: LocalBridgeImportPackageArtifact?
    @Published private(set) var transientWorkspaceArtifact: LocalBridgeTransientWorkspaceArtifact?
    @Published private(set) var transientWorkspaceSnapshot: SnapshotEnvelope?

    private let trustStore: BridgeTrustStoring
    private let identityStore: LocalBridgeIdentityStore
    private let snapshotExportService: LocalBridgeSnapshotExportService
    private let importValidationService: LocalBridgeImportValidationService
    private let importApplyService: LocalBridgeImportApplyService
    private let artifactStore: LocalBridgeArtifactStore
    private let workspaceStore: LocalBridgeTransientWorkspaceStore

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
            artifactStore: LocalBridgeArtifactStore(),
            workspaceStore: LocalBridgeTransientWorkspaceStore()
        )
    }

    init(
        trustStore: BridgeTrustStoring,
        identityStore: LocalBridgeIdentityStore,
        snapshotExportService: LocalBridgeSnapshotExportService,
        importValidationService: LocalBridgeImportValidationService,
        importApplyService: LocalBridgeImportApplyService,
        artifactStore: LocalBridgeArtifactStore,
        workspaceStore: LocalBridgeTransientWorkspaceStore
    ) {
        let initialTrustedDevices = trustStore.loadTrustedDevices()
        let latestImportPackage = artifactStore.latestImportPackageArtifact()
        self.trustStore = trustStore
        self.identityStore = identityStore
        self.snapshotExportService = snapshotExportService
        self.importValidationService = importValidationService
        self.importApplyService = importApplyService
        self.artifactStore = artifactStore
        self.workspaceStore = workspaceStore
        self.trustedDevices = initialTrustedDevices
        self.lastSyncOutcome = .neverSynced
        self.pendingAction = initialTrustedDevices.isEmpty ? .pairMac : .syncNow
        self.importReviewStatus = .none
        self.latestExportArtifact = artifactStore.latestSnapshotArtifact()
        self.latestImportArtifact = latestImportPackage?.artifact
        self.latestSignedPackageArtifact = nil
        self.latestExportedSnapshot = nil
        self.latestPreparedImportPackage = latestImportPackage?.package
        let loadedWorkspace = try? workspaceStore.load()
        self.transientWorkspaceArtifact = loadedWorkspace?.artifact
        self.transientWorkspaceSnapshot = loadedWorkspace?.snapshot
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

    var hasLoadedTransientWorkspace: Bool {
        transientWorkspaceSnapshot != nil
    }

    private var hasActiveTrustedDevices: Bool {
        trustedDevices.contains { $0.trustState == .active }
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
        #if DEBUG
        if UITestFlags.localBridgeScenario != nil {
            return
        }
        #endif
        trustedDevices = trustStore.loadTrustedDevices()
        latestExportArtifact = artifactStore.latestSnapshotArtifact()
        let latestImportPackage = artifactStore.latestImportPackageArtifact()
        latestImportArtifact = latestImportPackage?.artifact
        latestPreparedImportPackage = latestImportPackage?.package
        let loadedWorkspace = try? workspaceStore.load()
        transientWorkspaceArtifact = loadedWorkspace?.artifact
        transientWorkspaceSnapshot = loadedWorkspace?.snapshot
        if !hasActiveTrustedDevices {
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

    func preparePairingToken(displayName: String = "CryptoSavingsTracker Mac", method: BridgePairingMethod = .enterCodeManually) {
        do {
            let token = try identityStore.makeBootstrapToken(displayName: displayName)
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .pairingTokenReady,
                workspaceState: .empty,
                compatibilityState: trustedDevices.isEmpty ? .unknown : .compatible,
                cloudKitReconciliationState: sessionState.cloudKitReconciliationState,
                liveStoreMutationAllowed: false,
                activePairingMethod: method,
                bootstrapToken: token,
                lastImportedPackageID: sessionState.lastImportedPackageID
            )
            pendingAction = trustedDevices.filter({ $0.trustState == .active }).isEmpty ? .pairMac : .syncNow
            operatorMessage = "Bootstrap token prepared for \(method.displayTitle). Share it with the iPhone before any later signed package review."
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
            operatorMessage = "Failed to create pairing bootstrap token: \(error.localizedDescription)"
            pendingAction = .pairMac
        }
    }

    func pairMac(using method: BridgePairingMethod = .enterCodeManually, bootstrapTokenString: String) {
        do {
            let token: BridgeBootstrapToken
            switch method {
            case .enterCodeManually:
                if let pairingCodeToken = try? BridgeBootstrapToken.decodePairingCode(bootstrapTokenString) {
                    token = pairingCodeToken
                } else {
                    token = try BridgeBootstrapToken.decodeManualEntryToken(bootstrapTokenString)
                }
            case .scanQR, .pasteBootstrapToken:
                token = try BridgeBootstrapToken.decodeManualEntryToken(bootstrapTokenString)
            }
            guard !token.isExpired else {
                throw BridgeBootstrapTokenError.invalidPayload
            }

            let device = try identityStore.trustedDevice(from: token)
            try trustStore.upsert(device)
            trustedDevices = trustStore.loadTrustedDevices()
            pendingAction = .syncNow
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .connected,
                workspaceState: transientWorkspaceSnapshot == nil ? .empty : .loadedTransientWorkspace,
                compatibilityState: .compatible,
                cloudKitReconciliationState: .reconciled,
                liveStoreMutationAllowed: false,
                activePairingMethod: method,
                bootstrapToken: token,
                lastImportedPackageID: sessionState.lastImportedPackageID
            )
            operatorMessage = "Trusted device record created from the shared bootstrap token. Signed bridge packages from that Mac can now be reviewed and applied."
        } catch {
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .pairingRequired,
                workspaceState: transientWorkspaceSnapshot == nil ? .empty : .loadedTransientWorkspace,
                compatibilityState: trustedDevices.isEmpty ? .unknown : .compatible,
                cloudKitReconciliationState: sessionState.cloudKitReconciliationState,
                liveStoreMutationAllowed: false,
                activePairingMethod: method,
                bootstrapToken: nil,
                lastImportedPackageID: sessionState.lastImportedPackageID
            )
            operatorMessage = "Failed to import bridge bootstrap token: \(error.localizedDescription)"
            pendingAction = trustedDevices.filter({ $0.trustState == .active }).isEmpty ? .pairMac : .syncNow
        }
    }

    func syncNow() {
        guard hasActiveTrustedDevices else {
            pendingAction = .pairMac
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .pairingRequired,
                workspaceState: .empty,
                compatibilityState: .unknown,
                cloudKitReconciliationState: sessionState.cloudKitReconciliationState,
                liveStoreMutationAllowed: false,
                activePairingMethod: sessionState.activePairingMethod,
                bootstrapToken: sessionState.bootstrapToken,
                lastImportedPackageID: sessionState.lastImportedPackageID
            )
            operatorMessage = "Pair a trusted Mac before exporting or exchanging bridge snapshots."
            return
        }

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
            try updateValidationHistory(for: trustedDevice, status: importReviewStatus.validationStatus)
            let requiresUpdate = importReviewStatus.blockingIssues.contains {
                $0.localizedCaseInsensitiveContains("incompatible") ||
                $0.localizedCaseInsensitiveContains("outside the supported range")
            }
            let isDriftRejection = importReviewStatus.driftStatus == .conflicting
            let trustStatus = importReviewStatus.reviewSummaryDTO?.package.trustStatus
            let isTrustRejection = trustStatus == .trustRevoked || trustStatus == .signerUntrusted

            if importReviewStatus.requiresOperatorReview {
                pendingAction = requiresUpdate ? .updateRequired : .reviewImport
            } else if requiresUpdate {
                pendingAction = .updateRequired
            } else if isTrustRejection {
                pendingAction = .trustRevoked
            } else {
                pendingAction = hasActiveTrustedDevices ? .syncNow : .pairMac
            }
            sessionState = BridgeSessionState(
                sessionID: sessionState.sessionID,
                transportState: resolvedTransportState(
                    requiresOperatorReview: importReviewStatus.requiresOperatorReview,
                    requiresUpdate: requiresUpdate,
                    isDriftRejection: isDriftRejection,
                    isTrustRejection: isTrustRejection
                ),
                workspaceState: .loadedTransientWorkspace,
                compatibilityState: requiresUpdate ? .updateRequired : (hasActiveTrustedDevices ? .compatible : .unknown),
                cloudKitReconciliationState: isDriftRejection ? .blockedPendingCloudSync : .reconciled,
                liveStoreMutationAllowed: false,
                activePairingMethod: sessionState.activePairingMethod,
                bootstrapToken: sessionState.bootstrapToken,
                lastImportedPackageID: latestPreparedImportPackage.packageID
            )
            operatorMessage = blockedImportMessage(
                requiresOperatorReview: importReviewStatus.requiresOperatorReview,
                requiresUpdate: requiresUpdate,
                isDriftRejection: isDriftRejection,
                isTrustRejection: isTrustRejection
            )
        } catch {
            importReviewStatus = .none
            pendingAction = hasActiveTrustedDevices ? .syncNow : .pairMac
            operatorMessage = "Failed to prepare import review: \(error.localizedDescription)"
        }
    }

    func loadAuthoritativeSnapshotIntoTransientWorkspace() {
        do {
            let snapshot = try snapshotExportService.exportAuthoritativeSnapshot()
            let artifact = try workspaceStore.save(snapshot)
            transientWorkspaceArtifact = artifact
            transientWorkspaceSnapshot = snapshot
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: trustedDevices.isEmpty ? .pairingRequired : .idle,
                workspaceState: .loadedTransientWorkspace,
                compatibilityState: trustedDevices.isEmpty ? .unknown : .compatible,
                cloudKitReconciliationState: .reconciled,
                liveStoreMutationAllowed: false,
                activePairingMethod: sessionState.activePairingMethod,
                bootstrapToken: sessionState.bootstrapToken,
                lastImportedPackageID: sessionState.lastImportedPackageID
            )
            operatorMessage = "Authoritative snapshot loaded into an isolated transient workspace. Edit the workspace copy and export a signed package when ready."
        } catch {
            operatorMessage = "Failed to load authoritative snapshot into transient workspace: \(error.localizedDescription)"
        }
    }

    func saveTransientWorkspaceDraft(_ snapshot: SnapshotEnvelope) {
        do {
            let artifact = try workspaceStore.save(
                snapshot,
                workspaceID: transientWorkspaceArtifact?.workspaceID,
                createdAt: transientWorkspaceArtifact?.createdAt
            )
            transientWorkspaceArtifact = artifact
            transientWorkspaceSnapshot = snapshot
            sessionState = BridgeSessionState(
                sessionID: sessionState.sessionID,
                transportState: sessionState.transportState,
                workspaceState: .edited,
                compatibilityState: sessionState.compatibilityState,
                cloudKitReconciliationState: sessionState.cloudKitReconciliationState,
                liveStoreMutationAllowed: false,
                activePairingMethod: sessionState.activePairingMethod,
                bootstrapToken: sessionState.bootstrapToken,
                lastImportedPackageID: sessionState.lastImportedPackageID
            )
            operatorMessage = "Transient workspace saved. The live CloudKit-backed runtime remains unchanged until iPhone approval."
        } catch {
            operatorMessage = "Failed to save transient workspace: \(error.localizedDescription)"
        }
    }

    func discardTransientWorkspace() {
        workspaceStore.clear()
        transientWorkspaceArtifact = nil
        transientWorkspaceSnapshot = nil
        sessionState = BridgeSessionState(
            sessionID: UUID(),
            transportState: trustedDevices.isEmpty ? .pairingRequired : .idle,
            workspaceState: .discarded,
            compatibilityState: trustedDevices.isEmpty ? .unknown : .compatible,
            cloudKitReconciliationState: sessionState.cloudKitReconciliationState,
            liveStoreMutationAllowed: false,
            activePairingMethod: sessionState.activePairingMethod,
            bootstrapToken: sessionState.bootstrapToken,
            lastImportedPackageID: sessionState.lastImportedPackageID
        )
        operatorMessage = "Transient bridge workspace discarded. The live CloudKit-backed runtime remains unchanged."
    }

    func exportSignedPackageFromTransientWorkspace(displayName: String = "CryptoSavingsTracker Mac") {
        do {
            guard let transientWorkspaceSnapshot else {
                operatorMessage = "Load a transient workspace before exporting a signed package."
                return
            }

            let signingDevice = try identityStore.localBridgeIdentity(displayName: displayName)
            let package = try importValidationService.makeSignedPackage(
                from: transientWorkspaceSnapshot,
                trustedDevice: signingDevice
            )
            latestSignedPackageArtifact = try artifactStore.persist(
                importPackage: package,
                sourceDeviceName: signingDevice.displayName
            )
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .waitingForPeer,
                workspaceState: .exported,
                compatibilityState: trustedDevices.isEmpty ? .unknown : .compatible,
                cloudKitReconciliationState: .reconciled,
                liveStoreMutationAllowed: false,
                activePairingMethod: sessionState.activePairingMethod,
                bootstrapToken: sessionState.bootstrapToken,
                lastImportedPackageID: sessionState.lastImportedPackageID
            )
            operatorMessage = "Signed import package exported from the transient workspace. Share the package artifact with the paired iPhone for review."
        } catch {
            operatorMessage = "Failed to export signed package from transient workspace: \(error.localizedDescription)"
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
                operatorMessage = "Signed import package \(result.receipt.packageID) was approved and \(result.disposition == .applied ? "applied" : "accepted as already applied") against the CloudKit runtime."
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
            pendingAction = trustedDevices.filter({ $0.trustState == .active }).isEmpty ? .pairMac : .syncNow
            sessionState = BridgeSessionState(
                sessionID: sessionState.sessionID,
                transportState: .importCancelledByUser,
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
            pendingAction = .reviewImport
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

    private func updateValidationHistory(
        for trustedDevice: TrustedBridgeDevice?,
        status: BridgeImportValidationStatus
    ) throws {
        guard var trustedDevice else { return }

        let outcome: BridgeValidationOutcome
        switch status {
        case .passed:
            outcome = .passed
        case .warnings:
            outcome = .warnings
        case .failed, .notRun:
            outcome = .failed
        }

        trustedDevice.lastValidationOutcome = outcome
        trustedDevice.lastValidationAt = Date()
        try trustStore.upsert(trustedDevice)
        trustedDevices = trustStore.loadTrustedDevices()
    }

    private func packageBelongsToRevokedDevice(
        _ package: SignedImportPackage?,
        revokedDevice: TrustedBridgeDevice
    ) -> Bool {
        guard let package else { return false }
        let matchesSigningKey = revokedDevice.signingKeyID == package.signingKeyID
        let matchesFingerprint = revokedDevice.fingerprint.caseInsensitiveCompare(package.signerFingerprint) == .orderedSame
        return matchesSigningKey || matchesFingerprint
    }

    private func resolvedTransportState(
        requiresOperatorReview: Bool,
        requiresUpdate: Bool,
        isDriftRejection: Bool,
        isTrustRejection: Bool
    ) -> BridgeTransportState {
        if requiresOperatorReview {
            return .awaitingImportReview
        }
        if isDriftRejection {
            return .importRejectedDueToDrift
        }
        if isTrustRejection {
            return .trustRevoked
        }
        if requiresUpdate {
            return .idle
        }
        return .idle
    }

    private func blockedImportMessage(
        requiresOperatorReview: Bool,
        requiresUpdate: Bool,
        isDriftRejection: Bool,
        isTrustRejection: Bool
    ) -> String {
        if requiresOperatorReview {
            return "Loaded import package is ready for operator review. Signature verification is active, and apply is available after explicit approval."
        }
        if requiresUpdate {
            return "Loaded import package was rejected before review because bridge compatibility must be updated."
        }
        if isDriftRejection {
            return "Import rejected before review because the authoritative CloudKit dataset changed. Export a fresh snapshot and try again."
        }
        if isTrustRejection {
            return "Import rejected before review because the sending device is no longer trusted on this install."
        }
        return "Import rejected before review because the signed package failed validation."
    }

    func dismissImportReview() {
        importReviewStatus = .none
        pendingAction = hasActiveTrustedDevices ? .syncNow : .pairMac
        sessionState = BridgeSessionState(
            sessionID: sessionState.sessionID,
            transportState: .idle,
            workspaceState: .discarded,
            compatibilityState: hasActiveTrustedDevices ? .compatible : .unknown,
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
            guard let revokedDevice = trustedDevices.first(where: { $0.id == deviceID }) else {
                return
            }
            let invalidatedPackages = artifactStore.purgeImportPackages(for: revokedDevice)
            if packageBelongsToRevokedDevice(latestPreparedImportPackage, revokedDevice: revokedDevice) {
                if let latestImportArtifact {
                    artifactStore.clearImportPackage(at: latestImportArtifact.fileURL)
                }
                latestPreparedImportPackage = nil
                latestImportArtifact = nil
                importReviewStatus = .none
            }
            try trustStore.remove(deviceID: deviceID)
            refresh()
            pendingAction = hasActiveTrustedDevices ? .syncNow : .trustRevoked
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
            operatorMessage = "Trust revoked for the selected device. \(invalidatedPackages) unconsumed import package(s) were invalidated and the peer must re-pair before any later bridge session."
        } catch {
            operatorMessage = "Failed to revoke trusted device: \(error.localizedDescription)"
        }
    }

    #if DEBUG
    func resetForUITesting() {
        trustedDevices = []
        lastSyncOutcome = .neverSynced
        pendingAction = .pairMac
        importReviewStatus = .none
        operatorMessage = nil
        sessionState = .idle
        latestExportArtifact = nil
        latestImportArtifact = nil
        latestSignedPackageArtifact = nil
        latestExportedSnapshot = nil
        latestPreparedImportPackage = nil
        transientWorkspaceArtifact = nil
        transientWorkspaceSnapshot = nil
    }

    func seedUITestScenario(_ scenario: UITestFlags.LocalBridgeScenario) {
        resetForUITesting()

        switch scenario {
        case .pairingRequired:
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .pairingRequired,
                workspaceState: .empty,
                compatibilityState: .unknown,
                cloudKitReconciliationState: .unknown,
                liveStoreMutationAllowed: false,
                activePairingMethod: .enterCodeManually,
                bootstrapToken: Self.makeUITestBootstrapToken(),
                lastImportedPackageID: nil
            )
            pendingAction = .pairMac
            operatorMessage = "Pair a trusted Mac before you can exchange bridge snapshots."
        case .ready:
            trustedDevices = [Self.makeUITestTrustedDevice(displayName: "Bridge Mac")]
            lastSyncOutcome = .succeeded
            pendingAction = .syncNow
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .idle,
                workspaceState: .exported,
                compatibilityState: .compatible,
                cloudKitReconciliationState: .reconciled,
                liveStoreMutationAllowed: false,
                activePairingMethod: .enterCodeManually,
                bootstrapToken: Self.makeUITestBootstrapToken(),
                lastImportedPackageID: nil
            )
            latestExportArtifact = Self.makeUITestSnapshotArtifact()
            operatorMessage = "Authoritative snapshot exported and ready for manual handoff."
        case .reviewReady:
            seedUITestReviewScenario(blocked: false)
        case .reviewBlocked:
            seedUITestReviewScenario(blocked: true)
        case .trustRevoked:
            trustedDevices = [Self.makeUITestTrustedDevice(displayName: "Bridge Mac", trustState: .revoked)]
            lastSyncOutcome = .cancelled
            pendingAction = .trustRevoked
            sessionState = BridgeSessionState(
                sessionID: UUID(),
                transportState: .trustRevoked,
                workspaceState: .empty,
                compatibilityState: .unknown,
                cloudKitReconciliationState: .unknown,
                liveStoreMutationAllowed: false,
                activePairingMethod: .enterCodeManually,
                bootstrapToken: nil,
                lastImportedPackageID: nil
            )
            operatorMessage = "Trust revoked for the selected device. The peer must re-pair before any later bridge session."
        }
    }

    private func seedUITestReviewScenario(blocked: Bool) {
        let trustedDevice = Self.makeUITestTrustedDevice(displayName: "Bridge Mac")
        let package = Self.makeUITestSignedPackage(sourceDeviceName: trustedDevice.displayName)
        trustedDevices = [trustedDevice]
        lastSyncOutcome = blocked ? .failed : .succeeded
        pendingAction = blocked ? .updateRequired : .reviewImport
        latestPreparedImportPackage = package
        latestImportArtifact = Self.makeUITestImportArtifact(packageID: package.packageID, snapshotID: package.snapshotID, signedAt: package.signedAt, sourceDeviceName: trustedDevice.displayName)
        importReviewStatus = Self.makeUITestReviewStatus(packageID: package.packageID, blocked: blocked)
        sessionState = BridgeSessionState(
            sessionID: UUID(),
            transportState: .awaitingImportReview,
            workspaceState: .loadedTransientWorkspace,
            compatibilityState: blocked ? .updateRequired : .compatible,
            cloudKitReconciliationState: blocked ? .blockedPendingCloudSync : .reconciled,
            liveStoreMutationAllowed: false,
            activePairingMethod: .enterCodeManually,
            bootstrapToken: Self.makeUITestBootstrapToken(),
            lastImportedPackageID: package.packageID
        )
        operatorMessage = blocked
            ? "Loaded import package requires a bridge compatibility update before review can continue."
            : "Loaded import package is ready for operator review. Signature verification is active, and apply is available after explicit approval."
    }

    private static func makeUITestBootstrapToken() -> BridgeBootstrapToken {
        BridgeBootstrapToken(
            pairingID: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
            deviceName: "CryptoSavingsTracker Mac",
            expiresAt: Date().addingTimeInterval(10 * 60),
            oneTimeSecretReference: "ui-test-secret",
            ephemeralPublicKey: "UITESTEPHEMERALKEY1234567890",
            signingKeyID: "ui-test-signing-key",
            publicKeyRepresentation: Data("ui-test-public-key".utf8).base64EncodedString(),
            signingAlgorithm: "P256.Signing.ECDSA.SHA256",
            fingerprint: "ABCDEF1234567890ABCDEF1234567890"
        )
    }

    private static func makeUITestTrustedDevice(
        displayName: String,
        trustState: BridgeTrustState = .active
    ) -> TrustedBridgeDevice {
        TrustedBridgeDevice(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
            displayName: displayName,
            fingerprint: "ABCDEF1234567890ABCDEF1234567890",
            signingKeyID: "ui-test-signing-key",
            publicKeyRepresentation: Data("ui-test-public-key".utf8).base64EncodedString(),
            signingAlgorithm: "P256.Signing.ECDSA.SHA256",
            addedAt: Date().addingTimeInterval(-86400),
            lastSuccessfulSyncAt: Date().addingTimeInterval(-3600),
            trustState: trustState
        )
    }

    private static func makeUITestSnapshotEnvelope() -> SnapshotEnvelope {
        let exportedAt = Date().addingTimeInterval(-1800)
        let snapshotID = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()
        let manifest = SnapshotManifest(
            snapshotID: snapshotID,
            canonicalEncodingVersion: "bridge-snapshot-v1",
            snapshotSchemaVersion: 1,
            exportedAt: exportedAt,
            appModelSchemaVersion: "cloudkit-model-v1",
            entityCounts: [],
            baseDatasetFingerprint: "ui-test-dataset-fingerprint"
        )
        return SnapshotEnvelope(
            manifest: manifest,
            goals: [],
            assets: [],
            transactions: [],
            assetAllocations: [],
            allocationHistories: [],
            monthlyPlans: [],
            monthlyExecutionRecords: [],
            completedExecutions: [],
            executionSnapshots: [],
            completionEvents: []
        )
    }

    private static func makeUITestSignedPackage(sourceDeviceName: String) -> SignedImportPackage {
        let snapshot = makeUITestSnapshotEnvelope()
        let unsigned = SignedImportPackage(
            packageID: "",
            snapshotID: snapshot.manifest.snapshotID,
            canonicalEncodingVersion: snapshot.manifest.canonicalEncodingVersion,
            baseDatasetFingerprint: snapshot.manifest.baseDatasetFingerprint,
            editedDatasetFingerprint: snapshot.manifest.baseDatasetFingerprint,
            snapshotEnvelope: snapshot,
            signingKeyID: "ui-test-signing-key",
            signingAlgorithm: "P256.Signing.ECDSA.SHA256",
            signerPublicKeyRepresentation: Data(sourceDeviceName.utf8).base64EncodedString(),
            signedAt: Date().addingTimeInterval(-900),
            signature: Data("ui-test-signature".utf8).base64EncodedString()
        )
        let packageID = (try? unsigned.computedPackageID()) ?? "ui-test-package-invalid"
        return SignedImportPackage(
            packageID: packageID,
            snapshotID: unsigned.snapshotID,
            canonicalEncodingVersion: unsigned.canonicalEncodingVersion,
            baseDatasetFingerprint: unsigned.baseDatasetFingerprint,
            editedDatasetFingerprint: unsigned.editedDatasetFingerprint,
            snapshotEnvelope: unsigned.snapshotEnvelope,
            signingKeyID: unsigned.signingKeyID,
            signingAlgorithm: unsigned.signingAlgorithm,
            signerPublicKeyRepresentation: unsigned.signerPublicKeyRepresentation,
            signedAt: unsigned.signedAt,
            signature: unsigned.signature
        )
    }

    private static func makeUITestSnapshotArtifact() -> LocalBridgeSnapshotArtifact {
        LocalBridgeSnapshotArtifact(
            snapshotID: UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID(),
            exportedAt: Date().addingTimeInterval(-1800),
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("ui-test-bridge-snapshot.json"),
            fileSizeBytes: 1024,
            entityCounts: [
                BridgeEntityCount(name: "Goal", count: 4),
                BridgeEntityCount(name: "Transaction", count: 12)
            ]
        )
    }

    private static func makeUITestImportArtifact(
        packageID: String,
        snapshotID: UUID,
        signedAt: Date,
        sourceDeviceName: String
    ) -> LocalBridgeImportPackageArtifact {
        LocalBridgeImportPackageArtifact(
            packageID: packageID,
            snapshotID: snapshotID,
            signedAt: signedAt,
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("ui-test-bridge-import.json"),
            fileSizeBytes: 2048,
            sourceDeviceName: sourceDeviceName
        )
    }

    private static func makeUITestReviewStatus(
        packageID: String,
        blocked: Bool
    ) -> BridgeImportReviewStatus {
        let package = BridgeSignedImportPackageSummaryDTO(
            packageID: packageID,
            packageVersion: "bridge-import-v1",
            canonicalEncodingVersion: "bridge-snapshot-v1",
            sourceDeviceName: "Bridge Mac",
            sourceDeviceFingerprint: "ABCDEF1234567890",
            producedAt: Date().addingTimeInterval(-1800),
            expiresAt: Date().addingTimeInterval(1800),
            payloadBytes: 2048,
            digestHexPrefix: "5f4dcc3b5aa7",
            signatureStatus: .valid,
            trustStatus: blocked ? .trustRevoked : .activeTrusted
        )
        let reviewDTO = BridgeImportReviewSummaryDTO(
            package: package,
            validationStatus: blocked ? .failed : .warnings,
            driftStatus: blocked ? .conflicting : .none,
            warnings: blocked ? ["Bridge compatibility requires update before apply."] : ["Transaction history would change if this package were applied."],
            blockingIssues: blocked ? ["Package canonical encoding bridge-snapshot-v999 is incompatible with this build."] : [],
            entityDeltas: [
                BridgeImportEntityDeltaDTO(entityName: "Goal", incomingCount: 4, existingCount: 4, changedCount: 1),
                BridgeImportEntityDeltaDTO(entityName: "Transaction", incomingCount: 12, existingCount: 11, changedCount: 2),
                BridgeImportEntityDeltaDTO(entityName: "AssetAllocation", incomingCount: 6, existingCount: 6, changedCount: 1)
            ],
            concreteDiffs: [
                BridgeImportConcreteDiffDTO(
                    entityName: "Goal",
                    entityID: UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID(),
                    changeKind: .updated,
                    title: "Goal Emergency Fund",
                    beforeSummary: "Emergency Fund • 15000 USD • deadline 2026-03-13T00:00:00Z • status active",
                    afterSummary: "Emergency Fund • 18000 USD • deadline 2026-06-12T00:00:00Z • status active"
                ),
                BridgeImportConcreteDiffDTO(
                    entityName: "AssetAllocation",
                    entityID: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID(),
                    changeKind: .updated,
                    title: "Allocation 8f31c2ab",
                    beforeSummary: "asset 4A3E6E72-9B48-4B53-91A2-2E6F03F1A0CC • goal 2D5148EE-7AE1-4C1E-A447-FF26F2AC3E44 • amount 0.35",
                    afterSummary: "asset 4A3E6E72-9B48-4B53-91A2-2E6F03F1A0CC • goal 2D5148EE-7AE1-4C1E-A447-FF26F2AC3E44 • amount 0.50"
                )
            ]
        )

        return BridgeImportReviewStatus(
            summary: blocked ? "Review blocked until compatibility is updated." : "Review pending",
            requiresOperatorReview: true,
            validationStatus: reviewDTO.validationStatus,
            driftStatus: reviewDTO.driftStatus,
            operatorDecision: .awaitingDecision,
            importReviewSummary: ImportReviewSummary(
                packageID: packageID,
                snapshotID: UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID(),
                sourceDeviceName: "Bridge Mac",
                signatureStatus: reviewDTO.package.signatureStatus,
                validationStatus: reviewDTO.validationStatus,
                driftStatus: reviewDTO.driftStatus,
                changedEntityCounts: reviewDTO.changedEntityCounts,
                warnings: reviewDTO.warnings,
                blockingIssues: reviewDTO.blockingIssues
            ),
            reviewSummaryDTO: reviewDTO,
            validationWarnings: reviewDTO.warnings,
            blockingIssues: reviewDTO.blockingIssues
        )
    }
    #endif
}
