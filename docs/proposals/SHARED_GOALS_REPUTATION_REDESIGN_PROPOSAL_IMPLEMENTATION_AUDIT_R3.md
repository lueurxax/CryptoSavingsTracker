# Shared Goals Reputation Redesign Proposal Implementation Audit R3

| Field | Value |
|---|---|
| Proposal | `docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md` |
| Repository Root | `.` |
| Git SHA | `ede07ec` |
| Working Tree | `dirty` |
| Audited At | `2026-03-21T17:04:15+0200` |
| Proposal State | `Active (Draft)` |
| Overall Status | `Partial` |

## Verdict

The redesign is substantially implemented in the current iOS codebase. The invitee surface now uses `Shared with You`, routes section/row/detail semantics through canonical invitee projections, suppresses blocked owner labels, removes the legacy healthy-state row chip path, and passes the targeted acceptance and UI suites executed in this audit. The status remains `Partial` because the proposal's migration/evidence contract is not fully closed: semantic cache-migration proof is still indirect, and the repo does not yet contain a refreshed post-implementation screenshot/evidence set for the final shipped state.

## Proposal Contract

### Scope
- Invitee-facing shared-goals IA, row layout, ownership copy, and state hierarchy on iOS.
- Affected surfaces: `ContentView`, `SharedGoalsSectionView`, `SharedGoalRowView`, `SharedGoalDetailView`, and the family-sharing projection/mapping layer.

### Locked Decisions
- Rename the invitee entry to `Shared with You` and remove the green explainer banner.
- Remove the decorative `Shared by family` row badge and separate ownership from state.
- Use one stable ownership line: `Shared by {ownerName} · Read-only`.
- Suppress device-style owner labels and use deterministic neutral fallback naming for unresolved multi-owner sections.
- Move share availability to the section and keep lifecycle state at the row.
- Keep only meaningful row chips by default (`Achieved`, `Expired`).
- Feed section, row, and detail from one canonical invitee mapping boundary.
- Migrate cached data, previews, and UI-test seeds so legacy invitee copy cannot rehydrate.

### Acceptance Criteria
- No circular/wrapped ownership badge remains on invitee rows.
- No visible owner label leaks `iPhone`, `iPad`, `Mac`, or `Unknown device`.
- Healthy rows no longer show `Shared by family` as a status chip.
- Owner groups are no longer wrapped in an extra decorative card.
- First viewport uses one coherent `Shared with You` entry treatment.
- Rows preserve the four core layers and remain readable on 320pt / large Dynamic Type.
- Exceptional lifecycle state stays visible while share-health messaging stays section-scoped.
- Multiple unresolved owners stay distinguishable without exposing raw device names.
- List and detail use one canonical projection and do not bind legacy `ownerChip` / `currentMonthSummary` directly.
- Section header, banner, and primary action semantics come from the same mapper boundary.
- Cached/seeded legacy invitee data cannot reintroduce old copy or legacy row semantics after migration.

### Test / Evidence Requirements
- Before/after iPhone screenshots.
- Long-title, long-owner, blocked-owner, large Dynamic Type, and unresolved multi-owner preview coverage.
- UI tests for no legacy badge, device-label fallback, and unhealthy section behavior.
- Unit tests for canonical invitee projection mapping and owner identity normalization.
- Migration/parity coverage for cache/seed behavior and same-mapper semantics across section/row/detail.

### Explicit Exclusions
- No CloudKit architecture redesign.
- No participant-management redesign.
- No full shared-detail redesign beyond semantic alignment.
- No Android parity.
- No broad family-sharing rebrand.

## Requirement Summary

| Status | Count |
|---|---:|
| Implemented | 8 |
| Partially Implemented | 2 |
| Missing | 0 |
| Not Verifiable | 0 |

## Requirement Audit

### REQ-001 Invitee Entry Uses `Shared with You` Without the Legacy Explainer Banner
- Proposal Source: `## 5.1 Screen Information Architecture` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:100-115`), `## 8) Acceptance Criteria` (`:445-450`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/ContentView.swift:144-174`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:101-117`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CSTAuditDerivedDataUITests26_r3 -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests test` (passed)
- Gap / Note: `ContentView` now uses the projection entry title as the invitee section header and no longer renders the old first-viewport explainer surface.

### REQ-002 Owner Grouping Uses Standard Section Structure Without the Extra Outer Owner Card
- Proposal Source: `## 5.2 Owner Grouping Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:117-141`), `## 7) Implementation Scope` (`:428-430`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/ContentView.swift:153-173`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:29-72`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:8-26`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:119-145`
  - same `xcodebuild ... FamilySharingUITests test` run above (passed)
- Gap / Note: Owner header, state banner, and rows now render as separate list-section parts instead of nested owner-card chrome.

### REQ-003 Shared Goal Rows Follow the Locked Four-Layer Hierarchy and Suppress Legacy Healthy-State Row Semantics
- Proposal Source: `## 5.3 Shared Goal Row Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:143-183`), `## 4) Decision-Locked Fix Direction` (`:84-91`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift:30-102`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:380-419`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:168-179`
  - same `xcodebuild ... FamilySharingUITests test` run above (passed)
- Gap / Note: The row now shows title, ownership line, progress, and amount summary; healthy rows no longer expose `Current`, `On track`, or `Just started`.

### REQ-004 Share Availability Is Section-Level and Lifecycle State Remains Meaningful at the Row Level
- Proposal Source: `## 5.4 Status Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:185-250`), `## 8) Acceptance Criteria` (`:453-456`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:421-432`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift:35-52`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift:44-50`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:188-202`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:147-158`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CSTAuditDerivedDataUnitTests26_r3 -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests test` (passed)
  - same `xcodebuild ... FamilySharingUITests test` run above (passed)
- Gap / Note: Unhealthy share state now renders through the section banner/primary action path, while `Achieved` and `Expired` remain available as row-level lifecycle chips.

### REQ-005 Owner Identity Is Resolved Through One Human-First Normalizer with Deterministic Multi-Owner Fallbacks
- Proposal Source: `## 5.5 Ownership Copy Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:252-278`), `## 5.8.1 Section Projection Ownership` (`:354-363`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:186-339`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:350-377`
  - `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareTestSeeder.swift:42-50`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:130-139`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:159-171`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:160-189`
  - both targeted `xcodebuild ... test` runs above (passed)
- Gap / Note: The same resolver now suppresses device-like labels, emits `Shared by family member · Read-only`, and disambiguates multiple fallback owner sections as `Family member 1`, `Family member 2`.

### REQ-006 Shared Detail Semantics Align with the Invitee List Contract
- Proposal Source: `## 5.7 Shared Detail Alignment` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:294-304`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift:35-89`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:400-409`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:173-186`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:101-117`
  - both targeted `xcodebuild ... test` runs above (passed)
- Gap / Note: Detail now consumes projection-owned ownership/read-only semantics and no longer contradicts the invitee list with legacy ownership copy.

### REQ-007 Section, Row, and Detail Are Fed from One Canonical Invitee Projection Boundary
- Proposal Source: `## 5.8 Canonical Invitee Projection Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:305-323`), `## 5.8.1 Section Projection Ownership` (`:324-352`), `## 8) Acceptance Criteria` (`:457-458`)
- Status: `Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:380-438`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:717-767`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:259-282`
  - `ios/CryptoSavingsTracker/Views/ContentView.swift:144-173`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:173-186`
  - both targeted `xcodebuild ... test` runs above (passed)
- Gap / Note: The invitee projection now owns entry, section, and goal semantics; legacy `ownerChip` / `currentMonthSummary` remain in compatibility structs only.

### REQ-008 Cached Data, Fixtures, and Seeds Prevent Legacy Invitee Semantics from Reappearing After Migration
- Proposal Source: `## 5.9 Migration and Deprecation Contract` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:365-390`), `## 8) Acceptance Criteria` (`:459`)
- Status: `Partially Implemented`
- Evidence Type: `code, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareCacheStore.swift:169-243`
  - `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareCacheStore.swift:267-330`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift:341-377`
  - `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareTestSeeder.swift:71-219`
  - `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift:531-657`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:357-416`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:141-171`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CSTAuditDerivedDataUnitTests26_r3 -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests test` (passed)
- Gap / Note: Read-time canonicalization and new fixtures are in place, but the automated proof is still incomplete for a true pre-change cache payload containing legacy invitee copy/blocked owner values and rehydrating through the end-to-end migration path.

### REQ-009 Layout and Accessibility Safeguards Prevent the Original Screenshot Failure
- Proposal Source: `## 6) Layout and Accessibility Safeguards` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:392-409`)
- Status: `Implemented`
- Evidence Type: `code, tests-found, tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift:35-59`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift:64-85`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift:125-138`
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift:255-321`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:181-189`
  - same `xcodebuild ... FamilySharingUITests test` run above (passed)
- Gap / Note: The row now uses 2-line title / 1-line ownership constraints, a non-wrapping chip, stacked amount fallback, and the required VoiceOver reading order.

### REQ-010 Proposal-Specific Test and Evidence Pack Coverage Is Complete for the Landed Redesign
- Proposal Source: `## 9) Test and Evidence Plan` (`docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md:461-494`)
- Status: `Partially Implemented`
- Evidence Type: `code, tests-run, runtime`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsReputationRedesignPreview.swift:255-321`
  - `ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift:101-205`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift:108-202`
  - `docs/proposals/review-artifacts/shared-goals-reputation-r1/`
  - `docs/proposals/review-artifacts/shared-goals-reputation-r2/`
  - both targeted `xcodebuild ... test` runs above (passed)
- Gap / Note: The repo now contains the dedicated preview gallery and green test runs, but it still lacks a refreshed post-implementation before/after screenshot set and an updated evidence pack proving the final redesigned runtime states end-to-end. The blocked-device fallback preview is also covered indirectly rather than as a clearly named dedicated artifact.

## Verification Log

- `python3 /Users/user/.codex/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md`
- `git rev-parse --short HEAD`
- `git status --short`
- `rg -n "superseded|deprecated|replaced by|obsolete" docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL* docs/proposals`
- `rg -n "ownerChip|currentMonthSummary" ios/CryptoSavingsTracker/Views/FamilySharing ios/CryptoSavingsTracker/Views/ContentView.swift ios/CryptoSavingsTracker/Services/FamilySharing ios/CryptoSavingsTracker/Utilities/FamilySharing ios/CryptoSavingsTrackerTests/FamilySharing ios/CryptoSavingsTrackerUITests/FamilySharing`
- `rg -n "Shared Goals|Shared by family|iPhone|iPad|Unknown device|Family member 1|Family member 2" ios/CryptoSavingsTracker ios/CryptoSavingsTrackerTests ios/CryptoSavingsTrackerUITests`
- `mcp__xcode__XcodeListWindows` -> `windowtab1`
- `mcp__xcode__BuildProject(tabIdentifier: "windowtab1")` (passed)
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CSTAuditDerivedDataUnitTests26_r3 -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests test`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerUITests -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16' -derivedDataPath /tmp/CSTAuditDerivedDataUITests26_r3 -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests test`

## Recommended Next Actions

- Add one migration-focused automated test that seeds legacy invitee cache semantics (`Shared Goals`, `Shared by family`, blocked device labels) and proves canonicalization or invalidation on rehydrate.
- Refresh the proposal evidence set with final after-state iPhone screenshots for active, stale, removed, blocked-owner, and multi-owner scenarios, then write the corresponding updated evidence pack beside the proposal.
