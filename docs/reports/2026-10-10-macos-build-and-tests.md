# macOS build fixes and verification

Date: 2026-10-10

All 13 diagnostics from the original native macOS build are fixed. The final macOS Debug build succeeds, and all 615 unit/integration tests pass without failures or skips.

## Changes

- Added `SystemBackgrounds` for 17 shared-view background references. iOS retains its original UIKit system colors; macOS uses AppKit window/control backgrounds, including the existing Reduce Transparency branches.
- Both active and finished goal lists use `.inset` on macOS and retain `.insetGrouped` on iOS.
- Guarded three iOS navigation-title display modifiers that surfaced after the initial errors were fixed.
- Fixed the native CloudKit coordinator test crash. Share preparation now passes a container provider to the presentation request. The real CloudKit store captures the same container used for its database operations. The test stub supplies a lazy provider, preserving the existing share/state/telemetry checks and asserting that coordinator preparation never resolves the container.

The original macOS compile failure and the coordinator test crash were observed before their fixes. No failing tests were disabled, skipped, or removed. Existing working-copy edits and the staged patch are preserved.

## Verification

Environment: Xcode 27.0 (27A266a), macOS 27.0.1, native arm64 destination.

| Check | Result |
| --- | --- |
| Main app scheme, macOS Debug build | `BUILD SUCCEEDED` |
| FamilyShareAcceptanceCoordinatorTests, native macOS | 20 passed; zero failures or skips |
| Full CryptoSavingsTrackerTests scheme, native macOS | 615 passed; zero failures or skips |
| Full iOS 27 simulator regression after final shared changes | 615 passed; zero failures or skips |
| Independent review of platform adapters and CloudKit provider | No material issues found |
| Staged patch and added whitespace | Staged patch unchanged; no added trailing whitespace |

Native verification uses `CODE_SIGNING_ALLOWED=NO` and a fresh temporary DerivedData directory. It validates compilation and unit/integration execution; App Store signing, live CloudKit sharing, visual UI behavior, and the separate UI-test scheme were not exercised. Existing unrelated compiler warnings remain, including a concurrency warning in `GoalCompletionSettlementService`.

The first native unit run passed 614 tests and crashed in the CloudKit stub because it instantiated a client requiring iCloud entitlements. Supplying an explicit container identifier did not eliminate that SDK requirement. The provider seam fixes the fixture dependency without changing project signing settings or provisioning profiles. An extra iOS check with signing disabled encountered three Keychain entitlement failures; the final iOS check uses the normal simulator signing configuration.

## Commands and receipts

Run from the repository root:

```sh
xcodebuild -project ios/CryptoSavingsTracker.xcodeproj \
  -scheme CryptoSavingsTracker -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/cst-macos-20261010/DerivedData-verified \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project ios/CryptoSavingsTracker.xcodeproj \
  -scheme CryptoSavingsTrackerTests -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/cst-macos-20261010/DerivedData-verified \
  CODE_SIGNING_ALLOWED=NO test
```

- [Final macOS build log](/private/tmp/cst-macos-20261010/macos-build-final.log).
- [Full macOS test log](/private/tmp/cst-macos-20261010/macos-unit-final.log), [result bundle](/private/tmp/cst-macos-20261010/macos-unit-final.xcresult), and [summary](/private/tmp/cst-macos-20261010/macos-unit-final-summary.json).
- [Focused native coordinator result](/private/tmp/cst-macos-20261010/macos-family-share-verified.xcresult).
- [Final signed iOS test log](/private/tmp/cst-macos-20261010/ios-unit-signed-final.log), [result bundle](/private/tmp/cst-macos-20261010/ios-unit-signed-final.xcresult), and [summary](/private/tmp/cst-macos-20261010/ios-unit-signed-final-summary.json).
- [Original 13 compilation diagnostics](/private/tmp/cst-bugfix-20261010/apple-macos-build.log).
- [Focused current-task patch](/private/tmp/cst-macos-20261010/task.diff).
