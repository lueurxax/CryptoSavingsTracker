# Six bug fixes and regression tests

Date: 2026-10-10

All six application defects from the dependency audit are fixed. Added 42 deterministic tests: 16 Apple tests and 26 Android tests. Existing working-copy changes and staged changes are preserved. No database schema or data migration was needed.

| Defect | Corrected behavior | Regression suite |
| --- | --- | --- |
| Android Start Tracking overwrites saved amounts | Snapshots preserve saved custom and effective flex amounts without applying the percentage again. | `StartExecutionUseCaseTest` |
| Android execution uses asset units as goal currency | Live tracking and completion share a currency-aware valuation after replaying per-asset funding deltas. Missing assets or unavailable/invalid rates produce an explicit error and prevent completion writes. Tiny BTC contributions remain significant after conversion. | `ExecutionCurrencyConversionTest`, `MonthlyExecutionViewModelTest` |
| Android goal progress stays stale | Both list and detail observe transactions, all allocations including competing goals, asset metadata, and on-chain cache updates. Cache hits do not emit refresh signals. | `GetGoalProgressUseCaseReactiveTest`, `OnChainBalanceRepositoryChangesTest` |
| Apple planning applies flex twice and loses FX | The header uses the effective, converted total once. The macOS slider applies the same persisted adjustment as the other sliders. Delayed conversion responses cannot overwrite the latest slider choice. | `MonthlyPlanningFlexRegressionTests` |
| Apple Unskip keeps a zero payment | Bulk adjustment consistently assigns skip, protection and flex flags. Unskip restores contributions; protection preserves a custom amount. | `MonthlyPlanningFlexRegressionTests` |
| Apple ignores later portfolio pages | All portfolio pages are read before returning a missing-token zero. Requests retain the original wallet filters and trusted endpoint; invalid or repeated continuations fail. Later-page errors preserve the fallback cache. | `BalanceServicePaginationTests` |

Android FX failures have a Retry action that works without changing transactions or assets. UI consumers share one session valuation, recovering errors do not overwrite unrelated action errors, and summaries avoid adding amounts in different currencies.

New regressions were observed failing against the original algorithms before fixes. Additional tests cover unavailable-rate recovery, concurrent UI consumers, cache invalidation, cancellation and malformed pagination. No test was disabled or skipped.

## Verification

| Check | Result |
| --- | --- |
| Full Apple unit/integration scheme, iOS 27 simulator | 615 passed; zero failures or skips |
| Pagination tests after the final continuation validation change | Nine passed |
| Full Android unit suite | 101 passed; zero failures, errors or skips |
| Android debug app and instrumentation APKs | Both built |
| Android lint | Zero errors, 103 warnings, two hints; no checks suppressed |
| Independent review of all six fixes and recovery handling | No remaining material defect found |
| Existing staged patch and task whitespace | Staged patch unchanged; no added trailing whitespace |
| Additional macOS Debug compilation | Initially blocked by 13 pre-existing platform diagnostics; fixed in the [macOS follow-up](2026-10-10-macos-build-and-tests.md) |

The initial macOS diagnostics concerned UIKit-only background colors in screenshot/family-sharing views and `.insetGrouped` in `GoalDetailView`. Every diagnostic originated in a file identical to the six-bug task's starting snapshot. The subsequent macOS follow-up fixes these diagnostics and verifies the native build plus all 615 unit/integration tests. Android instrumentation tests were compiled but not executed on a device. Wallet API tests use controlled transport fixtures and do not establish live balances.

The first combined Android build/lint attempt encountered a lint analysis race while Hilt regenerated source files. Builds and lint were then run separately. A new coroutine-sharing test also required draining cancelled ViewModel coroutines before resetting its test Main dispatcher; its production behavior assertions remain intact.

Verification receipts:

- [Full Apple log](/private/tmp/cst-bugfix-20261010/apple-unit-final.log) and [result bundle](/private/tmp/cst-bugfix-20261010/apple-unit-final.xcresult).
- [Final pagination log](/private/tmp/cst-bugfix-20261010/apple-pagination-final.log).
- [Android unit tests and APK builds](/private/tmp/cst-bugfix-20261010/android-verified-builds.log).
- [Android lint](/private/tmp/cst-bugfix-20261010/android-verified-lint.log).
- [macOS compilation diagnostics](/private/tmp/cst-bugfix-20261010/apple-macos-build.log).
