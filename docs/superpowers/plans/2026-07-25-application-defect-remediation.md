# Application defect remediation implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:test-driven-development for every production change. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Status:** Implementation complete on 2026-07-28; closeout blocked only by
the current Android Gradle rerun.

**Audit:** [Application defect audit — 2026-07-25](../../audits/APPLICATION_DEFECT_AUDIT_2026-07-25.md).

**Goal:** Resolve the 16 initial findings plus every defect in the final
23-package whole-diff review, and protect each correction with a behavior-level
regression test.

**Architecture:** Keep fixes inside existing Apple MVVM/service boundaries and
Android domain/repository/ViewModel boundaries. Introduce small pure helpers
only where external APIs or SwiftUI/Compose surfaces make direct unit testing
impractical. Preserve native quantities and converted monetary values as
different data until an explicit valuation boundary.

**Tech Stack:** Swift 5+, SwiftUI, SwiftData, XCTest/Swift Testing, Kotlin,
Jetpack Compose, Room, JUnit, Gradle.

## Global constraints

- Never disable, skip, or comment out a failing test.
- Never commit API keys or copy `local.properties`.
- Do not modify the pre-existing design-system changes in the primary checkout.
- Do not modify `ios/CryptoSavingsTracker.xcodeproj/project.pbxproj`; append
  tests to existing files when possible.
- Every production fix must follow RED, GREEN, REFACTOR in that order.
- Tests must use deterministic clocks, exchange rates, model containers, and
  API fakes; no network calls are allowed.
- Keep Apple and Android behavior consistent where the same financial invariant
  exists.

---

### Task 1: Apple build and domain correctness

**Findings:** APPLE-001, APPLE-008, APPLE-009, APPLE-010, APPLE-011.

**Files:**

- Modify:
  `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift`
- Modify: `ios/CryptoSavingsTracker/Services/BalanceService.swift`
- Modify: `ios/CryptoSavingsTracker/Services/TatumModels.swift`
- Modify:
  `ios/CryptoSavingsTracker/Services/OnChainTransactionImportService.swift`
- Modify:
  `ios/CryptoSavingsTracker/Services/BudgetCalculatorService.swift`
- Modify: `ios/CryptoSavingsTracker/ViewModels/GoalViewModel.swift`
- Test:
  `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareRolloutTests.swift`
- Test: `ios/CryptoSavingsTrackerTests/BalanceStateTests.swift`
- Test: `ios/CryptoSavingsTrackerTests/TatumTransactionParsingTests.swift`
- Test: `ios/CryptoSavingsTrackerTests/BudgetCalculatorServiceTests.swift`
- Test: `ios/CryptoSavingsTrackerTests/GoalCurrentTotalTests.swift`

**Interfaces:**

- `FamilyShareInvitationMetadataSnapshot.init(metadata:)` must compile wherever
  CloudKit is available, independently of UIKit presentation.
- Tatum raw `denominatedBalance` must always be divided by `10^decimals`; no
  magnitude heuristic is permitted.
- Transaction subtypes `incoming` and `outgoing` must map to positive and
  negative persisted amounts before address fallback.
- Budget cache identity must change when target, deadline, allocation/current
  total, or rate inputs change.
- `GoalViewModel.refreshValues()` must use `Goal.suggestedDailyDeposit`.

- [x] Write one failing test/build check for each invariant above.
- [x] Run each targeted test and confirm the expected old behavior fails.
- [x] Implement the minimum production correction for each failing test.
- [x] Re-run every targeted test until all pass.
- [x] Build the app scheme for macOS with signing disabled.
- [x] Run the Apple unit suite on an available iOS simulator.

Targeted commands:

```bash
xcodebuild -project ios/CryptoSavingsTracker.xcodeproj \
  -scheme CryptoSavingsTracker -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

```bash
xcodebuild -project ios/CryptoSavingsTracker.xcodeproj \
  -scheme CryptoSavingsTrackerTests \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test
```

---

### Task 2: Apple navigation, lifecycle, and localized input

**Findings:** APPLE-002, APPLE-003, APPLE-004, APPLE-005, APPLE-006,
APPLE-007.

**Files:**

- Modify: `ios/CryptoSavingsTracker/Views/ContentView.swift`
- Modify: `ios/CryptoSavingsTracker/Views/DashboardView.swift`
- Modify: `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift`
- Modify: `ios/CryptoSavingsTracker/Services/GoalLifecycleService.swift`
- Modify: `ios/CryptoSavingsTracker/Services/AllocationService.swift`
- Modify: `ios/CryptoSavingsTracker/Views/AddGoalView.swift`
- Modify: `ios/CryptoSavingsTracker/Views/AddTransactionView.swift`
- Modify: `ios/CryptoSavingsTracker/Views/Goals/GoalsListContainer.swift`
- Modify:
  `ios/CryptoSavingsTracker/Views/Goals/GoalsSidebarContainer.swift`
- Modify: `ios/CryptoSavingsTracker/Views/Components/GoalsSidebarView.swift`
- Test: `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift`
- Test: `ios/CryptoSavingsTrackerTests/GoalLifecycleServiceTests.swift`
- Test: `ios/CryptoSavingsTrackerTests/MoneyInputParserTests.swift`
- Test: `ios/CryptoSavingsTrackerTests/PersistenceMutationServicesTests.swift`
- Test: `ios/CryptoSavingsTrackerTests/GoalRepositoryTests.swift`

**Interfaces:**

- Dashboard and Planning tabs must each have one explicit `NavigationStack`.
- Dashboard aggregation must convert every goal total to
  `mvp.settings.displayCurrency` before summing and formatting.
- Cancellation/deletion must remove allocations atomically even when the
  remaining asset allocation exceeds its newest balance.
- Goal and transaction forms must parse current-locale decimal separators via
  `MoneyInputParser`.
- Archived goals must have a user-facing list and restore action.
- macOS sidebar queries and post-delete selection must include active goals
  only.

- [x] Write failing contract/unit tests for the six findings.
- [x] Confirm failures name missing navigation, wrong conversion, retained
  allocation, rejected comma decimal, absent restore surface, and inactive
  sidebar rows respectively.
- [x] Implement the minimum production correction for each behavior.
- [x] Re-run the targeted tests after every correction.
- [x] Run all Apple unit tests and the relevant UI tests when CoreSimulator is
  healthy.

---

### Task 3: Android financial and persistence correctness

**Findings:** ANDROID-001, ANDROID-002, ANDROID-004.

**Files:**

- Modify:
  `android/app/src/main/java/com/xax/CryptoSavingsTracker/domain/usecase/execution/ExecutionProgressCalculator.kt`
- Modify:
  `android/app/src/main/java/com/xax/CryptoSavingsTracker/data/repository/OnChainBalanceRepositoryImpl.kt`
- Modify:
  `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/transactions/EditTransactionViewModel.kt`
- Test:
  `android/app/src/test/java/com/xax/CryptoSavingsTracker/domain/usecase/execution/ExecutionProgressCalculatorTest.kt`
- Test:
  `android/app/src/test/java/com/xax/CryptoSavingsTracker/presentation/assets/AssetBalanceCalculatorTest.kt`
- Test:
  `android/app/src/test/java/com/xax/CryptoSavingsTracker/presentation/transactions/EditTransactionViewModelTest.kt`

**Interfaces:**

- Execution progress must convert each native asset delta to snapshot currency
  using an explicit rate captured for the execution window.
- Balance routing must select by chain and currency/contract: EVM tokens use
  wallet portfolio, XRP uses XRP, TRON uses TRON, and Cardano uses Cardano.
- Editing metadata must preserve the original `dateMillis` unless the user
  changes the date.

- [x] Write failing unit tests for BTC-to-USD progress, token/chain routing, and
  metadata-only timestamp preservation.
- [x] Verify each test fails against the current implementation for the audited
  reason.
- [x] Implement the smallest model/repository/ViewModel changes that pass.
- [x] Run the three targeted test classes.

---

### Task 4: Android reminders and onboarding persistence

**Findings:** ANDROID-003, ANDROID-005.

**Files:**

- Modify:
  `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/goals/AddEditGoalScreen.kt`
- Modify:
  `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/onboarding/OnboardingViewModel.kt`
- Test:
  `android/app/src/test/java/com/xax/CryptoSavingsTracker/presentation/onboarding/OnboardingViewModelTest.kt`
- Test:
  `android/app/src/androidTest/java/com/xax/CryptoSavingsTracker/presentation/goals/GoalReminderPermissionTest.kt`

**Interfaces:**

- Enabling reminders on Android 13+ must request `POST_NOTIFICATIONS` and expose
  denial rather than silently accepting an undeliverable reminder.
- Onboarding completion must persist every selected asset before reporting
  completion; failure must leave onboarding incomplete and expose the error.

- [x] Write a failing ViewModel test for selected-asset persistence.
- [x] Write a failing permission contract/instrumentation test.
- [x] Verify both tests fail for missing side effects.
- [x] Implement persistence and permission request handling.
- [x] Run targeted tests, then `:app:testDebugUnitTest`.

---

### Task 5: Integrated verification and closeout

**Files:**

- Update:
  `docs/superpowers/plans/2026-07-25-application-defect-remediation.md`

- [x] Review the complete diff for unit/currency confusion and swallowed errors.
- [ ] Run Android unit tests from a clean Gradle invocation against the final
  Android diff.
- [x] Build the Apple app for macOS.
- [x] Run the Apple unit suite on iOS Simulator.
- [x] Run focused Apple UI/source-contract tests.
- [ ] Run Android instrumentation, migration, test-compilation, and lint gates
  against the final Android diff.
- [x] Record the Android environment limitation separately from application
  failures.
- [x] Obtain an independent whole-diff code review and resolve every material
  finding.

---

### Task 6: Final-review packages and stable-diff verification

**Findings:** FINAL-001 through FINAL-023 plus allocation-provenance and Budget
Apply follow-ups RF-APPLE-030 through RF-APPLE-037 and RF-ANDROID-023 through
RF-ANDROID-028.

- [x] Reconcile provider corrections/enrichment without duplicate durable
  movement identities.
- [x] Revalidate balance-cache and exchange-rate evidence immediately before
  Apple plan persistence.
- [x] Make execution membership, transition rollback, cross-currency progress,
  and month-boundary behavior fail closed.
- [x] Preserve automatic-allocation provenance through transaction deletion,
  provider correction, backfill, CloudKit repair, and Local Bridge transport.
- [x] Upgrade Local Bridge to `bridge-snapshot-v2` / schema 2 and reject
  provenance-losing v1 snapshots.
- [x] Prevent Budget Apply from committing or stamping a superseded preview;
  disable mutable sheet controls while Apply is in flight.
- [x] Run the full Apple suite against the stable code diff.
- [x] Build the stable Apple code for macOS with signing disabled.
- [x] Freeze and review the complete staged Android patch at SHA-256
  `5b8f5a84d153dbcedb81bf53104c68aa2a6aa3d39eb31847276fa402f8907187`;
  verify that its previously tracked-file component remains
  `8631bfcd01f1780aed0df7a91e022b2ed32f40d09b10012e247caf8f9ddf02ee`.
- [ ] Rerun final Android JVM, test compilation, instrumentation, Room
  migration, and lint gates when Gradle socket creation is available.

## Completion evidence

| Evidence scope | Gate | Result |
|----------------|------|--------|
| Current Apple diff | Full unit/integration suite | 896/896 passed on iPhone 17 Pro simulator; no failures or skips |
| Current Apple diff | Budget Apply RED/GREEN | RED reproduced two failing scenarios; GREEN passed 41/41 |
| Current Apple diff | Final Budget sheet source/UX contracts | 20/20 passed |
| Current Apple diff | macOS app build | Passed with signing disabled |
| Current Android diff | Complete staged patch identity | SHA-256 `5b8f5a84d153dbcedb81bf53104c68aa2a6aa3d39eb31847276fa402f8907187` |
| Current Android diff | Previously tracked-file patch identity | SHA-256 `8631bfcd01f1780aed0df7a91e022b2ed32f40d09b10012e247caf8f9ddf02ee` |
| Current Android diff | Static review | Zero unresolved Critical or Important findings |
| Current Android diff | Gradle gates | Blocked: sandbox denied the Gradle `FileLockContentionHandler` socket and the escalated retry was unavailable after the environment exhausted its tool-usage allowance |
| Historical Android artifact, 2026-07-27 | JVM suite | 456/456 passed; no failures or skips |
| Historical Android artifact, 2026-07-27 | Instrumentation | 46/46 passed on API 36.1 |
| Historical Android artifact, 2026-07-27 | Room migration | Direct 5-to-6, direct 6-to-7, and complete 1-to-7 migration paths passed |
| Historical Android artifact, 2026-07-27 | Lint | Zero errors, 127 warnings, and two informational hints |
| Current stable source | Final review | One budget-text normalization race found and fixed; zero remaining Critical or Important findings |

Implementation deviations and review-driven hardening:

- Android execution valuation required Room schema version 6 and the
  `execution_asset_rates` table. Rates are captured only for assets allocated
  to goals snapshotted by the execution; legacy backfill also includes
  historically relevant assets removed from current allocations. Active legacy
  records and closed records within their undo window are marked for
  deterministic backfill. Post-start allocations require a persisted rate,
  asset currency is immutable throughout the reversible lifecycle, and
  concurrent legacy callers preserve the first committed matrix across scope
  races.
- Room schema version 7 replaces address-only asset uniqueness with a composite
  wallet/network/currency identity, allowing one EVM wallet to track its native
  asset and multiple canonical tokens without permitting duplicate identities.
- Execution start, completion, and undo preconditions now share the write
  transaction with their state changes. Completion rereads and calculates from
  the final transaction-consistent snapshots, transaction history, allocation
  history, and immutable rates. Asset and goal deletion fail closed only while
  required execution evidence would otherwise be cascaded away.
- Real TRON TRC20 responses are contract-keyed atomic balances rather than the
  originally assumed synthetic symbol/balance object. The implementation
  decodes that payload, applies token decimals, and rejects unsupported
  currency/chain pairs before cache access. Canonical EVM contract routing,
  ADA-only Cardano routing, and versioned caches prevent stale or counterfeit
  matches.
- Apple lifecycle save failures now restore only operation-owned fields instead
  of rolling back the whole model context. Dashboard refreshes use complete
  input fingerprints plus generation-guarded commits.
- Apple on-chain history uses movement-scoped identities and upgrades a legacy
  hash row only when the fetched movement and legacy row are both unambiguous;
  user-authored metadata remains intact.
- The Apple goal form preserves the child Save accessibility element, and the
  focused UI suite launches deterministically and exercises the current
  Dashboard, goal-detail, and Planning add-goal routes.
- Android reminder permission is reconciled on lifecycle resume, permission
  callback, and Save. The worker atomically disables a stale undeliverable
  reminder before cancelling its periodic work, without cancelling a
  concurrently updated reminder.
- Onboarding uses both a synchronous in-flight guard and a deterministic
  template-goal identity, so rapid taps and process restart after insertion
  cannot create duplicate assets, goals, or navigation callbacks.
- Tatum V4 wallet portfolio and EVM history use documented offset pagination
  with bounded fail-closed caps. Movement identities include available API
  transaction/log discriminators; ambiguous no-discriminator duplicates and
  legacy hash reconciliation never perform a destructive guess.
- The Android accessibility test harness was aligned with Hilt and deterministic
  seeded goal data; no production behavior was weakened.
- No Xcode project-file changes were required; Apple regressions were added to
  existing test targets.
