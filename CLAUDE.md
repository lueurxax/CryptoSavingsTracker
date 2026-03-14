# CryptoSavingsTracker — Claude Code Guide

## Project overview

CryptoSavingsTracker is a multi-platform SwiftUI application for tracking cryptocurrency savings goals. Users create goals denominated in crypto, link on-chain wallets, allocate assets, and follow a monthly planning/execution cycle to measure progress.

**Platforms:** iOS 18.0+ (production), macOS 14.0+ (production), Android (90% complete), visionOS (planned)
**Bundle ID:** `xax.CryptoSavingsTracker`
**Build:** iOS 25 (current)

---

## Repository layout

```
CryptoSavingsTracker/
├── ios/CryptoSavingsTracker/       # iOS/macOS app source
│   ├── Models/                     # SwiftData @Model entities
│   ├── ViewModels/                 # MVVM observable objects
│   ├── Views/                      # SwiftUI views & previews
│   │   ├── Components/             # Reusable UI components
│   │   ├── Dashboard/              # Portfolio overview
│   │   ├── Goals/                  # Goal management
│   │   ├── Planning/               # Monthly planning
│   │   ├── Charts/                 # Data visualisation
│   │   └── Settings/               # App settings
│   ├── Services/                   # Business logic layer
│   ├── Utilities/                  # Helpers, formatters, managers
│   ├── Repositories/               # Data access layer
│   └── Protocols/                  # Shared protocols
├── android/                        # Kotlin/Jetpack Compose app
├── docs/                           # Shared documentation
│   ├── ARCHITECTURE.md             # System design (primary reference)
│   ├── DEVELOPMENT.md              # Roadmap and refactoring plans
│   ├── MONTHLY_PLANNING.md         # Monthly planning feature
│   ├── CONTRIBUTION_FLOW.md        # Execution tracking architecture
│   ├── COMPONENT_REGISTRY.md       # Component catalogue
│   └── STYLE_GUIDE.md              # Documentation conventions
└── artifacts/visual-system/        # Design capture reports
```

---

## Technology stack

| Concern | Technology |
|---------|-----------|
| Language | Swift 5.0 |
| UI | SwiftUI |
| Persistence | SwiftData (SQLite backend) |
| Architecture | MVVM + Service layer + DI |
| Price data | CoinGecko API |
| Blockchain data | Tatum API v3/v4 |
| Secrets | Keychain (`KeychainManager`) |
| Config | `ios/Config.plist` (copy from `Config.example.plist`) |
| Cloud sync | CloudKit (configured, not yet active) |
| Notifications | APNs + local (`NotificationManager`) |
| Shortcuts | Siri Shortcuts (`ShortcutsProvider`) |

---

## Architecture

### MVVM layers

```
SwiftUI View
    └── ViewModel (@Observable / @StateObject)
            └── Service (business logic, async/await)
                    └── SwiftData Model / External API
```

### Key services

| Service | Responsibility |
|---------|---------------|
| `GoalCalculationService` | Progress %, status (Achieved/On Track/Behind) |
| `AllocationService` | Asset→Goal allocation, reallocation |
| `MonthlyPlanningService` | Required monthly contributions |
| `ExecutionTrackingService` | Monthly execution records, snapshots |
| `BudgetCalculatorService` | Budget health analysis |
| `FlexAdjustmentService` | Payment flexibility adjustments |
| `ExchangeRateService` | Fiat/crypto conversion |
| `CoinGeckoService` | Real-time price feeds |
| `BalanceService` | On-chain balance fetching |
| `TatumService` | Blockchain transaction history |
| `GoalLifecycleService` | Goal state transitions |
| `AutomationScheduler` | Notification scheduling |

### Platform abstraction

`PlatformCapabilities` (env value) drives navigation style:
- iOS compact → `NavigationStack` (`.stack`)
- macOS / iPad → `NavigationSplitView` (`.splitView`)

`ContentView` switches between `iOSContentView` and `macOSContentView` based on this value. Avoid `#if os()` guards elsewhere; prefer capability checks.

### Dependency injection

`DIContainer` constructs and owns all services. Pass via environment or initialiser; do not instantiate services directly inside views.

### Data model entities

`Goal`, `Asset`, `Transaction`, `AssetAllocation`, `AllocationHistory`, `MonthlyPlan`, `MonthlyExecutionRecord`, `CompletedExecution`, `CompletionEvent`, `ExecutionSnapshot`

---

## Critical component rules

> When modifying goal display logic, update **all** goal row components:

| Platform | Component | File |
|----------|-----------|------|
| iOS list | `GoalRowView` | `Views/GoalsListView.swift` |
| macOS sidebar | `GoalSidebarRow` | `Views/Components/GoalsSidebarView.swift` |
| Unified | `UnifiedGoalRowView` | `Views/Shared/` |

Always check `docs/COMPONENT_REGISTRY.md` before adding new components.

---

## Build and run

```bash
# 1. Copy config template (only needed once)
cp ios/Config.example.plist ios/Config.plist
# Fill in CoinGecko and Tatum API keys

# 2. Open in Xcode
open ios/CryptoSavingsTracker.xcodeproj

# 3. Select scheme: CryptoSavingsTracker
# Target: iPhone 16 simulator (iOS 18+) or physical device
```

No external package dependencies — the project uses only Apple frameworks.

---

## Testing

```bash
# Unit tests
xcodebuild test -scheme CryptoSavingsTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# UI tests (uses deterministic seed data)
xcodebuild test -scheme CryptoSavingsTrackerUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Visual capture snapshots live in `docs/screenshots/` and `artifacts/visual-system/`.

---

## Code conventions

- **No emoji in code or doc headers** — only in content via the allowed badge set (✅ ❌ 🔄 ⚠️ 📋 🗄️)
- **Async/await** for all network and persistence operations; no completion-handler callbacks in new code
- **Rate limiting** — use `RateLimiter` before external API calls; `BalanceCacheManager` for on-chain data
- **Error handling** — propagate typed errors through the service layer; views consume via `Result` or `@Published` error state
- **Accessibility** — use `AccessibilityManager` and `AccessibilityViewModifiers`; all interactive elements need labels
- **Logging** — use `Logger` (not `print`); include subsystem/category
- **Preview files** — each view has a paired `*Preview.swift` file; keep them compilable
- **Platform guards** — prefer `PlatformCapabilities` over `#if os()`; use `#if` only when unavoidable (e.g., AppKit APIs)

### Documentation style

Follow `docs/STYLE_GUIDE.md`:
- Dates: ISO 8601 (`YYYY-MM-DD`)
- Bullet hyphen `-`, never `*` or `+`
- Code blocks always include language tag
- Every doc has a metadata table (Status / Last Updated / Platform / Audience)

---

## AI agent configs

Custom agents are defined in `.claude/agents/`:

- **`architecture-critic`** — launch before significant structural changes; validates alignment with `docs/ARCHITECTURE.md`
- **`ux-reviewer`** — launch after UI changes; checks consistency, accessibility, and navigation patterns

---

## Key documentation

| Document | Purpose |
|----------|---------|
| `docs/ARCHITECTURE.md` | Authoritative architecture reference |
| `docs/MONTHLY_PLANNING.md` | Monthly planning and execution tracking |
| `docs/CONTRIBUTION_FLOW.md` | Contribution and allocation flow |
| `docs/COMPONENT_REGISTRY.md` | All UI components with ownership |
| `docs/DEVELOPMENT.md` | Roadmap, active work, refactoring notes |
| `docs/API_INTEGRATIONS.md` | CoinGecko and Tatum integration details |
| `docs/CLOUDKIT_MIGRATION_PLAN.md` | Future iCloud sync plan |
| `docs/ANDROID_DEVELOPMENT_PLAN.md` | Android port status |
