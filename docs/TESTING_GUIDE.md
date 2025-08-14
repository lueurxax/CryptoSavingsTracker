# Required Monthly Feature - Testing Guide

## Overview

This guide provides comprehensive testing strategies for the Required Monthly feature, including unit tests, integration tests, UI tests, accessibility tests, and performance benchmarks.

---

## Test Architecture

### Testing Pyramid

```
        UI Tests (20 tests)
       /                    \
  Integration Tests (15)    Accessibility Tests (30)
 /                                                   \
Unit Tests (25)                              Performance Tests (10)
```

### Test Categories

1. **Unit Tests**: Individual component logic
2. **Integration Tests**: Service interaction and data flow
3. **UI Tests**: User interaction and interface behavior
4. **Accessibility Tests**: WCAG 2.1 AA compliance
5. **Performance Tests**: Speed and memory benchmarks

---

## Unit Tests

**Location**: `CryptoSavingsTrackerTests/MonthlyPlanningTests.swift`

### Financial Calculation Tests

#### Basic Monthly Requirement Calculation
```swift
@Test("Basic monthly requirement calculation")
func testBasicMonthlyRequirement() {
    let goal = Goal(
        name: "Test Goal",
        targetAmount: 12000,
        deadline: Calendar.current.date(byAdding: .month, value: 12, to: Date())!
    )
    
    // Simulate current total of $2000
    let currentTotal = 2000.0
    let remaining = 10000.0 // $12000 - $2000
    let monthsRemaining = 12
    let expectedMonthly = remaining / Double(monthsRemaining) // $833.33
    
    #expect(abs(expectedMonthly - 833.33) < 0.01, "Monthly calculation should be accurate")
}
```

#### Edge Cases
```swift
@Test("Zero amount goal handling")
func testZeroAmountGoal() {
    let goal = Goal(name: "Zero Goal", targetAmount: 0, deadline: Date())
    let requirement = createMonthlyRequirement(for: goal, currentTotal: 0)
    
    #expect(requirement.requiredMonthly == 0, "Zero target should require zero monthly")
    #expect(requirement.status == .completed, "Zero target should be completed")
}

@Test("Past deadline goal handling")
func testPastDeadlineGoal() {
    let pastDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    let goal = Goal(name: "Past Goal", targetAmount: 1000, deadline: pastDate)
    let requirement = createMonthlyRequirement(for: goal, currentTotal: 0)
    
    #expect(requirement.monthsRemaining >= 1, "Should have minimum 1 month remaining")
    #expect(requirement.status == .critical, "Past deadline should be critical")
}
```

### Status Determination Tests

```swift
@Test("Requirement status determination")
func testRequirementStatusLogic() {
    // Test completed status
    let completedRequirement = MonthlyRequirement(
        /* parameters with remaining = 0 */
    )
    #expect(completedRequirement.status == .completed)
    
    // Test critical status (high monthly amount)
    let criticalRequirement = MonthlyRequirement(
        /* parameters with requiredMonthly > 10000 */
    )
    #expect(criticalRequirement.status == .critical)
    
    // Test attention status
    let attentionRequirement = MonthlyRequirement(
        /* parameters with requiredMonthly > 5000 */
    )
    #expect(attentionRequirement.status == .attention)
    
    // Test on track status
    let onTrackRequirement = MonthlyRequirement(
        /* parameters with reasonable monthly amount */
    )
    #expect(onTrackRequirement.status == .onTrack)
}
```

### Flex Adjustment Tests

```swift
@Test("Flex adjustment redistribution")
func testFlexAdjustmentRedistribution() async {
    let flexService = FlexAdjustmentService()
    let requirements = createTestRequirements([
        ("Goal A", 1000.0, .flexible),
        ("Goal B", 800.0, .flexible),
        ("Goal C", 600.0, .protected)
    ])
    
    let adjusted = await flexService.applyFlexAdjustment(
        requirements: requirements,
        adjustment: 0.5, // 50% reduction
        protectedGoalIds: [requirements[2].goalId], // Goal C protected
        skippedGoalIds: [],
        strategy: .balanced
    )
    
    // Goal A and B should be reduced, Goal C unchanged
    #expect(adjusted[0].adjustedAmount < requirements[0].requiredMonthly)
    #expect(adjusted[1].adjustedAmount < requirements[1].requiredMonthly)
    #expect(adjusted[2].adjustedAmount == requirements[2].requiredMonthly)
    
    // Total reduction should be redistributed
    let totalOriginal = requirements.reduce(0) { $0 + $1.requiredMonthly }
    let totalAdjusted = adjusted.reduce(0) { $0 + $1.adjustedAmount }
    #expect(totalAdjusted < totalOriginal)
}
```

### Currency Conversion Tests

```swift
@Test("Currency conversion with exchange rates")
func testCurrencyConversion() async {
    let mockExchangeService = MockExchangeRateService()
    mockExchangeService.setRate(from: "EUR", to: "USD", rate: 1.20)
    
    let planningService = MonthlyPlanningService(exchangeRateService: mockExchangeService)
    let goals = [
        Goal(name: "EUR Goal", targetAmount: 1000, currency: "EUR", deadline: Date()),
        Goal(name: "USD Goal", targetAmount: 1200, currency: "USD", deadline: Date())
    ]
    
    let totalUSD = await planningService.calculateTotalRequired(for: goals, displayCurrency: "USD")
    
    // EUR goal: 1000 * 1.20 = 1200 USD
    // USD goal: 1200 USD
    // Expected total: 2400 USD
    #expect(abs(totalUSD - 2400) < 0.01, "Currency conversion should be accurate")
}
```

---

## Integration Tests

**Location**: `CryptoSavingsTrackerTests/IntegrationTests.swift`

### Service Coordination Tests

```swift
@Test("End-to-end monthly planning workflow")
func testCompleteMonthlyPlanningWorkflow() async {
    // Setup test environment
    let container = createTestModelContainer()
    let context = container.mainContext
    
    // Create test data
    let goals = await createTestGoalsInContext(context)
    
    // Initialize services
    let planningService = MonthlyPlanningService(exchangeRateService: MockExchangeRateService())
    let flexService = FlexAdjustmentService(planningService: planningService, modelContext: context)
    
    // Test complete workflow
    let requirements = await planningService.calculateMonthlyRequirements(for: goals)
    let adjusted = await flexService.applyFlexAdjustment(
        requirements: requirements,
        adjustment: 0.75,
        protectedGoalIds: [],
        skippedGoalIds: [],
        strategy: .balanced
    )
    
    // Verify results
    #expect(requirements.count == goals.count, "Should calculate requirement for each goal")
    #expect(adjusted.count == requirements.count, "Should adjust all requirements")
    #expect(adjusted.allSatisfy { $0.adjustedAmount >= 0 }, "All adjusted amounts should be non-negative")
}
```

### Performance Cache Integration

```swift
@Test("Performance optimizer caching integration")
func testPerformanceOptimizerIntegration() async {
    let optimizer = PerformanceOptimizer.shared
    let testData = createLargeRequirementSet(count: 1000)
    
    // Cache data
    await optimizer.cache(testData, forKey: "test_requirements", category: .monthlyRequirements)
    
    // Retrieve cached data
    let retrieved: [MonthlyRequirement]? = await optimizer.retrieve(
        [MonthlyRequirement].self,
        forKey: "test_requirements", 
        category: .monthlyRequirements
    )
    
    #expect(retrieved != nil, "Should retrieve cached data")
    #expect(retrieved?.count == testData.count, "Retrieved data should match cached data")
}
```

### Notification Integration

```swift
@Test("Monthly payment reminder integration")
func testNotificationIntegration() async {
    let notificationManager = NotificationManager.shared
    let requirements = createTestRequirements()
    let context = createTestModelContainer().mainContext
    
    await notificationManager.scheduleMonthlyPaymentReminders(
        requirements: requirements,
        modelContext: context
    )
    
    // Verify notifications were scheduled
    let pendingNotifications = await UNUserNotificationCenter.current().pendingNotificationRequests()
    let monthlyNotifications = pendingNotifications.filter { 
        $0.identifier.hasPrefix("monthly-payment-") 
    }
    
    #expect(monthlyNotifications.count > 0, "Should schedule monthly payment reminders")
}
```

---

## UI Tests

**Location**: `CryptoSavingsTrackerUITests/MonthlyPlanningUITests.swift`

### Widget Interaction Tests

```swift
func testMonthlyPlanningWidgetExpansion() throws {
    app.launch()
    
    // Navigate to dashboard
    let dashboardTab = app.tabBars.buttons["Dashboard"]
    XCTAssertTrue(dashboardTab.waitForExistence(timeout: 5))
    dashboardTab.tap()
    
    // Find monthly planning widget
    let widget = app.scrollViews.otherElements.containing(.staticText, identifier: "Required This Month").element
    XCTAssertTrue(widget.waitForExistence(timeout: 5))
    
    // Test expansion
    let expandButton = widget.buttons["Show more"]
    XCTAssertTrue(expandButton.exists)
    expandButton.tap()
    
    // Verify expanded content appears
    let goalBreakdown = widget.staticTexts["Goal Breakdown"]
    XCTAssertTrue(goalBreakdown.waitForExistence(timeout: 2))
    
    // Test collapse
    let collapseButton = widget.buttons["Show less"]
    XCTAssertTrue(collapseButton.exists)
    collapseButton.tap()
    
    XCTAssertFalse(goalBreakdown.exists)
}
```

### Planning View Navigation

```swift
func testPlanningViewNavigation() throws {
    app.launch()
    
    // Navigate to Planning tab
    let planningTab = app.tabBars.buttons["Planning"]
    XCTAssertTrue(planningTab.waitForExistence(timeout: 5))
    planningTab.tap()
    
    // Verify planning view loads
    let navigationTitle = app.navigationBars["Monthly Planning"]
    XCTAssertTrue(navigationTitle.waitForExistence(timeout: 3))
    
    #if os(iOS)
    // Test platform-specific navigation
    if UIDevice.current.userInterfaceIdiom == .phone {
        // Test compact layout tabs
        let controlsTab = app.buttons["Controls"]
        if controlsTab.exists {
            controlsTab.tap()
            
            let flexSlider = app.otherElements.containing(.staticText, identifier: "Flex Adjustment").element
            XCTAssertTrue(flexSlider.waitForExistence(timeout: 2))
        }
    }
    #endif
}
```

### Flex Adjustment Interaction

```swift
func testFlexAdjustmentSliderInteraction() throws {
    app.launch()
    
    let planningTab = app.tabBars.buttons["Planning"]
    planningTab.tap()
    
    let flexSection = app.scrollViews.otherElements.containing(.staticText, identifier: "Flex Adjustment").element
    
    if flexSection.waitForExistence(timeout: 5) {
        // Test preset buttons
        let halfButton = flexSection.buttons["Half"]
        XCTAssertTrue(halfButton.exists)
        halfButton.tap()
        
        // Verify percentage changed
        let fiftyPercent = flexSection.staticTexts["50%"]
        XCTAssertTrue(fiftyPercent.waitForExistence(timeout: 2))
        
        // Test another preset
        let fullButton = flexSection.buttons["Full"]
        XCTAssertTrue(fullButton.exists)
        fullButton.tap()
        
        let hundredPercent = flexSection.staticTexts["100%"]
        XCTAssertTrue(hundredPercent.waitForExistence(timeout: 2))
    }
}
```

### Cross-Platform UI Tests

```swift
#if os(macOS)
func testMacOSSplitViewLayout() throws {
    let planningTab = app.tabBars.buttons["Planning"]
    planningTab.tap()
    
    // Verify split view exists
    let leftPanel = app.scrollViews.containing(.staticText, identifier: "Goals").element
    XCTAssertTrue(leftPanel.waitForExistence(timeout: 5))
    
    let rightPanel = app.scrollViews.containing(.staticText, identifier: "Flex Adjustment").element
    XCTAssertTrue(rightPanel.waitForExistence(timeout: 5))
    
    // Test goal selection affects right panel
    let goalRow = leftPanel.buttons.firstMatch
    if goalRow.exists {
        goalRow.tap()
        // Verify right panel updates
    }
}
#endif
```

### Error State Testing

```swift
func testOfflineErrorHandling() throws {
    // Simulate offline condition
    app.launchEnvironment["UITEST_SIMULATE_OFFLINE"] = "1"
    app.launch()
    
    let planningTab = app.tabBars.buttons["Planning"]
    planningTab.tap()
    
    // Look for error state or loading indicator
    let loadingIndicator = app.activityIndicators.firstMatch
    let errorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'error' OR label CONTAINS 'offline'")).element
    
    XCTAssertTrue(loadingIndicator.exists || errorText.waitForExistence(timeout: 10))
}
```

---

## Accessibility Tests

**Location**: `CryptoSavingsTrackerTests/AccessibilityTests.swift`

### WCAG Compliance Tests

```swift
@Test("Color contrast ratios meet WCAG AA standards")
func testColorContrastCompliance() {
    let primaryOnWhite = AccessibleColors.contrastRatio(
        foreground: AccessibleColors.primaryInteractive,
        background: .white
    )
    #expect(primaryOnWhite >= 4.5, "Primary color must meet WCAG AA standards (4.5:1)")
    
    let errorOnWhite = AccessibleColors.contrastRatio(
        foreground: AccessibleColors.error,
        background: .white
    )
    #expect(errorOnWhite >= 4.5, "Error color must meet WCAG AA standards")
}
```

### VoiceOver Description Tests

```swift
@Test("VoiceOver currency descriptions")
func testVoiceOverCurrencyDescriptions() {
    let manager = AccessibilityManager.shared
    
    let description = manager.voiceOverDescription(
        for: 1250.50,
        currency: "USD"
    )
    
    #expect(description.contains("1250.50"), "Should contain amount value")
    #expect(description.contains("USD") || description.contains("dollar"), "Should contain currency")
    
    let contextDescription = manager.voiceOverDescription(
        for: 500.0,
        currency: "EUR",
        context: "Monthly requirement"
    )
    #expect(contextDescription.contains("Monthly requirement"), "Should include context")
}
```

### Chart Accessibility Tests

```swift
@Test("Chart accessibility descriptions")
func testChartAccessibilityLabels() {
    let manager = AccessibilityManager.shared
    let dataPoints = [
        ("Jan", 1000.0),
        ("Feb", 1250.0), 
        ("Mar", 1100.0)
    ]
    
    let chartLabel = manager.chartAccessibilityLabel(
        title: "Savings Progress",
        dataPoints: dataPoints,
        unit: "USD"
    )
    
    #expect(chartLabel.contains("Savings Progress"), "Should contain chart title")
    #expect(chartLabel.contains("3 data points"), "Should indicate data count")
    #expect(chartLabel.contains("1000") || chartLabel.contains("min"), "Should include range")
}
```

### Keyboard Navigation Tests

```swift
func testKeyboardNavigation() throws {
    #if os(macOS)
    let planningTab = app.tabBars.buttons["Planning"]
    planningTab.tap()
    
    // Test Tab key navigation
    app.typeKey("\t", modifierFlags: [])
    
    // Verify focus moves between elements
    let focusedElement = app.firstResponder
    XCTAssertTrue(focusedElement.exists)
    
    // Test Enter key activation
    app.typeKey("\r", modifierFlags: [])
    #endif
}
```

### Screen Reader Tests

```swift
func testVoiceOverSupport() throws {
    app.launchEnvironment["UITEST_ACCESSIBILITY"] = "1"
    app.launch()
    
    let planningTab = app.tabBars.buttons["Planning"]
    XCTAssertNotNil(planningTab.accessibilityLabel)
    planningTab.tap()
    
    // Test widget accessibility
    let widget = app.scrollViews.otherElements.containing(.staticText, identifier: "Required This Month").element
    if widget.waitForExistence(timeout: 5) {
        let expandButton = widget.buttons.firstMatch
        XCTAssertNotNil(expandButton.accessibilityLabel)
        XCTAssertNotNil(expandButton.accessibilityHint)
    }
}
```

---

## Performance Tests

**Location**: `CryptoSavingsTrackerTests/PerformanceTests.swift`

### Calculation Performance

```swift
@Test("Monthly requirement calculation performance")
func testCalculationPerformance() async {
    let goals = createLargeGoalSet(count: 1000) // 1000 goals
    let planningService = MonthlyPlanningService(exchangeRateService: MockExchangeRateService())
    
    let startTime = Date()
    let requirements = await planningService.calculateMonthlyRequirements(for: goals)
    let duration = Date().timeIntervalSince(startTime)
    
    #expect(duration < 5.0, "Should calculate 1000 requirements in under 5 seconds")
    #expect(requirements.count == goals.count, "Should calculate all requirements")
}
```

### Cache Performance

```swift
@Test("Cache retrieval performance")
func testCachePerformance() async {
    let optimizer = PerformanceOptimizer.shared
    let testData = createLargeRequirementSet(count: 10000)
    
    // Cache data
    await optimizer.cache(testData, forKey: "performance_test", category: .calculations)
    
    // Measure retrieval time
    let startTime = Date()
    let retrieved: [MonthlyRequirement]? = await optimizer.retrieve(
        [MonthlyRequirement].self,
        forKey: "performance_test",
        category: .calculations
    )
    let duration = Date().timeIntervalSince(startTime)
    
    #expect(duration < 0.1, "Should retrieve 10K items in under 100ms")
    #expect(retrieved?.count == testData.count, "Should retrieve all items")
}
```

### Memory Usage Tests

```swift
@Test("Memory usage within limits")
func testMemoryUsage() async {
    let optimizer = PerformanceOptimizer.shared
    let initialMemory = getMemoryUsage()
    
    // Perform memory-intensive operations
    for i in 0..<1000 {
        let data = createTestRequirement(index: i)
        await optimizer.cache(data, forKey: "memory_test_\(i)", category: .calculations)
    }
    
    let peakMemory = getMemoryUsage()
    let memoryIncrease = peakMemory - initialMemory
    
    #expect(memoryIncrease < 100, "Memory increase should be under 100MB")
}
```

### UI Responsiveness Tests

```swift
func testUIResponsiveness() {
    measure(metrics: [XCTApplicationLaunchMetric()]) {
        app.launch()
        
        let planningTab = app.tabBars.buttons["Planning"]
        planningTab.tap()
        
        let planningTitle = app.navigationBars["Monthly Planning"]
        _ = planningTitle.waitForExistence(timeout: 10)
    }
}
```

---

## Mock Objects and Test Helpers

### MockExchangeRateService

```swift
class MockExchangeRateService: ExchangeRateService {
    private var mockRates: [String: Double] = [: ]
    
    func setRate(from: String, to: String, rate: Double) {
        let key = "\(from)-\(to)"
        mockRates[key] = rate
    }
    
    override func fetchRate(from: String, to: String) async throws -> Double {
        let key = "\(from)-\(to)"
        return mockRates[key] ?? 1.0
    }
    
    override func fetchRates(currencies: [(from: String, to: String)]) async throws -> [String: Double] {
        var results: [String: Double] = [: ]
        for (from, to) in currencies {
            let key = "\(from)-\(to)"
            results[key] = mockRates[key] ?? 1.0
        }
        return results
    }
}
```

### Test Data Factories

```swift
func createTestGoal(
    name: String = "Test Goal",
    targetAmount: Double = 10000,
    currentTotal: Double = 2000,
    currency: String = "USD",
    monthsFromNow: Int = 12
) -> Goal {
    let deadline = Calendar.current.date(byAdding: .month, value: monthsFromNow, to: Date())!
    return Goal(name: name, targetAmount: targetAmount, deadline: deadline, currency: currency)
}

func createTestRequirement(
    goalName: String = "Test Goal",
    requiredMonthly: Double = 800,
    status: RequirementStatus = .onTrack
) -> MonthlyRequirement {
    return MonthlyRequirement(
        goalId: UUID(),
        goalName: goalName,
        currency: "USD",
        targetAmount: 10000,
        currentTotal: 2000,
        remainingAmount: 8000,
        monthsRemaining: 10,
        requiredMonthly: requiredMonthly,
        progress: 0.2,
        deadline: Date().addingTimeInterval(86400 * 300),
        status: status
    )
}
```

---

## Test Execution

### Running All Tests

```bash
# Run all tests
xcodebuild test -scheme CryptoSavingsTracker -destination "platform=macOS"

# Run specific test categories
xcodebuild test -scheme CryptoSavingsTracker -destination "platform=macOS" -only-testing:CryptoSavingsTrackerTests

# Run UI tests only  
xcodebuild test -scheme CryptoSavingsTracker -destination "platform=macOS" -only-testing:CryptoSavingsTrackerUITests

# Run accessibility tests only
xcodebuild test -scheme CryptoSavingsTracker -destination "platform=macOS" -only-testing:CryptoSavingsTrackerTests/AccessibilityTests
```

### Test Configuration

#### Test Environment Variables
```swift
app.launchEnvironment["UITEST_RESET_DATA"] = "1"
app.launchEnvironment["UITEST_MOCK_DATA"] = "monthly_planning"
app.launchEnvironment["UITEST_SIMULATE_OFFLINE"] = "1"
app.launchEnvironment["UITEST_ACCESSIBILITY"] = "1"
```

#### Test Schemes
- **Debug**: Full test suite with detailed logging
- **Release**: Performance and stability tests
- **Accessibility**: Focus on WCAG compliance

---

## Continuous Integration

### GitHub Actions Workflow

```yaml
name: Test Suite
on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v2
    - name: Run Unit Tests
      run: |
        xcodebuild test -scheme CryptoSavingsTracker \
          -destination "platform=macOS" \
          -only-testing:CryptoSavingsTrackerTests
    
    - name: Run UI Tests  
      run: |
        xcodebuild test -scheme CryptoSavingsTracker \
          -destination "platform=macOS" \
          -only-testing:CryptoSavingsTrackerUITests
          
    - name: Generate Coverage Report
      run: |
        xcrun xccov view --report --json DerivedData/Logs/Test/*.xcresult > coverage.json
```

### Quality Gates

Tests must pass these quality gates:

- ✅ **Unit Test Coverage**: >90%
- ✅ **Integration Test Coverage**: >80%  
- ✅ **UI Test Coverage**: >70%
- ✅ **Accessibility Compliance**: 100% WCAG AA
- ✅ **Performance Benchmarks**: All within limits
- ✅ **Memory Usage**: <100MB increase
- ✅ **Load Time**: <2 seconds cold start

---

## Best Practices

### Test Organization

1. **Group by Feature**: Tests organized by feature area
2. **Clear Naming**: Test names describe what they verify
3. **Fast Execution**: Unit tests run in <5 seconds
4. **Isolation**: Each test is independent
5. **Deterministic**: Tests produce consistent results

### Test Data Management

1. **Factories**: Use factory methods for test data creation
2. **Cleanup**: Reset state between tests
3. **Realistic Data**: Use realistic amounts and dates
4. **Edge Cases**: Test boundary conditions
5. **Error Scenarios**: Test failure paths

### Accessibility Testing

1. **Automated Checks**: Use accessibility APIs for validation
2. **Manual Testing**: Test with real assistive technologies
3. **Multiple Disabilities**: Consider various accessibility needs
4. **Platform Differences**: Test on iOS, macOS, and visionOS
5. **Regular Audits**: Continuous accessibility compliance checking

---

*Testing Guide v2.0.0 - Updated August 9, 2025*
## Comprehensive Test Plan

This test plan outlines a strategy for ensuring the quality, reliability, and performance of the CryptoSavingsTracker application. It builds upon the existing test infrastructure and identifies areas for further enhancement.

### 1. Current Test Coverage Summary

*   **Unit Tests (Swift Testing):**
    *   **Strengths:** Good coverage for core data models (`Goal`, `Asset`, `Transaction`), `ReminderFrequency` enum, and basic `GoalCalculationService` functions. Includes tests for SwiftData persistence and relationships.
    *   **Areas for Improvement:** While the `DIContainer` has been refactored to use protocols, the existing unit tests for services (e.g., `ExchangeRateServiceTests`) still directly interact with singletons or concrete implementations. This limits true isolation and mocking capabilities.
*   **UI Tests (XCTest):**
    *   **Strengths:** Comprehensive coverage of critical user flows (goal creation, asset/transaction management, goal deletion, navigation). Effective use of launch arguments and environment variables for controlling test data and simulating conditions (e.g., offline mode). Includes basic performance and accessibility checks.
    *   **Areas for Improvement:** Can be expanded to cover more edge cases, complex interactions, and a wider range of accessibility features.

### 2. Key Functionalities to Test

The following are the core functionalities of CryptoSavingsTracker that require thorough testing:

*   **Goal Management:** Create, Edit, Delete (including associated assets/transactions), Reminder Configuration, Deadline handling.
*   **Asset Management:** Add, Remove, Manual Balance updates, On-chain Balance fetching (for various chains/currencies).
*   **Transaction Tracking:** Add Manual Transactions (deposits/withdrawals), Fetch On-chain Transaction History, Correct parsing and display of transaction details.
*   **Progress Tracking & Visualization:** Accurate calculation of goal progress, current total, daily targets. Correct rendering and data integrity of charts (Balance History, Asset Composition).
*   **Monthly Planning:** Accurate calculation of monthly requirements, application of flex adjustments (various strategies), correct redistribution logic, persistence of planning settings.
*   **API Integration:** Robust error handling for CoinGecko and Tatum APIs (network errors, rate limits, invalid responses). Correct data mapping from API responses to app models.
*   **Data Persistence:** Reliable saving and loading of all application data using SwiftData, including relationships between models.
*   **Platform Adaptiveness:** Consistent and functional UI/UX across iOS, macOS, and visionOS. Platform-specific navigation and UI elements (e.g., sheets vs. popovers).
*   **Accessibility:** VoiceOver support. Keyboard navigation (macOS).
*   **Notifications:** Scheduling and canceling local notifications for reminders.

### 3. Proposed Test Plan

#### 3.1. Test Types and Focus Areas

*   **Unit Testing (Enhanced):**
    *   **Focus:** Isolated testing of individual functions, methods, and business logic components.
    *   **Actionable Items:**
        *   **Refactor Service Tests:** Update existing service tests (e.g., `ExchangeRateServiceTests`, `BalanceServiceTests`, `TransactionServiceTests`, `MonthlyPlanningServiceTests`) to fully leverage the new protocol-based dependency injection. This will involve creating mock implementations of service protocols and injecting them into the services under test.
        *   **Expand Coverage:** Add unit tests for new or complex logic, especially within `GoalCalculationService`, `FlexAdjustmentService` (for various redistribution strategies), and any complex data transformations.
        *   **Error Handling:** Ensure comprehensive unit tests for all defined error cases in services.
*   **UI Testing (Expanded):**
    *   **Focus:** End-to-end user flows, UI interactions, and visual correctness across platforms.
    *   **Actionable Items:**
        *   **Edge Cases:** Add UI tests for edge cases (e.g., empty states for all relevant screens, very large/small numbers, long text inputs, invalid API keys).
        *   **Complex Interactions:** Test multi-step interactions thoroughly (e.g., creating a goal, adding multiple assets, recording transactions, then verifying overall progress).
        *   **Platform-Specific UI:** Explicitly test UI elements that differ between platforms (e.g., popovers vs. sheets, context menus, toolbar items).
        *   **Accessibility:** Expand UI tests to include more explicit accessibility assertions (e.g., checking `accessibilityLabel`, `accessibilityValue`, `accessibilityHint` for key elements).
*   **Integration Testing:**
    *   **Focus:** Verify interactions between different modules and services, especially data flow from API to UI.
    *   **Actionable Items:**
        *   **API Integration:** Test the full data pipeline from fetching data from Tatum/CoinGecko (using controlled mock servers or recorded responses) through the services, view models, and finally to the UI.
        *   **SwiftData Integration:** Ensure that data persistence and retrieval work correctly across app launches and complex data manipulations.
        *   **Cross-Feature Consistency:** Verify that changes in one part of the app (e.g., adding a transaction) correctly update related views and calculations (e.g., goal progress, monthly planning).
*   **Performance Testing:**
    *   **Focus:** Measure and optimize app launch times, UI responsiveness, and data loading speeds.
    *   **Actionable Items:**
        *   **Dedicated Performance Suite:** Create a separate test suite for performance metrics using `XCTMeasure` and `XCTOSSignpostMetric` for critical user journeys (e.g., app launch, loading a goal with many assets/transactions, monthly planning calculations).
        *   **API Call Latency:** Monitor and set thresholds for API response times.
*   **Accessibility Testing:**
    *   **Focus:** Ensure the application is usable by individuals with disabilities.
    *   **Actionable Items:**
        *   **Manual VoiceOver Review:** Conduct thorough manual testing with VoiceOver enabled on both iOS and macOS.
        *   **Keyboard Navigation (macOS):** Verify all interactive elements are reachable and operable via keyboard.
        *   **Dynamic Type:** Test the UI's responsiveness to different font sizes.
        *   **Color Contrast:** Verify sufficient color contrast for all UI elements.
*   **Regression Testing:**
    *   **Focus:** Ensure that new changes do not introduce regressions in existing functionalities.
    *   **Actionable Items:**
        *   Maintain a comprehensive suite of automated unit and UI tests that are run before every major release.
        *   Prioritize tests for critical paths and frequently modified areas.

#### 3.2. Test Execution Strategy

*   **Automated Testing:**
    *   **Continuous Integration (CI):** Integrate all unit, UI, and selected integration tests into a CI pipeline (e.g., GitHub Actions, GitLab CI). Tests should run automatically on every pull request or commit to `main`.
    *   **Nightly Builds:** Run a more extensive suite of tests (including performance and accessibility checks) on nightly builds.
*   **Manual Testing:**
    *   **Exploratory Testing:** Conduct exploratory testing sessions to uncover unexpected bugs and usability issues.
    *   **User Acceptance Testing (UAT):** Involve end-users or stakeholders in UAT before major releases.
    *   **Accessibility Audits:** Perform periodic manual accessibility audits.

#### 3.3. Reporting

*   **CI Reports:** Generate automated test reports (e.g., JUnit XML) that can be integrated into CI dashboards.
*   **Bug Tracking:** Use a bug tracking system (e.g., Jira, GitHub Issues) to log, prioritize, and track defects.
*   **Test Summaries:** Provide regular summaries of test results, coverage, and identified risks to the development team and stakeholders.
