import Foundation
import Combine

/// Owns all invitee-side refresh triggers and freshness substate management.
///
/// Triggers refresh on:
/// - Foreground entry (with 30s cooldown)
/// - First visibility of "Shared with You" section
/// - User taps "Retry Refresh" / "Try Again"
/// - (v2) Push notification
///
/// Manages `FamilyShareFreshnessSubstate` transitions per namespace.
@MainActor
final class FamilyShareInviteeRefreshScheduler: ObservableObject {
    private enum RefreshTrigger: String {
        case foreground
        case firstVisibility
        case manual
    }

    // MARK: - Published State

    @Published private(set) var substateByNamespace: [String: FamilyShareFreshnessSubstate] = [:]
    @Published private(set) var lastCheckedByNamespace: [String: Date] = [:]

    // MARK: - Dependencies

    private let policy: FamilyShareFreshnessPolicy
    private let clock: FamilyShareClock
    private let scheduler: FamilyShareScheduler
    private let rollout: FamilyShareRollout

    private var lastRefreshByNamespace: [String: Date] = [:]
    private var autoDismissHandles: [String: any FamilyShareCancellable] = [:]
    private var refreshAction: ((String) async -> FamilyShareRefreshResult)?

    init(
        policy: FamilyShareFreshnessPolicy = FamilyShareFreshnessPolicy(),
        clock: FamilyShareClock = SystemClock(),
        scheduler: FamilyShareScheduler = GCDScheduler(),
        rollout: FamilyShareRollout = .shared
    ) {
        self.policy = policy
        self.clock = clock
        self.scheduler = scheduler
        self.rollout = rollout
    }

    func setRefreshAction(_ action: @escaping (String) async -> FamilyShareRefreshResult) {
        refreshAction = action
    }

    // MARK: - Triggers

    /// Called when the app enters foreground. Triggers refresh if cooldown allows.
    func onForegroundEntry(namespaceKeys: [String]) {
        guard rollout.isFreshnessPipelineEnabled() else { return }
        for key in namespaceKeys {
            if shouldRefresh(namespaceKey: key) {
                beginRefresh(namespaceKey: key, trigger: .foreground)
            }
        }
    }

    /// Called when the "Shared with You" section becomes visible for the first time.
    func onFirstVisibility(namespaceKey: String) {
        guard rollout.isFreshnessPipelineEnabled() else { return }
        if shouldRefresh(namespaceKey: namespaceKey) {
            beginRefresh(namespaceKey: namespaceKey, trigger: .firstVisibility)
        }
    }

    /// Called when the user taps "Retry Refresh" or "Try Again".
    func onManualRefresh(namespaceKey: String) {
        guard rollout.isFreshnessPipelineEnabled() else { return }
        let substate = substateByNamespace[namespaceKey] ?? .idle
        guard substate != .checking else { return }
        if let remainingCooldown = remainingCooldown(for: namespaceKey), remainingCooldown > 0 {
            setSubstate(.cooldown, for: namespaceKey)
            scheduleAutoDismiss(for: namespaceKey, delay: remainingCooldown)
            return
        }
        beginRefresh(namespaceKey: namespaceKey, trigger: .manual)
    }

    /// Report the result of a refresh attempt.
    func reportRefreshResult(_ result: FamilyShareRefreshResult, namespaceKey: String) {
        switch result {
        case .success(let updated):
            if updated {
                setSubstate(.refreshSucceeded, for: namespaceKey)
                lastCheckedByNamespace[namespaceKey] = clock.now()
                FamilyShareTelemetryTracker().track(.inviteeRefreshSucceeded, payload: [
                    "namespace": namespaceKey
                ])
                // Quickly transition to idle
                setSubstate(.idle, for: namespaceKey)
            } else {
                setSubstate(.checkedNoNewData, for: namespaceKey)
                lastCheckedByNamespace[namespaceKey] = clock.now()
                scheduleAutoDismiss(
                    for: namespaceKey,
                    delay: FamilyShareFreshnessPolicy.checkedNoNewDataAutoDismiss
                )
                FamilyShareTelemetryTracker().track(.inviteeCheckedNoNewData, payload: [
                    "namespace": namespaceKey
                ])
            }
        case .noNewData:
            setSubstate(.checkedNoNewData, for: namespaceKey)
            lastCheckedByNamespace[namespaceKey] = clock.now()
            FamilyShareTelemetryTracker().track(.inviteeRefreshSucceeded, payload: [
                "namespace": namespaceKey,
                "outcome": "no_new_data"
            ])
            scheduleAutoDismiss(
                for: namespaceKey,
                delay: FamilyShareFreshnessPolicy.checkedNoNewDataAutoDismiss
            )
        case .failure:
            setSubstate(.refreshFailed, for: namespaceKey)
            scheduleAutoDismiss(
                for: namespaceKey,
                delay: FamilyShareFreshnessPolicy.refreshFailedAutoDismiss
            )
            FamilyShareTelemetryTracker().track(.inviteeRefreshFailed, payload: [
                "namespace": namespaceKey
            ])
        }
    }

    /// Teardown for rollback.
    func teardown() {
        for handle in autoDismissHandles.values {
            handle.cancel()
        }
        autoDismissHandles.removeAll()
        substateByNamespace.removeAll()
        lastRefreshByNamespace.removeAll()
        lastCheckedByNamespace.removeAll()
        refreshAction = nil
    }

    // MARK: - Private

    private func shouldRefresh(namespaceKey: String) -> Bool {
        remainingCooldown(for: namespaceKey) == nil
    }

    private func beginRefresh(namespaceKey: String, trigger: RefreshTrigger) {
        setSubstate(.checking, for: namespaceKey)
        lastRefreshByNamespace[namespaceKey] = clock.now()

        FamilyShareTelemetryTracker().track(.inviteeForegroundRefreshRequested, payload: [
            "namespace": namespaceKey,
            "trigger": trigger.rawValue
        ])

        Task { [weak self] in
            guard let self else { return }
            let result = await self.refreshAction?(namespaceKey)
                ?? .failure(FamilyShareCloudKitError.sharedProjectionMissing)
            await MainActor.run {
                self.reportRefreshResult(result, namespaceKey: namespaceKey)
            }
        }
    }

    private func setSubstate(_ substate: FamilyShareFreshnessSubstate, for namespaceKey: String) {
        let previous = substateByNamespace[namespaceKey] ?? .idle
        substateByNamespace[namespaceKey] = substate

        if previous != substate {
            FamilyShareTelemetryTracker().track(.inviteeRefreshSubstateChanged, payload: [
                "namespace": namespaceKey,
                "fromSubstate": previous.rawValue,
                "toSubstate": substate.rawValue
            ])
        }
    }

    private func scheduleAutoDismiss(for namespaceKey: String, delay: TimeInterval) {
        autoDismissHandles[namespaceKey]?.cancel()
        autoDismissHandles[namespaceKey] = scheduler.scheduleDebounce(delay: delay) { [weak self] in
            guard let self else { return }
            await self.dismissAutoDismissState(for: namespaceKey)
        }
    }

    private func remainingCooldown(for namespaceKey: String) -> TimeInterval? {
        guard let lastRefresh = lastRefreshByNamespace[namespaceKey] else {
            return nil
        }
        let elapsed = clock.now().timeIntervalSince(lastRefresh)
        let remaining = FamilyShareFreshnessPolicy.refreshCooldown - elapsed
        return remaining > 0 ? remaining : nil
    }

    @MainActor
    private func dismissAutoDismissState(for namespaceKey: String) {
        setSubstate(.idle, for: namespaceKey)
    }
}
