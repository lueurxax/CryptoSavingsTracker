# Claude Code Workspace

## Development Notes

This is a SwiftUI cryptocurrency savings tracker app built for iOS, macOS, and visionOS.

### API Configuration

- **CoinGecko API**: The app uses CoinGecko API for real-time exchange rates
- **API Key Setup**: Replace `YOUR_COINGECKO_API_KEY` in both `CoinGeckoService.swift` and `ExchangeRateService.swift` with your actual API key
- **Get API Key**: Visit [CoinGecko API](https://www.coingecko.com/en/api) to get a free API key

### Build Commands

- **Build**: Use Xcode's Cmd+B or `xcodebuild` command
- **Run**: Use Xcode's Cmd+R or simulator/device deployment
- **Test**: No specific test framework configured yet

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