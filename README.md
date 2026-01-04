# CryptoSavingsTracker

A multi-platform application for tracking cryptocurrency savings goals.

## Platforms

| Platform | Directory | Status | Completion |
|----------|-----------|--------|------------|
| iOS / macOS / visionOS | [`/CryptoSavingsTracker`](./CryptoSavingsTracker) | ✅ Production | 100% |
| Android | [`/android`](./android) | 🔄 In Development | ~90% |

### Android Development Progress

The Android version is nearing completion with full iOS feature parity:

| Phase | Status |
|-------|--------|
| Foundation (Room, Hilt, Compose) | ✅ Complete |
| Goal Management | ✅ Complete |
| Asset Management | ✅ Complete |
| Transaction Management | ✅ Complete |
| Allocation System | ✅ Complete |
| Monthly Planning | ✅ Complete |
| Execution Tracking | ✅ Complete |
| Dashboard & API Integration | ✅ Complete |
| Testing & Polish | 🔄 In Progress |

**Codebase:** 179 Kotlin files, 14 domain models, 50+ screens

See [`/docs/ANDROID_DEVELOPMENT_PLAN.md`](./docs/ANDROID_DEVELOPMENT_PLAN.md) for detailed status.

## Project Structure

```
CryptoSavingsTracker/
├── CryptoSavingsTracker/               # iOS, macOS, visionOS source
│   ├── Models/                         # SwiftData models
│   ├── Views/                          # SwiftUI views
│   ├── ViewModels/                     # MVVM coordinators
│   ├── Services/                       # Business logic
│   └── Utilities/                      # Helpers & extensions
│
├── CryptoSavingsTrackerTests/          # iOS unit tests
├── CryptoSavingsTrackerUITests/        # iOS UI tests
├── CryptoSavingsTracker.xcodeproj/     # Xcode project
│
├── android/                            # Android (Kotlin + Jetpack Compose)
│   └── app/src/main/java/.../
│       ├── data/                       # Room database, repositories, APIs
│       │   ├── local/database/         # Entities, DAOs, converters
│       │   ├── remote/api/             # CoinGecko, Tatum APIs
│       │   └── repository/             # Repository implementations
│       ├── domain/                     # Business logic
│       │   ├── model/                  # Domain models (14)
│       │   ├── repository/             # Repository interfaces
│       │   └── usecase/                # Use cases (57+)
│       ├── presentation/               # UI layer
│       │   ├── goals/                  # Goal screens
│       │   ├── assets/                 # Asset screens
│       │   ├── planning/               # Monthly planning
│       │   ├── execution/              # Execution tracking
│       │   ├── dashboard/              # Dashboard
│       │   ├── charts/                 # Chart components
│       │   └── navigation/             # Navigation
│       └── di/                         # Hilt modules
│
├── docs/                               # Shared documentation
│   ├── ANDROID_DEVELOPMENT_PLAN.md     # Android implementation status
│   ├── ARCHITECTURE.md                 # iOS system design
│   ├── DEVELOPMENT.md                  # Development guide
│   └── ...
│
├── LICENSE
└── README.md                           # This file
```

## Documentation

See [`/docs`](./docs) for comprehensive documentation:

### Android Development
- **[ANDROID_DEVELOPMENT_PLAN.md](./docs/ANDROID_DEVELOPMENT_PLAN.md)** - Android implementation status, iOS parity tracking, architecture

### iOS/macOS Development
- **[ARCHITECTURE.md](./docs/ARCHITECTURE.md)** - iOS system architecture and design patterns
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
./gradlew assembleDebug        # Build debug APK
./gradlew testDebugUnitTest    # Run unit tests
./gradlew connectedDebugAndroidTest  # Run instrumented tests
```

Requirements:
- Android Studio Ladybug+ (2024.2+)
- Android SDK 36 (compileSdk)
- Android SDK 34+ (minSdk)
- JDK 17

Key Technologies:
- Jetpack Compose (UI)
- Room (Database)
- Hilt (Dependency Injection)
- Kotlin Coroutines + Flow (Async/Reactive)
- Retrofit + OkHttp (Networking)

## Features

- Track savings goals in any cryptocurrency
- Monitor progress across multiple wallets
- Monthly planning and budgeting tools
- Multi-currency support with real-time exchange rates
- Cloud sync (iCloud for Apple platforms)

## License

See [LICENSE](./LICENSE) for details.
