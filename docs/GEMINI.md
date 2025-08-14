# CryptoSavingsTracker

## Project Overview

This is a cross-platform SwiftUI application for tracking cryptocurrency savings goals. It allows users to create portfolio-based goals with multiple cryptocurrency assets and track their progress toward financial targets. The app is built using modern SwiftUI practices, including the MVVM (Model-View-ViewModel) architecture, and utilizes SwiftData for local data persistence. It integrates with the CoinGecko API for real-time cryptocurrency exchange rates. The application is designed to run on iOS, macOS, and visionOS.

The project is structured into several directories:

*   `CryptoSavingsTracker`: Contains the main source code for the application, including models, views, and view models.
*   `CryptoSavingsTrackerTests`: Contains unit tests for the application.
*   `CryptoSavingsTrackerUITests`: Contains UI tests for the application.
*   `docs`: Contains documentation for the project.

## Building and Running

To build and run this project, you will need Xcode 15.0+ and an Apple Developer account.

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd CryptoSavingsTracker
    ```

2.  **Configure API Key:**
    *   Copy `Config.example.plist` to `Config.plist`.
    *   Open `Config.plist` and replace `YOUR_COINGECKO_API_KEY` with your actual CoinGecko API key.

3.  **Open in Xcode:**
    ```bash
    open CryptoSavingsTracker.xcodeproj
    ```

4.  **Build and Run:**
    *   Select the desired scheme (e.g., `CryptoSavingsTracker (iOS)`).
    *   Select a simulator or a connected device.
    *   Press `Cmd+R` to build and run the application.

### Testing

To run the tests, you can use the following command:

```bash
xcodebuild test -scheme CryptoSavingsTracker -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Development Conventions

*   **Architecture:** The project follows the MVVM (Model-View-ViewModel) design pattern.
    *   **Models:** Located in the `CryptoSavingsTracker/Models` directory, these are SwiftData objects that represent the application's data.
    *   **Views:** Located in the `CryptoSavingsTracker/Views` directory, these are SwiftUI views that define the user interface.
    *   **ViewModels:** Located in the `CryptoSavingsTracker/ViewModels` directory, these classes contain the business logic and prepare data for the views.
*   **Concurrency:** The project uses `async/await` for handling asynchronous operations, such as API calls.
*   **Data Persistence:** SwiftData is used for local data storage.
*   **Dependency Management:** The project does not use any external package managers like Swift Package Manager or CocoaPods. All dependencies are included directly in the project.
*   **Code Style:** The code follows the standard Swift API Design Guidelines.

## Gemini's Contributions

### BalanceService Review and Enhancement

*   **Date:** 2025-08-13
*   **Summary:** Reviewed the `BalanceService` and its related components (`BalanceCacheManager`, `RateLimiter`) for stability, caching, and rate limiting.
*   **Findings:**
    *   The service is well-structured, stable, and uses effective caching and rate-limiting strategies.
    *   The implementation aligns with the project's documented architecture.
    *   Error handling is robust, with fallbacks to cached data to improve user experience during network failures.
*   **Enhancements:**
    *   Replaced `print` statements in `BalanceCacheManager` with the project's structured `Logger` for consistent and filterable logging.

### TransactionService Review and Enhancement

*   **Date:** 2025-08-13
*   **Summary:** Reviewed the `TransactionService` and implemented rate limiting and improved caching to enhance stability and performance.
*   **Enhancements:**
    *   **Rate Limiting:** Integrated a `RateLimiter` to control the frequency of API requests, preventing the application from exceeding the API's rate limits. This is especially important for fetching transaction history for multiple addresses in quick succession.
    *   **Improved Caching:** The existing caching for successful transaction responses was maintained.
*   **Note on Caching Empty Responses:** Caching of empty responses was initially considered but ultimately not implemented. Some of the underlying APIs have been observed to occasionally return empty responses erroneously. Caching these empty responses would prevent the application from retrieving the correct transaction data until the cache expires. To ensure data accuracy, empty responses are not cached, and the application will always attempt to fetch transaction data if no cached data is available.
