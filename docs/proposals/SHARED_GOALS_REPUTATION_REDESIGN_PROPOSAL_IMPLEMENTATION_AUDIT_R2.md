# Shared Goals Reputation Redesign Proposal Implementation Audit R2

| Field | Value |
|---|---|
| Proposal | docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md |
| Repository Root | . |
| Git SHA | ede07ec |
| Working Tree | dirty |
| Audited At | 2026-03-21T16:16:02+0200 |
| Proposal State | Active (Draft) |
| Overall Status | Not Implemented |

## Verdict

No, the proposal is not fully implemented. The redesign architecture is largely in place and several major invitee-surface requirements are implemented, but at least two in-scope requirements are still missing: deterministic neutral section-level disambiguation for multiple unresolved owners is absent, and the shared-row VoiceOver reading order does not match the proposal contract. Additional proposal requirements remain partial because the targeted shared-goals UI suite is not green and the required evidence pack coverage is incomplete for long-title and long-owner cases.

## Proposal Contract

### Scope
- Invitee-facing iPhone shared-goals information architecture, row layout, ownership copy, section-vs-row state hierarchy, and list/detail semantic alignment.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:10-13`, `:61-64`
- Canonical invitee projection, owner-identity normalization, section projection ownership, and cached/seeded migration path for the redesigned semantics.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:93-96`, `:305-390`

### Locked Decisions
- Remove the decorative `Shared by family` row badge and the full-width green explainer banner; rename the invitee entry to `Shared with You`.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:79-92`, `:102-115`
- Ownership is factual metadata; the default ownership line is `Shared by {ownerName} · Read-only`, with fallback `Shared by family member · Read-only`.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:84-89`, `:252-278`
- Share availability is section-level; row lifecycle is row-level; only `Achieved` and `Expired` are default row chips.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:89-96`, `:185-221`
- One canonical invitee projection and one owner resolver own list, detail, section, cache, preview, and UI-test semantics.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:93-96`, `:309-363`

### Acceptance Criteria
- No wrapped circular ownership badge, no device-name owner labels, no generic active share chip, and no extra decorative owner card.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:445-449`
- Shared rows show the four core layers clearly, including on 320pt width and large Dynamic Type.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:450-453`
- Share-health is section-level, `Achieved`/`Expired` remain visible when applicable, and unresolved owners remain distinguishable without raw device names.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:454-456`
- List, detail, and section semantics come from the same projection boundary, and migrated cached/seeded data cannot resurrect legacy copy.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:457-459`

### Test / Evidence Requirements
- Before/after iPhone screenshots plus long-title, long-owner, blocked-label, AX/Dynamic Type, and multi-owner evidence.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:463-471`
- UI tests for badge removal, fallback naming, and unhealthy-section behavior.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:472-474`
- Unit/migration/parity coverage for canonical projection, owner normalization, cache migration, and shared mapper boundary.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:475-478`

### Explicit Exclusions
- No CloudKit sharing architecture redesign.
- No participant-management redesign.
- No full shared-detail redesign beyond semantic alignment.
- No Android parity in this pass.
- No broader family-sharing rebrand.  
  Source: `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:65-74`

## Requirement Summary

| Status | Count |
|---|---:|
| Implemented | 4 |
| Partially Implemented | 5 |
| Missing | 2 |
| Not Verifiable | 0 |

## Requirement Audit

### REQ-001 Invitee entry is `Shared with You` and the green explainer banner is removed
- Proposal Source: `§5.1 Screen Information Architecture` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:102-115`), `§8 Acceptance Criteria #4-5` (`:448-450`)
- Status: Implemented
- Evidence Type: code, tests-run
- Evidence:
  - `ios/CryptoSavingsTracker/Views/ContentView.swift:144-175`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:186-237`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:85-100`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CSTAuditDerivedDataUITests26 -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests test` (`testInviteeScenarioShowsSharedWithYouAndReadOnlyDetail` passed)
- Gap / Note: None.

### REQ-002 Owner grouping uses light section affordances instead of an outer owner card, with persistent owner cues
- Proposal Source: `§5.2 Owner Grouping Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:117-141`), `§8 Acceptance Criteria #4` (`:448`)
- Status: Partially Implemented
- Evidence Type: code, tests-run
- Evidence:
  - `ios/CryptoSavingsTracker/Views/ContentView.swift:153-174`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:8-25`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:119-128`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:102-125`
  - `xcodebuild ... -scheme CryptoSavingsTrackerUITests ... -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests test` failed in `testInviteeScenarioShowsMultiOwnerGroupingAndStickyOwnerHeaders`
- Gap / Note: The outer wrapper is gone in code, but the screen-level acceptance proof for multi-owner owner-header visibility is still red.

### REQ-003 Shared rows use the 4-layer hierarchy, omit generic healthy share chips, and support compression fallback
- Proposal Source: `§5.3 Shared Goal Row Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:143-183`), `§6 Layout and Accessibility Safeguards #1-6` (`:396-404`)
- Status: Implemented
- Evidence Type: code, tests-run, tests-found
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift:30-101`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift:173-267`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:149-176`
  - `xcodebuild ... -scheme CryptoSavingsTrackerUITests ... -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests test` passed `testInviteeScenarioUsesLockedOwnershipLineAndSuppressesHealthyLifecycleChip`
- Gap / Note: Long-title and long-owner evidence are still handled separately under REQ-011.

### REQ-004 Device-like owner labels are suppressed and replaced with `family member`
- Proposal Source: `§4 Decision-Locked Fix Direction #4, #7` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:82-87`), `§5.5 Ownership Copy Contract` (`:252-278`), `§8 Acceptance Criteria #2` (`:446`)
- Status: Implemented
- Evidence Type: code, tests-run
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:186-214`
  - `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareTestSeeder.swift:91-92`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:148-160`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:141-147`
  - `xcodebuild ... -scheme CryptoSavingsTrackerTests ... -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests test` passed `testBlockedOwnerLabelIsNormalizedBeforeFixtureEmission`
  - `xcodebuild ... -scheme CryptoSavingsTrackerUITests ... -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests test` passed `testInviteeScenarioSuppressesBlockedDeviceOwnerLabels`
- Gap / Note: Single-owner blocked-label fallback is implemented; unresolved multi-owner disambiguation is audited separately in REQ-005.

### REQ-005 Multiple unresolved owners are deterministically distinguishable at section level without raw device names
- Proposal Source: `§5.2 Owner Grouping Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:127-132`), `§5.5 Ownership Copy Contract` (`:274-278`), `§5.8.1 Section Projection Ownership` (`:336-345`), `§8 Acceptance Criteria #11` (`:456`)
- Status: Missing
- Evidence Type: code
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:190-214`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:315-320`
  - `rg -n "Family member 1|Family member 2|disambiguat|unresolved multi-owner|deterministic neutral" ios/CryptoSavingsTracker ios/CryptoSavingsTrackerTests ios/CryptoSavingsTrackerUITests` returned no matches
- Gap / Note: The current resolver only emits the singular fallback `family member`; there is no deterministic neutral disambiguator for concurrent unresolved owners.

### REQ-006 Share availability is rendered at section level, while meaningful row lifecycle remains visible in unhealthy sections
- Proposal Source: `§5.4 Status Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:185-229`), `§5.4.1 Section-Level Unhealthy State Pattern` (`:233-250`), `§8 Acceptance Criteria #9-10` (`:454-455`)
- Status: Partially Implemented
- Evidence Type: code, tests-run
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:35-52`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift:44-51`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:177-191`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:127-139`
  - `xcodebuild ... -scheme CryptoSavingsTrackerTests ... -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests test` passed `testStaleFixturePreservesRowLifecycleWhenSectionIsUnhealthy`
  - `xcodebuild ... -scheme CryptoSavingsTrackerUITests ... -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests test` failed in `testInviteeScenarioShowsNonActiveStateBannerAndPrimaryAction`
- Gap / Note: The data model and section view support the contract, but the targeted stale-state UI acceptance path is not currently green.

### REQ-007 List, detail, and section semantics are fed by one canonical invitee projection instead of legacy direct UI fields
- Proposal Source: `§5.8 Canonical Invitee Projection Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:305-323`), `§5.8.1 Section Projection Ownership` (`:324-352`), `§8 Acceptance Criteria #12-13` (`:457-458`)
- Status: Implemented
- Evidence Type: code, tests-run
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:259-281`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:361-425`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift:8-139`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:162-175`
  - `xcodebuild ... -scheme CryptoSavingsTrackerTests ... -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests test` passed `testRedesignedInviteeProjectionKeepsListAndDetailOwnerIdentityInSync`
- Gap / Note: None.

### REQ-008 Cached and seeded legacy invitee semantics are migrated or invalidated so old copy cannot reappear
- Proposal Source: `§5.9 Migration and Deprecation Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:365-390`), `§8 Acceptance Criteria #14` (`:459`)
- Status: Partially Implemented
- Evidence Type: code, tests-run
- Evidence:
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:530-692`
  - `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareCacheStore.swift:169-243`
  - `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareCacheStore.swift:267-325`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:346-405`
  - `ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift:359-377`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift:444-475`
- Gap / Note: Cache migration and canonicalization exist, but legacy fallback strings still remain in lower-layer model and CloudKit defaults, so the old semantics are not fully purged from all invitee-path inputs.

### REQ-009 320pt / large Dynamic Type safeguards and preview evidence cover the redesigned shared-goal surface
- Proposal Source: `§5.3.1 Row Compression Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:163-183`), `§9 Test and Evidence Plan #2-7` (`:465-471`)
- Status: Partially Implemented
- Evidence Type: code, tests-found
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift:173-267`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:162-176`
  - `rg -n "long title|long owner" ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift` found no explicit long-title or long-owner preview cases
- Gap / Note: 320pt and AX previews exist, but repo-local evidence for explicit long-goal-title and long-owner-name shared-goal cases was not found.

### REQ-010 VoiceOver reads shared rows in the proposal’s semantic order
- Proposal Source: `§6 Layout and Accessibility Safeguards #7` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:404-407`)
- Status: Missing
- Evidence Type: code
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift:125-137`
- Gap / Note: The current accessibility label reads goal name, ownership line, and amounts before any exceptional state chip. The proposal requires state to be announced before amounts.

### REQ-011 Required proposal evidence and targeted verification coverage exist and are green
- Proposal Source: `§9 Test and Evidence Plan` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:461-494`)
- Status: Partially Implemented
- Evidence Type: tests-run, tests-found
- Evidence:
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:130-191`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:85-176`
  - `docs/proposals/review-artifacts/shared-goals-reputation-r2/active-list-r2.png`
  - `docs/proposals/review-artifacts/shared-goals-reputation-r2/removed-list-r2.png`
  - `xcodebuild ... -scheme CryptoSavingsTrackerTests ... -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests test` succeeded (`16` tests, `0` failures)
  - `xcodebuild ... -scheme CryptoSavingsTrackerUITests ... -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests test` failed (`7` tests, `2` failures)
- Gap / Note: Unit/migration coverage is strong, but the shared-goals UI suite is not green and the repo-local evidence set does not yet cover all required preview/evidence cases from the proposal.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md`
- `git rev-parse --show-toplevel`
- `git rev-parse --short HEAD`
- `git status --short`
- `rg -n "superseded|deprecated|replaced by|obsolete" docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md docs/proposals`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -configuration Debug -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' -derivedDataPath /tmp/CSTAuditDerivedData build`
- Xcode MCP `BuildProject(tabIdentifier: windowtab1)`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CSTAuditDerivedDataUnitTests26 -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests test`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CSTAuditDerivedDataUITests26 -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests test`
- `rg -n "Family member 1|Family member 2|disambiguat|unresolved multi-owner|deterministic neutral" ios/CryptoSavingsTracker ios/CryptoSavingsTrackerTests ios/CryptoSavingsTrackerUITests`
- `rg -n "long title|long owner" ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift`

## Recommended Next Actions

- Implement deterministic neutral disambiguation for multiple unresolved owners at the section level and cover it with unit and UI tests.
- Fix the shared-row VoiceOver label order so exceptional state is announced before the financial amounts.
- Reconcile the failing `FamilySharingUITests` selectors/runtime for multi-owner header visibility and stale-state banner rendering, then rerun the targeted UI suite until green.
- Remove remaining lower-layer legacy `Shared Goals` / `Shared by ...` fallback defaults or route them through the canonical resolver before they can reach invitee surfaces.
- Add the missing long-title and long-owner evidence cases to the shared-goals redesign preview/evidence set.
