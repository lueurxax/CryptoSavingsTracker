import Foundation

// MARK: - Currency Pair

/// Represents a directional currency conversion pair (e.g., BTC -> USD).
struct CurrencyPair: Hashable, Sendable, Codable {
    let from: String
    let to: String

    init(from: String, to: String) {
        self.from = from.uppercased()
        self.to = to.uppercased()
    }
}

// MARK: - Clock Seam

/// Abstraction over `Date()` for deterministic testing.
protocol FamilyShareClock: Sendable {
    func now() -> Date
}

/// Production clock returning the system time.
struct SystemClock: FamilyShareClock, Sendable {
    func now() -> Date { Date() }
}

// MARK: - Cancellable

/// Cancellation handle returned by scheduler operations.
protocol FamilyShareCancellable: Sendable {
    func cancel()
}

// MARK: - Scheduler Seam

/// Abstraction over timers and delayed execution for deterministic testing.
protocol FamilyShareScheduler: Sendable {
    func scheduleDebounce(delay: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable
    func schedulePeriodic(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable
}

/// Production scheduler using Swift concurrency `Task.sleep`.
struct GCDScheduler: FamilyShareScheduler, Sendable {

    func scheduleDebounce(delay: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable {
        let task = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await action()
        }
        return TaskCancellable(task: task)
    }

    func schedulePeriodic(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable {
        let task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await action()
            }
        }
        return TaskCancellable(task: task)
    }
}

/// Wraps a `Task` as a `FamilyShareCancellable`.
struct TaskCancellable: FamilyShareCancellable, Sendable {
    let task: Task<Void, Never>
    func cancel() { task.cancel() }
}

// MARK: - Publish Transport Seam

/// Receipt returned after a successful projection publish.
struct FamilySharePublishReceipt: Sendable {
    let serverTimestamp: Date
    let recordCount: Int
}

/// Abstraction over CloudKit projection publishing for testing.
protocol FamilySharePublishTransport: Sendable {
    func publish(payload: FamilyShareProjectionPayload, namespaceID: FamilyShareNamespaceID) async throws -> FamilySharePublishReceipt
}

// MARK: - Rate Refresh Source Seam

/// Event emitted when exchange rates are refreshed.
struct RateRefreshEvent: Sendable {
    let refreshedPairs: Set<CurrencyPair>
    let rateSnapshotTimestamp: Date
    let rates: [CurrencyPair: Decimal]
}

/// Abstraction over exchange-rate refresh notifications for testing.
protocol FamilyShareRateRefreshSource: Sendable {
    var ratesDidRefresh: AsyncStream<RateRefreshEvent> { get }
}

/// Production implementation bridging `NotificationCenter` to `AsyncStream`.
final class NotificationCenterRateRefreshSource: FamilyShareRateRefreshSource, Sendable {
    let ratesDidRefresh: AsyncStream<RateRefreshEvent>

    init() {
        ratesDidRefresh = AsyncStream { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: .exchangeRatesDidRefresh,
                object: nil,
                queue: nil
            ) { notification in
                let pairs = notification.userInfo?["refreshedPairs"] as? Set<CurrencyPair> ?? []
                let refreshedRates = notification.userInfo?["refreshedRates"] as? [CurrencyPair: Decimal] ?? [:]
                let timestamp = notification.userInfo?["rateSnapshotTimestamp"] as? Date ?? Date()
                let event = RateRefreshEvent(
                    refreshedPairs: pairs,
                    rateSnapshotTimestamp: timestamp,
                    rates: refreshedRates
                )
                continuation.yield(event)
            }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
