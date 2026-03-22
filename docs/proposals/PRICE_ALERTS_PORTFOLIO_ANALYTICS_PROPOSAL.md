# Price Alerts and Portfolio Analytics Proposal

> Add price target notifications, cost basis tracking, and investment performance analytics to transform the app from a savings tracker into a complete portfolio intelligence tool

| Metadata | Value |
|---|---|
| Status | Draft |
| Priority | P2 Feature |
| Last Updated | 2026-03-21 |
| Platform | iOS + macOS |
| Scope | Price alert system, cost basis tracking, gains/losses calculation, portfolio analytics dashboard |
| Affected Runtime | New services, new models, new views, `CoinGeckoService`, `NotificationManager`, `AutomationScheduler` |

---

## 1) Problem

CryptoSavingsTracker tracks savings goals and asset allocations but lacks several features that users of a crypto financial app expect:

### 1.1 No Price Alerts

Users cannot set notifications for when a cryptocurrency reaches a target price. This is a fundamental feature of any crypto tracking application. Currently, the app fetches real-time prices via `CoinGeckoService` but only uses them for exchange rate conversion. Users must check prices manually or use a separate app.

### 1.2 No Cost Basis Tracking

The app records transactions (deposits and manual entries) but does not track:

- **Purchase price** at the time of each transaction
- **Average cost basis** per asset
- **Unrealized gains/losses** (current value vs. cost basis)
- **Realized gains/losses** (for sold/withdrawn assets)

This data is critical for informed investment decisions and tax reporting.

### 1.3 No Portfolio Performance Analytics

The dashboard shows current balances and goal progress but provides no historical performance analysis:

- No total portfolio value over time chart
- No individual asset performance comparison
- No return on investment (ROI) calculation
- No benchmark comparison (e.g., "your portfolio vs. BTC vs. S&P 500")
- No allocation drift analysis (actual vs. target allocation)

### 1.4 No Tax-Relevant Data Export

`CSVExportService` exports raw transaction data but does not generate tax-relevant reports:

- No capital gains summary
- No cost basis report
- No holding period classification (short-term vs. long-term)

## 2) Goal

Transform the app from a pure savings tracker into a portfolio intelligence tool by adding:

1. **Price alerts**: Configurable notifications when crypto assets hit price targets
2. **Cost basis tracking**: Automatic purchase price recording and average cost calculation
3. **Portfolio analytics**: Performance charts, ROI metrics, and allocation analysis
4. **Tax export**: Capital gains summary export

## 3) Proposed Architecture

### 3.1 Data Models

#### PriceAlert Model

```swift
@Model
final class PriceAlert {
    var id: UUID = UUID()
    var coinId: String           // CoinGecko coin ID
    var coinName: String         // Display name (e.g., "Bitcoin")
    var coinSymbol: String       // Ticker (e.g., "BTC")
    var targetPrice: Double      // Target price in alert currency
    var alertCurrency: String    // Currency for target (e.g., "USD")
    var direction: AlertDirection // .above or .below
    var isEnabled: Bool = true
    var isTriggered: Bool = false
    var triggeredAt: Date?
    var createdAt: Date = Date()
    var isRepeating: Bool = false // Re-arm after trigger

    enum AlertDirection: String, Codable {
        case above  // Notify when price goes above target
        case below  // Notify when price drops below target
    }
}
```

#### CostBasisEntry Model

```swift
@Model
final class CostBasisEntry {
    var id: UUID = UUID()
    var transaction: Transaction?
    var asset: Asset?
    var purchasePrice: Double     // Price per unit at time of transaction
    var purchaseCurrency: String  // Currency of purchase price
    var quantity: Double          // Amount acquired
    var totalCost: Double         // purchasePrice * quantity
    var acquiredAt: Date          // Date of acquisition
    var method: CostBasisMethod = .fifo

    enum CostBasisMethod: String, Codable {
        case fifo    // First In, First Out
        case lifo    // Last In, First Out
        case average // Average cost
    }
}
```

#### PortfolioSnapshot Model

```swift
@Model
final class PortfolioSnapshot {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var totalValueUSD: Double     // Total portfolio value in USD
    var assetValues: Data         // Encoded [AssetValueSnapshot]
    var exchangeRates: Data       // Encoded rate snapshot

    struct AssetValueSnapshot: Codable {
        let coinId: String
        let quantity: Double
        let priceUSD: Double
        let valueUSD: Double
    }
}
```

### 3.2 Services

#### PriceAlertService

```swift
protocol PriceAlertServiceProtocol {
    func createAlert(coinId: String, targetPrice: Double, currency: String, direction: PriceAlert.AlertDirection) async throws -> PriceAlert
    func deleteAlert(_ alert: PriceAlert) async throws
    func toggleAlert(_ alert: PriceAlert) async throws
    func checkAlerts() async throws -> [PriceAlert]  // Returns newly triggered alerts
}

class PriceAlertService: PriceAlertServiceProtocol {
    private let coinGeckoService: CoinGeckoServiceProtocol
    private let notificationManager: NotificationManager
    private let modelContext: ModelContext

    /// Called periodically by AutomationScheduler
    func checkAlerts() async throws -> [PriceAlert] {
        let enabledAlerts = try fetchEnabledAlerts()
        let coinIds = Set(enabledAlerts.map(\.coinId))
        let prices = try await coinGeckoService.fetchPrices(for: Array(coinIds))

        var triggered: [PriceAlert] = []
        for alert in enabledAlerts {
            guard let currentPrice = prices[alert.coinId] else { continue }
            let shouldTrigger = switch alert.direction {
                case .above: currentPrice >= alert.targetPrice
                case .below: currentPrice <= alert.targetPrice
            }

            if shouldTrigger {
                alert.isTriggered = true
                alert.triggeredAt = Date()
                if !alert.isRepeating { alert.isEnabled = false }
                triggered.append(alert)

                await notificationManager.sendPriceAlert(
                    coin: alert.coinName,
                    price: currentPrice,
                    target: alert.targetPrice,
                    direction: alert.direction
                )
            }
        }

        try modelContext.save()
        return triggered
    }
}
```

#### CostBasisService

```swift
protocol CostBasisServiceProtocol {
    func recordCostBasis(for transaction: Transaction, priceAtTime: Double, currency: String) async throws
    func getAverageCostBasis(for asset: Asset) async throws -> Double
    func getUnrealizedGainLoss(for asset: Asset) async throws -> GainLossResult
    func getPortfolioGainLoss() async throws -> PortfolioGainLoss
}

struct GainLossResult {
    let costBasis: Double
    let currentValue: Double
    let unrealizedGain: Double       // currentValue - costBasis
    let unrealizedGainPercent: Double // (gain / costBasis) * 100
    let holdingPeriod: HoldingPeriod

    enum HoldingPeriod {
        case shortTerm  // < 1 year
        case longTerm   // >= 1 year
        case mixed      // Multiple lots with different periods
    }
}

struct PortfolioGainLoss {
    let totalCostBasis: Double
    let totalCurrentValue: Double
    let totalUnrealizedGain: Double
    let totalUnrealizedGainPercent: Double
    let perAsset: [AssetGainLoss]
}
```

#### PortfolioAnalyticsService

```swift
protocol PortfolioAnalyticsServiceProtocol {
    func recordSnapshot() async throws
    func getPerformanceHistory(period: TimePeriod) async throws -> [PortfolioSnapshot]
    func getAssetPerformance(coinId: String, period: TimePeriod) async throws -> AssetPerformance
    func getAllocationDrift() async throws -> AllocationDrift
    func getROI(period: TimePeriod) async throws -> ROIResult
}

enum TimePeriod {
    case week
    case month
    case threeMonths
    case sixMonths
    case year
    case allTime
}

struct AssetPerformance {
    let coinId: String
    let startPrice: Double
    let endPrice: Double
    let returnPercent: Double
    let highPrice: Double
    let lowPrice: Double
    let volatility: Double
    let dataPoints: [PricePoint]
}

struct AllocationDrift {
    let targetAllocations: [String: Double]  // coinId -> target %
    let actualAllocations: [String: Double]  // coinId -> actual %
    let driftPercent: [String: Double]       // coinId -> drift from target
    let rebalanceNeeded: Bool
    let suggestedTrades: [RebalanceSuggestion]
}

struct ROIResult {
    let totalInvested: Double
    let currentValue: Double
    let returnAmount: Double
    let returnPercent: Double
    let annualizedReturn: Double
    let period: TimePeriod
}
```

### 3.3 Views

#### Price Alerts Management

```swift
struct PriceAlertsView: View {
    // List of active alerts with toggle, edit, delete
    // "Add Alert" button
    // Triggered alerts history section
}

struct AddPriceAlertView: View {
    // Coin search/picker
    // Target price input
    // Direction picker (above/below)
    // Repeating toggle
    // Current price display for reference
}
```

#### Portfolio Analytics Dashboard

```swift
struct PortfolioAnalyticsView: View {
    // Time period selector (1W, 1M, 3M, 6M, 1Y, All)
    // Portfolio value chart (line chart over time)
    // ROI summary card
    // Per-asset performance table
    // Allocation drift visualization
    // Gain/loss summary
}

struct AssetPerformanceDetailView: View {
    // Individual asset price chart
    // Cost basis vs. current price
    // Unrealized gain/loss
    // Transaction history with cost basis
}
```

#### Tax Export

```swift
struct TaxExportView: View {
    // Tax year selector
    // Cost basis method picker (FIFO, LIFO, Average)
    // Capital gains summary preview
    // Export button (CSV with gains/losses)
}
```

## 4) Implementation Plan

### Phase 1: Price Alert System (Est. 6-8 hours)

| Step | Action | Files |
|---|---|---|
| 1.1 | Create `PriceAlert` SwiftData model | New: `Models/PriceAlert.swift` |
| 1.2 | Create `PriceAlertService` with check logic | New: `Services/PriceAlertService.swift` |
| 1.3 | Add batch price fetch to `CoinGeckoService` (if not existing) | `Services/CoinGeckoService.swift` |
| 1.4 | Extend `NotificationManager` with price alert notification type | `Utilities/NotificationManager.swift` |
| 1.5 | Integrate alert checking into `AutomationScheduler` (15-min interval) | `Services/AutomationScheduler.swift` |
| 1.6 | Create `PriceAlertsView` and `AddPriceAlertView` | New: `Views/Alerts/PriceAlertsView.swift`, `Views/Alerts/AddPriceAlertView.swift` |
| 1.7 | Add navigation route for Price Alerts | `Navigation/Coordinator.swift` |
| 1.8 | Register in `DIContainer` | `Utilities/DIContainer.swift` |
| 1.9 | Unit tests for alert trigger logic | New: `Tests/PriceAlertServiceTests.swift` |

### Phase 2: Cost Basis Tracking (Est. 5-6 hours)

| Step | Action | Files |
|---|---|---|
| 2.1 | Create `CostBasisEntry` SwiftData model | New: `Models/CostBasisEntry.swift` |
| 2.2 | Create `CostBasisService` with FIFO/LIFO/average methods | New: `Services/CostBasisService.swift` |
| 2.3 | Auto-record cost basis on manual transaction creation | `Services/PersistenceMutationServices.swift` |
| 2.4 | Auto-fetch price at transaction time for on-chain imports | `Services/OnChainTransactionImportService.swift` |
| 2.5 | Add cost basis display to `AssetDetailView` | `Views/AssetDetailView.swift` |
| 2.6 | Add gain/loss display to `TransactionHistoryView` | `Views/TransactionHistoryView.swift` |
| 2.7 | Unit tests for FIFO, LIFO, and average cost calculations | New: `Tests/CostBasisServiceTests.swift` |

### Phase 3: Portfolio Analytics (Est. 6-8 hours)

| Step | Action | Files |
|---|---|---|
| 3.1 | Create `PortfolioSnapshot` SwiftData model | New: `Models/PortfolioSnapshot.swift` |
| 3.2 | Create `PortfolioAnalyticsService` | New: `Services/PortfolioAnalyticsService.swift` |
| 3.3 | Add daily snapshot recording to `AutomationScheduler` | `Services/AutomationScheduler.swift` |
| 3.4 | Create `PortfolioAnalyticsView` with charts | New: `Views/Analytics/PortfolioAnalyticsView.swift` |
| 3.5 | Create `AssetPerformanceDetailView` | New: `Views/Analytics/AssetPerformanceDetailView.swift` |
| 3.6 | Create `AllocationDriftView` with rebalance suggestions | New: `Views/Analytics/AllocationDriftView.swift` |
| 3.7 | Add ROI calculation and display | New: `Views/Analytics/ROISummaryView.swift` |
| 3.8 | Add navigation routes for Analytics tab | `Navigation/Coordinator.swift` |
| 3.9 | Unit tests for ROI, allocation drift, and snapshot calculations | New: `Tests/PortfolioAnalyticsServiceTests.swift` |

### Phase 4: Tax Export (Est. 3-4 hours)

| Step | Action | Files |
|---|---|---|
| 4.1 | Extend `CSVExportService` with capital gains report format | `Services/CSVExportService.swift` |
| 4.2 | Add holding period classification (short-term vs. long-term) | `Services/CostBasisService.swift` |
| 4.3 | Create `TaxExportView` with year and method selection | New: `Views/Settings/TaxExportView.swift` |
| 4.4 | Unit tests for tax report generation | New: `Tests/TaxExportTests.swift` |

### Phase 5: Integration and Polish (Est. 3-4 hours)

| Step | Action | Files |
|---|---|---|
| 5.1 | Add Price Alerts and Analytics to main navigation | `Views/ContentView.swift` |
| 5.2 | Add price alert badge to tab bar (triggered count) | `Views/ContentView.swift` |
| 5.3 | Add portfolio summary widget to Dashboard | `Views/DashboardView.swift` |
| 5.4 | CloudKit schema update for new models | `PersistenceController.swift` |
| 5.5 | Integration tests for alert-to-notification flow | New: `Tests/PriceAlertIntegrationTests.swift` |
| 5.6 | UI tests for alert creation and analytics navigation | New: `UITests/PriceAlertUITests.swift` |

## 5) UI/UX Considerations

### Price Alerts

- Alerts should be creatable from any asset detail view with one tap ("Alert me when BTC reaches $X")
- Triggered alerts should appear as a notification badge in the app
- Alert history should show triggered alerts with the price at trigger time
- Support both "above" and "below" for the same coin simultaneously

### Portfolio Analytics

- Default view should show portfolio value over the last month
- ROI should be shown prominently with color coding (green for gain, red for loss)
- Allocation drift should show a side-by-side comparison of target vs. actual
- Rebalance suggestions should be actionable (link to allocation editing)

### Cost Basis

- Cost basis should be auto-populated when possible (using CoinGecko historical price)
- Users should be able to manually override cost basis for OTC or private transactions
- Gain/loss should be shown inline on transaction rows with color coding

## 6) Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| CoinGecko rate limiting from frequent price checks | Medium | Medium | Check alerts at 15-min intervals max; batch coin IDs into single API call |
| Historical price data unavailable for old transactions | Medium | Low | Allow manual cost basis entry; mark auto-populated entries for user review |
| Tax calculations are jurisdiction-specific | High | Medium | Clearly label as "estimates only, not tax advice"; export raw data for accountant review |
| Portfolio snapshot storage grows over time | Low | Low | Daily snapshots only; prune to weekly after 3 months, monthly after 1 year |
| Price alert check misses rapid price spikes between intervals | Medium | Low | Document 15-min check interval; future: WebSocket for real-time alerts |

## 7) Success Metrics

- Users can create, trigger, and manage price alerts for any supported cryptocurrency
- Cost basis is automatically recorded for all new transactions
- Portfolio analytics show performance over configurable time periods
- Tax export generates capital gains CSV with holding period classification
- Alert check runs reliably at 15-minute intervals via `AutomationScheduler`
- All new services have unit test coverage above 80%

## 8) Future Enhancements (Out of Scope)

- WebSocket-based real-time price alerts (requires background processing changes)
- Integration with tax software (TurboTax, CoinTracker, etc.)
- Benchmark comparison (portfolio vs. BTC vs. S&P 500)
- AI-powered portfolio insights ("your BTC allocation is higher than 80% of users")
- Android parity (separate effort)
- Apple Watch complications for price alerts

---

## Related Documentation

- `docs/ARCHITECTURE.md` - Service layer architecture
- `docs/API_INTEGRATIONS.md` - CoinGecko API capabilities
- `Services/CoinGeckoService.swift` - Existing price data integration
- `Services/CSVExportService.swift` - Existing export functionality
- `Services/AutomationScheduler.swift` - Existing automation infrastructure
- `Utilities/NotificationManager.swift` - Existing notification system
