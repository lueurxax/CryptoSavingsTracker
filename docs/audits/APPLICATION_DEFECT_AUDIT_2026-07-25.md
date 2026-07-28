# Application defect audit — 2026-07-25

> Evidence-backed register of defects found in the Apple and Android applications

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-07-25 |
| Platform | Shared |
| Audience | All |

---

## Table of contents

- [Document choice](#document-choice)
- [Executive summary](#executive-summary)
- [Scope and evidence](#scope-and-evidence)
- [Findings summary](#findings-summary)
- [Apple findings](#apple-findings)
- [Android findings](#android-findings)
- [Remediation order](#remediation-order)
- [Verification log](#verification-log)
- [Exit criteria](#exit-criteria)
- [Related documentation](#related-documentation)

---

## Document choice

This artifact is a **defect audit**, not a proposal. A proposal should recommend
one coherent future change and record its trade-offs. This document instead
captures several independent failures in the current product, the evidence for
each failure, and the smallest useful verification target.

Individual fixes can become proposals only when they require a cross-cutting
product or architecture decision. Most findings below should enter the normal
defect backlog directly.

---

## Executive summary

The audit found 16 defects: one release blocker, 12 high-impact defects, and
three medium-impact defects.

| Priority | Count | Meaning |
|----------|-------|---------|
| P0 | 1 | A documented supported platform cannot compile |
| P1 | 12 | Financial correctness, persisted-data integrity, or a core user flow is broken |
| P2 | 3 | A secondary or platform-specific flow is materially misleading or incomplete |

The highest-risk cluster is financial correctness. Both applications contain
paths that compare, aggregate, label, or persist values without converting them
to the required currency or unit. Those paths can show plausible but materially
wrong balances and progress.

Current release posture:

- The macOS target is blocked at compile time by `APPLE-001`.
- Apple simulator runtime verification remains incomplete because the local
  CoreSimulator service disconnected during the test run.
- The Android unit-test baseline passes, but the five Android findings are not
  covered by those tests.

---

## Scope and evidence

The audit covered production code in `ios/` and `android/`, with emphasis on
money movement, balances, allocations, lifecycle transitions, navigation,
persistence, and notification delivery.

Evidence labels used below:

- **Build-reproduced**: the failure was observed in a fresh targeted build.
- **Source-proven**: the failure follows deterministically from the current
  control flow or unit conversion, with a minimal reproduction specified.

This is a targeted audit, not an assertion that no other defects exist. The
working tree already contained unrelated user changes before the audit; those
changes were preserved and were not folded into this document.

---

## Findings summary

| ID | Priority | Platform | Area | Evidence |
|----|----------|----------|------|----------|
| APPLE-001 | P0 | macOS | Build compatibility | Build-reproduced |
| APPLE-002 | P1 | iOS | Navigation | Source-proven |
| APPLE-003 | P1 | iOS | Currency aggregation | Source-proven |
| APPLE-004 | P1 | Apple | Allocation lifecycle | Source-proven |
| APPLE-005 | P1 | iOS | Localized money input | Source-proven |
| APPLE-006 | P1 | iOS | Goal archival | Source-proven |
| APPLE-007 | P2 | macOS | Goal filtering | Source-proven |
| APPLE-008 | P1 | Apple | On-chain balances | Source-proven |
| APPLE-009 | P1 | Apple | Transaction import | Source-proven |
| APPLE-010 | P1 | Apple | Planning cache | Source-proven |
| APPLE-011 | P2 | Apple | Deposit suggestion | Source-proven |
| ANDROID-001 | P1 | Android | Execution progress | Source-proven |
| ANDROID-002 | P1 | Android | On-chain balances | Source-proven |
| ANDROID-003 | P1 | Android | Reminder permission | Source-proven |
| ANDROID-004 | P1 | Android | Transaction editing | Source-proven |
| ANDROID-005 | P2 | Android | Onboarding | Source-proven |

---

## Apple findings

### APPLE-001 — macOS fails to compile CloudKit sharing code

- **Priority:** P0.
- **Evidence:** Build-reproduced.
- **User impact:** The documented macOS target cannot be built or tested.
- **Root cause:** Three macOS-visible call sites construct
  `FamilyShareInvitationMetadataSnapshot(metadata:)`, but that initializer is
  compiled only when UIKit is available. On macOS, Swift therefore resolves
  only the synthesized Codable `init(from:)` and reports an incorrect argument
  label and type mismatch.
- **Code evidence:**
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:242`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1501`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:1579`
  - UIKit-scoped initializer:
    `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:2373-2406`
- **Reproduction:** Build the `CryptoSavingsTracker` app scheme for
  `platform=macOS` with code signing disabled. Compilation stops at the three call sites with
  `Incorrect argument label in call (have 'metadata:', expected 'from:')`.
- **Regression target:** Add a macOS compile-and-test CI job that includes the
  CloudKit sharing sources.
- **Fix boundary:** Make the metadata conversion available wherever CloudKit is
  available; UIKit-specific invitation presentation should remain separately
  guarded.

### APPLE-002 — Dashboard and Planning routes have no navigation host

- **Priority:** P1.
- **Evidence:** Source-proven.
- **User impact:** Dashboard calls to action and goal cards cannot push their
  destinations. The preview Planning tab loses its navigation title, toolbar,
  settings route, and add-goal route.
- **Root cause:** `ContentView` mounts `DashboardView` and
  `MonthlyPlanningContainer` directly inside a bare `TabView`, while both views
  depend on navigation APIs. The application root mounts `ContentView` without
  adding a navigation host.
- **Code evidence:**
  - `ios/CryptoSavingsTracker/Views/ContentView.swift:97-127`
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift:237-240`
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift:438-465`
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift:493-497`
  - `ios/CryptoSavingsTracker/Views/Planning/MonthlyPlanningContainer.swift:81-107`
  - `ios/CryptoSavingsTracker/Views/Planning/MonthlyPlanningContainer.swift:186-190`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:202-223`
- **Minimal reproduction:** On an empty Dashboard, tap **Create Goal**. With
  seeded data, tap a goal card. Neither `NavigationLink` has a stack in which to
  push. Enable preview features and open Planning to observe the missing
  navigation-bar actions.
- **Regression target:** UI tests should open New Goal from the empty state,
  open goal detail from a card, and open the Planning add-goal destination.
- **Fix boundary:** Establish one explicit navigation owner per tab and preserve
  existing sheets and deep-link routing.

### APPLE-003 — Dashboard sums mixed currencies and always labels the result USD

- **Priority:** P1.
- **Evidence:** Source-proven.
- **User impact:** The portfolio value can be materially false. Changing
  **Display Currency** to EUR or GBP has no effect.
- **Root cause:** Each goal total is denominated in that goal's currency, but
  Dashboard adds the raw totals and formats the result as USD. The
  `mvp.settings.displayCurrency` preference has no consumer outside Settings.
- **Code evidence:**
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:19`
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:35-40`
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift:90-93`
  - Snapshot loading:
    `ios/CryptoSavingsTracker/Views/DashboardView.swift:176-184`
  - Per-goal calculation:
    `ios/CryptoSavingsTracker/Services/GoalCalculationService.swift:79-82`
  - Goal-currency total:
    `ios/CryptoSavingsTracker/ViewModels/GoalViewModel.swift:99-105`
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift:203`
- **Minimal reproduction:** Create one goal worth 100 USD and another worth
  100 EUR. Dashboard displays `$200`. Select GBP in Settings; the amount and
  currency label remain unchanged.
- **Regression target:** Use fixed exchange-rate fixtures to aggregate mixed
  goal currencies, then verify that changing display currency changes both the
  number and its label.
- **Fix boundary:** Convert every component to one explicit display currency
  before aggregation; do not relabel an unconverted amount.

### APPLE-004 — Cancelling or deleting a goal can leave its allocation attached

- **Priority:** P1.
- **Evidence:** Source-proven.
- **User impact:** A goal can disappear while continuing to reserve funds,
  leaving allocation totals inconsistent and preventing reuse of the funds.
- **Root cause:** Goal lifecycle cleanup rebuilds each asset's remaining
  allocation set through the general validation path and suppresses every
  thrown error with `try?`. If the asset balance has fallen below the remaining
  allocations, validation rejects the cleanup, but the goal can still be marked
  inactive. A removal-only API already exists but is not used by this path.
- **Code evidence:**
  - User promise:
    `ios/CryptoSavingsTracker/Views/GoalDetailView.swift:366-389`
  - Lifecycle mutation:
    `ios/CryptoSavingsTracker/Services/GoalLifecycleService.swift:25-36`
  - Delete mutation:
    `ios/CryptoSavingsTracker/Services/GoalLifecycleService.swift:52-81`
  - Validation rejection:
    `ios/CryptoSavingsTracker/Services/AllocationService.swift:274-278`
  - Removal-only operation:
    `ios/CryptoSavingsTracker/Services/AllocationService.swift:259-267`
- **Minimal reproduction:** Persist an asset with current balance 50 and
  allocations A=100 and B=200, representing a balance that fell after valid
  allocation. Cancel A. Revalidating remaining B against 50 fails; the error is
  swallowed, A becomes hidden, and its allocation can remain.
- **Regression target:** A lifecycle test must assert that no allocation
  references a cancelled or deleted goal, even when remaining allocations
  exceed the latest balance.
- **Fix boundary:** Make lifecycle state and allocation removal atomic, use a
  removal-safe primitive, and surface persistence failures.

### APPLE-005 — Comma-decimal locales cannot save fractional money values

- **Priority:** P1.
- **Evidence:** Source-proven.
- **User impact:** Users in comma-decimal locales cannot save common fractional
  crypto amounts. A localized value prefilled by the app can fail the app's own
  validation.
- **Root cause:** Add Goal and Add Transaction show a localized decimal
  keyboard but parse text with locale-independent `Double(String)`. Transaction
  prefilling uses the current locale, so it can produce `1,5`, which the
  subsequent parser rejects. A locale-aware `MoneyInputParser` already exists
  but is not used by these forms.
- **Code evidence:**
  - `ios/CryptoSavingsTracker/Views/AddGoalView.swift:95-100`
  - `ios/CryptoSavingsTracker/Views/AddGoalView.swift:417-420`
  - `ios/CryptoSavingsTracker/Views/AddGoalView.swift:545-552`
  - `ios/CryptoSavingsTracker/Views/AddTransactionView.swift:132-135`
  - `ios/CryptoSavingsTracker/Views/AddTransactionView.swift:204-206`
  - `ios/CryptoSavingsTracker/Views/AddTransactionView.swift:238-263`
  - `ios/CryptoSavingsTracker/Utilities/MoneyInputParser.swift:35-85`
- **Minimal reproduction:** Launch under `de_DE`, enter `1,50` as a goal or
  transaction amount, and observe that Save remains disabled.
- **Regression target:** Locale-parameterized view-model or UI tests should save
  `1,50` as 1.5 while retaining crypto-appropriate precision.
- **Fix boundary:** Route display, validation, and persistence through the same
  locale-aware decimal parser.

### APPLE-006 — Archived goals cannot be restored through the iOS app

- **Priority:** P1.
- **Evidence:** Source-proven.
- **User impact:** Archive preserves data but removes the goal from every
  user-facing iOS list, despite copy promising that it can be restored.
- **Root cause:** Archive maps the goal to lifecycle state `.deleted`; the iOS
  goals query includes only active goals, and no archived/deleted UI query,
  route, section, or user-facing restore action exists.
- **Code evidence:**
  - Restore promise:
    `ios/CryptoSavingsTracker/Views/EditGoalView.swift:401-415`
  - Archive confirmation:
    `ios/CryptoSavingsTracker/Views/EditGoalView.swift:597-625`
  - Lifecycle mapping:
    `ios/CryptoSavingsTracker/Models/Goal+Editing.swift:21-37`
  - Active-only query:
    `ios/CryptoSavingsTracker/Views/Goals/GoalsListContainer.swift:15-18`
  - Service-level restore operation without a UI entry point:
    `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:51-58`
  - View-model restore operation without a UI entry point:
    `ios/CryptoSavingsTracker/ViewModels/GoalEditViewModel.swift:203-218`
- **Minimal reproduction:** Archive an active goal, return to Goals, and
  relaunch. The goal is absent and there is no archived-goals destination.
- **Regression target:** UI-test archive, locate the goal in an archived
  section, restore it, and assert that it returns to the active list.
- **Fix boundary:** Either implement the promised restore surface or change the
  operation and copy to match an intentionally irreversible lifecycle.

### APPLE-007 — macOS sidebar includes inactive goals

- **Priority:** P2.
- **Evidence:** Source-proven.
- **User impact:** Once the P0 macOS build blocker is removed, deleted,
  cancelled, or completed goals can remain in the sidebar and may be
  automatically selected after another deletion.
- **Root cause:** The macOS sidebar uses an unfiltered goal query and renders
  every result. Its deletion handler selects `goals.first`, which can itself be
  inactive. The iOS list correctly applies an active-only predicate.
- **Code evidence:**
  - `ios/CryptoSavingsTracker/Views/Goals/GoalsSidebarContainer.swift:13`
  - `ios/CryptoSavingsTracker/Views/Goals/GoalsSidebarContainer.swift:39-43`
  - `ios/CryptoSavingsTracker/Views/Components/GoalsSidebarView.swift:45-57`
  - Active-only contrast:
    `ios/CryptoSavingsTracker/Views/Goals/GoalsListContainer.swift:15-18`
- **Minimal reproduction:** After macOS builds again, seed active and deleted
  goals, open the sidebar, and delete the selected active goal. The deleted row
  remains eligible for display and selection.
- **Regression target:** A macOS view/query test should expose only active goals
  and select the next active row.
- **Fix boundary:** Centralize the active-goal predicate so iOS and macOS cannot
  drift.

### APPLE-008 — Small raw Tatum balances are inflated by token decimals

- **Priority:** P1.
- **Evidence:** Source-proven.
- **User impact:** A small wallet balance can be overstated by as much as
  `10^decimals`, corrupting balances, allocations, and progress.
- **Root cause:** The v4 parser prioritizes raw `denominatedBalance` but converts
  atomic units only when the numeric value is greater than 1,000. Raw values at
  or below that arbitrary threshold are returned as human-readable units. The
  same magnitude heuristic appears in the response model.
- **Code evidence:**
  - `ios/CryptoSavingsTracker/Services/BalanceService.swift:194-209`
  - Raw-field contract:
    `ios/CryptoSavingsTracker/Services/TatumModels.swift:98-108`
  - Duplicate heuristic:
    `ios/CryptoSavingsTracker/Services/TatumModels.swift:118-127`
- **Minimal reproduction:** Parse ETH with `denominatedBalance = "1000"` and
  `decimals = 18`. The correct balance is `0.000000000000001`, but the service
  reports `1000`.
- **Regression target:** Add boundary fixtures for raw values below, equal to,
  and above 1,000 across multiple decimal counts.
- **Fix boundary:** Interpret fields from their API contract, never from value
  magnitude, and keep raw integer and normalized decimal types distinct.

### APPLE-009 — Tatum v4 incoming and outgoing transactions are skipped

- **Priority:** P1.
- **Evidence:** Source-proven.
- **User impact:** Valid deposits and withdrawals can disappear from durable
  history, contribution calculations, and automatic goal allocation.
- **Root cause:** Import recognizes subtype text containing `receive` or `sent`,
  but normal v4 records use `incoming` and `outgoing`. When those records omit
  `from` and `to`, direction inference returns `nil`, and the importer silently
  skips the transaction.
- **Code evidence:**
  - Skip path:
    `ios/CryptoSavingsTracker/Services/OnChainTransactionImportService.swift:22-41`
  - Direction inference:
    `ios/CryptoSavingsTracker/Services/OnChainTransactionImportService.swift:104-134`
  - Existing real-format fixture:
    `ios/CryptoSavingsTrackerTests/TatumTransactionParsingTests.swift:17-34`
- **Minimal reproduction:** Import the existing `incoming` fixture, which has
  `address` and `counterAddress` but no `from` or `to`. Zero transactions are
  persisted. An equivalent `outgoing` record fails the same way.
- **Regression target:** Import both subtype variants into an in-memory model
  container and assert one positive and one negative transaction.
- **Fix boundary:** Normalize documented subtype values before address-based
  fallback and make unsupported variants observable rather than silently lost.

### APPLE-010 — Planning cache returns schedules built from obsolete goal data

- **Priority:** P1.
- **Evidence:** Source-proven.
- **User impact:** A user can edit a target, deadline, balance, or allocation
  and then apply a five-minute-old contribution plan.
- **Root cause:** Cache identity contains goal IDs, budget, currency, and time,
  but omits target, deadline, current total/allocation, and rate inputs.
  Remaining amounts are recalculated only after a cache miss.
- **Code evidence:**
  - Cache key:
    `ios/CryptoSavingsTracker/Services/BudgetCalculatorService.swift:24-29`
  - Cache lookup:
    `ios/CryptoSavingsTracker/Services/BudgetCalculatorService.swift:331-338`
  - Recalculation after miss:
    `ios/CryptoSavingsTracker/Services/BudgetCalculatorService.swift:355-370`
  - Suggestion application:
    `ios/CryptoSavingsTracker/ViewModels/MonthlyPlanningViewModel.swift:455-481`
- **Minimal reproduction:** Generate a plan, change the same goal's target or
  deadline, and regenerate within five minutes with the same budget and
  currency. The old schedule is returned.
- **Regression target:** Mutate target, deadline, balance/allocation, and rate
  inputs between calls and assert that the second result reflects the new
  state.
- **Fix boundary:** Include a stable fingerprint of all plan inputs or
  invalidate the cache on every relevant mutation.

### APPLE-011 — Refresh changes a valid deposit suggestion to zero

- **Priority:** P2.
- **Evidence:** Source-proven.
- **User impact:** A new goal can initially show a useful daily deposit and then
  show zero after refresh.
- **Root cause:** Initialization uses the model's day-based
  `suggestedDailyDeposit`, but refresh replaces it with a legacy calculation
  based on `remainingDates`. Current persistence clears that retired reminder
  metadata, so the refresh path returns zero.
- **Code evidence:**
  - Initial value:
    `ios/CryptoSavingsTracker/ViewModels/GoalViewModel.swift:31-33`
  - Refresh overwrite:
    `ios/CryptoSavingsTracker/ViewModels/GoalViewModel.swift:64-72`
  - Empty-date behavior:
    `ios/CryptoSavingsTracker/ViewModels/GoalViewModel.swift:158-164`
  - Cleared legacy fields:
    `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:27-39`
  - Canonical day calculation:
    `ios/CryptoSavingsTracker/Models/Goal.swift:199-204`
- **Minimal reproduction:** Create a 1,000-unit goal due in ten days with no
  reminder metadata. Its initial suggestion is approximately 100 per day; call
  `refreshValues()` and it becomes zero.
- **Regression target:** Assert that refresh uses the canonical model
  calculation and preserves a positive, day-based suggestion.
- **Fix boundary:** Remove the duplicate legacy calculation and keep one source
  of truth for suggested deposits.

---

## Android findings

### ANDROID-001 — Execution progress mixes crypto units with goal currency

- **Priority:** P1.
- **Evidence:** Source-proven.
- **User impact:** Progress and completed history can label a crypto quantity as
  fiat, materially understating or overstating a contribution.
- **Root cause:** The calculator sums raw transaction and allocation amounts and
  compares them directly with `requiredAmount`, which is captured in the goal
  currency. It receives neither asset metadata nor exchange rates. Completion
  then persists the raw result in the snapshot currency, and UI labels it with
  that currency.
- **Code evidence:**
  - Raw accumulation:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/domain/usecase/execution/ExecutionProgressCalculator.kt:34-108`
  - Required amount and currency snapshot:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/domain/usecase/execution/StartExecutionUseCase.kt:77-100`
  - Persisted completion:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/domain/usecase/execution/CompleteExecutionUseCase.kt:47-68`
  - UI currency label:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/execution/components/GoalProgressCard.kt:95-99`
- **Minimal reproduction:** Before execution starts, persist an allocation
  history target for a BTC asset and a USD goal. Start execution, then deposit
  0.01 BTC. Progress and history record approximately `$0.01` instead of the
  converted USD value.
- **Regression target:** Use a fixed BTC-to-USD quote and assert conversion
  happens before comparison, display, and persistence.
- **Fix boundary:** Define a single valuation boundary for execution events and
  preserve both native quantity and converted snapshot value.

### ANDROID-002 — Balance routing ignores tokens and several supported chains

- **Priority:** P1.
- **Evidence:** Source-proven.
- **User impact:** Token balances can display the native network coin, while
  XRP, TRON, and Cardano can be sent to the wrong endpoint.
- **Root cause:** `fetchBalance` accepts `currency` but never uses it. It handles
  selected UTXO and Solana paths, then routes every unhandled chain to the
  native EVM endpoint. The app exposes tokens and non-EVM chains for which
  dedicated API methods already exist.
- **Code evidence:**
  - Ignored currency and fallback:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/data/repository/OnChainBalanceRepositoryImpl.kt:125-154`
  - Supported assets:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/domain/model/Asset.kt:87-123`
  - Token portfolio API:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/data/remote/api/TatumApi.kt:17-26`
  - Dedicated API methods:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/data/remote/api/TatumApi.kt:102-133`
- **Minimal reproduction:** Query USDT on an address holding 1,000 USDT and
  0.2 ETH. The repository can return 0.2 and label it USDT. Query XRP and
  observe the generic EVM fallback.
- **Regression target:** A fake API must verify Ethereum plus USDT uses a token
  path and XRP uses `getXrpBalance`, never `getEvmBalance`.
- **Fix boundary:** Route by both network family and asset contract, and reject
  unsupported combinations explicitly.

### ANDROID-003 — Goal reminders never request notification permission

- **Priority:** P1.
- **Evidence:** Source-proven.
- **User impact:** On a fresh Android install, a user can enable reminders but
  receives neither a permission prompt nor a notification.
- **Root cause:** The manifest declares `POST_NOTIFICATIONS`, but the app has no
  runtime permission request. The worker treats missing permission as success,
  while the goal form still presents an enabled reminder toggle.
- **Code evidence:**
  - Declaration:
    `android/app/src/main/AndroidManifest.xml:5-7`
  - Silent worker exit:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/work/GoalReminderWorker.kt:30-48`
  - Reminder toggle:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/goals/AddEditGoalScreen.kt:232-245`
- **Minimal reproduction:** On a fresh Android 13+ install, enable a reminder
  and trigger its worker. No permission request appears and no notification is
  delivered.
- **Regression target:** An instrumentation test should begin with permission
  denied and assert that enabling reminders launches the permission flow and
  exposes denial state.
- **Fix boundary:** Request permission at a user-explained moment and reflect
  denial in reminder state instead of silently reporting successful work.

### ANDROID-004 — Editing transaction metadata changes its timestamp

- **Priority:** P1.
- **Evidence:** Source-proven.
- **User impact:** Editing only a note or counterparty can move a transaction
  into or out of an execution window and retroactively change progress.
- **Root cause:** Loading an existing transaction retains only its `LocalDate`,
  discarding time of day. Saving assigns the current time for today's date and
  local midnight for older dates, regardless of which field changed.
- **Code evidence:**
  - Time discarded:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/transactions/EditTransactionViewModel.kt:70-89`
  - Timestamp regenerated:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/transactions/EditTransactionViewModel.kt:126-155`
- **Minimal reproduction:** Create a 09:00 transaction, start execution at
  12:00, then edit only its comment at 15:00. The transaction moves to 15:00
  and becomes eligible for that execution window.
- **Regression target:** With a fixed clock, edit only `comment` and assert that
  persisted `dateMillis` is byte-for-byte unchanged.
- **Fix boundary:** Preserve the original instant unless the user explicitly
  edits the transaction date or time.

### ANDROID-005 — Onboarding discards selected assets

- **Priority:** P2.
- **Evidence:** Source-proven.
- **User impact:** The onboarding flow promises to track selected currencies,
  but the Assets screen starts empty after completion.
- **Root cause:** Onboarding state records and toggles selected assets, but
  completion injects only `AddGoalUseCase`, creates the goal, and exits without
  writing any asset.
- **Code evidence:**
  - Selection state and dependency:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/onboarding/OnboardingViewModel.kt:130-163`
  - Toggle and completion:
    `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/onboarding/OnboardingViewModel.kt:231-266`
  - Product promise:
    `android/app/src/main/res/values/strings.xml:44-46`
- **Minimal reproduction:** Select BTC and ETH during onboarding, complete the
  flow, and open Assets. Neither selection was persisted.
- **Regression target:** Complete onboarding with selected assets and assert
  that the asset repository contains both records.
- **Fix boundary:** Persist selected assets transactionally with onboarding
  completion or remove the non-functional selection step.

---

## Remediation order

1. Restore the macOS build (`APPLE-001`) so the supported-platform test gate can
   run.
2. Correct unit and currency boundaries (`APPLE-003`, `APPLE-008`,
   `ANDROID-001`, `ANDROID-002`) before trusting displayed totals
   or execution completion.
3. Protect durable financial state (`APPLE-004`, `APPLE-009`, `APPLE-010`,
   `ANDROID-004`).
4. Restore blocked core flows (`APPLE-002`, `APPLE-005`, `APPLE-006`,
   `ANDROID-003`).
5. Resolve the remaining consistency gaps (`APPLE-007`, `APPLE-011`,
   `ANDROID-005`).

Each fix should first add the regression target described in its finding. Where
a fix changes stored units, lifecycle semantics, or cached data, it also needs
an explicit migration or invalidation decision.

---

## Verification log

| Check | Result |
|-------|--------|
| Android `:app:testDebugUnitTest` | Passed: 33 actionable tasks, all up to date |
| macOS targeted app build | Failed during compilation at the three `APPLE-001` call sites |
| iOS targeted XCTest run | Inconclusive: local CoreSimulator service disconnected |
| Source trace for all listed findings | Completed against the current working tree |

The iOS simulator interruption is recorded as an environment limitation, not as
an application defect. It must be rerun on a healthy CoreSimulator before using
this audit as a complete release gate.

---

## Exit criteria

The audit can be closed when:

- Every finding has a regression test that fails before its fix and passes
  afterward.
- The macOS target compiles and its targeted test suite passes.
- The full Apple simulator suite passes on a healthy CoreSimulator.
- Android unit and relevant instrumentation suites pass.
- Mixed-currency and token-unit scenarios use fixed, auditable rate fixtures.
- Lifecycle tests prove that hidden goals cannot retain allocations.
- Documentation and user-facing copy match the implemented archive and
  reminder behavior.

---

## Related documentation

- [Architecture](../ARCHITECTURE.md) - Apple application architecture and
  service boundaries
- [Android development plan](../ANDROID_DEVELOPMENT_PLAN.md) - Android scope
  and parity context
- [Contribution flow](../CONTRIBUTION_FLOW.md) - Change and review workflow
- [Documentation style guide](../STYLE_GUIDE.md) - Documentation conventions

---

*Last updated: 2026-07-25*
