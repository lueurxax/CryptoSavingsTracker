//
//  FamilyShareAcceptanceCoordinatorTests.swift
//  CryptoSavingsTrackerTests
//

import XCTest
import CloudKit
@testable import CryptoSavingsTracker

@MainActor
final class FamilyShareAcceptanceCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        cloudSync: FamilyShareCloudSyncing? = nil,
        telemetry: FamilyShareTelemetryTracking = FamilyShareTelemetryTracker()
    ) -> FamilyShareAcceptanceCoordinator {
        let defaults = UserDefaults(suiteName: "FamilyShareAcceptanceCoordinatorTests.\(UUID().uuidString)")!
        defaults.set("test-owner", forKey: "familyShare.ownerID")
        defaults.set("test-share", forKey: "familyShare.shareID")
        defaults.set("Test Owner", forKey: "familyShare.ownerName")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let stateProvider = DefaultFamilyShareStateProvider(registry: registry)
        let publisher = DefaultFamilyShareProjectionPublisher(registry: registry, cloudSync: cloudSync, telemetry: telemetry)
        let identityStore = FamilyShareOwnerIdentityStore(userDefaults: defaults)
        let ownerSharingService = DefaultFamilyShareOwnerSharingService(
            registry: registry,
            stateProvider: stateProvider,
            publisher: publisher,
            cloudSync: cloudSync,
            telemetry: telemetry
        )
        let migrationCoordinator = FamilyShareCacheMigrationCoordinator(registry: registry)
        let publishCoordinator = FamilyShareProjectionPublishCoordinator(publisher: publisher)
        let seeder = FamilyShareTestSeeder(registry: registry)

        return FamilyShareAcceptanceCoordinator(
            registry: registry,
            stateProvider: stateProvider,
            inviteeStateProvider: stateProvider,
            ownerSharingService: ownerSharingService,
            cacheMigrationCoordinator: migrationCoordinator,
            publishCoordinator: publishCoordinator,
            seeder: seeder,
            identityStore: identityStore,
            cloudSync: cloudSync,
            telemetry: telemetry
        )
    }

    func testShareAllGoalsPublishesOwnerStateAndPendingShareRequest() async {
        let telemetry = RecordingFamilyShareTelemetryTracker()
        let ownerNamespaceID = FamilyShareNamespaceID(ownerID: "owner", shareID: "share")
        let coordinator = makeCoordinator(
            cloudSync: StubFamilyShareCloudSync(
                ownerSnapshot: FamilyShareOwnerShareSnapshot(
                    ownerState: FamilyShareOwnerViewState(
                        namespaceID: ownerNamespaceID,
                        lifecycleState: .sharedActive,
                        participantCount: 0,
                        pendingParticipantCount: 0,
                        activeParticipantCount: 0,
                        revokedParticipantCount: 0,
                        failedParticipantCount: 0,
                        summaryCopy: "Share all of your goals with family in read-only mode.",
                        primaryActionCopy: "Share with Family"
                    ),
                    participants: []
                )
            ),
            telemetry: telemetry
        )
        let goal = Goal(
            name: "School Fund",
            currency: "USD",
            targetAmount: 1_500,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )

        await coordinator.shareAllGoals([goal])

        XCTAssertEqual(coordinator.ownerState.lifecycleState, .sharedActive)
        XCTAssertNotNil(coordinator.pendingCloudSharingRequest)
        XCTAssertEqual(coordinator.pendingCloudSharingRequest?.namespaceID, coordinator.ownerNamespaceID)

        let familyAccessModel = coordinator.makeFamilyAccessModel(currentGoals: [goal])
        XCTAssertEqual(familyAccessModel.ownerSections.count, 1)
        XCTAssertEqual(familyAccessModel.ownerSections.first?.goals.count, 1)
        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.createStarted.rawValue))
        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.createSucceeded.rawValue))
    }

    func testShareAllGoalsTracksCreateFailureTelemetryWhenCloudSyncIsMissing() async {
        let telemetry = RecordingFamilyShareTelemetryTracker()
        let coordinator = makeCoordinator(telemetry: telemetry)
        let goal = Goal(
            name: "School Fund",
            currency: "USD",
            targetAmount: 1_500,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )

        await coordinator.shareAllGoals([goal])

        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.createStarted.rawValue))
        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.createFailed.rawValue))
    }

    func testSeedInviteeScenarioBuildsSharedGoalsSections() async {
        let coordinator = makeCoordinator()

        await coordinator.seedUITestScenario(.inviteeStale)

        XCTAssertEqual(coordinator.sharedSections.count, 1)
        XCTAssertEqual(coordinator.sharedSections.first?.state, .stale)
        XCTAssertEqual(coordinator.sharedSections.first?.primaryActionTitle, "Retry Refresh")
        XCTAssertEqual(coordinator.inviteeStates.first?.lifecycleState, .stale)
    }

    func testSeedMultiOwnerScenarioBuildsGroupedSharedGoalsSections() async {
        let coordinator = makeCoordinator()

        await coordinator.seedUITestScenario(.inviteeMultiOwner)

        XCTAssertEqual(coordinator.sharedSections.count, 2)
        XCTAssertEqual(coordinator.sharedSections.map(\.ownerName), ["Family", "Jordan"])
        XCTAssertEqual(coordinator.sharedSections.first?.goals.count, 2)
        XCTAssertEqual(coordinator.sharedSections.last?.goals.count, 1)
    }

    func testResetAllNamespacesClearsPublishedFamilySharingState() async {
        let coordinator = makeCoordinator()
        await coordinator.seedUITestScenario(.inviteeActive)

        XCTAssertFalse(coordinator.sharedSections.isEmpty)

        await coordinator.resetAllNamespaces()

        XCTAssertTrue(coordinator.sharedSections.isEmpty)
        XCTAssertTrue(coordinator.inviteeStates.isEmpty)
        XCTAssertNil(coordinator.pendingCloudSharingRequest)
        XCTAssertEqual(coordinator.ownerState.lifecycleState, .notShared)
    }

    func testMissingRecordTypeErrorsAreTreatedAsBootstrapSafe() {
        let unknownItem = CKError(.unknownItem)
        XCTAssertTrue(DefaultFamilyShareCloudKitStore.isMissingRecordTypeError(unknownItem))

        let dashboardStyleError = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.serverRejectedRequest.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Did not find record type: FamilySharedGoalProjection"]
        )
        XCTAssertTrue(DefaultFamilyShareCloudKitStore.isMissingRecordTypeError(dashboardStyleError))

        let unrelatedError = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.networkUnavailable.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "The network is unavailable."]
        )
        XCTAssertFalse(DefaultFamilyShareCloudKitStore.isMissingRecordTypeError(unrelatedError))
    }

    func testOwnerFamilyAccessModelUsesLiveCloudKitParticipants() async {
        let ownerNamespaceID = FamilyShareNamespaceID(ownerID: "owner", shareID: "share")
        let cloudSync = StubFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: FamilyShareOwnerViewState(
                    namespaceID: ownerNamespaceID,
                    lifecycleState: .sharedActive,
                    participantCount: 1,
                    pendingParticipantCount: 0,
                    activeParticipantCount: 1,
                    revokedParticipantCount: 0,
                    failedParticipantCount: 0,
                    summaryCopy: "1 family member has active read-only access.",
                    primaryActionCopy: "Manage Participants"
                ),
                participants: [
                    FamilyShareParticipantSnapshot(
                        id: "marta@example.com",
                        displayName: "Marta",
                        emailOrAlias: "marta@example.com",
                        state: .active,
                        lastUpdatedAt: Date(),
                        isCurrentUser: false
                    )
                ]
            )
        )
        let coordinator = makeCoordinator(cloudSync: cloudSync)

        await coordinator.seedUITestScenario(.ownerSharedActive)
        let model = coordinator.makeFamilyAccessModel(currentGoals: [])

        XCTAssertEqual(model.participants.map(\.displayName), ["Marta"])
        XCTAssertEqual(model.participants.first?.state, .active)
        XCTAssertEqual(coordinator.settingsRowSummary(currentGoalCount: 1), "1 participant")
    }

    func testInviteeTelemetryTracksViewedStates() async {
        let telemetry = RecordingFamilyShareTelemetryTracker()
        let coordinator = makeCoordinator(telemetry: telemetry)

        await coordinator.seedUITestScenario(.inviteePending)
        await coordinator.seedUITestScenario(.inviteeActive)
        await coordinator.seedUITestScenario(.inviteeStale)
        await coordinator.seedUITestScenario(.inviteeEmpty)
        await coordinator.seedUITestScenario(.inviteeRevoked)
        await coordinator.seedUITestScenario(.inviteeRemoved)
        await coordinator.seedUITestScenario(.inviteeUnavailable)

        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.invitePendingViewed.rawValue))
        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.activeViewed.rawValue))
        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.refreshStale.rawValue))
        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.emptyViewed.rawValue))
        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.revokedViewed.rawValue))
        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.removedViewed.rawValue))
        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.temporarilyUnavailableViewed.rawValue))
    }

    func testTelemetryTrackerRedactsSensitiveIdentifiersAndReasons() {
        let provider = RecordingFamilyShareTelemetryProvider()
        let tracker = FamilyShareTelemetryTracker(provider: provider)
        let namespaceID = FamilyShareNamespaceID(ownerID: "owner@example.com", shareID: "share-123")

        tracker.track(
            .refreshFailed,
            payload: [
                "namespace": namespaceID.namespaceKey,
                "ownerID": namespaceID.ownerID,
                "shareID": namespaceID.shareID,
                "participant": "invitee@example.com",
                "reason": "The shared database is unavailable for this record type."
            ]
        )

        XCTAssertEqual(provider.records.count, 1)
        let record = provider.records[0]
        XCTAssertEqual(record.event, FamilyShareTelemetryEvent.refreshFailed.rawValue)
        XCTAssertNotEqual(record.payload["namespace"], namespaceID.namespaceKey)
        XCTAssertEqual(record.payload["ownerID"]?.count, 12)
        XCTAssertEqual(record.payload["shareID"]?.count, 12)
        XCTAssertEqual(record.payload["participant"]?.count, 12)
        XCTAssertEqual(record.payload["reason"], "shared_database_unavailable")
    }

    func testNamespaceExecutionHubTracksLatestStateAcrossTransitions() async {
        let namespaceID = FamilyShareNamespaceID(ownerID: "owner", shareID: "share")
        let hub = FamilyShareNamespaceExecutionHub()
        let seed = FamilyShareTestSeeder.makeSeed(for: .inviteeActive, namespaceID: namespaceID)

        await hub.bootstrap(with: seed)
        var snapshot = await hub.stateSnapshot(for: namespaceID)
        XCTAssertEqual(snapshot?.lifecycleState, .active)

        let quarantined = FamilyShareSeededNamespaceState(
            ownerDisplayName: seed.ownerDisplayName,
            ownerState: seed.ownerState,
            inviteeState: FamilyShareInviteeViewState(
                namespaceID: namespaceID,
                ownerDisplayName: seed.ownerDisplayName,
                lifecycleState: .temporarilyUnavailable,
                goalCount: 0,
                lastUpdatedAt: nil,
                asOfCopy: nil,
                titleCopy: "Shared Goals",
                messageCopy: "Temporarily unavailable.",
                primaryActionCopy: "Retry",
                isReadOnly: true
            ),
            projectionPayload: nil
        )

        await hub.markFailed(with: quarantined, reason: "quarantined")
        snapshot = await hub.stateSnapshot(for: namespaceID)
        XCTAssertEqual(snapshot?.lifecycleState, .temporarilyUnavailable)

        await hub.markRevoked(with: quarantined)
        snapshot = await hub.stateSnapshot(for: namespaceID)
        XCTAssertEqual(snapshot?.lifecycleState, .revoked)
    }

    func testMigrationCoordinatorQuarantinesFutureSchemaVersions() async throws {
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let migrationCoordinator = FamilyShareCacheMigrationCoordinator(registry: registry)
        let namespaceID = FamilyShareNamespaceID(ownerID: "owner", shareID: "share")
        let seed = FamilyShareSeededNamespaceState(
            ownerDisplayName: "Owner",
            ownerState: FamilyShareOwnerViewState(
                namespaceID: namespaceID,
                lifecycleState: .sharedActive,
                participantCount: 1,
                pendingParticipantCount: 0,
                activeParticipantCount: 1,
                revokedParticipantCount: 0,
                failedParticipantCount: 0,
                summaryCopy: "Shared.",
                primaryActionCopy: "Manage Participants"
            ),
            inviteeState: FamilyShareInviteeViewState(
                namespaceID: namespaceID,
                ownerDisplayName: "Owner",
                lifecycleState: .active,
                goalCount: 1,
                lastUpdatedAt: Date(),
                asOfCopy: nil,
                titleCopy: "Shared Goals",
                messageCopy: "Shared.",
                primaryActionCopy: "Retry Refresh",
                isReadOnly: true
            ),
            projectionPayload: FamilyShareProjectionPayload(
                namespaceID: namespaceID,
                ownerDisplayName: "Owner",
                schemaVersion: FamilyShareCacheSchema.currentVersion + 1,
                projectionVersion: 1,
                activeProjectionVersion: 1,
                freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
                lifecycleStateRawValue: FamilyShareOwnerLifecycleState.sharedActive.rawValue,
                publishedAt: Date(),
                lastReconciledAt: Date(),
                lastRefreshAttemptAt: Date(),
                lastRefreshErrorCode: nil,
                lastRefreshErrorMessage: nil,
                summaryTitle: "Shared Goals",
                summaryCopy: "Shared.",
                participantCount: 1,
                pendingParticipantCount: 0,
                revokedParticipantCount: 0,
                goals: [],
                ownerSections: []
            )
        )

        try registry.seed(seed)
        let result = try await migrationCoordinator.ensureCompatible(namespaceID: namespaceID)

        XCTAssertTrue(result.quarantined)
        XCTAssertTrue(result.requiresRebuild)
        XCTAssertFalse(result.didMigrate)
    }

    func testRootRecordLocatorStorePersistsSharedZoneLocator() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = FamilyShareRootRecordLocatorStore(userDefaults: defaults)
        let namespaceID = FamilyShareNamespaceID(ownerID: "owner-1", shareID: "share-1")
        let recordID = CKRecord.ID(
            recordName: "family-share.owner-1.share-1.root",
            zoneID: CKRecordZone.ID(zoneName: "shared-zone", ownerName: "owner-record-name")
        )

        await store.save(recordID: recordID, for: namespaceID)
        let locator = await store.locator(for: namespaceID)

        XCTAssertEqual(locator?.recordName, recordID.recordName)
        XCTAssertEqual(locator?.zoneName, recordID.zoneID.zoneName)
        XCTAssertEqual(locator?.zoneOwnerName, recordID.zoneID.ownerName)

        await store.remove(for: namespaceID)
        let clearedLocator = await store.locator(for: namespaceID)
        XCTAssertNil(clearedLocator)
    }
}

private final class StubFamilyShareCloudSync: FamilyShareCloudSyncing {
    let ownerSnapshot: FamilyShareOwnerShareSnapshot

    init(ownerSnapshot: FamilyShareOwnerShareSnapshot) {
        self.ownerSnapshot = ownerSnapshot
    }

    func publishProjection(_ payload: FamilyShareProjectionPayload) async throws {
    }

    func prepareShare(for request: FamilyShareCloudSharingPreparationRequest) async throws -> (share: CKShare, container: CKContainer) {
        let zoneID = CKRecordZone.ID(zoneName: "stub-zone", ownerName: CKCurrentUserDefaultName)
        let rootRecord = CKRecord(recordType: "FamilyShareProjectionRoot", recordID: CKRecord.ID(recordName: "stub-root", zoneID: zoneID))
        let share = CKShare(rootRecord: rootRecord, shareID: CKRecord.ID(recordName: "stub-share", zoneID: zoneID))
        return (share, CKContainer.default())
    }

    func acceptInvitation(metadata: CKShare.Metadata) async throws -> FamilyShareInvitationMetadataSnapshot {
        FamilyShareInvitationMetadataSnapshot(metadata: metadata)
    }

    func ownerShareSnapshot(namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareOwnerShareSnapshot {
        ownerSnapshot
    }

    func fetchAcceptedProjection(from snapshot: FamilyShareInvitationMetadataSnapshot) async throws -> FamilyShareSeededNamespaceState {
        throw NSError(domain: "StubFamilyShareCloudSync", code: 2)
    }

    func refreshProjection(namespaceID: FamilyShareNamespaceID) async throws -> FamilyShareSeededNamespaceState {
        throw NSError(domain: "StubFamilyShareCloudSync", code: 3)
    }

    func revoke(namespaceID: FamilyShareNamespaceID) async throws {
    }
}

private final class RecordingFamilyShareTelemetryTracker: FamilyShareTelemetryTracking {
    private(set) var events: [String] = []

    func track(_ event: FamilyShareTelemetryEvent, payload: [String : String] = [:]) {
        events.append(event.rawValue)
    }
}

private final class RecordingFamilyShareTelemetryProvider: FamilyShareTelemetryProviding {
    struct Record {
        let event: String
        let payload: [String: String]
    }

    private(set) var records: [Record] = []

    func track(event: String, payload: [String : String]) {
        records.append(Record(event: event, payload: payload))
    }
}
