# Required Monthly Feature - Architectural Plan

## Overview

This document outlines the architectural approach for implementing the "Required Monthly" feature based on comprehensive review by the architecture-critic agent. The plan ensures seamless integration with the existing SwiftUI/SwiftData architecture while maintaining performance and code quality.

## Architectural Assessment

### Current Architecture Strengths
- Strong Service Layer Pattern with clean separation
- Proper MVVM Implementation with @MainActor and ObservableObject
- Well-structured SwiftData models with proper relationships
- Multi-platform architecture via PlatformCapabilities
- Dependency injection through DIContainer

### Critical Issues Identified
1. **Service Layer Circular Dependencies**: Avoided through proper service orchestration
2. **State Management Complexity**: Addressed with dedicated ViewModels
3. **SwiftData Model Performance**: Solved using separate MonthlyPlan model

## Core Architectural Decisions

### 1. Service Layer Integration

```swift
@MainActor
class MonthlyPlanningService: ObservableObject {
    private let exchangeRateService: ExchangeRateService
    private let goalCalculationService: GoalCalculationService
    private let notificationManager = NotificationManager.shared
    
    // Performance cache
    private var planCache: [UUID: MonthlyPlan] = [:]
    private let cacheExpiration: TimeInterval = 300 // 5 minutes
    
    init(exchangeRateService: ExchangeRateService) {
        self.exchangeRateService = exchangeRateService
        self.goalCalculationService = GoalCalculationService()
    }
    
    func calculateMonthlyRequirements(for goals: [Goal]) async -> [MonthlyRequirement] {
        // Batch processing with currency conversion
    }
}
```

### 2. Data Model Strategy

**Separate MonthlyPlan Model** (not Goal extension):

```swift
@Model
final class MonthlyPlan: @unchecked Sendable {
    @Attribute(.unique) var id: UUID
    var goalId: UUID
    var requiredMonthly: Double
    var flexState: FlexState = .flexible
    var lastCalculated: Date
    var customAmount: Double? // User override
    
    enum FlexState: String, Codable {
        case protected   // Cannot be reduced
        case flexible    // Can be adjusted
        case skipped    // Temporarily excluded
    }
}
```

### 3. State Management

```swift
@MainActor
class MonthlyPlanningViewModel: ObservableObject {
    @Published var monthlyPlans: [MonthlyPlan] = []
    @Published var totalRequired: Double = 0
    @Published var flexAdjustment: Double = 1.0 // 0.5 to 1.5
    @Published var adjustmentPreview: [UUID: Double] = [:]
    
    private let planningService: MonthlyPlanningService
    private var cancellables = Set<AnyCancellable>()
    
    // Reactive updates when goals change
    func observeGoalChanges() {
        NotificationCenter.default.publisher(for: .goalUpdated)
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.recalculatePlans() }
            }
            .store(in: &cancellables)
    }
}
```

### 4. Multi-Platform Architecture

```swift
// Shared protocol for monthly planning views
protocol MonthlyPlanningViewProtocol: View {
    var viewModel: MonthlyPlanningViewModel { get }
}

// Platform-specific implementations
struct iOSMonthlyPlanningView: MonthlyPlanningViewProtocol {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    
    var body: some View {
        // Compact mobile layout with bottom sheet
    }
}

struct macOSMonthlyPlanningView: MonthlyPlanningViewProtocol {
    @ObservedObject var viewModel: MonthlyPlanningViewModel
    
    var body: some View {
        // Sidebar panel with detailed controls
    }
}
```

## Performance Optimization Strategy

### 1. Batch Processing
```swift
extension MonthlyPlanningService {
    func batchCalculateWithCache(goals: [Goal]) async -> [MonthlyPlan] {
        // Check cache first
        let validPlans = goals.compactMap { goal in
            if let cached = planCache[goal.id],
               Date().timeIntervalSince(cached.lastCalculated) < cacheExpiration {
                return cached
            }
            return nil
        }
        
        // Calculate missing plans in parallel
        let missingGoals = goals.filter { goal in
            !validPlans.contains { $0.goalId == goal.id }
        }
        
        let newPlans = await withTaskGroup(of: MonthlyPlan?.self) { group in
            for goal in missingGoals {
                group.addTask { await self.calculatePlan(for: goal) }
            }
            
            var results: [MonthlyPlan] = []
            for await plan in group {
                if let plan = plan {
                    results.append(plan)
                    self.planCache[plan.goalId] = plan
                }
            }
            return results
        }
        
        return validPlans + newPlans
    }
}
```

### 2. Key Performance Strategies
- **Aggressive Caching**: 5-minute cache expiration for calculations
- **Background Processing**: Use Task.detached for heavy calculations
- **Batch Currency Conversion**: Minimize API calls
- **Progressive Loading**: Show cached values immediately, update in background

## Integration Points

### Dashboard Integration
```swift
struct DashboardMonthlyWidget: View {
    @StateObject private var monthlyVM = MonthlyPlanningViewModel()
    
    var body: some View {
        VStack {
            HStack {
                Text("Required This Month")
                Spacer()
                Text(monthlyVM.totalRequired.formatted(.currency))
            }
            
            if monthlyVM.hasFlexibleGoals {
                FlexSlider(value: $monthlyVM.flexAdjustment)
                    .onChange(of: monthlyVM.flexAdjustment) { _, newValue in
                        Task { await monthlyVM.previewAdjustment(newValue) }
                    }
            }
        }
    }
}
```

### Notification Integration
```swift
extension NotificationManager {
    func scheduleMonthlyReminders(plan: MonthlyPlan, goal: Goal) async {
        let content = UNMutableNotificationContent()
        content.title = "Monthly Payment Due: \(goal.name)"
        content.body = "Required: \(plan.requiredMonthly.formatted(.currency))"
        content.categoryIdentifier = "MONTHLY_PAYMENT"
        
        content.userInfo = [
            "goalId": goal.id.uuidString,
            "requiredAmount": plan.requiredMonthly,
            "planId": plan.id.uuidString
        ]
    }
}
```

## Testing Architecture

```swift
class MonthlyPlanningTests: XCTestCase {
    var sut: MonthlyPlanningService!
    var mockExchangeService: MockExchangeRateService!
    
    @Test("Calculate basic monthly requirement")
    func testBasicMonthlyCalculation() async {
        // Given
        let goal = TestHelpers.createGoal(
            target: 12000,
            currentTotal: 3000,
            monthsRemaining: 3
        )
        
        // When
        let plan = await sut.calculatePlan(for: goal)
        
        // Then
        #expect(plan.requiredMonthly == 3000) // (12000-3000)/3
    }
    
    @Test("Flex adjustment redistribution")
    func testFlexRedistribution() async {
        // Test complex redistribution logic
    }
}
```

## Risk Mitigation

### Risk 1: Performance Degradation
**Mitigation**: Progressive calculation - show cached values immediately, update in background

### Risk 2: Complex State Synchronization
**Mitigation**: Use Combine publishers for reactive updates with proper debouncing

### Risk 3: SwiftData Migration
**Mitigation**: Version the MonthlyPlan model separately, allowing gradual migration

### Risk 4: Currency API Rate Limits
**Mitigation**: Batch all currency conversions and implement exponential backoff

## Implementation Timeline

### Phase 1: Core Infrastructure (Week 1)
1. Create MonthlyPlanningService with batch calculations and caching
2. Add MonthlyPlan SwiftData model (separate from Goal model)
3. Integrate MonthlyPlanningService with DIContainer
4. Add comprehensive unit tests for financial calculations

### Phase 2: UI Integration (Week 2)
1. Create MonthlyPlanningViewModel with reactive updates
2. Implement Dashboard monthly widget with performance optimization
3. Build platform-specific Planning views (iOS/macOS)
4. Add integration tests for service coordination

### Phase 3: Advanced Features (Week 3)
1. Implement FlexAdjustmentService with redistribution logic
2. Add interactive Flex slider with live preview and debouncing
3. Enhance NotificationManager for monthly payment reminders
4. Add UI tests for complex user interactions

### Phase 4: Polish & Optimization (Week 4)
1. Optimize performance with aggressive caching and background processing
2. Implement currency API batching and rate limit handling
3. Add accessibility features and WCAG 2.1 AA compliance
4. Create comprehensive documentation and migration guides

## Key Success Factors

1. **Maintain separation of concerns** by creating dedicated services
2. **Avoid model bloat** by using separate MonthlyPlan entities
3. **Leverage existing patterns** like DIContainer and service coordination
4. **Optimize aggressively** for performance with caching and batching
5. **Test comprehensively** given the financial calculations involved

This architectural approach maintains consistency with existing patterns while adding powerful new functionality that enhances the app's value proposition for users managing multiple cryptocurrency savings goals.

---

**Last Updated**: August 9, 2025  
**Status**: Architecture Complete, Ready for Implementation  
**Priority**: High - Core Feature Enhancement