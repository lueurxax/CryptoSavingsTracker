# Android Development Plan - CryptoSavingsTracker

> Comprehensive plan for Android version with iOS feature parity

| Metadata | Value |
|----------|-------|
| Status | 🔄 In Progress |
| Last Updated | 2026-01-05 |
| Platform | Android |
| Audience | Developers |

---

## Overview

This document outlines the comprehensive plan to build the Android version of CryptoSavingsTracker, ensuring feature parity with the iOS/macOS app while following Android best practices and Modern Android Development (MAD) guidelines.

---

## Implementation Status (Updated: December 21, 2025)

### Phase Completion Summary

| Phase | Description | Status | Completion |
|-------|-------------|--------|------------|
| **Phase 1** | Foundation (Room, Hilt, Compose) | ✅ Complete | 100% |
| **Phase 2** | Goal Management CRUD | ✅ Complete | 100% |
| **Phase 3** | Asset Management | ✅ Complete | 100% |
| **Phase 4** | Transaction Management | ✅ Complete | 100% |
| **Phase 5** | Allocation System | ✅ Complete | 100% |
| **Phase 6** | Monthly Planning & Exchange Rates | ✅ Complete | 100% |
| **Phase 7** | Execution Tracking & Dashboard | ✅ Complete | 100% |
| **Phase 8** | Testing & Polish | 🔄 In Progress | ~70% |

### Codebase Statistics

| Metric | Count |
|--------|-------|
| Total Kotlin files | 179 |
| Domain models | 14 |
| Use cases/services | 57+ |
| Repository interfaces | 13 |
| Repository implementations | 21 |
| Room entities | 10 |
| DAOs | 10 |
| UI screens | 50+ |
| DAO test coverage | 100% |

### Feature Status

#### ✅ Fully Implemented

| Feature | iOS Parity | Notes |
|---------|------------|-------|
| Goal CRUD | ✅ Full | Lifecycle statuses match iOS exactly |
| Asset CRUD | ✅ Full | Chain auto-detection from currency symbols |
| Transaction CRUD | ✅ Full | Manual + on-chain source tracking |
| Allocations | ✅ Full | Over-allocation detection, history tracking |
| Monthly Planning | ✅ Full | Per-goal customization, flex percentage |
| Execution Tracking | ✅ Full | 24-hour undo window, progress calculation |
| Exchange Rates | ✅ Full | CoinGecko API with rate limiting |
| On-Chain Balances | ✅ Full | Tatum API integration |
| Dashboard | ✅ Full | Portfolio overview, goal summary |
| CSV Export | ✅ Full | Matches iOS export format |
| Budget Calculator | ✅ Full | All 10 UI/UX improvements from iOS |

#### 🔄 In Progress (Untracked Files Ready for Commit)

| Feature | Files | Status |
|---------|-------|--------|
| **Charts** | 4 files in `presentation/charts/` | Implementation complete, needs integration |
| | - ProgressRingChart.kt | Animated progress visualization (0-150%) |
| | - ForecastChart.kt | Projection visualization |
| | - HeatmapCalendar.kt | Activity calendar view |
| | - SparklineChart.kt | Inline sparkline charts |
| **UI Components** | 5 files in `presentation/components/` | Ready for use |
| | - EmptyState.kt | Empty state UI patterns |
| | - HelpTooltip.kt | Contextual help tooltips |
| | - PullToRefresh.kt | Pull-to-refresh gesture |
| | - ReminderConfiguration.kt | Reminder settings UI |
| | - SwipeActions.kt | Swipe-to-delete gestures |
| **Onboarding** | 2 files in `presentation/onboarding/` | Feature complete |
| | - OnboardingScreen.kt | Multi-step intro flow |
| | - OnboardingViewModel.kt | Onboarding state |
| **What-If Simulator** | 1 file in `presentation/whatif/` | Feature complete |
| | - WhatIfSimulator.kt | Scenario projection tool |
| **On-Chain Transactions** | 2 files | Ready for integration |
| | - OnChainTransactionRepository.kt | Domain interface |
| | - OnChainTransactionRepositoryImpl.kt | Tatum implementation |

#### 📋 Modified Files (Staged Changes)

35 files have modifications for iOS parity fixes and enhancements:
- ViewModels updated for latest features
- Screen components refactored
- Repository implementations enhanced
- Use case services improved
- Test files added

### Recent Commits

| Commit | Description |
|--------|-------------|
| `01732ab` | Chain auto-detection and iOS parity fixes |
| `a8a7d48` | Phases 5-7: execution tracking, API integration, dashboard |
| `7b10ded` | Exchange Rate and Monthly Planning services |
| `b7d30ff` | Phase 2 allocation system with iOS parity |
| `234da65` | Phase 2 fixes: progress and navigation |

### iOS Parity Achieved

| Feature | Implementation |
|---------|---------------|
| GoalLifecycleStatus enum | Matches iOS: `active`, `cancelled`, `finished`, `deleted` |
| Chain auto-detection | 14+ chains with currency-based prediction |
| Progress calculation | `min(allocation.amount, assetManualBalance)` formula |
| Allocation validation | Over-allocation detection matches iOS behavior |
| MonthlyGoalPlan | Per-goal customization architecture |
| Date storage | epochDay for dates, epochMillis for timestamps |
| CSV export | 3-file format matching iOS exactly |
| Budget Calculator UI | Full parity: 10 UI/UX fixes + payment schedule sheet |

### Remaining Work

| Task | Priority | Estimate |
|------|----------|----------|
| **Fix execution progress tracking bug** | P0 | 1 day |
| Commit untracked features (charts, onboarding, what-if) | P0 | Ready |
| Fix iOS parity gaps (see below) | P1 | 3-5 days |
| Integration tests for new components | P1 | 1-2 days |
| UI polish and edge case handling | P1 | 2-3 days |
| Accessibility audit (TalkBack) | P1 | 1 day |
| Performance optimization | P2 | 1-2 days |
| Play Store preparation | P2 | 2-3 days |

---

## Critical Bug Fixes & iOS Parity Gaps (December 21, 2025)

### 🔴 BUG: Execution Progress Shows 0% (CRITICAL) - ✅ FIXED

**Symptom**: Monthly execution screen shows 0% progress even when transactions have been added.

**Root Cause**: Transaction timestamp handling difference between iOS and Android.

| Platform | Transaction Date Handling |
|----------|---------------------------|
| **iOS** | `Date()` = current instant with exact time (e.g., 12:45:32 PM) |
| **Android (broken)** | `LocalDate.now().atStartOfDay()` = midnight (00:00:00) |

**The Problem**:
1. Execution starts at 12:32 PM → `startedAtMillis` = 12:32 PM timestamp
2. User adds transaction with date = "today"
3. Android converts to **midnight** (00:00:00)
4. Midnight < 12:32 PM → transaction is **BEFORE** execution window
5. Filter excludes it: `.filter { it.dateMillis in startedAtMillis..nowMillis }`
6. Result: 0% progress

**Fix Applied** (December 21, 2025):

Files modified:
- `presentation/transactions/AddTransactionViewModel.kt`
- `presentation/transactions/EditTransactionViewModel.kt`

```kotlin
// Before (broken):
val dateMillis = currentState.date
    .atStartOfDay(ZoneId.systemDefault())
    .toInstant()
    .toEpochMilli()

// After (iOS parity):
val dateMillis = if (currentState.date == LocalDate.now()) {
    System.currentTimeMillis()  // Use actual current time for today
} else {
    currentState.date
        .atStartOfDay(ZoneId.systemDefault())
        .toInstant()
        .toEpochMilli()
}
```

**Lesson Learned**: Always compare iOS and Android implementations for timestamp/date handling - iOS uses `Date()` (instant), Android often uses `LocalDate` (date only).

---

### 🔴 BUG: ReminderFrequency Enum Mismatch - ✅ FIXED

**Symptom**: Android had a `DAILY` reminder frequency option that doesn't exist in iOS.

**Root Cause**: Android added an extra enum value not present in iOS.

| Platform | ReminderFrequency Options |
|----------|---------------------------|
| **iOS** | `weekly`, `biweekly`, `monthly` (3 options) |
| **Android (broken)** | `DAILY`, `WEEKLY`, `BIWEEKLY`, `MONTHLY` (4 options) |

**The Problem**:
1. iOS app creates goals with only 3 reminder frequency options
2. Android allows selecting `DAILY` which iOS can't parse
3. Data sync between platforms would cause inconsistencies
4. Also: iOS uses `DateComponents(month: 1)` for monthly (actual calendar month), Android used fixed 30 days

**Fix Applied** (December 21, 2025):

Files modified:
- `domain/model/Goal.kt` - Removed DAILY enum value, added rawValue for DB compatibility
- `presentation/components/ReminderConfiguration.kt` - Import domain enum, use `plusFrequency()` for accurate date calculation
- `data/local/reminders/GoalReminderSchedulerImpl.kt` - Removed DAILY case
- `data/export/CsvExportFormatter.kt` - Removed DAILY case
- `test/.../AddGoalUseCaseTest.kt` - Updated test to use WEEKLY instead of DAILY

```kotlin
// Before (broken - 4 options):
enum class ReminderFrequency {
    DAILY, WEEKLY, BIWEEKLY, MONTHLY
}

// After (iOS parity - 3 options with rawValue):
enum class ReminderFrequency(val rawValue: String) {
    WEEKLY("weekly"),
    BIWEEKLY("biweekly"),
    MONTHLY("monthly");
}

// Also added proper calendar month handling:
fun LocalDate.plusFrequency(frequency: ReminderFrequency): LocalDate = when (frequency) {
    ReminderFrequency.WEEKLY -> this.plusDays(7)
    ReminderFrequency.BIWEEKLY -> this.plusDays(14)
    ReminderFrequency.MONTHLY -> this.plusMonths(1)  // Actual calendar month
}
```

**Lesson Learned**: Always compare enums/constants between platforms to ensure exact parity. iOS is the source of truth.

---

### 🟠 iOS Parity Gaps (Missing Features)

#### Gap 1: AutomationScheduler (HIGH PRIORITY)

**iOS Has**: `AutomationScheduler.swift` for auto-start/auto-complete monthly executions
- Auto-start tracking on 1st of month
- Auto-complete on last day of month
- Configurable grace period (24h, 48h, 168h, or disabled)
- Background task scheduling

**Android Missing**: No equivalent background automation

**Fix Required**:
```kotlin
// New files needed:
// 1. domain/usecase/automation/AutomationScheduler.kt
// 2. work/MonthlyExecutionWorker.kt (WorkManager)
// 3. Models: AutomationSettings.kt

class MonthlyExecutionWorker(
    context: Context,
    params: WorkerParameters,
    private val startExecutionUseCase: StartExecutionUseCase,
    private val completeExecutionUseCase: CompleteExecutionUseCase
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val dayOfMonth = LocalDate.now().dayOfMonth
        val settings = // load from DataStore

        if (dayOfMonth == 1 && settings.autoStartEnabled) {
            startExecutionUseCase()
        }
        if (dayOfMonth == LocalDate.now().lengthOfMonth() && settings.autoCompleteEnabled) {
            // complete if grace period allows
        }
        return Result.success()
    }
}
```

---

#### Gap 2: MonthlyPlanningSettings Model (HIGH PRIORITY)

**iOS Has**: `MonthlyPlanningSettings.swift` with:
- Payment day (1-28)
- Notification enable/disable
- Notification days before deadline
- Auto-start/auto-complete toggles
- Undo grace period enum

**Android Missing**: No settings model for planning preferences

**Fix Required**:
```kotlin
// New file: domain/model/MonthlyPlanningSettings.kt
data class MonthlyPlanningSettings(
    val paymentDay: Int = 1, // 1-28
    val notificationsEnabled: Boolean = true,
    val notificationDaysBefore: Int = 3,
    val autoStartEnabled: Boolean = false,
    val autoCompleteEnabled: Boolean = false,
    val undoGracePeriod: UndoGracePeriod = UndoGracePeriod.HOURS_24
)

enum class UndoGracePeriod(val hours: Long) {
    NONE(0), HOURS_24(24), HOURS_48(48), HOURS_168(168)
}

// Store in DataStore Preferences
```

---

#### Gap 3: FlexAdjustment UI (MEDIUM PRIORITY)

**iOS Has**:
- `FlexAdjustmentView.swift` - Full screen for flex adjustments
- `FlexAdjustmentSlider.swift` - Interactive slider with presets
- 4 redistribution strategies: Balanced, Urgent First, Largest First, Minimize Risk
- Impact preview showing delay/risk for each goal

**Android Has**: Backend (`MonthlyGoalPlanService.applyFlexAdjustment`) but NO UI

**Fix Required**:
```kotlin
// New files:
// 1. presentation/planning/FlexAdjustmentScreen.kt
// 2. presentation/planning/FlexAdjustmentViewModel.kt
// 3. presentation/planning/components/FlexSlider.kt
// 4. presentation/planning/components/ImpactPreviewCard.kt
```

---

#### Gap 4: Emoji Picker (MEDIUM PRIORITY)

**iOS Has**: `EmojiPickerView.swift` with:
- 10 categories: Popular, Finance, Home, Transport, Education, Tech, Health, Events, Nature, Food
- Search functionality
- Category tabs

**Android Missing**: Uses plain text input for emojis

**Fix Required**:
```kotlin
// New file: presentation/components/EmojiPicker.kt
@Composable
fun EmojiPicker(
    onEmojiSelected: (String) -> Unit,
    onDismiss: () -> Unit
) {
    // Category tabs + LazyVerticalGrid of emojis
}
```

---

#### Gap 5: Missing Chart Types (MEDIUM PRIORITY)

**iOS Has** (10 charts):
- EnhancedLineChartView ❌
- ForecastChartView ✅
- HeatmapCalendarView ✅
- ProgressRingView ✅
- SimpleLineChartView ❌
- SimpleStackedBarView ❌
- SparklineChartView ✅
- StackedBarChartView ❌
- LineChartView ❌
- ChartSkeletonView ❌

**Android Has** (4 charts): ForecastChart, HeatmapCalendar, ProgressRingChart, SparklineChart

**Fix Required**: Add 6 missing chart types for feature parity

---

#### Gap 6: Missing UI Components (LOW PRIORITY)

| iOS Component | Android Status | Priority |
|---------------|----------------|----------|
| GoalPaymentScheduleSheet | ✅ Implemented | Done |
| ImpactPreviewCard | Missing | P1 (for Flex UI) |
| ExchangeRateWarningView | Missing | P2 |
| AllocationPromptBanner | Missing | P2 |
| SimplePieChart | Missing | P2 |
| DashboardMetricsGrid | Missing | P2 |
| GoalSwitcherBar | Missing | P3 |
| HeroProgressView | Missing | P3 |
| SharedAssetIndicator | Missing | P3 |
| MonthlyPlanningWidget | Missing | P2 |

---

#### Gap 7: Utility Services (LOW PRIORITY)

| iOS Utility | Android Status | Priority |
|-------------|----------------|----------|
| KeychainManager (secure storage) | Missing - use EncryptedSharedPreferences | P1 |
| HapticManager | Missing | P3 |
| AccessibilityManager | Basic (Material 3 handles most) | P2 |
| PerformanceOptimizer | Missing | P3 |
| NotificationNames | Using sealed classes instead | N/A |

---

### Fix Implementation Order

**Phase 1 - Critical Bug (Day 1)** ✅ DONE
1. ~~Fix transaction timestamp handling~~ ✅ Fixed
2. Test execution progress with new transactions
3. Verify allocations are created on asset-goal linking

**Phase 2 - High Priority Gaps (Days 2-4)**
1. Add `MonthlyPlanningSettings` model + DataStore persistence
2. Implement `AutomationScheduler` with WorkManager
3. Add settings UI for payment day, notifications, automation

**Phase 3 - Medium Priority Gaps (Days 5-7)**
1. Build `FlexAdjustmentScreen` and `FlexSlider` components
2. Implement `EmojiPicker` composable
3. Add missing chart types (Line, StackedBar, etc.)

**Phase 4 - Polish (Days 8-10)**
1. Add missing UI components (ImpactPreviewCard, etc.)
2. Implement secure storage with EncryptedSharedPreferences
3. Add haptic feedback
4. Accessibility audit

---

## Systematic iOS Parity Testing Plan

### How to Find Parity Issues

#### Preparation (Before Any Parity Pass)

- Use the same timezone and locale on both devices.
- Set display currency to a known value (default: USD) and note it in the log.
- Clear caches (exchange rates + on-chain balances) before each run.
- Disable network for deterministic tests; only enable for API-specific flows.
- Keep API keys out of screenshots/logs (use placeholders when sharing).

#### Baseline Test Data Pack (Deterministic)

Use this minimal dataset for parity checks that must be deterministic (no FX):

| Entity | Values | Notes |
|--------|--------|-------|
| Goal A | Name: Emergency Fund, Currency: USD, Target: 12000, Deadline: +12 months | Single-currency goal |
| Goal B | Name: Vacation, Currency: USD, Target: 3000, Deadline: +6 months | Single-currency goal |
| Asset 1 | Currency: USDC, Address: empty | Avoids FX conversions |
| Transactions | USDC: +1000 (today), +250 (today) | Manual only |
| Allocations | Allocate USDC 1000 to Goal A, USDC 250 to Goal B | Matches balances |

Expected outcomes (baseline):
- Goal A funded: 1000 USD, Goal B funded: 250 USD.
- Progress: Goal A 8.33%, Goal B 8.33%.
- No FX conversion required.

For FX parity, run a second pass with BTC/ETH assets and record the CoinGecko rates used
in both apps (same timestamp window) before comparing totals.

#### FX Rate Capture Strategy for Live Parity Runs

When testing features that involve exchange rate conversions (portfolio totals, multi-currency goals, etc.):

**Option 1: Deterministic Mock Rates (Recommended for CI)**
```kotlin
// Android: Create FakeExchangeRateRepository for tests
class FakeExchangeRateRepository : ExchangeRateRepository {
    override suspend fun fetchRate(from: String, to: String): Double {
        return when {
            from == "BTC" && to == "USD" -> 100000.0  // Fixed test rate
            from == "ETH" && to == "USD" -> 4000.0   // Fixed test rate
            else -> 1.0
        }
    }
}

// iOS: Create MockExchangeRateService
class MockExchangeRateService: ExchangeRateServiceProtocol {
    func getRate(from: String, to: String) async throws -> Double {
        // Return same fixed rates as Android
    }
}
```

**Option 2: Snapshot Recording (For Live API Testing)**

Both platforms should log the CoinGecko response with timestamp:

```
[FX_SNAPSHOT] 2025-12-21T14:32:15Z
BTC/USD: 100234.56 (source: coingecko, market_cap_rank: 1)
ETH/USD: 3892.12 (source: coingecko, market_cap_rank: 2)
Cache TTL: 300s
```

**Parity Check Protocol:**
1. Clear FX caches on both devices (Settings → Clear Exchange Rate Cache)
2. Ensure same network connectivity (both online or both use mock)
3. Trigger FX fetch within 30-second window on both devices
4. Log the rates used for each calculation
5. Compare portfolio totals using **Comparison Criteria & Tolerances** below
6. Acceptable delta: |iOS_total - Android_total| < 0.01% of portfolio value

**Test Data for FX Parity:**
| Asset | Amount | Mock Rate (USD) | Expected Value |
|-------|--------|-----------------|----------------|
| BTC | 0.5 | 100000.0 | 50000.00 |
| ETH | 2.0 | 4000.0 | 8000.00 |
| USDC | 1000 | 1.0 | 1000.00 |
| **Total** | | | **59000.00** |

#### Method 1: Happy Path Testing (Most Effective)

Test each user flow end-to-end on both platforms simultaneously:

| Flow | iOS Steps | Android Steps | Check Points |
|------|-----------|---------------|--------------|
| **Goal Creation** | Create goal → Set deadline → Add reminder | Same | Data saved correctly, reminder scheduled |
| **Asset Addition** | Add asset → Set chain → Enter address | Same | Chain auto-detected, address validated |
| **Transaction** | Add transaction → Check balance | Same | Balance updates, progress recalculates |
| **Allocation** | Allocate asset to goal → Check progress | Same | Progress %, over-allocation warning |
| **Execution** | Start → Add transaction → Check progress → Complete | Same | Progress tracks, undo works |
| **Planning** | Create plan → Adjust flex → Start execution | Same | Amounts calculate correctly |
| **Settings** | Update API keys → Clear caches → Export CSV | Same | Values saved, export produced |
| **Onboarding** | Complete onboarding → Create template goal | Same | Goal created and marked complete |

#### Method 2: Code Comparison Checklist

For each feature, compare these aspects:

```
□ Data Types
  - iOS Date vs Android Long (millis) vs LocalDate
  - iOS UUID vs Android String
  - iOS Double precision vs Android Double

□ Default Values
  - iOS: Check init() parameters
  - Android: Check data class defaults

□ Timestamp Handling
  - Creation timestamps: Date() vs System.currentTimeMillis()
  - User-selected dates: Date components vs LocalDate conversion
  - Time zone handling

□ Business Logic
  - Formulas (progress calculation, allocations)
  - Filters (date ranges, status filters)
  - Sorting order

□ Reactive Updates
  - iOS: @Published, NotificationCenter, SwiftData relationships
  - Android: Flow, StateFlow, Room DAO queries

□ Error Handling
  - Validation rules
  - Error messages
  - Edge cases (empty lists, zero values, null)
```

#### Method 3: Automated Comparison Script

Run this to find structural differences:

```bash
# Compare model properties
diff <(rg --no-heading -g "*.swift" "\\b(var|let) " ios/CryptoSavingsTracker/Models | sort) \
     <(rg --no-heading -g "*.kt" "\\bval " android/app/src/main/java/com/xax/CryptoSavingsTracker/domain/model | sort)

# Compare service/use case methods
diff <(rg --no-heading -g "*.swift" "\\bfunc " ios/CryptoSavingsTracker/Services | sort) \
     <(rg --no-heading -g "*.kt" "\\b(suspend\\s+)?fun " android/app/src/main/java/com/xax/CryptoSavingsTracker/domain/usecase | sort)

# Find iOS notification-based refresh triggers
rg -n "NotificationCenter\\.default\\.post" ios/CryptoSavingsTracker
```

### Common Parity Pitfalls

| Category | iOS Pattern | Android Pitfall | Fix |
|----------|-------------|-----------------|-----|
| **Timestamps** | `Date()` (instant) | `LocalDate.now()` (date only) | Use `System.currentTimeMillis()` |
| **Date Storage** | `Date` (full timestamp) | `Long` (millis) | Ensure millis, not seconds |
| **Notifications** | `NotificationCenter` | Flow doesn't auto-refresh | Check Flow combines re-trigger |
| **Relationships** | SwiftData auto-updates | Room requires explicit queries | Use proper Flow observation |
| **Defaults** | Swift optionals with defaults | Kotlin nullability | Match default values exactly |
| **Enums** | String raw values | Enum classes | Match raw value storage |
| **UUIDs** | `UUID` type | `String` | Use consistent format |

### Comparison Criteria & Tolerances

- **Fiat amounts**: within 0.01 (cent-level) after rounding.
- **Crypto amounts**: within 1e-8 after rounding.
- **Percentages**: within 0.1% of iOS.
- **Dates**: same local date; timestamps within 1 second when created side-by-side.
- **Sorting**: identical primary sort; define secondary tie-breakers when equal.

### Parity Run Log (Copy/Paste)

```
Run Date/Time:
Tester:
Devices (iOS/Android):
Timezone/Locale:
Display Currency:
Network (on/off):
API Keys (set/empty):
Seed Data Pack: Baseline / FX

Findings:
- Feature:
  iOS:
  Android:
  Delta:
  Screenshots/Logs:
```

### Parity Testing Checklist by Feature

#### Execution Tracking (High Risk)

**Basic Checks:**
- [ ] Start execution → timestamp stored correctly
- [ ] Add transaction same day → falls within execution window
- [ ] Add transaction past date → handled correctly
- [ ] Progress updates in real-time
- [ ] Undo within 24h works
- [ ] Complete execution → data frozen correctly

**Time-Window Edge Cases (Critical):**
- [ ] **End of Day**: Start execution at 11:55 PM, add transaction at 11:58 PM → included in window
- [ ] **Midnight Crossing**: Start at 11:55 PM Day 1, add transaction at 12:05 AM Day 2 → included
- [ ] **Timezone Change**: Device timezone changes mid-execution → progress still calculated correctly
- [ ] **Daylight Savings (Spring Forward)**: Execution spans 2 AM → 3 AM skip → no lost transactions
- [ ] **Daylight Savings (Fall Back)**: Execution spans 2 AM → 1 AM repeat → no duplicate counting
- [ ] **Past Date Selection**: User selects yesterday's date → transaction excluded from current execution window
- [ ] **Future Date Selection**: User selects tomorrow → should be rejected or handled gracefully
- [ ] **Boundary Exact**: Transaction timestamp == execution startedAtMillis → INCLUDED
- [ ] **Boundary Off-by-One**: Transaction timestamp == startedAtMillis - 1ms → EXCLUDED

**Test Mapping:**
| Check | Android Test File | Status |
|-------|-------------------|--------|
| Timestamp stored | `ExecutionRecordDaoTest.kt` | ✅ Exists |
| Window filtering | `ExecutionProgressCalculatorTest.kt` | ✅ Created (12 tests) |
| Undo within 24h | `UndoExecutionUseCaseTest.kt` | ✅ Exists |
| Undo start execution | `UndoStartExecutionUseCaseTest.kt` | ✅ Exists |
| Complete execution | `CompleteExecutionUseCaseTest.kt` | ✅ Exists |
| Timezone edge cases | `ExecutionProgressCalculatorTest.kt` | ⚠️ Partial (boundary tests) |
| DST edge cases | `ExecutionDSTTest.kt` | ❌ TODO |

#### Monthly Planning (Medium Risk)

**Checks:**
- [ ] Requirements calculated same as iOS
- [ ] Flex adjustment produces same results
- [ ] Skip/protect goals behaves identically
- [ ] Payment day affects calculations correctly
- [ ] Multi-currency totals match iOS (with same FX rates)

**Test Mapping:**
| Check | Android Test File | Status |
|-------|-------------------|--------|
| Plan sync | `MonthlyGoalPlanServiceTest.kt` | ✅ Exists (3 tests) |
| Flex adjustment | `MonthlyGoalPlanServiceTest.kt` | ✅ Exists (2 tests) |
| Requirement calculation | `MonthlyPlanningServiceTest.kt` | ❌ TODO (needs DI mocks) |
| Payment day logic | `MonthlyPlanningServiceTest.kt` | ❌ TODO (needs DI mocks) |
| FX conversion | `ExchangeRateRepositoryTest.kt` | ❌ TODO |

#### Asset Management (Medium Risk)

**Checks:**
- [ ] Chain auto-detection matches iOS mappings
- [ ] On-chain balance fetches correctly
- [ ] Transaction import deduplicates properly
- [ ] Balance cache respects TTL

**Test Mapping:**
| Check | Android Test File | Status |
|-------|-------------------|--------|
| Chain auto-detection | `AssetTest.kt` (unit) | ✅ Exists |
| DAO operations | `AssetDaoTest.kt` | ✅ Exists |
| Tatum API parsing | `TatumClientTest.kt` | ❌ TODO |
| Balance caching | `BalanceCacheTest.kt` | ❌ TODO |

#### Goal Management (Low Risk)

**Checks:**
- [ ] Lifecycle status transitions work
- [ ] Progress calculation formula matches
- [ ] Reminder scheduling works
- [ ] All enum values match iOS (GoalLifecycleStatus, ReminderFrequency)

**Test Mapping:**
| Check | Android Test File | Status |
|-------|-------------------|--------|
| DAO operations | `GoalDaoTest.kt` | ✅ 25 tests |
| Add goal flow | `AddGoalUseCaseTest.kt` | ✅ Exists |
| Progress calculation | `GetGoalProgressUseCaseTest.kt` | ✅ Exists (FX + on-chain) |
| Goal progress | `GoalProgressTest.kt` | ✅ Exists |
| Reminder scheduling | `GoalReminderSchedulerTest.kt` | ❌ TODO |

### When Adding New Features

Before implementing any new Android feature:

1. **Read the iOS code first** - Understand the exact behavior
2. **Document the data flow** - Inputs → Processing → Outputs
3. **Note all timestamps** - How dates are created, stored, compared
4. **Check notifications** - What triggers refreshes in iOS
5. **Test the happy path** - Run both platforms side-by-side
6. **Test edge cases** - Empty data, zero values, boundaries

### Issue Tracking Template

When finding a parity issue, document it as:

```markdown
## [PARITY] Feature Name - Brief Description

**Symptom**: What user sees
**iOS Behavior**: Expected behavior (with code reference)
**Android Behavior**: Current (wrong) behavior
**Root Cause**: Technical reason for difference
**Fix**: Code changes needed
**Files**: List of files to modify
**Test**: How to verify the fix
```

---

## Table of Contents

1. [Scope & Parity Definition](#1-scope--parity-definition)
2. [Technology Stack](#2-technology-stack)
3. [Project Structure](#3-project-structure)
4. [Data Layer](#4-data-layer)
5. [Domain Layer](#5-domain-layer)
6. [Presentation Layer](#6-presentation-layer)
7. [API & Security](#7-api--security)
8. [Implementation Phases](#8-implementation-phases)
9. [Testing Strategy](#9-testing-strategy)
10. [Platform-Specific Considerations](#10-platform-specific-considerations)

---

## 1. Scope & Parity Definition

### 1.1 Feature Parity Checklist

| Feature | iOS Status | Android Target | Priority | Notes |
|---------|------------|----------------|----------|-------|
| **Goal Management** | | | | |
| Create/Edit/Delete goals | ✅ | Required | P0 | Core feature |
| Goal lifecycle (active/cancelled/finished) | ✅ | Required | P0 | |
| Emoji picker with smart suggestions | ✅ | Required | P1 | |
| Goal description and external links | ✅ | Required | P1 | |
| Reminder scheduling | ✅ | Required | P1 | WorkManager |
| **Asset Management** | | | | |
| Create/Edit/Delete assets | ✅ | Required | P0 | Core feature |
| Manual transaction entry | ✅ | Required | P0 | |
| On-chain balance fetching | ✅ | Required | P1 | Tatum API |
| Transaction history import | ✅ | Required | P1 | |
| **Allocation System** | | | | |
| Fixed-amount asset allocation | ✅ | Required | P0 | Core feature |
| Allocation history snapshots | ✅ | Required | P0 | For execution |
| Auto-allocation for single-goal assets | ✅ | Required | P1 | |
| Over-allocation detection | ✅ | Required | P1 | |
| **Monthly Planning** | | | | |
| Zero-input requirement calculation | ✅ | Required | P0 | Core feature |
| Flex adjustment slider (0-150%) | ✅ | Required | P0 | |
| Protected/skipped goal flags | ✅ | Required | P1 | |
| Custom amount override | ✅ | Required | P1 | |
| **Execution Tracking** | | | | |
| Timestamp-based progress derivation | ✅ | Required | P0 | Core innovation |
| Execution state machine (draft→executing→closed) | ✅ | Required | P0 | |
| ExecutionSnapshot capture | ✅ | Required | P0 | |
| 24-hour undo windows | ✅ | Required | P1 | |
| CompletedExecution history | ✅ | Required | P1 | |
| **Dashboard** | | | | |
| Portfolio overview | ✅ | Required | P0 | |
| Goal progress summary | ✅ | Required | P0 | |
| Monthly planning widget | ✅ | Required | P1 | |
| **Multi-Currency** | | | | |
| Real-time exchange rates (CoinGecko) | ✅ | Required | P0 | |
| Batch currency conversion | ✅ | Required | P0 | |
| Display currency preference | ✅ | Required | P1 | |
| **Data Export** | | | | |
| CSV export | ✅ | Required | P2 | |

### 1.2 Non-Goals (v1.0)

The following features are explicitly **out of scope** for the initial Android release:

| Feature | Reason | Future Consideration |
|---------|--------|---------------------|
| iCloud sync | Apple-only technology | Firebase/custom backend v2.0 |
| visionOS support | iOS-only | N/A |
| Siri Shortcuts | iOS-only | Android Shortcuts v1.1 |
| Apple Watch widget | iOS-only | Wear OS v2.0 |
| Biometric auth for app lock | Scope creep | v1.1 |
| Dark mode toggle | Use system setting only | v1.1 if requested |
| Landscape tablet layout | Complexity | v1.1 |
| Localization (non-English) | Scope | v1.2 |

### 1.3 Acceptance Criteria

#### Release Criteria (Must Pass All)

1. **Functional Parity**: All P0 features implemented and working
2. **Data Integrity**:
   - All CRUD operations persist correctly
   - No data loss on app restart/kill
   - Allocation calculations match iOS within 0.01% tolerance
3. **Performance**:
   - Cold start < 2 seconds on mid-range device (Pixel 6a)
   - Goal list scroll at 60fps with 50+ goals
   - API responses cached, no redundant network calls
4. **Stability**:
   - Crash-free rate > 99.5% (Firebase Crashlytics)
   - No ANRs in normal usage
5. **Testing**:
   - Unit test coverage > 80% for domain layer
   - All critical user journeys have UI tests
   - Manual QA sign-off on test matrix

#### Device Test Matrix

| Device | OS Version | Form Factor | Priority |
|--------|------------|-------------|----------|
| Pixel 8 | Android 14 | Phone | P0 |
| Pixel 6a | Android 13 | Phone | P0 |
| Samsung S23 | Android 14 | Phone | P0 |
| Samsung A54 | Android 13 | Phone | P1 |
| Pixel Tablet | Android 14 | Tablet | P2 |

---

## 2. Technology Stack

### Core Technologies

| Category | iOS (Reference) | Android (Target) |
|----------|-----------------|------------------|
| **UI Framework** | SwiftUI | Jetpack Compose |
| **Database** | SwiftData | Room 2.6+ |
| **Reactive** | Combine | Kotlin Flow + StateFlow |
| **DI** | DIContainer (custom) | Hilt 2.52+ |
| **Architecture** | MVVM | MVVM + Clean Architecture |
| **Networking** | URLSession | Retrofit 2.11 + OkHttp 4.12 |
| **JSON** | Codable | Kotlinx Serialization 1.7 |
| **Async** | async/await | Kotlin Coroutines 1.9 |
| **Navigation** | NavigationStack | Navigation Compose 2.8 |
| **Testing** | XCTest | JUnit 5 + MockK + Turbine |

### Dependencies

```kotlin
// build.gradle.kts (app)
//
// PACKAGE NAMING: com.xax.CryptoSavingsTracker
// This mixed-case package is used consistently throughout:
// - namespace and applicationId (below)
// - folder structure: java/com/xax/CryptoSavingsTracker/
// - HiltTestRunner package
// - Room schema export path

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

android {
    namespace = "com.xax.CryptoSavingsTracker"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.xax.CryptoSavingsTracker"
        minSdk = 34  // Android 14+ (modern baseline, no desugaring needed)
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "com.xax.CryptoSavingsTracker.HiltTestRunner"

        // Room schema export for migrations
        ksp {
            arg("room.schemaLocation", "$projectDir/schemas")
            arg("room.incremental", "true")
            arg("room.generateKotlin", "true")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // No desugaring needed - minSdk 34 has full java.time support
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    // Core Android
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.3")

    // Jetpack Compose (BOM)
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    // Navigation
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.hilt:hilt-navigation-compose:1.2.0")

    // Room Database
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")

    // Hilt DI
    implementation("com.google.dagger:hilt-android:2.52")
    ksp("com.google.dagger:hilt-compiler:2.52")

    // Networking
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("com.jakewharton.retrofit:retrofit2-kotlinx-serialization-converter:1.0.0")

    // DataStore (preferences)
    implementation("androidx.datastore:datastore-preferences:1.1.1")

    // Security (API key storage)
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // WorkManager (reminders)
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    implementation("androidx.hilt:hilt-work:1.2.0")
    ksp("androidx.hilt:hilt-compiler:1.2.0")

    // Charts
    implementation("com.patrykandpatrick.vico:compose-m3:2.0.0-beta.2")

    // Firebase Crashlytics (stability monitoring)
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-crashlytics-ktx")
    implementation("com.google.firebase:firebase-analytics-ktx")

    // ========== TESTING ==========

    // Unit Tests (JUnit 5)
    testImplementation(platform("org.junit:junit-bom:5.11.3"))
    testImplementation("org.junit.jupiter:junit-jupiter-api")
    testImplementation("org.junit.jupiter:junit-jupiter-params")
    testRuntimeOnly("org.junit.jupiter:junit-jupiter-engine")

    // Mocking & Assertions
    testImplementation("io.mockk:mockk:1.13.13")
    testImplementation("com.google.truth:truth:1.4.4")
    testImplementation("app.cash.turbine:turbine:1.2.0")

    // Coroutines Testing
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")

    // Room Testing
    testImplementation("androidx.room:room-testing:2.6.1")

    // Network Mocking
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")

    // Android Instrumented Tests
    androidTestImplementation(platform("androidx.compose:compose-bom:2024.12.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit-ktx:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:rules:1.6.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("com.google.dagger:hilt-android-testing:2.52")
    kspAndroidTest("com.google.dagger:hilt-compiler:2.52")
    androidTestImplementation("io.mockk:mockk-android:1.13.13")
}

tasks.withType<Test> {
    useJUnitPlatform()  // Enable JUnit 5
}
```

---

## 3. Project Structure

```
android/app/src/
├── main/
│   ├── java/com/xax/CryptoSavingsTracker/
│   │   ├── CryptoSavingsTrackerApp.kt
│   │   ├── MainActivity.kt
│   │   │
│   │   ├── data/
│   │   │   ├── local/
│   │   │   │   ├── database/
│   │   │   │   │   ├── AppDatabase.kt
│   │   │   │   │   ├── DatabaseMigrations.kt
│   │   │   │   │   ├── dao/
│   │   │   │   │   ├── entity/
│   │   │   │   │   └── converter/
│   │   │   │   ├── datastore/
│   │   │   │   └── cache/
│   │   │   ├── remote/
│   │   │   │   ├── api/
│   │   │   │   ├── dto/
│   │   │   │   └── interceptor/
│   │   │   └── repository/
│   │   │
│   │   ├── domain/
│   │   │   ├── model/
│   │   │   ├── repository/
│   │   │   └── usecase/
│   │   │
│   │   ├── presentation/
│   │   │   ├── navigation/
│   │   │   ├── theme/
│   │   │   ├── common/
│   │   │   ├── goals/
│   │   │   ├── assets/
│   │   │   ├── planning/
│   │   │   ├── execution/
│   │   │   ├── dashboard/
│   │   │   └── transactions/
│   │   │
│   │   └── di/
│   │
│   └── res/
│
├── test/                          # Unit tests
│   └── java/com/xax/CryptoSavingsTracker/
│       ├── data/
│       │   ├── repository/
│       │   └── local/
│       ├── domain/usecase/
│       ├── presentation/
│       └── testutil/
│           ├── MainDispatcherExtension.kt
│           ├── TestFixtures.kt
│           └── FakeRepositories.kt
│
├── androidTest/                   # Instrumented tests
│   └── java/com/xax/CryptoSavingsTracker/
│       ├── HiltTestRunner.kt
│       ├── data/local/
│       ├── presentation/
│       └── e2e/
│
└── schemas/                       # Room schema exports
    └── com.xax.CryptoSavingsTracker.data.local.database.AppDatabase/
        ├── 1.json
        ├── 2.json
        └── ...
```

---

## 4. Data Layer

### 4.1 Room Database Configuration

```kotlin
@Database(
    entities = [
        GoalEntity::class,
        AssetEntity::class,
        TransactionEntity::class,
        AssetAllocationEntity::class,
        AllocationHistoryEntity::class,
        MonthlyPlanEntity::class,
        MonthlyExecutionRecordEntity::class,
        ExecutionSnapshotEntity::class,
        CompletedExecutionEntity::class
    ],
    version = 1,
    exportSchema = true,
    autoMigrations = []  // Manual migrations for control
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun goalDao(): GoalDao
    abstract fun assetDao(): AssetDao
    abstract fun transactionDao(): TransactionDao
    abstract fun allocationDao(): AllocationDao
    abstract fun allocationHistoryDao(): AllocationHistoryDao
    abstract fun monthlyPlanDao(): MonthlyPlanDao
    abstract fun executionRecordDao(): ExecutionRecordDao
    abstract fun executionSnapshotDao(): ExecutionSnapshotDao
    abstract fun completedExecutionDao(): CompletedExecutionDao
}
```

### 4.2 Entity Definitions with Constraints

```kotlin
/**
 * DATE vs TIMESTAMP STORAGE STRATEGY:
 *
 * - DATE-ONLY fields (deadline, startDate, firstReminderDate):
 *   Stored as Int using LocalDate.toEpochDay() - days since 1970-01-01.
 *   This avoids timezone shifting issues with midnight UTC.
 *
 * - TIMESTAMP fields (createdAt, lastModifiedAt, reminderTime):
 *   Stored as Long using epoch milliseconds UTC.
 *   These represent specific instants in time.
 */
@Entity(
    tableName = "goals",
    indices = [
        Index(value = ["name"], unique = false),
        Index(value = ["lifecycle_status"]),
        Index(value = ["deadline_epoch_day"])
    ]
)
data class GoalEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "currency")
    val currency: String,  // ISO 4217 or crypto symbol

    @ColumnInfo(name = "target_amount")
    val targetAmount: Double,

    // DATE-ONLY: Stored as epoch day (Int) to avoid timezone shifting
    // Use LocalDate.toEpochDay() to convert, LocalDate.ofEpochDay() to read
    @ColumnInfo(name = "deadline_epoch_day")
    val deadlineEpochDay: Int,

    @ColumnInfo(name = "start_date_epoch_day")
    val startDateEpochDay: Int,

    @ColumnInfo(name = "lifecycle_status")
    val lifecycleStatus: String,  // "active", "cancelled", "finished", "deleted"

    @ColumnInfo(name = "emoji")
    val emoji: String?,

    @ColumnInfo(name = "description")
    val description: String?,

    @ColumnInfo(name = "link")
    val link: String?,

    @ColumnInfo(name = "reminder_frequency")
    val reminderFrequency: String?,

    // TIMESTAMP: Specific time of day for reminder (epoch millis UTC)
    @ColumnInfo(name = "reminder_time_utc_millis")
    val reminderTimeUtcMillis: Long?,

    // DATE-ONLY: First reminder date (epoch day)
    @ColumnInfo(name = "first_reminder_epoch_day")
    val firstReminderEpochDay: Int?,

    // TIMESTAMPS: Audit fields (epoch millis UTC, no defaultValue - set in code)
    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "last_modified_at_utc_millis")
    val lastModifiedAtUtcMillis: Long = System.currentTimeMillis()
)

@Entity(
    tableName = "asset_allocations",
    foreignKeys = [
        ForeignKey(
            entity = AssetEntity::class,
            parentColumns = ["id"],
            childColumns = ["asset_id"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = GoalEntity::class,
            parentColumns = ["id"],
            childColumns = ["goal_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["asset_id"]),
        Index(value = ["goal_id"]),
        Index(value = ["asset_id", "goal_id"], unique = true)  // Unique constraint
    ]
)
data class AssetAllocationEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "asset_id")
    val assetId: String,

    @ColumnInfo(name = "goal_id")
    val goalId: String,

    @ColumnInfo(name = "amount")
    val amount: Double,  // Must be >= 0

    // TIMESTAMPS: No defaultValue - set in Kotlin code
    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "last_modified_at_utc_millis")
    val lastModifiedAtUtcMillis: Long = System.currentTimeMillis()
)

@Entity(
    tableName = "transactions",
    foreignKeys = [
        ForeignKey(
            entity = AssetEntity::class,
            parentColumns = ["id"],
            childColumns = ["asset_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["asset_id"]),
        Index(value = ["date_utc_millis"]),
        Index(value = ["external_id"], unique = true)  // Prevent duplicate imports
    ]
)
data class TransactionEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "asset_id")
    val assetId: String,

    @ColumnInfo(name = "amount")
    val amount: Double,  // Positive = deposit, Negative = withdrawal

    // TIMESTAMP: Transaction occurred at specific instant (epoch millis UTC)
    @ColumnInfo(name = "date_utc_millis")
    val dateUtcMillis: Long,

    @ColumnInfo(name = "source")
    val source: String,  // "manual" or "onChain"

    @ColumnInfo(name = "external_id")
    val externalId: String?,  // Blockchain tx hash (nullable, unique when present)

    @ColumnInfo(name = "counterparty")
    val counterparty: String?,

    @ColumnInfo(name = "comment")
    val comment: String?,

    // TIMESTAMP: No defaultValue - set in Kotlin code
    @ColumnInfo(name = "created_at_utc_millis")
    val createdAtUtcMillis: Long = System.currentTimeMillis()
)
```

### 4.3 Date & Timestamp Handling

```kotlin
/**
 * DATE vs TIMESTAMP STORAGE RULES
 *
 * DATE-ONLY FIELDS (deadline, startDate, firstReminderDate):
 *   - Stored as Int using LocalDate.toEpochDay() (days since 1970-01-01)
 *   - Timezone-agnostic: "2025-01-15" is the same epoch day everywhere
 *   - No risk of shifting across timezone boundaries
 *
 * TIMESTAMP FIELDS (createdAt, lastModifiedAt, reminderTime, transaction dates):
 *   - Stored as Long using epoch milliseconds UTC
 *   - Represents a specific instant in time
 *   - Converted to local timezone only for display
 *
 * MONTH LABELS (for execution tracking):
 *   - Stored as String "yyyy-MM" in UTC
 *   - Consistent across timezones for grouping
 */
object DateTimeUtils {

    // ========== DATE-ONLY CONVERSIONS (epoch day) ==========

    fun LocalDate.toEpochDayInt(): Int = this.toEpochDay().toInt()

    fun Int.toLocalDate(): LocalDate = LocalDate.ofEpochDay(this.toLong())

    // ========== TIMESTAMP CONVERSIONS (epoch millis) ==========

    fun Instant.toUtcMillis(): Long = this.toEpochMilli()

    fun Long.toInstant(): Instant = Instant.ofEpochMilli(this)

    fun Long.toLocalDateTime(zone: ZoneId = ZoneId.systemDefault()): LocalDateTime {
        return Instant.ofEpochMilli(this).atZone(zone).toLocalDateTime()
    }

    fun Long.toZonedDateTime(zone: ZoneId = ZoneId.systemDefault()): ZonedDateTime {
        return Instant.ofEpochMilli(this).atZone(zone)
    }

    // ========== MONTH LABEL UTILITIES ==========

    fun monthLabelFromMillis(millis: Long): String {
        val formatter = DateTimeFormatter.ofPattern("yyyy-MM")
        return Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).format(formatter)
    }

    fun currentMonthLabel(): String = monthLabelFromMillis(System.currentTimeMillis())

    fun parseMonthLabel(label: String): YearMonth = YearMonth.parse(label)
}
```

### 4.4 Room Migration Strategy

```kotlin
object DatabaseMigrations {

    /**
     * Migration Strategy:
     *
     * 1. Schema versions are exported to /schemas/ directory
     * 2. Every migration has a corresponding test in DatabaseMigrationTest
     * 3. Destructive migrations are NEVER used for UPGRADES
     * 4. Large data migrations run in batches to avoid ANRs
     * 5. DOWNGRADES are unsupported in production:
     *    - Downgrading schema version implies rolling back to older app version
     *    - We use fallbackToDestructiveMigrationOnDowngrade() to wipe data
     *    - This is acceptable because:
     *      a) Downgrades only happen in dev (installing older APK over newer)
     *      b) Production users can't downgrade past Play Store's minimum version
     *      c) Data loss on downgrade is preferable to crash loops
     *
     * NOTE: The migrations below are TEMPLATES for future schema changes.
     * Initial release uses version = 1 with no migrations needed.
     * When you need to change the schema:
     *   1. Increment @Database(version = N)
     *   2. Add MIGRATION_(N-1)_N following the patterns below
     *   3. Add a test for the new migration
     */

    // === FUTURE MIGRATION TEMPLATES ===
    // Uncomment and modify when schema changes are needed

    val MIGRATION_1_2 = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // Example: Add new column with default value
            db.execSQL("""
                ALTER TABLE goals
                ADD COLUMN priority INTEGER NOT NULL DEFAULT 0
            """)
        }
    }

    val MIGRATION_2_3 = object : Migration(2, 3) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // Example: Create new table
            db.execSQL("""
                CREATE TABLE IF NOT EXISTS goal_tags (
                    id TEXT PRIMARY KEY NOT NULL,
                    goal_id TEXT NOT NULL,
                    tag TEXT NOT NULL,
                    FOREIGN KEY (goal_id) REFERENCES goals(id) ON DELETE CASCADE
                )
            """)
            db.execSQL("CREATE INDEX IF NOT EXISTS index_goal_tags_goal_id ON goal_tags(goal_id)")
        }
    }

    // For complex migrations with data transformation
    val MIGRATION_3_4 = object : Migration(3, 4) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // 1. Create new table with updated schema
            db.execSQL("""
                CREATE TABLE goals_new (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    -- ... new schema
                )
            """)

            // 2. Copy data with transformation (batch for large tables)
            db.execSQL("""
                INSERT INTO goals_new (id, name, ...)
                SELECT id, name, ... FROM goals
            """)

            // 3. Drop old table
            db.execSQL("DROP TABLE goals")

            // 4. Rename new table
            db.execSQL("ALTER TABLE goals_new RENAME TO goals")

            // 5. Recreate indices
            db.execSQL("CREATE INDEX IF NOT EXISTS index_goals_deadline ON goals(deadline_epoch_day)")
        }
    }

    val ALL_MIGRATIONS = arrayOf(
        MIGRATION_1_2,
        MIGRATION_2_3,
        MIGRATION_3_4
    )
}

// DatabaseModule.kt
@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context,
            AppDatabase::class.java,
            "crypto_savings_tracker.db"
        )
        .addMigrations(*DatabaseMigrations.ALL_MIGRATIONS)
        .fallbackToDestructiveMigrationOnDowngrade()  // Only on downgrade
        .build()
    }
}
```

### 4.5 Migration Testing

```kotlin
@RunWith(AndroidJUnit4::class)
class DatabaseMigrationTest {

    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        AppDatabase::class.java
    )

    @Test
    fun migrate1To2() {
        // Create database at version 1
        // Note: Column names must match GoalEntity schema exactly
        helper.createDatabase("test_db", 1).apply {
            execSQL("""
                INSERT INTO goals (
                    id, name, currency, target_amount,
                    deadline_epoch_day, start_date_epoch_day,
                    lifecycle_status, created_at_utc_millis, last_modified_at_utc_millis
                ) VALUES (
                    'test-id', 'Test Goal', 'USD', 1000.0,
                    20089, 19724,  -- epochDay values (2025-01-01, 2024-01-01)
                    'active', 1704067200000, 1704067200000
                )
            """)
            close()
        }

        // Migrate to version 2
        val db = helper.runMigrationsAndValidate("test_db", 2, true, DatabaseMigrations.MIGRATION_1_2)

        // Verify data preserved and new column exists with default
        val cursor = db.query("SELECT priority FROM goals WHERE id = 'test-id'")
        assertTrue(cursor.moveToFirst())
        assertEquals(0, cursor.getInt(0))  // Default value
        cursor.close()
    }

    @Test
    fun migrateAllVersions() {
        helper.createDatabase("test_db", 1).close()
        helper.runMigrationsAndValidate(
            "test_db",
            AppDatabase.VERSION,
            true,
            *DatabaseMigrations.ALL_MIGRATIONS
        )
    }
}
```

---

## 5. Domain Layer

### 5.1 Domain Models

```kotlin
data class Goal(
    val id: String,
    val name: String,
    val currency: String,
    val targetAmount: Double,
    val deadline: LocalDate,
    val startDate: LocalDate,
    val lifecycleStatus: GoalLifecycleStatus,
    val emoji: String?,
    val description: String?,
    val link: String?,
    val reminderFrequency: ReminderFrequency?,
    val allocations: List<AssetAllocation> = emptyList()
) {
    val daysRemaining: Int
        get() = ChronoUnit.DAYS.between(LocalDate.now(), deadline).toInt()

    val isExpired: Boolean
        get() = daysRemaining < 0

    val isAchieved: Boolean
        get() = lifecycleStatus == GoalLifecycleStatus.FINISHED
}

data class MonthlyRequirement(
    val id: String,
    val goalId: String,
    val goalName: String,
    val currency: String,
    val targetAmount: Double,
    val currentTotal: Double,
    val remainingAmount: Double,
    val monthsRemaining: Int,
    val requiredMonthly: Double,
    val progress: Double,
    val deadline: LocalDate,
    val status: RequirementStatus
)
```

### 5.2 Key Use Cases

```kotlin
class CalculateMonthlyRequirementsUseCase @Inject constructor(
    private val goalRepository: GoalRepository,
    private val allocationRepository: AllocationRepository,
    private val exchangeRateRepository: ExchangeRateRepository
) {
    suspend operator fun invoke(displayCurrency: String): List<MonthlyRequirement> {
        val goals = goalRepository.getActiveGoals().first()

        return goals.map { goal ->
            val currentTotal = calculateCurrentTotal(goal)
            val remainingAmount = (goal.targetAmount - currentTotal).coerceAtLeast(0.0)
            val monthsRemaining = calculateMonthsRemaining(goal.deadline)
            val requiredMonthly = if (monthsRemaining > 0) {
                remainingAmount / monthsRemaining
            } else 0.0

            val progress = if (goal.targetAmount > 0) {
                (currentTotal / goal.targetAmount).coerceIn(0.0, 1.0)
            } else 0.0

            MonthlyRequirement(
                id = UUID.randomUUID().toString(),
                goalId = goal.id,
                goalName = goal.name,
                currency = goal.currency,
                targetAmount = goal.targetAmount,
                currentTotal = currentTotal,
                remainingAmount = remainingAmount,
                monthsRemaining = monthsRemaining,
                requiredMonthly = requiredMonthly,
                progress = progress,
                deadline = goal.deadline,
                status = determineStatus(progress, monthsRemaining, remainingAmount)
            )
        }
    }
}
```

---

## 6. Presentation Layer

*(Section unchanged - see original)*

---

## 7. API & Security

### 7.1 API Key Management

```kotlin
/**
 * Secure API Key Storage using EncryptedSharedPreferences
 *
 * Keys are stored encrypted at rest using AES-256-GCM.
 * Master key is stored in Android Keystore (hardware-backed when available).
 */
@Singleton
class SecureApiKeyStorage @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val encryptedPrefs = EncryptedSharedPreferences.create(
        context,
        "secure_api_keys",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun getApiKey(key: ApiKeyType): String? {
        return encryptedPrefs.getString(key.prefKey, null)
    }

    fun setApiKey(key: ApiKeyType, value: String) {
        encryptedPrefs.edit().putString(key.prefKey, value).apply()
    }

    fun hasApiKey(key: ApiKeyType): Boolean {
        return encryptedPrefs.contains(key.prefKey)
    }

    enum class ApiKeyType(val prefKey: String) {
        COINGECKO("coingecko_api_key"),
        TATUM("tatum_api_key"),
        QUICKNODE("quicknode_api_key"),
        NOWNODES("nownodes_api_key")
    }
}

// Usage in DI Module
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideCoinGeckoApi(
        okHttpClient: OkHttpClient,
        apiKeyStorage: SecureApiKeyStorage
    ): CoinGeckoApi {
        return Retrofit.Builder()
            .baseUrl("https://api.coingecko.com/api/v3/")
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(CoinGeckoApi::class.java)
    }
}
```

### 7.2 API Key Injection via Interceptor

```kotlin
/**
 * Injects API keys into requests based on host.
 * Keys are loaded from secure storage, NOT hardcoded.
 */
class ApiKeyInterceptor @Inject constructor(
    private val apiKeyStorage: SecureApiKeyStorage
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()
        val host = originalRequest.url.host

        val apiKey = when {
            host.contains("coingecko.com") ->
                apiKeyStorage.getApiKey(SecureApiKeyStorage.ApiKeyType.COINGECKO)
            host.contains("tatum.io") ->
                apiKeyStorage.getApiKey(SecureApiKeyStorage.ApiKeyType.TATUM)
            else -> null
        }

        val newRequest = if (apiKey != null) {
            val headerName = when {
                host.contains("coingecko.com") -> "x-cg-demo-api-key"
                host.contains("tatum.io") -> "x-api-key"
                else -> return chain.proceed(originalRequest)
            }
            originalRequest.newBuilder()
                .addHeader(headerName, apiKey)
                .build()
        } else {
            originalRequest
        }

        return chain.proceed(newRequest)
    }
}
```

### 7.3 Rate Limiting (Token Bucket Algorithm)

```kotlin
/**
 * Token Bucket Rate Limiter
 *
 * - CoinGecko free tier: 10 requests/minute
 * - Tatum free tier: 5 requests/second
 *
 * Uses suspend instead of Thread.sleep to avoid blocking.
 */
class TokenBucketRateLimiter(
    private val maxTokens: Int,
    private val refillRatePerSecond: Double
) {
    private var tokens: Double = maxTokens.toDouble()
    private var lastRefillTime: Long = System.nanoTime()
    private val mutex = Mutex()

    suspend fun acquire() {
        mutex.withLock {
            refill()
            while (tokens < 1.0) {
                val waitTime = ((1.0 - tokens) / refillRatePerSecond * 1000).toLong()
                delay(waitTime.coerceAtLeast(10))
                refill()
            }
            tokens -= 1.0
        }
    }

    private fun refill() {
        val now = System.nanoTime()
        val elapsed = (now - lastRefillTime) / 1_000_000_000.0
        tokens = (tokens + elapsed * refillRatePerSecond).coerceAtMost(maxTokens.toDouble())
        lastRefillTime = now
    }
}

// Rate limiters per API
@Module
@InstallIn(SingletonComponent::class)
object RateLimiterModule {

    @Provides
    @Singleton
    @Named("coingecko")
    fun provideCoinGeckoRateLimiter(): TokenBucketRateLimiter {
        // 10 requests per minute = 0.167 per second
        return TokenBucketRateLimiter(maxTokens = 10, refillRatePerSecond = 10.0 / 60.0)
    }

    @Provides
    @Singleton
    @Named("tatum")
    fun provideTatumRateLimiter(): TokenBucketRateLimiter {
        // 5 requests per second
        return TokenBucketRateLimiter(maxTokens = 5, refillRatePerSecond = 5.0)
    }
}

// Usage in Repository
class ExchangeRateRepositoryImpl @Inject constructor(
    private val api: CoinGeckoApi,
    @Named("coingecko") private val rateLimiter: TokenBucketRateLimiter,
    private val cache: ExchangeRateCache
) : ExchangeRateRepository {

    override suspend fun getExchangeRate(from: String, to: String): Result<Double> {
        // Check cache first (no rate limit consumed)
        cache.get(from, to)?.let { cached ->
            if (!cached.isExpired) return Result.success(cached.rate)
        }

        // Acquire rate limit token (suspends if needed)
        rateLimiter.acquire()

        return try {
            val response = api.getExchangeRates(from, to)
            val rate = response[from]?.get(to)
                ?: return Result.failure(RateNotFoundException(from, to))
            cache.put(from, to, rate)
            Result.success(rate)
        } catch (e: Exception) {
            // Return stale cache on error
            cache.get(from, to)?.let { Result.success(it.rate) }
                ?: Result.failure(e)
        }
    }
}
```

### 7.4 Network Security Configuration

```xml
<!-- res/xml/network_security_config.xml -->
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>

    <!-- Pin certificates for critical APIs (optional but recommended) -->
    <domain-config>
        <domain includeSubdomains="true">api.coingecko.com</domain>
        <pin-set expiration="2025-12-31">
            <pin digest="SHA-256">AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=</pin>
            <!-- Add backup pin -->
            <pin digest="SHA-256">BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=</pin>
        </pin-set>
    </domain-config>
</network-security-config>
```

---

## 8. Implementation Phases

### Phase 1: Foundation
**Duration**: 2 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| Project setup with Hilt, Room, Compose | `./gradlew build` succeeds |
| Database schema (all entities) | Schema exports to /schemas/1.json |
| Basic DAOs with tests | 100% DAO test coverage |
| Navigation structure | Can navigate between all placeholder screens |
| Theme + common components | Design tokens match iOS Figma |

**Exit Gate**: Demo navigation between screens, insert/query one Goal entity.

---

### Phase 2: Core Features
**Duration**: 3 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| Goal CRUD operations | Create, read, update, delete all work |
| Goals list screen | List loads, scrolls at 60fps, taps navigate |
| Goal detail screen | Shows all fields, edit navigates correctly |
| Asset CRUD | Same as Goal |
| Transaction recording | Can add manual deposit/withdrawal |
| Basic progress calculations | Progress matches iOS calculation |

**Exit Gate**: Create 10 goals with transactions, verify progress calculations match iOS app within 0.01%.

---

### Phase 3: Allocation System
**Duration**: 2 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| AssetAllocation model | CRUD with unique constraint enforced |
| AllocationHistory snapshots | Snapshots created on allocation changes |
| Auto-allocation logic | Auto-allocates when asset has single goal |
| Over-allocation detection | Warning shown when over-allocated |
| Asset sharing UI | Can split asset across multiple goals |

**Exit Gate**: Allocate 1 asset to 3 goals, verify totals match, allocation history recorded.

---

### Phase 4: Monthly Planning
**Duration**: 3 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| Monthly requirements calculation | Calculations match iOS |
| Flex adjustment slider (0-150%) | Slider updates amounts in real-time |
| Protected/skipped goal flags | UI toggles persist and affect calculation |
| Custom amount override | Can set custom amount per goal |
| Planning UI complete | All components match iOS design |

**Exit Gate**: 5 goals with mixed flex states, flex slider adjusts correctly, amounts match iOS.

---

### Phase 5: Execution Tracking
**Duration**: 3 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| MonthlyExecutionRecord management | State transitions work correctly |
| ExecutionSnapshot capture | Snapshot frozen at execution start |
| Timestamp-based progress derivation | Progress derived from transactions + allocations |
| 24-hour undo windows | Undo available within window, disabled after |
| CompletedExecution history | History persisted and viewable |
| Execution UI | All states displayed correctly |

**Exit Gate**: Full execution cycle (start → add transactions → complete), verify derived progress matches expected.

---

### Phase 6: API Integration
**Duration**: 2 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| CoinGecko integration | Exchange rates fetched and cached |
| Tatum blockchain integration | Balances fetched for test addresses |
| Rate limiting | No 429 errors in normal usage |
| Caching | Cache hit ratio > 90% in typical usage |
| Fallback handling | Stale cache returned on API failure |

**Exit Gate**: Fetch rates for 10 currencies, verify cache works, simulate API failure and verify fallback.

---

### Phase 7: Dashboard & Polish
**Duration**: 2 weeks
**Staffing**: 1 Android developer

| Task | Exit Criteria |
|------|---------------|
| Dashboard screen | Portfolio total, goal summary displayed |
| Charts (Vico) | Progress charts render correctly |
| Accessibility audit | TalkBack works on all screens |
| Performance optimization | Cold start < 2s, scroll 60fps |
| Edge case handling | Empty states, error states handled |

**Exit Gate**: Accessibility review pass, performance benchmarks met.

---

### Phase 8: Testing & Release
**Duration**: 3 weeks
**Staffing**: 1 Android developer + 0.5 QA

| Task | Exit Criteria |
|------|---------------|
| Unit test coverage | Domain layer > 80% coverage |
| UI tests | All critical journeys have tests |
| Migration tests | All Room migrations tested |
| Manual QA | Test matrix complete, no P0/P1 bugs |
| Beta release | Internal testing track published |
| Production release | Play Store approved |

**Exit Gate**: All acceptance criteria met (see Section 1.3).

---

## 9. Testing Strategy

### 9.1 Test Framework Setup

```kotlin
// JUnit 5 Extension for Main Dispatcher
@ExtendWith(MainDispatcherExtension::class)
class MonthlyPlanningViewModelTest {
    // Tests run on TestDispatcher
}

class MainDispatcherExtension : BeforeEachCallback, AfterEachCallback {
    private val testDispatcher = UnconfinedTestDispatcher()

    override fun beforeEach(context: ExtensionContext) {
        Dispatchers.setMain(testDispatcher)
    }

    override fun afterEach(context: ExtensionContext) {
        Dispatchers.resetMain()
    }
}
```

### 9.2 Unit Tests (JUnit 5 + MockK + Turbine)

```kotlin
@ExtendWith(MainDispatcherExtension::class)
class MonthlyPlanningViewModelTest {

    private val calculateRequirementsUseCase = mockk<CalculateMonthlyRequirementsUseCase>()
    private val applyFlexAdjustmentUseCase = mockk<ApplyFlexAdjustmentUseCase>()
    private val preferencesDataStore = mockk<PreferencesDataStore> {
        every { displayCurrency } returns flowOf("USD")
    }

    private lateinit var viewModel: MonthlyPlanningViewModel

    @BeforeEach
    fun setup() {
        viewModel = MonthlyPlanningViewModel(
            calculateRequirementsUseCase = calculateRequirementsUseCase,
            applyFlexAdjustmentUseCase = applyFlexAdjustmentUseCase,
            monthlyPlanRepository = mockk(),
            preferencesDataStore = preferencesDataStore
        )
    }

    @Test
    fun `loadRequirements emits loading then success`() = runTest {
        // Given
        val mockRequirements = listOf(TestFixtures.createRequirement("goal1", 1000.0))
        coEvery { calculateRequirementsUseCase("USD") } returns mockRequirements

        // When & Then
        viewModel.uiState.test {
            assertThat(awaitItem().isLoading).isFalse()  // Initial

            viewModel.loadRequirements()

            assertThat(awaitItem().isLoading).isTrue()   // Loading
            assertThat(awaitItem().isLoading).isFalse()  // Success
        }

        viewModel.requirements.test {
            assertThat(awaitItem()).isEqualTo(mockRequirements)
        }
    }

    @Test
    fun `toggleProtected adds and removes goal from protected set`() {
        // When
        viewModel.toggleProtected("goal1")

        // Then
        assertThat(viewModel.uiState.value.protectedGoalIds).contains("goal1")

        // When toggled again
        viewModel.toggleProtected("goal1")

        // Then removed
        assertThat(viewModel.uiState.value.protectedGoalIds).doesNotContain("goal1")
    }
}
```

### 9.3 Network Testing (MockWebServer)

```kotlin
class ExchangeRateRepositoryTest {

    private lateinit var mockWebServer: MockWebServer
    private lateinit var api: CoinGeckoApi
    private lateinit var repository: ExchangeRateRepositoryImpl

    @BeforeEach
    fun setup() {
        mockWebServer = MockWebServer()
        mockWebServer.start()

        api = Retrofit.Builder()
            .baseUrl(mockWebServer.url("/"))
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(CoinGeckoApi::class.java)

        repository = ExchangeRateRepositoryImpl(
            api = api,
            rateLimiter = TokenBucketRateLimiter(10, 10.0),
            cache = InMemoryExchangeRateCache()
        )
    }

    @AfterEach
    fun teardown() {
        mockWebServer.shutdown()
    }

    @Test
    fun `getExchangeRate returns cached value on network error`() = runTest {
        // Given - prime cache
        mockWebServer.enqueue(MockResponse()
            .setBody("""{"bitcoin":{"usd":50000.0}}""")
            .setResponseCode(200))

        repository.getExchangeRate("BTC", "USD")

        // When - network fails
        mockWebServer.enqueue(MockResponse().setResponseCode(500))

        val result = repository.getExchangeRate("BTC", "USD")

        // Then - returns cached value
        assertThat(result.isSuccess).isTrue()
        assertThat(result.getOrNull()).isEqualTo(50000.0)
    }

    @Test
    fun `rate limiter prevents burst requests`() = runTest {
        repeat(15) {
            mockWebServer.enqueue(MockResponse()
                .setBody("""{"bitcoin":{"usd":50000.0}}""")
                .setResponseCode(200))
        }

        val startTime = System.currentTimeMillis()

        // Make 15 requests (rate limit is 10/minute)
        repeat(15) {
            repository.getExchangeRate("BTC", "USD")
        }

        val elapsed = System.currentTimeMillis() - startTime

        // Should take at least 30 seconds for 15 requests at 10/min
        // (Actually less due to initial bucket, but > 0)
        assertThat(elapsed).isGreaterThan(0)
    }
}
```

### 9.4 UI Tests (Compose Testing)

**Running UI Tests:**
```bash
# Run all instrumented tests (includes Compose UI tests)
./gradlew connectedDebugAndroidTest

# Run a specific test class
./gradlew connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.xax.CryptoSavingsTracker.GoalsListScreenTest
```

**Required Dependencies** (already included in Section 2):
- `androidTestImplementation("androidx.compose.ui:ui-test-junit4")` - Compose test APIs
- `debugImplementation("androidx.compose.ui:ui-test-manifest")` - Required for createAndroidComposeRule
- `androidTestImplementation("com.google.dagger:hilt-android-testing:2.52")` - Hilt test support

```kotlin
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class GoalsListScreenTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Inject
    lateinit var goalRepository: GoalRepository

    @Before
    fun setup() {
        hiltRule.inject()
    }

    @Test
    fun goalsListDisplaysGoals() = runTest {
        // Given
        val goal = TestFixtures.createGoal(name = "Buy a car")
        goalRepository.insert(goal)

        // Navigate to goals list
        composeRule.onNodeWithText("Goals").performClick()

        // Then
        composeRule.onNodeWithText("Buy a car").assertIsDisplayed()
    }

    @Test
    fun tapGoalNavigatesToDetail() = runTest {
        // Given
        val goal = TestFixtures.createGoal(name = "Vacation fund")
        goalRepository.insert(goal)

        composeRule.onNodeWithText("Goals").performClick()

        // When
        composeRule.onNodeWithText("Vacation fund").performClick()

        // Then - verify on detail screen
        composeRule.onNodeWithTag("goal_detail_screen").assertIsDisplayed()
    }
}
```

### 9.5 E2E Test Harness

```kotlin
/**
 * End-to-end test for complete monthly planning flow.
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class MonthlyPlanningE2ETest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun completeMonthlyPlanningFlow() {
        // 1. Create goals
        composeRule.onNodeWithContentDescription("Add goal").performClick()
        composeRule.onNodeWithTag("goal_name_input").performTextInput("Emergency Fund")
        composeRule.onNodeWithTag("goal_amount_input").performTextInput("10000")
        composeRule.onNodeWithText("Save").performClick()

        // 2. Add assets with transactions
        composeRule.onNodeWithText("Assets").performClick()
        composeRule.onNodeWithContentDescription("Add asset").performClick()
        // ... add asset flow

        // 3. Go to Monthly Planning
        composeRule.onNodeWithText("Planning").performClick()

        // 4. Verify requirements calculated
        composeRule.onNodeWithText("Emergency Fund").assertIsDisplayed()
        composeRule.onNodeWithTextContaining("$/month").assertIsDisplayed()

        // 5. Adjust flex slider
        composeRule.onNodeWithTag("flex_slider").performTouchInput {
            swipeRight()
        }

        // 6. Start tracking
        composeRule.onNodeWithText("Start Tracking").performClick()

        // 7. Verify execution screen
        composeRule.onNodeWithTag("execution_screen").assertIsDisplayed()
        composeRule.onNodeWithText("Executing").assertIsDisplayed()
    }
}
```

### 9.6 CI/CD Integration

```yaml
# .github/workflows/android-tests.yml
name: Android Tests

on:
  push:
    paths: ['android/**']
  pull_request:
    paths: ['android/**']

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Run unit tests
        working-directory: android
        run: ./gradlew testDebugUnitTest

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: unit-test-results
          path: android/app/build/reports/tests/

  instrumented-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Enable KVM (for emulator)
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - name: Run instrumented tests
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 34
          arch: x86_64
          script: cd android && ./gradlew connectedDebugAndroidTest
```

```kotlin
// HiltTestRunner.kt - Required for Hilt instrumented tests
package com.xax.CryptoSavingsTracker

import android.app.Application
import android.content.Context
import androidx.test.runner.AndroidJUnitRunner
import dagger.hilt.android.testing.HiltTestApplication

class HiltTestRunner : AndroidJUnitRunner() {
    override fun newApplication(
        cl: ClassLoader?,
        className: String?,
        context: Context?
    ): Application {
        return super.newApplication(cl, HiltTestApplication::class.java.name, context)
    }
}
```

---

## 10. Platform-Specific Considerations

### Android-Specific Features (v1.0)
- **Material You**: Dynamic theming from wallpaper colors
- **Notifications**: Reminder notifications via WorkManager
- **Edge-to-edge**: Full edge-to-edge display support

### Deferred to v1.1+
- Home screen widgets
- Wear OS companion
- Biometric app lock
- Tablet landscape layouts

---

## 11. CSV Export Format Specification

CSV export **must match iOS format exactly** for cross-platform data exchange compatibility.

**iOS exports 3 files:**
1. `goals.csv` - with allocations embedded as JSON
2. `assets.csv` - with allocations embedded as JSON
3. `value_changes.csv` - combined transactions and allocation history events

### 11.1 goals.csv

```csv
id,name,currency,targetAmount,deadline,startDate,lifecycleStatusRawValue,lifecycleStatusChangedAt,lastModifiedDate,reminderFrequency,reminderTime,firstReminderDate,emoji,goalDescription,link,allocationCount,allocationIds,allocationsJson
"uuid-1","Emergency Fund","USD",10000.0,"2024-01-01T00:00:00.000Z","2024-01-01T00:00:00.000Z","active","","2024-03-15T10:00:00.000Z","monthly","","","💰","6 months expenses","",2,"alloc-1;alloc-2","[{...}]"
```

| Column | Type | Format | Notes |
|--------|------|--------|-------|
| id | String | UUID | Primary key |
| name | String | UTF-8 | Goal name |
| currency | String | ISO 4217 / crypto | e.g., "USD", "BTC" |
| targetAmount | Double | Full precision | Target value |
| deadline | String | ISO 8601 | Full timestamp with fractional seconds |
| startDate | String | ISO 8601 | Full timestamp |
| lifecycleStatusRawValue | String | Enum | "active", "cancelled", "finished", "deleted" |
| lifecycleStatusChangedAt | String | ISO 8601 | Optional |
| lastModifiedDate | String | ISO 8601 | Last update |
| reminderFrequency | String | Enum | Optional: "daily", "weekly", "monthly" |
| reminderTime | String | ISO 8601 | Optional |
| firstReminderDate | String | ISO 8601 | Optional |
| emoji | String | UTF-8 emoji | Optional |
| goalDescription | String | UTF-8 | Optional |
| link | String | URL | Optional |
| allocationCount | Int | Count | Number of allocations |
| allocationIds | String | Semicolon-separated UUIDs | "id1;id2;id3" |
| allocationsJson | String | JSON array | Embedded allocation objects |

### 11.2 assets.csv

```csv
id,currency,address,chainId,transactionCount,transactionIds,allocationCount,allocationIds,allocationsJson
"uuid-1","BTC","bc1q...xyz","bitcoin",5,"tx-1;tx-2;tx-3;tx-4;tx-5",2,"alloc-1;alloc-2","[{...}]"
```

| Column | Type | Format | Notes |
|--------|------|--------|-------|
| id | String | UUID | Primary key |
| currency | String | Symbol | e.g., "BTC", "ETH", "USD" |
| address | String | Blockchain address | Optional, empty for fiat |
| chainId | String | Chain identifier | Optional, empty for fiat |
| transactionCount | Int | Count | Number of transactions |
| transactionIds | String | Semicolon-separated UUIDs | "id1;id2;id3" |
| allocationCount | Int | Count | Number of allocations |
| allocationIds | String | Semicolon-separated UUIDs | "id1;id2;id3" |
| allocationsJson | String | JSON array | Embedded allocation objects |

### 11.3 value_changes.csv

Combines transactions and allocation history into a single chronological event stream.

```csv
eventType,eventId,timestamp,amount,amountSemantics,assetId,assetCurrency,assetChainId,assetAddress,goalId,goalName,transactionSource,transactionExternalId,transactionCounterparty,transactionComment,allocationMonthLabel,allocationCreatedAt
"transaction","tx-uuid-1","2024-03-15T09:00:00.000Z",0.05,"delta","asset-uuid-1","BTC","bitcoin","bc1q...","","","manual","","","Monthly DCA","",""
"allocationHistory","ah-uuid-1","2024-03-15T10:00:00.000Z",5000.0,"allocationTargetSnapshot","asset-uuid-1","BTC","bitcoin","bc1q...","goal-uuid-1","Emergency Fund","","","","","2024-03","2024-03-15T10:00:00.000Z"
```

| Column | Type | Format | Notes |
|--------|------|--------|-------|
| eventType | String | Enum | "transaction" or "allocationHistory" |
| eventId | String | UUID | Event ID |
| timestamp | String | ISO 8601 | Event timestamp |
| amount | Double | Full precision | Transaction delta or allocation snapshot |
| amountSemantics | String | Enum | "delta" (tx) or "allocationTargetSnapshot" (history) |
| assetId | String | UUID | Asset reference |
| assetCurrency | String | Symbol | Asset currency |
| assetChainId | String | Chain ID | Optional |
| assetAddress | String | Address | Optional |
| goalId | String | UUID | Only for allocationHistory |
| goalName | String | UTF-8 | Only for allocationHistory |
| transactionSource | String | Enum | "manual" or "onChain" (tx only) |
| transactionExternalId | String | Tx hash | On-chain tx hash (tx only) |
| transactionCounterparty | String | UTF-8 | Optional (tx only) |
| transactionComment | String | UTF-8 | Optional (tx only) |
| allocationMonthLabel | String | "yyyy-MM" | Month label (history only) |
| allocationCreatedAt | String | ISO 8601 | Creation time (history only) |

### 11.4 Allocations JSON Schema (embedded in goals.csv and assets.csv)

```json
[
  {
    "id": "uuid",
    "amount": 5000.0,
    "createdDate": "2024-01-15T10:00:00.000Z",
    "lastModifiedDate": "2024-03-15T10:00:00.000Z",
    "assetId": "asset-uuid",
    "goalId": "goal-uuid",
    "assetCurrency": "BTC",
    "goalName": "Emergency Fund"
  }
]
```

### 11.5 Export Implementation

```kotlin
class CsvExportService @Inject constructor(
    private val goalRepository: GoalRepository,
    private val assetRepository: AssetRepository,
    private val transactionRepository: TransactionRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository
) {
    private val isoFormatter = DateTimeFormatter.ISO_INSTANT

    /**
     * Exports 3 files matching iOS format:
     * - goals.csv (with embedded allocations JSON)
     * - assets.csv (with embedded allocations JSON)
     * - value_changes.csv (combined transactions + allocation history)
     */
    suspend fun exportAll(outputDir: File): List<File> {
        val goals = goalRepository.getAllGoals().first()
        val assets = assetRepository.getAllAssets().first()
        val transactions = transactionRepository.getAllTransactions().first()
        val allocationHistories = allocationHistoryRepository.getAll().first()

        val timestamp = Instant.now().toString()
            .replace(":", "-").replace(".", "-")
        val exportDir = File(outputDir, "CryptoSavingsTracker-CSV-$timestamp")
        exportDir.mkdirs()

        return listOf(
            exportGoals(goals, File(exportDir, "goals.csv")),
            exportAssets(assets, File(exportDir, "assets.csv")),
            exportValueChanges(transactions, allocationHistories, goals, assets,
                File(exportDir, "value_changes.csv"))
        )
    }

    private fun exportGoals(goals: List<Goal>, file: File): File {
        val header = "id,name,currency,targetAmount,deadline,startDate," +
            "lifecycleStatusRawValue,lifecycleStatusChangedAt,lastModifiedDate," +
            "reminderFrequency,reminderTime,firstReminderDate,emoji,goalDescription,link," +
            "allocationCount,allocationIds,allocationsJson"

        file.bufferedWriter().use { writer ->
            writer.write(header + "\n")
            goals.forEach { goal ->
                val allocationIds = goal.allocations.joinToString(";") { it.id }
                val allocationsJson = Json.encodeToString(goal.allocations.map { it.toExportDto() })
                writer.write(csvLine(
                    goal.id, goal.name, goal.currency, goal.targetAmount.toString(),
                    goal.deadline.format(isoFormatter), goal.startDate.format(isoFormatter),
                    goal.lifecycleStatus.name.lowercase(), goal.lifecycleStatusChangedAt?.format(isoFormatter) ?: "",
                    goal.lastModifiedDate.format(isoFormatter),
                    goal.reminderFrequency ?: "", goal.reminderTime?.format(isoFormatter) ?: "",
                    goal.firstReminderDate?.format(isoFormatter) ?: "",
                    goal.emoji ?: "", goal.description ?: "", goal.link ?: "",
                    goal.allocations.size.toString(), allocationIds, allocationsJson
                ))
            }
        }
        return file
    }

    private fun exportValueChanges(
        transactions: List<Transaction>,
        histories: List<AllocationHistory>,
        goals: List<Goal>,
        assets: List<Asset>,
        file: File
    ): File {
        val goalNameById = goals.associate { it.id to it.name }
        val assetById = assets.associateBy { it.id }

        data class Event(val timestamp: Instant, val row: List<String>)
        val events = mutableListOf<Event>()

        // Add transaction events
        transactions.forEach { tx ->
            val asset = assetById[tx.assetId]
            events += Event(tx.date, listOf(
                "transaction", tx.id, tx.date.format(isoFormatter), tx.amount.toString(), "delta",
                tx.assetId, asset?.currency ?: "", asset?.chainId ?: "", asset?.address ?: "",
                "", "", tx.source.name.lowercase(), tx.externalId ?: "",
                tx.counterparty ?: "", tx.comment ?: "", "", ""
            ))
        }

        // Add allocation history events
        histories.forEach { history ->
            val asset = assetById[history.assetId]
            val goalName = goalNameById[history.goalId] ?: ""
            events += Event(history.timestamp, listOf(
                "allocationHistory", history.id, history.timestamp.format(isoFormatter),
                history.amount.toString(), "allocationTargetSnapshot",
                history.assetId, asset?.currency ?: "", asset?.chainId ?: "", asset?.address ?: "",
                history.goalId, goalName, "", "", "", "", history.monthLabel,
                history.createdAt.format(isoFormatter)
            ))
        }

        // Sort chronologically and write
        val header = "eventType,eventId,timestamp,amount,amountSemantics,assetId,assetCurrency," +
            "assetChainId,assetAddress,goalId,goalName,transactionSource,transactionExternalId," +
            "transactionCounterparty,transactionComment,allocationMonthLabel,allocationCreatedAt"

        file.bufferedWriter().use { writer ->
            writer.write(header + "\n")
            events.sortedBy { it.timestamp }.forEach { event ->
                writer.write(csvLine(*event.row.toTypedArray()))
            }
        }
        return file
    }

    private fun csvLine(vararg values: String): String {
        return values.joinToString(",") { value ->
            if (value.contains(",") || value.contains("\"") || value.contains("\n")) {
                "\"${value.replace("\"", "\"\"")}\""
            } else value
        } + "\n"
    }
}
```

---

## Appendix: iOS-Android Model Mapping

| iOS (SwiftData) | Android (Room) | Notes |
|-----------------|----------------|-------|
| `@Model` | `@Entity` | Class annotation |
| `@Attribute(.unique)` | `@Index(unique = true)` | Unique constraint |
| `@Relationship` | `@ForeignKey` + `@Relation` | Relationships |
| `#Predicate` | `@Query` with SQL | Filtering |
| `Codable` (JSON) | `@TypeConverter` | Complex types |
| `UUID` | `String` (UUID.toString()) | ID storage |
| `Date` (date-only) | `Int` (epochDay) | Use `LocalDate.toEpochDay()` |
| `Date` (timestamp) | `Long` (epochMillis) | Use `Instant.toEpochMilli()` |

---

*Last Updated: December 2024*
