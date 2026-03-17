//
//  FamilyShareAcceptanceCoordinatorTests.swift
//  CryptoSavingsTrackerTests
//

import XCTest
import CloudKit
@testable import CryptoSavingsTracker

@MainActor
final class FamilyShareAcceptanceCoordinatorTests: XCTestCase {
    private func makeCoordinator(cloudSync: FamilyShareCloudSyncing? = nil) -> FamilyShareAcceptanceCoordinator {
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let stateProvider = DefaultFamilyShareStateProvider(registry: registry)
        let publisher = DefaultFamilyShareProjectionPublisher(registry: registry, cloudSync: cloudSync)
        let ownerSharingService = DefaultFamilyShareOwnerSharingService(
            registry: registry,
            stateProvider: stateProvider,
            publisher: publisher,
            cloudSync: cloudSync
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
            cloudSync: cloudSync
        )
    }

    func testShareAllGoalsPublishesOwnerStateAndPendingShareRequest() async {
        let coordinator = makeCoordinator()
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
    }

    func testSeedInviteeScenarioBuildsSharedGoalsSections() async {
        let coordinator = makeCoordinator()

        await coordinator.seedUITestScenario(.inviteeStale)

        XCTAssertEqual(coordinator.sharedSections.count, 1)
        XCTAssertEqual(coordinator.sharedSections.first?.state, .stale)
        XCTAssertEqual(coordinator.sharedSections.first?.primaryActionTitle, "Retry Refresh")
        XCTAssertEqual(coordinator.inviteeStates.first?.lifecycleState, .stale)
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
}

private final class StubFamilyShareCloudSync: FamilyShareCloudSyncing {
    let ownerSnapshot: FamilyShareOwnerShareSnapshot

    init(ownerSnapshot: FamilyShareOwnerShareSnapshot) {
        self.ownerSnapshot = ownerSnapshot
    }

    func publishProjection(_ payload: FamilyShareProjectionPayload) async throws {
    }

    func prepareShare(for request: FamilyShareCloudSharingPreparationRequest) async throws -> (share: CKShare, container: CKContainer) {
        throw NSError(domain: "StubFamilyShareCloudSync", code: 1)
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
