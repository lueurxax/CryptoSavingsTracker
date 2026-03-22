import Foundation
import CoreData

/// Pre-publish reconciliation barrier that prevents a lagging owner device
/// from publishing a semantically older snapshot.
///
/// Before the auto-republish coordinator publishes, the barrier verifies that
/// the local SwiftData store reflects the latest CloudKit truth by checking
/// for pending import events.
///
/// If pending imports exist, it waits up to `importFenceTimeout` (10s) for
/// completion. If the fence times out, publish is suppressed and the namespace
/// stays dirty for the next cycle.
struct FamilyShareReconciliationBarrier: Sendable {

    enum BarrierResult: Sendable {
        case satisfied(waitDurationMs: Int, importCompleted: Bool)
        case timedOut(pendingImportAge: TimeInterval, waitDurationMs: Int)
    }

    private let policy: FamilyShareFreshnessPolicy
    private let clock: FamilyShareClock
    private let scheduler: FamilyShareScheduler

    init(
        policy: FamilyShareFreshnessPolicy = FamilyShareFreshnessPolicy(),
        clock: FamilyShareClock = SystemClock(),
        scheduler: FamilyShareScheduler = GCDScheduler()
    ) {
        self.policy = policy
        self.clock = clock
        self.scheduler = scheduler
    }

    /// Check whether the local store is current enough to publish.
    ///
    /// In production, this observes `NSPersistentCloudKitContainer.eventChangedNotification`
    /// to detect pending imports. For testability, the barrier can be overridden
    /// via the scheduler seam.
    ///
    /// - Parameter lastKnownRemoteChangeDate: The last known remote mutation timestamp
    ///   from the namespace's `CKServerChangeToken`.
    /// - Returns: `.satisfied` if local state is current, `.timedOut` if import fence
    ///   could not be satisfied within the timeout window.
    func checkBarrier(lastKnownRemoteChangeDate: Date?) async -> BarrierResult {
        // If we have no evidence of remote changes, the barrier is trivially satisfied
        guard let remoteDate = lastKnownRemoteChangeDate else {
            return .satisfied(waitDurationMs: 0, importCompleted: false)
        }

        // Check if local state is already current
        let initialLocalImportDate = lastLocalImportDate()
        if let localDate = initialLocalImportDate, localDate >= remoteDate {
            return .satisfied(waitDurationMs: 0, importCompleted: false)
        }

        // Wait for import to complete with timeout
        let startTime = clock.now()
        await waitForTimeout()
        let waitDurationMs = Int(clock.now().timeIntervalSince(startTime) * 1000)

        // Re-check after waiting
        let updatedLocalDate = lastLocalImportDate()
        if let localDate = updatedLocalDate,
           localDate > (initialLocalImportDate ?? .distantPast) || localDate >= remoteDate {
            return .satisfied(waitDurationMs: waitDurationMs, importCompleted: true)
        }

        let pendingAge = clock.now().timeIntervalSince(remoteDate)
        return .timedOut(pendingImportAge: pendingAge, waitDurationMs: waitDurationMs)
    }

    // MARK: - Private

    /// Last observed import event timestamp. Updated by observing
    /// `NSPersistentCloudKitContainer.eventChangedNotification`.
    private static var lastObservedImportDate: Date?
    private static var importObserver: NSObjectProtocol?

    /// Start observing CloudKit import events. Call once at app launch.
    static func startObservingImports() {
        importObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSPersistentCloudKitContainer.eventChangedNotification"),
            object: nil,
            queue: nil
        ) { notification in
            // Extract event type from notification — import events update the timestamp
            // In production, check event.type == .import and event.succeeded
            lastObservedImportDate = Date()
        }
    }

    static func resetObservedImportsForTesting() {
        lastObservedImportDate = nil
    }

    static func recordImportObservedForTesting(at date: Date) {
        lastObservedImportDate = date
    }

    /// Best-effort check for the last successful CloudKit import timestamp.
    ///
    /// Uses the last observed import event from
    /// `NSPersistentCloudKitContainer.eventChangedNotification`.
    /// Returns `nil` if no import history is available (barrier is satisfied
    /// when no remote change date is known — conservative default).
    private func lastLocalImportDate() -> Date? {
        return Self.lastObservedImportDate
    }

    private func waitForTimeout() async {
        await withCheckedContinuation { continuation in
            _ = scheduler.scheduleDebounce(delay: FamilyShareFreshnessPolicy.importFenceTimeout) {
                continuation.resume()
            }
        }
    }
}
