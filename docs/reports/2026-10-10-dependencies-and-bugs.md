# Dependency updates and confirmed bugs

Date: 2026-10-10

Compatible stable Android dependencies have been updated, including the Kotlin compiler, networking, persistence, Compose and test libraries. The Apple app has no external Swift package dependencies. Six application defects were reproduced in the initial working copy. All six were subsequently fixed with regression coverage; see [the fix report](2026-10-10-six-bug-fixes.md) for current results. The initial audit and maintenance results are retained below.

## Dependency versions

| Dependency | Previous | Selected |
| --- | --- | --- |
| Gradle | 8.13 | 8.14.6 |
| Foojay toolchain resolver | 0.10.0 | 1.0.0 |
| Kotlin | 2.0.21 | 2.3.21 |
| KSP | 2.0.21-1.0.28 | 2.3.12 |
| AndroidX Core | 1.17.0 | 1.18.0 |
| AppCompat | 1.7.1 | 1.8.0 |
| Activity Compose | 1.9.3 | 1.13.0 |
| Lifecycle Runtime Compose | 2.8.7 | 2.10.0 |
| Compose BOM | 2024.12.01 | 2026.06.01 |
| Navigation Compose | 2.8.5 | 2.9.8 |
| Room | 2.6.1 | 2.8.5 |
| Hilt | 2.52 | 2.58 |
| Hilt Navigation Compose | 1.2.0 | 1.3.0 |
| Hilt Work | 1.2.0 | 1.4.0 |
| Retrofit | 2.11.0 | 3.0.0 |
| OkHttp and MockWebServer | 4.12.0 | 5.4.0 |
| Kotlin serialization | 1.7.3 | 1.11.0 |
| Kotlin coroutines | Test library 1.9.0 | Runtime and test libraries 1.11.0 |
| DataStore Preferences | 1.1.1 | 1.2.1 |
| Security Crypto | 1.1.0-alpha06 | 1.1.0 |
| WorkManager | 2.10.0 | 2.12.0 |
| Vico | 2.0.0-beta.2 | 2.5.1 |
| JUnit 5 | 5.11.3 | 5.14.4 |
| MockK | 1.13.13 | 1.14.11 |
| Truth | 1.4.4 | 1.4.5 |
| Turbine | 1.2.0 | 1.2.1 |
| JSON Schema Validator | 1.5.6 | 1.5.9 |
| Android test runner | 1.6.2 | 1.7.0 |
| Android test rules | 1.6.1 | 1.7.0 |
| Material | 1.13.0 | 1.14.0 |

The archived Jake Wharton serialization converter was replaced with `com.squareup.retrofit2:converter-kotlinx-serialization`, using the same version as Retrofit. The maintained converter contains the imported implementation from the old converter. [Retrofit changelog](https://raw.githubusercontent.com/square/retrofit/3.0.0/CHANGELOG.md)

Android remains on compile/target SDK 36, min SDK 34 and AGP 8.13.2. Kotlin 2.3 fits the compiler support documented for that AGP release. Hilt 2.59 and later require AGP 9; newer Core, Lifecycle, Navigation, Hilt Navigation, Vico and OkHttp releases inspected during selection require SDK 37 and/or newer tooling. JUnit and JSON Schema Validator stay within their current major release lines. [AGP compatibility](https://developer.android.com/build/releases/agp-8-13-0-release-notes), [Hilt release requirement](https://github.com/google/dagger/releases/tag/dagger-2.59)

Gradle's distribution checksum is pinned. The Kotlin compiler configuration now uses `compilerOptions`, and mixed SQL binding arrays explicitly use `Any`. Vico keeps its axis spacing of five through the new lambda argument. [Kotlin compiler migration](https://kotlinlang.org/docs/gradle-compiler-options.html)

## Verification repairs

JUnit Vintage and an explicit platform launcher restore discovery of 13 existing JUnit 4 cases in three classes. Previously the JUnit Platform ran only the 62 JUnit 5 cases. No test was disabled or removed.

The Apple rate-drift test now waits for the actual recorded event and still asserts its exact goal IDs. The camera contract still checks the DEBUG and iOS guard, while ignoring leading indentation of preprocessor directives.

Compose month labels in the heatmap and planning action strip read the observable locale instead of `Locale.getDefault()`. The reminder worker retains its permission check and additionally handles permission revocation during notification dispatch. These changes resolve four lint errors without suppressing the checks.

## Initial maintenance validation results

| Check | Result |
| --- | --- |
| Apple unit and integration scheme on iOS 27 simulator | 599 passed, zero failures or skips |
| Android unit suite | 75 passed, zero failures, errors or skips |
| Android debug application APK | Built successfully |
| Android instrumentation APK | Built successfully |
| Android Lint | Zero errors, 103 warnings, two hints |
| Room exported schemas | Unchanged |
| Independent review of the maintenance patch | No material regression found |
| Original working-copy edits and Git index | Preserved |

The 13 previously omitted JUnit 4 tests are in `VisualSystemRolloutTest` (four), `NavigationTelemetryTrackerTest` (four) and `MonthlyCycleActionGateTest` (five). Lint warnings include existing locale-formatting calls, API conveniences, resource cleanup and notices about newer dependency versions; they were not suppressed. Instrumentation tests were compiled into an APK, but were not executed on an Android device. The Apple validation covers the iOS simulator, not macOS or visionOS execution.

Validation commands from the repository root:

```sh
xcodebuild -project ios/CryptoSavingsTracker.xcodeproj \
  -scheme CryptoSavingsTrackerTests \
  -destination 'platform=iOS Simulator,id=6D71D81C-35CD-4DA1-A310-6FCC54EB821F' \
  -derivedDataPath /private/tmp/cst-audit-20261010/DerivedData \
  -resultBundlePath /private/tmp/cst-audit-20261010/apple-unit-verified.xcresult test

cd android
GRADLE_USER_HOME=/private/tmp/cst-gradle-audit-cache ./gradlew \
  --no-daemon --max-workers=4 \
  :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug
```

The result-bundle path must be changed for a repeated Xcode run because Xcode does not overwrite an existing bundle. Run receipts: [Apple test log](/private/tmp/cst-audit-20261010/apple-unit-verified.log), [Android build and lint log](/private/tmp/cst-audit-20261010/android-verified-lint.log).

The task's additions contain no trailing-whitespace errors. A whole-worktree `git diff --check` also sees pre-existing whitespace in the user's original edits; those edits were preserved rather than reformatted.

## Application bugs confirmed in the initial working copy

### Android starting tracking changes saved amounts

Priority: P1. Source: [StartExecutionUseCase.kt line 45](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/domain/usecase/execution/StartExecutionUseCase.kt:45), [MonthlyGoalPlanService.kt line 138](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/domain/usecase/planning/MonthlyGoalPlanService.kt:138).

Set a custom amount of 60 for a goal whose base requirement is 100, then start tracking. Starting tracking reapplies flex=1 and clears the custom amount, producing a snapshot of 100. Alternatively, apply 50% flex to a base amount of 100: the displayed plan is 50, but starting tracking reapplies the factor to the already adjusted amount and produces 25. Budget allocation is affected because it also persists custom amounts.

The execution snapshot should use the saved effective plan amounts once, preserving custom and budget choices.

### Android execution treats asset units as goal currency

Priority: P1. Source: [ExecutionProgressCalculator.kt line 219](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/domain/usecase/execution/ExecutionProgressCalculator.kt:219), [GoalProgressCard.kt line 97](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/execution/components/GoalProgressCard.kt:97).

Add a contribution to a BTC asset allocated to a USD goal. The calculator sums raw asset quantities without asset or exchange-rate context, then the UI formats that number in the goal currency. A one-BTC fixture yields `contributed=1.0` for the USD goal. Remaining amounts and fulfillment are therefore calculated using incompatible units; completing execution persists the same result.

Convert each asset's contribution into the specific goal currency before summing, and use the same calculation for completion history.

### Android goal progress stays stale after transaction edits

Priority: P2. Source: [GetGoalProgressUseCase.kt line 65](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/domain/usecase/goal/GetGoalProgressUseCase.kt:65).

Keep the goal list or detail flow subscribed and edit a manual transaction from 100 to 50. Direct recalculation returns 50, but both existing flows retain 100 and emit no new result. The list subscribes only to goals; detail subscribes to goals and allocations. Changes to transactions and asset balances are absent from these subscriptions. Updating the allocation refreshes detail but still leaves the list stale.

Include the money sources in the reactive calculation, including an invalidation signal for refreshed on-chain balances.

### Apple planning applies flex twice and omits currency conversion

Priority: P2. Source: [MonthlyPlanningViewModel.swift line 119](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/ViewModels/MonthlyPlanningViewModel.swift:119).

With Preview Features enabled, apply 50% flex to a USD100 monthly requirement. The persisted effective amount is USD50, but `adjustedTotal` applies the percentage again and displays USD25. Whenever flex differs from 1, this total also sums raw amounts without currency conversion: a protected EUR100 requirement with a fixture rate of EUR→USD=1.2 displays USD100 instead of USD120.

Calculate the displayed total from effective amounts with currency conversion, without reapplying flex.

### Apple removing a skip leaves the payment at zero

Priority: P2. Source: [MonthlyPlanService.swift line 385](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/MonthlyPlanService.swift:385).

With Preview Features enabled, skip a goal for the month, then undo the skip or choose Reset/Pay Exact. The bulk adjustment changes its flex state but never clears `isSkipped`. The effective amount therefore remains zero, and reloading restores the skipped presentation. A base requirement of 100 still produces an effective amount of zero after unskip.

Synchronize both the skip flag and the flex state when a goal leaves the skipped set.

### Apple token balances ignore later portfolio pages

Priority: P2. Source: [BalanceService.swift line 118](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/BalanceService.swift:118).

For a supported EVM chain, request a token found after the first portfolio page. The service fetches only one page and treats absence of the token there as a successful zero balance. The fixture contains 50 other tokens on page one and USDT42 on page two; the result is zero after one request and can be cached as such. Tatum documents a default page size of 50 and offset pagination. [Tatum portfolio API](https://docs.tatum.io/reference/getwalletportfoliov4)

Search the remaining pages before concluding that a token balance is zero.

## Reproduction evidence

Deterministic Swift fixtures execute the relevant method bodies extracted from the working copy. Kotlin fixtures compile and execute the actual planning, execution-progress and goal-progress classes with isolated repositories. These checks validate the algorithms and their reachable consumer paths; they do not establish live wallet balances or production API behavior.

```text
DOUBLE_FLEX: persisted=50.0, displayed=25.0, expected=50
MISSING_FX: convertedTotal=120.0, displayed=100.0, expectedUSD=120
UNSKIP: isSkipped=true, flexState=flexible, effective=0.0, expected=100
PAGINATION: requests=1, actualUSDT=0.0, expectedUSDT=42.0
START_DEFAULT_FLEX: explicit=60.0, snapshot=100.0, custom=null
START_HALF_FLEX: preview=50.0, snapshot=25.0
EXECUTION_UNITS: asset=BTC, deposit=1.0, displayed=1.0 USD
PROGRESS_TRANSACTION_EDIT: listCached=100.0, detailCached=100.0, actual=50.0, no emissions
PROGRESS_ALLOCATION_EDIT: detail=50.0, listCached=100.0, no list emission
```

Android is still the repository's work-in-progress app. The two Apple monthly-planning findings require opting into Preview Features; the portfolio pagination finding affects ordinary token-balance consumers.
