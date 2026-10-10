# Six bug fixes and regression coverage

Scope: the six application bugs confirmed in the dependency audit. Preserve existing workspace changes and the Git index.

- [x] Android: preserve saved effective monthly amounts when tracking starts.
- [x] Android: convert execution contributions into each goal's currency for live progress and completion.
- [x] Android: update goal progress when transactions, allocations, asset metadata, or cached on-chain balances change.
- [x] Apple: show the effective monthly total once, converted into the display currency.
- [x] Apple: restore contributions when a goal is unskipped, including protected goals.
- [x] Apple: follow Tatum portfolio pagination before reporting a missing token.

For each bug, run deterministic regression tests against the old behavior before changing the algorithm. Then run the complete Apple unit suite and Android unit suite, build both Android APKs, and run Android lint. Review the resulting patch against the start-of-task snapshot and check that staged changes remain intact.

No data-model migrations or live API requests are expected. Regression fixtures must not use real credentials or network calls.

Verification complete: Apple 615 tests and final pagination nine tests pass; Android 101 tests, both APK builds and lint pass. Independent review has no remaining material findings. Added 42 tests. The original staged patch is unchanged. An additional macOS compilation attempt exposed 13 existing platform diagnostics in unchanged files, recorded in the [fix report](../../reports/2026-10-10-six-bug-fixes.md).
