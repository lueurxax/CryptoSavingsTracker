# Shared Goals Reputation Redesign Proposal Implementation Audit R1

| Field | Value |
|---|---|
| Proposal | /Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md |
| Audited On | 2026-03-21 |
| Overall Status | Partial |

## Summary

The redesign is mostly implemented in the invitee runtime path: the app now uses a canonical invitee projection, owner-grouped sections, locked ownership lines, blocked-owner normalization, cache migration, and updated previews/tests. It is not fully implemented yet because the proposal's screen-level acceptance proof is still red: the targeted UI suite fails in multi-owner and stale-state cases, and lower-level legacy defaults can still reintroduce old terminology if data reaches the UI outside the canonicalized path.

## Implemented

- Entry treatment now uses `Shared with You` and removes the old full-width explainer banner from the invitee list surface.  
  Evidence: `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/ContentView.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift`

- Section, row, and detail semantics are now driven by canonical invitee projection types instead of ad hoc legacy fields.  
  Evidence: `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift`

- Blocked-device owner labels are normalized through a dedicated resolver and preserved consistently through seeded data and runtime projections.  
  Evidence: `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareTestSeeder.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift`

- Section-level unhealthy share state is separated from row lifecycle state, and row lifecycle chips remain available for achieved/expired items.  
  Evidence: `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift`

- Cache/schema migration and cache canonicalization exist for the shared-goals projection path.  
  Evidence: `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareCacheStore.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift`

- Proposal-specific preview evidence for standard, 320pt, and accessibility text-size states exists in the repo.  
  Evidence: `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift`

## Partial Gaps

- Screen-level acceptance is not fully green yet.  
  Gap: The targeted UI suite still fails in the multi-owner header and stale banner scenarios, so the proposal's final invitee acceptance criteria are not fully verified end-to-end. The current view code still exposes the expected accessibility identifiers, which suggests either selector/seed drift or remaining runtime presentation drift.  
  Evidence: `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift`, `/tmp/CSTAuditDerivedDataUITests26/Logs/Test/Test-CryptoSavingsTrackerUITests-2026.03.21_15-42-57-+0200.xcresult`

- Lower-level fallback defaults still carry legacy `Shared Goals` / `Shared by ...` terminology.  
  Gap: The canonical projection masks this in the verified happy path, but the old copy still exists in model and CloudKit fallback defaults, which keeps proposal drift alive in edge paths or malformed upstream payloads.  
  Evidence: `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift`, `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift`

## Missing

- No fully missing proposal requirement was confirmed from the current code inspection. The remaining gaps are verification drift and residual legacy defaults rather than an entirely absent feature slice.

## Verification

- `xcodebuild -project /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -configuration Debug -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' -derivedDataPath /tmp/CSTAuditDerivedData build`  
  Result: `BUILD SUCCEEDED`

- Xcode MCP `BuildProject(tabIdentifier: windowtab1)`  
  Result: project built successfully with no reported warnings/errors in the retrieved build log

- `xcodebuild -project /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CSTAuditDerivedDataUnitTests26 -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests test`  
  Result: `TEST SUCCEEDED` (`16` tests, `0` failures)

- `xcodebuild -project /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CSTAuditDerivedDataUITests26 -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests test`  
  Result: `TEST FAILED` (`7` tests, `2` failures)  
  Notes: failing cases were `testInviteeScenarioShowsMultiOwnerGroupingAndStickyOwnerHeaders` and `testInviteeScenarioShowsNonActiveStateBannerAndPrimaryAction`

## Recommended Next Actions

- Reconcile `FamilySharingUITests` with the current seeded runtime for multi-owner and stale states, then rerun the targeted UI suite until it is green.
- Remove remaining legacy `Shared Goals` / `Shared by ...` fallback strings from lower-layer projection defaults and route them through the canonical resolver.
- Keep the current targeted build + unit + UI commands as the proposal verification gate for future changes to the shared-goals invitee flow.
