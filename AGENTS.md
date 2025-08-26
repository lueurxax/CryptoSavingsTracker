# Repository Guidelines

## Project Structure & Modules
- `CryptoSavingsTracker/`: App source (Swift/SwiftUI, MVVM)
  - `Models/`, `ViewModels/`, `Views/`, `Services/`, `Utilities/`, `Repositories/`, `Navigation/`, `Assets.xcassets/`.
- `CryptoSavingsTrackerTests/`: Unit/integration tests (XCTest).
- `CryptoSavingsTrackerUITests/`: UI tests.
- `docs/`: Architecture, API, testing, and migration guides.
- `Config.plist` / `Config.example.plist`: Non-secret configuration; never commit secrets.

## Build, Run, and Test
- Build (CLI): `xcodebuild -scheme CryptoSavingsTracker -configuration Debug build`
- Run (Xcode): Open `CryptoSavingsTracker.xcodeproj`, select a simulator (e.g., iPhone 15), Run.
- Unit/Integration tests: `xcodebuild -scheme CryptoSavingsTracker -destination 'platform=iOS Simulator,name=iPhone 15' test`
- SwiftPM (where applicable): `swift build` and `swift test` (project includes `Package.swift`).

## Coding Style & Naming
- Swift 5+, SwiftUI, MVVM separation (Models → Services → ViewModels → Views).
- Indentation: 4 spaces; 120-char soft wrap.
- Types: `PascalCase`; properties/functions: `camelCase`; enum cases: `lowerCamelCase`.
- Files match primary type (e.g., `MonthlyPlanningService.swift`).
- Prefer protocols in `Protocols/` and dependency injection via `DIContainer`.
- Formatting/Linting: use SwiftLint if available; run formatter before PRs.

## Testing Guidelines
- Framework: XCTest; test files end with `Tests.swift` (e.g., `MonthlyPlanningServiceTests.swift`).
- Write unit tests for Services, Models, and ViewModels; add UI tests for critical flows.
- Coverage target: prioritize logic-heavy modules (planning, exchange rates, allocations).
- Run locally with the xcodebuild command above; keep tests deterministic (no network—use fixtures/mocks).

## Commit & Pull Requests
- Commits: imperative mood, scoped when helpful (e.g., `feat: add MonthlyPlanningWidget preview`).
- PRs: clear description, linked issues, reproduction steps, and screenshots for UI changes.
- Include: test coverage notes, migration notes (if data models change), and docs updates under `docs/`.
- Passing CI and lint/format checks required; no secrets in diffs (use `Config.example.plist`).

## Security & Configuration
- Do not hardcode API keys; use `Config.plist` and `KeychainManager` for sensitive values.
- Follow rate limiting patterns (`RateLimiter`) and cache policies (`BalanceCacheManager`).

