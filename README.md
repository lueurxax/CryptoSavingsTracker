# CryptoSavingsTracker

CryptoSavingsTracker is a savings goal and asset tracking app.

The current public release scope is focused on the Apple app experience: create goals, add assets, record contributions, review progress, and manage monthly planning and execution flows. The repository also contains Android work, internal review artifacts, and proposal documents that support ongoing product development.

## Current Scope

- Apple app: active App Store release track
- Android app: repository work in progress, not the primary public release contract
- Internal docs: architecture notes, proposals, audits, and release evidence

## Repository Layout

```text
.
├── ios/
│   ├── CryptoSavingsTracker/                # Apple app source (Swift / SwiftUI / SwiftData)
│   ├── CryptoSavingsTrackerTests/           # Unit and integration tests
│   ├── CryptoSavingsTrackerUITests/         # UI tests
│   └── CryptoSavingsTracker.xcodeproj/      # Xcode project
├── android/                                 # Android app work (Kotlin / Compose)
├── docs/                                    # Product, architecture, proposals, runbooks
├── artifacts/                               # Review evidence and generated screenshots
└── README.md
```

## Apple App Highlights

- Goal creation and editing
- Asset tracking and allocation to goals
- Manual contribution logging
- Goal dashboard and progress review
- Monthly planning and monthly execution flows
- Settings, support, and App Store release metadata

## Development

### Build

```bash
cd ios
xcodebuild -scheme CryptoSavingsTracker -configuration Debug build
```

### Test

```bash
cd ios
xcodebuild -scheme CryptoSavingsTracker -destination 'platform=iOS Simulator,name=iPhone 15' test
```

### Open in Xcode

```bash
cd ios
open CryptoSavingsTracker.xcodeproj
```

## Documentation

Useful starting points:

- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md)
- [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md)
- [docs/MONTHLY_PLANNING.md](./docs/MONTHLY_PLANNING.md)
- [docs/USER_GUIDES.md](./docs/USER_GUIDES.md)
- [docs/proposals](./docs/proposals)

## Public Support

- Support: [https://lueurxax.github.io/CryptoSavingsTracker/support/](https://lueurxax.github.io/CryptoSavingsTracker/support/)
- Privacy Policy: [https://lueurxax.github.io/CryptoSavingsTracker/privacy/](https://lueurxax.github.io/CryptoSavingsTracker/privacy/)

## License

See [LICENSE](./LICENSE).
