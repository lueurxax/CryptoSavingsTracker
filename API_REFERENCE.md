# Required Monthly Feature - API Reference

## Overview

This document provides comprehensive API reference for the Required Monthly feature components, including method signatures, parameters, return types, and usage examples.

---

## Core Services

### MonthlyPlanningService

**Location**: `CryptoSavingsTracker/Services/MonthlyPlanningService.swift`

Main service for calculating monthly savings requirements across goals.

#### Properties

```swift
@Published var isCalculating: Bool
@Published var rateLimitStatus: RateLimitStatus  
@Published var lastError: Error?
```

#### Methods

##### `calculateMonthlyRequirements(for:)`
```swift
func calculateMonthlyRequirements(for goals: [Goal]) async -> [MonthlyRequirement]
```

Calculates monthly requirements for all goals with intelligent caching and batch processing.

**Parameters:**
- `goals: [Goal]` - Array of user goals to calculate requirements for

**Returns:** `[MonthlyRequirement]` - Sorted array of monthly requirements

**Example:**
```swift
let goals = await fetchUserGoals()
let requirements = await planningService.calculateMonthlyRequirements(for: goals)

for requirement in requirements {
    print("\(requirement.goalName): \(requirement.formattedRequiredMonthly)")
}
```

##### `calculateTotalRequired(for:displayCurrency:)`
```swift
func calculateTotalRequired(for goals: [Goal], displayCurrency: String) async -> Double
```

Calculates total monthly requirement in specified display currency with batched exchange rate fetching.

**Parameters:**
- `goals: [Goal]` - Goals to calculate total for
- `displayCurrency: String` - Target currency code (e.g., "USD", "EUR")

**Returns:** `Double` - Total monthly requirement in display currency

**Example:**
```swift
let total = await planningService.calculateTotalRequired(
    for: goals, 
    displayCurrency: "USD"
)
print("Total monthly: $\(total)")
```

##### `getMonthlyRequirement(for:)`
```swift
func getMonthlyRequirement(for goal: Goal) async -> MonthlyRequirement?
```

Gets monthly requirement for a single goal.

**Parameters:**
- `goal: Goal` - Individual goal to calculate requirement for

**Returns:** `MonthlyRequirement?` - Requirement or nil if calculation fails

##### `clearCache()`
```swift
func clearCache()
```

Clears all cached calculations to force recalculation.

---

### FlexAdjustmentService

**Location**: `CryptoSavingsTracker/Services/FlexAdjustmentService.swift`

Service for applying flexible adjustments to monthly requirements with intelligent redistribution.

#### Methods

##### `applyFlexAdjustment(requirements:adjustment:protectedGoalIds:skippedGoalIds:strategy:)`
```swift
func applyFlexAdjustment(
    requirements: [MonthlyRequirement],
    adjustment: Double,
    protectedGoalIds: Set<UUID>,
    skippedGoalIds: Set<UUID>,
    strategy: RedistributionStrategy = .balanced
) async -> [AdjustedRequirement]
```

Applies flexible adjustment to monthly requirements with advanced redistribution logic.

**Parameters:**
- `requirements: [MonthlyRequirement]` - Base requirements to adjust
- `adjustment: Double` - Adjustment factor (0.5 = 50%, 1.0 = 100%, 1.25 = 125%)
- `protectedGoalIds: Set<UUID>` - Goals protected from reduction
- `skippedGoalIds: Set<UUID>` - Goals to skip entirely  
- `strategy: RedistributionStrategy` - How to redistribute excess/deficit

**Returns:** `[AdjustedRequirement]` - Adjusted requirements with impact analysis

**Example:**
```swift
let adjusted = await flexService.applyFlexAdjustment(
    requirements: baseRequirements,
    adjustment: 0.75, // 75% of original amounts
    protectedGoalIds: [criticalGoalId],
    skippedGoalIds: [],
    strategy: .balanced
)

for result in adjusted {
    print("\(result.requirement.goalName): \(result.adjustedAmount)")
    print("Impact: \(result.impactAnalysis.riskLevel)")
}
```

##### `calculateImpact(original:adjusted:)`
```swift
func calculateImpact(original: Double, adjusted: Double, monthsRemaining: Int) -> ImpactAnalysis
```

Calculates impact analysis for a requirement adjustment.

**Parameters:**
- `original: Double` - Original monthly amount
- `adjusted: Double` - Adjusted monthly amount
- `monthsRemaining: Int` - Months remaining to deadline

**Returns:** `ImpactAnalysis` - Detailed impact assessment

---

### ExchangeRateService

**Location**: `CryptoSavingsTracker/Services/ExchangeRateService.swift`

Enhanced exchange rate service with batching and rate limiting.

#### Properties

```swift
@Published var isLoading: Bool
@Published var rateLimitStatus: RateLimitStatus
@Published var lastError: ExchangeRateError?
```

#### Methods

##### `fetchRate(from:to:)`
```swift
func fetchRate(from: String, to: String) async throws -> Double
```

Fetches single exchange rate with intelligent batching and caching.

**Parameters:**
- `from: String` - Source currency code
- `to: String` - Target currency code

**Returns:** `Double` - Exchange rate

**Throws:** `ExchangeRateError`

**Example:**
```swift
do {
    let rate = try await exchangeService.fetchRate(from: "BTC", to: "USD")
    print("1 BTC = $\(rate) USD")
} catch {
    print("Rate fetch failed: \(error)")
}
```

##### `fetchRates(currencies:)`
```swift
func fetchRates(currencies: [(from: String, to: String)]) async throws -> [String: Double]
```

Efficiently fetches multiple rates using batching.

**Parameters:**
- `currencies: [(String, String)]` - Array of currency pairs

**Returns:** `[String: Double]` - Dictionary of rates keyed by "FROM-TO"

**Example:**
```swift
let pairs = [("BTC", "USD"), ("ETH", "EUR"), ("ADA", "GBP")]
let rates = try await exchangeService.fetchRates(currencies: pairs)

for (key, rate) in rates {
    print("\(key): \(rate)")
}
```

##### `preloadCommonRates(baseCurrency:targetCurrencies:)`
```swift
func preloadCommonRates(baseCurrency: String = "USD", targetCurrencies: [String] = ["EUR", "GBP", "JPY", "CAD", "AUD"]) async
```

Preloads commonly used currency pairs for better performance.

---

## Data Models

### MonthlyRequirement

**Location**: `CryptoSavingsTracker/Models/MonthlyRequirement.swift`

Represents monthly savings requirement for a goal.

```swift
struct MonthlyRequirement: Identifiable, Sendable, Codable {
    let id: UUID
    let goalId: UUID
    let goalName: String
    let currency: String
    let targetAmount: Double
    let currentTotal: Double
    let remainingAmount: Double
    let monthsRemaining: Int
    let requiredMonthly: Double
    let progress: Double
    let deadline: Date
    let status: RequirementStatus
}
```

#### Computed Properties

```swift
var formattedRequiredMonthly: String  // "$1,250"
var formattedRemainingAmount: String  // "$10,000 remaining"  
var timeRemainingDescription: String  // "6 months left"
```

### RequirementStatus

Status enumeration for monthly requirements.

```swift
enum RequirementStatus: String, Sendable, Codable {
    case completed = "completed"    // Goal achieved
    case onTrack = "on_track"      // Progress is sufficient
    case attention = "attention"    // Needs attention
    case critical = "critical"      // Urgent action required
}
```

#### Properties

```swift
var displayName: String      // "On Track", "Critical", etc.
var systemImageName: String  // SF Symbol name for status
```

### MonthlyPlan

**Location**: `CryptoSavingsTracker/Models/MonthlyPlan.swift`

SwiftData model for storing user planning preferences.

```swift
@Model
final class MonthlyPlan: @unchecked Sendable {
    var goalId: UUID
    var flexStateRawValue: String = "flexible"
    var customAmount: Double?
    var isProtected: Bool = false
    var notes: String = ""
    var lastModifiedDate: Date
}
```

#### Computed Properties

```swift
var flexState: FlexState {
    get { FlexState(rawValue: flexStateRawValue) ?? .flexible }
    set { flexStateRawValue = newValue.rawValue; lastModifiedDate = Date() }
}
```

### AdjustedRequirement

Result of flex adjustment calculations.

```swift
struct AdjustedRequirement: Identifiable {
    let id: UUID
    let requirement: MonthlyRequirement
    let adjustedAmount: Double
    let adjustmentFactor: Double
    let redistributionAmount: Double
    let impactAnalysis: ImpactAnalysis
}
```

### ImpactAnalysis

Analysis of adjustment impact on goal completion.

```swift
struct ImpactAnalysis {
    let changeAmount: Double        // Dollar change
    let changePercentage: Double    // Percentage change
    let estimatedDelay: Int         // Days of estimated delay
    let riskLevel: RiskLevel        // .low, .medium, .high
}
```

---

## View Models

### MonthlyPlanningViewModel

**Location**: `CryptoSavingsTracker/ViewModels/MonthlyPlanningViewModel.swift`

Main view model coordinating monthly planning UI.

#### Properties

```swift
@Published var monthlyRequirements: [MonthlyRequirement] = []
@Published var totalRequired: Double = 0.0
@Published var adjustedTotal: Double = 0.0
@Published var flexAdjustment: Double = 1.0
@Published var adjustmentPreview: [UUID: Double] = [:]
@Published var statistics: PlanningStatistics = .empty
@Published var isLoading: Bool = false
@Published var error: Error?
```

#### Methods

##### `loadMonthlyRequirements()`
```swift
func loadMonthlyRequirements() async
```

Loads monthly requirements for all user goals.

##### `refreshCalculations()`
```swift
func refreshCalculations() async  
```

Forces refresh of all calculations, bypassing cache.

##### `applyFlexAdjustment(_:)`
```swift
func applyFlexAdjustment(_ adjustment: Double) async
```

Applies flex adjustment and updates UI state.

##### `previewAdjustment(_:)`
```swift
func previewAdjustment(_ percentage: Double) async
```

Generates live preview of adjustment without applying it.

---

## UI Components

### MonthlyPlanningWidget

**Location**: `CryptoSavingsTracker/Views/Components/MonthlyPlanningWidget.swift`

Dashboard widget displaying monthly requirements summary.

```swift
struct MonthlyPlanningWidget: View {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    
    var body: some View { /* Implementation */ }
}
```

#### Features
- Expandable/collapsible interface
- Quick action buttons
- Real-time updates
- Comprehensive accessibility support

### FlexAdjustmentSlider

**Location**: `CryptoSavingsTracker/Views/Components/FlexAdjustmentSlider.swift`

Interactive slider for adjusting monthly payments.

```swift
struct FlexAdjustmentSlider: View {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    
    var body: some View { /* Implementation */ }
}
```

#### Features
- Custom slider with visual feedback
- Preset adjustment buttons (Skip, Quarter, Half, Full, Extra)
- Live preview with debouncing
- Impact analysis display

### PlatformSpecific Planning Views

Adaptive planning interface for different platforms:

- `PlanningView.swift` - Main coordinator view
- `iOSCompactPlanningView.swift` - iPhone layout
- `iOSRegularPlanningView.swift` - iPad layout  
- `macOSPlanningView.swift` - macOS with HSplitView

---

## Enums and Types

### RedistributionStrategy

Strategy for redistributing excess savings in flex adjustments.

```swift
enum RedistributionStrategy {
    case balanced        // Equal distribution across goals
    case urgent          // Prioritize goals with nearest deadlines
    case largest         // Reduce largest amounts first
    case riskMinimizing  // Minimize risk to all goal completion
}
```

### FlexState

State of goal flexibility for adjustments.

```swift
enum FlexState: String, CaseIterable {
    case flexible = "flexible"      // Can be adjusted
    case protected = "protected"    // Protected from reductions
    case skipped = "skipped"        // Skip this month
    case custom = "custom"          // User-defined amount
}
```

### RiskLevel

Risk level for goal completion impact.

```swift
enum RiskLevel {
    case low     // Minimal impact on goal completion
    case medium  // Moderate risk of delay
    case high    // Significant risk to goal achievement
}
```

### CacheCategory

Categories for performance optimization caching.

```swift
enum CacheCategory: String {
    case general = "general"
    case monthlyRequirements = "monthly_requirements"
    case calculations = "calculations" 
    case exchangeRates = "exchange_rates"
    case notifications = "notifications"
    case flexAdjustments = "flex_adjustments"
}
```

---

## Utility Classes

### AccessibilityManager

**Location**: `CryptoSavingsTracker/Utilities/AccessibilityManager.swift`

Comprehensive accessibility support for WCAG 2.1 AA compliance.

#### Key Methods

##### `voiceOverDescription(for:currency:context:)`
```swift
func voiceOverDescription(for amount: Double, currency: String, context: String = "") -> String
```

Generates VoiceOver-friendly descriptions for financial amounts.

**Example:**
```swift
let description = AccessibilityManager.shared.voiceOverDescription(
    for: 1250.50,
    currency: "USD", 
    context: "Monthly requirement"
)
// Output: "Monthly requirement: One thousand two hundred fifty dollars and fifty cents"
```

##### `chartAccessibilityLabel(title:dataPoints:unit:)`
```swift
func chartAccessibilityLabel(title: String, dataPoints: [(String, Double)], unit: String = "") -> String  
```

Creates comprehensive chart descriptions for screen readers.

##### `performHapticFeedback(_:)`
```swift
func performHapticFeedback(_ type: HapticFeedbackType)
```

Provides contextual haptic feedback with user preference respect.

### PerformanceOptimizer  

**Location**: `CryptoSavingsTracker/Utilities/PerformanceOptimizer.swift`

Multi-level caching and background processing system.

#### Key Methods

##### `cache(_:forKey:category:ttl:)`
```swift
func cache<T: Codable & Sendable>(_ value: T, forKey key: String, category: CacheCategory = .general, ttl: TimeInterval? = nil) async
```

Stores value in multi-tier cache system.

##### `retrieve(_:forKey:category:)`
```swift
func retrieve<T: Codable>(_ type: T.Type, forKey key: String, category: CacheCategory = .general) async -> T?
```

Retrieves cached value with automatic expiration handling.

##### `batchProcess(items:batchSize:operation:)`
```swift
func batchProcess<T: Sendable, R: Sendable>(items: [T], batchSize: Int = 10, operation: @escaping @Sendable (T) async throws -> R) async -> [R]
```

Processes items in batches with parallel execution.

---

## Error Types

### MonthlyPlanningError

```swift
enum MonthlyPlanningError: LocalizedError, Sendable {
    case calculationFailed(String)
    case currencyConversionFailed(String) 
    case invalidGoalData(String)
}
```

### ExchangeRateError

```swift
enum ExchangeRateError: LocalizedError, Equatable {
    case rateNotAvailable
    case networkError
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case invalidAPIKey
    case quotaExceeded
}
```

### FlexAdjustmentError

```swift
enum FlexAdjustmentError: LocalizedError {
    case insufficientData
    case invalidAdjustment(Double)
    case noFlexibleGoals
    case calculationFailed(String)
}
```

---

## Configuration

### DIContainer Integration

```swift
// Required methods to add to DIContainer
class DIContainer {
    private lazy var _monthlyPlanningService = MonthlyPlanningService(
        exchangeRateService: exchangeRateService
    )
    
    var monthlyPlanningService: MonthlyPlanningService {
        return _monthlyPlanningService
    }
    
    func makeFlexAdjustmentService(modelContext: ModelContext) -> FlexAdjustmentService {
        return FlexAdjustmentService(
            planningService: monthlyPlanningService,
            modelContext: modelContext
        )
    }
    
    func makeMonthlyPlanningViewModel(modelContext: ModelContext) -> MonthlyPlanningViewModel {
        return MonthlyPlanningViewModel(modelContext: modelContext)
    }
}
```

### Model Container Setup

```swift
let container = try ModelContainer(for: 
    Goal.self,
    Asset.self, 
    Transaction.self,
    MonthlyPlan.self  // Required new model
)
```

---

## Usage Examples

### Complete Planning Flow

```swift
// 1. Initialize services
let planningService = DIContainer.shared.monthlyPlanningService
let flexService = DIContainer.shared.makeFlexAdjustmentService(modelContext: context)

// 2. Calculate base requirements
let goals = await fetchActiveGoals()
let requirements = await planningService.calculateMonthlyRequirements(for: goals)

// 3. Apply flexible adjustments  
let adjusted = await flexService.applyFlexAdjustment(
    requirements: requirements,
    adjustment: 0.75, // 75% of original
    protectedGoalIds: [],
    skippedGoalIds: [],
    strategy: .balanced
)

// 4. Display results
for result in adjusted {
    print("\(result.requirement.goalName):")
    print("  Original: \(result.requirement.formattedRequiredMonthly)")
    print("  Adjusted: \(formatCurrency(result.adjustedAmount))")
    print("  Impact: \(result.impactAnalysis.riskLevel)")
}
```

### Widget Integration

```swift
struct DashboardView: View {
    @StateObject private var planningViewModel: MonthlyPlanningViewModel
    
    init(modelContext: ModelContext) {
        _planningViewModel = StateObject(
            wrappedValue: MonthlyPlanningViewModel(modelContext: modelContext)
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Other dashboard widgets...
                
                MonthlyPlanningWidget(viewModel: planningViewModel)
                    .accessibilityIdentifier("MonthlyPlanningWidget")
            }
            .padding()
        }
    }
}
```

### Accessibility Implementation

```swift
struct GoalRowView: View {
    let requirement: MonthlyRequirement
    
    var body: some View {
        HStack {
            Text(requirement.goalName)
            Spacer()
            Text(requirement.formattedRequiredMonthly)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(requirement.goalName) goal")
        .accessibilityValue(
            AccessibilityManager.shared.voiceOverDescription(
                for: requirement.requiredMonthly,
                currency: requirement.currency,
                context: "Monthly requirement"
            )
        )
        .accessibilityHint("Double tap for goal details")
    }
}
```

---

*API Reference v2.0.0 - Updated August 9, 2025*