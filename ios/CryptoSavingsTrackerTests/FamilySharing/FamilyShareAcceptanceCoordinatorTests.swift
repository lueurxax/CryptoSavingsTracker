//
//  FamilyShareAcceptanceCoordinatorTests.swift
//  CryptoSavingsTrackerTests
//

import XCTest
import CloudKit
@testable import CryptoSavingsTracker

@MainActor
final class FamilyShareAcceptanceCoordinatorTests: XCTestCase {
    private func makeCoordinator() -> FamilyShareAcceptanceCoordinator {
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let stateProvider = DefaultFamilyShareStateProvider(registry: registry)
        let publisher = DefaultFamilyShareProjectionPublisher(registry: registry)
        let ownerSharingService = DefaultFamilyShareOwnerSharingService(
            registry: registry,
            stateProvider: stateProvider,
            publisher: publisher
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
            seeder: seeder
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
}
