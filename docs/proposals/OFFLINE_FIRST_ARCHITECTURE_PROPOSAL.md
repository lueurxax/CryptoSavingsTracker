# Offline-First Architecture Proposal

> Enable full app functionality without network connectivity, with transparent sync when connectivity returns

| Metadata | Value |
|---|---|
| Status | Draft |
| Priority | P1 Reliability |
| Last Updated | 2026-03-21 |
| Platform | iOS + macOS |
| Scope | Offline mutation queuing, cached data fallbacks, network state management, sync-on-reconnect |
| Affected Runtime | `DIContainer`, all Services, `PersistenceController`, `CoinGeckoService`, `TatumClient`, `ExchangeRateService`, `ContentView` |

---

## 1) Problem

The app requires active network connectivity for several core operations that should work offline. Users who open the app on a plane, in a subway, or with poor cellular coverage encounter:

### 1.1 Blocked Core Flows

| Operation | Network Dependency | Offline Behavior |
|---|---|---|
| Create a goal | Fetches currency list from CoinGecko | Fails silently; form cannot load |
| View goal progress | Calls `ExchangeRateService` for conversion | Shows $0.00 or stale data |
| Add manual transaction | None required, but validation calls services | May fail depending on validation path |
| View dashboard charts | Fetches balance history, exchange rates | Charts show empty or crash |
| Monthly planning | Calls `MonthlyPlanningService` which calls `ExchangeRateService` | Plans show incorrect amounts |

### 1.2 No Network State Awareness

- No network reachability monitor exists in the app
- No UI indicator shows online/offline status
- Users cannot distinguish between "loading" and "no network"
- Background refresh silently fails with no notification

### 1.3 Mutations Lost on Crash

- SwiftData writes to CloudKit-backed store
- If the app crashes before CloudKit sync completes, local mutations may be lost
- No write-ahead log or pending mutation queue
- No conflict resolution for simultaneous offline edits on multiple devices

### 1.4 API Data Not Cached Durably

| Data Source | Current Cache | Durability |
|---|---|---|
| CoinGecko coin list | `NSCache` (memory-only) | Lost on app termination |
| CoinGecko exchange rates | In-memory dict with 5-min TTL | Lost on app termination |
| Tatum balances | `BalanceCacheManager` (memory-only) | Lost on app termination |
| Tatum transactions | Not cached | Always fetched fresh |

## 2) Goal

The app should function fully offline with the most recently cached data, queue all mutations for sync, and transparently reconcile when connectivity returns. Users should always know whether they are viewing fresh or cached data.

Specific targets:

1. All read operations work offline using cached data with visible freshness indicators
2. All write operations (create goal, add transaction, edit allocation) succeed offline and sync later
3. Network state is visible in the UI at all times
4. Sync-on-reconnect is automatic with conflict resolution
5. Durable cache survives app termination (persisted to disk, not memory-only)

## 3) Proposed Architecture

### 3.1 Network Reachability Monitor

```swift
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected: Bool = true
    private(set) var connectionType: ConnectionType = .unknown
    private let monitor = NWPathMonitor()

    enum ConnectionType {
        case wifi
        case cellular
        case wired
        case unknown
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = self?.resolveType(path) ?? .unknown
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }
}
```

### 3.2 Durable API Cache

Replace in-memory caches with disk-backed cache using a lightweight SQLite store:

```swift
actor DurableAPICache {
    private let store: URL  // App Support/api-cache.sqlite

    struct CachedEntry<T: Codable> {
        let value: T
        let fetchedAt: Date
        let ttl: TimeInterval
        var isExpired: Bool { Date().timeIntervalSince(fetchedAt) > ttl }
        var age: TimeInterval { Date().timeIntervalSince(fetchedAt) }
    }

    func get<T: Codable>(key: String, type: T.Type) async -> CachedEntry<T>?
    func set<T: Codable>(key: String, value: T, ttl: TimeInterval) async
    func invalidate(key: String) async
    func pruneExpired(olderThan maxAge: TimeInterval) async
}
```

Cache strategy per data source:

| Data Source | Cache Key | TTL | Max Stale Age |
|---|---|---|---|
| CoinGecko coin list | `coingecko-coins` | 24 hours | 30 days |
| Exchange rates | `exchange-{from}-{to}` | 5 minutes | 24 hours |
| On-chain balances | `balance-{chain}-{address}` | 15 minutes | 24 hours |
| Transaction history | `txns-{chain}-{address}` | 1 hour | 7 days |

### 3.3 Offline Mutation Queue

```swift
actor MutationQueue {
    private var pending: [PendingMutation] = []
    private let persistence: MutationQueueStore  // Disk-backed

    struct PendingMutation: Codable, Identifiable {
        let id: UUID
        let type: MutationType
        let payload: Data  // Codable mutation payload
        let createdAt: Date
        let retryCount: Int
        var status: MutationStatus
    }

    enum MutationType: String, Codable {
        case createGoal
        case updateGoal
        case deleteGoal
        case createAsset
        case addTransaction
        case updateAllocation
        case createPlan
    }

    enum MutationStatus: String, Codable {
        case pending
        case syncing
        case synced
        case conflicted
        case failed
    }

    func enqueue(_ mutation: PendingMutation) async
    func processQueue() async  // Called on reconnect
    func resolveConflict(_ id: UUID, resolution: ConflictResolution) async
}
```

### 3.4 Network-Aware Service Wrapper

Wrap existing services with network-aware behavior:

```swift
final class NetworkAwareService<S> {
    private let onlineService: S
    private let cache: DurableAPICache
    private let networkMonitor: NetworkMonitor

    func fetch<T: Codable>(
        key: String,
        ttl: TimeInterval,
        maxStaleAge: TimeInterval,
        onlineFetch: (S) async throws -> T
    ) async -> ServiceResult<T> {
        // 1. If online, try fresh fetch
        if networkMonitor.isConnected {
            do {
                let result = try await onlineFetch(onlineService)
                await cache.set(key: key, value: result, ttl: ttl)
                return .fresh(result)
            } catch {
                // Fall through to cache
            }
        }

        // 2. Return cached if available
        if let cached = await cache.get(key: key, type: T.self) {
            if cached.isExpired {
                return .cached(cached.value, age: cached.age)
            } else {
                return .fresh(cached.value)
            }
        }

        // 3. No cache, no network
        return .failure(.networkUnavailable)
    }
}
```

### 3.5 UI Network Status Indicator

```swift
struct NetworkStatusBarView: View {
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        if !network.isConnected {
            HStack {
                Image(systemName: "wifi.slash")
                Text("Offline - showing cached data")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.yellow.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
```

## 4) Implementation Plan

### Phase 1: Network Monitor and UI Indicator (Est. 2-3 hours)

| Step | Action | Files |
|---|---|---|
| 1.1 | Create `NetworkMonitor` using `NWPathMonitor` | New: `Utilities/NetworkMonitor.swift` |
| 1.2 | Register in `DIContainer` and inject as environment value | `Utilities/DIContainer.swift` |
| 1.3 | Create `NetworkStatusBarView` | New: `Views/Components/NetworkStatusBarView.swift` |
| 1.4 | Add to `ContentView` as overlay | `Views/ContentView.swift` |
| 1.5 | Unit tests for `NetworkMonitor` state transitions | New: `Tests/NetworkMonitorTests.swift` |

### Phase 2: Durable API Cache (Est. 3-4 hours)

| Step | Action | Files |
|---|---|---|
| 2.1 | Create `DurableAPICache` with SQLite backing store | New: `Utilities/DurableAPICache.swift` |
| 2.2 | Migrate `ExchangeRateService` from in-memory cache to durable cache | `Services/ExchangeRateService.swift` |
| 2.3 | Migrate `CoinGeckoService` from `NSCache` to durable cache | `Services/CoinGeckoService.swift` |
| 2.4 | Migrate `BalanceCacheManager` to durable cache | `Utilities/BalanceCacheManager.swift` |
| 2.5 | Add hardcoded fallback coin list (top 100 coins) for zero-cache scenario | New: `Utilities/FallbackCurrencyList.swift` |
| 2.6 | Unit tests for cache expiry, pruning, and disk persistence | New: `Tests/DurableAPICacheTests.swift` |

### Phase 3: Network-Aware Service Layer (Est. 3-4 hours)

| Step | Action | Files |
|---|---|---|
| 3.1 | Create `NetworkAwareService` wrapper | New: `Services/NetworkAwareService.swift` |
| 3.2 | Wrap `ExchangeRateService` with network-aware behavior | `Services/ExchangeRateService.swift` |
| 3.3 | Wrap `CoinGeckoService` with network-aware behavior | `Services/CoinGeckoService.swift` |
| 3.4 | Wrap `TatumClient` with network-aware behavior | `Services/TatumClient.swift` |
| 3.5 | Update `ServiceResult` integration with Resilient Error Handling proposal | `Utilities/ServiceResult.swift` |

### Phase 4: Offline Mutation Queue (Est. 4-5 hours)

| Step | Action | Files |
|---|---|---|
| 4.1 | Create `MutationQueue` with disk-backed persistence | New: `Utilities/MutationQueue.swift` |
| 4.2 | Create `MutationQueueStore` for persistence | New: `Utilities/MutationQueueStore.swift` |
| 4.3 | Integrate with `GoalMutationService` - enqueue on offline create/update | `Services/PersistenceMutationServices.swift` |
| 4.4 | Integrate with `TransactionMutationService` - enqueue offline transactions | `Services/PersistenceMutationServices.swift` |
| 4.5 | Add sync-on-reconnect trigger in `NetworkMonitor` | `Utilities/NetworkMonitor.swift` |
| 4.6 | Create `MutationQueueStatusView` showing pending sync count | New: `Views/Components/MutationQueueStatusView.swift` |
| 4.7 | Unit tests for queue operations and conflict detection | New: `Tests/MutationQueueTests.swift` |

### Phase 5: Conflict Resolution (Est. 3-4 hours)

| Step | Action | Files |
|---|---|---|
| 5.1 | Define conflict detection rules (timestamp-based, field-level) | New: `Utilities/ConflictResolver.swift` |
| 5.2 | Create `ConflictResolutionView` for user-facing conflicts | New: `Views/Settings/ConflictResolutionView.swift` |
| 5.3 | Integration with CloudKit sync | `Services/CloudKitCutoverCoordinator.swift` |
| 5.4 | Integration tests for offline-to-online transition | New: `Tests/OfflineSyncIntegrationTests.swift` |

## 5) Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Cache corruption causing incorrect financial data display | Low | Critical | Checksum validation on cache reads; fall back to "no data" rather than corrupt data |
| Mutation queue conflicts on multi-device offline edits | Medium | High | Last-writer-wins with user notification; option for manual resolution |
| Disk space growth from durable cache | Low | Low | Automatic pruning of entries older than max stale age; configurable cache size limit |
| CloudKit sync conflicts with mutation queue | Medium | High | Mutation queue processes before CloudKit sync; deduplication handles duplicates |
| Stale data displayed as current | Medium | Medium | Mandatory freshness indicators on all cached data; timestamp visible to user |

## 6) Success Metrics

- App launches and displays goals/dashboard fully offline using cached data
- User can create a goal, add a transaction, and modify allocations while offline
- On reconnect, all queued mutations sync within 30 seconds
- Network status indicator visible within 2 seconds of connectivity change
- Cache survives app termination and device restart
- Zero data loss from offline operations (verified via integration test)

## 7) Dependencies

- **Resilient Error Handling proposal**: `ServiceResult` type shared between proposals
- **CloudKit migration**: Must coordinate mutation queue with CloudKit sync pipeline
- **Shared Goals Freshness Sync proposal**: Offline state affects shared projection publishing

## 8) Out of Scope

- Background App Refresh for periodic cache warming (future work)
- Peer-to-peer sync between devices without CloudKit (covered in CloudKit QR/Multipeer proposal)
- Android offline-first parity (separate effort)

---

## Related Documentation

- `docs/CLOUDKIT_MIGRATION_PLAN.md` - CloudKit sync architecture
- `docs/proposals/RESILIENT_ERROR_HANDLING_RECOVERY_UX_PROPOSAL.md` - Error state foundation
- `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` - Alternative sync mechanisms
- `Services/ExchangeRateService.swift` - Current caching implementation
- `Utilities/BalanceCacheManager.swift` - Current balance caching
