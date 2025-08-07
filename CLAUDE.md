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