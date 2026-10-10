//
//  FamilyShareAcceptanceCoordinatorTests.swift
//  CryptoSavingsTrackerTests
//

import XCTest
import CloudKit
import SwiftData
import SwiftUI
@testable import CryptoSavingsTracker

@MainActor
final class FamilyShareAcceptanceCoordinatorTests: XCTestCase {
    private func flushAsyncWork(iterations: Int = 20) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    private func makeCoordinator(
        cloudSync: FamilyShareCloudSyncing? = nil,
        telemetry: FamilyShareTelemetryTracking = FamilyShareTelemetryTracker(),
        activeGoalsProvider: @escaping () throws -> [Goal] = { [] },
        exchangeRateService: ExchangeRateServiceProtocol? = nil,
        initialSeed: FamilyShareSeededNamespaceState? = nil,
        registry providedRegistry: FamilyShareNamespaceRegistry? = nil,
        revocationTombstoneStore: FamilyShareRevocationTombstoneStore = FamilyShareRevocationTombstoneStore(),
        revocationRetryScheduler: any FamilyShareScheduler = GCDScheduler(),
        autoRepublishScheduler: any FamilyShareScheduler = GCDScheduler(),
        autoRepublishDirtyStateStore: FamilyShareDirtyStateStore = FamilyShareDirtyStateStore(),
        startsInitialRefreshTask: Bool = true
    ) -> FamilyShareAcceptanceCoordinator {
        let defaults = UserDefaults(suiteName: "FamilyShareAcceptanceCoordinatorTests.\(UUID().uuidString)")!
        defaults.set("test-owner", forKey: "familyShare.ownerID")
        defaults.set("test-share", forKey: "familyShare.shareID")
        defaults.set("Test Owner", forKey: "familyShare.ownerName")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = providedRegistry ?? FamilyShareNamespaceRegistry(factory: factory)
        let stateProvider = DefaultFamilyShareStateProvider(registry: registry)
        let publisher = DefaultFamilyShareProjectionPublisher(
            registry: registry,
            cloudSync: cloudSync,
            telemetry: telemetry,
            revocationTombstoneStore: revocationTombstoneStore
        )
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
        if let initialSeed {
            do {
                try registry.seed(initialSeed)
            } catch {
                XCTFail("Failed to seed Family Sharing test registry: \(error)")
            }
        }

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
            telemetry: telemetry,
            activeGoalsProvider: activeGoalsProvider,
            exchangeRateService: exchangeRateService,
            revocationTombstoneStore: revocationTombstoneStore,
            revocationRetryScheduler: revocationRetryScheduler,
            autoRepublishScheduler: autoRepublishScheduler,
            autoRepublishDirtyStateStore: autoRepublishDirtyStateStore,
            startsInitialRefreshTask: startsInitialRefreshTask
        )
    }

    func testShareAllGoalsPublishesOwnerStateAndPendingShareRequest() async {
        let telemetry = RecordingFamilyShareTelemetryTracker()
        let ownerNamespaceID = FamilyShareNamespaceID(ownerID: "owner", shareID: "share")
        let cloudSync = StubFamilyShareCloudSync(
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
            )
        let goal = Goal(
            name: "School Fund",
            currency: "USD",
            targetAmount: 1_500,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            telemetry: telemetry,
            activeGoalsProvider: { [goal] }
        )

        await coordinator.shareAllGoals([goal])

        XCTAssertEqual(coordinator.ownerState.lifecycleState, .sharedActive)
        XCTAssertNotNil(coordinator.pendingCloudSharingRequest)
        XCTAssertEqual(coordinator.pendingCloudSharingRequest?.namespaceID, coordinator.ownerNamespaceID)
        XCTAssertEqual(coordinator.pendingCloudSharingRequest?.share.recordID.recordName, "stub-share")

        let familyAccessModel = coordinator.makeFamilyAccessModel(currentGoals: [goal])
        XCTAssertEqual(familyAccessModel.ownerSections.count, 1)
        XCTAssertEqual(familyAccessModel.ownerSections.first?.goals.count, 1)
        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.createStarted.rawValue))
        XCTAssertTrue(telemetry.events.contains(FamilyShareTelemetryEvent.createSucceeded.rawValue))
        XCTAssertEqual(cloudSync.publishProjectionCallCount, 1)
        XCTAssertEqual(cloudSync.prepareShareCallCount, 1)
        XCTAssertEqual(cloudSync.containerResolutionCount, 0)
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

    func testIncompleteExchangeRatesRetainLastGoodProjectionInsteadOfPublishingActiveFallback() async throws {
        let ownerNamespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let lastGoodPayload = try XCTUnwrap(
            FamilyShareTestSeeder.makeSeed(
                for: .ownerSharedActive,
                namespaceID: ownerNamespaceID
            ).projectionPayload
        )
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
                    summaryCopy: "Shared goals are active.",
                    primaryActionCopy: "Manage Participants"
                ),
                participants: []
            ),
            publishedPayloads: [lastGoodPayload]
        )
        let goal = Goal(
            name: "School Fund",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let asset = Asset(currency: "BTC")
        let transaction = Transaction(amount: 300, asset: asset)
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 300)
        asset.transactions = [transaction]
        asset.allocations = [allocation]
        goal.allocations = [allocation]

        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            exchangeRateService: MissingFamilyShareExchangeRateService()
        )

        await coordinator.shareAllGoals([goal])

        XCTAssertEqual(cloudSync.publishProjectionCallCount, 0)
        XCTAssertEqual(cloudSync.prepareShareCallCount, 0)
        XCTAssertEqual(cloudSync.publishedPayloads.last, lastGoodPayload)
        XCTAssertEqual(
            coordinator.latestErrorMessage,
            "Family progress was not published because exchange rates are unavailable for BTC→USD."
        )
    }

    func testOrphanedAllocationRetainsLastGoodProjectionInsteadOfPublishingPartialProgress() async throws {
        let ownerNamespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let lastGoodPayload = try XCTUnwrap(
            FamilyShareTestSeeder.makeSeed(
                for: .ownerSharedActive,
                namespaceID: ownerNamespaceID
            ).projectionPayload
        )
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
                    summaryCopy: "Shared goals are active.",
                    primaryActionCopy: "Manage Participants"
                ),
                participants: []
            ),
            publishedPayloads: [lastGoodPayload]
        )
        let goal = Goal(
            name: "School Fund",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let asset = Asset(currency: "USD")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 300)
        goal.allocations = [allocation]
        allocation.asset = nil
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            exchangeRateService: MissingFamilyShareExchangeRateService()
        )

        await coordinator.shareAllGoals([goal])

        XCTAssertEqual(cloudSync.publishProjectionCallCount, 0)
        XCTAssertEqual(cloudSync.prepareShareCallCount, 0)
        XCTAssertEqual(cloudSync.publishedPayloads.last, lastGoodPayload)
        XCTAssertEqual(
            coordinator.latestErrorMessage,
            "Family progress was not published because one or more allocations no longer reference an asset."
        )
    }

    func testExistingShareStartupFetchesEveryRequiredRatePair() async {
        let ownerNamespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let goal = Goal(
            name: "Diversified Fund",
            currency: "USD",
            targetAmount: 50_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let bitcoin = Asset(currency: "BTC")
        let ether = Asset(currency: "ETH")
        let bitcoinAllocation = AssetAllocation(asset: bitcoin, goal: goal, amount: 1)
        let etherAllocation = AssetAllocation(asset: ether, goal: goal, amount: 1)
        goal.allocations = [bitcoinAllocation, etherAllocation]
        let rates = RecordingFamilyShareExchangeRateService(
            rates: [
                "BTC→USD": 10_000,
                "ETH→USD": 2_000
            ]
        )
        let coordinator = makeCoordinator(
            activeGoalsProvider: { [goal] },
            exchangeRateService: rates,
            initialSeed: FamilyShareTestSeeder.makeSeed(
                for: .ownerSharedActive,
                namespaceID: ownerNamespaceID
            )
        )

        await coordinator.refreshAllState()
        for _ in 0..<50 where rates.fetchedPairs.count < 2 {
            await Task.yield()
        }

        XCTAssertEqual(rates.fetchedPairs, ["BTC→USD", "ETH→USD"])
    }

    func testRevokedOwnerCannotBeRepublishedByParticipantOrMutationEvents() async {
        let ownerNamespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let activeSnapshot = FamilyShareOwnerShareSnapshot(
            ownerState: FamilyShareOwnerViewState(
                namespaceID: ownerNamespaceID,
                lifecycleState: .sharedActive,
                participantCount: 1,
                pendingParticipantCount: 0,
                activeParticipantCount: 1,
                revokedParticipantCount: 0,
                failedParticipantCount: 0,
                summaryCopy: "Shared goals are active.",
                primaryActionCopy: "Manage Participants"
            ),
            participants: [
                FamilyShareParticipantSnapshot(
                    id: "participant",
                    displayName: "Participant",
                    emailOrAlias: nil,
                    state: .active,
                    lastUpdatedAt: nil,
                    isCurrentUser: false
                )
            ]
        )
        let goal = Goal(
            name: "School Fund",
            currency: "USD",
            targetAmount: 1_500,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let cloudSync = StubFamilyShareCloudSync(ownerSnapshot: activeSnapshot)
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            initialSeed: FamilyShareSeededNamespaceState(
                ownerDisplayName: "Test Owner",
                ownerState: activeSnapshot.ownerState,
                inviteeState: nil,
                projectionPayload: nil
            )
        )

        await coordinator.refreshAllState()
        await coordinator.revokeOwnerShare()

        XCTAssertEqual(coordinator.ownerState.lifecycleState, .revoked)
        let publishCountAfterRevoke = cloudSync.publishProjectionCallCount

        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": [goal.id],
                "reason": "goalMutation"
            ]
        )
        try? await Task.sleep(nanoseconds: 2_200_000_000)

        XCTAssertEqual(
            cloudSync.publishProjectionCallCount,
            publishCountAfterRevoke,
            "Revocation must permanently stop every automatic publish source until an explicit re-share."
        )
        guard cloudSync.publishProjectionCallCount == publishCountAfterRevoke else {
            return
        }

        await coordinator.noteOwnerParticipantsDidChange()
        XCTAssertEqual(
            cloudSync.publishProjectionCallCount,
            publishCountAfterRevoke,
            "Participant changes after revocation must refresh state without republishing."
        )
    }

    func testLateInFlightPublishIsCompensatedAfterOwnerRevokesShare() async throws {
        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-a"
        )
        let initialState = FamilyShareSeededNamespaceState(
            ownerDisplayName: seededFixture.ownerDisplayName,
            ownerState: seededFixture.ownerState,
            inviteeState: seededFixture.inviteeState,
            projectionPayload: initialPayload
        )
        try registry.seed(initialState)

        let goal = Goal(
            name: "Late publish B",
            currency: "USD",
            targetAmount: 2_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            registry: registry
        )
        await coordinator.refreshAllState()

        let publishTask = Task { @MainActor in
            await coordinator.refreshFamilyAccessOwnerData(currentGoals: [goal])
        }
        await cloudSync.waitUntilPublishStarts()

        await coordinator.revokeOwnerShare()

        XCTAssertNil(cloudSync.remoteRootPayload)
        XCTAssertTrue(cloudSync.remoteGoalPayloads.isEmpty)
        XCTAssertEqual(coordinator.ownerState.lifecycleState, .revoked)

        cloudSync.resumeBlockedPublish()
        await publishTask.value

        XCTAssertEqual(
            cloudSync.events,
            ["publish-started", "revoke", "publish-committed", "revoke"],
            "A publish that commits after revoke must be followed by a compensating remote delete."
        )
        XCTAssertNil(cloudSync.remoteRootPayload)
        XCTAssertTrue(cloudSync.remoteGoalPayloads.isEmpty)
        XCTAssertEqual(coordinator.ownerState.lifecycleState, .revoked)

        let finalState = try XCTUnwrap(registry.seededState(for: namespaceID))
        XCTAssertEqual(finalState.ownerState.lifecycleState, .revoked)
        XCTAssertEqual(
            finalState.projectionPayload?.lifecycleStateRawValue,
            FamilyShareOwnerLifecycleState.revoked.rawValue
        )

        let publishCountAfterCompensation = cloudSync.publishProjectionCallCount
        await coordinator.noteOwnerParticipantsDidChange()
        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": [goal.id],
                "reason": "goalMutation"
            ]
        )
        try? await Task.sleep(nanoseconds: 2_200_000_000)

        XCTAssertEqual(
            cloudSync.publishProjectionCallCount,
            publishCountAfterCompensation,
            "A compensated revoke must leave every automatic publish source disabled."
        )
    }

    func testFailedLatePublishCompensationPersistsRevocationUntilRelaunchRetryAcknowledges() async throws {
        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-a"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )

        let suiteName = "FamilyShareRevocationRecovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let tombstoneStore = FamilyShareRevocationTombstoneStore(defaults: defaults)
        let goal = Goal(
            name: "Late publish requiring durable revoke",
            currency: "USD",
            targetAmount: 3_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload,
            failingRevokeCalls: [2]
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            registry: registry,
            revocationTombstoneStore: tombstoneStore
        )
        await coordinator.refreshAllState()

        let publishTask = Task { @MainActor in
            await coordinator.refreshFamilyAccessOwnerData(currentGoals: [goal])
        }
        await cloudSync.waitUntilPublishStarts()
        await coordinator.revokeOwnerShare()
        cloudSync.resumeBlockedPublish()
        await publishTask.value

        XCTAssertNotNil(
            cloudSync.remoteRootPayload,
            "The fixture must leave the late projection remote after the first compensation fails."
        )
        XCTAssertTrue(
            tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey),
            "A failed compensating delete must leave a durable revocation marker."
        )
        let stateAfterFailedCompensation = try XCTUnwrap(registry.seededState(for: namespaceID))
        XCTAssertNotEqual(stateAfterFailedCompensation.ownerState.lifecycleState, .sharedActive)
        XCTAssertNotEqual(
            stateAfterFailedCompensation.projectionPayload?.lifecycleStateRawValue,
            FamilyShareOwnerLifecycleState.sharedActive.rawValue,
            "A late remote ACK must not reactivate the local registry while revocation is pending."
        )

        let publishCountWhilePending = cloudSync.publishProjectionCallCount
        await coordinator.noteOwnerParticipantsDidChange()
        XCTAssertEqual(cloudSync.publishProjectionCallCount, publishCountWhilePending)

        let relaunchedCoordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            registry: registry,
            revocationTombstoneStore: tombstoneStore
        )
        for _ in 0..<200 where tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey) {
            await Task.yield()
        }
        await relaunchedCoordinator.refreshAllState()

        XCTAssertEqual(cloudSync.revokeCallCount, 3)
        XCTAssertNil(cloudSync.remoteRootPayload)
        XCTAssertTrue(cloudSync.remoteGoalPayloads.isEmpty)
        XCTAssertFalse(tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey))
        XCTAssertNotEqual(relaunchedCoordinator.ownerState.lifecycleState, .sharedActive)

        let publishCountAfterRecovery = cloudSync.publishProjectionCallCount
        await relaunchedCoordinator.noteOwnerParticipantsDidChange()
        XCTAssertEqual(cloudSync.publishProjectionCallCount, publishCountAfterRecovery)
    }

    func testPendingRevocationRetriesOnForegroundAndBackoffUntilRemoteAcknowledges() async throws {
        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-a"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )

        let suiteName = "FamilyShareRevocationLiveRetry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let tombstoneStore = FamilyShareRevocationTombstoneStore(defaults: defaults)
        let retryScheduler = ManualFamilyShareRetryScheduler()
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload,
            failingRevokeCalls: [1, 2]
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [] },
            registry: registry,
            revocationTombstoneStore: tombstoneStore,
            revocationRetryScheduler: retryScheduler
        )
        await coordinator.refreshAllState()

        await coordinator.revokeOwnerShare()

        XCTAssertEqual(cloudSync.revokeCallCount, 1)
        XCTAssertTrue(tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey))
        XCTAssertNotEqual(coordinator.ownerState.lifecycleState, .sharedActive)
        XCTAssertNotEqual(
            try registry.seededState(for: namespaceID)?.ownerState.lifecycleState,
            .sharedActive
        )
        XCTAssertNotNil(retryScheduler.lastDebounceAction)
        XCTAssertGreaterThan(retryScheduler.lastDebounceDelay ?? 0, 0)
        let scheduleCountAfterFirstFailure = retryScheduler.debounceScheduleCount

        coordinator.handleScenePhaseChange(.active)
        for _ in 0..<200 where retryScheduler.debounceScheduleCount == scheduleCountAfterFirstFailure {
            await Task.yield()
        }

        XCTAssertEqual(cloudSync.revokeCallCount, 2)
        XCTAssertGreaterThan(
            retryScheduler.debounceScheduleCount,
            scheduleCountAfterFirstFailure,
            "The foreground retry must settle and install a new backoff callback before the test invokes it."
        )
        XCTAssertTrue(tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey))
        XCTAssertNotNil(cloudSync.remoteRootPayload)
        XCTAssertTrue(cloudSync.remoteShareExists)

        let didRunBackoffRetry = await retryScheduler.runLatestActiveDebounce()
        XCTAssertTrue(didRunBackoffRetry)

        XCTAssertEqual(cloudSync.revokeCallCount, 3)
        XCTAssertNil(cloudSync.remoteRootPayload)
        XCTAssertTrue(cloudSync.remoteGoalPayloads.isEmpty)
        XCTAssertFalse(cloudSync.remoteShareExists)
        XCTAssertFalse(tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey))
        XCTAssertNotEqual(coordinator.ownerState.lifecycleState, .sharedActive)

        let publishCountAfterRecovery = cloudSync.publishProjectionCallCount
        await coordinator.noteOwnerParticipantsDidChange()
        XCTAssertEqual(cloudSync.publishProjectionCallCount, publishCountAfterRecovery)
    }

    func testFreshReshareSurvivesSuccessfulRetryOfOlderRevocationTombstone() async throws {
        FamilyShareReconciliationBarrier.recordImportObservedForTesting(at: .distantFuture)
        defer {
            FamilyShareReconciliationBarrier.resetObservedImportsForTesting()
        }

        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-before-fresh-reshare"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )

        let suiteName = "FamilyShareFreshReshareRecovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let tombstoneStore = FamilyShareRevocationTombstoneStore(defaults: defaults)
        let dirtyStore = FamilyShareDirtyStateStore(defaults: defaults)
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload,
            failingRevokeCalls: [1],
            suspendFirstPublish: false
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [] },
            registry: registry,
            revocationTombstoneStore: tombstoneStore,
            revocationRetryScheduler: ManualFamilyShareRetryScheduler(),
            autoRepublishScheduler: ManualFamilyShareAutoRepublishScheduler(),
            autoRepublishDirtyStateStore: dirtyStore,
            startsInitialRefreshTask: true
        )
        await coordinator.waitForInitialRefreshForTesting()
        await coordinator.revokeOwnerShare()
        XCTAssertTrue(tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey))
        XCTAssertEqual(cloudSync.revokeCallCount, 1)

        let freshGoal = Goal(
            name: "Fresh post-revoke share",
            currency: "USD",
            targetAmount: 21_000,
            deadline: Date().addingTimeInterval(86_400 * 120)
        )
        await coordinator.shareAllGoals([freshGoal])

        XCTAssertEqual(cloudSync.revokeCallCount, 2)
        XCTAssertFalse(tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey))
        XCTAssertEqual(
            cloudSync.publishProjectionCallCount,
            1,
            "The fresh intent must survive successful settlement of the older tombstone."
        )
        XCTAssertEqual(cloudSync.prepareShareCallCount, 1)
        XCTAssertEqual(
            cloudSync.publishedPayloads.last?.goals.map(\.goalName),
            ["Fresh post-revoke share"]
        )
        XCTAssertNotNil(coordinator.pendingCloudSharingRequest)
    }

    func testFreshReshareFailureDoesNotAutoShareAfterLaterTombstoneRecovery() async throws {
        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-before-failed-fresh-reshare"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )

        let suiteName = "FamilyShareFreshReshareFailure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let tombstoneStore = FamilyShareRevocationTombstoneStore(defaults: defaults)
        let dirtyStore = FamilyShareDirtyStateStore(defaults: defaults)
        let retryScheduler = ManualFamilyShareRetryScheduler()
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload,
            failingRevokeCalls: [1, 2],
            suspendFirstPublish: false
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [] },
            registry: registry,
            revocationTombstoneStore: tombstoneStore,
            revocationRetryScheduler: retryScheduler,
            autoRepublishScheduler: ManualFamilyShareAutoRepublishScheduler(),
            autoRepublishDirtyStateStore: dirtyStore,
            startsInitialRefreshTask: true
        )
        await coordinator.waitForInitialRefreshForTesting()
        await coordinator.revokeOwnerShare()

        let freshGoal = Goal(
            name: "Must require another explicit tap",
            currency: "USD",
            targetAmount: 22_000,
            deadline: Date().addingTimeInterval(86_400 * 120)
        )
        await coordinator.shareAllGoals([freshGoal])

        XCTAssertEqual(cloudSync.revokeCallCount, 2)
        XCTAssertEqual(cloudSync.publishProjectionCallCount, 0)
        XCTAssertEqual(cloudSync.prepareShareCallCount, 0)
        XCTAssertNotNil(coordinator.latestErrorMessage)
        XCTAssertTrue(tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey))

        let didRunRecovery = await retryScheduler.runLatestActiveDebounce()
        XCTAssertTrue(didRunRecovery)
        XCTAssertEqual(cloudSync.revokeCallCount, 3)
        XCTAssertFalse(tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey))
        XCTAssertEqual(
            cloudSync.publishProjectionCallCount,
            0,
            "A later background tombstone recovery must not resurrect a failed explicit share."
        )
        XCTAssertEqual(cloudSync.prepareShareCallCount, 0)
    }

    func testExplicitReshareWaitsForSuspendedOriginalRevokeBeforePublishing() async throws {
        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-before-revoke"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )
        let resharedGoal = Goal(
            name: "Re-share after suspended revoke",
            currency: "USD",
            targetAmount: 4_500,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload,
            suspendFirstRevoke: true,
            suspendFirstPublish: false
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [resharedGoal] },
            registry: registry
        )
        await coordinator.refreshAllState()

        let revoke = Task { @MainActor in
            await coordinator.revokeOwnerShare()
        }
        await cloudSync.waitUntilFirstRevokeStarts()

        let reshare = Task { @MainActor in
            await coordinator.shareAllGoals([resharedGoal])
        }
        await flushAsyncWork(iterations: 100)

        let revokeCallCountWhileOriginalRevokeWasSuspended = cloudSync.revokeCallCount
        let publishCallCountWhileOriginalRevokeWasSuspended = cloudSync.publishProjectionCallCount
        let prepareCallCountWhileOriginalRevokeWasSuspended = cloudSync.prepareShareCallCount
        cloudSync.resumeFirstRevoke()
        cloudSync.resumeBlockedPublish()
        await revoke.value
        await reshare.value

        XCTAssertEqual(
            revokeCallCountWhileOriginalRevokeWasSuspended,
            1,
            "A re-share must join the original revocation operation instead of starting a concurrent recovery revoke."
        )
        XCTAssertEqual(
            publishCallCountWhileOriginalRevokeWasSuspended,
            0,
            "A re-share must not publish while its preceding revocation is still awaiting remote acknowledgement."
        )
        XCTAssertEqual(prepareCallCountWhileOriginalRevokeWasSuspended, 0)

        XCTAssertEqual(cloudSync.revokeCallCount, 1)
        XCTAssertEqual(cloudSync.publishProjectionCallCount, 1)
        XCTAssertEqual(cloudSync.prepareShareCallCount, 1)
        XCTAssertNotNil(
            cloudSync.remoteRootPayload,
            "The completed original revoke must not delete the projection published by the later explicit re-share."
        )
        XCTAssertTrue(cloudSync.remoteShareExists)
    }

    func testExplicitReshareWaitsForInFlightRevokedPublicationToBeCompensated() async throws {
        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-a"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )

        let suiteName = "FamilyShareRevocationReshare.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let tombstoneStore = FamilyShareRevocationTombstoneStore(defaults: defaults)
        let goal = Goal(
            name: "Re-share after revoke",
            currency: "USD",
            targetAmount: 4_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            registry: registry,
            revocationTombstoneStore: tombstoneStore
        )
        await coordinator.refreshAllState()

        let publishTask = Task { @MainActor in
            await coordinator.refreshFamilyAccessOwnerData(currentGoals: [goal])
        }
        await cloudSync.waitUntilPublishStarts()
        await coordinator.revokeOwnerShare()

        let reshareTask = Task { @MainActor in
            await coordinator.shareAllGoals([goal])
        }
        await flushAsyncWork()
        let prepareShareCallCountWhileOldPublishIsBlocked = cloudSync.prepareShareCallCount
        let tombstoneWasPendingWhileOldPublishWasBlocked = tombstoneStore.isPending(
            namespaceKey: namespaceID.namespaceKey
        )

        cloudSync.resumeBlockedPublish()
        await publishTask.value
        await reshareTask.value

        XCTAssertEqual(
            prepareShareCallCountWhileOldPublishIsBlocked,
            0,
            "A re-share must not prepare CloudKit access before the revoked in-flight publication is compensated."
        )
        XCTAssertTrue(tombstoneWasPendingWhileOldPublishWasBlocked)
        XCTAssertFalse(tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey))
        XCTAssertEqual(
            cloudSync.publishProjectionCallCount,
            2,
            "The requested re-share must publish after compensating the revoked in-flight projection."
        )
        XCTAssertEqual(cloudSync.prepareShareCallCount, 1)
        XCTAssertNotNil(coordinator.pendingCloudSharingRequest)
        XCTAssertNotNil(cloudSync.remoteRootPayload)
    }

    func testEquivalentExplicitReshareAfterRevokeStartsANewShareGeneration() async throws {
        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-a"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )

        let suiteName = "FamilyShareExplicitRevocationReshare.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let tombstoneStore = FamilyShareRevocationTombstoneStore(defaults: defaults)
        let goal = Goal(
            name: "Explicit re-share after revoke",
            currency: "USD",
            targetAmount: 4_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            registry: registry,
            revocationTombstoneStore: tombstoneStore
        )
        await coordinator.refreshAllState()

        let firstShare = Task { @MainActor in
            await coordinator.shareAllGoals([goal])
        }
        await cloudSync.waitUntilPublishStarts()
        await coordinator.revokeOwnerShare()

        let reshare = Task { @MainActor in
            await coordinator.shareAllGoals([goal])
        }
        await flushAsyncWork()

        XCTAssertEqual(cloudSync.prepareShareCallCount, 0)
        XCTAssertTrue(tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey))

        cloudSync.resumeBlockedPublish()
        await firstShare.value
        await reshare.value

        XCTAssertEqual(
            cloudSync.publishProjectionCallCount,
            2,
            "The explicit re-share must publish in a new generation after the revoked generation settles."
        )
        XCTAssertEqual(cloudSync.prepareShareCallCount, 1)
        XCTAssertEqual(cloudSync.revokeCallCount, 2)
        XCTAssertFalse(tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey))
        XCTAssertNotNil(coordinator.pendingCloudSharingRequest)
        XCTAssertNotNil(cloudSync.remoteRootPayload)
    }

    func testOverlappingExplicitShareRequestsSerializeBeforePreparingOrRevoking() async throws {
        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-a"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )
        let goal = Goal(
            name: "Double explicit share",
            currency: "USD",
            targetAmount: 5_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            registry: registry
        )
        await coordinator.refreshAllState()

        let firstShare = Task { @MainActor in
            await coordinator.shareAllGoals([goal])
        }
        await cloudSync.waitUntilPublishStarts()
        var secondShareCompleted = false
        let secondShare = Task { @MainActor in
            await coordinator.shareAllGoals([goal])
            secondShareCompleted = true
        }
        await flushAsyncWork()

        XCTAssertFalse(
            secondShareCompleted,
            "The joined caller must await the owner of the explicit share single-flight."
        )
        XCTAssertEqual(
            cloudSync.prepareShareCallCount,
            0,
            "A later explicit share must not treat an in-flight publish as completed."
        )
        XCTAssertEqual(cloudSync.revokeCallCount, 0)

        cloudSync.resumeBlockedPublish()
        await firstShare.value
        await secondShare.value

        XCTAssertTrue(secondShareCompleted)
        XCTAssertNil(coordinator.latestErrorMessage)
        XCTAssertEqual(cloudSync.publishProjectionCallCount, 1)
        XCTAssertEqual(
            cloudSync.prepareShareCallCount,
            1,
            "Equivalent overlapping share intents should join one explicit single-flight."
        )
        XCTAssertEqual(
            cloudSync.revokeCallCount,
            0,
            "Overlapping explicit shares must not invalidate and compensate each other."
        )
        XCTAssertNotNil(cloudSync.remoteRootPayload)
        XCTAssertNotNil(coordinator.pendingCloudSharingRequest)
    }

    func testOverlappingMixedExplicitShareIntentsPreserveFIFOOrder() async throws {
        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-before-mixed-intents"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )
        let intentX = Goal(
            name: "Intent X",
            currency: "USD",
            targetAmount: 5_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let intentY = Goal(
            name: "Intent Y",
            currency: "USD",
            targetAmount: 7_500,
            deadline: Date().addingTimeInterval(86_400 * 120)
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: {
                throw NSError(
                    domain: "FamilyShareAcceptanceCoordinatorTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Use the explicit intent snapshot"]
                )
            },
            registry: registry
        )
        await coordinator.refreshAllState()

        let firstX = Task { @MainActor in
            await coordinator.shareAllGoals([intentX])
        }
        await cloudSync.waitUntilPublishStarts()
        let middleY = Task { @MainActor in
            await coordinator.shareAllGoals([intentY])
        }
        await flushAsyncWork()
        let latestX = Task { @MainActor in
            await coordinator.shareAllGoals([intentX])
        }
        await flushAsyncWork()

        cloudSync.resumeBlockedPublish()
        await firstX.value
        await middleY.value
        await latestX.value

        XCTAssertEqual(
            cloudSync.publishedPayloads.compactMap { $0.goals.first?.goalName },
            ["Intent X", "Intent Y", "Intent X"],
            "An intervening Y intent means the later X cannot coalesce with the already in-flight earlier X."
        )
        XCTAssertEqual(cloudSync.prepareShareCallCount, 3)
        XCTAssertEqual(
            cloudSync.remoteRootPayload?.goals.first?.goalName,
            "Intent X",
            "The durable projection must reflect the latest explicit intent."
        )
    }

    func testQueuedExplicitShareUsesCallTimeSnapshotThenCatchesUpToAuthoritativeMutation() async throws {
        FamilyShareReconciliationBarrier.recordImportObservedForTesting(at: .distantFuture)
        defer {
            FamilyShareReconciliationBarrier.resetObservedImportsForTesting()
        }

        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-before-queued-mutation"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )
        let blockingX = Goal(
            name: "Blocking X",
            currency: "USD",
            targetAmount: 5_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let queuedY = Goal(
            name: "Queued Y",
            currency: "USD",
            targetAmount: 7_500,
            deadline: Date().addingTimeInterval(86_400 * 120)
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [blockingX, queuedY] },
            registry: registry
        )
        await coordinator.refreshAllState()

        let firstShare = Task { @MainActor in
            await coordinator.shareAllGoals([blockingX])
        }
        await cloudSync.waitUntilPublishStarts()

        var queuedShareEntered = false
        let queuedShare = Task { @MainActor in
            queuedShareEntered = true
            await coordinator.shareAllGoals([queuedY])
        }
        while queuedShareEntered == false {
            await Task.yield()
        }
        // Once another MainActor task can run, shareAllGoals has reached its first
        // suspension and the Y intent is already present in the coordinator queue.
        await Task.yield()
        queuedY.name = "Mutated Y"
        queuedY.targetAmount = 99_000

        cloudSync.resumeBlockedPublish()
        await firstShare.value
        await queuedShare.value

        let queuedGoalNameSequence = cloudSync.publishedPayloads.compactMap { payload in
            payload.goals.first(where: { $0.goalID == queuedY.id.uuidString })?.goalName
        }
        let queuedGoalTargetSequence = cloudSync.publishedPayloads.compactMap { payload in
            payload.goals.first(where: { $0.goalID == queuedY.id.uuidString })?.targetAmount
        }
        XCTAssertEqual(
            queuedGoalNameSequence,
            ["Queued Y", "Mutated Y"],
            "The explicit payload must preserve call-time Y, followed by one authoritative catch-up."
        )
        XCTAssertEqual(
            queuedGoalTargetSequence,
            [Decimal(7_500), Decimal(99_000)]
        )
        XCTAssertEqual(
            cloudSync.publishedPayloads.count,
            3,
            "Expected explicit X, explicit call-time Y, then exactly one automatic catch-up."
        )
        XCTAssertEqual(
            cloudSync.publishedPayloads.first?.goals.map(\.goalName),
            ["Blocking X"]
        )
        XCTAssertEqual(
            Set(cloudSync.publishedPayloads.last?.goals.map(\.goalName) ?? []),
            Set(["Blocking X", "Mutated Y"]),
            "The final durable projection must reflect all authoritative active goals."
        )
        XCTAssertEqual(
            cloudSync.remoteRootPayload?.goals.first(where: { $0.goalID == queuedY.id.uuidString })?.targetAmount,
            Decimal(99_000)
        )
        XCTAssertEqual(cloudSync.prepareShareCallCount, 2)
    }

    func testExplicitCatchUpIsDurableBeforeSuspendedRemotePublishCommits() async throws {
        FamilyShareReconciliationBarrier.recordImportObservedForTesting(at: .distantFuture)
        defer {
            FamilyShareReconciliationBarrier.resetObservedImportsForTesting()
        }

        let dirtySuiteName = "FamilySharePrecommitCatchUp.\(UUID().uuidString)"
        let dirtyDefaults = UserDefaults(suiteName: dirtySuiteName)!
        defer {
            dirtyDefaults.removePersistentDomain(forName: dirtySuiteName)
        }
        let dirtyStore = FamilyShareDirtyStateStore(defaults: dirtyDefaults)
        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-before-precommit-marker"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )
        let goal = Goal(
            name: "Call-time durable goal",
            currency: "USD",
            targetAmount: 14_000,
            deadline: Date().addingTimeInterval(86_400 * 120)
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            registry: registry,
            autoRepublishScheduler: ManualFamilyShareAutoRepublishScheduler(),
            autoRepublishDirtyStateStore: dirtyStore
        )
        await coordinator.refreshAllState()

        let shareTask = Task { @MainActor in
            await coordinator.shareAllGoals([goal])
        }
        await cloudSync.waitUntilPublishStarts()

        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            }),
            "The catch-up obligation must be durable before the first explicit remote commit can complete."
        )

        cloudSync.resumeBlockedPublish()
        await shareTask.value
        XCTAssertFalse(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            }),
            "An authoritative post-explicit publish or dedup may clear the provisional marker."
        )
    }

    func testAuthoritativeCatchUpFetchFailureStaysDurablyDirtyWithoutFallbackPublish() async throws {
        FamilyShareReconciliationBarrier.recordImportObservedForTesting(at: .distantFuture)
        defer {
            FamilyShareReconciliationBarrier.resetObservedImportsForTesting()
        }

        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let dirtySuiteName = "FamilyShareStrictCatchUp.\(UUID().uuidString)"
        let dirtyDefaults = UserDefaults(suiteName: dirtySuiteName)!
        defer {
            dirtyDefaults.removePersistentDomain(forName: dirtySuiteName)
        }
        let dirtyStore = FamilyShareDirtyStateStore(defaults: dirtyDefaults)
        let autoRepublishScheduler = ManualFamilyShareAutoRepublishScheduler()

        let ownerState = FamilyShareOwnerViewState(
            namespaceID: namespaceID,
            lifecycleState: .sharedActive,
            participantCount: 0,
            pendingParticipantCount: 0,
            activeParticipantCount: 0,
            revokedParticipantCount: 0,
            failedParticipantCount: 0,
            summaryCopy: "Shared goals are active.",
            primaryActionCopy: "Manage Participants"
        )
        let cloudSync = StubFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: ownerState,
                participants: []
            )
        )
        let explicitGoal = Goal(
            name: "Call-time goal",
            currency: "USD",
            targetAmount: 12_500,
            deadline: Date().addingTimeInterval(86_400 * 120)
        )
        let providerError = NSError(
            domain: "FamilyShareAcceptanceCoordinatorTests",
            code: 41,
            userInfo: [NSLocalizedDescriptionKey: "Synthetic authoritative goal fetch failure"]
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { throw providerError },
            autoRepublishScheduler: autoRepublishScheduler,
            autoRepublishDirtyStateStore: dirtyStore
        )
        await coordinator.refreshAllState()

        await coordinator.shareAllGoals([explicitGoal])

        XCTAssertEqual(
            cloudSync.publishProjectionCallCount,
            1,
            "Catch-up must not publish the live explicit cache when the authoritative fetch fails."
        )
        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            }),
            "Authoritative fetch failure must keep a durable catch-up obligation for retry."
        )
        XCTAssertEqual(coordinator.latestErrorMessage, providerError.localizedDescription)
    }

    func testInactiveLifecyclePreservesCatchUpUntilLaterActivationPublishesAuthoritativeGoals() async throws {
        FamilyShareReconciliationBarrier.recordImportObservedForTesting(at: .distantFuture)
        defer {
            FamilyShareReconciliationBarrier.resetObservedImportsForTesting()
        }

        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let dirtySuiteName = "FamilyShareInactiveCatchUp.\(UUID().uuidString)"
        let dirtyDefaults = UserDefaults(suiteName: dirtySuiteName)!
        defer {
            dirtyDefaults.removePersistentDomain(forName: dirtySuiteName)
        }
        let dirtyStore = FamilyShareDirtyStateStore(defaults: dirtyDefaults)
        let autoRepublishScheduler = ManualFamilyShareAutoRepublishScheduler()

        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-before-inactive-catch-up"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )
        let inactiveOwnerState = FamilyShareOwnerViewState(
            namespaceID: namespaceID,
            lifecycleState: .notShared,
            participantCount: 0,
            pendingParticipantCount: 0,
            activeParticipantCount: 0,
            revokedParticipantCount: 0,
            failedParticipantCount: 0,
            summaryCopy: "Not currently shared.",
            primaryActionCopy: "Share with Family"
        )
        let goal = Goal(
            name: "Call-time goal",
            currency: "USD",
            targetAmount: 8_000,
            deadline: Date().addingTimeInterval(86_400 * 120)
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: inactiveOwnerState,
                participants: []
            ),
            remotePayload: initialPayload
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            registry: registry,
            autoRepublishScheduler: autoRepublishScheduler,
            autoRepublishDirtyStateStore: dirtyStore
        )
        await coordinator.refreshAllState()

        let shareTask = Task { @MainActor in
            await coordinator.shareAllGoals([goal])
        }
        await cloudSync.waitUntilPublishStarts()
        goal.name = "Authoritative goal"
        goal.targetAmount = 88_000
        cloudSync.resumeBlockedPublish()
        await shareTask.value

        XCTAssertEqual(cloudSync.publishProjectionCallCount, 1)
        XCTAssertEqual(
            cloudSync.publishedPayloads.first?.goals.first?.goalName,
            "Call-time goal"
        )
        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            }),
            "An inactive lifecycle guard must persist the pending catch-up."
        )

        cloudSync.setOwnerSnapshot(
            FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            )
        )
        await coordinator.refreshAllState()
        let didRunCatchUpRetry = await autoRepublishScheduler.runLatestActiveDebounce()
        XCTAssertTrue(
            didRunCatchUpRetry,
            "Pipeline activation must expose a live, non-cancelled catch-up retry."
        )

        XCTAssertEqual(
            cloudSync.publishProjectionCallCount,
            2,
            "Pipeline activation must retry the retained catch-up exactly once."
        )
        XCTAssertEqual(
            cloudSync.remoteRootPayload?.goals.first(where: {
                $0.goalID == goal.id.uuidString
            })?.goalName,
            "Authoritative goal"
        )
        XCTAssertEqual(
            cloudSync.remoteRootPayload?.goals.first(where: {
                $0.goalID == goal.id.uuidString
            })?.targetAmount,
            Decimal(88_000)
        )
        XCTAssertFalse(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            })
        )
    }

    func testRetainedCatchUpSurvivesInactiveTeardownAndRelaunch() async throws {
        FamilyShareReconciliationBarrier.recordImportObservedForTesting(at: .distantFuture)
        defer {
            FamilyShareReconciliationBarrier.resetObservedImportsForTesting()
        }

        let dirtySuiteName = "FamilyShareRelaunchCatchUp.\(UUID().uuidString)"
        let dirtyDefaults = UserDefaults(suiteName: dirtySuiteName)!
        defer {
            dirtyDefaults.removePersistentDomain(forName: dirtySuiteName)
        }
        let dirtyStore = FamilyShareDirtyStateStore(defaults: dirtyDefaults)
        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-before-relaunch-catch-up"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )

        let goal = Goal(
            name: "Call-time goal",
            currency: "USD",
            targetAmount: 9_000,
            deadline: Date().addingTimeInterval(86_400 * 120)
        )
        var providerIsUnavailable = true
        let providerError = NSError(
            domain: "FamilyShareAcceptanceCoordinatorTests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Synthetic pre-relaunch fetch failure"]
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload,
            suspendFirstPublish: false
        )
        let firstScheduler = ManualFamilyShareAutoRepublishScheduler()
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: {
                if providerIsUnavailable {
                    throw providerError
                }
                return [goal]
            },
            registry: registry,
            autoRepublishScheduler: firstScheduler,
            autoRepublishDirtyStateStore: dirtyStore
        )
        await coordinator.refreshAllState()
        await coordinator.shareAllGoals([goal])

        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            })
        )
        goal.name = "Authoritative after relaunch"
        goal.targetAmount = 99_000
        cloudSync.setOwnerSnapshot(
            FamilyShareOwnerShareSnapshot(
                ownerState: FamilyShareOwnerViewState(
                    namespaceID: namespaceID,
                    lifecycleState: .notShared,
                    participantCount: 0,
                    pendingParticipantCount: 0,
                    activeParticipantCount: 0,
                    revokedParticipantCount: 0,
                    failedParticipantCount: 0,
                    summaryCopy: "Not currently shared.",
                    primaryActionCopy: "Share with Family"
                ),
                participants: []
            )
        )
        await coordinator.refreshAllState()

        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            }),
            "Inactive lifecycle teardown must preserve a retained catch-up across app termination."
        )

        providerIsUnavailable = false
        cloudSync.setOwnerSnapshot(
            FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            )
        )
        let relaunchScheduler = ManualFamilyShareAutoRepublishScheduler()
        let relaunchedCoordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            registry: registry,
            autoRepublishScheduler: relaunchScheduler,
            autoRepublishDirtyStateStore: dirtyStore
        )
        await relaunchedCoordinator.refreshAllState()
        let didRunRelaunchCatchUp = await relaunchScheduler.runLatestActiveDebounce()

        XCTAssertTrue(didRunRelaunchCatchUp)
        XCTAssertEqual(cloudSync.publishProjectionCallCount, 2)
        XCTAssertEqual(
            cloudSync.remoteRootPayload?.goals.first(where: {
                $0.goalID == goal.id.uuidString
            })?.goalName,
            "Authoritative after relaunch"
        )
        XCTAssertEqual(
            cloudSync.remoteRootPayload?.goals.first(where: {
                $0.goalID == goal.id.uuidString
            })?.targetAmount,
            Decimal(99_000)
        )
        XCTAssertFalse(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            })
        )
    }

    func testObservedRemoteRevocationClearsRetainedCatchUpEvenAfterInactiveTeardown() async throws {
        FamilyShareReconciliationBarrier.recordImportObservedForTesting(at: .distantFuture)
        defer {
            FamilyShareReconciliationBarrier.resetObservedImportsForTesting()
        }

        let dirtySuiteName = "FamilyShareRevokedCatchUp.\(UUID().uuidString)"
        let dirtyDefaults = UserDefaults(suiteName: dirtySuiteName)!
        defer {
            dirtyDefaults.removePersistentDomain(forName: dirtySuiteName)
        }
        let dirtyStore = FamilyShareDirtyStateStore(defaults: dirtyDefaults)
        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-before-observed-revoke"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )

        let goal = Goal(
            name: "Call-time goal",
            currency: "USD",
            targetAmount: 10_000,
            deadline: Date().addingTimeInterval(86_400 * 120)
        )
        var providerIsUnavailable = true
        let providerError = NSError(
            domain: "FamilyShareAcceptanceCoordinatorTests",
            code: 43,
            userInfo: [NSLocalizedDescriptionKey: "Synthetic pre-revoke fetch failure"]
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload,
            suspendFirstPublish: false
        )
        let scheduler = ManualFamilyShareAutoRepublishScheduler()
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: {
                if providerIsUnavailable {
                    throw providerError
                }
                return [goal]
            },
            registry: registry,
            autoRepublishScheduler: scheduler,
            autoRepublishDirtyStateStore: dirtyStore
        )
        await coordinator.refreshAllState()
        await coordinator.shareAllGoals([goal])
        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            })
        )

        let inactiveOwnerState = FamilyShareOwnerViewState(
            namespaceID: namespaceID,
            lifecycleState: .notShared,
            participantCount: 0,
            pendingParticipantCount: 0,
            activeParticipantCount: 0,
            revokedParticipantCount: 0,
            failedParticipantCount: 0,
            summaryCopy: "Not currently shared.",
            primaryActionCopy: "Share with Family"
        )
        cloudSync.setOwnerSnapshot(
            FamilyShareOwnerShareSnapshot(
                ownerState: inactiveOwnerState,
                participants: []
            )
        )
        await coordinator.refreshAllState()
        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            }),
            "A merely inactive lifecycle must retain the pending authoritative catch-up."
        )

        let revokedOwnerState = FamilyShareOwnerViewState(
            namespaceID: namespaceID,
            lifecycleState: .revoked,
            participantCount: 0,
            pendingParticipantCount: 0,
            activeParticipantCount: 0,
            revokedParticipantCount: 1,
            failedParticipantCount: 0,
            summaryCopy: "Access revoked.",
            primaryActionCopy: "Share with Family"
        )
        cloudSync.setOwnerSnapshot(
            FamilyShareOwnerShareSnapshot(
                ownerState: revokedOwnerState,
                participants: []
            )
        )
        await coordinator.refreshAllState()

        XCTAssertFalse(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            }),
            "A confirmed remote revocation terminates the catch-up obligation even when the pipeline is already inactive."
        )

        providerIsUnavailable = false
        cloudSync.setOwnerSnapshot(
            FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            )
        )
        await coordinator.refreshAllState()
        let didResurrectOnSameCoordinator = await scheduler.runLatestActiveDebounce()
        XCTAssertFalse(
            didResurrectOnSameCoordinator,
            "The revoked catch-up must not be resurrected when the same coordinator later sees an active lifecycle."
        )

        let relaunchScheduler = ManualFamilyShareAutoRepublishScheduler()
        let relaunchedCoordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            registry: registry,
            autoRepublishScheduler: relaunchScheduler,
            autoRepublishDirtyStateStore: dirtyStore
        )
        await relaunchedCoordinator.refreshAllState()
        let didRehydrateAfterRelaunch = await relaunchScheduler.runLatestActiveDebounce()
        XCTAssertFalse(
            didRehydrateAfterRelaunch,
            "A revoked catch-up must not rehydrate after relaunch."
        )
        XCTAssertEqual(
            cloudSync.publishProjectionCallCount,
            1,
            "Only the original explicit publication is allowed after confirmed revocation."
        )
    }

    func testTransientNotSharedRefreshDoesNotCompensateSuspendedAutomaticPublish() async throws {
        FamilyShareReconciliationBarrier.recordImportObservedForTesting(at: .distantFuture)
        defer {
            FamilyShareReconciliationBarrier.resetObservedImportsForTesting()
        }

        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-before-transient-inactive-refresh"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )

        let suiteName = "FamilyShareTransientInactivePublish.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let tombstoneStore = FamilyShareRevocationTombstoneStore(defaults: defaults)
        let dirtyStore = FamilyShareDirtyStateStore(defaults: defaults)
        let goal = Goal(
            name: "Automatic publish survives transient state",
            currency: "USD",
            targetAmount: 12_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: seededFixture.ownerState,
                participants: []
            ),
            remotePayload: initialPayload
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            registry: registry,
            revocationTombstoneStore: tombstoneStore,
            autoRepublishScheduler: ManualFamilyShareAutoRepublishScheduler(),
            autoRepublishDirtyStateStore: dirtyStore
        )
        await coordinator.refreshAllState()

        let publishTask = Task { @MainActor in
            await coordinator.refreshFamilyAccessOwnerData(
                currentGoals: [goal]
            )
        }
        await cloudSync.waitUntilPublishStarts()

        let inactiveOwnerState = FamilyShareOwnerViewState(
            namespaceID: namespaceID,
            lifecycleState: .notShared,
            participantCount: 0,
            pendingParticipantCount: 0,
            activeParticipantCount: 0,
            revokedParticipantCount: 0,
            failedParticipantCount: 0,
            summaryCopy: "Temporarily not shared.",
            primaryActionCopy: "Share with Family"
        )
        cloudSync.setOwnerSnapshot(
            FamilyShareOwnerShareSnapshot(
                ownerState: inactiveOwnerState,
                participants: []
            )
        )
        await coordinator.refreshAllState()
        XCTAssertEqual(coordinator.ownerState.lifecycleState, .notShared)
        XCTAssertEqual(cloudSync.revokeCallCount, 0)

        cloudSync.resumeBlockedPublish()
        await publishTask.value

        XCTAssertEqual(cloudSync.publishProjectionCallCount, 1)
        XCTAssertEqual(
            cloudSync.revokeCallCount,
            0,
            "A transient inactive refresh must not convert a late automatic ACK into a remote revoke."
        )
        XCTAssertEqual(
            cloudSync.events,
            ["publish-started", "publish-committed"]
        )
        XCTAssertTrue(cloudSync.remoteShareExists)
        XCTAssertNotNil(cloudSync.remoteRootPayload)
        XCTAssertFalse(
            tombstoneStore.isPending(namespaceKey: namespaceID.namespaceKey)
        )
        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            }),
            "Transient teardown must retain the automatic publication obligation."
        )
        XCTAssertEqual(coordinator.ownerState.lifecycleState, .notShared)
    }

    func testOverlappingNewerRefreshCannotDiscardObservedInactiveLifecycleFence() async throws {
        FamilyShareReconciliationBarrier.recordImportObservedForTesting(at: .distantFuture)
        defer {
            FamilyShareReconciliationBarrier.resetObservedImportsForTesting()
        }

        let namespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let seededFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        let initialPayload = try payloadWithoutRemoteTimestamp(
            from: XCTUnwrap(seededFixture.projectionPayload),
            contentHash: "projection-before-overlapping-refresh"
        )
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: seededFixture.ownerDisplayName,
                ownerState: seededFixture.ownerState,
                inviteeState: seededFixture.inviteeState,
                projectionPayload: initialPayload
            )
        )

        let suiteName = "FamilyShareOverlappingRefresh.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let dirtyStore = FamilyShareDirtyStateStore(defaults: defaults)
        let tombstoneStore = FamilyShareRevocationTombstoneStore(defaults: defaults)
        let goal = Goal(
            name: "Overlapped refresh goal",
            currency: "USD",
            targetAmount: 16_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let activeSnapshot = FamilyShareOwnerShareSnapshot(
            ownerState: seededFixture.ownerState,
            participants: []
        )
        let inactiveSnapshot = FamilyShareOwnerShareSnapshot(
            ownerState: FamilyShareOwnerViewState(
                namespaceID: namespaceID,
                lifecycleState: .notShared,
                participantCount: 0,
                pendingParticipantCount: 0,
                activeParticipantCount: 0,
                revokedParticipantCount: 0,
                failedParticipantCount: 0,
                summaryCopy: "Temporarily not shared.",
                primaryActionCopy: "Share with Family"
            ),
            participants: []
        )
        let cloudSync = BlockingLatePublishFamilyShareCloudSync(
            ownerSnapshot: activeSnapshot,
            remotePayload: initialPayload
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            registry: registry,
            revocationTombstoneStore: tombstoneStore,
            autoRepublishScheduler: ManualFamilyShareAutoRepublishScheduler(),
            autoRepublishDirtyStateStore: dirtyStore,
            startsInitialRefreshTask: true
        )
        await coordinator.waitForInitialRefreshForTesting()

        let publishTask = Task { @MainActor in
            await coordinator.refreshFamilyAccessOwnerData(
                currentGoals: [goal]
            )
        }
        await cloudSync.waitUntilPublishStarts()
        let preInactiveDebugSnapshot =
            await coordinator.autoRepublishDebugSnapshotForTesting()
        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            }),
            "The automatic publish must be durably dirty before the inactive refresh begins. Debug: \(preInactiveDebugSnapshot)"
        )

        cloudSync.suspendNextOwnerSnapshot(returning: inactiveSnapshot)
        let inactiveRefresh = Task { @MainActor in
            await coordinator.refreshAllState()
        }
        let didObserveInactiveRequest = await cloudSync.waitUntilSuspendedOwnerSnapshotStarts()
        XCTAssertTrue(didObserveInactiveRequest)

        cloudSync.setOwnerSnapshot(activeSnapshot)
        cloudSync.suspendNextOwnerSnapshot(returning: activeSnapshot)
        let requestCountBeforeNewerRefresh = coordinator.refreshRequestCountForTesting
        let newerRefresh = Task { @MainActor in
            await coordinator.refreshAllState()
        }
        for _ in 0..<200
        where coordinator.refreshRequestCountForTesting == requestCountBeforeNewerRefresh {
            await Task.yield()
        }
        XCTAssertGreaterThan(
            coordinator.refreshRequestCountForTesting,
            requestCountBeforeNewerRefresh,
            "The newer refresh must be registered before the inactive observation is released."
        )

        cloudSync.resumeSuspendedOwnerSnapshot()
        await inactiveRefresh.value
        let didStartTrailingActiveSnapshot =
            await cloudSync.waitUntilSuspendedOwnerSnapshotStarts()
        XCTAssertTrue(
            didStartTrailingActiveSnapshot,
            "The queued newer refresh must begin only after the inactive pass has reconciled."
        )
        XCTAssertEqual(
            coordinator.ownerState.lifecycleState,
            .notShared,
            "The first single-flight pass must apply its already observed inactive lifecycle."
        )
        let postInactiveDebugSnapshot =
            await coordinator.autoRepublishDebugSnapshotForTesting()
        XCTAssertEqual(
            postInactiveDebugSnapshot.lastTeardownPreservedDirtyState,
            true,
            "Inactive reconciliation must request preserving teardown. Debug: \(postInactiveDebugSnapshot)"
        )
        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            }),
            "Inactive reconciliation must preserve dirty state before the trailing active pass runs. Debug: \(postInactiveDebugSnapshot)"
        )

        cloudSync.resumeSuspendedOwnerSnapshot()
        await newerRefresh.value
        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            }),
            "Reactivating the pipeline must not clear the retained obligation before its retry runs."
        )
        cloudSync.resumeBlockedPublish()
        await publishTask.value

        XCTAssertEqual(cloudSync.revokeCallCount, 0)
        XCTAssertTrue(cloudSync.remoteShareExists)
        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceID.namespaceKey
            }),
            "Every observed inactive lifecycle must fence an in-flight publish even when a newer refresh is queued."
        )
    }

    func testProjectionBuildUsesOneImmutableGoalSnapshotAcrossRateAwait() async throws {
        let ownerNamespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let cloudSync = StubFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: FamilyShareOwnerViewState(
                    namespaceID: ownerNamespaceID,
                    lifecycleState: .sharedActive,
                    participantCount: 0,
                    pendingParticipantCount: 0,
                    activeParticipantCount: 0,
                    revokedParticipantCount: 0,
                    failedParticipantCount: 0,
                    summaryCopy: "Shared goals are active.",
                    primaryActionCopy: "Manage Participants"
                ),
                participants: []
            )
        )
        let originalDeadline = Date(timeIntervalSince1970: 2_000_000_000)
        let originalModifiedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let goal = Goal(
            name: "Before await",
            currency: "USD",
            targetAmount: 10_000,
            deadline: originalDeadline,
            emoji: "🎯"
        )
        goal.lastModifiedDate = originalModifiedAt
        let bitcoin = Asset(currency: "BTC")
        let allocation = AssetAllocation(asset: bitcoin, goal: goal, amount: 1)
        bitcoin.allocations = [allocation]
        goal.allocations = [allocation]
        let rates = SuspendingFamilyShareExchangeRateService(rate: 10_000)
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            exchangeRateService: rates
        )

        let shareTask = Task { @MainActor in
            await coordinator.shareAllGoals([goal])
        }
        await rates.waitUntilFirstFetchStarts()

        goal.name = "After await"
        goal.emoji = "🚀"
        goal.targetAmount = 20_000
        goal.deadline = originalDeadline.addingTimeInterval(86_400)
        goal.lastModifiedDate = originalModifiedAt.addingTimeInterval(60)
        allocation.updateAmount(2)

        rates.resumeFirstFetch()
        await shareTask.value

        let payload = try XCTUnwrap(cloudSync.publishedPayloads.first)
        let projectedGoal = try XCTUnwrap(payload.goals.first)
        XCTAssertEqual(projectedGoal.goalName, "Before await")
        XCTAssertEqual(projectedGoal.goalEmoji, "🎯")
        XCTAssertEqual(projectedGoal.targetAmount, Decimal(10_000))
        XCTAssertEqual(projectedGoal.currentAmount, Decimal(10_000))
        XCTAssertEqual(projectedGoal.deadline, originalDeadline)
        XCTAssertEqual(projectedGoal.lastUpdatedAt, originalModifiedAt)
    }

    func testPublishedGoalStatusUsesFXConvertedProgress() async throws {
        let ownerNamespaceID = FamilyShareNamespaceID(ownerID: "test-owner", shareID: "test-share")
        let cloudSync = StubFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: FamilyShareOwnerViewState(
                    namespaceID: ownerNamespaceID,
                    lifecycleState: .sharedActive,
                    participantCount: 0,
                    pendingParticipantCount: 0,
                    activeParticipantCount: 0,
                    revokedParticipantCount: 0,
                    failedParticipantCount: 0,
                    summaryCopy: "Shared goals are active.",
                    primaryActionCopy: "Manage Participants"
                ),
                participants: []
            )
        )
        let goal = Goal(
            name: "One Bitcoin",
            currency: "USD",
            targetAmount: 10_000,
            deadline: Date().addingTimeInterval(86_400 * 90)
        )
        let bitcoin = Asset(currency: "BTC")
        let allocation = AssetAllocation(asset: bitcoin, goal: goal, amount: 1)
        bitcoin.allocations = [allocation]
        goal.allocations = [allocation]
        let rates = RecordingFamilyShareExchangeRateService(
            rates: ["BTC→USD": 10_000]
        )
        let coordinator = makeCoordinator(
            cloudSync: cloudSync,
            activeGoalsProvider: { [goal] },
            exchangeRateService: rates
        )

        XCTAssertEqual(goal.status, "Just Started")
        await coordinator.shareAllGoals([goal])

        let payload = try XCTUnwrap(cloudSync.publishedPayloads.first)
        XCTAssertEqual(payload.goals.first?.currentAmount, Decimal(10_000))
        XCTAssertEqual(payload.goals.first?.goalStatusRawValue, "Achieved")
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
        XCTAssertEqual(coordinator.sharedSections.map(\.ownerIdentity.displayName), ["Alex", "Jordan"])
        XCTAssertEqual(coordinator.sharedSections.first?.goals.count, 3)
        XCTAssertEqual(coordinator.sharedSections.last?.goals.count, 1)
    }

    func testSeedUnresolvedMultiOwnerScenarioDisambiguatesFallbackSectionHeaders() async {
        let coordinator = makeCoordinator()

        await coordinator.seedUITestScenario(.inviteeMultiOwnerUnresolved)

        XCTAssertEqual(coordinator.sharedSections.count, 2)
        XCTAssertEqual(coordinator.sharedSections.map(\.ownerIdentity.displayName), ["Family member 1", "Family member 2"])
        XCTAssertTrue(coordinator.sharedSections.allSatisfy(\.ownerIdentity.isFallback))
        XCTAssertEqual(coordinator.sharedSections.flatMap(\.goals).map(\.ownershipLine), Array(repeating: "Shared by family member · Read-only", count: 6))
    }

    func testRedesignedInviteeActiveFixtureUsesCanonicalSharedWithYouCopy() {
        let namespaceID = FamilyShareNamespaceID(ownerID: "owner", shareID: "share")
        let seed = FamilyShareTestSeeder.makeRedesignedMixedLifecycleSeed(namespaceID: namespaceID)

        XCTAssertEqual(seed.inviteeState?.titleCopy, "Shared with You")
        XCTAssertEqual(seed.inviteeState?.messageCopy, "Goals are grouped by owner and stay read-only.")
        XCTAssertEqual(seed.projectionPayload?.summaryTitle, "Shared with You")
        XCTAssertEqual(seed.projectionPayload?.summaryCopy, "Read-only shared goals grouped by owner.")
        XCTAssertEqual(seed.projectionPayload?.goals.map(\.goalStatusRawValue), ["active", "achieved", "expired"])
        XCTAssertEqual(seed.projectionPayload?.goals.map(\.summaryCopy), [
            "Goal 1 is still in progress.",
            "Goal 2 was achieved earlier this month.",
            "Goal 3 expired before full funding."
        ])
        XCTAssertEqual(seed.projectionPayload?.ownerSections.first?.inlineChipCopy, "")
        XCTAssertFalse((seed.projectionPayload?.summaryTitle ?? "").contains("Shared Goals"))
    }

    func testBlockedOwnerLabelIsNormalizedBeforeFixtureEmission() {
        let namespaceID = FamilyShareNamespaceID(ownerID: "owner", shareID: "share")
        let normalized = FamilyShareTestSeeder.normalizedOwnerDisplayName(from: "iPhone")
        let seed = FamilyShareTestSeeder.makeSeed(for: .inviteeBlockedOwner, namespaceID: namespaceID)
        let projection = seed.canonicalInviteeProjection

        XCTAssertEqual(normalized, "Family member")
        XCTAssertEqual(seed.ownerDisplayName, "Family member")
        XCTAssertEqual(seed.inviteeState?.ownerDisplayName, "Family member")
        XCTAssertEqual(seed.projectionPayload?.ownerDisplayName, "Family member")
        XCTAssertEqual(projection.sections.first?.goals.first?.ownershipLine, "Shared by family member · Read-only")
        XCTAssertFalse((seed.projectionPayload?.summaryTitle ?? "").contains("Shared Goals"))
    }

    func testRedesignedInviteeProjectionKeepsListAndDetailOwnerIdentityInSync() {
        let namespaceID = FamilyShareNamespaceID(ownerID: "owner", shareID: "share")
        let seed = FamilyShareTestSeeder.makeRedesignedMixedLifecycleSeed(namespaceID: namespaceID, ownerDisplayName: "Alex")
        let projection = seed.canonicalInviteeProjection

        XCTAssertEqual(seed.inviteeState?.ownerDisplayName, seed.projectionPayload?.ownerDisplayName)
        XCTAssertTrue(seed.projectionPayload?.goals.allSatisfy { $0.ownerDisplayName == "Alex" } == true)
        XCTAssertTrue(seed.projectionPayload?.ownerSections.allSatisfy { $0.ownerDisplayName == "Alex" } == true)
        XCTAssertEqual(seed.inviteeState?.titleCopy, "Shared with You")
        XCTAssertEqual(seed.projectionPayload?.summaryTitle, "Shared with You")
        XCTAssertEqual(projection.sections.first?.ownerIdentity.displayName, "Alex")
        XCTAssertEqual(projection.sections.first?.goals.first?.ownerIdentity.displayName, "Alex")
        XCTAssertEqual(projection.sections.first?.goals.first?.ownershipLine, "Shared by Alex · Read-only")
    }

    func testStaleFixturePreservesRowLifecycleWhenSectionIsUnhealthy() {
        let namespaceID = FamilyShareNamespaceID(ownerID: "owner", shareID: "share")
        let seed = FamilyShareTestSeeder.makeSeed(for: .inviteeStale, namespaceID: namespaceID)

        XCTAssertEqual(seed.inviteeState?.titleCopy, "Shared with You")
        XCTAssertEqual(seed.inviteeState?.primaryActionCopy, "Retry Refresh")
        XCTAssertEqual(seed.inviteeState?.messageCopy, "The shared cache may be out of date.")
        XCTAssertEqual(seed.projectionPayload?.goals.map(\.goalStatusRawValue), ["active", "achieved", "expired"])
        XCTAssertTrue(seed.projectionPayload?.goals.contains(where: { $0.summaryCopy.contains("achieved") }) == true)
        XCTAssertTrue(seed.projectionPayload?.goals.contains(where: { $0.summaryCopy.contains("expired") }) == true)
        let projection = seed.canonicalInviteeProjection
        XCTAssertEqual(projection.sections.first?.state, .stale)
        XCTAssertEqual(projection.sections.first?.goals.map(\.lifecycleState.displayTitle), ["Current", "Achieved", "Expired"])
        XCTAssertEqual(projection.sections.first?.goals.map(\.lifecycleState.defaultRowChipTitle), [nil, "Achieved", "Expired"])
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
                    summaryCopy: "1 participant has active read-only access.",
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

    func testScenePhaseActiveTriggersInviteeForegroundRefresh() async {
        let namespaceID = FamilyShareNamespaceID(ownerID: "invitee-owner", shareID: "invitee-share")
        let staleState = FamilyShareTestSeeder.makeSeed(for: .inviteeStale, namespaceID: namespaceID)
        let refreshedState = FamilyShareTestSeeder.makeSeed(for: .inviteeActive, namespaceID: namespaceID)
        let cloudSync = StubFamilyShareCloudSync(
            ownerSnapshot: FamilyShareOwnerShareSnapshot(
                ownerState: staleState.ownerState,
                participants: []
            ),
            refreshProjectionResult: refreshedState
        )
        let coordinator = makeCoordinator(cloudSync: cloudSync)

        try? coordinator.seedScenario(.inviteeStale, namespaceID: namespaceID)
        await coordinator.refreshAllState()

        coordinator.handleScenePhaseChange(.active)
        await flushAsyncWork()

        XCTAssertGreaterThanOrEqual(cloudSync.refreshProjectionCallCount, 1)
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
                titleCopy: "Shared with You",
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
                summaryCopy: "Read-only shared goals grouped by owner.",
                primaryActionCopy: "Manage Participants"
            ),
            inviteeState: FamilyShareInviteeViewState(
                namespaceID: namespaceID,
                ownerDisplayName: "Owner",
                lifecycleState: .active,
                goalCount: 1,
                lastUpdatedAt: Date(),
                asOfCopy: nil,
                titleCopy: "Shared with You",
                messageCopy: "Goals are grouped by owner and stay read-only.",
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
                summaryTitle: "Shared with You",
                summaryCopy: "Read-only shared goals grouped by owner.",
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

    func testLegacyInviteeCachePayloadIsCanonicalizedOnRehydrate() async throws {
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let stateProvider = DefaultFamilyShareStateProvider(registry: registry)

        let primaryNamespaceID = FamilyShareNamespaceID(ownerID: "legacy-owner-a", shareID: "legacy-share-a")
        let secondaryNamespaceID = FamilyShareNamespaceID(ownerID: "legacy-owner-b", shareID: "legacy-share-b")

        try seedLegacyInviteeCache(
            registry: registry,
            namespaceID: primaryNamespaceID,
            rawOwnerDisplayName: "iPhone"
        )
        try seedLegacyInviteeCache(
            registry: registry,
            namespaceID: secondaryNamespaceID,
            rawOwnerDisplayName: "iPad"
        )

        let primarySeed = try XCTUnwrap(registry.seededState(for: primaryNamespaceID))
        XCTAssertEqual(primarySeed.ownerDisplayName, "Family member")
        XCTAssertEqual(primarySeed.inviteeState?.titleCopy, "Shared with You")
        XCTAssertEqual(primarySeed.inviteeState?.ownerDisplayName, "Family member")
        XCTAssertEqual(primarySeed.projectionPayload?.summaryTitle, "Shared with You")
        XCTAssertEqual(primarySeed.projectionPayload?.summaryCopy, "Goals are grouped by owner and stay read-only.")
        XCTAssertEqual(primarySeed.projectionPayload?.ownerSections.first?.ownerDisplayName, "Family member")
        XCTAssertEqual(primarySeed.projectionPayload?.goals.first?.ownerDisplayName, "Family member")

        let projection = try await stateProvider.sharedInviteeProjection()
        XCTAssertEqual(projection.entryTitle, "Shared with You")
        XCTAssertEqual(projection.sections.map(\.ownerIdentity.displayName), ["Family member 1", "Family member 2"])
        XCTAssertTrue(
            projection.sections.flatMap(\.goals).allSatisfy { $0.ownershipLine == "Shared by family member · Read-only" }
        )
    }

    func testLegacyFreshnessMigrationDefaultsMissingMetadataConservatively() async throws {
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let migrationCoordinator = FamilyShareCacheMigrationCoordinator(registry: registry)
        let namespaceID = FamilyShareNamespaceID(ownerID: "legacy-owner", shareID: "legacy-share")
        let publishedAt = Date().addingTimeInterval(-7200)

        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: "iPhone",
                ownerState: FamilyShareOwnerViewState(
                    namespaceID: namespaceID,
                    lifecycleState: .sharedActive,
                    participantCount: 1,
                    pendingParticipantCount: 0,
                    activeParticipantCount: 1,
                    revokedParticipantCount: 0,
                    failedParticipantCount: 0,
                    summaryCopy: "Shared goals are read-only.",
                    primaryActionCopy: "Manage Participants"
                ),
                inviteeState: FamilyShareInviteeViewState(
                    namespaceID: namespaceID,
                    ownerDisplayName: "iPhone",
                    lifecycleState: .active,
                    goalCount: 1,
                    lastUpdatedAt: publishedAt,
                    asOfCopy: nil,
                    titleCopy: "Shared Goals",
                    messageCopy: "Shared goals are read-only.",
                    primaryActionCopy: "Retry",
                    isReadOnly: true
                ),
                projectionPayload: FamilyShareProjectionPayload(
                    namespaceID: namespaceID,
                    ownerDisplayName: "iPhone",
                    schemaVersion: 1,
                    projectionVersion: 2,
                    activeProjectionVersion: 2,
                    freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
                    lifecycleStateRawValue: FamilyShareOwnerLifecycleState.sharedActive.rawValue,
                    publishedAt: publishedAt,
                    lastReconciledAt: publishedAt,
                    lastRefreshAttemptAt: publishedAt,
                    lastRefreshErrorCode: nil,
                    lastRefreshErrorMessage: nil,
                    summaryTitle: "Shared Goals",
                    summaryCopy: "Shared goals are read-only.",
                    participantCount: 1,
                    pendingParticipantCount: 0,
                    revokedParticipantCount: 0,
                    goals: [],
                    ownerSections: []
                )
            )
        )

        let result = try await migrationCoordinator.ensureCompatible(namespaceID: namespaceID)
        let migratedState = try XCTUnwrap(registry.seededState(for: namespaceID))
        let migratedPayload = try XCTUnwrap(migratedState.projectionPayload)

        XCTAssertTrue(result.didMigrate)
        XCTAssertFalse(result.quarantined)
        XCTAssertEqual(migratedPayload.schemaVersion, FamilyShareCacheSchema.currentVersion)
        XCTAssertEqual(migratedPayload.rateSnapshotTimestamp, publishedAt)
        XCTAssertNil(migratedPayload.projectionServerTimestamp)
        XCTAssertNil(migratedPayload.contentHash)
        XCTAssertEqual(migratedPayload.freshnessStateRawValue, FamilyShareLifecycleState.active.rawValue)
        XCTAssertEqual(migratedState.inviteeState?.lifecycleState, .active)
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

    private func seedLegacyInviteeCache(
        registry: FamilyShareNamespaceRegistry,
        namespaceID: FamilyShareNamespaceID,
        rawOwnerDisplayName: String
    ) throws {
        let store = try registry.store(for: namespaceID)
        let context = store.mainContext

        context.insert(
            FamilySharedDatasetCache(
                namespaceID: namespaceID,
                ownerDisplayName: rawOwnerDisplayName,
                schemaVersion: FamilyShareCacheSchema.currentVersion,
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
                summaryCopy: "Shared goals are read-only.",
                participantCount: 1,
                pendingParticipantCount: 0,
                revokedParticipantCount: 0
            )
        )

        context.insert(
            FamilySharedGoalCache(
                namespaceID: namespaceID,
                ownerDisplayName: rawOwnerDisplayName,
                goalID: "legacy-goal-\(namespaceID.shareID)",
                goalName: "Legacy shared goal",
                goalEmoji: "🎯",
                currency: "EUR",
                targetAmount: 500,
                currentAmount: 200,
                progressRatio: 0.4,
                deadline: Date(),
                goalStatusRawValue: "active",
                forecastStateRawValue: "on_track",
                freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
                lastUpdatedAt: Date(),
                summaryCopy: "Shared by family",
                sortIndex: 0
            )
        )

        context.insert(
            FamilySharedOwnerSectionCache(
                namespaceID: namespaceID,
                ownerDisplayName: rawOwnerDisplayName,
                goalCount: 1,
                freshnessStateRawValue: FamilyShareLifecycleState.active.rawValue,
                lifecycleStateRawValue: FamilyShareOwnerLifecycleState.sharedActive.rawValue,
                sortIndex: 0,
                inlineChipCopy: "Shared by family"
            )
        )

        try context.save()
    }

    private func payloadWithoutRemoteTimestamp(
        from payload: FamilyShareProjectionPayload,
        contentHash: String
    ) -> FamilyShareProjectionPayload {
        FamilyShareProjectionPayload(
            namespaceID: payload.namespaceID,
            ownerDisplayName: payload.ownerDisplayName,
            schemaVersion: payload.schemaVersion,
            projectionVersion: payload.projectionVersion,
            activeProjectionVersion: payload.activeProjectionVersion,
            freshnessStateRawValue: payload.freshnessStateRawValue,
            lifecycleStateRawValue: payload.lifecycleStateRawValue,
            publishedAt: nil,
            lastReconciledAt: payload.lastReconciledAt,
            lastRefreshAttemptAt: payload.lastRefreshAttemptAt,
            lastRefreshErrorCode: payload.lastRefreshErrorCode,
            lastRefreshErrorMessage: payload.lastRefreshErrorMessage,
            summaryTitle: payload.summaryTitle,
            summaryCopy: payload.summaryCopy,
            participantCount: payload.participantCount,
            pendingParticipantCount: payload.pendingParticipantCount,
            revokedParticipantCount: payload.revokedParticipantCount,
            goals: payload.goals,
            ownerSections: payload.ownerSections,
            rateSnapshotTimestamp: payload.rateSnapshotTimestamp,
            projectionServerTimestamp: nil,
            contentHash: contentHash
        )
    }
}

private final class ManualFamilyShareRetryScheduler: FamilyShareScheduler, @unchecked Sendable {
    private struct ScheduledDebounce {
        let delay: TimeInterval
        let action: @Sendable () async -> Void
        let cancellable: ManualFamilyShareRetryCancellable
    }

    private nonisolated(unsafe) var scheduledDebounces: [ScheduledDebounce] = []

    nonisolated var lastDebounceDelay: TimeInterval? {
        scheduledDebounces.last(where: {
            $0.cancellable.cancelled == false
        })?.delay
    }

    nonisolated var lastDebounceAction: (@Sendable () async -> Void)? {
        scheduledDebounces.last(where: {
            $0.cancellable.cancelled == false
        })?.action
    }

    nonisolated var debounceScheduleCount: Int {
        scheduledDebounces.count
    }

    nonisolated func scheduleDebounce(
        delay: TimeInterval,
        action: @escaping @Sendable () async -> Void
    ) -> any FamilyShareCancellable {
        let cancellable = ManualFamilyShareRetryCancellable()
        scheduledDebounces.append(
            ScheduledDebounce(
                delay: delay,
                action: action,
                cancellable: cancellable
            )
        )
        return cancellable
    }

    nonisolated func schedulePeriodic(
        interval: TimeInterval,
        action: @escaping @Sendable () async -> Void
    ) -> any FamilyShareCancellable {
        ManualFamilyShareRetryCancellable()
    }

    @MainActor
    func runLatestActiveDebounce() async -> Bool {
        guard let scheduled = scheduledDebounces.last(where: {
            $0.cancellable.cancelled == false
        }) else {
            return false
        }
        scheduled.cancellable.cancel()
        await scheduled.action()
        return true
    }
}

private final class ManualFamilyShareRetryCancellable: FamilyShareCancellable, @unchecked Sendable {
    private(set) nonisolated(unsafe) var cancelled = false

    nonisolated init() {}

    nonisolated func cancel() {
        cancelled = true
    }
}

private final class ManualFamilyShareAutoRepublishScheduler: FamilyShareScheduler, @unchecked Sendable {
    private struct ScheduledDebounce {
        let action: @Sendable () async -> Void
        let cancellable: ManualFamilyShareAutoRepublishCancellable
    }

    private nonisolated(unsafe) var scheduledDebounces: [ScheduledDebounce] = []

    nonisolated func scheduleDebounce(
        delay: TimeInterval,
        action: @escaping @Sendable () async -> Void
    ) -> any FamilyShareCancellable {
        let cancellable = ManualFamilyShareAutoRepublishCancellable()
        scheduledDebounces.append(
            ScheduledDebounce(
                action: action,
                cancellable: cancellable
            )
        )
        return cancellable
    }

    nonisolated func schedulePeriodic(
        interval: TimeInterval,
        action: @escaping @Sendable () async -> Void
    ) -> any FamilyShareCancellable {
        ManualFamilyShareAutoRepublishCancellable()
    }

    @MainActor
    func runLatestActiveDebounce() async -> Bool {
        guard let scheduled = scheduledDebounces.last(where: {
            $0.cancellable.cancelled == false
        }) else {
            return false
        }
        scheduled.cancellable.cancel()
        await scheduled.action()
        return true
    }
}

private final class ManualFamilyShareAutoRepublishCancellable: FamilyShareCancellable, @unchecked Sendable {
    private(set) nonisolated(unsafe) var cancelled = false

    nonisolated init() {}

    nonisolated func cancel() {
        cancelled = true
    }
}

@MainActor
private final class BlockingLatePublishFamilyShareCloudSync: FamilyShareCloudSyncing {
    private(set) var ownerSnapshot: FamilyShareOwnerShareSnapshot
    private(set) var remoteRootPayload: FamilyShareProjectionPayload?
    private(set) var remoteGoalPayloads: [FamilyShareProjectedGoalPayload]
    private(set) var remoteShareExists = true
    private(set) var publishProjectionCallCount = 0
    private(set) var publishedPayloads: [FamilyShareProjectionPayload] = []
    private(set) var prepareShareCallCount = 0
    private(set) var revokeCallCount = 0
    private(set) var events: [String] = []

    private let failingRevokeCalls: Set<Int>
    private let suspendFirstRevoke: Bool
    private let suspendFirstPublish: Bool
    private var publishStarted = false
    private var publishContinuation: CheckedContinuation<Void, Never>?
    private var firstRevokeStarted = false
    private var firstRevokeContinuation: CheckedContinuation<Void, Never>?
    private var suspendedOwnerSnapshot: FamilyShareOwnerShareSnapshot?
    private var suspendedOwnerSnapshotStarted = false
    private var suspendedOwnerSnapshotContinuation: CheckedContinuation<Void, Never>?

    init(
        ownerSnapshot: FamilyShareOwnerShareSnapshot,
        remotePayload: FamilyShareProjectionPayload,
        failingRevokeCalls: Set<Int> = [],
        suspendFirstRevoke: Bool = false,
        suspendFirstPublish: Bool = true
    ) {
        self.ownerSnapshot = ownerSnapshot
        self.remoteRootPayload = remotePayload
        self.remoteGoalPayloads = remotePayload.goals
        self.failingRevokeCalls = failingRevokeCalls
        self.suspendFirstRevoke = suspendFirstRevoke
        self.suspendFirstPublish = suspendFirstPublish
    }

    func setOwnerSnapshot(_ snapshot: FamilyShareOwnerShareSnapshot) {
        ownerSnapshot = snapshot
    }

    func suspendNextOwnerSnapshot(
        returning snapshot: FamilyShareOwnerShareSnapshot
    ) {
        suspendedOwnerSnapshot = snapshot
        suspendedOwnerSnapshotStarted = false
    }

    func waitUntilSuspendedOwnerSnapshotStarts() async -> Bool {
        for _ in 0..<500 {
            if suspendedOwnerSnapshotStarted {
                return true
            }
            await Task.yield()
        }
        return false
    }

    func resumeSuspendedOwnerSnapshot() {
        let continuation = suspendedOwnerSnapshotContinuation
        suspendedOwnerSnapshotContinuation = nil
        continuation?.resume()
    }

    func publishProjection(_ payload: FamilyShareProjectionPayload) async throws {
        publishProjectionCallCount += 1
        publishedPayloads.append(payload)
        events.append("publish-started")
        if suspendFirstPublish, publishProjectionCallCount == 1 {
            publishStarted = true
            await withCheckedContinuation { continuation in
                publishContinuation = continuation
            }
        }
        remoteRootPayload = payload
        remoteGoalPayloads = payload.goals
        events.append("publish-committed")
    }

    func waitUntilPublishStarts() async {
        while publishStarted == false {
            await Task.yield()
        }
    }

    func resumeBlockedPublish() {
        let continuation = publishContinuation
        publishContinuation = nil
        continuation?.resume()
    }

    func waitUntilFirstRevokeStarts() async {
        while firstRevokeStarted == false {
            await Task.yield()
        }
    }

    func resumeFirstRevoke() {
        let continuation = firstRevokeContinuation
        firstRevokeContinuation = nil
        continuation?.resume()
    }

    func prepareShare(
        for request: FamilyShareCloudSharingPreparationRequest
    ) async throws -> (share: CKShare, containerProvider: FamilyShareContainerProvider) {
        prepareShareCallCount += 1
        remoteShareExists = true
        let zoneID = CKRecordZone.ID(
            zoneName: "blocking-late-publish-zone",
            ownerName: CKCurrentUserDefaultName
        )
        let rootRecord = CKRecord(
            recordType: "FamilyShareProjectionRoot",
            recordID: CKRecord.ID(recordName: "blocking-late-publish-root", zoneID: zoneID)
        )
        let share = CKShare(
            rootRecord: rootRecord,
            shareID: CKRecord.ID(recordName: "blocking-late-publish-share", zoneID: zoneID)
        )
        return (share, { CKContainer(identifier: "iCloud.com.cryptosavingstracker.tests") })
    }

    func acceptInvitation(
        metadata: CKShare.Metadata
    ) async throws -> FamilyShareInvitationMetadataSnapshot {
        FamilyShareInvitationMetadataSnapshot(metadata: metadata)
    }

    func ownerShareSnapshot(
        namespaceID: FamilyShareNamespaceID
    ) async throws -> FamilyShareOwnerShareSnapshot {
        if let suspendedOwnerSnapshot {
            self.suspendedOwnerSnapshot = nil
            suspendedOwnerSnapshotStarted = true
            await withCheckedContinuation { continuation in
                suspendedOwnerSnapshotContinuation = continuation
            }
            return suspendedOwnerSnapshot
        }
        return ownerSnapshot
    }

    func fetchAcceptedProjection(
        from snapshot: FamilyShareInvitationMetadataSnapshot
    ) async throws -> FamilyShareSeededNamespaceState {
        throw NSError(domain: "BlockingLatePublishFamilyShareCloudSync", code: 2)
    }

    func refreshProjection(
        namespaceID: FamilyShareNamespaceID
    ) async throws -> FamilyShareSeededNamespaceState {
        throw NSError(domain: "BlockingLatePublishFamilyShareCloudSync", code: 3)
    }

    func revoke(namespaceID: FamilyShareNamespaceID) async throws {
        revokeCallCount += 1
        let callNumber = revokeCallCount
        events.append("revoke")
        if suspendFirstRevoke, callNumber == 1 {
            firstRevokeStarted = true
            await withCheckedContinuation { continuation in
                firstRevokeContinuation = continuation
            }
        }
        if failingRevokeCalls.contains(callNumber) {
            throw NSError(
                domain: "BlockingLatePublishFamilyShareCloudSync",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Synthetic compensating revoke failure"]
            )
        }
        remoteRootPayload = nil
        remoteGoalPayloads = []
        remoteShareExists = false
        ownerSnapshot = FamilyShareOwnerShareSnapshot(
            ownerState: FamilyShareOwnerViewState(
                namespaceID: namespaceID,
                lifecycleState: .revoked,
                participantCount: 0,
                pendingParticipantCount: 0,
                activeParticipantCount: 0,
                revokedParticipantCount: 1,
                failedParticipantCount: 0,
                summaryCopy: "Access revoked.",
                primaryActionCopy: "Share with Family"
            ),
            participants: []
        )
    }
}

@MainActor
private final class StubFamilyShareCloudSync: FamilyShareCloudSyncing {
    private(set) var ownerSnapshot: FamilyShareOwnerShareSnapshot
    let refreshProjectionResult: FamilyShareSeededNamespaceState?
    private(set) var publishProjectionCallCount = 0
    private(set) var publishedPayloads: [FamilyShareProjectionPayload] = []
    private(set) var prepareShareCallCount = 0
    private(set) var containerResolutionCount = 0
    private(set) var refreshProjectionCallCount = 0
    private(set) var revokeCallCount = 0

    init(
        ownerSnapshot: FamilyShareOwnerShareSnapshot,
        refreshProjectionResult: FamilyShareSeededNamespaceState? = nil,
        publishedPayloads: [FamilyShareProjectionPayload] = []
    ) {
        self.ownerSnapshot = ownerSnapshot
        self.refreshProjectionResult = refreshProjectionResult
        self.publishedPayloads = publishedPayloads
    }

    func publishProjection(_ payload: FamilyShareProjectionPayload) async throws {
        publishProjectionCallCount += 1
        publishedPayloads.append(payload)
    }

    func prepareShare(for request: FamilyShareCloudSharingPreparationRequest) async throws
        -> (share: CKShare, containerProvider: FamilyShareContainerProvider) {
        prepareShareCallCount += 1
        let zoneID = CKRecordZone.ID(zoneName: "stub-zone", ownerName: CKCurrentUserDefaultName)
        let rootRecord = CKRecord(recordType: "FamilyShareProjectionRoot", recordID: CKRecord.ID(recordName: "stub-root", zoneID: zoneID))
        let share = CKShare(rootRecord: rootRecord, shareID: CKRecord.ID(recordName: "stub-share", zoneID: zoneID))
        // Preparing coordinator state must not resolve a client that requires iCloud entitlements.
        return (share, {
            self.containerResolutionCount += 1
            return CKContainer(identifier: "iCloud.com.cryptosavingstracker.tests")
        })
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
        refreshProjectionCallCount += 1
        if let refreshProjectionResult {
            return refreshProjectionResult
        }
        throw NSError(domain: "StubFamilyShareCloudSync", code: 3)
    }

    func revoke(namespaceID: FamilyShareNamespaceID) async throws {
        revokeCallCount += 1
        ownerSnapshot = FamilyShareOwnerShareSnapshot(
            ownerState: FamilyShareOwnerViewState(
                namespaceID: namespaceID,
                lifecycleState: .revoked,
                participantCount: ownerSnapshot.participantCount,
                pendingParticipantCount: 0,
                activeParticipantCount: 0,
                revokedParticipantCount: ownerSnapshot.participantCount,
                failedParticipantCount: 0,
                summaryCopy: "Access revoked.",
                primaryActionCopy: "Share with Family"
            ),
            participants: ownerSnapshot.participants.map { participant in
                FamilyShareParticipantSnapshot(
                    id: participant.id,
                    displayName: participant.displayName,
                    emailOrAlias: participant.emailOrAlias,
                    state: .revoked,
                    lastUpdatedAt: participant.lastUpdatedAt,
                    isCurrentUser: participant.isCurrentUser
                )
            }
        )
    }
}

private final class MissingFamilyShareExchangeRateService: ExchangeRateServiceProtocol {
    func fetchRate(from: String, to: String) async throws -> Double {
        throw NSError(
            domain: "MissingFamilyShareExchangeRateService",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing \(from)→\(to) exchange rate"]
        )
    }

    func hasValidConfiguration() -> Bool {
        true
    }

    func setOfflineMode(_ offline: Bool) {
    }

    func refreshRatesIfStale() async {
    }
}

private final class RecordingFamilyShareExchangeRateService: ExchangeRateServiceProtocol {
    private let rates: [String: Double]
    private(set) var fetchedPairs: Set<String> = []

    init(rates: [String: Double]) {
        self.rates = rates
    }

    func fetchRate(from: String, to: String) async throws -> Double {
        let pair = CurrencyPair.canonicalKey(from: from, to: to)
        fetchedPairs.insert(pair)
        guard let rate = rates[pair] else {
            throw ExchangeRateError.rateNotAvailable
        }
        return rate
    }

    func hasValidConfiguration() -> Bool {
        true
    }

    func setOfflineMode(_ offline: Bool) {
    }

    func refreshRatesIfStale() async {
    }
}

@MainActor
private final class SuspendingFamilyShareExchangeRateService: ExchangeRateServiceProtocol {
    private let rate: Double
    private var firstFetchContinuation: CheckedContinuation<Double, Error>?
    private var firstFetchStarted = false
    private var fetchCount = 0

    init(rate: Double) {
        self.rate = rate
    }

    func fetchRate(from: String, to: String) async throws -> Double {
        fetchCount += 1
        guard fetchCount == 1 else {
            return rate
        }
        return try await withCheckedThrowingContinuation { continuation in
            firstFetchContinuation = continuation
            firstFetchStarted = true
        }
    }

    func waitUntilFirstFetchStarts() async {
        while firstFetchStarted == false {
            await Task.yield()
        }
    }

    func resumeFirstFetch() {
        firstFetchContinuation?.resume(returning: rate)
        firstFetchContinuation = nil
    }

    func hasValidConfiguration() -> Bool {
        true
    }

    func setOfflineMode(_ offline: Bool) {
    }

    func refreshRatesIfStale() async {
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
