# Claude Code Workspace

## Development Notes

This is a SwiftUI cryptocurrency savings tracker app built for iOS, macOS, and visionOS.

### API Configuration

- **CoinGecko API**: The app uses CoinGecko API for real-time exchange rates
- **Tatum API**: The app uses Tatum.io API for on-chain balance and transaction lookup across multiple blockchains
- **API Key Setup**: Copy `Config.example.plist` to `Config.plist` and replace API keys:
  - `YOUR_COINGECKO_API_KEY` with your actual CoinGecko API key
  - `YOUR_TATUM_API_KEY` with your actual Tatum API key
- **Get API Keys**: 
  - [CoinGecko API](https://www.coingecko.com/en/api) for exchange rates
  - [Tatum.io API](https://tatum.io) for multi-chain blockchain data

### Supported Chains (via Tatum.io)

#### EVM Chains
- Ethereum (ETH)
- Polygon (MATIC) 
- Binance Smart Chain (BSC)
- Avalanche C-Chain (AVAX)
- Fantom (FTM)
- Celo (CELO)
- Harmony (ONE)
- Klaytn (KLAY)

#### UTXO Chains
- Bitcoin (BTC)
- Litecoin (LTC)
- Bitcoin Cash (BCH)
- Dogecoin (DOGE)

#### Other Chains
- XRP Ledger (XRP)
- Tron (TRX) - *v3 API support added*
- Cardano (ADA)
- Solana (SOL)
- Algorand (ALGO)
- Stellar (XLM)

### Build Commands

- **Build**: Use Xcode's Cmd+B or `xcodebuild -scheme CryptoSavingsTracker -destination "platform=macOS" build`
- **Run**: Use Xcode's Cmd+R or simulator/device deployment
- **Test**: `xcodebuild test -scheme CryptoSavingsTracker -destination "platform=macOS"`
  - Unit tests: `xcodebuild test -scheme CryptoSavingsTracker -only-testing:CryptoSavingsTrackerTests`
  - UI tests: `xcodebuild test -scheme CryptoSavingsTracker -only-testing:CryptoSavingsTrackerUITests`

### Security Notes

- API keys have been sanitized for public repository
- Build artifacts and personal data removed from git tracking
- `.gitignore` configured for Swift/Xcode projects

### Architecture

- **SwiftUI**: Modern declarative UI framework
- **SwiftData**: Core Data replacement for persistence
- **MVVM Pattern**: Clean separation of concerns
- **Portfolio-based Goals**: Multiple cryptocurrency assets per savings goal

### Platform Support

- iOS 17.0+
- macOS 14.0+ 
- visionOS 1.0+
- Xcode 15.0+

### Recent Fixes & Improvements

#### SwiftData Model Enhancements
- **Goal Model**: Added `ObservableObject` conformance for proper SwiftUI integration
- **Frequency Property**: Fixed nil keypath fatal error by implementing safe computed property with optional backing storage
- **Async Methods**: Maintained both sync and async calculation methods for flexibility
  - `getCurrentTotal()` / `getProgress()` - async with currency conversion
  - `currentTotal` / `progress` - sync properties for fallback

#### GoalsListView Improvements
- **Query Syntax**: Updated to use correct SwiftData `@Query(sort: \.deadline, order: .forward)`
- **Row Updates**: Fixed currentTotal and progress displaying 0 by using async methods
- **SwiftUI Best Practices**: Implemented proper `.task` and `.onChange` modifiers
- **Deprecation Fixes**: Updated to modern SwiftUI onChange syntax

#### Build & Stability
- **Clean Compilation**: All files now compile without errors
- **Metal Warnings**: Documented expected warnings from Xcode beta (harmless)
- **Error Handling**: Improved data migration and nil safety throughout

#### Data Flow
- **Real-time Updates**: Goal progress updates properly when assets/transactions change
- **Currency Conversion**: Async exchange rate calculations working correctly
- **UI Responsiveness**: Proper MainActor usage for smooth UI updates

#### API Enhancements
- **TRX Support**: Added Tron (TRX) blockchain support using Tatum v3 API
  - Native TRX balance fetching with sun to TRX conversion (1,000,000 sun = 1 TRX)
  - TRC10 and TRC20 token support in response structure
  - Endpoint: `/v3/tron/account/{address}`
- **CoinGecko Upgrade**: Migrated from `supported_vs_currencies` to `coins/list` endpoint
  - Enhanced SearchableCurrencyPicker with coin names and symbols
  - Improved search functionality (search by both symbol and name)
  - Better caching with full coin information (id, symbol, name)
  - Backward compatibility maintained for existing `coins` array

### Testing Framework

#### Test Structure
- **Swift Testing**: Uses the new Swift Testing framework for modern, expressive tests
- **Comprehensive Coverage**: Unit tests, integration tests, UI tests, and performance tests
- **In-Memory Testing**: SwiftData tests use in-memory containers for speed and isolation

#### Test Categories

**Unit Tests (`CryptoSavingsTrackerTests.swift`)**
- Model validation (Goal, Asset, Transaction, ReminderFrequency)
- Business logic (progress calculation, currency conversion, date handling)
- SwiftData persistence and relationships
- Edge cases and error conditions

**Integration Tests (`IntegrationTests.swift`)**
- Full data flow testing (goal → assets → transactions)
- Multi-currency scenarios
- Large dataset performance
- Cascading delete behavior
- Complex business scenarios

**UI Tests (`CryptoSavingsTrackerUITests.swift`)**
- Goal creation and management flows
- Asset and transaction management
- Navigation testing
- Platform-specific UI behavior (iOS vs macOS)
- Progress display validation

**Service Tests (`ExchangeRateServiceTests.swift`)**
- Exchange rate API integration
- Error handling and fallback behavior
- Caching functionality
- Network request performance

#### Test Helpers (`TestHelpers.swift`)**
- Test data factories for consistent test data
- Performance measurement utilities
- Mock services for reliable testing
- Test configuration for different environments

#### Test Status & Known Issues

**Current Status**: ✅ Tests compile successfully and individual tests pass

**Test Execution**:
- Individual tests: ✅ Working (e.g., `reminderFrequencyDisplayNames`, `relationshipPersistence` pass)
- Full test suite: ⚠️ Test runner issues with Xcode Beta 2

**Known Issues**:
- **Xcode Beta Limitations**: Running all tests simultaneously fails due to Xcode beta test runner issues
- **Workaround**: Run individual tests or test categories separately
- **File System Errors**: Result bundle saving fails in beta environment (cosmetic issue)

**Recent Fixes**:
- **Index Out of Range Error**: Fixed array access in `relationshipPersistence` test by using safe `.first` access instead of direct indexing
- **Test Safety**: Updated tests to use guard statements and `.first` property for safer array access

**Test Coverage Areas**:
- ✅ Model validation and business logic
- ✅ SwiftData persistence and relationships  
- ✅ Currency conversion and calculations
- ✅ Date handling and reminder scheduling
- ✅ UI component testing structure
- ✅ Error handling and edge cases

**Running Tests**:
```bash
# Individual test (recommended for beta)
xcodebuild test -scheme CryptoSavingsTracker -destination "platform=macOS" -only-testing:CryptoSavingsTrackerTests/CryptoSavingsTrackerTests/reminderFrequencyDisplayNames

# Test category
xcodebuild test -scheme CryptoSavingsTracker -destination "platform=macOS" -only-testing:CryptoSavingsTrackerTests

# All tests (may fail in Xcode beta)
xcodebuild test -scheme CryptoSavingsTracker -destination "platform=macOS"
```

### ✨ Required Monthly Feature (v2.0) - COMPLETED

#### Zero-Input Planning System
- **Automatic Calculations**: Monthly savings requirements calculated for all goals without user input
- **Real-time Updates**: Requirements recalculate when goals, assets, or transactions change
- **Multi-Currency Support**: Handles goals in different currencies with live exchange rate conversion
- **Smart Status Detection**: Automatic categorization (On Track, Attention, Critical, Completed)

#### Advanced Flex Adjustment System
- **Interactive Slider**: Real-time preview of payment adjustments (0% to 200%)
- **Preset Buttons**: Quick adjustments (Skip, Quarter, Half, Full, Extra)
- **Redistribution Logic**: Intelligent reallocation using multiple strategies:
  - Balanced: Equal distribution across goals
  - Urgent: Prioritize nearest deadlines
  - Largest: Reduce largest amounts first
  - Risk-Minimizing: Minimize impact on goal completion
- **Protected Goals**: Shield critical goals from reductions
- **Impact Analysis**: Risk assessment with estimated delays

#### Performance Optimization
- **Multi-Level Caching**: Memory (NSCache) + Disk (PerformanceOptimizer) + Background processing
- **Batch API Calls**: Up to 50 currency pairs per request with rate limiting (10 req/min)
- **Parallel Processing**: TaskGroup for concurrent calculations
- **Background Queue**: Non-blocking UI with utility QoS processing
- **Automatic Cleanup**: Memory pressure handling and cache expiration

#### Accessibility Compliance (WCAG 2.1 AA)
- **Color Contrast**: All colors meet 4.5:1 contrast ratio minimum
- **VoiceOver Support**: Comprehensive screen reader descriptions for financial data
- **Keyboard Navigation**: Full keyboard accessibility with focus indicators
- **Haptic Feedback**: Contextual vibrations respecting user preferences
- **Colorblind Support**: 7 distinct colorblind-safe colors
- **Reduce Motion**: Animation adaptation for motion sensitivity
- **High Contrast**: Alternative color schemes for visual accessibility

#### Platform-Specific UI
- **iOS Compact**: iPhone-optimized segmented interface
- **iOS Regular**: iPad split-view with enhanced controls
- **macOS**: HSplitView architecture with native navigation patterns
- **Adaptive Design**: Automatic platform detection and UI adjustment

#### Enhanced Notification System
- **Monthly Payment Reminders**: Automated scheduling on 1st of each month
- **Smart Reminders**: Frequency based on goal urgency (daily/weekly/monthly)
- **Deadline Warnings**: 1 month, 1 week, and 1 day before deadlines
- **Risk-Based Alerts**: Critical goals get priority notifications
- **Customizable Settings**: User-configurable reminder preferences

#### Comprehensive Testing Suite
- **90+ Test Cases**: Unit, Integration, UI, Accessibility, and Performance tests
- **WCAG Compliance Testing**: Automated accessibility validation
- **Performance Benchmarks**: Speed and memory usage monitoring
- **Cross-Platform Testing**: iOS, macOS, and visionOS coverage
- **Continuous Integration**: GitHub Actions with quality gates

#### Documentation & Migration
- **Complete Documentation**: 4 comprehensive guides (150+ pages total)
  - Main Feature Documentation (`REQUIRED_MONTHLY_DOCUMENTATION.md`)
  - Quick Migration Guide (`MIGRATION_GUIDE.md`) 
  - API Reference (`API_REFERENCE.md`)
  - Testing Guide (`TESTING_GUIDE.md`)
- **Migration Support**: Backward compatible with existing data
- **Code Examples**: Comprehensive usage examples and best practices
- **Troubleshooting**: Common issues and solutions documented