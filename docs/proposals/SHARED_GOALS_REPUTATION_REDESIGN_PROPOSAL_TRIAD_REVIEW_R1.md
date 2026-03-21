# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `full-review`
- Evidence completeness: `Partial`
- Documents / repo inputs reviewed:
  - [`/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md`](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL.md)
  - [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/ContentView.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/ContentView.swift)
  - [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift)
  - [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift)
  - [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift)
  - [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift)
  - [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift)
  - [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift)
  - [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareTestSeeder.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareTestSeeder.swift)
  - [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift)
- External sources reviewed:
  - None required for this repo-grounded pass.
- Build/run attempts:
  - `RUN-01`: CLI `xcodebuild build` succeeded for `CryptoSavingsTracker` on iPhone 16 simulator / iOS 18.5.
  - `RUN-02`: seeded simulator launch succeeded for active, stale, and removed invitee states on a fresh simulator.
  - `RUN-03`: Xcode MCP build succeeded on project tab `windowtab1`.
- Screenshots captured:
  - `SCR-01` active invitee list
  - `SCR-02` stale invitee list
  - `SCR-03` removed/no-longer-shared invitee list
  - `SCR-04` attempted multi-owner capture that did not reproduce cleanly
- Code areas inspected:
  - shared-goals list composition
  - owner-section grouping
  - shared-goal row layout
  - shared-goal detail semantics
  - family-sharing UI models
  - service-layer projection mapping
  - CloudKit fallback mapping
  - UI test fixture and assertions
- Remaining assumptions:
  - The proposal targets the invitee-facing iPhone shared-goals list and its semantic alignment with detail.
  - Current repo behavior and seeded simulator states are the correct baseline for this redesign.
- Remaining blockers:
  - Multi-owner simulator evidence is incomplete (`BASE-04`, `BLOCKER-01`).
  - Simulator runs emitted CloudKit no-account warnings, limiting confidence on live-backed state behavior (`BLOCKER-02`).

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `Medium`
- Release blockers:
  - None at proposal stage, but the redesign is not implementation-ready enough to ship without clarifying the data contract and state precedence rules.
- Top risks:
  1. The proposal splits ownership, share health, and lifecycle visually, but it does not define a canonical invitee projection or migration boundary for the existing `FamilySharedGoalSummary` contract.
  2. The proposal leaves key runtime behaviors underdefined: narrow-width collapse, Dynamic Type fallback, and the exact relationship between section-level share health and row-level lifecycle chips.
  3. The proposal does not fully close the list/detail loop or the owner-label normalization path, so the app can still present conflicting semantics after a partial implementation.
- Top opportunities:
  1. The proposal correctly identifies the incident as structural rather than cosmetic and sets the right direction: ownership as metadata, share health at section level, calmer row hierarchy.
  2. A small set of explicit additions could make this implementation-ready: one canonical invitee projection, one section-state pattern, one row-collapse contract, and one owner-identity resolver.
  3. The existing simulator fixture path is already good enough to turn the missing acceptance criteria into UI tests once the proposal sharpens the contract.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | Amber | Medium | Partial | 0 | 1 | 2 | 1 |
| UX | Amber | Medium | Partial | 0 | 1 | 2 | 0 |
| iOS Architecture | Amber | Medium | Partial | 0 | 2 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Findings
- Finding ID: `UI-01`
  Severity: `High`
  Evidence IDs: `DOC-04`, `SCR-01`, `BASE-01`
  Why it matters: The proposal removes the visible badge failure, but it does not define hard collapse behavior for title, metadata, chip, and amount at narrow widths or large Dynamic Type. That leaves the core incident mechanically possible even after the redesign direction is implemented.
  Recommended fix: Add a normative row-compression contract covering layout priority, truncation order, and chip suppression on narrow width and accessibility text sizes.
  Acceptance criteria: On a 320pt-width device at the largest supported Dynamic Type, the title stays within 2 lines, ownership metadata stays within 1 line, the chip never wraps, and the amount row remains legible without overlap.
  Confidence: `High`

- Finding ID: `UI-02`
  Severity: `Medium`
  Evidence IDs: `DOC-02`, `DOC-03`, `SCR-01`, `SCR-02`
  Why it matters: The proposal removes the outer owner card but does not define the replacement visual affordance that keeps owner groups scannable. In the current UI, that extra chrome is doing real grouping work, even if it is visually noisy.
  Recommended fix: Specify the replacement owner-group treatment: header spacing, divider behavior, optional background banding, and how that behaves in light/dark mode.
  Acceptance criteria: Owner groups remain visually distinct without nested card chrome, and the first viewport is still easy to scan when two owner groups are visible.
  Confidence: `Medium`

- Finding ID: `UI-03`
  Severity: `Medium`
  Evidence IDs: `DOC-03`, `DOC-05`, `BASE-02`, `BASE-03`
  Why it matters: The proposal says unhealthy share states belong at section level, but it does not define a single concrete visual pattern for stale, unavailable, revoked, and removed states. That can lead to either under-signaling trust issues or recreating the same noisy duplication in a new form.
  Recommended fix: Define one section-level unhealthy-state component pattern with icon, color, copy length, spacing, and explicit suppression rules for row-level share-state chips.
  Acceptance criteria: Unhealthy sections have one stable warning treatment, healthy rows beneath them remain calm, and the same warning is not repeated on each row.
  Confidence: `Medium`

- Finding ID: `UI-04`
  Severity: `Low`
  Evidence IDs: `DOC-02`, `SCR-01`, `BASE-01`
  Why it matters: The proposal renames the section to `Shared with You`, but it does not decide the fate of the existing green explainer banner. Leaving that unresolved can preserve the loudest visual element even after the rename.
  Recommended fix: Either remove the banner or restyle/demote it so the section header remains the single primary entry cue.
  Acceptance criteria: The first viewport no longer contains a full-width green callout that competes with the shared-goals section title.
  Confidence: `Medium`

### 3.2 UX Findings
- Finding ID: `UX-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `DOC-03`, `DOC-04`, `SCR-02`, `SCR-03`, `BASE-02`, `BASE-03`
  Why it matters: The proposal says section-level share health has priority, but it also defines `Achieved` and `Expired` as the only default row-level lifecycle chips. It does not explicitly resolve whether those lifecycle chips remain visible inside unhealthy sections. That ambiguity can hide the only meaningful per-row state and reduce trust.
  Recommended fix: State explicitly that section-level share-health messaging suppresses only the generic share chip, not meaningful row-level lifecycle chips like `Achieved` and `Expired`.
  Acceptance criteria: In stale, removed, and unavailable sections, row lifecycle chips still appear when applicable; active rows never show the generic positive share chip.
  Confidence: `Medium`

- Finding ID: `UX-02`
  Severity: `Medium`
  Evidence IDs: `DOC-02`, `CODE-01`, `SCR-01`, `QUESTION-01`
  Why it matters: The rename to `Shared with You` is not paired with an explicit decision about the current green explainer banner, so the first viewport can still present two competing shared-surface concepts.
  Recommended fix: Pick one entry treatment for the invitee surface and align all top-of-screen copy to that single concept.
  Acceptance criteria: No `Shared Goals` copy remains on the invitee list, and the first viewport shows one coherent shared-surface entry treatment in before/after evidence.
  Confidence: `High`

- Finding ID: `UX-GAP-01`
  Severity: `Medium`
  Evidence IDs: `SCR-04`, `BASE-04`, `DOC-08`, `CODE-07`, `CODE-08`, `DOC-10`
  Why it matters: Acceptance criterion 10 depends on multiple unresolved owners being distinguishable without raw device names, but the current review could not verify that runtime path cleanly in simulator.
  Recommended fix: Add a deterministic unresolved-multi-owner fixture and require both screenshot evidence and a UI test for neutral owner disambiguation.
  Acceptance criteria: Simulator evidence shows multiple unresolved owners with neutral section labels, rows never expose device-like names, and the UI test fails if a blocked owner label leaks.
  Confidence: `High`

### 3.3 iOS Architecture Findings
- Finding ID: `ARCH-01`
  Severity: `High`
  Evidence IDs: `DOC-04`, `DOC-06`, `DOC-07`, `DOC-10`, `CODE-03`, `CODE-05`, `CODE-06`, `CODE-09`
  Why it matters: The proposal removes `ownerChip`, `currentMonthSummary`, and row-level share-state duplication, but it never defines a canonical invitee projection or migration boundary for those fields. The current service/model layer still encodes the old coupling, so the redesign can be implemented only in views and still leave the architecture semantically broken.
  Recommended fix: Add a canonical invitee projection contract that owns `ownerDisplayName`, `shareAvailabilityState`, `goalLifecycleState`, row summary content, and detail semantics. Route list and detail through that projection and deprecate legacy fields behind an adapter.
  Acceptance criteria: One mapper produces the invitee projection from cache/CloudKit state; list and detail do not read `ownerChip` or `currentMonthSummary` directly; state-axis mapping is exhaustive and unit-tested.
  Confidence: `High`

- Finding ID: `ARCH-02`
  Severity: `High`
  Evidence IDs: `DOC-05`, `DOC-01`, `CODE-03`, `CODE-05`, `CODE-10`
  Why it matters: The proposal says detail must align with the redesigned list but does not define the detail-side contract. The current detail screen still uses the same ownership chip and status semantics the list redesign is trying to eliminate, so a partial rollout can create two different semantic systems for the same shared goal.
  Recommended fix: Make detail an explicit consumer of the same canonical invitee projection as the list, and define which fields remain only for diagnostics versus user-facing copy.
  Acceptance criteria: List and detail resolve owner identity the same way, use the same read-only semantics, and do not expose conflicting ownership/status copy after migration.
  Confidence: `High`

- Finding ID: `ARCH-03`
  Severity: `Medium`
  Evidence IDs: `DOC-08`, `DOC-09`, `DOC-10`, `CODE-07`, `CODE-08`, `SCR-04`, `BLOCKER-01`, `BLOCKER-02`
  Why it matters: The proposal bans device-style owner labels but does not define where normalization lives or how all runtime paths are forced through it. Today CloudKit fallback, test seeding, and runtime evidence are still inconsistent enough that label leaks remain plausible.
  Recommended fix: Add a dedicated owner-identity resolver in the data/projection layer with blocked-label handling, deterministic neutral fallback generation, and shared use across CloudKit, previews, and test fixtures.
  Acceptance criteria: No user-facing path can emit blocked device-like owner labels, all fallback labels come from one tested resolver, and multi-owner fallback naming is deterministic.
  Confidence: `Medium`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict: Removing the outer owner card reduces clutter but also removes the current grouping affordance.
  Tradeoff: Lower visual noise versus weaker owner-group scanability.
  Decision: Keep the removal, but only with an explicit replacement owner-header/separator pattern in the proposal.
  Owner: Design / proposal author

- Conflict: Section-level share-health priority can accidentally suppress meaningful row lifecycle states.
  Tradeoff: Cleaner rows versus loss of per-goal truth in unhealthy sections.
  Decision: Suppress only the generic positive share chip; preserve `Achieved` and `Expired` when they apply.
  Owner: Product + design + iOS implementation

- Conflict: Renaming the section without resolving the existing green explainer banner can leave duplicate shared-surface entry cues.
  Tradeoff: Faster copy change versus continued top-of-screen hierarchy confusion.
  Decision: One shared-surface entry treatment only; the banner must be removed, demoted, or fully absorbed into the new section pattern.
  Owner: Design / proposal author

- Conflict: View-only redesign is faster, but it risks leaving list and detail on divergent semantic models.
  Tradeoff: Faster UI patch versus persistent architectural drift.
  Decision: Define the canonical invitee projection before implementation starts.
  Owner: iOS architecture / proposal author

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P0 | Add canonical invitee projection and migration boundary for owner identity, share health, lifecycle, and row/detail semantics. | iOS Architecture | Proposal author + iOS lead | Before implementation | None | Proposal defines one projection contract and one mapper boundary; no legacy field is needed directly by list/detail UI. | `ARCH-01`, `ARCH-02`, `ARCH-03` |
| P0 | Clarify state-precedence rules so section health never suppresses meaningful row lifecycle chips. | UX | Proposal author | Before implementation | Canonical projection decision | Proposal explicitly states when `Achieved` and `Expired` remain visible in unhealthy sections. | `UX-01` |
| P1 | Specify the row-compression contract for narrow widths and large Dynamic Type. | UI | Proposal author + design | Before implementation | None | Acceptance criteria include 320pt width and accessibility text-size behavior with no wrapped chip or illegible amount row. | `UI-01` |
| P1 | Specify the replacement owner-group visual affordance after outer-card removal. | UI | Proposal author + design | Before implementation | None | Owner groups remain visually distinct in mock/runtime evidence without nested card chrome. | `UI-02` |
| P1 | Resolve top-level banner/title treatment for `Shared with You`. | UX/UI | Proposal author + design | Before implementation | None | First viewport has one coherent shared-surface entry concept and no lingering `Shared Goals` copy. | `UI-04`, `UX-02` |
| P2 | Add deterministic unresolved-multi-owner fixtures plus screenshot/UI-test evidence. | UX + Architecture | iOS team | During implementation | Canonical owner resolver | Multi-owner simulator capture is clean, and UI tests fail if blocked owner labels appear. | `UX-GAP-01`, `ARCH-03` |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Row layout | Shared-goal row readability at default and large Dynamic Type sizes | Before/after screenshots; UI test for row hierarchy; preview coverage for long title and long owner name | No wrapped chip; no clipped amount row; VoiceOver reading order preserved | Proposal update review before implementation | Hold implementation if compression behavior is still implicit |
| State semantics | Correct separation of section-level share health and row-level lifecycle | Unit tests for projection mapping; UI tests for active, stale, removed, achieved, expired combinations | No duplicate generic share-state chip on rows; `Achieved` / `Expired` preserved when applicable | Architecture signoff before UI coding | Hold if share-health/lifecycle precedence remains ambiguous |
| Owner identity | Blocked-label suppression and neutral fallback behavior | Unit tests for owner resolver; UI test for blocked device-like labels; clean multi-owner simulator evidence | No user-facing `iPhone`, `iPad`, `Mac`, `Unknown device`, or similar placeholders | Proposal update review plus implementation PR review | Hold if owner normalization is not centralized |
| List/detail parity | Semantic alignment between shared-goal list and detail | Snapshot/UI evidence for both list and detail; projection model coverage | No contradictory ownership/read-only/state copy between list and detail | Mid-implementation design review | Hold if detail keeps legacy semantics while list migrates |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- GAP-01: Multi-owner unresolved-owner runtime behavior was not cleanly reproduced in simulator (`SCR-04`, `BASE-04`, `BLOCKER-01`).
- GAP-02: CloudKit no-account warnings reduced confidence in live-backed validation for invitee states (`RUN-02`, `BLOCKER-02`).

### Open Questions
- QUESTION-01: Should the current top-level green explainer banner be removed entirely, or retained only as a much quieter helper within the redesigned section?
- QUESTION-02: After share health is removed from the row-level state path, where exactly will achieved/expired lifecycle mapping live in the canonical invitee projection?
