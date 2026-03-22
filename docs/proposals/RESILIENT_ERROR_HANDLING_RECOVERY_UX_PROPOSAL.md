# Resilient Error Handling and Recovery UX Proposal

> Systematic overhaul of error propagation, user-facing error states, and recovery flows across all app layers

| Metadata | Value |
|---|---|
| Status | Draft |
| Priority | P0 Trust and Correctness |
| Last Updated | 2026-03-21 |
| Platform | iOS + macOS |
| Scope | Service error propagation, ViewModel error states, View error/empty/loading states, recovery UX |
| Affected Runtime | All ViewModels, all Services, all user-facing Views, `ErrorHandling.swift`, `DIContainer` |

---

## 1) Problem

The app has inconsistent error handling across its three architectural layers, leading to silent failures, frozen UIs, and no recovery path for users:

### 1.1 Service Layer: Silent Failures

Services handle errors inconsistently:

| Service | Current Behavior | Impact |
|---|---|---|
| `ExchangeRateService` | Returns fallback rate (0.0) on failure | Goal progress shows 0% silently |
| `CoinGeckoService` | Catches and logs errors, continues | Price data stale with no indication |
| `GoalCalculationService` | Recalculates on every view update, no cache | Repeated failures on each render |
| `ExecutionTrackingService` | Throws errors | Callers don't always handle them |

Example: when `ExchangeRateService` returns a 0.0 fallback rate because CoinGecko is unreachable, the dashboard shows all goals at "$0.00 progress" with no explanation. Users may believe their savings are gone.

### 1.2 ViewModel Layer: Missing Error States

Several ViewModels have no `@Published var error` property:

| ViewModel | Has Error State | Has Loading State | Consequence |
|---|---|---|---|
| `GoalViewModel` | No | No | View appears frozen on failure |
| `AssetViewModel` | No | No | Balance shows stale data silently |
| `MonthlyExecutionViewModel` | No | No | Execution status unknown on error |
| `GoalRowViewModel` | Partial | No | Row shows 0% without explanation |
| `DashboardViewModel` | Partial | Yes | Chart sections fail silently |

### 1.3 View Layer: No Recovery UX

- `ErrorAlertModifier` exists but only shows a generic alert with no retry action
- `recoverySuggestion` is defined in `ErrorHandling.swift` but never surfaced to users
- No inline error banners, no retry buttons, no "last updated" timestamps
- Empty states exist for some views (`DashboardEmptyState`) but not for error conditions
- Charts crash or show blank space when data is unavailable

### 1.4 Network Failures Block Core Functionality

- Creating a new goal requires fetching the currency list from CoinGecko first
- If CoinGecko is unreachable, the user cannot create any goal at all
- No fallback to a cached or hardcoded currency list
- No offline indicator in the UI

## 2) Goal

Every user-facing operation should either succeed or show a clear, actionable error state with a recovery path. Specifically:

1. No silent failures: every service error must propagate to the ViewModel and render in the View
2. Every async View must have three states: loading, content, and error
3. Error states must include: what failed, why (in user terms), and how to retry
4. Cached/stale data should be shown with a freshness indicator rather than hidden
5. Network-dependent features must degrade gracefully to cached data or hardcoded fallbacks

## 3) Proposed Architecture

### 3.1 Unified Result Pattern for Services

Define a standard `ServiceResult` type that all services return:

```swift
enum ServiceResult<T> {
    case fresh(T)
    case cached(T, age: TimeInterval)
    case fallback(T, reason: ServiceDegradationReason)
    case failure(AppError)

    var value: T? {
        switch self {
        case .fresh(let v), .cached(let v, _), .fallback(let v, _): return v
        case .failure: return nil
        }
    }

    var isFresh: Bool {
        if case .fresh = self { return true }
        return false
    }
}

enum ServiceDegradationReason {
    case networkUnavailable
    case apiRateLimited
    case apiKeyInvalid
    case serviceUnavailable
    case timeout
}
```

### 3.2 ViewModel Error State Protocol

Standardize all ViewModels with an `ErrorAware` protocol:

```swift
@MainActor
protocol ErrorAwareViewModel: ObservableObject {
    var viewState: ViewState { get set }
    var lastSuccessfulLoad: Date? { get }
    func retry() async
}

enum ViewState: Equatable {
    case idle
    case loading
    case loaded
    case error(UserFacingError)
    case degraded(String)  // Partial data available, with explanation
}

struct UserFacingError: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let recoverySuggestion: String?
    let isRetryable: Bool
    let category: ErrorCategory

    enum ErrorCategory {
        case network
        case apiKey
        case dataCorruption
        case unknown
    }
}
```

### 3.3 View-Level Error Components

Create reusable error state views:

```swift
// Inline error banner (non-blocking, dismissible)
struct ErrorBannerView: View {
    let error: UserFacingError
    let onRetry: (() async -> Void)?
    let onDismiss: (() -> Void)?
}

// Full-screen error state (blocking, requires action)
struct ErrorStateView: View {
    let error: UserFacingError
    let onRetry: (() async -> Void)?
}

// Freshness indicator (shows data age)
struct FreshnessIndicatorView: View {
    let lastUpdated: Date?
    let isRefreshing: Bool
}

// Tri-state container (loading / content / error)
struct AsyncContentView<Content: View, Loading: View, Error: View>: View {
    let state: ViewState
    @ViewBuilder let content: () -> Content
    @ViewBuilder let loading: () -> Loading
    @ViewBuilder let error: (UserFacingError) -> Error
}
```

### 3.4 Error Translation Layer

Centralize service error to user-facing error translation:

```swift
struct ErrorTranslator {
    static func translate(_ error: AppError) -> UserFacingError {
        switch error {
        case .networkUnavailable:
            return UserFacingError(
                title: "No Connection",
                message: "Unable to reach the server. Your existing data is still available.",
                recoverySuggestion: "Check your internet connection and try again.",
                isRetryable: true,
                category: .network
            )
        case .apiKeyInvalid:
            return UserFacingError(
                title: "API Key Issue",
                message: "The price data service rejected the API key.",
                recoverySuggestion: "Go to Settings to update your API key.",
                isRetryable: false,
                category: .apiKey
            )
        // ... other cases
        }
    }
}
```

## 4) Implementation Plan

### Phase 1: Foundation (Est. 3-4 hours)

| Step | Action | Files |
|---|---|---|
| 1.1 | Define `ServiceResult`, `ViewState`, `UserFacingError`, `ErrorTranslator` | New: `Utilities/ServiceResult.swift`, update `Utilities/ErrorHandling.swift` |
| 1.2 | Define `ErrorAwareViewModel` protocol | New: `Protocols/ErrorAwareViewModel.swift` |
| 1.3 | Create `ErrorBannerView`, `ErrorStateView`, `FreshnessIndicatorView`, `AsyncContentView` | New: `Views/Components/ErrorBannerView.swift`, etc. |
| 1.4 | Write unit tests for `ErrorTranslator` and `ServiceResult` | New: `Tests/ErrorTranslatorTests.swift`, `Tests/ServiceResultTests.swift` |

### Phase 2: Service Layer Retrofit (Est. 4-5 hours)

| Step | Action | Files |
|---|---|---|
| 2.1 | Update `ExchangeRateService` to return `ServiceResult` with cached/fallback states | `Services/ExchangeRateService.swift` |
| 2.2 | Update `CoinGeckoService` to return `ServiceResult`, add cached currency list fallback | `Services/CoinGeckoService.swift` |
| 2.3 | Update `GoalCalculationService` to propagate errors instead of swallowing | `Services/GoalCalculationService.swift` |
| 2.4 | Update `BalanceService` and `TransactionService` to return `ServiceResult` | `Services/BalanceService.swift`, `Services/TransactionService.swift` |
| 2.5 | Add hardcoded fallback currency list (top 50 coins) for offline goal creation | New: `Utilities/FallbackCurrencyList.swift` |

### Phase 3: ViewModel Layer Retrofit (Est. 3-4 hours)

| Step | Action | Files |
|---|---|---|
| 3.1 | Conform `GoalViewModel` to `ErrorAwareViewModel`, add `viewState` and `retry()` | `ViewModels/GoalViewModel.swift` |
| 3.2 | Conform `AssetViewModel` to `ErrorAwareViewModel` | `ViewModels/AssetViewModel.swift` |
| 3.3 | Conform `MonthlyExecutionViewModel` to `ErrorAwareViewModel` | `ViewModels/MonthlyExecutionViewModel.swift` |
| 3.4 | Conform `DashboardViewModel` to `ErrorAwareViewModel`, surface per-section errors | `ViewModels/DashboardViewModel.swift` |
| 3.5 | Conform `GoalRowViewModel` to `ErrorAwareViewModel` | `ViewModels/GoalRowViewModel.swift` |

### Phase 4: View Layer Integration (Est. 4-5 hours)

| Step | Action | Files |
|---|---|---|
| 4.1 | Wrap `DashboardView` chart sections in `AsyncContentView` | `Views/DashboardView.swift` |
| 4.2 | Add `ErrorBannerView` to `GoalDetailView` for calculation failures | `Views/GoalDetailView.swift` |
| 4.3 | Add `ErrorStateView` to `AddGoalView` for currency list fetch failures | `Views/AddGoalView.swift` |
| 4.4 | Add `FreshnessIndicatorView` to `AssetDetailView` for balance staleness | `Views/AssetDetailView.swift` |
| 4.5 | Add loading + error states to `MonthlyPlanningView` | `Views/MonthlyPlanningView.swift` |
| 4.6 | Update `EditGoalView` with save error handling and retry | `Views/EditGoalView.swift` |

### Phase 5: Testing and Validation (Est. 2-3 hours)

| Step | Action | Files |
|---|---|---|
| 5.1 | Unit tests for all ViewModel error states | New: `Tests/GoalViewModelErrorTests.swift`, etc. |
| 5.2 | Unit tests for service `ServiceResult` propagation | Update existing service test files |
| 5.3 | UI tests for error state rendering (banner, full-screen, freshness) | New: `UITests/ErrorStateUITests.swift` |
| 5.4 | Manual testing matrix for network failure scenarios | Documented in test plan |

## 5) Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Breaking existing error handling during retrofit | Medium | High | Incremental rollout, one ViewModel at a time; keep old pattern as fallback |
| Performance overhead from `ServiceResult` wrapping | Low | Low | `ServiceResult` is a lightweight enum; no heap allocation for value types |
| Inconsistent adoption across team | Medium | Medium | Enforce via `ErrorAwareViewModel` protocol conformance check in CI |
| Over-alerting users with error banners | Medium | Medium | Use `ErrorBannerView` for recoverable errors only; silent degradation for non-critical failures |

## 6) Success Metrics

- Zero silent failures: every service error reaches the View layer
- 100% of async Views have loading, content, and error states
- User can retry any failed operation without leaving the current screen
- `AddGoalView` works offline using cached currency list
- Error banner includes actionable recovery suggestion for all retryable errors
- All new error components have unit tests and at least one UI test

## 7) Out of Scope

- Offline mutation queuing (covered in separate Offline-First proposal)
- Push notification for background sync failures (covered in Shared Goals Freshness Sync proposal)
- Analytics/telemetry for error rates (future work)
- Android error handling parity (separate effort)

---

## Related Documentation

- `docs/ARCHITECTURE.md` - Service layer architecture
- `Utilities/ErrorHandling.swift` - Current error types
- `docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md` - Related freshness concerns for shared data
