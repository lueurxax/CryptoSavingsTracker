import Foundation

/// Per-namespace debounced republish coordinator.
///
/// Lives inside `FamilyShareNamespaceActor` and owns:
/// - Dirty event stream and debounce/coalescing
/// - Reconciliation barrier checks
/// - Projection rebuild via `GoalProgressCalculator`
/// - Content hash computation and dedup
/// - Publish delegation to `FamilyShareProjectionPublishCoordinator`
/// - Exponential backoff on failure
/// - Dirty-state persistence for kill/relaunch survival
///
/// This coordinator is the **sole owner** of all publish-triggering actions
/// for its namespace. No component outside the namespace actor boundary
/// may trigger a publish.
actor FamilyShareProjectionAutoRepublishCoordinator {

    // MARK: - Dependencies

    private let namespaceKey: String
    private let clock: FamilyShareClock
    private let scheduler: FamilyShareScheduler
    private let policy: FamilyShareFreshnessPolicy
    private let contentHasher: FamilyShareContentHasher
    private let dirtyStateStore: FamilyShareDirtyStateStore
    private let calculator: GoalProgressCalculator
    private let rollout: FamilyShareRollout

    // MARK: - State

    private var isDirty = false
    private var pendingReasons: [FamilyShareProjectionDirtyReason] = []
    private var coalescedGoalIDs: Set<UUID> = []
    private var debounceHandle: (any FamilyShareCancellable)?
    private var isPublishInFlight = false
    private var trailingPublishNeeded = false
    private var failureCount = 0
    private var lastPublishedSnapshot: FamilyShareLastPublishedSnapshot?
    private var remoteChangeDateProvider: (() async -> Date?)?

    // MARK: - Init

    init(
        namespaceKey: String,
        clock: FamilyShareClock = SystemClock(),
        scheduler: FamilyShareScheduler = GCDScheduler(),
        policy: FamilyShareFreshnessPolicy = FamilyShareFreshnessPolicy(),
        contentHasher: FamilyShareContentHasher = FamilyShareContentHasher(),
        dirtyStateStore: FamilyShareDirtyStateStore = FamilyShareDirtyStateStore(),
        calculator: GoalProgressCalculator = GoalProgressCalculator(),
        rollout: FamilyShareRollout = .shared
    ) {
        self.namespaceKey = namespaceKey
        self.clock = clock
        self.scheduler = scheduler
        self.policy = policy
        self.contentHasher = contentHasher
        self.dirtyStateStore = dirtyStateStore
        self.calculator = calculator
        self.rollout = rollout
    }

    // MARK: - Public API

    /// Receive a dirty event and start the debounce/publish pipeline.
    func markDirty(reason: FamilyShareProjectionDirtyReason) {
        guard rollout.isFreshnessPipelineEnabled() else { return }
        guard !reason.isEmptyScopedMutation else { return }

        isDirty = true
        pendingReasons.append(reason)
        coalescedGoalIDs.formUnion(reason.affectedGoalIDs)

        // Persist dirty state for kill/relaunch survival
        dirtyStateStore.markDirty(namespaceKey: namespaceKey, reason: reason)

        // Determine debounce delay based on reason type
        let delay: TimeInterval
        switch reason {
        case .rateDrift:
            delay = FamilyShareFreshnessPolicy.rateDriftDebounce
        default:
            delay = FamilyShareFreshnessPolicy.mutationDebounce
        }

        // Cancel existing debounce timer and restart
        debounceHandle?.cancel()
        debounceHandle = scheduler.scheduleDebounce(delay: delay) { [weak self] in
            await self?.executePublish()
        }
    }

    /// Rehydrate dirty state from persistent store (called on launch).
    func rehydrateIfNeeded() {
        let entries = dirtyStateStore.dirtyNamespaces()
        guard entries.contains(where: { $0.namespaceKey == namespaceKey }) else { return }

        isDirty = true
        debounceHandle = scheduler.scheduleDebounce(delay: FamilyShareFreshnessPolicy.mutationDebounce) { [weak self] in
            await self?.executePublish()
        }
    }

    /// Teardown for rollback. Cancels all timers, discards pending events.
    func teardown() {
        let discardedDirtyEventCount = pendingReasons.count
        let activeTimerCount = debounceHandle == nil ? 0 : 1
        debounceHandle?.cancel()
        debounceHandle = nil
        isDirty = false
        pendingReasons.removeAll()
        coalescedGoalIDs.removeAll()
        trailingPublishNeeded = false
        dirtyStateStore.clearDirty(namespaceKey: namespaceKey)
        FamilyShareTelemetryTracker().track(.freshnessRollback, payload: [
            "namespace": namespaceKey,
            "discardedDirtyEventCount": "\(discardedDirtyEventCount)",
            "activeTimerCount": "\(activeTimerCount)"
        ])
    }

    // MARK: - Publish Pipeline

    private func executePublish() async {
        do {
            _ = try await executePublishSynchronously()
        } catch {
            // Backoff / retry scheduling is already handled inside
            // `executePublishSynchronously()`.
        }
    }

    /// The external publish action injected by the namespace actor.
    /// Executes the actual projection rebuild + CloudKit publish.
    private var publishAction: (() async throws -> FamilySharePublishReceipt?)?

    /// Configure the external publish action. Called once during namespace actor setup.
    func setPublishAction(_ action: @escaping () async throws -> FamilySharePublishReceipt?) {
        self.publishAction = action
    }

    /// Configure the last-known remote change date provider used by the
    /// reconciliation barrier. The provider is evaluated immediately before
    /// each publish attempt so lagging devices can suppress semantically older
    /// snapshots using the freshest known server timestamp.
    func setRemoteChangeDateProvider(_ provider: @escaping () async -> Date?) {
        self.remoteChangeDateProvider = provider
    }

    /// Force an immediate publish through the same coordinator boundary used by
    /// debounced dirty events. This is used for share lifecycle actions that
    /// must complete before continuing (for example initial share preparation)
    /// without reintroducing direct publish bypasses.
    @discardableResult
    func publishNow(reason: FamilyShareProjectionDirtyReason) async throws -> FamilySharePublishReceipt? {
        guard rollout.isFreshnessPipelineEnabled() else { return nil }
        guard !reason.isEmptyScopedMutation else { return nil }

        isDirty = true
        pendingReasons.append(reason)
        coalescedGoalIDs.formUnion(reason.affectedGoalIDs)
        dirtyStateStore.markDirty(namespaceKey: namespaceKey, reason: reason)
        debounceHandle?.cancel()
        debounceHandle = nil

        if isPublishInFlight {
            trailingPublishNeeded = true
            return nil
        }

        return try await executePublishSynchronously()
    }

    private enum PublishError: Error {
        case reconciliationTimeout
    }

    private func onPublishSuccess() {
        if failureCount > 0 {
            FamilyShareTelemetryTracker().track(.publishRecovered, payload: [
                "namespace": namespaceKey,
                "failureCount": "\(failureCount)"
            ])
        }
        isDirty = false
        failureCount = 0
        dirtyStateStore.clearDirty(namespaceKey: namespaceKey)

        FamilyShareTelemetryTracker().track(.autoPublishSucceeded, payload: [
            "namespace": namespaceKey
        ])
    }

    private func onPublishFailure(error: Error) {
        // Keep dirty for retry
        isDirty = true
        failureCount += 1

        let backoffDelay = policy.backoffDelay(forFailureCount: failureCount)

        FamilyShareTelemetryTracker().track(.autoPublishFailed, payload: [
            "namespace": namespaceKey,
            "errorCode": "\(error)",
            "failureCount": "\(failureCount)",
            "backoffSeconds": "\(backoffDelay)"
        ])

        FamilyShareTelemetryTracker().track(.publishBackoffEntered, payload: [
            "namespace": namespaceKey
        ])

        // Schedule retry with backoff
        debounceHandle?.cancel()
        debounceHandle = scheduler.scheduleDebounce(delay: backoffDelay) { [weak self] in
            await self?.executePublish()
        }
    }

    // MARK: - Helpers

    private func describeReason(_ reason: FamilyShareProjectionDirtyReason) -> String {
        switch reason {
        case .goalMutation: return "goalMutation"
        case .assetMutation: return "assetMutation"
        case .transactionMutation: return "transactionMutation"
        case .rateDrift: return "rateDrift"
        case .importOrRepair: return "importOrRepair"
        case .manualRefresh: return "manualRefresh"
        case .participantChange: return "participantChange"
        }
    }

    @discardableResult
    private func executePublishSynchronously() async throws -> FamilySharePublishReceipt? {
        guard rollout.isFreshnessPipelineEnabled() else { return nil }
        guard isDirty else { return nil }

        if isPublishInFlight {
            trailingPublishNeeded = true
            return nil
        }

        isPublishInFlight = true
        let reasons = pendingReasons
        let goalIDs = coalescedGoalIDs
        pendingReasons.removeAll()
        coalescedGoalIDs.removeAll()

        if reasons.count > 1 {
            FamilyShareTelemetryTracker().track(.autoPublishCoalesced, payload: [
                "namespace": namespaceKey,
                "coalescedCount": "\(reasons.count)"
            ])
        }

        FamilyShareTelemetryTracker().track(.autoPublishRequested, payload: [
            "namespace": namespaceKey,
            "reason": reasons.first.map { describeReason($0) } ?? "unknown",
            "goalCount": "\(goalIDs.count)"
        ])

        do {
            let receipt = try await performPublishWithReceipt()
            onPublishSuccess()
            isPublishInFlight = false
            if trailingPublishNeeded {
                trailingPublishNeeded = false
                if isDirty {
                    await executePublish()
                }
            }
            return receipt
        } catch {
            onPublishFailure(error: error)
            isPublishInFlight = false
            if trailingPublishNeeded {
                trailingPublishNeeded = false
                if isDirty {
                    await executePublish()
                }
            }
            throw error
        }
    }

    private func performPublishWithReceipt() async throws -> FamilySharePublishReceipt? {
        let barrier = FamilyShareReconciliationBarrier(policy: policy, clock: clock, scheduler: scheduler)
        let barrierResult = await barrier.checkBarrier(lastKnownRemoteChangeDate: await remoteChangeDateProvider?())

        switch barrierResult {
        case .satisfied(let waitDurationMs, let importCompleted):
            if waitDurationMs > 0 || importCompleted {
                FamilyShareTelemetryTracker().track(.reconciliationBarrierWaited, payload: [
                    "namespace": namespaceKey,
                    "waitDurationMs": "\(waitDurationMs)",
                    "importCompleted": importCompleted ? "true" : "false"
                ])
            }
        case .timedOut(let pendingAge, let waitDurationMs):
            FamilyShareTelemetryTracker().track(.reconciliationBarrierWaited, payload: [
                "namespace": namespaceKey,
                "waitDurationMs": "\(waitDurationMs)",
                "importCompleted": "false"
            ])
            FamilyShareTelemetryTracker().track(.publishSuppressedStaleLocal, payload: [
                "namespace": namespaceKey,
                "pendingImportAge": "\(pendingAge)"
            ])
            throw PublishError.reconciliationTimeout
        }

        guard let publishAction else {
            AppLog.warning("Auto-republish coordinator has no publish action configured", category: .api)
            return nil
        }

        let receipt = try await publishAction()
        if let receipt {
            FamilyShareTelemetryTracker().track(.rateSnapshotAgeAtPublish, payload: [
                "namespace": namespaceKey,
                "recordCount": "\(receipt.recordCount)"
            ])
        }
        return receipt
    }
}
