# Evidence Pack

## A. Scope and Purpose
This pack closes the remaining evidence gaps for the landed invitee-side redesign in
[`SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md`](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md).

It provides:
- baseline "before" artifacts that captured the original reputation issue,
- fresh post-implementation iPhone runtime screenshots for the final redesign states,
- explicit long-title / long-owner preview evidence,
- targeted unit and UI verification references for the redesigned mapper boundary.

## B. Before / After Runtime Screenshots
| Evidence ID | Artifact | State | Verified On | Key Fact |
|---|---|---|---|---|
| BEFORE-01 | [`/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r1/active-list-fresh.png`](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r1/active-list-fresh.png) | Active baseline | 2026-03-18 | Original incident state showed `Shared Goals`, a green explainer banner, extra owner chrome, and the wrapped `Shared by family` badge. |
| BEFORE-02 | [`/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r1/stale-list.png`](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r1/stale-list.png) | Stale baseline | 2026-03-18 | Pre-redesign stale path duplicated unhealthy state between the section and the row. |
| AFTER-01 | [`/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r3/active-list-r3.png`](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r3/active-list-r3.png) | Active redesigned runtime | 2026-03-21 | Invitee entry is `Shared with You`; no green explainer banner or wrapped ownership badge remains. |
| AFTER-02 | [`/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r3/stale-list-r3.png`](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r3/stale-list-r3.png) | Stale redesigned runtime | 2026-03-21 | Share-health is section-level via `Out of date` banner + `Retry Refresh`, while row lifecycle remains separate. |
| AFTER-03 | [`/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r3/removed-list-r3.png`](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r3/removed-list-r3.png) | Removed / no-longer-shared runtime | 2026-03-21 | Non-happy path uses section-level messaging instead of legacy row-level duplication. |
| AFTER-04 | [`/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r3/blocked-owner-list-r3.png`](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r3/blocked-owner-list-r3.png) | Blocked-device-label runtime | 2026-03-21 | Raw device labels are suppressed; invitee copy falls back to human-safe `family member`. |
| AFTER-05 | [`/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r3/multi-owner-fallback-list-r3.png`](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/review-artifacts/shared-goals-reputation-r3/multi-owner-fallback-list-r3.png) | Unresolved multi-owner runtime | 2026-03-21 | Multiple unresolved owners are disambiguated neutrally as `Family member 1` / `Family member 2` without leaking raw device names. |

## C. Preview / Layout Evidence
| Evidence ID | Artifact | State | Verified On | Key Fact |
|---|---|---|---|---|
| PREVIEW-01 | [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift) | Preview gallery | 2026-03-21 | Dedicated preview gallery exists for redesigned invitee surfaces. |
| PREVIEW-02 | [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift#L255`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift#L255) | Long owner / long title preview data | 2026-03-21 | Explicit long-copy cases are now named and stored in the preview gallery instead of being indirect. |
| PREVIEW-03 | [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift#L291`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift#L291) | 320pt preview | 2026-03-21 | Narrow-width fallback remains part of the evidence set. |
| PREVIEW-04 | [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift#L296`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift#L296) | AX Dynamic Type preview | 2026-03-21 | Large Dynamic Type coverage remains part of the evidence set. |

## D. Mapper / Migration / UI Verification
| Evidence ID | Artifact | Verified On | Result | Key Fact |
|---|---|---|---|---|
| TEST-01 | [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift) | 2026-03-21 | Pass | Canonical invitee projection, owner normalization, stale-row coexistence, unresolved multi-owner fallback, and legacy cache rehydrate proof are covered. |
| TEST-02 | [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift) | 2026-03-21 | Pass | Targeted invitee UI tests validate active, stale, multi-owner grouping, blocked-owner fallback, and unresolved multi-owner runtime behavior. |
| TEST-03 | `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CST-shared-r3-unit test -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests` | 2026-03-21 | Pass | Unit suite is green on the redesign mapper boundary. |
| TEST-04 | `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CST-shared-r3-ui-multi test -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests/testInviteeScenarioShowsMultiOwnerGroupingAndStickyOwnerHeaders` | 2026-03-21 | Pass | Multi-owner grouping/runtime evidence is now green. |
| TEST-05 | `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CST-shared-r3-ui-stale test -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests/testInviteeScenarioShowsNonActiveStateBannerAndPrimaryAction` | 2026-03-21 | Pass | Stale runtime banner/action evidence is now green. |
| TEST-06 | `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CST-shared-r3-ui-unresolved test -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests/testInviteeScenarioDisambiguatesMultipleFallbackOwners` | 2026-03-21 | Pass | Unresolved multi-owner fallback evidence is now green. |

## E. Closeout
The original incident is preserved as baseline evidence in `r1`, while `r3` captures the landed redesign states and the tests that prove the final invitee contract.
