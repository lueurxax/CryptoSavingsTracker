# Comprehensive Test Coverage Expansion Proposal

> Close critical testing gaps across ViewModels, API services, error paths, and platform-specific behaviors

| Metadata | Value |
|---|---|
| Status | Draft |
| Priority | P1 Quality |
| Last Updated | 2026-03-21 |
| Platform | iOS + macOS |
| Scope | ViewModel unit tests, API service mocks, error path tests, UI test expansion, platform-specific tests |
| Affected Runtime | All test targets |

---

## 1) Problem

The app has 40 unit test files and 10 UI test files covering approximately 30-40% of the codebase. While core services like `ExchangeRateService`, `MonthlyPlanningService`, and `ExecutionTrackingService` have good coverage, critical gaps exist that allow regressions to ship undetected.

### 1.1 ViewModel Layer: Zero Error Path Tests

No ViewModel has tests for error handling behavior:

| ViewModel | Unit Tests | Error Tests | Loading State Tests |
|---|---|---|---|
| `DashboardViewModel` | None | None | None |
| `GoalViewModel` | None | None | None |
| `AssetViewModel` | None | None | None |
| `MonthlyPlanningViewModel` | None | None | None |
| `MonthlyExecutionViewModel` | None | None | None |
| `CurrencyViewModel` | None | None | None |
| `GoalEditViewModel` | None | None | None |
| `GoalRowViewModel` | Partial (via `GoalCurrentTotalTests`) | None | None |

### 1.2 API Service Mocking Gaps

| Service | Has Mock | Mock Simulates Errors | Mock Simulates Rate Limiting |
|---|---|---|---|
| `CoinGeckoService` | Partial protocol | No | No |
| `TatumClient` | No | No | No |
| `BalanceService` | Partial | No | No |
| `TransactionService` | No | No | No |
| `ExchangeRateService` | Yes (`MockExchangeRateService`) | Partially | No |

Existing mocks lack error simulation capabilities, making it impossible to test error propagation paths.

### 1.3 View Layer Testing

- 145+ view files but only 10 UI test files
- No tests for error state rendering
- No tests for empty state display
- No tests for loading state transitions
- No accessibility audits in tests
- No macOS-specific UI tests

### 1.4 Test Quality Issues

Some existing tests use defensive patterns that mask failures:

```swift
// Pattern found in ExchangeRateServiceTests.swift
if let rate = result {
    #expect(rate > 0)
} else {
    #expect(true)  // Silently passes even when service returns nil
}
```

### 1.5 Missing Integration Test Scenarios

| Scenario | Tested |
|---|---|
| Goal creation end-to-end (form to persistence) | No |
| Allocation rebalancing across multiple goals | Partial |
| Monthly cycle complete flow (draft to completed to new month) | Partial |
| Offline-to-online transition | No |
| Multi-device sync conflict | No |
| App launch with corrupted data | No |
| Family sharing invitation acceptance | Partial |

## 2) Goal

Achieve targeted test coverage that catches the most impactful regressions:

1. 100% of ViewModels have unit tests covering normal, error, and loading states
2. All API services have comprehensive mocks that simulate success, error, timeout, and rate limiting
3. UI tests cover all critical user flows including error states
4. Existing test quality issues (silent passes) are fixed
5. Platform-specific behavior is tested for both iOS and macOS
6. Integration tests cover the five most critical end-to-end flows

## 3) Proposed Test Architecture

### 3.1 Mock Service Protocol

Standardize all service mocks to support configurable behavior:

```swift
protocol ConfigurableMock {
    var callCount: Int { get }
    var lastCallArguments: [Any] { get }
    func reset()
}

class MockCoinGeckoService: CoinGeckoServiceProtocol, ConfigurableMock {
    var callCount = 0
    var lastCallArguments: [Any] = []

    // Configurable responses
    var coinListResult: Result<[CoinGeckoCoin], Error> = .success(MockData.coinList)
    var priceResult: Result<[String: Double], Error> = .success(MockData.prices)

    // Configurable behavior
    var artificialDelay: TimeInterval = 0
    var shouldSimulateRateLimit: Bool = false
    var shouldSimulateTimeout: Bool = false

    func fetchCoinList() async throws -> [CoinGeckoCoin] {
        callCount += 1
        if artificialDelay > 0 { try await Task.sleep(for: .seconds(artificialDelay)) }
        if shouldSimulateTimeout { throw AppError.timeout }
        if shouldSimulateRateLimit { throw AppError.rateLimited }
        return try coinListResult.get()
    }

    func reset() {
        callCount = 0
        lastCallArguments = []
        coinListResult = .success(MockData.coinList)
    }
}
```

### 3.2 ViewModel Test Pattern

Standard template for ViewModel tests:

```swift
@MainActor
final class GoalViewModelTests: XCTestCase {
    var sut: GoalViewModel!
    var mockCalculationService: MockGoalCalculationService!
    var mockExchangeRateService: MockExchangeRateService!

    override func setUp() {
        mockCalculationService = MockGoalCalculationService()
        mockExchangeRateService = MockExchangeRateService()
        sut = GoalViewModel(
            goal: MockData.sampleGoal,
            calculationService: mockCalculationService,
            exchangeRateService: mockExchangeRateService
        )
    }

    // MARK: - Happy Path
    func testLoadProgress_success_updatesPublishedProperties() async { }
    func testLoadProgress_success_setsLoadingStateFalse() async { }

    // MARK: - Error Path
    func testLoadProgress_networkError_setsErrorState() async { }
    func testLoadProgress_apiKeyError_setsNonRetryableError() async { }
    func testLoadProgress_timeout_setsRetryableError() async { }

    // MARK: - Loading State
    func testLoadProgress_setsLoadingTrue_beforeServiceCall() async { }
    func testLoadProgress_setsLoadingFalse_afterSuccess() async { }
    func testLoadProgress_setsLoadingFalse_afterError() async { }

    // MARK: - Retry
    func testRetry_afterError_retriesServiceCall() async { }
    func testRetry_success_clearsErrorState() async { }

    // MARK: - Cancellation
    func testLoadProgress_cancelled_doesNotUpdateState() async { }
}
```

### 3.3 UI Test Error State Verification

```swift
final class ErrorStateUITests: XCTestCase {
    let app = XCUIApplication()

    func testDashboard_networkError_showsErrorBanner() {
        app.launchArguments.append("UITEST_SIMULATE_NETWORK_ERROR")
        app.launch()

        let errorBanner = app.staticTexts["Offline - showing cached data"]
        XCTAssertTrue(errorBanner.waitForExistence(timeout: 5))
    }

    func testAddGoal_currencyFetchFails_showsFallbackList() {
        app.launchArguments.append("UITEST_SIMULATE_COINGECKO_ERROR")
        app.launch()
        app.buttons["Add Goal"].tap()

        let currencyPicker = app.pickers["Currency"]
        XCTAssertTrue(currencyPicker.waitForExistence(timeout: 5))
        // Verify fallback list is shown
    }
}
```

## 4) Implementation Plan

### Phase 1: Mock Infrastructure (Est. 3-4 hours)

| Step | Action | Files |
|---|---|---|
| 1.1 | Define `ConfigurableMock` protocol | New: `Tests/Mocks/ConfigurableMock.swift` |
| 1.2 | Create `MockCoinGeckoService` with full error simulation | New: `Tests/Mocks/MockCoinGeckoService.swift` |
| 1.3 | Create `MockTatumClient` with error simulation | New: `Tests/Mocks/MockTatumClient.swift` |
| 1.4 | Create `MockBalanceService` with error simulation | New: `Tests/Mocks/MockBalanceService.swift` |
| 1.5 | Enhance existing `MockExchangeRateService` with timeout and rate limiting | Update: `Tests/Mocks/MockExchangeRateService.swift` |
| 1.6 | Create `MockData` helper with sample goals, assets, transactions | New: `Tests/Mocks/MockData.swift` |

### Phase 2: ViewModel Unit Tests (Est. 5-6 hours)

| Step | Action | Est. Tests | Files |
|---|---|---|---|
| 2.1 | `DashboardViewModelTests` - load, refresh, per-section errors | 12 tests | New: `Tests/DashboardViewModelTests.swift` |
| 2.2 | `GoalViewModelTests` - progress, error, retry, cancellation | 15 tests | New: `Tests/GoalViewModelTests.swift` |
| 2.3 | `AssetViewModelTests` - balance, error, cache, refresh | 10 tests | New: `Tests/AssetViewModelTests.swift` |
| 2.4 | `MonthlyPlanningViewModelTests` - plan load, create, error | 10 tests | New: `Tests/MonthlyPlanningViewModelTests.swift` |
| 2.5 | `MonthlyExecutionViewModelTests` - execution flow, error | 8 tests | New: `Tests/MonthlyExecutionViewModelTests.swift` |
| 2.6 | `CurrencyViewModelTests` - rate fetch, error, fallback | 6 tests | New: `Tests/CurrencyViewModelTests.swift` |
| 2.7 | `GoalEditViewModelTests` - validation, save, error | 10 tests | New: `Tests/GoalEditViewModelTests.swift` |

### Phase 3: Fix Existing Test Quality (Est. 2-3 hours)

| Step | Action | Files |
|---|---|---|
| 3.1 | Audit all `#expect(true)` fallback patterns and replace with proper assertions | All existing test files |
| 3.2 | Add error message verification to existing tests | Various test files |
| 3.3 | Add `XCTFail` for unexpected code paths instead of silent pass | Various test files |
| 3.4 | Verify all test names follow naming convention: `test<Method>_<condition>_<expected>` | Various test files |

### Phase 4: API Service Tests (Est. 3-4 hours)

| Step | Action | Est. Tests | Files |
|---|---|---|---|
| 4.1 | `CoinGeckoServiceTests` - coin list, prices, error, rate limit | 10 tests | New: `Tests/CoinGeckoServiceTests.swift` |
| 4.2 | `TatumClientTests` - balance, transactions, retry, timeout | 10 tests | New: `Tests/TatumClientTests.swift` |
| 4.3 | `BalanceServiceTests` - fetch, cache hit/miss, error propagation | 8 tests | New: `Tests/BalanceServiceTests.swift` |
| 4.4 | `TransactionServiceTests` - fetch, dedup, error | 6 tests | New: `Tests/TransactionServiceTests.swift` |

### Phase 5: Integration Tests (Est. 3-4 hours)

| Step | Action | Files |
|---|---|---|
| 5.1 | Goal creation end-to-end (form validation to persistence to display) | New: `Tests/GoalCreationIntegrationTests.swift` |
| 5.2 | Monthly cycle complete flow (draft to executing to completed) | Update: `Tests/ExecutionFlowIntegrationTests.swift` |
| 5.3 | Allocation rebalancing with exchange rate changes | New: `Tests/AllocationRebalancingIntegrationTests.swift` |
| 5.4 | DIContainer health check and service recovery | New: `Tests/DIContainerIntegrationTests.swift` |
| 5.5 | Data migration and deduplication after sync | New: `Tests/DataMigrationIntegrationTests.swift` |

### Phase 6: UI Test Expansion (Est. 4-5 hours)

| Step | Action | Est. Tests | Files |
|---|---|---|---|
| 6.1 | Error state UI tests (network error, API error, empty state) | 6 tests | New: `UITests/ErrorStateUITests.swift` |
| 6.2 | Goal management flow (create, edit, archive, restore) | 5 tests | New: `UITests/GoalManagementUITests.swift` |
| 6.3 | Monthly planning flow (view plans, start execution, complete) | 4 tests | New: `UITests/MonthlyPlanningUITests.swift` |
| 6.4 | Settings and configuration flow | 3 tests | New: `UITests/SettingsUITests.swift` |
| 6.5 | Accessibility audit tests (VoiceOver labels, tap targets) | 5 tests | New: `UITests/AccessibilityAuditUITests.swift` |

## 5) Test Coverage Targets by Module

| Module | Current Coverage (Est.) | Target Coverage | Priority |
|---|---|---|---|
| Services (calculation) | 60% | 85% | P0 |
| ViewModels | 5% | 80% | P0 |
| Models | 40% | 70% | P1 |
| Services (API) | 10% | 60% | P1 |
| Views (UI tests) | 10% | 40% | P2 |
| Utilities | 30% | 60% | P2 |
| Navigation | 20% | 50% | P2 |

## 6) Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Mock services diverge from real implementations | Medium | High | Use protocol conformance; CI check that mocks implement all required methods |
| Flaky UI tests due to animation timing | Medium | Medium | Use `waitForExistence(timeout:)` consistently; disable animations in test mode |
| Test maintenance burden increases development velocity cost | Medium | Medium | Focus on high-value tests (error paths, critical flows); avoid testing SwiftUI layout details |
| Tests pass locally but fail in CI due to simulator differences | Low | Medium | Pin simulator version in CI; use `iPhone 16` consistently |
| Over-mocking leads to tests that don't catch real bugs | Medium | High | Include integration tests that use real service implementations with in-memory persistence |

## 7) Success Metrics

- 71+ new unit tests across all ViewModels
- 34+ new API service tests with error simulation
- 23+ new UI tests covering error states and critical flows
- Zero `#expect(true)` silent-pass patterns remaining
- All ViewModel error paths have explicit test coverage
- CI test suite runs in under 5 minutes
- No test relies on network connectivity (all use mocks or fixtures)

## 8) Out of Scope

- Android test coverage (separate effort)
- Performance/load testing (covered in Performance proposal)
- Visual regression testing (existing visual capture system covers this)
- Code coverage reporting tool integration (future work)

---

## Related Documentation

- `docs/ARCHITECTURE.md` - Service layer architecture (informs mock design)
- `docs/proposals/RESILIENT_ERROR_HANDLING_RECOVERY_UX_PROPOSAL.md` - Error states that need testing
- Existing test files in `ios/CryptoSavingsTrackerTests/` - Current patterns
- `ios/CryptoSavingsTrackerUITests/` - Existing UI test infrastructure
