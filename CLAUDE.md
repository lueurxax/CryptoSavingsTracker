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