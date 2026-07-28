import Foundation

struct FamilyShareAutoRepublishDebugSnapshot: Sendable {
    let isDirty: Bool
    let hasPersistedDirtyState: Bool
    let acceptsAutomaticEvents: Bool
    let teardownGeneration: Int
    let lastTeardownPreservedDirtyState: Bool?
    let lastTeardownCause: String?
    let lastDirtyClearCause: String?
}

enum FamilyShareProjectionAutoPublishOutcome: Sendable {
    case published(FamilySharePublishReceipt)
    case deduplicated
    case suppressed

    nonisolated var receipt: FamilySharePublishReceipt? {
        guard case .published(let receipt) = self else {
            return nil
        }
        return receipt
    }
}

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
    private var publishIdleWaiters: [CheckedContinuation<Void, Never>] = []
    private var trailingPublishNeeded = false
    private var failureCount = 0
    private var lastLocallyAcknowledgedServerTimestamp: Date?
    private var remoteChangeDateProvider: (() async -> Date?)?
    private var acceptsAutomaticEvents = true
    private var teardownGeneration = 0
    private var lastTeardownPreservedDirtyState: Bool?
    private var lastTeardownCause: String?
    private var lastDirtyClearCause: String?
    private var provisionalExplicitCatchUpTokens: Set<Int> = []
    private var provisionalCatchUpPreservesAutomaticDirtyState = false

    private struct SuspendedAutomaticDirtyState {
        let isDirty: Bool
        let pendingReasons: [FamilyShareProjectionDirtyReason]
        let coalescedGoalIDs: Set<UUID>
        let trailingPublishNeeded: Bool
        let failureCount: Int
        let wasPersisted: Bool
    }

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
        guard acceptsAutomaticEvents else { return }
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

    /// Persist an automatic publication obligation even while lifecycle teardown
    /// temporarily rejects observer events. Activation/rehydration will schedule it.
    func retainDirtyForLater(reason: FamilyShareProjectionDirtyReason) {
        guard rollout.isFreshnessPipelineEnabled() else { return }
        guard !reason.isEmptyScopedMutation else { return }

        isDirty = true
        pendingReasons.append(reason)
        coalescedGoalIDs.formUnion(reason.affectedGoalIDs)
        dirtyStateStore.markDirty(namespaceKey: namespaceKey, reason: reason)

        guard acceptsAutomaticEvents else { return }
        if isPublishInFlight {
            trailingPublishNeeded = true
            return
        }
        scheduleAutomaticRetry(
            delay: failureCount > 0
                ? policy.backoffDelay(forFailureCount: failureCount)
                : FamilyShareFreshnessPolicy.mutationDebounce
        )
    }

    /// Rehydrate dirty state from persistent store (called on launch).
    func rehydrateIfNeeded() {
        guard acceptsAutomaticEvents else { return }
        let entries = dirtyStateStore.dirtyNamespaces()
        guard entries.contains(where: { $0.namespaceKey == namespaceKey }) else { return }
        guard provisionalExplicitCatchUpTokens.isEmpty
                || provisionalCatchUpPreservesAutomaticDirtyState
                || isDirty
                || pendingReasons.isEmpty == false
                || trailingPublishNeeded else {
            // The durable namespace entry belongs only to an explicit action
            // that is still live in this process. Promoting it here would
            // schedule a redundant automatic publish after the explicit ACK.
            // After a process restart the token set is empty, so the same entry
            // is conservatively rehydrated as an automatic catch-up.
            return
        }

        isDirty = true
        debounceHandle = scheduler.scheduleDebounce(delay: FamilyShareFreshnessPolicy.mutationDebounce) { [weak self] in
            await self?.executePublish()
        }
    }

    /// Teardown for rollback. Explicit sharing may temporarily preserve automatic
    /// dirty state so a failed user action can restore the older obligation.
    func teardown(
        preservingDirtyState: Bool = false,
        cause: String = "direct"
    ) {
        teardownGeneration &+= 1
        lastTeardownPreservedDirtyState = preservingDirtyState
        lastTeardownCause = cause
        let discardedDirtyEventCount = pendingReasons.count
        let activeTimerCount = debounceHandle == nil ? 0 : 1
        debounceHandle?.cancel()
        debounceHandle = nil
        if preservingDirtyState == false {
            isDirty = false
            pendingReasons.removeAll()
            coalescedGoalIDs.removeAll()
            trailingPublishNeeded = false
            failureCount = 0
            provisionalExplicitCatchUpTokens.removeAll()
            provisionalCatchUpPreservesAutomaticDirtyState = false
            lastLocallyAcknowledgedServerTimestamp = nil
            dirtyStateStore.clearDirty(namespaceKey: namespaceKey)
            lastDirtyClearCause = "teardown"
        }
        acceptsAutomaticEvents = false
        publishAction = nil
        remoteChangeDateProvider = nil
        FamilyShareTelemetryTracker().track(.freshnessRollback, payload: [
            "namespace": namespaceKey,
            "discardedDirtyEventCount": "\(discardedDirtyEventCount)",
            "activeTimerCount": "\(activeTimerCount)"
        ])
    }

    /// Re-enable automatic events after an owner enters an active sharing lifecycle.
    func activateAutomaticPublishing() {
        acceptsAutomaticEvents = true
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
    private var publishAction: (() async throws -> FamilyShareProjectionAutoPublishOutcome)?

    /// Configure the external publish action. Called once during namespace actor setup.
    func setPublishAction(
        _ action: @escaping () async throws -> FamilyShareProjectionAutoPublishOutcome
    ) {
        self.publishAction = action
    }

    func setPublishAction(
        _ action: @escaping () async throws -> FamilySharePublishReceipt?
    ) {
        self.publishAction = {
            if let receipt = try await action() {
                return .published(receipt)
            }
            return .deduplicated
        }
    }

    /// Persist a crash-safe explicit-intent marker without adding it to the
    /// automatic batch. A matching explicit success can acknowledge only this
    /// marker while unrelated automatic obligations remain durable.
    func durablyMarkExplicitCatchUp(
        token: Int,
        reason: FamilyShareProjectionDirtyReason
    ) {
        guard provisionalExplicitCatchUpTokens.contains(token) == false else {
            return
        }
        let hasPersistedDirtyState = dirtyStateStore.dirtyNamespaces().contains {
            $0.namespaceKey == namespaceKey
        }
        let hasPreexistingAutomaticDirtyState =
            isDirty
            || pendingReasons.isEmpty == false
            || trailingPublishNeeded
            || (
                hasPersistedDirtyState
                && provisionalExplicitCatchUpTokens.isEmpty
            )
        provisionalCatchUpPreservesAutomaticDirtyState =
            provisionalCatchUpPreservesAutomaticDirtyState
            || hasPreexistingAutomaticDirtyState
        provisionalExplicitCatchUpTokens.insert(token)
        dirtyStateStore.markDirty(namespaceKey: namespaceKey, reason: reason)
    }

    /// Atomically transfer a still-live explicit obligation to a newer FIFO
    /// intent. The namespace marker remains present for crash safety throughout
    /// the handoff, and acknowledgements for superseded tokens become no-ops.
    func supersedeExplicitCatchUp(
        oldToken: Int,
        newToken: Int,
        reason: FamilyShareProjectionDirtyReason
    ) {
        guard oldToken != newToken else {
            durablyMarkExplicitCatchUp(token: newToken, reason: reason)
            return
        }
        guard provisionalExplicitCatchUpTokens.remove(oldToken) != nil else {
            durablyMarkExplicitCatchUp(token: newToken, reason: reason)
            return
        }
        provisionalExplicitCatchUpTokens.insert(newToken)
        dirtyStateStore.markDirty(namespaceKey: namespaceKey, reason: reason)
    }

    /// Remove one satisfied explicit marker. Clear the durable namespace marker
    /// only when no automatic or other explicit obligation remains.
    func acknowledgeExplicitCatchUp(token: Int) {
        guard provisionalExplicitCatchUpTokens.remove(token) != nil else {
            return
        }
        guard provisionalExplicitCatchUpTokens.isEmpty else {
            return
        }

        let mustPreserveAutomaticDirtyState =
            provisionalCatchUpPreservesAutomaticDirtyState
            || isDirty
            || pendingReasons.isEmpty == false
            || trailingPublishNeeded
        provisionalCatchUpPreservesAutomaticDirtyState = false
        if mustPreserveAutomaticDirtyState {
            dirtyStateStore.markDirty(
                namespaceKey: namespaceKey,
                reason: pendingReasons.first ?? .manualRefresh
            )
        } else {
            dirtyStateStore.clearDirty(namespaceKey: namespaceKey)
            lastDirtyClearCause = "explicitCatchUpAcknowledged"
        }
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

    /// Executes a user-authored share intent after every older publish settles.
    ///
    /// Explicit intents are already serialized by the acceptance coordinator and
    /// carry their own immutable goal snapshot. They must not be coalesced with
    /// automatic dirty events or rejected by the remote-import reconciliation
    /// fence, which protects background auto-publishing rather than direct user
    /// actions.
    func publishExplicitIntent(
        reason: FamilyShareProjectionDirtyReason,
        action: @escaping () async throws -> FamilySharePublishReceipt?
    ) async throws -> FamilySharePublishReceipt? {
        guard rollout.isFreshnessPipelineEnabled() else { return nil }
        guard !reason.isEmptyScopedMutation else { return nil }

        await waitUntilPublishIsIdle()
        let executionTeardownGeneration = teardownGeneration
        let suspendedAutomaticState = SuspendedAutomaticDirtyState(
            isDirty: isDirty,
            pendingReasons: pendingReasons,
            coalescedGoalIDs: coalescedGoalIDs,
            trailingPublishNeeded: trailingPublishNeeded,
            failureCount: failureCount,
            wasPersisted: dirtyStateStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceKey
            })
        )
        debounceHandle?.cancel()
        debounceHandle = nil
        isDirty = false
        pendingReasons.removeAll()
        coalescedGoalIDs.removeAll()
        trailingPublishNeeded = false
        failureCount = 0
        if suspendedAutomaticState.wasPersisted == false {
            dirtyStateStore.clearDirty(namespaceKey: namespaceKey)
            lastDirtyClearCause = "explicitIsolation"
        }
        isPublishInFlight = true

        FamilyShareTelemetryTracker().track(.autoPublishRequested, payload: [
            "namespace": namespaceKey,
            "reason": describeReason(reason),
            "goalCount": "\(reason.affectedGoalIDs.count)"
        ])

        do {
            let receipt = try await action()
            if executionTeardownGeneration == teardownGeneration {
                if let receipt {
                    recordLocallyAcknowledgedServerTimestamp(
                        receipt.serverTimestamp
                    )
                }
                FamilyShareTelemetryTracker().track(.autoPublishSucceeded, payload: [
                    "namespace": namespaceKey
                ])
            }
            finishPublish()
            await executeTrailingAutomaticPublishIfNeeded()
            return receipt
        } catch {
            finishPublish()
            if executionTeardownGeneration == teardownGeneration {
                restoreAutomaticDirtyState(suspendedAutomaticState)
                if acceptsAutomaticEvents, isDirty {
                    scheduleAutomaticRetry(
                        delay: failureCount > 0
                            ? policy.backoffDelay(forFailureCount: failureCount)
                            : FamilyShareFreshnessPolicy.mutationDebounce
                    )
                }
            }
            throw error
        }
    }

    private enum PublishError: Error {
        case reconciliationTimeout
        case missingPublishAction
    }

    private func onPublishSuccess() {
        if failureCount > 0 {
            FamilyShareTelemetryTracker().track(.publishRecovered, payload: [
                "namespace": namespaceKey,
                "failureCount": "\(failureCount)"
            ])
        }
        let hasTrailingDirtyState = pendingReasons.isEmpty == false
        isDirty = hasTrailingDirtyState
        failureCount = 0
        if let trailingReason = pendingReasons.first {
            dirtyStateStore.markDirty(
                namespaceKey: namespaceKey,
                reason: trailingReason
            )
        } else {
            dirtyStateStore.clearDirty(namespaceKey: namespaceKey)
            lastDirtyClearCause = "publishSuccess"
        }

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

    private func onPublishSuppressed(reason: FamilyShareProjectionDirtyReason) {
        isDirty = true
        failureCount += 1
        dirtyStateStore.markDirty(namespaceKey: namespaceKey, reason: reason)
        guard acceptsAutomaticEvents else {
            return
        }
        scheduleAutomaticRetry(
            delay: policy.backoffDelay(forFailureCount: failureCount)
        )
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

        let executionTeardownGeneration = teardownGeneration
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
            let outcome = try await performPublish()
            if executionTeardownGeneration == teardownGeneration {
                if let receipt = outcome.receipt {
                    recordLocallyAcknowledgedServerTimestamp(
                        receipt.serverTimestamp
                    )
                }
                switch outcome {
                case .published, .deduplicated:
                    onPublishSuccess()
                case .suppressed:
                    onPublishSuppressed(
                        reason: reasons.first ?? .manualRefresh
                    )
                }
            }
            finishPublish()
            await executeTrailingAutomaticPublishIfNeeded()
            return outcome.receipt
        } catch {
            if executionTeardownGeneration == teardownGeneration {
                onPublishFailure(error: error)
            }
            // A generation mismatch means teardown already chose whether this
            // obligation must be cleared (revoke/rollback) or retained
            // (temporary inactive lifecycle). A late result from the old
            // generation must not override that decision in either direction.
            finishPublish()
            await executeTrailingAutomaticPublishIfNeeded()
            throw error
        }
    }

    private func waitUntilPublishIsIdle() async {
        while isPublishInFlight {
            await withCheckedContinuation { continuation in
                publishIdleWaiters.append(continuation)
            }
        }
    }

    private func finishPublish() {
        isPublishInFlight = false
        let waiters = publishIdleWaiters
        publishIdleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func executeTrailingAutomaticPublishIfNeeded() async {
        guard trailingPublishNeeded else {
            return
        }
        trailingPublishNeeded = false
        guard acceptsAutomaticEvents, isDirty else {
            return
        }
        await executePublish()
    }

    private func restoreAutomaticDirtyState(
        _ state: SuspendedAutomaticDirtyState
    ) {
        let dirtyAddedDuringExplicit = isDirty
        let reasonsAddedDuringExplicit = pendingReasons
        let goalIDsAddedDuringExplicit = coalescedGoalIDs
        let trailingAddedDuringExplicit = trailingPublishNeeded
        let failureCountDuringExplicit = failureCount

        isDirty = state.isDirty || state.wasPersisted || dirtyAddedDuringExplicit
        pendingReasons = state.pendingReasons + reasonsAddedDuringExplicit
        coalescedGoalIDs = state.coalescedGoalIDs.union(goalIDsAddedDuringExplicit)
        trailingPublishNeeded = state.trailingPublishNeeded
            || trailingAddedDuringExplicit
            || dirtyAddedDuringExplicit
        failureCount = max(state.failureCount, failureCountDuringExplicit)

        guard isDirty else { return }
        let persistenceReason = pendingReasons.first
            ?? (coalescedGoalIDs.isEmpty
                ? .manualRefresh
                : .goalMutation(goalIDs: coalescedGoalIDs))
        dirtyStateStore.markDirty(
            namespaceKey: namespaceKey,
            reason: persistenceReason
        )
    }

    private func scheduleAutomaticRetry(delay: TimeInterval) {
        debounceHandle?.cancel()
        debounceHandle = scheduler.scheduleDebounce(delay: delay) { [weak self] in
            await self?.executePublish()
        }
    }

    private func recordLocallyAcknowledgedServerTimestamp(_ timestamp: Date) {
        lastLocallyAcknowledgedServerTimestamp = max(
            lastLocallyAcknowledgedServerTimestamp ?? .distantPast,
            timestamp
        )
    }

    func debugSnapshotForTesting() -> FamilyShareAutoRepublishDebugSnapshot {
        FamilyShareAutoRepublishDebugSnapshot(
            isDirty: isDirty,
            hasPersistedDirtyState: dirtyStateStore.dirtyNamespaces().contains(where: {
                $0.namespaceKey == namespaceKey
            }),
            acceptsAutomaticEvents: acceptsAutomaticEvents,
            teardownGeneration: teardownGeneration,
            lastTeardownPreservedDirtyState: lastTeardownPreservedDirtyState,
            lastTeardownCause: lastTeardownCause,
            lastDirtyClearCause: lastDirtyClearCause
        )
    }

    private func performPublish() async throws -> FamilyShareProjectionAutoPublishOutcome {
        let barrier = FamilyShareReconciliationBarrier(policy: policy, clock: clock, scheduler: scheduler)
        let lastKnownRemoteChangeDate = await remoteChangeDateProvider?()
        let unresolvedRemoteChangeDate: Date?
        if let lastKnownRemoteChangeDate,
           let lastLocallyAcknowledgedServerTimestamp,
           lastKnownRemoteChangeDate <= lastLocallyAcknowledgedServerTimestamp {
            unresolvedRemoteChangeDate = nil
        } else {
            unresolvedRemoteChangeDate = lastKnownRemoteChangeDate
        }
        let barrierResult = await barrier.checkBarrier(
            lastKnownRemoteChangeDate: unresolvedRemoteChangeDate
        )

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
            throw PublishError.missingPublishAction
        }

        let outcome = try await publishAction()
        if let receipt = outcome.receipt {
            FamilyShareTelemetryTracker().track(.rateSnapshotAgeAtPublish, payload: [
                "namespace": namespaceKey,
                "recordCount": "\(receipt.recordCount)"
            ])
        }
        return outcome
    }
}
