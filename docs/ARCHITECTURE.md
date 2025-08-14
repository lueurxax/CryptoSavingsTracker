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
├── GoalCalculationService.swift      ← **Currency-converted progress**
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
| `GoalCalculationService` | Currency-converted progress/totals | Singleton | **ALL goal display components** |
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
```

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

```
Models/
├── Item.swift (Goal model)           ← SwiftData persistence
├── Goal+Editing.swift                ← Change detection extensions
└── ...

ViewModels/
├── GoalEditViewModel.swift           ← Goal editing logic
├── GoalViewModel.swift               ← Individual goal management
├── MonthlyPlanningViewModel.swift    ← Portfolio planning
└── DashboardViewModel.swift          ← Portfolio overview

Views/
├── GoalsListView.swift              ← iOS goal list
├── Components/GoalsSidebarView.swift ← macOS goal sidebar
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

```
Goal Model
    ↓
GoalCalculationService ← ExchangeRateService
    ↓                      ↓
GoalRowView (iOS)     GoalSidebarRow (macOS)
    ↓                      ↓
GoalsListView         GoalsSidebarView
    ↓                      ↓
iOSContentView        macOSContentView
    ↓                      ↓
        ContentView (Platform Router)
```

### Critical Dependencies

1. **All goal displays** → `GoalCalculationService` (currency conversion)
2. **GoalCalculationService** → `ExchangeRateService` (live rates)
3. **Goal row components** → `Goal` model (data binding)
4. **Platform views** → `PlatformCapabilities` (abstraction)

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

*This document is maintained as part of the codebase. Update it whenever architectural changes are made.*