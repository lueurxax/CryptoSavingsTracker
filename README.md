# CryptoSavingsTracker

A multi-platform application for tracking cryptocurrency savings goals.

## Platforms

| Platform | Directory | Status |
|----------|-----------|--------|
| iOS / macOS / visionOS | [`/ios`](./ios) | Production |
| Android | [`/android`](./android) | In Development |

## Project Structure

```
CryptoSavingsTracker/
├── ios/                    # iOS, macOS, visionOS (SwiftUI + SwiftData)
│   ├── CryptoSavingsTracker/           # Main app source
│   ├── CryptoSavingsTrackerTests/      # Unit tests
│   ├── CryptoSavingsTrackerUITests/    # UI tests
│   └── CryptoSavingsTracker.xcodeproj/
│
├── android/                # Android (Kotlin + Jetpack Compose)
│   ├── app/
│   └── gradle/
│
├── docs/                   # Shared documentation
│   ├── ARCHITECTURE.md     # System design
│   ├── DEVELOPMENT.md      # Development guide
│   ├── USER_GUIDES.md      # User documentation
│   └── ...
│
├── LICENSE
└── README.md               # This file
```

## Documentation

See [`/docs`](./docs) for comprehensive documentation:

- **[ARCHITECTURE.md](./docs/ARCHITECTURE.md)** - System architecture and design patterns
- **[DEVELOPMENT.md](./docs/DEVELOPMENT.md)** - Development guide and roadmap
- **[USER_GUIDES.md](./docs/USER_GUIDES.md)** - User guides and troubleshooting
- **[MONTHLY_PLANNING.md](./docs/MONTHLY_PLANNING.md)** - Monthly planning feature docs

## Quick Start

### iOS / macOS

```bash
cd ios
open CryptoSavingsTracker.xcodeproj
```

Requirements:
- Xcode 15+
- iOS 17+ / macOS 14+

### Android

```bash
cd android
./gradlew build
```

Requirements:
- Android Studio Hedgehog+
- Android SDK 34+

## Features

- Track savings goals in any cryptocurrency
- Monitor progress across multiple wallets
- Monthly planning and budgeting tools
- Multi-currency support with real-time exchange rates
- Cloud sync (iCloud for Apple platforms)

## License

See [LICENSE](./LICENSE) for details.
