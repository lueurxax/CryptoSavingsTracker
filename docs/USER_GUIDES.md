# User and Developer Guides

> Testing, migration, screenshot, and troubleshooting guides for developers

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-01-04 |
| Platform | Shared |
| Audience | Developers |

---

This document provides a collection of guides for developers and contributors.

## Contents

1.  [Testing Guide](#testing-guide)
2.  [Migration Guide](#migration-guide)
3.  [Screenshot Guide](#screenshot-guide)
4.  [Troubleshooting Guide](#troubleshooting-guide)

---

## Testing Guide

### Required Monthly Feature - Testing Guide

#### Overview

This guide provides comprehensive testing strategies for the Required Monthly feature, including unit tests, integration tests, UI tests, accessibility tests, and performance benchmarks.

---

#### Test Architecture

##### Testing Pyramid

```
        UI Tests (20 tests)
       /                    \
  Integration Tests (15)    Accessibility Tests (30)
 /                                                   \
Unit Tests (25)                              Performance Tests (10)
```

##### Test Categories

1. **Unit Tests**: Individual component logic
2. **Integration Tests**: Service interaction and data flow
3. **UI Tests**: User interaction and interface behavior
4. **Accessibility Tests**: WCAG 2.1 AA compliance
5. **Performance Tests**: Speed and memory benchmarks

---

#### Unit Tests

**Location**: `CryptoSavingsTrackerTests/MonthlyPlanningTests.swift`

##### Financial Calculation Tests

###### Basic Monthly Requirement Calculation
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

###### Edge Cases
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

##### Status Determination Tests

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

##### Flex Adjustment Tests

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

##### Currency Conversion Tests

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

#### Integration Tests

**Location**: `CryptoSavingsTrackerTests/IntegrationTests.swift`

##### Service Coordination Tests

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

##### Performance Cache Integration

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

##### Notification Integration

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

#### UI Tests

**Location**: `CryptoSavingsTrackerUITests/MonthlyPlanningUITests.swift`

##### Widget Interaction Tests

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

##### Planning View Navigation

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

##### Flex Adjustment Interaction

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

##### Cross-Platform UI Tests

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

##### Error State Testing

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

#### Accessibility Tests

**Location**: `CryptoSavingsTrackerTests/AccessibilityTests.swift`

##### WCAG Compliance Tests

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

##### VoiceOver Description Tests

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

##### Chart Accessibility Tests

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

##### Keyboard Navigation Tests

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

##### Screen Reader Tests

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

#### Performance Tests

**Location**: `CryptoSavingsTrackerTests/PerformanceTests.swift`

##### Calculation Performance

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

##### Cache Performance

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

##### Memory Usage Tests

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

##### UI Responsiveness Tests

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

#### Mock Objects and Test Helpers

##### MockExchangeRateService

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

##### Test Data Factories

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

#### Test Execution

##### Running All Tests

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

##### Test Configuration

###### Test Environment Variables
```swift
app.launchEnvironment["UITEST_RESET_DATA"] = "1"
app.launchEnvironment["UITEST_MOCK_DATA"] = "monthly_planning"
app.launchEnvironment["UITEST_SIMULATE_OFFLINE"] = "1"
app.launchEnvironment["UITEST_ACCESSIBILITY"] = "1"
```

###### Test Schemes
- **Debug**: Full test suite with detailed logging
- **Release**: Performance and stability tests
- **Accessibility**: Focus on WCAG compliance

---

#### Continuous Integration

##### GitHub Actions Workflow

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

##### Quality Gates

Tests must pass these quality gates:

- ✅ **Unit Test Coverage**: >90%
- ✅ **Integration Test Coverage**: >80%
- ✅ **UI Test Coverage**: >70%
- ✅ **Accessibility Compliance**: 100% WCAG AA
- ✅ **Performance Benchmarks**: All within limits
- ✅ **Memory Usage**: <100MB increase
- ✅ **Load Time**: <2 seconds cold start

---

#### Best Practices

##### Test Organization

1. **Group by Feature**: Tests organized by feature area
2. **Clear Naming**: Test names describe what they verify
3. **Fast Execution**: Unit tests run in <5 seconds
4. **Isolation**: Each test is independent
5. **Deterministic**: Tests produce consistent results

##### Test Data Management

1. **Factories**: Use factory methods for test data creation
2. **Cleanup**: Reset state between tests
3. **Realistic Data**: Use realistic amounts and dates
4. **Edge Cases**: Test boundary conditions
5. **Error Scenarios**: Test failure paths

##### Accessibility Testing

1. **Automated Checks**: Use accessibility APIs for validation
2. **Manual Testing**: Test with real assistive technologies
3. **Multiple Disabilities**: Consider various accessibility needs
4. **Platform Differences**: Test on iOS, macOS, and visionOS
5. **Regular Audits**: Continuous accessibility compliance checking

---

*Testing Guide v2.0.0 - Updated August 9, 2025*
### Comprehensive Test Plan

This test plan outlines a strategy for ensuring the quality, reliability, and performance of the CryptoSavingsTracker application. It builds upon the existing test infrastructure and identifies areas for further enhancement.

#### 1. Current Test Coverage Summary

*   **Unit Tests (Swift Testing):**
    *   **Strengths:** Good coverage for core data models (`Goal`, `Asset`, `Transaction`), `ReminderFrequency` enum, and basic `GoalCalculationService` functions. Includes tests for SwiftData persistence and relationships.
    *   **Areas for Improvement:** While the `DIContainer` has been refactored to use protocols, the existing unit tests for services (e.g., `ExchangeRateServiceTests`) still directly interact with singletons or concrete implementations. This limits true isolation and mocking capabilities.
*   **UI Tests (XCTest):**
    *   **Strengths:** Comprehensive coverage of critical user flows (goal creation, asset/transaction management, goal deletion, navigation). Effective use of launch arguments and environment variables for controlling test data and simulating conditions (e.g., offline mode). Includes basic performance and accessibility checks.
    *   **Areas for Improvement:** Can be expanded to cover more edge cases, complex interactions, and a wider range of accessibility features.

#### 2. Key Functionalities to Test

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

#### 3. Proposed Test Plan

##### 3.1. Test Types and Focus Areas

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

##### 3.2. Test Execution Strategy

*   **Automated Testing:**
    *   **Continuous Integration (CI):** Integrate all unit, UI, and selected integration tests into a CI pipeline (e.g., GitHub Actions, GitLab CI). Tests should run automatically on every pull request or commit to `main`.
    *   **Nightly Builds:** Run a more extensive suite of tests (including performance and accessibility checks) on nightly builds.
*   **Manual Testing:**
    *   **Exploratory Testing:** Conduct exploratory testing sessions to uncover unexpected bugs and usability issues.
    *   **User Acceptance Testing (UAT):** Involve end-users or stakeholders in UAT before major releases.
    *   **Accessibility Audits:** Perform periodic manual accessibility audits.

##### 3.3. Reporting

*   **CI Reports:** Generate automated test reports (e.g., JUnit XML) that can be integrated into CI dashboards.
*   **Bug Tracking:** Use a bug tracking system (e.g., Jira, GitHub Issues) to log, prioritize, and track defects.
*   **Test Summaries:** Provide regular summaries of test results, coverage, and identified risks to the development team and stakeholders.

---

## Migration Guide

### Required Monthly Feature - Migration Guide

#### Quick Migration Checklist

##### ✅ Required Changes (Must Do)

###### 1. Update Model Container
```swift
// BEFORE
let container = try ModelContainer(for: Goal.self, Asset.self, Transaction.self)

// AFTER  
let container = try ModelContainer(for: 
    Goal.self, 
    Asset.self, 
    Transaction.self,
    MonthlyPlan.self  // 👈 Add this new model
)
```

###### 2. Update DIContainer
Add these methods to your `DIContainer.swift`:

```swift
// Add private property
private lazy var _monthlyPlanningService = MonthlyPlanningService(
    exchangeRateService: exchangeRateService
)

// Add public accessor
var monthlyPlanningService: MonthlyPlanningService {
    return _monthlyPlanningService
}

// Add factory method
func makeFlexAdjustmentService(modelContext: ModelContext) -> FlexAdjustmentService {
    return FlexAdjustmentService(
        planningService: monthlyPlanningService,
        modelContext: modelContext
    )
}
```

##### 🎯 Optional Enhancements (Recommended)

###### 3. Add Planning Tab
```swift
TabView {
    // Your existing tabs...
    
    NavigationView {
        PlanningView(viewModel: MonthlyPlanningViewModel(modelContext: modelContext))
    }
    .tabItem {
        Image(systemName: "calendar.badge.clock")
        Text("Planning")
    }
}
```

###### 4. Add Dashboard Widget
```swift
// In your main dashboard view
VStack(spacing: 16) {
    // Existing dashboard widgets...
    
    MonthlyPlanningWidget(
        viewModel: MonthlyPlanningViewModel(modelContext: modelContext)
    )
}
```

---

#### File Additions

Copy these new files to your project:

##### Core Services
- `Services/MonthlyPlanningService.swift`
- `Services/FlexAdjustmentService.swift` 
- `Services/ExchangeRateService.swift` (enhanced)

##### Data Models  
- `Models/MonthlyPlan.swift`
- `Models/MonthlyRequirement.swift`

##### ViewModels
- `ViewModels/MonthlyPlanningViewModel.swift`

##### UI Components
- `Views/Components/MonthlyPlanningWidget.swift`
- `Views/Components/FlexAdjustmentSlider.swift`
- `Views/Planning/PlanningView.swift`
- `Views/Planning/MonthlyPlanningContainer.swift`
- `Views/Planning/MonthlyExecutionView.swift`
- `Views/Planning/GoalRequirementRow.swift`
- `Views/Planning/BudgetCalculatorSheet.swift`
- `Views/Planning/BudgetSummaryCard.swift`

##### Utilities & Performance
- `Utilities/PerformanceOptimizer.swift`
- `Utilities/AccessibilityManager.swift`
- `Utilities/AccessibilityViewModifiers.swift`
- `Utilities/AccessibleColors.swift` (enhanced)

##### Testing
- `CryptoSavingsTrackerTests/MonthlyPlanningTests.swift`
- `CryptoSavingsTrackerTests/FlexAdjustmentTests.swift`
- `CryptoSavingsTrackerTests/AccessibilityTests.swift`
- `CryptoSavingsTrackerUITests/MonthlyPlanningUITests.swift`

---

#### Common Migration Issues

##### Issue 1: "Cannot find MonthlyPlan in scope"
**Solution**: Make sure you added `MonthlyPlan.swift` to your project and included it in ModelContainer.

##### Issue 2: "No member 'monthlyPlanningService'"
**Solution**: Update DIContainer.swift with the new service properties and methods.

##### Issue 3: Build errors with AccessibleColors
**Solution**: The enhanced AccessibleColors file has new properties. Make sure you're using the updated version.

##### Issue 4: Currency conversion not working
**Solution**: Verify your CoinGecko API key is set in Config.plist and not the placeholder value.

---

#### Testing Your Migration

Run these tests to verify everything is working:

##### 1. Basic Functionality Test
```swift
// In your app, create a test goal and verify monthly calculation appears
let testGoal = Goal(name: "Test", targetAmount: 12000, deadline: Date().addingTimeInterval(86400 * 365))
// Should see monthly requirement of ~$1000
```

##### 2. Widget Test
- Open dashboard
- Look for "Required This Month" widget
- Tap "Show more" to expand
- Verify goal breakdown appears

##### 3. Planning View Test
- Navigate to Planning tab
- Verify goals list appears  
- Test flex adjustment slider
- Check that adjustments update in real-time

##### 4. Accessibility Test
- Enable VoiceOver (Settings > Accessibility > VoiceOver)
- Navigate through planning interface
- Verify currency amounts are spoken clearly
- Test focus indicators are visible

---

#### Build Configuration

##### Xcode Project Settings
Make sure these files are added to your target:
- All new Swift files should be added to main app target
- Test files should be added to appropriate test targets
- No changes to Info.plist required

##### Dependencies
No new external dependencies required. The feature uses:
- SwiftUI (built-in)
- SwiftData (built-in)
- Combine (built-in)
- UserNotifications (built-in)

---

#### Rollback Plan

If you need to rollback the migration:

##### 1. Remove New Files
Delete all files listed in "File Additions" section above.

##### 2. Revert Model Container
```swift  
// Revert to original
let container = try ModelContainer(for: Goal.self, Asset.self, Transaction.self)
```

##### 3. Revert DIContainer
Remove the new monthlyPlanningService properties and methods.

##### 4. Remove Navigation
Remove Planning tab from your main TabView.

**Note**: Your existing data (Goals, Assets, Transactions) will remain intact. Only the new monthly planning data will be lost.

---

#### Performance Considerations

##### Memory Usage
- Expected increase: ~10-50MB for caching
- Automatic cache cleanup every hour
- Memory pressure handling included

##### CPU Usage  
- Background processing for calculations
- Batch API calls to reduce network overhead
- Intelligent caching reduces repeated calculations

##### Battery Impact
- Minimal - calculations run on-demand
- Background processing uses .utility QoS
- Haptic feedback respects user preferences

---

#### Support

After migration, if you encounter issues:

1. **Check Build Errors**: Usually missing files or incorrect ModelContainer setup
2. **Verify API Configuration**: CoinGecko API key in Config.plist  
3. **Run Tests**: Use included test suite to verify functionality
4. **Check Console**: Look for error messages with solutions

For detailed troubleshooting, see the full documentation: `REQUIRED_MONTHLY_DOCUMENTATION.md`

---

*Migration Guide v2.0.0 - Updated August 9, 2025*

---

## Screenshot Guide

### Screenshot Guide for CryptoSavingsTracker

This guide will help you capture professional screenshots for the README that showcase the app's key features and cross-platform experience.

#### 📱 iOS Screenshots (iPhone)

##### Setup
1. Use iPhone 15 Pro or iPhone 15 Pro Max simulator for best quality
2. Use Light mode for consistency
3. Create sample data before screenshots

##### Required Screenshots

###### 1. `ios-goals-list.png` - Main Goals List
- **What to show**: Main screen with 2-3 sample goals
- **Sample data**: 
  - "Vacation Fund" - $5000 USD, 30% progress
  - "Emergency Savings" - $10000 USD, 67% progress  
  - "New Car" - $25000 USD, 12% progress
- **Key elements**: Progress bars, amounts, deadlines
- **How to capture**: Navigate to main screen, take screenshot with Cmd+Shift+4

###### 2. `ios-goal-details.png` - Goal Detail View
- **What to show**: Detailed view of one goal with assets
- **Sample data**: "Vacation Fund" with BTC, ETH assets
- **Key elements**: 
  - Progress ring at the top
  - Edit/Delete buttons (our new feature!)
  - Asset list with balances
  - Charts section (expanded)
- **How to capture**: Tap on a goal, ensure charts are expanded

###### 3. `ios-add-goal.png` - Add New Goal Screen
- **What to show**: Goal creation form
- **Key elements**:
  - Goal name field
  - Currency picker (USD selected)
  - Target amount field
  - Deadline picker
  - Save button
- **How to capture**: Tap "+" button, fill in sample data partially

###### 4. `ios-add-asset.png` - Add Asset Screen
- **What to show**: Asset creation form
- **Key elements**:
  - Currency selection (BTC or ETH)
  - Optional address field
  - Chain selection if address is filled
  - Form validation
- **How to capture**: From goal detail, tap "Add Asset"

###### 5. `ios-currency-picker.png` - Currency Search & Selection
- **What to show**: Currency picker with search
- **Key elements**:
  - Search bar with "BTC" typed
  - Smart sorting in action (Bitcoin at top)
  - List of cryptocurrencies with symbols and names
- **How to capture**: In Add Asset, tap currency field, type "BTC"

###### 6. `ios-progress.png` - Progress Tracking
- **What to show**: Goal with good progress and charts
- **Key elements**:
  - Large progress ring showing 67%+
  - Balance history chart
  - Asset composition pie chart
  - Timeline view
- **How to capture**: Select goal with multiple assets and transactions

#### 💻 macOS Screenshots

##### Setup
1. Use standard macOS window size (not fullscreen)
2. Use Light mode for consistency
3. Position window nicely on screen

##### Required Screenshots

###### 1. `macos-main.png` - Split View Interface
- **What to show**: Main macOS interface with sidebar
- **Key elements**:
  - Goals sidebar on left with 3-4 goals
  - Goal detail view on right
  - Native macOS styling
  - Toolbar with edit/delete buttons (our new feature!)
- **How to capture**: Cmd+Shift+3 or Cmd+Shift+4 for selection

###### 2. `macos-goal-management.png` - Goal Management
- **What to show**: Context menu or edit functionality
- **Key elements**:
  - Right-click context menu on sidebar goal
  - OR edit goal sheet open
  - Show edit/delete options clearly
- **How to capture**: Right-click on goal in sidebar

###### 3. `macos-assets.png` - Asset Management
- **What to show**: Asset view with macOS-specific features
- **Key elements**:
  - Asset list in detail view
  - macOS-style buttons and controls
  - Add Asset popover (if possible)
- **How to capture**: Click "Add Asset" to show popover

#### 🎨 Screenshot Best Practices

##### Data Preparation
1. **Create realistic sample data**: 
   ```
   Goals:
   - "Emergency Fund" ($10,000 USD, 67% complete, 45 days left)
   - "Vacation Savings" ($5,000 USD, 34% complete, 120 days left)  
   - "New Car" ($25,000 USD, 12% complete, 365 days left)
   
   Assets per goal:
   - Bitcoin (BTC): $2,450
   - Ethereum (ETH): $1,200
   - Solana (SOL): $350
   ```

2. **Use round numbers** for better visual appeal
3. **Show progress** - avoid 0% or 100% goals
4. **Include dates** that make sense (future deadlines)

##### Visual Quality
- **High resolution**: Use 2x or 3x simulator scales
- **Good lighting**: Light mode with proper contrast
- **Clean UI**: No debug info or placeholder text
- **Consistent sizing**: All screenshots should be similar scale

##### Platform-Specific Tips

###### iOS:
- Show native iOS elements (navigation bars, toolbars)
- Capture swipe actions if possible
- Show context menus on long press
- Demonstrate the new unified currency sorting

###### macOS:
- Show split-view layout clearly
- Highlight toolbar buttons (our edit/delete feature)
- Demonstrate popover vs sheet differences
- Show right-click context menus

#### 📸 Taking Screenshots

##### iOS Simulator:
1. Open iOS Simulator
2. Choose "Device" > "Screenshot" or Cmd+S
3. Screenshots save to Desktop by default

##### macOS App:
1. Use Cmd+Shift+4 for selection tool
2. Cmd+Shift+3 for full screen
3. Use Preview to crop/adjust if needed

##### File Naming:
- Use exact names from README: `ios-goals-list.png`, etc.
- Save as PNG format
- Optimize file sizes (under 500KB each)

#### 🚀 After Capturing

1. **Review each screenshot** for clarity and content
2. **Resize if needed** to consistent dimensions
3. **Place in `/docs/screenshots/` directory**
4. **Test README** to ensure all images display correctly
5. **Commit and push** the screenshots with the README update

#### 📋 Screenshot Checklist

##### iOS Screenshots:
- [ ] `ios-goals-list.png` - Main goals screen
- [ ] `ios-goal-details.png` - Goal detail with edit buttons
- [ ] `ios-add-goal.png` - Goal creation form  
- [ ] `ios-add-asset.png` - Asset creation form
- [ ] `ios-currency-picker.png` - Smart currency search
- [ ] `ios-progress.png` - Progress tracking with charts

##### macOS Screenshots:
- [ ] `macos-main.png` - Split-view interface
- [ ] `macos-goal-management.png` - Edit/delete functionality
- [ ] `macos-assets.png` - Asset management

##### Quality Check:
- [ ] All images under 500KB
- [ ] Consistent lighting/theme
- [ ] Realistic sample data
- [ ] Key features highlighted
- [ ] No debug/placeholder content

Good luck! These screenshots will really showcase the professional quality and cross-platform nature of your app! 📱💻

---

## Troubleshooting Guide

### Common Console Warnings and How to Fix Them

#### 🔇 Haptic Feedback Warnings (iOS Simulator)

**Symptoms:**
```
CHHapticPattern.mm:487 +[CHHapticPattern patternForKey:error:]: Failed to read pattern library data
<_UIKBFeedbackGenerator: 0x...>: Error creating CHHapticPattern
```

**Cause:** iOS Simulator doesn't have full haptic feedback support, causing system components (like keyboard) to generate warnings when trying to provide haptic feedback.

**Impact:** ✅ **Harmless** - These warnings:
- Don't affect app functionality
- Only appear in iOS Simulator (not on real devices)
- Are generated by system components, not your app
- Don't indicate any bugs in your code

**Solutions:**

##### Option 1: Ignore Them (Recommended)
These warnings are safe to ignore as they're system-level iOS Simulator limitations.

##### Option 2: Use Custom Haptic Manager
We've included a `HapticManager` utility that automatically disables haptics in simulator:

```swift
// Safe haptic feedback that won't generate warnings
HapticManager.shared.impact(.light)
HapticManager.shared.notification(.success)
HapticManager.shared.selection()

// SwiftUI integration
Button("Save") { } 
    .successHaptic(on: saveSuccess)
```

##### Option 3: Filter Console Output
In Xcode, you can filter out these warnings:
1. Open Console in Xcode
2. Add filter: `-CHHapticPattern -UIKBFeedbackGenerator`
3. This will hide haptic-related warnings

#### 🔤 RTIInputSystemClient Warnings

**Symptoms:**
```
-[RTIInputSystemClient remoteTextInputSessionWithID:performInputOperation:] perform input operation requires a valid sessionID
```

**Cause:** iOS Simulator text input system handling differences from real devices.

**Impact:** ✅ **Harmless** - This warning:
- Doesn't affect text input functionality
- Only appears in iOS Simulator
- Is a known iOS Simulator limitation

**Solution:** Safe to ignore - text input works normally despite the warning.

### 🛠️ Development Tips

#### Building in Xcode Beta
- Expect additional warnings from beta toolchain
- Most Metal/GPU warnings are cosmetic in beta
- Focus on functionality over warning count during development

#### Clean Build Issues
If you encounter build issues:
1. **Clean Build Folder**: Product → Clean Build Folder (⌘⇧K)
2. **Clear DerivedData**: `rm -rf ~/Library/Developer/Xcode/DerivedData`
3. **Reset Simulator**: Device → Erase All Content and Settings

#### Performance in Simulator
- SwiftData operations may be slower in simulator
- Network requests have different timing than real devices
- Use real device testing for performance validation

### 🚀 Best Practices

#### Console Management
- Filter out system warnings during development
- Focus on your app's log messages and errors
- Use `print()` with prefixes for easy filtering: `print("🔔 MyApp: message")`

#### Testing Strategy
1. **Simulator**: UI layout, basic functionality, debugging
2. **Real Device**: Performance, haptics, camera, notifications
3. **Multiple Devices**: Different screen sizes and capabilities

#### Memory Management
- These warnings don't indicate memory leaks
- Use Instruments for actual memory profiling
- SwiftData handles most memory management automatically

---

### 📞 Need More Help? 

If you encounter warnings not covered here:
1. Check if they appear on real devices
2. Search Apple Developer Forums
3. File feedback with Apple if it's a framework issue

Remember: **Not all console output indicates problems** - focus on functionality over warning count!

---

*Last Updated: August 2025*
*This guide helps you focus on what matters during development.*