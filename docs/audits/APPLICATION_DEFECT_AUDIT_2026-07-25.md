# Application defect audit — 2026-07-25

> Evidence-backed register of defects found in the Apple and Android applications

| Metadata | Value |
|----------|-------|
| Status | ✅ Closed — fixes implemented; Apple and Android verified |
| Last Updated | 2026-07-28 |
| Platform | Shared |
| Audience | All |
| Audited base revision | `40ec5f6c` |

---

## Table of contents

- [Document choice](#document-choice)
- [Executive summary](#executive-summary)
- [Scope and evidence](#scope-and-evidence)
- [External contract evidence](#external-contract-evidence)
- [Findings summary](#findings-summary)
- [Apple findings](#apple-findings)
- [Android findings](#android-findings)
- [Remediation order](#remediation-order)
- [Review follow-ups](#review-follow-ups)
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

The initial audit found 16 primary defects: one release blocker, 12 high-impact
defects, and three medium-impact defects. A later exhaustive whole-diff review
found zero Critical findings and 23 deduplicated Important defect packages,
including both variants of the original findings and newly proven failures.
All identified packages now have production corrections and behavior-level
regressions. Apple and Android closeout are current and green.

| Initial priority | Count | Meaning |
|------------------|-------|---------|
| P0 | 1 | A documented supported platform cannot compile |
| P1 | 12 | Financial correctness, persisted-data integrity, or a core user flow is broken |
| P2 | 3 | A secondary or platform-specific flow is materially misleading or incomplete |

| Final whole-diff severity | Count | Current state |
|---------------------------|-------|---------------|
| Critical | 0 | None found |
| Important | 23 packages | Implemented and verified |

The highest-risk cluster was financial correctness. Both applications contained
paths that compared, aggregated, labeled, or persisted values without
converting them to the required currency or unit. Those paths could show
plausible but materially wrong balances and progress.

Remediation posture:

- The 16 original findings and all 23 final review packages are implemented.
- The current Apple diff passed 896 tests with no failures or skips and a
  signing-disabled macOS build.
- The complete Android production/test patch relative to `origin/main` has
  SHA-256
  `aceb5df5e98267f086c351d0cd70ffd8421555570a99a30cd9af1e8d06e255fa`,
  and the final static review has no unresolved Critical or Important finding.
- The current Android diff passed 502 JVM tests and 48 instrumentation tests on
  API 36.1 with no failures or skips. Instrumentation compilation/assembly and
  the included Room migration regressions passed.
- Current Android lint passed with zero errors, 128 warnings, and two
  informational hints.

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

## External contract evidence

On-chain routing, pagination, balance units, and Polygon-native symbol behavior
were checked against the current primary vendor documentation:

- [Tatum V4 transaction history](https://docs.tatum.io/reference/gettransactionhistoryv4)
- [Tatum V4 transaction by hash](https://docs.tatum.io/reference/gettransactionblockchainsapi)
- [Tatum EVM transaction receipt RPC](https://docs.tatum.io/reference/rpc-ethereum-eth_gettransactionreceipt)
- [Ethereum JSON-RPC transaction receipt contract](https://ethereum.github.io/execution-apis/api/methods/eth_getTransactionReceipt/)
- [Tatum failed-transaction gas behavior](https://docs.tatum.io/docs/unconfirmed-and-dropped-transactions)
- [Tatum V4 wallet portfolio](https://docs.tatum.io/reference/getwalletportfoliov4)
- [Tatum V4 native balance](https://docs.tatum.io/reference/getbalanceblockchainsapi)
- [Tatum V4 UTXO transaction history](https://docs.tatum.io/reference/gettransactionhistoryutxosblockchainsapi)
- [Tatum V4 UTXO transaction detail](https://docs.tatum.io/reference/getutxoinfoblockchainsapi)
- [Tatum TRON account history](https://docs.tatum.io/reference/tronaccounttx)
- [Tatum Solana `getSignaturesForAddress`](https://docs.tatum.io/reference/rpc-solana-getsignaturesforaddress)
- [Tatum V3 Litecoin address history](https://docs.tatum.io/reference/ltcgettxbyaddress)
- [Tatum V3 Bitcoin Cash address history](https://docs.tatum.io/reference/bchgettxbyaddress)
- [Tatum V3 Dogecoin address history](https://docs.tatum.io/reference/dogegettxbyaddress)
- [Tatum V3-to-V4 response migration observations](https://docs.tatum.io/docs/v3-to-v4-blockchains-api-migration-observations)
- [Polygon MATIC-to-POL migration](https://docs.polygon.technology/pos/concepts/tokens/matic-to-pol)
- [Polygon POL token reference](https://docs.polygon.technology/pos/concepts/tokens/pol)
- [Android WorkManager periodic replacement policies](https://developer.android.com/reference/androidx/work/ExistingPeriodicWorkPolicy)

The Tatum V4 transaction and UTXO list endpoints document a page size of 1–50
plus offset pagination; TRON and Solana instead expose their documented
chain-specific continuation values. The migration notes identify UTXO
response-field changes that must be decoded explicitly. The Polygon references
identify POL as the Polygon PoS native gas and staking token and document the
native MATIC-to-POL transition as 1:1. WorkManager documents that `UPDATE` lets
an already-running periodic worker continue with its old request state, whereas
`CANCEL_AND_REENQUEUE` creates a replacement occurrence after cancelling the
old one.

---

## Findings summary

| ID | Priority | Platform | Area | Evidence | Resolution |
|----|----------|----------|------|----------|------------|
| APPLE-001 | P0 | macOS | Build compatibility | Build-reproduced | Fixed |
| APPLE-002 | P1 | iOS | Navigation | Source-proven | Fixed |
| APPLE-003 | P1 | iOS | Currency aggregation | Source-proven | Fixed |
| APPLE-004 | P1 | Apple | Allocation lifecycle | Source-proven | Fixed |
| APPLE-005 | P1 | iOS | Localized money input | Source-proven | Fixed |
| APPLE-006 | P1 | iOS | Goal archival | Source-proven | Fixed |
| APPLE-007 | P2 | macOS | Goal filtering | Source-proven | Fixed |
| APPLE-008 | P1 | Apple | On-chain balances | Source-proven | Fixed |
| APPLE-009 | P1 | Apple | Transaction import | Source-proven | Fixed |
| APPLE-010 | P1 | Apple | Planning cache | Source-proven | Fixed |
| APPLE-011 | P2 | Apple | Deposit suggestion | Source-proven | Fixed |
| ANDROID-001 | P1 | Android | Execution progress | Source-proven | Fixed |
| ANDROID-002 | P1 | Android | On-chain balances | Source-proven | Fixed |
| ANDROID-003 | P1 | Android | Reminder permission | Source-proven | Fixed |
| ANDROID-004 | P1 | Android | Transaction editing | Source-proven | Fixed |
| ANDROID-005 | P2 | Android | Onboarding | Source-proven | Fixed |

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

## Review follow-ups

Independent review remains part of the remediation loop. The exhaustive final
sweep produced the following closeout scope; status may become **Verified**
only after its behavior regression and the final stable-diff review pass.

| ID | Platform | Important defect package | Status |
|----|----------|--------------------------|--------|
| FINAL-001 | Apple | Provider correction or enrichment can duplicate one durable movement instead of reconciling it. | Verified |
| FINAL-002 | Apple | Monthly requirements can be saved from a mixed financial snapshot across suspension points. | Verified |
| FINAL-003 | Apple | Plan/execution membership can retain inactive goals, duplicate roll-forward, or resurrect a removed goal at close. | Verified |
| FINAL-004 | Shared | Planning month, payment-date, storage, and worker timezone semantics disagree at month boundaries. | Verified |
| FINAL-005 | Apple | Start and undo compose multiple saves without one rollback-safe persistence boundary. | Verified |
| FINAL-006 | Apple | Missing execution FX becomes omitted or zero progress, and failed completion can leave a pending closed mutation. | Verified |
| FINAL-007 | Shared | Overall execution progress raw-sums incompatible currencies and can display an incorrect currency label. | Verified |
| FINAL-008 | Apple | Canonically duplicate addressed assets can double balances, totals, and imported history. | Verified |
| FINAL-009 | Apple | Asset deletion can destroy active or still-undoable execution evidence. | Verified |
| FINAL-010 | Apple | Goal rows promote partial or unavailable financial totals as a successful authoritative zero. | Verified |
| FINAL-011 | Apple | Onboarding creation is not restart-safe after commit succeeds before the completion flag. | Verified |
| FINAL-012 | Apple | Real exchange-rate stale refresh can synchronously re-enter its own queue and deadlock. | Verified |
| FINAL-013 | Apple | Cloud sync dedup folds case-sensitive wallets and can discard allocation value. | Verified |
| FINAL-014 | Android | Asset provider identity can change during reversible execution or a suspended refresh. | Verified |
| FINAL-015 | Android | Provider identity and reconciliation do not survive mutable corrections or optional event-index enrichment. | Verified |
| FINAL-016 | Android | Equivalent BTC, LTC, or BCH address aliases can persist as separate financial assets. | Verified |
| FINAL-017 | Android | Historical-only execution assets can be omitted from the immutable rate scope. | Verified |
| FINAL-018 | Android | Start can commit a stale, internally inconsistent goal/plan/progress snapshot. | Verified |
| FINAL-019 | Android | Missing, stale, or malformed on-chain balance data can become authoritative zero. | Verified |
| FINAL-020 | Android | Automation workers report success when Start or Complete returns a domain failure, preventing retry. | Verified |
| FINAL-021 | Android | Downstream financial and presentation consumers can promote missing, stale, malformed, or identity-mismatched on-chain balances to authoritative zero. | Verified |
| FINAL-022 | Apple | Family Sharing can publish active or fresh goal progress from incomplete FX/allocation inputs, miss material partial-rate drift, or republish after sharing is revoked. | Verified |
| FINAL-023 | Android | Monthly planning can treat a failed FX conversion as one-to-one, retain a stale total, or persist a false successful zero budget. | Verified |

Earlier review variants are retained below as historical evidence. Their
presence does not close the final packages above.

| ID | Related finding | Review defect and resolution |
|----|-----------------|------------------------------|
| RF-APPLE-001 | APPLE-004, APPLE-006 | Lifecycle save failures previously relied on context-wide rollback or incomplete restoration. Operation-owned snapshots now restore only fields and deleted relationships touched by the failed action, preserve unrelated dirty/inserted models, and defer notifications until persistence succeeds. |
| RF-APPLE-002 | APPLE-003 | Dashboard refresh identity omitted changing financial inputs. Full goal/allocation/transaction fingerprints, exchange-rate generation, calendar-day rollover, and a generation guard prevent stale async commits. |
| RF-APPLE-003 | APPLE-003 | Dashboard rate notifications could mutate view state off the main run loop, and background day rollover was missed. Notifications are delivered on the main run loop and active-scene/day-change events advance the refresh identity. |
| RF-APPLE-004 | APPLE-003 | Recent activity used unsigned or unconverted values and treated conversion failure as no activity. The seven-day trend now preserves signs, converts every currency, and distinguishes unavailable data from a genuinely empty result. |
| RF-APPLE-005 | APPLE-003 | Per-goal calculation returned only a partial `Double` after a balance or FX failure. Completeness now propagates through `GoalViewModel` and `GoalCalculationService`; Dashboard withholds incomplete goal and portfolio totals rather than presenting them as authoritative. |
| RF-APPLE-006 | APPLE-008 | Symbol-only EVM balance matching accepted counterfeit tokens, native-only routes accepted mismatched symbols, and obsolete chain identifiers were guessed. Routing now validates before cache access, matches canonical contracts, uses documented current chain IDs, fails closed for unsupported networks, and invalidates prior balance-cache namespaces. |
| RF-APPLE-007 | APPLE-008 | UTXO balance requests used `Authorization: Bearer` against endpoints requiring `x-api-key`. BTC, LTC, BCH, and DOGE now use the v3 request builder and have request-contract tests. |
| RF-APPLE-008 | APPLE-008 | Wallet portfolio lookup stopped after the first 50 fungible tokens. It now follows offset pagination until the canonical contract is found or the response is exhausted; a defensive page limit returns unavailable instead of a false zero. |
| RF-APPLE-009 | APPLE-008 | Polygon PoS still labeled its native asset MATIC. New tracking uses POL and the `polygon-mainnet` route, while persisted MATIC remains an explicit 1:1-compatible native alias; balance caches were invalidated for the semantic change. |
| RF-APPLE-010 | APPLE-008 | Add Asset allowed an addressed symbol/network pair that balance routing would always reject. Both the form and persistence service now validate the shared route and return an actionable manual-tracking alternative before writing. |
| RF-APPLE-011 | APPLE-009 | Unfiltered EVM history could import native, NFT, or unrelated-token activity as the selected asset, while hash-scoped identities collapsed distinct movements. Requests now specify native or fungible plus canonical contract, decoded events are validated again locally, and movement-scoped identities include the available transaction index plus normalized movement fields. A legacy hash row is upgraded only for exactly one valid canonical movement and exactly one matching legacy row; ambiguous or unmatched legacy rows remain intact, and an exact upgrade preserves user-authored comments, counterparties, sources, and model identity. |
| RF-APPLE-012 | APPLE-004 | Cancel, finish, and delete did not dirty the Family Share projection. Each successful lifecycle mutation now emits exactly one goal-mutation event with the affected goal ID; failed persistence emits none. |
| RF-APPLE-013 | APPLE-002 | The goal form's container accessibility identifier hid the child Save button from assistive and UI-test lookup, while routing coverage still asserted a removed widget flow. The container identifier was removed, deterministic UI-test launch state was added, current target semantics were asserted, and the regression now exercises the real Planning add-goal destination. |
| RF-APPLE-014 | APPLE-009 | Chain-specific history pagination stopped early or reused the wrong continuation model. UTXO and Cardano now advance by returned-count offsets, TRON follows the provider's `next` cursor, Solana follows `before`, and XRP accepts only bounded, serializable markers. Every flow rejects cycles, conflicting overlap, and safety-cap exhaustion instead of returning a partial success. |
| RF-APPLE-015 | APPLE-009 | Provider decoding treated malformed payloads, missing authoritative fields, and valid empty history as the same result. Required movement fields and timestamps now fail closed, Solana detail batches are all-or-fail, valid-empty responses remain authoritative, and numeric conversion rejects non-finite or out-of-range values. |
| RF-APPLE-016 | APPLE-009 | Mutable provider fields participated in movement identity while some chain-specific identifiers were normalized with EVM rules. Stable identity now uses immutable discriminators, folds only identifiers whose chain contract is case-insensitive, preserves case-sensitive Solana values, and correlates UTXO inputs through `txid` rather than witness hashes. |
| RF-APPLE-017 | APPLE-009 | Refresh failures could replace retained history with an empty list or display fetched rows that failed to persist. Provider and importer errors now preserve the last durable rows, expose a retryable error, and publish newly fetched history only after the atomic import succeeds. |
| RF-APPLE-018 | APPLE-010 | Applied-budget identity omitted persisted flex/custom outputs, payment day, exact FX inputs, and source-state changes, while including ephemeral IDs and timestamps. The canonical fingerprint now covers every financial input and output that changes the result, excludes ephemeral values, and invalidates synchronously on relevant mutations. |
| RF-APPLE-019 | APPLE-010 | Planning refresh and transitions could partially save a batch or reuse an expired/degraded preview. Calculation, get-or-create, flex, apply, and lifecycle transitions now use immutable snapshots plus operation-owned rollback; incomplete balances, missing rates, stale TTLs, or source drift prevent every write. |
| RF-APPLE-020 | APPLE-004, APPLE-006 | Durable mutations could commit unrelated drafts from a shared SwiftData context, including work created after a deferred allocation sync yielded. Mutation entry points reject unrelated pending changes, pending inserts are cancelled without a save, and deferred plan synchronization uses its own autosave-disabled `ModelContext`. |
| RF-APPLE-021 | APPLE-006 | Goal callers cleared retired reminder fields and modified timestamps before the mutation service captured its rollback snapshot, and generic form errors hid clean-context recovery guidance. The service now owns cleanup and timestamps inside its persistence boundary; Add Transaction, Add Goal, and Edit Goal preserve actionable validation guidance and remain retryable without dismissing. |
| RF-APPLE-022 | APPLE-002, APPLE-006, APPLE-007 | Archived-goal restore and archive failure handling were incomplete across Apple hosts. The macOS sidebar exposes archived goals with retryable restore, iOS stays in the editor after an archive failure, and a deterministic UI regression proves the retry succeeds before dismissal. |
| RF-APPLE-023 | APPLE-004, APPLE-006, APPLE-009, APPLE-010 | Successful direct and transactional SwiftData saves could still commit another screen's pending draft. Every affected save boundary now declares its operation-owned models, rejects unrelated dirty/inserted/deleted state before mutation, and leaves those drafts pending and non-durable. |
| RF-APPLE-024 | APPLE-008 | The TRON TRC10 decoder accepted only a legacy dictionary or an empty array, so the provider's non-empty `{key,value}` array could invalidate the complete TRX response. It now accepts both documented payload families, validates keys and finite non-negative numeric values strictly, rejects duplicates, and preserves TRX/TRC20 balances in mixed responses. |
| RF-APPLE-025 | APPLE-009 | EVM identity omitted the provider's `logIndex`, so distinct same-hash event logs with otherwise equal fields could collapse. The optional discriminator now participates in provider, movement, legacy-upgrade, and canonical-content identity while nil preserves the previous byte-for-byte identity. |
| RF-APPLE-026 | APPLE-009 | A global legacy hash collision, including a row owned by another asset, could abort a valid scoped canonical import. Hash-only upgrade is now allowed only for one current-asset legacy row and one canonical movement; ambiguous or cross-asset legacy history remains quarantined without blocking the canonical row. |
| RF-APPLE-027 | APPLE-004, APPLE-009, APPLE-010 | Save-isolation preflight ran before knowing whether an import or plan deletion would persist anything. Empty/exact-existing imports now remain read-only, and pending-only plan deletion cancels the insert without preflight or save; mutating and durable paths retain the guarded transactional boundary. |
| RF-APPLE-028 | APPLE-010 | Cancelling a pending plan shadow before a later validation failure could detach it from SwiftData and lose its execution-record relationship, breaking retryability. Both planning entry points now capture separate candidate and durable snapshots, allow the union of both graphs (including distinct execution records), delete the exact model objects instead of a broad predicate, and restore attachment plus relationship state through an undo-isolated resolver boundary. Regressions prove rollback after resolver or save failure and a successful same-context retry without unrelated saves or duplicate notifications. |
| RF-APPLE-029 | APPLE-009 | Transaction refresh views published the raw provider array even when import validation rejected wrong-route, counterfeit, pending-only, or cross-asset movements. Before any mutation, the importer performs a candidate-scoped durable lookup constrained to `.onChain` and the target asset, then returns only the accepted durable provider set in provider order. No throwing lookup remains after commit, and both asset refresh paths publish and notify only after persistence succeeds. |
| RF-ANDROID-001 | ANDROID-001 | Execution progress lacked a durable rate boundary across restart and undo. Room schema 6 stores immutable per-execution asset rates and deterministic legacy backfill for active or still-undoable records. |
| RF-ANDROID-002 | ANDROID-001 | Rate capture and later allocation/currency mutations had time-of-check/time-of-use races. Start/backfill recheck an exact scope fingerprint at commit, while allocation validation plus write and asset-currency guards share the same Room transaction boundary. |
| RF-ANDROID-003 | ANDROID-002 | Native EVM balances used a generic v3 route and assumed 18 decimals; several V4 chain IDs were obsolete. Native balances now use the documented human-readable V4 endpoint, canonical tokens use wallet portfolio, AVAX uses `avax-mainnet`, and unsupported FTM/unknown routes fail before cache or API access. |
| RF-ANDROID-004 | ANDROID-002 | Android EVM transaction history was unfiltered and fell back to guessed legacy routes. It now uses current chain IDs, native/fungible plus canonical-contract filters, strict local validation, scoped event identities, and a versioned refresh cache. |
| RF-ANDROID-005 | ANDROID-003 | Permission could be revoked after the editor check or before worker delivery. Resume and Save reread permission, and the worker handles the notification-time security race without crashing or persisting an undeliverable enabled state. |
| RF-ANDROID-006 | ANDROID-005 | Rapid repeated onboarding completion could duplicate goals/assets or callbacks. A synchronous in-flight guard makes persistence and completion single-shot while leaving a failed attempt retryable. |
| RF-ANDROID-007 | ANDROID-001 | Lifecycle preconditions were read outside the write transaction, stale Start could replace a closed record, and racing complete/undo/start operations could produce contradictory records. All transition preconditions and writes are now serialized in one Room boundary and use conditional state changes rather than destructive replacement. |
| RF-ANDROID-008 | ANDROID-001 | Hard-deleting an asset or goal could cascade away transactions, allocation history, snapshots, rates, and completion evidence required by an active or undoable execution. Deletion now fails closed while execution evidence still depends on the model. |
| RF-ANDROID-009 | ANDROID-001 | Execution start and legacy backfill captured rates for every asset, so an unrelated unsupported or temporarily unavailable asset could block the month. The immutable rate scope now contains only assets allocated to the execution's snapshotted goals; later allocation of an unsnapshotted asset remains rejected. |
| RF-ANDROID-010 | ANDROID-002 | Canonical token balance lookup inspected only the first wallet-portfolio page. It now follows documented offset pagination until the contract is found or results are exhausted, and returns unavailable rather than a false zero at its defensive cap. |
| RF-ANDROID-011 | ANDROID-002 | EVM refresh always reread only the newest page, permanently missing older new movements after a burst. History import now follows documented offset pagination to exhaustion with a bounded fail-closed safety limit. |
| RF-ANDROID-012 | ANDROID-002 | Same-hash movements with otherwise identical fields could collapse, and the first API-ordered movement could claim an ambiguous legacy hash row. Canonical identity now uses the API movement discriminator when available, and legacy upgrade requires exactly one unique valid canonical movement plus exactly one legacy row; ambiguous history is preserved. |
| RF-ANDROID-013 | ANDROID-003 | Revoked notification permission left the persisted reminder enabled, and the permission-grant callback could race the editor's stale local state. The worker disables and unschedules an undeliverable reminder, while the grant callback updates local permission state before enabling it. |
| RF-ANDROID-014 | ANDROID-002 | Add and Update Asset could persist an addressed currency/network pair that balance and history routing reject. A shared validator now rejects unsupported addressed routes before any write, while deliberate address-free manual tracking remains available. |
| RF-ANDROID-015 | ANDROID-005 | The in-memory onboarding guard did not survive process death after goal insertion or a post-insert scheduling error. Template-goal creation now has a restart-safe deterministic identity and retry reconciliation, preserving successful prior writes without creating a duplicate. |
| RF-ANDROID-016 | ANDROID-002 | Database uniqueness on address alone prevented tracking native and canonical token assets for one EVM wallet. Room schema 7 replaces it with normalized address/network/currency identity, preserving legacy rows while allowing distinct supported assets on the same address. |
| RF-ANDROID-017 | ANDROID-002 | QUICK routing accepted the retired token contract and could count quarantined legacy movements. Balance, history, migration normalization, and execution progress now share the current canonical contract; legacy QUICK rows remain preserved but excluded until a canonical refresh can reconcile them safely. |
| RF-ANDROID-018 | ANDROID-002, ANDROID-004 | UTXO import guessed missing input values and could partially persist a page after a prevout failure. Parent lookups validate the requested `txid`, coinbase inputs bypass prevout lookup, address normalization follows chain-specific case rules, and the whole Room import transaction aborts on lookup, identity, or persistence failure. |
| RF-ANDROID-019 | ANDROID-002 | Provider pagination and local cache semantics could turn truncation, overlap corrections, or a provider failure into a plausible empty success. Offset imports run to exhaustion with bounded caps, conflicting overlaps fail closed, valid-empty refreshes are authoritative, and failures retain durable data while exposing retry state. |
| RF-ANDROID-020 | ANDROID-001, ANDROID-004 | Repository mutations split preconditions, graph writes, and lifecycle evidence across separate Room transactions. Allocation, goal, asset, transaction, execution, and undo operations now expose transactional repository boundaries so failures cannot leave partially updated graphs or contradictory execution state. |
| RF-ANDROID-021 | ANDROID-003 | Reminder delivery could target a missing or obsolete notification channel and permission recovery could re-enable stale UI state. Channel creation, permission rereads, persisted-disable behavior, worker cancellation, and editor callbacks now form one deterministic recovery contract. |
| RF-ANDROID-022 | ANDROID-005 | Onboarding completion discarded selected asset choices and replaced persistence failures with generic completion behavior. Selected assets now cross the ViewModel/use-case boundary exactly once, persisted errors keep onboarding active with retry guidance, and rapid/restarted completion remains idempotent. |
| RF-APPLE-030 | FINAL-001 | Provider corrections and optional movement enrichment now reconcile to the durable model identity instead of inserting a second movement. Ambiguous legacy aliases, cross-asset matches, or disappearing discriminators fail closed before mutation. |
| RF-APPLE-031 | FINAL-002 | Monthly plan creation/update and Budget Apply carry immutable balance-cache and exchange-rate evidence across every suspension point. The service revalidates immediately before commit, while the ViewModel rejects a superseded amount, currency, month, payment day, plan set, or preview request without stamping stale settings. |
| RF-APPLE-032 | FINAL-003, FINAL-005, FINAL-006, FINAL-007 | Execution membership, start, close, and undo now use active snapshotted goals, frozen rate evidence, and operation-owned rollback. Missing FX or incomplete progress blocks the transition instead of becoming zero or a partial closed record. |
| RF-APPLE-033 | FINAL-004 | Planning month and payment-date calculations share strict calendar contracts, and malformed labels fail closed. Boundary regressions cover roll-forward, current-month closure, and next-month selection. |
| RF-APPLE-034 | FINAL-008, FINAL-009, FINAL-010, FINAL-011, FINAL-012, FINAL-013 | Addressed-asset identity is chain-aware, destructive lifecycle operations retain reversible execution evidence, financial UI state carries completeness, onboarding is restart-safe, exchange-rate refresh avoids queue re-entry, and CloudKit dedup preserves case-sensitive identities plus allocation value. |
| RF-APPLE-035 | FINAL-022 | Family Sharing projection construction now rejects incomplete balance, allocation, or FX inputs, evaluates material drift from the merged rate snapshot, retains last-good data, and fences late/in-flight publication after revoke. |
| RF-APPLE-036 | APPLE-004, APPLE-009 | Automatic allocation histories now persist `sourceTransactionId` plus the exact pre-mutation target. Deletion, provider correction, chronology backfill, and duplicate repair replay linked changes deterministically; missing or conflicting provenance stops without changing the store. |
| RF-APPLE-037 | APPLE-009 | Local Bridge canonical encoding and snapshot schema were advanced to `bridge-snapshot-v2` / schema 2 so allocation provenance round-trips through export, review, import, and apply. Version 1 is rejected rather than silently dropping financial replay evidence. |
| RF-ANDROID-023 | FINAL-014, FINAL-015 | Provider identity is captured and rechecked across refresh and reversible execution. Same-batch enrichment, optional event indices, corrections, EVM receipt status, and gas evidence reconcile deterministically or fail before Room writes. |
| RF-ANDROID-024 | FINAL-016 | BTC, LTC, and BCH address aliases use chain-specific canonical identities in validation, migration, persistence, cache, and provider history; case-sensitive address families are preserved. |
| RF-ANDROID-025 | FINAL-017, FINAL-018 | Execution rate scope includes historically relevant assets, and Start carries a complete goal/plan/allocation/rate fingerprint through the Room transaction. Any source drift prevents the state transition. |
| RF-ANDROID-026 | FINAL-019, FINAL-021 | On-chain balances carry freshness, provider-identity, and completeness evidence through repositories and presentation. Missing, malformed, stale, or mismatched data remains unavailable and cannot be promoted to an authoritative zero. |
| RF-ANDROID-027 | FINAL-020 | Automation workers map Start/Complete domain failures to retry or explicit terminal outcomes instead of reporting a false WorkManager success. |
| RF-ANDROID-028 | FINAL-004, FINAL-023 | UTC month boundaries, settings snapshots, FX conversion, budget validation, and latest-request-wins publication now form one fail-closed planning contract. Missing rates or stale inputs cannot persist a false successful plan. |

These rows are review variants of the 16 primary findings, not silently folded
into their original evidence.

---

## Verification log

| Evidence scope | Check | Result |
|----------------|-------|--------|
| Current Apple diff | Full unit/integration suite | Passed: 896/896 on iPhone 17 Pro simulator; no failures or skips |
| Current Apple diff | Budget Apply RED/GREEN | RED reproduced two failures; GREEN passed 41/41 |
| Current Apple diff | Provenance, bridge, dedup, provider-correction, and financial-race regressions | Passed: 106/106 |
| Current Apple diff | Budget sheet source/UX contracts after final formatting fix | Passed: 20/20 |
| Current Apple diff | macOS app build | Passed with code signing disabled |
| Current Android diff | Complete production/test patch identity relative to `origin/main` | SHA-256 `aceb5df5e98267f086c351d0cd70ffd8421555570a99a30cd9af1e8d06e255fa` |
| Current Android diff | Static whole-diff review | Zero unresolved Critical or Important findings |
| Current Android diff | JVM suite | Passed: 502/502; no failures or skips |
| Current Android diff | Test compilation and instrumentation APK assembly | Passed |
| Current Android diff | Instrumentation suite | Passed: 48/48 on API 36.1; no failures or skips |
| Current Android diff | Room migrations | Current 1-to-7 and focused 5-to-6/6-to-7 migration regressions passed in the instrumentation suite |
| Current Android diff | Lint | Passed with zero errors; 128 warnings and two informational hints |
| Historical Android artifact, 2026-07-27 | JVM suite | Passed: 456/456; no failures or skips |
| Historical Android artifact, 2026-07-27 | Instrumentation suite | Passed: 46/46 on API 36.1 |
| Historical Android artifact, 2026-07-27 | Room migrations | Direct 5-to-6, direct 6-to-7, and complete 1-to-7 paths passed |
| Historical Android artifact, 2026-07-27 | Lint | Zero errors; 127 warnings and two informational hints |
| Current stable source | Final review | Found one budget-text normalization race, fixed it, and found no remaining Critical or Important issue |

---

## Exit criteria

The audit is closed because:

- [x] Every finding has a behavior-level regression that passed against the
  current platform diff.
- [x] The macOS target compiles with signing disabled.
- [x] The Apple unit suite passes on a healthy CoreSimulator.
- [x] Focused Apple UI regressions pass.
- [x] Android unit, test-compilation, instrumentation, migration, and lint
  gates pass against the current Android diff.
- [x] Mixed-currency and token-unit scenarios use deterministic rate fixtures.
- [x] Lifecycle tests prove hidden goals cannot retain allocations.
- [x] Documentation and user-facing archive/reminder behavior agree after the
  final review findings are recorded.
- [x] Stable-diff source review has no unresolved Critical or Important
  finding.

---

## Related documentation

- [Architecture](../ARCHITECTURE.md) - Apple application architecture and
  service boundaries
- [Android development plan](../ANDROID_DEVELOPMENT_PLAN.md) - Android scope
  and parity context
- [Remediation implementation plan](../superpowers/plans/2026-07-25-application-defect-remediation.md) -
  active implementation record
- [Contribution flow](../CONTRIBUTION_FLOW.md) - Change and review workflow
- [Documentation style guide](../STYLE_GUIDE.md) - Documentation conventions

---

*Last updated: 2026-07-28*
