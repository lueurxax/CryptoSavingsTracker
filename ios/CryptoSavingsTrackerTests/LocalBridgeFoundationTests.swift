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
        #expect(manifest.minimumSupportedCanonicalEncodingVersion == "bridge-snapshot-v2")
        #expect(manifest.maximumSupportedCanonicalEncodingVersion == "bridge-snapshot-v2")
        #expect(manifest.minimumSupportedSnapshotSchemaVersion == 1)
        #expect(manifest.maximumSupportedSnapshotSchemaVersion == 2)
        #expect(manifest.appModelSchemaVersion == "cloudkit-model-v2")
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

        #expect(decoded.pairingID == token.pairingID)
        #expect(decoded.deviceName == token.deviceName)
        #expect(decoded.oneTimeSecretReference == token.oneTimeSecretReference)
        #expect(decoded.ephemeralPublicKey == token.ephemeralPublicKey)
        #expect(decoded.signingKeyID == token.signingKeyID)
        #expect(decoded.publicKeyRepresentation == token.publicKeyRepresentation)
        #expect(decoded.signingAlgorithm == token.signingAlgorithm)
        #expect(decoded.fingerprint == token.fingerprint)
        #expect(abs(decoded.expiresAt.timeIntervalSince(token.expiresAt)) < 0.001)
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

    @Test("snapshot export preserves retained and released completion payloads")
    func snapshotExportPreservesCompletionPayloads() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let retainedGoal = Goal(
            name: "Retained Bridge Goal",
            currency: "USD",
            targetAmount: 120,
            deadline: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let releasedGoal = Goal(
            name: "Released Bridge Goal",
            currency: "USDT",
            targetAmount: 80,
            deadline: Date(timeIntervalSince1970: 1_900_000_100)
        )
        retainedGoal.lifecycleStatus = .finished
        releasedGoal.lifecycleStatus = .finished
        let retainedPayload = try completionSnapshotData(
            for: retainedGoal,
            settlement: .keepAsSpent
        )
        let releasedPayload = try completionSnapshotData(
            for: releasedGoal,
            settlement: .balanceAlreadyDecreased
        )
        retainedGoal.completionSnapshotData = retainedPayload
        releasedGoal.completionSnapshotData = releasedPayload
        context.insert(retainedGoal)
        context.insert(releasedGoal)
        try context.save()

        let snapshot = try LocalBridgeSnapshotExportService().exportSnapshot(from: context)
        let goalsByID = Dictionary(uniqueKeysWithValues: snapshot.goals.map { ($0.id, $0) })

        #expect(snapshot.manifest.snapshotSchemaVersion == 2)
        #expect(goalsByID[retainedGoal.id]?.completionSnapshotData == retainedPayload)
        #expect(goalsByID[releasedGoal.id]?.completionSnapshotData == releasedPayload)
    }

    @Test("completion payload mutation changes the canonical dataset fingerprint")
    func completionPayloadParticipatesInCanonicalFingerprint() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = Goal(
            name: "Canonical Bridge Goal",
            currency: "USDT",
            targetAmount: 35,
            deadline: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let retainedPayload = try completionSnapshotData(for: goal, settlement: .keepAsSpent)
        goal.completionSnapshotData = retainedPayload
        context.insert(goal)
        try context.save()
        let snapshot = try LocalBridgeSnapshotExportService().exportSnapshot(from: context)
        let originalGoal = try #require(snapshot.goals.first { $0.id == goal.id })
        let releasedPayload = try completionSnapshotData(
            for: goal,
            settlement: .balanceAlreadyDecreased
        )
        let mutatedGoal = BridgeGoalSnapshot(
            id: originalGoal.id,
            recordState: originalGoal.recordState,
            name: originalGoal.name,
            currency: originalGoal.currency,
            targetAmount: originalGoal.targetAmount,
            deadline: originalGoal.deadline,
            startDate: originalGoal.startDate,
            lifecycleStatusRawValue: originalGoal.lifecycleStatusRawValue,
            emoji: originalGoal.emoji,
            goalDescription: originalGoal.goalDescription,
            link: originalGoal.link,
            completionSnapshotData: releasedPayload
        )
        let mutatedSnapshot = SnapshotEnvelope(
            manifest: snapshot.manifest,
            goals: snapshot.goals.map { $0.id == goal.id ? mutatedGoal : $0 },
            assets: snapshot.assets,
            transactions: snapshot.transactions,
            assetAllocations: snapshot.assetAllocations,
            allocationHistories: snapshot.allocationHistories,
            monthlyPlans: snapshot.monthlyPlans,
            monthlyExecutionRecords: snapshot.monthlyExecutionRecords,
            completedExecutions: snapshot.completedExecutions,
            executionSnapshots: snapshot.executionSnapshots,
            completionEvents: snapshot.completionEvents
        )
        let canonical = String(decoding: try snapshot.canonicalEncodingData(), as: UTF8.self)

        #expect(canonical.contains(retainedPayload.base64EncodedString()))
        #expect(try snapshot.computedDatasetFingerprint() != mutatedSnapshot.computedDatasetFingerprint())
    }

    @Test("schema v1 goal without completion payload decodes as nil with legacy canonical shape")
    func schemaV1MissingCompletionPayloadIsBackwardReadable() throws {
        let goal = BridgeGoalSnapshot(
            id: UUID(),
            name: "Legacy Bridge Goal",
            currency: "USD",
            targetAmount: 42,
            deadline: Date(timeIntervalSince1970: 1_900_000_000),
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            lifecycleStatusRawValue: GoalLifecycleStatus.finished.rawValue,
            emoji: nil,
            goalDescription: nil,
            link: nil,
            completionSnapshotData: nil
        )
        let envelope = SnapshotEnvelope(
            manifest: SnapshotManifest(
                snapshotID: UUID(),
                canonicalEncodingVersion: "bridge-snapshot-v1",
                snapshotSchemaVersion: 1,
                exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
                appModelSchemaVersion: "cloudkit-model-v1",
                entityCounts: [BridgeEntityCount(name: "Goal", count: 1)],
                baseDatasetFingerprint: ""
            ),
            goals: [goal],
            assets: [],
            transactions: [],
            assetAllocations: [],
            allocationHistories: [],
            monthlyPlans: [],
            monthlyExecutionRecords: []
        )
        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(SnapshotEnvelope.self, from: encoded)
        let canonical = String(decoding: try decoded.canonicalEncodingData(), as: UTF8.self)

        #expect(try #require(decoded.goals.first).completionSnapshotData == nil)
        #expect(canonical.contains("completionSnapshotData") == false)
    }

    private func completionSnapshotData(
        for goal: Goal,
        settlement: FinishedAllocationSettlement
    ) throws -> Data {
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return try GoalCompletionSnapshotCodec.encode(
            GoalCompletionSnapshot(
                id: UUID(),
                schemaVersion: GoalCompletionSnapshot.currentSchemaVersion,
                goalID: goal.id,
                goalName: goal.name,
                goalCurrency: goal.currency,
                goalTargetAmount: goal.targetAmount,
                goalCompletedAt: completedAt,
                snapshotCreatedAt: completedAt,
                entries: [
                    GoalCompletionSnapshot.Entry(
                        allocationID: UUID(),
                        assetID: UUID(),
                        assetCurrency: goal.currency,
                        amount: goal.targetAmount,
                        accountingMode: settlement == .keepAsSpent ? .manual : .onChain,
                        settlement: settlement,
                        bestKnownBalance: goal.targetAmount,
                        balanceCapturedAt: completedAt,
                        balanceTiming: .completionTime
                    )
                ]
            )
        )
    }

    @Test("Snapshot export preserves transaction-linked allocation provenance")
    func snapshotExportPreservesAllocationProvenance() throws {
        let fixture = try makeAllocationProvenanceFixture()

        let snapshot = try LocalBridgeSnapshotExportService()
            .exportSnapshot(from: ModelContext(fixture.container))
        let history = try #require(snapshot.allocationHistories.first(where: { $0.id == fixture.historyID }))

        #expect(history.sourceTransactionId == fixture.transactionID)
        #expect(history.sourcePreviousAmount == 12.5)
    }

    @Test("Canonical allocation history encodes provenance as explicit ordered fields")
    func canonicalAllocationHistoryEncodesProvenance() throws {
        let fixture = try makeAllocationProvenanceFixture()
        let snapshot = try LocalBridgeSnapshotExportService()
            .exportSnapshot(from: ModelContext(fixture.container))

        let canonical = String(
            decoding: try snapshot.canonicalEncodingData(forFingerprinting: false),
            as: UTF8.self
        )
        let historyStart = try (#require(canonical.range(of: "\"allocationHistories\":[{"))).upperBound
        let historyTail = String(canonical[historyStart...])
        let historyEnd = try #require(historyTail.firstIndex(of: "}"))
        let historyObject = String(historyTail[..<historyEnd]) as NSString
        let previousRange = historyObject.range(of: "\"sourcePreviousAmount\":\"12.5\"")
        let transactionRange = historyObject.range(
            of: "\"sourceTransactionId\":\"00000000-0000-0000-0000-000000000042\""
        )
        let timestampRange = historyObject.range(of: "\"timestamp\":")

        #expect(previousRange.location != NSNotFound)
        #expect(transactionRange.location != NSNotFound)
        #expect(timestampRange.location != NSNotFound)
        #expect(previousRange.location < transactionRange.location)
        #expect(transactionRange.location < timestampRange.location)
    }

    @Test("Canonical workspace round-trip preserves allocation provenance")
    func canonicalWorkspaceRoundTripPreservesAllocationProvenance() throws {
        let fixture = try makeAllocationProvenanceFixture()
        let snapshot = try LocalBridgeSnapshotExportService()
            .exportSnapshot(from: ModelContext(fixture.container))
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bridge-provenance-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = LocalBridgeTransientWorkspaceStore(appSupportURL: rootURL)

        _ = try store.save(
            snapshot,
            workspaceID: UUID(uuidString: "00000000-0000-0000-0000-000000000099"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try store.load().snapshot
        let history = try #require(decoded.allocationHistories.first(where: { $0.id == fixture.historyID }))

        #expect(history.sourceTransactionId == fixture.transactionID)
        #expect(history.sourcePreviousAmount == 12.5)
    }

    @Test("Snapshot export rejects a previous allocation amount without a source transaction")
    func snapshotExportRejectsPreviousAmountWithoutSourceTransaction() throws {
        let fixture = try makeAllocationProvenanceFixture()
        fixture.history.sourceTransactionId = nil
        try fixture.context.save()

        try expectProvenanceExportFailure(
            fixture.container,
            containing: "has sourcePreviousAmount without sourceTransactionId"
        )
    }

    @Test("Snapshot export rejects negative and non-finite previous allocation amounts")
    func snapshotExportRejectsInvalidPreviousAmounts() throws {
        for invalidAmount in [-0.01, Double.infinity] {
            let fixture = try makeAllocationProvenanceFixture()
            fixture.history.sourcePreviousAmount = invalidAmount
            try fixture.context.save()

            try expectProvenanceExportFailure(
                fixture.container,
                containing: "has invalid sourcePreviousAmount"
            )
        }
    }

    @Test("Snapshot export rejects a missing provenance transaction")
    func snapshotExportRejectsMissingProvenanceTransaction() throws {
        let fixture = try makeAllocationProvenanceFixture()
        fixture.history.sourceTransactionId = UUID(
            uuidString: "00000000-0000-0000-0000-000000000777"
        )
        try fixture.context.save()

        try expectProvenanceExportFailure(
            fixture.container,
            containing: "references missing source transaction"
        )
    }

    @Test("Snapshot export rejects provenance linked to a transaction from another asset")
    func snapshotExportRejectsCrossAssetProvenanceTransaction() throws {
        let fixture = try makeAllocationProvenanceFixture()
        let context = fixture.context
        let otherAsset = Asset(currency: "ETH")
        otherAsset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
        let otherTransaction = Transaction(
            amount: 3,
            asset: otherAsset,
            date: Date(timeIntervalSince1970: 1_700_000_020)
        )
        otherTransaction.id = UUID(uuidString: "00000000-0000-0000-0000-000000000043")!
        context.insert(otherAsset)
        context.insert(otherTransaction)
        fixture.history.sourceTransactionId = otherTransaction.id
        try context.save()

        try expectProvenanceExportFailure(
            fixture.container,
            containing: "references a source transaction from another asset"
        )
    }

    private func makeAllocationProvenanceFixture() throws -> (
        container: ModelContainer,
        context: ModelContext,
        transactionID: UUID,
        historyID: UUID,
        history: AllocationHistory
    ) {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = Goal(
            name: "Bridge provenance",
            currency: "USD",
            targetAmount: 100,
            deadline: Date(timeIntervalSince1970: 1_900_000_000)
        )
        goal.id = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let asset = Asset(currency: "USD")
        asset.id = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        let transactionID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        let transaction = Transaction(
            amount: 7.5,
            asset: asset,
            date: Date(timeIntervalSince1970: 1_700_000_010)
        )
        transaction.id = transactionID
        let history = AllocationHistory(
            asset: asset,
            goal: goal,
            amount: 20,
            timestamp: Date(timeIntervalSince1970: 1_700_000_010),
            sourceTransactionId: transactionID,
            sourcePreviousAmount: 12.5
        )
        let historyID = UUID(uuidString: "00000000-0000-0000-0000-000000000044")!
        history.id = historyID
        history.createdAt = Date(timeIntervalSince1970: 1_700_000_011)
        history.monthLabel = "2023-11"
        context.insert(goal)
        context.insert(asset)
        context.insert(transaction)
        context.insert(history)
        try context.save()
        return (container, context, transactionID, historyID, history)
    }

    private func expectProvenanceExportFailure(
        _ container: ModelContainer,
        containing expectedIssue: String
    ) throws {
        do {
            _ = try LocalBridgeSnapshotExportService()
                .exportSnapshot(from: ModelContext(container))
            Issue.record("Expected Local Bridge provenance validation to reject the export.")
        } catch let error as LocalBridgeSnapshotExportError {
            guard case let .invalidAuthoritativeDataset(issues) = error else {
                Issue.record("Expected invalidAuthoritativeDataset, got \(error).")
                return
            }
            #expect(issues.contains(where: { $0.contains(expectedIssue) }))
        }
    }
}
