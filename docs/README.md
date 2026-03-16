# CryptoSavingsTracker Documentation

> A comprehensive multi-platform application for tracking cryptocurrency savings goals across iOS, macOS, visionOS, and Android.

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-03-04 |
| Platform | Shared |
| Audience | All |

---

## Quick Start

### For iOS/macOS Developers
1. Read [ARCHITECTURE.md](ARCHITECTURE.md) → Understand iOS system design
2. Review [COMPONENT_REGISTRY.md](COMPONENT_REGISTRY.md) → Familiarize with SwiftUI components
3. Check [DEVELOPMENT.md](DEVELOPMENT.md) → See active development plans
4. Run tests → See "Testing" section below

### For Android Developers
1. Read [ANDROID_DEVELOPMENT_PLAN.md](ANDROID_DEVELOPMENT_PLAN.md) → Android architecture, status, and iOS parity
2. Review the Android codebase structure in `android/app/src/main/java/`
3. Reference [API_INTEGRATIONS.md](API_INTEGRATIONS.md) → Same APIs used on both platforms

### For QA/Testers
1. Use [sample-data.md](sample-data.md) for test data generation
2. Follow [USER_GUIDES.md](USER_GUIDES.md) → Testing Guide
3. Reference [USER_GUIDES.md](USER_GUIDES.md) → Troubleshooting Guide

---

## Documentation Index

### Android Documentation

| Document | Purpose | Audience |
|----------|---------|----------|
| [ANDROID_DEVELOPMENT_PLAN.md](ANDROID_DEVELOPMENT_PLAN.md) | Android implementation status, iOS parity, architecture, testing | Android Developers |

### iOS/macOS Documentation

| Document | Purpose | Audience |
|----------|---------|----------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | iOS system architecture, design patterns, component organization | iOS Developers |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Development plans, feature roadmaps, refactoring strategies | iOS Developers |
| [MONTHLY_PLANNING.md](MONTHLY_PLANNING.md) | Monthly planning feature documentation and implementation | Developers, QA |
| [MONTHLY_PLANNING_BUDGET_HEALTH_WIDGET.md](MONTHLY_PLANNING_BUDGET_HEALTH_WIDGET.md) | Budget Health Widget specification: states, visual rules, accessibility, API reference | Developers |
| [GOAL_DASHBOARD.md](GOAL_DASHBOARD.md) | Goal dashboard architecture: scene model, next-action resolver, module contract | Developers |
| [NAVIGATION_PRESENTATION_CONSISTENCY.md](NAVIGATION_PRESENTATION_CONSISTENCY.md) | Navigation architecture, modal policy (MOD-01...MOD-05), CI enforcement | Developers |
| [VISUAL_SYSTEM_UNIFICATION.md](VISUAL_SYSTEM_UNIFICATION.md) | Visual token contract, surface/elevation policy, CI gates, release certification | Developers |
| [USER_GUIDES.md](USER_GUIDES.md) | Testing guide, migration guide, troubleshooting | Developers, QA |

### Shared Reference Documentation

| Document | Purpose | Audience |
|----------|---------|----------|
| [API_INTEGRATIONS.md](API_INTEGRATIONS.md) | External API integration details (CoinGecko, Tatum) - used by both platforms | Developers |
| [COMPONENT_REGISTRY.md](COMPONENT_REGISTRY.md) | iOS reusable UI component catalog | iOS Developers, Designers |
| [BUDGET_CALCULATOR.md](BUDGET_CALCULATOR.md) | Budget Calculator feature documentation for fixed monthly savings | Developers |
| [CONTRIBUTION_PROCESS.md](CONTRIBUTION_PROCESS.md) | Contribution process UX features: "Add to Close Month" action, current goal first sorting, execution currency selector | Developers |
| [CONTRIBUTION_FLOW.md](CONTRIBUTION_FLOW.md) | Timestamp-based execution tracking architecture and contribution derivation | Developers |
| [CONTRIBUTION_TRACKING_REDESIGN.md](CONTRIBUTION_TRACKING_REDESIGN.md) | AllocationHistory, contribution tracking architecture decisions | Developers |
| [CLOUDKIT_MIGRATION_PLAN.md](CLOUDKIT_MIGRATION_PLAN.md) | CloudKit/iCloud sync migration requirements and plan | Developers |
| [CLOUDKIT_PHASE1_WORKTREE_EXECUTION_PLAN.md](CLOUDKIT_PHASE1_WORKTREE_EXECUTION_PLAN.md) | Worktree split, merge waves, and ownership rules for CloudKit Phase 0/1/1.5 | Developers |
| [STYLE_GUIDE.md](STYLE_GUIDE.md) | Documentation style standards and conventions | All |
| [sample-data.md](sample-data.md) | Sample data for testing and development | Developers, QA |

### Copy and Content

| Document | Purpose | Audience |
|----------|---------|----------|
| [copy/FINANCIAL_COPY_DICTIONARY.md](copy/FINANCIAL_COPY_DICTIONARY.md) | Source of truth for planning/form user-facing language and copy keys | Developers, Content |

### Historical Documentation

| Directory | Contents |
|-----------|----------|
| [proposals/](proposals/) | Active proposal documents (drafts and ADRs) |
| [archive/2026-01/](archive/2026-01/) | Archived proposals from January 2026 (now implemented) |
| [archive/2025-11/](archive/2025-11/) | Archived proposals, fixes, and plans from August-November 2025 |

## Architecture Quick Reference

### Key Technologies

#### iOS/macOS
- **UI Framework**: SwiftUI
- **Data Persistence**: SwiftData
- **Platforms**: iOS, macOS, visionOS
- **Architecture Pattern**: MVVM with Service Layer
- **Language**: Swift 5.9+
- **Minimum Deployment**: iOS 17.0, macOS 15.0

#### Android
- **UI Framework**: Jetpack Compose
- **Data Persistence**: Room
- **Dependency Injection**: Hilt
- **Architecture Pattern**: Clean Architecture (Data/Domain/Presentation layers)
- **Language**: Kotlin
- **Minimum SDK**: 34 (Android 14)

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Presentation Layer                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  iOS Views   │  │ macOS Views  │  │ Shared Views │          │
│  │  (iPhone)    │  │ (Split View) │  │ (Components) │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
└─────────┼──────────────────┼──────────────────┼─────────────────┘
          │                  │                  │
          └──────────────────┴──────────────────┘
                             │
┌────────────────────────────┼─────────────────────────────────────┐
│                      ViewModel Layer                              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  GoalViewModel • DashboardViewModel • PlanningViewModel  │   │
│  │  @Published properties • Combine integration             │   │
│  └──────────────────────────┬───────────────────────────────┘   │
└─────────────────────────────┼─────────────────────────────────────┘
                              │
┌─────────────────────────────┼─────────────────────────────────────┐
│                       Service Layer                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │ Calculation  │  │   External   │  │   Planning   │           │
│  │  Services    │  │     APIs     │  │   Services   │           │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘           │
└─────────┼──────────────────┼──────────────────┼───────────────────┘
          │                  │                  │
          └──────────────────┴──────────────────┘
                             │
┌────────────────────────────┼─────────────────────────────────────┐
│                        Data Layer                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  SwiftData Models: Goal • Asset • Transaction • Plan    │   │
│  │  Persistent storage with relationships                   │   │
│  └──────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────┘
```

### Project Structure
```
CryptoSavingsTracker/
├── Models/                    # SwiftData @Model classes
│   ├── Goal.swift            # Core goal entity
│   ├── Asset.swift           # Cryptocurrency assets
│   ├── Transaction.swift     # Transaction records
│   ├── MonthlyPlan.swift     # Planning entities
│   └── AssetAllocation.swift # Shared asset allocations
│
├── ViewModels/               # MVVM coordinators
│   ├── GoalViewModel.swift
│   ├── DashboardViewModel.swift
│   └── MonthlyPlanningViewModel.swift
│
├── Views/                    # SwiftUI views
│   ├── Components/          # Reusable UI components
│   │   ├── HeroProgressView.swift
│   │   ├── FlexAdjustmentSlider.swift
│   │   └── MonthlyPlanningWidget.swift
│   ├── Planning/            # Monthly planning feature
│   │   ├── PlanningView.swift
│   │   └── MonthlyExecutionView.swift
│   ├── Dashboard/           # Portfolio dashboard
│   │   ├── DashboardView.swift
│   │   └── WhatIfView.swift
│   ├── Charts/              # Data visualization
│   │   ├── EnhancedLineChartView.swift
│   │   └── ForecastChartView.swift
│   └── Goals/               # Goal management
│       └── GoalDetailView.swift
│
├── Services/                # Business logic
│   ├── GoalCalculationService.swift
│   ├── MonthlyPlanService.swift
│   ├── ExchangeRateService.swift
│   ├── BalanceService.swift
│   └── TransactionService.swift
│
├── Utilities/               # Helpers & extensions
│   ├── DIContainer.swift   # Dependency injection
│   ├── PerformanceOptimizer.swift
│   ├── AccessibilityManager.swift
│   └── PlatformCapabilities.swift
│
└── Repositories/            # Data access layer
    └── GoalRepository.swift
```

Android Project Structure
```
android/
├── app/src/main/java/com/xax/CryptoSavingsTracker/
│   ├── presentation/          # Compose screens + view models
│   ├── domain/                # Models + use cases + repositories
│   ├── data/                  # Room + API + repository impls
│   ├── di/                    # Hilt modules
│   └── work/                  # WorkManager workers
│
└── app/src/main/res/           # Resources (themes, strings, drawables)
```

## Key Features

### Core Features
- **🎯 Goal Management**: Create and track multiple cryptocurrency savings goals
- **💰 Asset Tracking**: Monitor crypto holdings across multiple blockchains
- **📊 Portfolio Dashboard**: Real-time portfolio value and performance metrics
- **📈 Interactive Charts**: Balance history, asset composition, and forecast visualizations
- **🔄 Transaction History**: Manual and on-chain transaction tracking
- **📅 Monthly Planning**: Zero-input planning with flexible budget adjustments
- **🔗 Asset Allocation**: Share assets across multiple goals

### Advanced Features
- **💱 Multi-Currency Support**: 100+ fiat and cryptocurrency pairs
- **🌐 Multi-Platform**: Native iOS, macOS, and visionOS support
- **⚡ Real-Time Prices**: Live cryptocurrency price tracking (CoinGecko API)
- **🔍 On-Chain Data**: Blockchain balance and transaction fetching (Tatum API)
- **📱 Platform-Adaptive UI**: Optimized layouts for each platform
- **♿ Accessibility**: WCAG 2.1 AA compliant with VoiceOver support
- **🔔 Notifications**: Smart reminders for monthly contributions

## Getting Started

### Android Prerequisites
- Android Studio (latest stable)
- Android SDK + emulator/device

### Android Initial Setup
1. Open the `android/` directory in Android Studio
2. Sync Gradle
3. Run the `app` configuration on a device or emulator

### iOS/macOS Prerequisites
- Xcode 15.0 or later
- macOS 15.0 or later (for development)
- CoinGecko API key (for exchange rates)
- Tatum API key (optional, for on-chain data)

### iOS/macOS Initial Setup
1. Clone the repository
2. Open `CryptoSavingsTracker.xcodeproj`
3. Configure API keys in `Config.plist`
4. Build and run

### For New Developers

1. **Start with**: [ARCHITECTURE.md](ARCHITECTURE.md) - Understand the system design
2. **Then read**: [DEVELOPMENT.md](DEVELOPMENT.md) - Learn about development plans
3. **Review**: [COMPONENT_REGISTRY.md](COMPONENT_REGISTRY.md) - Familiarize yourself with UI components
4. **Reference**: [API_INTEGRATIONS.md](API_INTEGRATIONS.md) - Understand external integrations

### For Feature Development

1. **Architecture Review**: Check ARCHITECTURE.md for design patterns
2. **Component Reuse**: Browse COMPONENT_REGISTRY.md before creating new UI
3. **Testing**: Follow guidelines in USER_GUIDES.md
4. **API Integration**: Reference API_INTEGRATIONS.md for external services

### For Testing

1. **Test Strategy**: See "Testing Guide" in USER_GUIDES.md
2. **Sample Data**: Use sample-data.md for test data generation
3. **Troubleshooting**: Reference "Troubleshooting Guide" in USER_GUIDES.md

## Feature Documentation

### Monthly Planning Feature

The Monthly Planning feature is a comprehensive zero-input planning system. See [MONTHLY_PLANNING.md](MONTHLY_PLANNING.md) for:

- **Architecture Overview**: System design and data flow
- **Core Components**: Services, ViewModels, UI components
- **Implementation Guide**: Step-by-step integration
- **API Reference**: Complete API documentation
- **Testing Strategy**: Unit, integration, UI, and accessibility tests
- **Migration Guide**: Upgrading from previous versions

**Quick Start**: See section 1 of MONTHLY_PLANNING.md

### Asset Splitting & Allocations

The Asset Splitting feature allows users to allocate a single asset across multiple goals. See DEVELOPMENT.md for:

- **Problem Statement**: Why asset splitting is needed
- **Technical Implementation**: Data model changes
- **UI/UX Vision**: User interface design
- **Migration Plan**: Data migration strategy

**Quick Start**: See "Feature: Asset Splitting" in DEVELOPMENT.md

### Architectural Refactoring

Platform abstraction and component unification. See DEVELOPMENT.md for:

- **Phase 1**: Unified goal components ✅ COMPLETED
- **Phase 2**: Platform abstraction ✅ COMPLETED
- **Phase 3**: File organization ✅ COMPLETED
- **Phase 4**: Testing & validation (in progress)

**Status**: See "Architectural Refactoring Plan" in DEVELOPMENT.md

## Testing

### Test Coverage

| Test Type | Location | Coverage |
|-----------|----------|----------|
| Unit Tests | `CryptoSavingsTrackerTests/` | >90% target |
| UI Tests | `CryptoSavingsTrackerUITests/` | >70% target |
| Accessibility Tests | `CryptoSavingsTrackerTests/AccessibilityTests.swift` | 100% WCAG AA |

### Running Tests

```bash
# All tests
xcodebuild test -scheme CryptoSavingsTracker -destination "platform=macOS"

# Unit tests only
xcodebuild test -scheme CryptoSavingsTracker -destination "platform=macOS" \
  -only-testing:CryptoSavingsTrackerTests

# UI tests only
xcodebuild test -scheme CryptoSavingsTracker -destination "platform=macOS" \
  -only-testing:CryptoSavingsTrackerUITests
```

**Detailed Guide**: See "Testing Guide" in USER_GUIDES.md

## Configuration

### API Keys

Configure external API keys in `Config.plist`:

- **CoinGecko API**: Currency exchange rates
- **Tatum API**: Blockchain data

**Details**: See API_INTEGRATIONS.md

### Build Targets

- **Debug**: Full logging, debug symbols
- **Release**: Optimized, minimal logging
- **TestFlight**: Beta distribution

## Contributing

### Before Starting

1. Review ARCHITECTURE.md for design patterns
2. Check COMPONENT_REGISTRY.md for existing components
3. Follow testing guidelines in USER_GUIDES.md

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftLint for style enforcement
- Write comprehensive tests (>90% coverage)
- Document public APIs with Swift DocC

### Pull Request Checklist

- [ ] Code follows architectural patterns
- [ ] Unit tests added/updated (>90% coverage)
- [ ] UI tests for user flows
- [ ] Accessibility tests for WCAG compliance
- [ ] Documentation updated
- [ ] No regression in existing tests

## Archive

Historical documentation is preserved in `archive/` directories:

- **archive/2026-03/**: Implemented proposals from March 2026
  - Budget Health Widget Proposal (now MONTHLY_PLANNING_BUDGET_HEALTH_WIDGET.md)
  - Navigation Presentation Consistency Proposal (now NAVIGATION_PRESENTATION_CONSISTENCY.md)
  - Visual System Unification Proposal (now VISUAL_SYSTEM_UNIFICATION.md)

- **archive/2026-01/**: Implemented proposals from January 2026
  - Fixed Budget Planning Proposal (now BUDGET_CALCULATOR.md)
  - Contribution Process Proposal (now CONTRIBUTION_PROCESS.md)
  - Execution Tracking Live Sync Proposal (superseded by CONTRIBUTION_FLOW.md)

- **archive/2025-11/**: Proposals and fixes from August-November 2025
  - Dashboard improvement plans
  - Execution tracking implementations
  - Migration fixes
  - UX reviews
  - Technical fixes

These are kept for historical reference but are superseded by current documentation.

## External Resources

- [Swift Documentation](https://swift.org/documentation/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [WCAG 2.1 AA Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)

## Getting Help

### Quick Solutions

| Issue | Solution |
|-------|----------|
| Build errors | See USER_GUIDES.md → Troubleshooting Guide |
| Console warnings | See USER_GUIDES.md → Console warnings section |
| Test failures | See USER_GUIDES.md → Testing Guide |
| API integration | See API_INTEGRATIONS.md |
| Migration issues | See USER_GUIDES.md → Migration Guide |

### Common Issues

<details>
<summary><strong>Build Error: "Cannot find MonthlyPlan in scope"</strong></summary>

**Solution**: Add `MonthlyPlan.swift` to your project and update ModelContainer:
```swift
let container = try ModelContainer(for:
    Goal.self,
    Asset.self,
    Transaction.self,
    MonthlyPlan.self  // Add this
)
```
</details>

<details>
<summary><strong>SwiftData Migration Failure</strong></summary>

**Solution**: Check that all new optional fields have default values or are properly marked as optional with `?`. See USER_GUIDES.md → Migration Guide for details.
</details>

<details>
<summary><strong>Exchange Rates Not Updating</strong></summary>

**Solution**:
1. Verify CoinGecko API key in `Config.plist`
2. Check network connectivity
3. Monitor API rate limits (10 requests/minute)
4. See API_INTEGRATIONS.md for details
</details>

<details>
<summary><strong>Type-Checking Timeout Errors</strong></summary>

**Solution**: Break complex SwiftUI views into smaller computed properties. See GoalDetailView.swift:288-439 for an example.
</details>

### For Documentation Issues

1. Check this README for navigation
2. Search relevant documentation file
3. Check archive for historical context

### For Technical Issues

1. Review "Troubleshooting Guide" in USER_GUIDES.md
2. Check console warnings reference in USER_GUIDES.md
3. Search GitHub issues

### For Testing Issues

1. See "Testing Guide" in USER_GUIDES.md
2. Check sample-data.md for test data
3. Review test architecture in USER_GUIDES.md

## Documentation Status

| Document | Last Updated | Status | Coverage |
|----------|--------------|--------|----------|
| README.md | 2026-03-16 | ✅ Current | Complete |
| STYLE_GUIDE.md | 2026-01-04 | ✅ Current | Complete |
| ANDROID_DEVELOPMENT_PLAN.md | 2026-01-04 | ✅ Current | Complete |
| ARCHITECTURE.md | 2026-01-04 | ✅ Current | Complete |
| BUDGET_CALCULATOR.md | 2026-03-16 | ✅ Current | Complete |
| CONTRIBUTION_PROCESS.md | 2026-01-04 | ✅ Current | Complete |
| CONTRIBUTION_FLOW.md | 2026-01-04 | ✅ Current | Complete |
| CONTRIBUTION_TRACKING_REDESIGN.md | 2026-01-04 | ✅ Current | Complete |
| CLOUDKIT_MIGRATION_PLAN.md | 2026-01-04 | 📋 Planning | Complete |
| DEVELOPMENT.md | 2026-01-04 | ✅ Current | Complete |
| MONTHLY_PLANNING.md | 2026-01-04 | ✅ Current | Complete |
| USER_GUIDES.md | 2026-01-04 | ✅ Current | Complete |
| API_INTEGRATIONS.md | 2026-01-04 | ✅ Current | Complete |
| NAVIGATION_PRESENTATION_CONSISTENCY.md | 2026-03-04 | ✅ Current | Complete |
| VISUAL_SYSTEM_UNIFICATION.md | 2026-03-04 | ✅ Current | Complete |
| GOAL_DASHBOARD.md | 2026-03-16 | ✅ Current | Complete |
| COMPONENT_REGISTRY.md | 2026-03-16 | ✅ Current | iOS Only |
| sample-data.md | 2026-01-04 | ✅ Current | Complete |

### Recent Updates
- **2026-03-16**: Converted 4 implemented proposals to documentation (Goal Dashboard, Budget Flow Hardening, Commit Dock Scroll Collapse, UI/UX Incremental Improvements); removed 16 proposal/review files
- **2026-03-04**: Converted implemented Navigation and Visual System proposals to proper documentation
- **2026-03-02**: Added MONTHLY_PLANNING_BUDGET_HEALTH_WIDGET.md from implemented proposal
- **2026-01-04**: Created STYLE_GUIDE.md and standardized all documentation
- **2026-01-04**: Documentation cleanup - archived execution-tracking-live-sync proposal
- **2026-01-04**: Added CONTRIBUTION_FLOW.md, CONTRIBUTION_TRACKING_REDESIGN.md to index
- **2025-11-23**: Enhanced README with architecture diagrams, quick start guide
- **2025-11-23**: Archived 12 outdated proposal documents to archive/2025-11/

## Version Information

- **App Version**: 2.1+
- **Documentation Version**: 2.0
- **Swift Version**: 5.9+
- **Minimum iOS**: 17.0
- **Minimum macOS**: 15.0

---

*Last updated: 2026-03-16*
