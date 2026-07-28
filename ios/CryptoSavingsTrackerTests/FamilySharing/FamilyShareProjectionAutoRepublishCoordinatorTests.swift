import XCTest
import CloudKit
@testable import CryptoSavingsTracker

@MainActor
final class FamilyShareProjectionAutoRepublishCoordinatorTests: XCTestCase {

    // MARK: - Test Helpers

    private final class TestScheduler: FamilyShareScheduler, @unchecked Sendable {
        private struct ScheduledDebounce {
            let delay: TimeInterval
            let action: @Sendable () async -> Void
            let cancellable: TestCancellable
        }

        private nonisolated(unsafe) var scheduledDebounces: [ScheduledDebounce] = []
        nonisolated(unsafe) var periodicAction: (@Sendable () async -> Void)?
        private let automaticallyRunImportFence: Bool

        nonisolated init(automaticallyRunImportFence: Bool = false) {
            self.automaticallyRunImportFence = automaticallyRunImportFence
        }

        nonisolated var lastDelay: TimeInterval? {
            scheduledDebounces.last(where: { $0.cancellable.cancelled == false })?.delay
        }

        nonisolated var lastAction: (@Sendable () async -> Void)? {
            scheduledDebounces.last(where: { $0.cancellable.cancelled == false })?.action
        }

        nonisolated var debounceScheduleCount: Int {
            scheduledDebounces.count
        }

        nonisolated func scheduleDebounce(
            delay: TimeInterval,
            action: @escaping @Sendable () async -> Void
        ) -> any FamilyShareCancellable {
            let cancellable = TestCancellable()
            scheduledDebounces.append(
                ScheduledDebounce(
                    delay: delay,
                    action: action,
                    cancellable: cancellable
                )
            )
            if automaticallyRunImportFence,
               delay == FamilyShareFreshnessPolicy.importFenceTimeout {
                Task {
                    await action()
                }
            }
            return cancellable
        }

        nonisolated func schedulePeriodic(
            interval: TimeInterval,
            action: @escaping @Sendable () async -> Void
        ) -> any FamilyShareCancellable {
            periodicAction = action
            return TestCancellable()
        }
    }

    private final class TestCancellable: FamilyShareCancellable, @unchecked Sendable {
        nonisolated(unsafe) var cancelled = false

        nonisolated init() {}

        nonisolated func cancel() {
            cancelled = true
        }
    }

    private struct CoordinatorHarness {
        let coordinator: FamilyShareProjectionAutoRepublishCoordinator
        let scheduler: TestScheduler
        let dirtyStateStore: FamilyShareDirtyStateStore
    }

    private func makeIsolatedDirtyStateStore(
        suitePrefix: String = "FamilyShareProjectionAutoRepublishCoordinatorTests"
    ) -> FamilyShareDirtyStateStore {
        let suiteName = "\(suitePrefix).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated UserDefaults suite \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return FamilyShareDirtyStateStore(defaults: defaults)
    }

    private func makeCoordinator(
        namespaceKey: String = "test-ns-\(UUID().uuidString)",
        scheduler: TestScheduler? = nil,
        dirtyStateStore: FamilyShareDirtyStateStore? = nil
    ) -> CoordinatorHarness {
        let scheduler = scheduler ?? TestScheduler()
        let dirtyStateStore = dirtyStateStore ?? makeIsolatedDirtyStateStore()
        return CoordinatorHarness(
            coordinator: FamilyShareProjectionAutoRepublishCoordinator(
                namespaceKey: namespaceKey,
                scheduler: scheduler,
                dirtyStateStore: dirtyStateStore
            ),
            scheduler: scheduler,
            dirtyStateStore: dirtyStateStore
        )
    }

    private func waitUntilStarted(
        _ action: SuspendingFamilySharePublishAction,
        timeout: TimeInterval = 2
    ) async {
        await fulfillment(of: [action.startedExpectation], timeout: timeout)
        XCTAssertTrue(action.hasStarted, "Suspended publish action did not start within \(timeout) seconds.")
    }

    // MARK: - Debounce/Coalescing

    func testMarkDirty_schedulesDebounce() async {
        let harness = makeCoordinator(namespaceKey: "test-ns")
        let coordinator = harness.coordinator
        let scheduler = harness.scheduler

        await coordinator.markDirty(reason: .assetMutation(goalIDs: []))

        XCTAssertNil(scheduler.lastAction)
        XCTAssertNil(scheduler.lastDelay)

        await coordinator.markDirty(reason: .goalMutation(goalIDs: [UUID()]))

        XCTAssertNotNil(scheduler.lastDelay)
        XCTAssertEqual(scheduler.lastDelay, FamilyShareFreshnessPolicy.mutationDebounce)
    }

    func testMarkDirty_rateDrift_usesLongerDebounce() async {
        let harness = makeCoordinator(namespaceKey: "test-ns")
        let coordinator = harness.coordinator
        let scheduler = harness.scheduler

        await coordinator.markDirty(reason: .rateDrift(goalIDs: [UUID()]))

        XCTAssertEqual(scheduler.lastDelay, FamilyShareFreshnessPolicy.rateDriftDebounce)
    }

    func testTeardown_clearsState() async {
        let harness = makeCoordinator(namespaceKey: "test-ns")
        let coordinator = harness.coordinator
        await coordinator.markDirty(reason: .manualRefresh)

        XCTAssertTrue(
            harness.dirtyStateStore.dirtyNamespaces().contains(where: { $0.namespaceKey == "test-ns" })
        )

        await coordinator.teardown()

        XCTAssertFalse(
            harness.dirtyStateStore.dirtyNamespaces().contains(where: { $0.namespaceKey == "test-ns" })
        )
    }

    func testTeardownRejectsSubsequentAutomaticEventsUntilReactivated() async {
        let harness = makeCoordinator(namespaceKey: "test-ns")
        let coordinator = harness.coordinator
        let scheduler = harness.scheduler

        await coordinator.teardown()
        await coordinator.markDirty(reason: .goalMutation(goalIDs: [UUID()]))

        XCTAssertNil(scheduler.lastAction)
        XCTAssertNil(scheduler.lastDelay)

        await coordinator.activateAutomaticPublishing()
        await coordinator.markDirty(reason: .goalMutation(goalIDs: [UUID()]))

        XCTAssertNotNil(scheduler.lastAction)
        XCTAssertEqual(scheduler.lastDelay, FamilyShareFreshnessPolicy.mutationDebounce)
    }

    func testAuthorizationSuppressedPublishRetainsDirtyForRetry() async throws {
        let namespaceKey = "suppressed-\(UUID().uuidString)"
        let harness = makeCoordinator(namespaceKey: namespaceKey)
        await harness.coordinator.setPublishAction {
            FamilyShareProjectionAutoPublishOutcome.suppressed
        }

        let receipt = try await harness.coordinator.publishNow(
            reason: .manualRefresh
        )

        XCTAssertNil(receipt)
        XCTAssertTrue(
            harness.dirtyStateStore.dirtyNamespaces().contains {
                $0.namespaceKey == namespaceKey
            },
            "Authorization suppression must not be treated as a successful dedup."
        )
        XCTAssertNotNil(
            harness.scheduler.lastAction,
            "A same-generation suppression must retain a bounded retry."
        )
    }

    func testDeduplicatedPublishClearsDirtyWithoutRetry() async throws {
        let namespaceKey = "deduplicated-\(UUID().uuidString)"
        let harness = makeCoordinator(namespaceKey: namespaceKey)
        await harness.coordinator.setPublishAction {
            FamilyShareProjectionAutoPublishOutcome.deduplicated
        }

        let receipt = try await harness.coordinator.publishNow(
            reason: .manualRefresh
        )

        XCTAssertNil(receipt)
        XCTAssertFalse(
            harness.dirtyStateStore.dirtyNamespaces().contains {
                $0.namespaceKey == namespaceKey
            }
        )
        XCTAssertNil(harness.scheduler.lastAction)
    }

    func testExplicitCatchUpAcknowledgementClearsOnlyItsProvisionalMarker() async {
        let namespaceKey = "explicit-marker-\(UUID().uuidString)"
        let harness = makeCoordinator(namespaceKey: namespaceKey)

        await harness.coordinator.durablyMarkExplicitCatchUp(
            token: 41,
            reason: .participantChange
        )
        XCTAssertTrue(
            harness.dirtyStateStore.dirtyNamespaces().contains {
                $0.namespaceKey == namespaceKey
            }
        )

        await harness.coordinator.acknowledgeExplicitCatchUp(token: 41)

        XCTAssertFalse(
            harness.dirtyStateStore.dirtyNamespaces().contains {
                $0.namespaceKey == namespaceKey
            }
        )
        XCTAssertNil(harness.scheduler.lastAction)
    }

    func testExplicitCatchUpAcknowledgementPreservesPreexistingAutomaticDirty() async {
        let namespaceKey = "explicit-marker-with-automatic-\(UUID().uuidString)"
        let harness = makeCoordinator(namespaceKey: namespaceKey)
        await harness.coordinator.markDirty(reason: .manualRefresh)
        let scheduleCountBeforeMarker = harness.scheduler.debounceScheduleCount
        await harness.coordinator.durablyMarkExplicitCatchUp(
            token: 42,
            reason: .participantChange
        )

        await harness.coordinator.acknowledgeExplicitCatchUp(token: 42)

        XCTAssertTrue(
            harness.dirtyStateStore.dirtyNamespaces().contains {
                $0.namespaceKey == namespaceKey
            },
            "Acknowledging an explicit marker must not erase an older automatic obligation."
        )
        XCTAssertEqual(
            harness.scheduler.debounceScheduleCount,
            scheduleCountBeforeMarker
        )
    }

    func testProvisionalExplicitMarkerDoesNotRehydrateAsAutomaticDirty() async {
        let namespaceKey = "provisional-explicit-\(UUID().uuidString)"
        let harness = makeCoordinator(namespaceKey: namespaceKey)

        await harness.coordinator.durablyMarkExplicitCatchUp(
            token: 51,
            reason: .participantChange
        )
        await harness.coordinator.rehydrateIfNeeded()

        XCTAssertNil(
            harness.scheduler.lastAction,
            "A live provisional marker must not schedule a redundant automatic publish."
        )
        await harness.coordinator.acknowledgeExplicitCatchUp(token: 51)
        XCTAssertFalse(
            harness.dirtyStateStore.dirtyNamespaces().contains {
                $0.namespaceKey == namespaceKey
            }
        )
    }

    func testSupersedingExplicitMarkersLeavesOnlyLatestTokenAuthoritative() async {
        let namespaceKey = "superseded-explicit-\(UUID().uuidString)"
        let harness = makeCoordinator(namespaceKey: namespaceKey)

        await harness.coordinator.durablyMarkExplicitCatchUp(
            token: 61,
            reason: .participantChange
        )
        await harness.coordinator.supersedeExplicitCatchUp(
            oldToken: 61,
            newToken: 62,
            reason: .participantChange
        )
        await harness.coordinator.supersedeExplicitCatchUp(
            oldToken: 62,
            newToken: 63,
            reason: .participantChange
        )

        await harness.coordinator.acknowledgeExplicitCatchUp(token: 61)
        await harness.coordinator.acknowledgeExplicitCatchUp(token: 62)
        XCTAssertTrue(
            harness.dirtyStateStore.dirtyNamespaces().contains {
                $0.namespaceKey == namespaceKey
            },
            "Superseded intents must not be able to clear the latest durable marker."
        )

        await harness.coordinator.acknowledgeExplicitCatchUp(token: 63)
        XCTAssertFalse(
            harness.dirtyStateStore.dirtyNamespaces().contains {
                $0.namespaceKey == namespaceKey
            }
        )
    }

    func testExplicitPublicationReceiptDoesNotFenceItsOwnImmediateCatchUp() async throws {
        let namespaceKey = "self-authored-remote-date-\(UUID().uuidString)"
        let scheduler = TestScheduler(automaticallyRunImportFence: true)
        let harness = makeCoordinator(
            namespaceKey: namespaceKey,
            scheduler: scheduler
        )
        let selfAuthoredTimestamp = Date()

        _ = try await harness.coordinator.publishExplicitIntent(
            reason: .participantChange
        ) {
            FamilySharePublishReceipt(
                serverTimestamp: selfAuthoredTimestamp,
                recordCount: 1
            )
        }
        await harness.coordinator.setRemoteChangeDateProvider {
            selfAuthoredTimestamp
        }
        var automaticPublishCount = 0
        await harness.coordinator.setPublishAction {
            automaticPublishCount += 1
            return FamilyShareProjectionAutoPublishOutcome.published(
                FamilySharePublishReceipt(
                    serverTimestamp: selfAuthoredTimestamp.addingTimeInterval(1),
                    recordCount: 1
                )
            )
        }

        _ = try await harness.coordinator.publishNow(reason: .manualRefresh)

        XCTAssertEqual(
            automaticPublishCount,
            1,
            "A locally acknowledged server timestamp must not be mistaken for an unimported remote mutation."
        )
    }

    func testTeardownDuringInFlightFailureDoesNotScheduleBackoffRetry() async {
        let namespaceKey = "test-ns-\(UUID().uuidString)"
        let dirtyStore = makeIsolatedDirtyStateStore(suitePrefix: "FamilyShareTeardownInFlightFailure")
        let harness = makeCoordinator(
            namespaceKey: namespaceKey,
            dirtyStateStore: dirtyStore
        )
        let coordinator = harness.coordinator
        let scheduler = harness.scheduler
        let publishAction = SuspendingFamilySharePublishAction()
        await coordinator.setPublishAction {
            try await publishAction.run()
            return FamilySharePublishReceipt(serverTimestamp: Date(), recordCount: 1)
        }

        let publishTask = Task {
            try await coordinator.publishNow(reason: .manualRefresh)
        }
        await waitUntilStarted(publishAction)
        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: { $0.namespaceKey == namespaceKey }),
            "The in-flight publish must be durable before teardown exercises the clearing path."
        )

        await coordinator.teardown()
        publishAction.fail()
        _ = await publishTask.result

        XCTAssertNil(
            scheduler.lastAction,
            "An in-flight failure that returns after teardown must not resurrect automatic publishing."
        )
        XCTAssertNil(scheduler.lastDelay)
        XCTAssertFalse(
            dirtyStore.dirtyNamespaces().contains(where: { $0.namespaceKey == namespaceKey }),
            "A non-preserving teardown must clear the durable dirty obligation."
        )

        let relaunchedHarness = makeCoordinator(
            namespaceKey: namespaceKey,
            dirtyStateStore: dirtyStore
        )
        await relaunchedHarness.coordinator.rehydrateIfNeeded()

        XCTAssertNil(
            relaunchedHarness.scheduler.lastAction,
            "A coordinator reconstructed after teardown must not rehydrate cleared dirty state."
        )
        XCTAssertEqual(relaunchedHarness.scheduler.debounceScheduleCount, 0)
    }

    func testPreservingTeardownDuringInFlightSuccessKeepsDirtyUntilReactivationPublishes() async throws {
        let dirtyStore = makeIsolatedDirtyStateStore(suitePrefix: "FamilySharePreservedLateSuccess")
        let namespaceKey = "test-ns-\(UUID().uuidString)"
        let suspendedPublish = SuspendingFamilySharePublishAction()
        let harness = makeCoordinator(
            namespaceKey: namespaceKey,
            dirtyStateStore: dirtyStore
        )
        let coordinator = harness.coordinator
        let scheduler = harness.scheduler
        await coordinator.setPublishAction {
            try await suspendedPublish.run()
            return FamilySharePublishReceipt(serverTimestamp: Date(), recordCount: 1)
        }

        let publishTask = Task {
            try await coordinator.publishNow(reason: .manualRefresh)
        }
        await waitUntilStarted(suspendedPublish)
        await coordinator.teardown(preservingDirtyState: true)
        suspendedPublish.succeed()
        _ = try await publishTask.value

        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceKey
            }),
            "A late success from the old lifecycle must not override a preserving teardown decision."
        )
        XCTAssertNil(scheduler.lastAction)

        var recoveryPublishCount = 0
        await coordinator.setPublishAction {
            recoveryPublishCount += 1
            return FamilySharePublishReceipt(serverTimestamp: Date(), recordCount: 1)
        }
        await coordinator.activateAutomaticPublishing()
        await coordinator.rehydrateIfNeeded()
        let recoveryAction = try XCTUnwrap(scheduler.lastAction)
        await recoveryAction()

        XCTAssertEqual(recoveryPublishCount, 1)
        XCTAssertFalse(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceKey
            })
        )
    }

    func testPreservingTeardownDuringInFlightFailureKeepsDirtyUntilReactivationPublishes() async throws {
        let dirtyStore = makeIsolatedDirtyStateStore(suitePrefix: "FamilySharePreservedLateFailure")
        let namespaceKey = "test-ns-\(UUID().uuidString)"
        let suspendedPublish = SuspendingFamilySharePublishAction()
        let harness = makeCoordinator(
            namespaceKey: namespaceKey,
            dirtyStateStore: dirtyStore
        )
        let coordinator = harness.coordinator
        let scheduler = harness.scheduler
        await coordinator.setPublishAction {
            try await suspendedPublish.run()
            return FamilySharePublishReceipt(serverTimestamp: Date(), recordCount: 1)
        }

        let publishTask = Task {
            try await coordinator.publishNow(reason: .manualRefresh)
        }
        await waitUntilStarted(suspendedPublish)
        await coordinator.teardown(preservingDirtyState: true)
        suspendedPublish.fail()
        _ = await publishTask.result

        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceKey
            }),
            "A late failure from the old lifecycle must not erase the preserving teardown obligation."
        )
        XCTAssertNil(
            scheduler.lastAction,
            "The inactive lifecycle must retain durability without scheduling work."
        )

        var recoveryPublishCount = 0
        await coordinator.setPublishAction {
            recoveryPublishCount += 1
            return FamilySharePublishReceipt(serverTimestamp: Date(), recordCount: 1)
        }
        await coordinator.activateAutomaticPublishing()
        await coordinator.rehydrateIfNeeded()
        let recoveryAction = try XCTUnwrap(scheduler.lastAction)
        await recoveryAction()

        XCTAssertEqual(recoveryPublishCount, 1)
        XCTAssertFalse(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceKey
            })
        )
    }

    func testFailedExplicitIntentPreservesPreexistingAutomaticDirtyStateForRetry() async throws {
        let dirtyStore = makeIsolatedDirtyStateStore(suitePrefix: "FamilyShareExplicitDirtyRestore")
        let namespaceKey = "test-ns-\(UUID().uuidString)"
        let harness = makeCoordinator(
            namespaceKey: namespaceKey,
            dirtyStateStore: dirtyStore
        )
        let coordinator = harness.coordinator
        let scheduler = harness.scheduler
        var automaticPublishAttempts = 0
        var automaticRetryMaySucceed = false
        await coordinator.setPublishAction {
            automaticPublishAttempts += 1
            guard automaticRetryMaySucceed else {
                throw NSError(
                    domain: "FamilyShareProjectionAutoRepublishCoordinatorTests",
                    code: 21,
                    userInfo: [NSLocalizedDescriptionKey: "Synthetic automatic publish failure"]
                )
            }
            return FamilySharePublishReceipt(serverTimestamp: Date(), recordCount: 1)
        }

        let preexistingGoalID = UUID()
        let duringExplicitGoalID = UUID()
        await coordinator.markDirty(
            reason: .goalMutation(goalIDs: [preexistingGoalID])
        )
        let scheduleCountBeforeExplicit = scheduler.debounceScheduleCount
        let explicitAction = SuspendingFamilySharePublishAction()

        let explicitTask = Task {
            try await coordinator.publishExplicitIntent(reason: .participantChange) {
                try await explicitAction.run()
                return FamilySharePublishReceipt(
                    serverTimestamp: Date(),
                    recordCount: 1
                )
            }
        }
        await waitUntilStarted(explicitAction)
        await coordinator.markDirty(
            reason: .goalMutation(goalIDs: [duringExplicitGoalID])
        )
        explicitAction.fail()
        let explicitResult = await explicitTask.result

        if case .success = explicitResult {
            XCTFail("The explicit action must fail")
        }

        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: { $0.namespaceKey == namespaceKey }),
            "A failed explicit action must not erase an older automatic dirty obligation."
        )

        await coordinator.activateAutomaticPublishing()
        XCTAssertGreaterThan(
            scheduler.debounceScheduleCount,
            scheduleCountBeforeExplicit,
            "Failed explicit action must create a new runnable automatic retry."
        )
        XCTAssertLessThanOrEqual(
            automaticPublishAttempts,
            1,
            "At most one immediate trailing attempt is allowed before the scheduled retry."
        )
        automaticRetryMaySucceed = true
        let retryAction = try XCTUnwrap(scheduler.lastAction)
        await retryAction()

        XCTAssertGreaterThanOrEqual(automaticPublishAttempts, 1)
        XCTAssertFalse(
            dirtyStore.dirtyNamespaces().contains(where: { $0.namespaceKey == namespaceKey }),
            "The restored dirty obligation may clear only after automatic retry succeeds."
        )
    }

    func testDirtyEventDuringAutomaticPublishSurvivesFirstSuccessAndPublishesNextBatch() async throws {
        let dirtyStore = makeIsolatedDirtyStateStore(suitePrefix: "FamilyShareAutomaticTrailingDirty")
        let namespaceKey = "test-ns-\(UUID().uuidString)"
        let firstPublish = SuspendingFamilySharePublishAction()
        var automaticPublishAttempts = 0
        let harness = makeCoordinator(
            namespaceKey: namespaceKey,
            dirtyStateStore: dirtyStore
        )
        let coordinator = harness.coordinator
        let scheduler = harness.scheduler
        await coordinator.setPublishAction {
            automaticPublishAttempts += 1
            if automaticPublishAttempts == 1 {
                try await firstPublish.run()
            }
            return FamilySharePublishReceipt(
                serverTimestamp: Date(),
                recordCount: 1
            )
        }

        await coordinator.markDirty(
            reason: .goalMutation(goalIDs: [UUID()])
        )
        let firstScheduledPublish = try XCTUnwrap(scheduler.lastAction)
        let firstPublishTask = Task {
            await firstScheduledPublish()
        }
        await waitUntilStarted(firstPublish)

        await coordinator.markDirty(
            reason: .goalMutation(goalIDs: [UUID()])
        )
        firstPublish.succeed()
        await firstPublishTask.value

        XCTAssertEqual(automaticPublishAttempts, 1)
        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceKey
            }),
            "Success for the first batch must not clear a mutation received while that batch was in flight."
        )

        let trailingPublish = try XCTUnwrap(
            scheduler.lastAction,
            "The mutation received in flight must retain a live follow-up publish."
        )
        await trailingPublish()

        XCTAssertEqual(automaticPublishAttempts, 2)
        XCTAssertFalse(
            dirtyStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceKey
            }),
            "Only the successful follow-up batch may clear the trailing dirty obligation."
        )
    }

    // MARK: - Rehydration

    func testRehydrateIfNeeded_withPersistedDirty_schedules() async {
        let dirtyStore = makeIsolatedDirtyStateStore(suitePrefix: "CoordinatorTests")
        dirtyStore.markDirty(namespaceKey: "test-ns", reason: .manualRefresh)

        let harness = makeCoordinator(
            namespaceKey: "test-ns",
            dirtyStateStore: dirtyStore
        )
        let coordinator = harness.coordinator
        let scheduler = harness.scheduler

        await coordinator.rehydrateIfNeeded()

        XCTAssertNotNil(scheduler.lastAction, "Should schedule a debounced publish after rehydration")
    }

    func testRehydrateIfNeeded_eventuallyPublishesAndClearsDirtyState() async throws {
        let dirtyStore = makeIsolatedDirtyStateStore(suitePrefix: "CoordinatorTestsRecovery")
        dirtyStore.markDirty(namespaceKey: "test-ns", reason: .manualRefresh)

        let harness = makeCoordinator(
            namespaceKey: "test-ns",
            dirtyStateStore: dirtyStore
        )
        let coordinator = harness.coordinator
        let scheduler = harness.scheduler

        await coordinator.setPublishAction {
            FamilySharePublishReceipt(serverTimestamp: Date(), recordCount: 2)
        }
        await coordinator.rehydrateIfNeeded()

        XCTAssertNotNil(scheduler.lastAction)
        await scheduler.lastAction?()

        XCTAssertFalse(
            dirtyStore.dirtyNamespaces().contains(where: { $0.namespaceKey == "test-ns" }),
            "Successful publish after rehydration should clear persisted dirty state"
        )
    }

    func testRemoteFailureKeepsAuthoritativeRegistryAndDirtyUntilRetryAcknowledges() async throws {
        let namespaceID = FamilyShareNamespaceID(ownerID: "owner-a", shareID: "share-a")
        let factory = FamilyShareNamespaceStoreFactory(environment: .preview)
        let registry = FamilyShareNamespaceRegistry(factory: factory)
        let initialFixture = FamilyShareTestSeeder.makeSeed(
            for: .ownerSharedActive,
            namespaceID: namespaceID
        )
        var payloadA = try XCTUnwrap(initialFixture.projectionPayload)
        payloadA.contentHash = "projection-a"
        try registry.seed(
            FamilyShareSeededNamespaceState(
                ownerDisplayName: initialFixture.ownerDisplayName,
                ownerState: initialFixture.ownerState,
                inviteeState: initialFixture.inviteeState,
                projectionPayload: payloadA
            )
        )

        var payloadB = payloadA
        payloadB.contentHash = "projection-b"
        let cloudSync = FailOnceFamilyShareCloudSync(remotePayload: payloadA)
        let publisher = DefaultFamilyShareProjectionPublisher(
            registry: registry,
            cloudSync: cloudSync
        )
        let dirtyStore = makeIsolatedDirtyStateStore(suitePrefix: "FamilySharePublishAckTests")
        let harness = makeCoordinator(
            namespaceKey: namespaceID.namespaceKey,
            dirtyStateStore: dirtyStore
        )
        let coordinator = harness.coordinator
        let scheduler = harness.scheduler
        await coordinator.setPublishAction {
            let result = try await publisher.publish(payloadB)
            return FamilySharePublishReceipt(
                serverTimestamp: result.projectionServerTimestamp ?? result.publishedAt,
                recordCount: result.goalCount + result.ownerSectionCount + 1
            )
        }

        do {
            _ = try await coordinator.publishNow(reason: .manualRefresh)
            XCTFail("The first remote publish must fail")
        } catch {
            // Expected: the transport rejected projection B before acknowledging it.
        }

        XCTAssertEqual(cloudSync.publishProjectionCallCount, 1)
        XCTAssertEqual(cloudSync.remotePayload?.contentHash, "projection-a")
        XCTAssertEqual(
            try registry.seededState(for: namespaceID)?.projectionPayload?.contentHash,
            "projection-a",
            "An unacknowledged projection must not replace the authoritative local registry entry."
        )
        XCTAssertTrue(
            dirtyStore.dirtyNamespaces().contains(where: { $0.namespaceKey == namespaceID.namespaceKey }),
            "A failed publish must remain dirty so it can be retried."
        )

        let retryAction = try XCTUnwrap(scheduler.lastAction)
        await retryAction()

        XCTAssertEqual(cloudSync.publishProjectionCallCount, 2)
        XCTAssertEqual(cloudSync.remotePayload?.contentHash, "projection-b")
        XCTAssertEqual(
            try registry.seededState(for: namespaceID)?.projectionPayload?.contentHash,
            "projection-b"
        )
        XCTAssertFalse(
            dirtyStore.dirtyNamespaces().contains(where: { $0.namespaceKey == namespaceID.namespaceKey }),
            "Dirty state may clear only after the remote transport acknowledges projection B."
        )
    }
}

@MainActor
private final class SuspendingFamilySharePublishAction {
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var hasStarted = false
    let startedExpectation: XCTestExpectation

    init() {
        startedExpectation = XCTestExpectation(description: "Suspended family-share publish started")
        startedExpectation.assertForOverFulfill = true
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            hasStarted = true
            startedExpectation.fulfill()
        }
    }

    func fail() {
        continuation?.resume(
            throwing: NSError(
                domain: "SuspendingFamilySharePublishAction",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Synthetic in-flight publish failure"]
            )
        )
        continuation = nil
    }

    func succeed() {
        continuation?.resume()
        continuation = nil
    }
}

private final class FailOnceFamilyShareCloudSync: FamilyShareCloudSyncing {
    private(set) var remotePayload: FamilyShareProjectionPayload?
    private(set) var publishProjectionCallCount = 0

    init(remotePayload: FamilyShareProjectionPayload) {
        self.remotePayload = remotePayload
    }

    func publishProjection(_ payload: FamilyShareProjectionPayload) async throws {
        publishProjectionCallCount += 1
        if publishProjectionCallCount == 1 {
            throw NSError(
                domain: "FailOnceFamilyShareCloudSync",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Synthetic remote rejection"]
            )
        }
        remotePayload = payload
    }

    func prepareShare(
        for request: FamilyShareCloudSharingPreparationRequest
    ) async throws -> (share: CKShare, container: CKContainer) {
        throw NSError(domain: "FailOnceFamilyShareCloudSync", code: 2)
    }

    func acceptInvitation(
        metadata: CKShare.Metadata
    ) async throws -> FamilyShareInvitationMetadataSnapshot {
        FamilyShareInvitationMetadataSnapshot(metadata: metadata)
    }

    func ownerShareSnapshot(
        namespaceID: FamilyShareNamespaceID
    ) async throws -> FamilyShareOwnerShareSnapshot {
        throw NSError(domain: "FailOnceFamilyShareCloudSync", code: 3)
    }

    func fetchAcceptedProjection(
        from snapshot: FamilyShareInvitationMetadataSnapshot
    ) async throws -> FamilyShareSeededNamespaceState {
        throw NSError(domain: "FailOnceFamilyShareCloudSync", code: 4)
    }

    func refreshProjection(
        namespaceID: FamilyShareNamespaceID
    ) async throws -> FamilyShareSeededNamespaceState {
        throw NSError(domain: "FailOnceFamilyShareCloudSync", code: 5)
    }

    func revoke(namespaceID: FamilyShareNamespaceID) async throws {
        remotePayload = nil
    }
}
