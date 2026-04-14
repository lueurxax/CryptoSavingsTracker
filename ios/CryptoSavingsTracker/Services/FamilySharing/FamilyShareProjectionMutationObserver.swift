import Foundation

/// Observes `PersistenceMutationServices` notifications and emits dirty events
/// into the auto-republish coordinator's input stream.
///
/// Gated by `FamilyShareRollout.isFreshnessPipelineEnabled()`. If the pipeline
/// is disabled, the observer is not registered and mutation notifications are ignored.
@MainActor
final class FamilyShareProjectionMutationObserver {

    private let rollout: FamilyShareRollout
    private var observer: NSObjectProtocol?
    private var onDirtyEvent: ((FamilyShareProjectionDirtyReason) -> Void)?

    init(rollout: FamilyShareRollout = .shared) {
        self.rollout = rollout
    }

    /// Start observing mutation notifications.
    /// - Parameter handler: Called with a dirty reason when a shared-goal mutation is detected.
    func start(handler: @escaping (FamilyShareProjectionDirtyReason) -> Void) {
        teardown()
        guard rollout.isFreshnessPipelineEnabled() else { return }
        onDirtyEvent = handler

        observer = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleNotification(notification)
            }
        }
    }

    /// Stop observing and release resources. Used during rollback teardown.
    func teardown() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        onDirtyEvent = nil
    }

    // MARK: - Private

    private func handleNotification(_ notification: Notification) {
        guard rollout.isFreshnessPipelineEnabled() else { return }

        let goalIDs: Set<UUID>
        if let ids = notification.userInfo?["affectedGoalIDs"] as? [UUID] {
            goalIDs = Set(ids)
        } else {
            goalIDs = []
        }

        // Determine dirty reason based on notification source context
        let explicitReason = notification.userInfo?["reason"] as? String
        let reason: FamilyShareProjectionDirtyReason
        switch explicitReason {
        case "assetMutation":
            reason = .assetMutation(goalIDs: goalIDs)
        case "transactionMutation":
            reason = .transactionMutation(goalIDs: goalIDs)
        case "importOrRepair":
            reason = .importOrRepair
        default:
            if notification.userInfo?["assetId"] != nil {
                reason = .assetMutation(goalIDs: goalIDs)
            } else if notification.userInfo?["transactionId"] != nil {
                reason = .transactionMutation(goalIDs: goalIDs)
            } else {
                reason = .goalMutation(goalIDs: goalIDs)
            }
        }
        onDirtyEvent?(reason)
    }
}
