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
  - [`/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift`](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift)
  - [`/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL_TRIAD_REVIEW_R1.md`](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_REPUTATION_REDESIGN_PROPOSAL_TRIAD_REVIEW_R1.md)
- External sources reviewed:
  - None required for this repeat pass.
- Build/run attempts:
  - `RUN-01`: Xcode MCP build succeeded on `windowtab1`.
  - `RUN-02`: simulator launches succeeded for active, removed, and multi-owner scenarios on iPhone 16 simulator.
  - `RUN-03`: stale scenario launched but did not produce a clean stale viewport; prior validated stale evidence was reused as supplemental baseline.
- Screenshots captured:
  - `SCR-01` active invitee list (`R2`)
  - `SCR-02` removed / no-longer-shared invitee list (`R2`)
  - `SCR-03` stale invitee list (prior validated artifact reused)
  - `SCR-04` multi-owner attempt (`R2`, still not clean)
- Code areas inspected:
  - invitee shared-goals list entry
  - owner grouping
  - shared-goal row contract
  - shared-goal detail semantics
  - family-sharing models
  - service-layer mapping
  - CloudKit fallback mapping
  - UI test coverage
- Remaining assumptions:
  - Current family-sharing UI code is materially unchanged from the baseline the proposal is targeting.
  - This review is limited to the invitee-facing iPhone shared-goals flow.
- Remaining blockers:
  - Multi-owner runtime evidence is still incomplete (`BASE-04`, `BLOCKER-01`).
  - Stale rerun remained unstable (`RUN-03`, `BLOCKER-03`).
  - Large Dynamic Type / long-title / blocked-device fallback artifacts are not yet present in the prepared pack.

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `Medium`
- Release blockers:
  - None at proposal stage, but the document should not be treated as signoff-ready for implementation until the section-boundary ownership and migration/evidence gaps are closed.
- Top risks:
  1. The document now defines a canonical invitee projection for list/detail, but it still does not fully pin down section header/banner/action ownership, leaving room for a split adapter model.
  2. The proposal changes user-facing semantics, but it still lacks an explicit cache/fixture migration plan to keep old projection data and test seeds from reintroducing legacy copy and states.
  3. The hardest acceptance cases are still only partially evidenced: unresolved multi-owner identity, blocked-device fallback, and large Dynamic Type stress states.
- Top opportunities:
  1. The biggest R1 contract gaps are now closed: banner treatment, row-compression rules, state precedence, canonical projection, and owner resolver ownership are all materially improved.
  2. One more architecture pass to define section-boundary ownership would make the document much harder to misimplement.
  3. Finishing the missing edge-case evidence pack would likely move this proposal from `Amber` to near-signoff quality.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | Green | Medium | Partial | 0 | 0 | 1 | 0 |
| UX | Green | Medium | Partial | 0 | 0 | 0 | 0 |
| iOS Architecture | Amber | Medium | Partial | 0 | 1 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Findings
- Finding ID: `UI-01`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `SCR-01`, `CODE-01`, `CODE-02`, `BASE-01`
  Why it matters: The updated proposal removes the green explainer banner, which is correct, but it still allows optional helper copy beneath `Shared with You` and still allows owner-header subtitle text in active sections. Without a tighter suppression rule, the implementation can drift back toward the same “too many explanatory surfaces” problem in the first viewport.
  Recommended fix: Define an explicit active-state copy suppression rule: in healthy sections, default to section title plus owner name only; reserve helper/bad-news explanatory copy for unhealthy states.
  Acceptance criteria: In the active default viewport there is one primary entry cue and no duplicated explanatory line; unhealthy sections use exactly one explanatory surface plus the rows beneath it.
  Confidence: `Medium`

### 3.2 UX Findings
- No material new UX contract defects were confirmed in this pass.
- The major R1 UX ambiguity around row lifecycle chips inside unhealthy sections appears resolved by the updated text in sections `5.4` and `8`.

### 3.3 iOS Architecture Findings
- Finding ID: `ARCH-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `DOC-03`, `DOC-05`, `DOC-07`, `CODE-02`, `CODE-03`, `CODE-08`
  Why it matters: The proposal now introduces a canonical invitee projection for list and detail, but it still does not fully define who owns section header, section banner, and section action semantics. Current repo baseline computes those through separate paths, so the redesign can still be implemented as two adapters: one for section chrome and one for rows/detail. That would recreate semantic drift under a cleaner UI.
  Recommended fix: Expand the canonical projection so it also owns section-boundary semantics, or define a second formally owned section projection derived by the same mapper and governed by the same acceptance tests.
  Acceptance criteria: One mapper emits section header, section banner, row metadata, and detail header from the same source of truth; no view computes `summaryCopy`, `primaryActionTitle`, `ownerChip`, or `currentMonthSummary` directly; parity tests cover active, stale, removed, and multi-owner cases.
  Confidence: `Medium`

- Finding ID: `ARCH-02`
  Severity: `Medium`
  Evidence IDs: `DOC-06`, `DOC-07`, `DOC-08`, `DOC-09`, `CODE-05`, `CODE-06`, `CODE-07`, `CODE-09`
  Why it matters: The proposal changes the user-facing contract, but it still does not spell out the cache / fixture migration path needed to get there safely. Current repo state still contains legacy persisted and seeded semantics such as `Shared Goals`, `Shared Family`, `ownerChip`, and `currentMonthSummary`. Without a migration/deprecation plan, stale cached data or old fixtures can reintroduce the old behavior after rollout.
  Recommended fix: Add a versioned migration section for the cache/projection layer and explicitly require preview/UI-test seed updates to use the new contract instead of legacy copy fields.
  Acceptance criteria: Old cached/projection records are adapted or invalidated deterministically; no persisted or seeded path can resurrect `Shared Goals`, `Shared Family`, or blocked owner labels; migration tests cover pre-change records and updated fixtures.
  Confidence: `Medium`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict: The proposal correctly centralizes row/detail semantics, but section-level semantics are still partially outside that central contract.
  Tradeoff: Faster implementation via separate adapters versus stronger semantic consistency.
  Decision: Keep one owned source of truth across section, row, and detail semantics, even if this requires a formally separate section projection derived by the same mapper.
  Owner: Proposal author + iOS lead

- Conflict: Removing the banner reduces noise, but optional helper copy can quietly reintroduce a second explanatory surface.
  Tradeoff: Extra reassurance copy versus first-viewport clarity.
  Decision: Default healthy shared sections to the minimum copy needed for comprehension; reserve helper copy for exceptional states or explicitly gated contexts.
  Owner: Proposal author + design

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P0 | Define section-boundary ownership so section header/banner/action semantics are emitted from the same source of truth as row/detail semantics. | iOS Architecture | Proposal author + iOS lead | Before implementation | Existing canonical projection section | No view computes legacy family-sharing semantics directly; section, row, and detail parity tests pass from one mapper contract. | `ARCH-01` |
| P1 | Add an explicit cache / fixture migration and deprecation plan for legacy family-sharing semantics. | iOS Architecture | Proposal author + iOS lead | Before implementation | Section-boundary ownership decision | Old cached/seeded data cannot reintroduce `Shared Goals`, `Shared Family`, or legacy row semantics after rollout. | `ARCH-02` |
| P1 | Tighten active-state copy suppression so the healthy first viewport cannot accumulate extra explanatory text again. | UI | Proposal author + design | Before implementation | None | Active shared section shows one entry cue only and no duplicated helper surfaces. | `UI-01` |
| P1 | Complete edge-case evidence artifacts: long title, long owner name, blocked-device fallback, 320pt Dynamic Type, and clean unresolved multi-owner viewport. | Validation | iOS team | Before implementation signoff | Updated fixtures and previews | Evidence pack proves the proposal’s hardest acceptance cases rather than only asserting them. | Evidence gaps |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Section/source-of-truth parity | Whether section, row, and detail semantics all come from one owned mapper contract | Projection tests; parity tests across active/stale/removed states | No direct legacy-field reads in views | Architecture review before implementation starts | Hold if section semantics remain view-derived |
| Cache and fixture migration | Whether old data or seeds can resurrect legacy copy/state | Migration tests; updated preview/UI-test fixtures | No `Shared Goals`, `Shared Family`, or blocked labels from persisted/seeded inputs | Pre-implementation review | Hold if migration/deprecation behavior is unspecified |
| First-viewport clarity | Whether the active shared section stays calm after banner removal | Before/after screenshots; preview of active state | No duplicate helper surfaces in active viewport | Design review before implementation | Hold if helper copy rules stay optional/ambiguous |
| Edge-case readability and identity | Whether the hardest acceptance cases are actually proven | Dedicated screenshots/previews/tests for long-title, long-owner, blocked-label, 320pt, multi-owner | No clipped text, no overlap, no device-name leakage | Signoff review after proposal update | Hold if edge-case evidence is still missing |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- GAP-01: The prepared pack still lacks clean artifacts for long goal titles, long owner names, blocked-device fallback, 320pt large Dynamic Type, and a clean unresolved multi-owner viewport.
- GAP-02: The current `invitee_stale` rerun remained unstable, so stale-state evidence partly relies on the prior validated artifact.

### Open Questions
- QUESTION-01: Should the canonical invitee projection itself own section header/banner/action semantics, or should the document explicitly define a second section projection derived by the same mapper?
- QUESTION-02: Is any helper subtitle under `Shared with You` required in the healthy default state, or should healthy sections default to no secondary explanatory copy at all?
