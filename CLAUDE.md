# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CryptoSavingsTracker is a cross-platform SwiftUI application that helps users track cryptocurrency savings goals. Each goal can contain multiple cryptocurrency assets, making it a portfolio-based savings tracker. The app supports iOS, macOS, visionOS, and uses SwiftData for local persistence with local notifications for deadline reminders.

## Architecture

The application follows a modern SwiftUI + SwiftData architecture with portfolio-based goal tracking:

### Data Models (Item.swift)
- **Goal**: Top-level savings goal with single target currency and amount
  - `id: UUID` (unique identifier)
  - `name: String` (e.g., "Vacation 2025")
  - `currency: String` (goal's benchmark currency, e.g., "USD", "BTC")
  - `targetAmount: Double` (target amount in the goal's currency)
  - `deadline: Date` (target completion date)
  - `assets: [Asset]` (relationship to multiple cryptocurrency assets)
  - Computed properties: `daysRemaining`
  - Async methods: `getCurrentTotal()` (sum of all assets converted to goal currency), `getProgress()` (currentTotal/targetAmount)

- **Asset**: Individual cryptocurrency within a goal (no individual targets)
  - `id: UUID` (unique identifier)
  - `currency: String` (e.g., "BTC", "ETH")
  - `transactions: [Transaction]` (relationship to deposits)
  - `goal: Goal` (back-reference to parent goal)
  - Computed properties: `currentAmount` (sum of transactions in asset's currency)

- **Transaction**: Individual deposits/contributions to an asset
  - `id: UUID` (unique identifier)
  - `amount: Double` (deposit amount in the asset's currency)
  - `date: Date` (transaction date)
  - `asset: Asset` (back-reference to parent asset)

### Views and Navigation
- **ContentView.swift**: Entry point that displays GoalsListView
- **GoalsListView.swift**: Main list showing goals with "X / Y [currency]" progress format and smooth animations
- **GoalDetailView.swift**: Detailed view with Query-based asset binding, expandable transactions, and proper refresh handling
- **AddGoalView.swift**: Pure SwiftUI form avoiding AppKit controls for macOS 15.5 compatibility
- **AddAssetView.swift**: Form to add cryptocurrency assets to existing goals (no targetAmount field)
- **AddTransactionView.swift**: Form to add deposit transactions to assets
- **SearchableCurrencyPicker.swift**: Efficient searchable currency selector with pagination and full CoinGecko integration
- **CoinGeckoService.swift**: Real-time cryptocurrency data service with caching and supported currencies API

### SwiftData Integration
- **Query-based data binding**: Uses `@Query` with predicates for real-time updates
- **Explicit model saving**: Calls `modelContext.save()` after insertions to ensure immediate refresh
- **Relationship filtering**: Filters related entities using computed properties with Query results
- **Animation integration**: Smooth animations triggered by data count changes
- **Data persistence**: Removed automatic store deletion to maintain user data across app restarts

### Exchange Rate Conversion (ExchangeRateService.swift)
- Singleton service for currency conversion with persistent caching
- Real-time integration with CoinGecko API for accurate exchange rates
- `fetchRate(from: String, to: String) async throws -> Double` function
- 5-minute cache expiration with UserDefaults persistence across app restarts
- Used in Goal's `currentTotal` computation to convert asset values to goal currency
- Supports both cryptocurrency symbols and fiat currencies via CoinGecko price API

### Notifications (NotificationManager.swift)
- Local notification system for deadline management
- Schedules notifications on goal deadline and 3 days before
- Uses goal UUID for unique notification identifiers
- One-time permission request at app initialization to prevent sheet freezing
- Separated permission requests from notification scheduling for macOS 15.5 compatibility

### Data Relationships
```
Goal (1) → Assets (many) → Transactions (many)
Goal ←← Asset ←← Transaction (inverse relationships)
```
- **Goal-level targeting**: Only Goals have targetAmount and currency; Assets contribute to Goal's total
- **Currency conversion**: Asset values automatically converted to Goal currency for progress calculation
- **Cascade delete**: Deleting a Goal removes all Assets and Transactions
- **Cascade delete**: Deleting an Asset removes all its Transactions
- **Async computations**: Goal progress requires async exchange rate fetching

## Development Commands

### Building and Running
```bash
# Open in Xcode
open CryptoSavingsTracker.xcodeproj

# Build for macOS
xcodebuild -project CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -configuration Debug -destination "platform=macOS"

# Build for iOS Simulator
xcodebuild -project CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -configuration Debug -destination "platform=iOS Simulator,id=<device-id>"
```

### Testing
```bash
# Run unit tests (macOS)
xcodebuild test -project CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination "platform=macOS"

# Run UI tests (iOS)
xcodebuild test -project CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination "platform=iOS Simulator,id=<device-id>"
```

## Platform-Specific Considerations

The codebase uses conditional compilation for platform-specific UI elements:

- **iOS-only modifiers**: `.navigationBarTitleDisplayMode()`, `.keyboardType()`, `.textInputAutocapitalization()`
- **iOS toolbar placements**: `.navigationBarLeading`, `.navigationBarTrailing`
- **macOS toolbar placements**: `.cancellationAction`, `.confirmationAction`, `.primaryAction`
- **Sheet presentation**: 
  - **iOS**: Uses `.sheet()` for modal presentation
  - **macOS**: Uses `.sheet()` but avoids AppKit-backed controls (Form, default DatePicker)
- **Form sizing**: All forms include `minWidth` and `minHeight` constraints for macOS compatibility

### macOS 15.5 / Xcode 26β4 Compatibility
- **Avoid AppKit controls**: Use pure SwiftUI (`VStack`, `ScrollView`) instead of `Form` on macOS
- **DatePicker**: Use `.graphical` style instead of default to prevent RemoteViewService crashes
- **Currency selection**: Custom searchable picker instead of native `Picker` to avoid freezing
- **Persistent buttons**: Use bottom `HStack` instead of `.toolbar` for reliable button placement

### Presentation Modifiers
- **GoalsListView**: `.sheet()` with `minWidth: 500, minHeight: 450` for AddGoalView
- **GoalDetailView**: `.sheet()` with appropriate sizing for AddAssetView
- **Currency selection**: Full-screen searchable interface with efficient pagination

When adding new UI elements, always consider macOS 15.5 compatibility and avoid AppKit-backed SwiftUI controls.

## Schema Management

The app uses SwiftData's built-in schema management:

- **Automatic migrations**: SwiftData handles schema changes automatically
- **Data persistence**: User data persists across app restarts and updates
- **Store location**: Application Support directory (`~/Library/Containers/xax.CryptoSavingsTracker/Data/Library/Application Support/`)
- **Store files**: `default.store`, `default.store-shm`, `default.store-wal`

### Manual Cleanup (if needed)
If the app fails to launch due to severe schema conflicts, manually delete the store files:
```bash
rm -f ~/Library/Containers/xax.CryptoSavingsTracker/Data/Library/Application\ Support/default.store*
```

The app no longer automatically deletes user data on launch, ensuring proper data persistence.

## Key Configuration Details

- **Bundle ID**: `xax.CryptoSavingsTracker`
- **Deployment Targets**: iOS 26.0, macOS 15.5, visionOS 26.0
- **Swift Version**: 5.0
- **SwiftData Models**: Goal, Asset, Transaction with proper relationships and versioning
- **Local Notifications**: UserNotifications framework for deadline reminders
- **Multi-platform**: Supports iPhone, iPad, Mac, and Vision Pro
- **App Sandbox**: Enabled for security
- **Hardened Runtime**: Enabled for macOS security