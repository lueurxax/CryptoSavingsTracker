# 🏗️ CryptoSavingsTracker Architecture Documentation

## Overview

CryptoSavingsTracker is a multi-platform SwiftUI application built with SwiftData persistence, supporting iOS, macOS, and visionOS. This document provides a comprehensive guide to the application's architecture, component organization, and platform abstractions.

## 📋 Table of Contents

1. [Platform Architecture](#platform-architecture)
2. [View Component Map](#view-component-map) 
3. [Goal List Implementation Guide](#goal-list-implementation-guide)
4. [Service Layer Architecture](#service-layer-architecture)
5. [Data Flow Patterns](#data-flow-patterns)
6. [File Organization](#file-organization)
7. [Component Relationships](#component-relationships)
8. [Architectural Patterns](#architectural-patterns)
9. [Required Monthly Feature - Architectural Plan](#required-monthly-feature---architectural-plan)
10. [Architecture Review](#architecture-review)

---

## Platform Architecture

### Platform Abstraction Strategy

The app uses **conditional platform abstraction** with a hybrid approach:

```swift
// Primary abstraction through ContentView platform switching
struct ContentView: View {
    @Environment(\.platformCapabilities) private var platform
    
    var body: some View {
        Group {
            switch platform.navigationStyle {
            case .stack: iOSContentView()
            case .splitView: macOSContentView()
            case .tabs: // Future implementation
            }
        }
    }
}
```

### Platform Capabilities System

Location: `/CryptoSavingsTracker/Utilities/PlatformCapabilities.swift`

```swift
enum NavigationStylePreference {
    case stack     // iOS compact
    case splitView // macOS, iPad
    case tabs      // Future: tvOS, watchOS
}
```

---

## View Component Map

### 🎯 **Goal Display Components** *(Critical for Maintainability)*

> **⚠️ IMPORTANT**: When modifying goal display logic, you must update ALL these components

| Platform | Component | File Location | Purpose |
|----------|-----------|---------------|---------|
| **iOS** | `GoalRowView` | `/Views/GoalsListView.swift` | Main iOS goal list rows |
| **macOS** | `GoalSidebarRow` | `/Views/Components/GoalsSidebarView.swift` | macOS sidebar goal entries |
| **Shared** | `GoalRowView` (alt) | `/Views/ContentView.swift` (GoalsList) | Alternative iOS implementation |
| **Shared** | `GoalRowView` (alt) | `/Views/Goals/GoalsListContainer.swift` | iOS container variant |

#### 🔧 **Goal Component Responsibilities**

```swift
// Common functionality across ALL goal display components:
// ✅ Emoji display (with SF Symbol fallback)
// ✅ Progress bar with currency-converted values
// ✅ Status badges (Achieved, On Track, Behind)
// ✅ Days remaining with urgency indicators
// ✅ Description preview (if available)
// ✅ Accessibility support
```

### 📊 **Progress Calculation Architecture**

> **🎯 KEY INSIGHT**: All goal lists must use `GoalCalculationService` for accurate progress

```swift
// ❌ DEPRECATED - Returns 0% fallback values
let progress = await goal.getProgress()

// ✅ CORRECT - Returns currency-converted progress
let progress = await GoalCalculationService.getProgress(for: goal)
```

**Service Location**: `/Services/GoalCalculationService.swift`
**Purpose**: Centralizes currency conversion and progress calculation logic

---

## Goal List Implementation Guide

### Finding Goal List Components

When you need to modify goal display logic:

1. **iOS Primary**: Look in `GoalsListView.swift` for `GoalRowView`
2. **macOS Primary**: Look in `GoalsSidebarView.swift` for `GoalSidebarRow`
3. **Alternative implementations**: Search for `GoalRowView` usage across codebase
4. **Progress calculation**: Always use `GoalCalculationService` for currency conversion

### Component Unification Status

| Status | Component | Notes |
|--------|-----------|-------|
| ✅ **Unified (Phase 1)** | Goal row display logic | `UnifiedGoalRowView` with `GoalRowViewModel` |
| ✅ **Unified** | Progress calculation | Uses GoalCalculationService |
| ✅ **Unified** | Emoji/description data | Shared Goal model properties |
| ✅ **Enhanced (Phase 2)** | Platform abstraction | Enhanced `PlatformCapabilities` with modal styles, haptics, window management |

---

## Service Layer Architecture

### Calculation Services

```
Services/
├── AllocationService.swift           ← **Manages asset allocations to goals (NEW)**
├── GoalCalculationService.swift      ← **Allocation-aware progress calculation**
├── ExchangeRateService.swift         ← Currency conversion
├── BalanceService.swift              ← Blockchain balance fetching (DI)
├── TransactionService.swift          ← Transaction history fetching (DI)
├── TatumService.swift                ← Blockchain data wrapper (DI)
├── MonthlyPlanningService.swift      ← Required monthly calculations
└── FlexAdjustmentService.swift       ← Payment flexibility
```

### Service Responsibilities

| Service | Purpose | Initialization | Used By |
|---------|---------|---------------|---------|
| `AllocationService` | Manages the percentage-based allocation of assets to goals. | DI (ModelContext) | Asset & Goal management views |
| `GoalCalculationService` | Calculates goal progress based on asset allocations and currency conversion. | Singleton | **ALL goal display components** |
| `ExchangeRateService` | Real-time exchange rates | Singleton | Goal calculations, displays |
| `BalanceService` | On-chain balance fetching | DI (TatumClient, ChainService) | Asset management, calculations |
| `TransactionService` | Transaction history | DI (TatumClient, ChainService) | Transaction views |
| `TatumService` | Blockchain API wrapper | DI (TatumClient, ChainService) | Views, ViewModels |
| `MonthlyPlanningService` | Required payment calculations | DI (ExchangeRateService) | Planning views, widgets |

### Dependency Injection Architecture

```swift
// Services now use dependency injection instead of singletons
let balanceService = BalanceService(
    client: TatumClient.shared,
    chainService: ChainService.shared
)

// DIContainer manages service creation with error recovery
DIContainer.shared.coinGeckoService     // Returns service or fallback
DIContainer.shared.exchangeRateService  // Automatic error handling
DIContainer.shared.makeDashboardViewModel() // ViewModel factory with injected deps
```

#### ViewModel Factories (Usage)

```swift
// Prefer DI-provided factories over direct initializers
@StateObject private var viewModel = DIContainer.shared.makeDashboardViewModel()

// DashboardViewModel receives:
// - ExchangeRateServiceProtocol
// - BalanceServiceProtocol
// - TransactionServiceProtocol
// - GoalCalculationServiceProtocol
```

> Do not construct services inside ViewModels. Inject via `DIContainer` to improve testability and enable error recovery/fallbacks.

### Error Recovery Strategy

The `DIContainer` implements a robust error recovery pattern:

```swift
// Automatic fallback when service creation fails
var coinGeckoService: CoinGeckoService {
    do {
        let service = try createCoinGeckoService()
        return service
    } catch {
        AppLog.error("Failed to create service: \(error)")
        return createMockCoinGeckoService()  // Fallback service
    }
}
```

**Key Features:**
- Circular dependency detection
- Service validation after initialization
- Health check capabilities
- Automatic retry for failed services
- Fallback/mock services for critical functionality

### API Rate Limiting Architecture

```
Utilities/
├── RateLimiter.swift         ← Per-key rate limiting
├── StartupThrottler.swift    ← Prevents startup API spam
└── BalanceCacheManager.swift ← Persistent cache with fallback
```

**Rate Limiting Strategy:**
1. **StartupThrottler**: 3-second delay after app startup
2. **RateLimiter**: 5-second cooldown per unique request key
3. **BalanceCacheManager**: 30-minute cache for balances, 2-hour for transactions
4. **Fallback Cache**: Returns stale data when rate limited

---

## Data Flow Patterns

### MVVM Implementation Status

The data model now uses a join model, `AssetAllocation`, to link Assets and Goals.

```
Models/
├── Goal.swift                    ← SwiftData persistence
├── Asset.swift                   ← SwiftData persistence
├── AssetAllocation.swift         ← **Links Assets and Goals (NEW)**
├── Transaction.swift             ← SwiftData persistence
└── ...

ViewModels/
├── GoalEditViewModel.swift           ← Goal editing logic
├── GoalViewModel.swift               ← Individual goal management
├── AssetViewModel.swift              ← Individual asset management
└── ...

Views/
├── GoalsListView.swift              ← iOS goal list
├── AssetAllocationView.swift        ← **Manages asset allocations (NEW)**
└── ...
```

### Change Detection Pattern

```swift
// SwiftData change detection pattern used throughout
@Published var goal: Goal
private let originalSnapshot: GoalSnapshot

func triggerChangeDetection() {
    updateDirtyState()
    validateWithDelay()
}
```

---

## File Organization

### Current Structure

```
CryptoSavingsTracker/
├── Models/                   ← SwiftData models
├── ViewModels/              ← MVVM view models  
├── Views/
│   ├── Components/          ← Reusable UI components
│   ├── Goals/              ← Goal-specific views
│   ├── Planning/           ← Monthly planning
│   ├── Dashboard/          ← Portfolio overview
│   ├── Charts/             ← Data visualization
│   └── [Platform files]    ← iOS/macOS specific
├── Services/               ← Business logic layer
├── Utilities/              ← Helper classes, extensions
└── Repositories/           ← Data access layer
```

### Platform-Specific Files

| Platform | Key Files | Navigation Pattern |
|----------|-----------|-------------------|
| **iOS** | `iOSContentView.swift`, `GoalsListView.swift` | NavigationStack |
| **macOS** | `macOSContentView.swift`, `GoalsSidebarView.swift` | NavigationSplitView |
| **Shared** | `ContentView.swift`, Models, Services | Platform abstraction |

---

## Component Relationships

### Goal Display Dependency Graph

The data relationship between `Asset` and `Goal` is now mediated by the `AssetAllocation` model.

```
Goal Model ←── AssetAllocation ──→ Asset Model
    │                                    │
    └───────────┐                        │
                ↓                        ↓
    GoalCalculationService ←─────── ExchangeRateService
                │
                ↓
    UnifiedGoalRowView (Shared)
                ↓
    GoalsListView / GoalsSidebarView
                ↓
    ContentView (Platform Router)
```

### Critical Dependencies

1. **`GoalCalculationService`** → `AssetAllocation` (to determine how much of an asset contributes to a goal).
2. **All goal displays** → `GoalCalculationService` (for currency conversion and progress calculation).
3. **`AllocationService`** → `Asset`, `Goal`, `AssetAllocation` (to manage relationships).
4. **Platform views** → `PlatformCapabilities` (abstraction).

---

## Architectural Patterns

### Current Patterns in Use

✅ **MVVM Pattern**: ViewModels handle business logic  
✅ **Service Layer**: Separation of business logic from views  
✅ **SwiftData Integration**: Modern Core Data replacement  
✅ **Platform Abstraction**: PlatformCapabilities system  
✅ **Dependency Injection**: DIContainer with error recovery  
✅ **Repository Pattern**: GoalRepository for data access  
✅ **Coordinator Pattern**: AppCoordinator for navigation  
✅ **Error Recovery**: Automatic fallback services in DIContainer  

### Recent Improvements

✅ **View Unification**: Unified `GoalRowView` and `GoalSidebarRow` into a single `UnifiedGoalRowView` component.
✅ **Protocol-Based Services**: Refactored all services to use protocols for improved testability and mocking.
✅ **Component Registry**: Created a `COMPONENT_REGISTRY.md` file to document all reusable UI components.
✅ **UI and Design Enhancements**:
    - Improved visual hierarchy in `GoalDetailView`.
    - Enhanced interactivity of `FlexAdjustmentSlider`.
    - Simplified the design of `MonthlyPlanningWidget`.
    - Added animations and transitions to `DetailContainerView`.
✅ **Service Dependency Injection**: Removed singleton anti-pattern from BalanceService/TransactionService  
✅ **Rate Limiting**: Implemented RateLimiter for API calls  
✅ **Persistent Caching**: BalanceCacheManager with UserDefaults persistence  
✅ **Startup Throttling**: StartupThrottler prevents API spam  
✅ **Structured Logging**: AppLog with 16 categories replacing print statements

### Patterns Needing Improvement

❌ **Complete Platform Abstraction**: Still uses `#if os()` conditionals in some views.

### Recommended Patterns

🎯 **Protocol-Driven Abstraction**: Remove platform conditionals  
🎯 **Complete MVVM**: Move all business logic to ViewModels

---

## UI and Design Review

A UI and design review was conducted to identify areas for improvement. The following enhancements have been implemented:

*   **Improved Visual Hierarchy in `GoalDetailView`**: The font size of the section headers has been increased and more vertical spacing has been added between sections to improve readability.
*   **Enhanced `FlexAdjustmentSlider` Interactivity**: A live-updating label has been added to the slider to display the precise percentage as the user drags it.
*   **Simplified `MonthlyPlanningWidget` Design**: The design of the widget has been simplified to focus on the most critical information and to use a more spacious layout.
*   **Incorporated More Animations and Transitions**: A smooth cross-fade transition has been added when switching between the "Details" and "Dashboard" tabs in the `DetailContainerView`.

---

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

# Architecture Review

## 1. Executive Summary

The application architecture is modern, robust, and well-suited for a cross-platform SwiftUI application. It effectively utilizes key design patterns like **MVVM, Service Layer, Repository, and Coordinator**, which provides a clear and scalable separation of concerns. The adoption of modern Apple technologies, including **SwiftUI, SwiftData, and Combine**, is commendable.

The architecture's primary strengths are its modularity, clear data flow, and thoughtful approach to dependency management through the `DIContainer`. The recent refactoring to support the "Asset Splitting" feature has been integrated cleanly, demonstrating the architecture's flexibility.

The key recommendations focus on enforcing stricter adherence to the established Dependency Injection (DI) pattern within the ViewModels to further improve testability and maintainability.

---

## 2. Architectural Pattern Analysis

The application correctly implements several key architectural patterns:

*   **Model-View-ViewModel (MVVM):** There is a clear separation between Views (UI), ViewModels (UI logic and state), and Models (data). This is well-executed, with Views remaining lightweight and ViewModels handling user interactions and data preparation.

*   **Service Layer:** Business logic is correctly encapsulated in dedicated services (e.g., `MonthlyPlanningService`, `AllocationService`, `BalanceService`). This makes the logic reusable and independent of the UI.

*   **Repository Pattern:** The use of `GoalRepository` and `AssetRepository` abstracts the data source (SwiftData) from the services that consume the data. This is excellent practice and makes the application more resilient to future changes in the persistence layer.

*   **Dependency Injection (DI) & `DIContainer`:** The `DIContainer` acts as a centralized point for creating and accessing services. This is a major strength, as it decouples components and simplifies dependency management. However, as noted below, its use is not yet consistent across all ViewModels.

*   **Coordinator Pattern:** The `AppCoordinator` centralizes navigation logic, which is a scalable approach for managing complex navigation flows, especially in a multi-platform app.

---

## 3. Key Strengths

1.  **Clear Separation of Concerns:** The distinct layers (View, ViewModel, Service, Repository, Model) make the codebase easy to navigate, understand, and maintain.
2.  **Testability:** The use of protocols for services (`BalanceServiceProtocol`, etc.) and the DI container are excellent architectural choices that make the codebase highly testable. Mocking dependencies for unit tests is straightforward.
3.  **Scalability:** The current architecture can easily accommodate new features. The recent addition of the `AssetAllocation` model and `AllocationService` was integrated without requiring a fundamental redesign, proving the architecture's flexibility.
4.  **Modern Technology Stack:** The use of SwiftUI, SwiftData, and modern concurrency (`async/await`) makes the app performant and future-proof.
5.  **Platform Abstraction:** The `PlatformCapabilities` system provides a solid foundation for managing platform-specific UI and logic, reducing the need for `#if os()` directives in the view layer.

---

## 4. Architectural Refinements Implemented

Following the initial review, several key architectural refinements have been successfully implemented, strengthening the codebase and improving adherence to best practices.

### 4.1. Dependency Injection in ViewModels

*   **Action Taken:** ViewModels such as `DashboardViewModel` have been refactored to receive their service dependencies via an initializer, which is called from a factory method in the `DIContainer`.
*   **Outcome:** This change has decoupled ViewModels from concrete service implementations, significantly improving testability and ensuring all services are managed centrally.

### 4.2. Singleton Conversion for Services

*   **Action Taken:** The `GoalCalculationService`, which previously used static methods, has been refactored into an injectable, protocol-based service managed by the `DIContainer`.
*   **Outcome:** This allows `GoalCalculationService` to be easily mocked in unit tests, completing the transition to a fully testable service layer.

### 4.3. Code Consolidation

*   **Action Taken:** Several redundant views related to asset allocation (`AssetAllocationView`, `TestAllocationView`) and an older dashboard (`SimpleDashboardView`) were removed.
*   **Outcome:** The codebase is now leaner, with a single source of truth for the allocation UI (`AssetSharingView`), which reduces maintenance and improves clarity.

---

## 5. Code Duplication and Dead Code Analysis

An analysis of the codebase was performed to identify areas of code duplication and unused (dead) code.

### 5.1. Findings

*   **Code Duplication:** Multiple views (`AssetAllocationView`, `AssetSharingView`, `TestAllocationView`) were created to handle asset allocation management. Their functionality was largely identical, leading to duplicated UI code and logic.
*   **Dead Code:** The `SimpleDashboardView.swift` file was identified as being superseded by the more robust and feature-rich `DashboardView.swift` and its components.

### 5.2. Actions Taken

Based on the review, the following cleanup actions were performed:

*   **Consolidation:** The functionality of the various allocation views was consolidated into a single, reusable view: `AssetSharingView.swift`. The redundant files (`AssetAllocationView.swift`, `TestAllocationView.swift`) were deleted.
*   **Removal of Dead Code:** The unused `SimpleDashboardView.swift` file was deleted from the project.

### 5.3. Outcome

These changes have streamlined the codebase, reduced the maintenance overhead, and ensured a single source of truth for the asset allocation UI. The project is now leaner and easier to navigate.

---

## 6. Conclusion

The application is built on a solid and scalable architectural foundation. The existing patterns are well-chosen and have been implemented consistently following the latest refactoring.

By enforcing Dependency Injection and consolidating duplicated UI components, the architecture has been made even more robust and testable. These refinements ensure the application will be easy to maintain and extend as it continues to grow.