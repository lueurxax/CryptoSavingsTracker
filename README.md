# CryptoSavingsTracker

A cross-platform SwiftUI application for tracking cryptocurrency savings goals. Set portfolio-based goals with multiple cryptocurrency assets and track your progress toward financial targets.

## Features

- 📊 **Portfolio-based Goals**: Create savings goals with multiple cryptocurrency assets
- 💰 **Real-time Exchange Rates**: Powered by CoinGecko API for accurate pricing
- 🔍 **Searchable Currency Picker**: Choose from 5000+ cryptocurrencies
- 📱 **Cross-Platform**: Native SwiftUI for iOS, macOS, and visionOS
- 💾 **Data Persistence**: SwiftData for local storage with automatic synchronization
- 🔔 **Smart Notifications**: Deadline reminders and progress alerts
- 🎯 **Progress Tracking**: Visual progress indicators and goal completion status

## Screenshots

*Screenshots coming soon*

## Requirements

- **iOS**: 17.0+
- **macOS**: 14.0+
- **visionOS**: 1.0+
- **Xcode**: 15.0+
- **Swift**: 5.9+

## Installation

### Prerequisites

1. Get a free CoinGecko API key:
   - Visit [CoinGecko API](https://www.coingecko.com/en/api)
   - Sign up for a free account
   - Generate your API key

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/CryptoSavingsTracker.git
   cd CryptoSavingsTracker
   ```

2. Open the project in Xcode:
   ```bash
   open CryptoSavingsTracker.xcodeproj
   ```

3. Configure your API key:
   - Open `CoinGeckoService.swift`
   - Replace `YOUR_COINGECKO_API_KEY` with your actual API key
   - Open `ExchangeRateService.swift`
   - Replace `YOUR_COINGECKO_API_KEY` with your actual API key

4. Update the bundle identifier:
   - Select the project in Xcode
   - Update the bundle identifier to your own (e.g., `com.yourname.CryptoSavingsTracker`)

5. Build and run:
   - Select your target device/simulator
   - Press `Cmd+R` to build and run

## Usage

### Creating Your First Goal

1. Launch the app and tap "Add New Goal"
2. Enter a goal name (e.g., "Vacation Fund")
3. Select your target currency (e.g., "USD")
4. Set your target amount (e.g., $5000)
5. Choose a deadline date
6. Tap "Save"

### Adding Cryptocurrency Assets

1. Select your goal from the main list
2. Tap "Add Asset"
3. Choose a cryptocurrency (e.g., "BTC", "ETH")
4. Tap "Save"

### Recording Transactions

1. In your goal detail view, find the asset
2. Tap on the asset row
3. Tap "Add Transaction"
4. Enter the amount you've saved in that cryptocurrency
5. Tap "Save"

The app will automatically calculate your progress by converting all assets to your goal's target currency using real-time exchange rates.

## Architecture

The app follows modern SwiftUI best practices:

- **SwiftData**: Core Data replacement for local persistence
- **MVVM Pattern**: Clean separation of concerns
- **Async/Await**: Modern concurrency for API calls
- **Portfolio-based Design**: Multiple assets per goal for diversified savings

### Data Model

```
Goal (1) → Assets (many) → Transactions (many)
```

- **Goals**: Top-level savings targets with currency and amount
- **Assets**: Individual cryptocurrencies within a goal
- **Transactions**: Deposit records for each asset

## Platform Support

The app is designed to work seamlessly across Apple platforms:

### iOS
- Native navigation with toolbar controls
- Optimized for iPhone and iPad
- Keyboard shortcuts for forms

### macOS
- Pure SwiftUI implementation avoiding AppKit controls
- Graphical date pickers for better compatibility
- Proper window sizing and keyboard navigation

### visionOS
- Future-ready for spatial computing
- Adaptive layouts for immersive experiences

## API Integration

### CoinGecko API

The app integrates with CoinGecko's public API for:
- **Supported Currencies**: `/api/v3/simple/supported_vs_currencies`
- **Price Data**: `/api/v3/simple/price`

All API calls include:
- 5-minute caching for performance
- Persistent cache across app restarts
- Error handling and offline support

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftUI best practices
- Include comments for complex logic
- Ensure cross-platform compatibility

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [CoinGecko](https://www.coingecko.com) for providing free cryptocurrency data
- Apple for the excellent SwiftUI and SwiftData frameworks
- The iOS development community for inspiration and best practices

## Support

If you encounter any issues or have questions:

1. Check the [Issues](https://github.com/yourusername/CryptoSavingsTracker/issues) page
2. Create a new issue with detailed description
3. Include your iOS/macOS version and steps to reproduce

---

Made with ❤️ using SwiftUI