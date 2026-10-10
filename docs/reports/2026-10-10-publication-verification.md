# Publication verification

Date: 2026-10-10

The local dependency updates, six bug fixes, macOS fixes and earlier unpublished commits are integrated with GitHub `main` at `6a593852`. Both histories are preserved. Generated archives, DerivedData, agent scratch state and credential configuration remain ignored.

The GitHub changes include frozen execution-rate snapshots, transactional persistence, financial-input receipts and additional integrity tests. Merge resolutions retain the local custom/flex, tiny-BTC valuation, pagination, reactive progress, goal settlement and CloudKit test-isolation fixes. Tests were adapted to the canonical frozen-rate and baseline/effective-amount contracts rather than retaining duplicate valuation paths.

## Verification of the merged source

| Check | Result |
| --- | --- |
| iOS unit/integration, XcodeBuildMCP without opening Xcode | 1,015 passed; zero failures or skips |
| Native macOS unit/integration, command line without GUI | 1,015 passed; zero failures or skips |
| Android unit tests | 542 passed; zero failures, errors or skips |
| Android debug app and androidTest APK | Both built |
| Android lint | Zero errors, 106 warnings, two hints |
| iOS Release signing preflight | Archive succeeded |
| Git whitespace | No added whitespace errors |

New regressions prove that a same-value cache refresh or a balance change followed by its reversal during suspended FX invalidates the consumed financial receipt. The receipt is captured before the FX await. Restoring the old custom/flex, raw-unit threshold and overflow behavior also reproduced five expected Android failures before the fixes were restored.

Planning asset refresh retains the selected month and commits draft recalculations as one batch. Historical August fixtures now use fixed August deadlines. Requirements retain their automatic baseline; persisted effective amounts and converted totals remain separate. Refresh errors retain the last cache for explicitly degraded presentation while propagating the fetch failure.

## CI and scope limitations

The six existing GitHub workflows target pull requests or `release/**`; none runs for a push to `main`. Local static preflight passed seven of 20 gates. The other 13 still reference deleted visual/CloudKit files or existing copy/navigation-policy violations. The Python script suite passed 18 of 21 tests; the three failures rely on visual schemas already absent from GitHub `main`. These pre-existing gate problems were not hidden or suppressed. SwiftLint is not installed locally.

Separate Apple UI tests and Android device instrumentation execution were not run. Unit/API tests use fixtures and do not establish live wallet balances. The shipping archive selects the ignored production configuration; no API keys or signed app bundles are published to GitHub.

## Receipts

- [iOS result](/private/tmp/cst-testflight-20261010/ios-publish-verified.xcresult) and [summary](/private/tmp/cst-testflight-20261010/ios-publish-verified-summary.json).
- [macOS result](/private/tmp/cst-testflight-20261010/macos-publish-verified.xcresult) and [summary](/private/tmp/cst-testflight-20261010/macos-publish-verified-summary.json).
- [Android unit summary](/private/tmp/cst-android-merge-full-unit-summary.json).
- [Android APK build log](/private/tmp/cst-testflight-20261010/android-apk-build-verified.log) and [lint summary](/private/tmp/cst-testflight-20261010/android-lint-summary.json).
- [Local CI preflight](/private/tmp/cst-testflight-20261010/ci-preflight/summary.json).
- [Final iOS archive log](/private/tmp/cst-testflight-20261010/archive-final.log).
