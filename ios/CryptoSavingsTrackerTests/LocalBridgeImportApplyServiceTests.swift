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
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        let artifactStore = LocalBridgeArtifactStore(appSupportURL: artifactRoot)
        let controller = LocalBridgeSyncController(
            trustStore: trustStore,
            identityStore: identityStore,
            snapshotExportService: exportService,
            importValidationService: validationService,
            importApplyService: importApplyService,
            artifactStore: artifactStore,
            workspaceStore: LocalBridgeTransientWorkspaceStore(appSupportURL: artifactRoot)
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
        #expect(controller.importReviewStatus.reviewSummaryDTO?.package.packageID == package.packageID)
        #expect(controller.importReviewStatus.validationStatus != .failed)
        #expect(controller.pendingAction == LocalBridgePendingAction.reviewImport)

        controller.markImportDecision(BridgeImportOperatorDecisionState.approved)

        #expect(controller.importReviewStatus.reviewSummaryDTO == nil)
        #expect(controller.pendingAction == .syncNow)
        #expect(controller.lastSyncOutcome == .succeeded)
        #expect(controller.sessionState.transportState == .importApplied)
        #expect(controller.sessionState.lastImportedPackageID == package.packageID)
        #expect(controller.operatorMessage?.contains("approved") == true)
    }

    @Test("Controller reject returns bridge flow to sync-now state without mutation")
    func controllerRejectsPackageAndClearsReviewRequirement() throws {
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
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        let artifactStore = LocalBridgeArtifactStore(appSupportURL: artifactRoot)
        let controller = LocalBridgeSyncController(
            trustStore: trustStore,
            identityStore: identityStore,
            snapshotExportService: exportService,
            importValidationService: validationService,
            importApplyService: importApplyService,
            artifactStore: artifactStore,
            workspaceStore: LocalBridgeTransientWorkspaceStore(appSupportURL: artifactRoot)
        )

        let baseSnapshot = try exportService.exportAuthoritativeSnapshot()
        let editedSnapshot = try makePhase2BridgeEditedSnapshot(from: baseSnapshot)
        let package = try makePhase2BridgeSignedPackage(
            from: editedSnapshot,
            baseDatasetFingerprint: baseSnapshot.manifest.baseDatasetFingerprint,
            trustedDevice: trustedDevice,
            signingService: signingService
        )
        let packageURL = artifactRoot.appendingPathComponent("bridge-import-reject.json")
        try package.canonicalEncodingData().write(to: packageURL, options: .atomic)

        controller.loadImportPackage(from: packageURL)
        #expect(controller.pendingAction == .reviewImport)
        #expect(controller.importReviewStatus.requiresOperatorReview)

        controller.markImportDecision(.rejected)

        #expect(controller.importReviewStatus.operatorDecision == .rejected)
        #expect(controller.importReviewStatus.requiresOperatorReview == false)
        #expect(controller.pendingAction == .syncNow)
        #expect(controller.lastSyncOutcome == .cancelled)
        #expect(controller.sessionState.transportState == .importCancelledByUser)
        #expect(controller.operatorMessage?.contains("rejected by operator") == true)
    }

    @Test("Revoking trust invalidates the loaded import package from that device")
    func revokeTrustInvalidatesLoadedPackage() throws {
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
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        let artifactStore = LocalBridgeArtifactStore(appSupportURL: artifactRoot)
        let controller = LocalBridgeSyncController(
            trustStore: trustStore,
            identityStore: identityStore,
            snapshotExportService: exportService,
            importValidationService: validationService,
            importApplyService: importApplyService,
            artifactStore: artifactStore,
            workspaceStore: LocalBridgeTransientWorkspaceStore(appSupportURL: artifactRoot)
        )

        let baseSnapshot = try exportService.exportAuthoritativeSnapshot()
        let editedSnapshot = try makePhase2BridgeEditedSnapshot(from: baseSnapshot)
        let package = try makePhase2BridgeSignedPackage(
            from: editedSnapshot,
            baseDatasetFingerprint: baseSnapshot.manifest.baseDatasetFingerprint,
            trustedDevice: trustedDevice,
            signingService: signingService
        )
        let packageURL = artifactRoot.appendingPathComponent("bridge-import-revoke.json")
        try package.canonicalEncodingData().write(to: packageURL, options: .atomic)

        controller.loadImportPackage(from: packageURL)
        #expect(controller.latestImportArtifact != nil)
        #expect(controller.hasLoadedImportPackage)

        controller.revokeTrust(deviceID: trustedDevice.id)

        #expect(controller.latestImportArtifact == nil)
        #expect(controller.hasLoadedImportPackage == false)
        #expect(controller.pendingAction == .trustRevoked)
        #expect(controller.sessionState.transportState == .trustRevoked)
    }

    @Test("Drifted package is rejected before import review opens")
    func driftedPackageRejectedBeforeReview() throws {
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
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        let artifactStore = LocalBridgeArtifactStore(appSupportURL: artifactRoot)
        let controller = LocalBridgeSyncController(
            trustStore: trustStore,
            identityStore: identityStore,
            snapshotExportService: exportService,
            importValidationService: validationService,
            importApplyService: importApplyService,
            artifactStore: artifactStore,
            workspaceStore: LocalBridgeTransientWorkspaceStore(appSupportURL: artifactRoot)
        )

        let baseSnapshot = try exportService.exportAuthoritativeSnapshot()
        let editedSnapshot = try makePhase2BridgeEditedSnapshot(from: baseSnapshot)
        let staleBaseFingerprint = "stale-\(baseSnapshot.manifest.baseDatasetFingerprint)"
        let package = try makePhase2BridgeSignedPackage(
            from: editedSnapshot,
            baseDatasetFingerprint: staleBaseFingerprint,
            trustedDevice: trustedDevice,
            signingService: signingService
        )
        let packageURL = artifactRoot.appendingPathComponent("bridge-import-drift.json")
        try package.canonicalEncodingData().write(to: packageURL, options: .atomic)

        controller.loadImportPackage(from: packageURL)

        #expect(controller.importReviewStatus.requiresOperatorReview == false)
        #expect(controller.importReviewStatus.driftStatus == .conflicting)
        #expect(controller.pendingAction == .syncNow)
        #expect(controller.sessionState.transportState == .importRejectedDueToDrift)
        #expect(controller.operatorMessage?.contains("rejected before review") == true)
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

    @Test("Package ID is derived from the canonical package body")
    func packageIdMatchesCanonicalPackageBodyHash() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        _ = try TestDataFactory.createFullCutoverTestData(in: context)

        let signingService = TestBridgeSigningService()
        let trustedDevice = signingService.makeTrustedDevice(displayName: "Bridge Mac")
        let exportService = LocalBridgeSnapshotExportService()

        let snapshot = try exportService.exportSnapshot(from: context)
        let package = try makeSignedPackage(
            from: snapshot,
            baseDatasetFingerprint: snapshot.manifest.baseDatasetFingerprint,
            trustedDevice: trustedDevice,
            signingService: signingService
        )

        let expectedPackageID = BudgetSnapshotIdentity.sha256(String(decoding: try package.canonicalPackageBodyData(), as: UTF8.self))
        #expect(package.packageID == expectedPackageID)
        let signingPayload = String(decoding: try package.signingPayloadData(), as: UTF8.self)
        #expect(signingPayload.contains("\"packageID\""))
        #expect(signingPayload.contains("\"signature\":null"))
    }

    @Test("Deleted snapshot rows remove only uniquely matched authoritative entities")
    func deletedGoalSnapshotRemovesOnlyMatchedGoal() throws {
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
        guard let deletedGoal = baseSnapshot.goals.first else {
            throw NSError(domain: "LocalBridgeImportApplyServiceTests", code: 3)
        }
        let deletedSnapshot = BridgeGoalSnapshot(
            id: deletedGoal.id,
            recordState: .deleted,
            name: deletedGoal.name,
            currency: deletedGoal.currency,
            targetAmount: deletedGoal.targetAmount,
            deadline: deletedGoal.deadline,
            startDate: deletedGoal.startDate,
            lifecycleStatusRawValue: deletedGoal.lifecycleStatusRawValue,
            emoji: deletedGoal.emoji,
            goalDescription: deletedGoal.goalDescription,
            link: deletedGoal.link
        )
        let editedSnapshot = try SnapshotEnvelope(
            manifest: SnapshotManifest(
                snapshotID: baseSnapshot.manifest.snapshotID,
                canonicalEncodingVersion: baseSnapshot.manifest.canonicalEncodingVersion,
                snapshotSchemaVersion: baseSnapshot.manifest.snapshotSchemaVersion,
                exportedAt: baseSnapshot.manifest.exportedAt,
                appModelSchemaVersion: baseSnapshot.manifest.appModelSchemaVersion,
                entityCounts: baseSnapshot.manifest.entityCounts,
                baseDatasetFingerprint: ""
            ),
            goals: [deletedSnapshot] + baseSnapshot.goals.dropFirst(),
            assets: baseSnapshot.assets,
            transactions: baseSnapshot.transactions,
            assetAllocations: baseSnapshot.assetAllocations,
            allocationHistories: baseSnapshot.allocationHistories,
            monthlyPlans: baseSnapshot.monthlyPlans,
            monthlyExecutionRecords: baseSnapshot.monthlyExecutionRecords,
            completedExecutions: baseSnapshot.completedExecutions,
            executionSnapshots: baseSnapshot.executionSnapshots,
            completionEvents: baseSnapshot.completionEvents
        ).withComputedFingerprint()
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
        #expect(finalSnapshot.goals.count == baseSnapshot.goals.count - 1)
        #expect(finalSnapshot.goals.contains(where: { $0.id == deletedGoal.id }) == false)
    }

    @Test("Omitted rows remain authoritative unless explicitly deleted")
    func omittedGoalSnapshotDoesNotDeleteAuthoritativeGoal() throws {
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
        let insertedGoalID = UUID()
        let insertedGoal = makeStandaloneGoalSnapshot(id: insertedGoalID, name: "Bridge Omitted Goal")
        let augmentedSnapshot = try makeSnapshot(
            from: baseSnapshot,
            goals: baseSnapshot.goals + [insertedGoal]
        )
        let insertedPackage = try makeSignedPackage(
            from: augmentedSnapshot,
            baseDatasetFingerprint: baseSnapshot.manifest.baseDatasetFingerprint,
            trustedDevice: trustedDevice,
            signingService: signingService
        )
        let insertedReview = try validationService.review(
            package: insertedPackage,
            trustedDevice: trustedDevice,
            currentSnapshot: baseSnapshot
        )

        _ = try applyService.applyReviewedPackage(
            insertedPackage,
            trustedDevice: trustedDevice,
            reviewStatus: approved(insertedReview),
            in: container
        )

        let expandedSnapshot = try exportService.exportSnapshot(from: ModelContext(container))
        #expect(expandedSnapshot.goals.contains(where: { $0.id == insertedGoalID }))

        let omittedGoals = expandedSnapshot.goals.filter { $0.id != insertedGoalID }
        let omittedSnapshot = try makeSnapshot(
            from: expandedSnapshot,
            goals: omittedGoals
        )
        let omittedPackage = try makeSignedPackage(
            from: omittedSnapshot,
            baseDatasetFingerprint: expandedSnapshot.manifest.baseDatasetFingerprint,
            trustedDevice: trustedDevice,
            signingService: signingService
        )
        let omittedReview = try validationService.review(
            package: omittedPackage,
            trustedDevice: trustedDevice,
            currentSnapshot: expandedSnapshot
        )

        _ = try applyService.applyReviewedPackage(
            omittedPackage,
            trustedDevice: trustedDevice,
            reviewStatus: approved(omittedReview),
            in: container
        )

        let finalSnapshot = try exportService.exportSnapshot(from: ModelContext(container))
        #expect(finalSnapshot.goals.contains(where: { $0.id == insertedGoalID }))
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
                BridgeEntityCount(name: "MonthlyExecutionRecord", count: baseSnapshot.monthlyExecutionRecords.count),
                BridgeEntityCount(name: "CompletedExecution", count: baseSnapshot.completedExecutions.count),
                BridgeEntityCount(name: "ExecutionSnapshot", count: baseSnapshot.executionSnapshots.count),
                BridgeEntityCount(name: "CompletionEvent", count: baseSnapshot.completionEvents.count)
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
            monthlyExecutionRecords: baseSnapshot.monthlyExecutionRecords,
            completedExecutions: baseSnapshot.completedExecutions,
            executionSnapshots: baseSnapshot.executionSnapshots,
            completionEvents: baseSnapshot.completionEvents
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
                    recordState: .active,
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
                recordState: .active,
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
                recordState: .active,
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
                recordState: .active,
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

    private func makeSnapshot(
        from baseSnapshot: SnapshotEnvelope,
        goals: [BridgeGoalSnapshot]
    ) throws -> SnapshotEnvelope {
        let manifest = SnapshotManifest(
            snapshotID: baseSnapshot.manifest.snapshotID,
            canonicalEncodingVersion: baseSnapshot.manifest.canonicalEncodingVersion,
            snapshotSchemaVersion: baseSnapshot.manifest.snapshotSchemaVersion,
            exportedAt: baseSnapshot.manifest.exportedAt,
            appModelSchemaVersion: baseSnapshot.manifest.appModelSchemaVersion,
            entityCounts: [
                BridgeEntityCount(name: "Goal", count: goals.count),
                BridgeEntityCount(name: "Asset", count: baseSnapshot.assets.count),
                BridgeEntityCount(name: "Transaction", count: baseSnapshot.transactions.count),
                BridgeEntityCount(name: "AssetAllocation", count: baseSnapshot.assetAllocations.count),
                BridgeEntityCount(name: "AllocationHistory", count: baseSnapshot.allocationHistories.count),
                BridgeEntityCount(name: "MonthlyPlan", count: baseSnapshot.monthlyPlans.count),
                BridgeEntityCount(name: "MonthlyExecutionRecord", count: baseSnapshot.monthlyExecutionRecords.count),
                BridgeEntityCount(name: "CompletedExecution", count: baseSnapshot.completedExecutions.count),
                BridgeEntityCount(name: "ExecutionSnapshot", count: baseSnapshot.executionSnapshots.count),
                BridgeEntityCount(name: "CompletionEvent", count: baseSnapshot.completionEvents.count)
            ],
            baseDatasetFingerprint: ""
        )

        return try SnapshotEnvelope(
            manifest: manifest,
            goals: goals,
            assets: baseSnapshot.assets,
            transactions: baseSnapshot.transactions,
            assetAllocations: baseSnapshot.assetAllocations,
            allocationHistories: baseSnapshot.allocationHistories,
            monthlyPlans: baseSnapshot.monthlyPlans,
            monthlyExecutionRecords: baseSnapshot.monthlyExecutionRecords,
            completedExecutions: baseSnapshot.completedExecutions,
            executionSnapshots: baseSnapshot.executionSnapshots,
            completionEvents: baseSnapshot.completionEvents
        ).withComputedFingerprint()
    }

    private func makeStandaloneGoalSnapshot(id: UUID, name: String) -> BridgeGoalSnapshot {
        BridgeGoalSnapshot(
            id: id,
            recordState: .active,
            name: name,
            currency: "USD",
            targetAmount: 42.0,
            deadline: Date(timeIntervalSince1970: 1_900_000_000),
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            lifecycleStatusRawValue: GoalLifecycleStatus.active.rawValue,
            emoji: "🧭",
            goalDescription: "Standalone bridge omission test goal",
            link: nil
        )
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
            packageID: "",
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
        let packageID = BudgetSnapshotIdentity.sha256(String(decoding: try unsignedPackage.canonicalPackageBodyData(), as: UTF8.self))
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
        let signature = try signingService.sign(bodyPackage.signingPayloadData(), keyID: signingKeyID)

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
