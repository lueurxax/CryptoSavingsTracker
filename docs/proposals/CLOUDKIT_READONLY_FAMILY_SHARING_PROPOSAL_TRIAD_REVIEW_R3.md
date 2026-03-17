# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed:
  - `docs/proposals/CLOUDKIT_READONLY_FAMILY_SHARING_PROPOSAL.md`
  - `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md`
  - `docs/CLOUDKIT_MIGRATION_PLAN.md`
  - `docs/runbooks/cloudkit-cutover-release-gate.md`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift`
  - `ios/CryptoSavingsTracker/Utilities/PersistenceController.swift`
  - `ios/CryptoSavingsTracker/Views/ContentView.swift`
  - `ios/CryptoSavingsTracker/Views/GoalDetailView.swift`
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift`
- Internet sources reviewed:
  - Apple CloudKit participant, acceptance, sharing-controller, and SwiftUI share-invitation guidance
  - Apple HIG guidance for activity views and destructive alerts
  - CFPB 2024 personal financial data rights final rule
- Xcode screenshots captured:
  - `docs/screenshots/review-cloudkit-family-sharing-r3/current-goals-root-no-shared-entry-preview-iphone-light.png`
  - `docs/screenshots/review-cloudkit-family-sharing-r3/current-goal-detail-owner-surface-preview-iphone-light.png`
  - `docs/screenshots/review-cloudkit-family-sharing-r3/current-settings-local-bridge-entry-preview-iphone-light.png`
- Remaining assumptions:
  - Full-goal-set sharing remains the intended v1 product simplification.
  - The proposal text is meant to be normative, not merely suggestive implementation guidance.
  - Current-state Xcode previews are sufficient because the feature is still proposal-only.

## 1. Executive Summary
- Overall readiness: `Amber-Green`
- Top 3 risks:
  1. The proposal locks CloudKit share acceptance to the wrong lifecycle hook for a scene-based SwiftUI app.
  2. The shared-data sync layer is still missing an explicit actor/serialization model and local cache evolution policy.
  3. Invitee trust moments after acceptance and during revoke remain under-designed for a finance workflow.
- Top 3 opportunities:
  1. Most `R2` structural gaps are now closed: atomic publish, scope acknowledgment, multi-owner grouping, cache namespace isolation, accessibility, and rollout thresholds are all present.
  2. The proposal is now largely implementation-shaped rather than purely directional.
  3. The remaining issues are concentrated in lifecycle correctness, recovery UX, and visual simplification rather than product strategy.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 8 | 0 | 1 | 2 | 1 |
| UX (Financial) | 8 | 0 | 2 | 2 | 0 |
| iOS Architecture | 7 | 0 | 1 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Shared-detail hierarchy is still too dense for a single Liquid Glass viewport.
  - Evidence:
    - `DOC-05`, `DOC-06`, `DOC-07`
  - Why it matters:
    - The proposal now includes all the right ingredients, but on iPhone the combined stack of owner identity, read-only badge, freshness, dominant state banner, and multiple summary cards risks visual competition. In a finance read-only surface, the first viewport needs a single obvious primary surface.
  - Recommended fix:
    - Collapse the active shared-detail header into one primary hero surface that contains identity and freshness.
    - Keep non-active states as the only dominant card when they apply, with secondary metrics pushed lower.
  - Acceptance criteria:
    - At default and large Dynamic Type on iPhone and iPad, the first viewport shows one unmistakable primary surface.
    - No clipped labels or competing chip/card hierarchy appears above the fold.

- [Medium] No explicit motion contract exists for accept, revoke, and state transitions.
  - Evidence:
    - `DOC-03`, `DOC-05`, `DOC-06`
  - Why it matters:
    - Without a defined motion system, transitions between `Goals`, `Shared Goals`, and stale/unavailable/revoked states can feel abrupt and disorienting.
  - Recommended fix:
    - Add a motion contract for list-to-detail transitions, state-banner swaps, refresh, and revoke outcomes, with a Reduce Motion fallback.
  - Acceptance criteria:
    - State changes animate consistently.
    - Refresh and revoke do not cause unexpected first-viewport reflow.

- [Medium] `Settings -> Family Access` still needs a stronger visual-management treatment.
  - Evidence:
    - `DOC-02`, `DOC-06`, `SCR-03`
  - Why it matters:
    - Even though the proposal now says this row should be distinct, it still does not specify enough to stop implementation from producing a passive-looking settings row.
  - Recommended fix:
    - Define stronger hierarchy, subtitle/supporting copy, and card-like row treatment so the surface reads as management rather than preference.
  - Acceptance criteria:
    - `Family Access` is visually distinct from neighboring settings rows within one glance.

- [Low] Multi-owner grouping still needs deterministic ordering.
  - Evidence:
    - `DOC-06`, `QUESTION-03`
  - Why it matters:
    - Owner groups that reshuffle between sessions weaken scanability and trust.
  - Recommended fix:
    - Define a stable section order and within-group row order.
  - Acceptance criteria:
    - Refreshes never reorder unrelated owner groups unexpectedly.

### 3.2 UX Review Findings
- [High] Invitee acceptance still lacks an explicit success and empty-state landing.
  - Evidence:
    - `DOC-02`, `DOC-06`, `DOC-07`, `SCR-01`
  - Why it matters:
    - The proposal explains how accepted shares should appear, but it does not define a visible success acknowledgment or what to show when an invitee has access but currently no shared goals. In a finance app, ambiguity after acceptance reads like failure or missing data.
  - Recommended fix:
    - Add a dedicated post-acceptance success state and a distinct shared-goals empty state in the `Goals` shell.
  - Acceptance criteria:
    - Cold-start and warm-start acceptance both produce a visible success acknowledgment.
    - Users with zero shared goals see an explicit empty state rather than a blank owner-only shell.

- [High] Revocation still needs a required destructive confirmation and recovery model.
  - Evidence:
    - `DOC-06`, `WEB-09`
  - Why it matters:
    - Revoking household access is a high-stakes trust action. The proposal now defines revoke outcomes, but it still does not require a confirmation that tells the owner who loses access, what happens to cached local data, and what recovery path remains.
  - Recommended fix:
    - Add a destructive confirmation sheet before revoke with access impact, local cache outcome, and re-invite/undo guidance.
  - Acceptance criteria:
    - Revoke cannot happen without explicit confirmation.
    - The confirmation explains access impact and local-data outcome in plain language.
    - Post-revoke UI states the recovery path clearly.

- [Medium] The mandatory scope preview remains too abstract for informed consent.
  - Evidence:
    - `DOC-06`, `WEB-10`
  - Why it matters:
    - Enumerating categories is better than nothing, but finance users need a concrete plain-language example of what another person will actually see.
  - Recommended fix:
    - Add an example-driven summary in the scope preview with one concrete shared-goal example and one excluded-field example.
  - Acceptance criteria:
    - Owners can accurately explain what is shared after one read.
    - First invite remains blocked until that preview is acknowledged.

- [Medium] Multi-owner grouping still needs a documented ordering rule.
  - Evidence:
    - `DOC-06`, `DOC-07`, `QUESTION-03`
  - Why it matters:
    - Grouping by owner is correct, but unstable ordering still creates avoidable cognitive load.
  - Recommended fix:
    - Define a stable owner-group order and row order and test it.
  - Acceptance criteria:
    - Owner groups always render in the same documented order across refreshes and launches.

### 3.3 Architecture Review Findings
- [High] Acceptance routing is locked to the wrong lifecycle hook.
  - Evidence:
    - `DOC-03`, `WEB-02`, `WEB-03`, `DOC-09`
  - Why it matters:
    - The proposal hard-codes `@UIApplicationDelegateAdaptor` plus `application(_:userDidAcceptCloudKitShareWith:)`, but Apple's current guidance for scene-based/SwiftUI apps is to use `windowScene(_:userDidAcceptCloudKitShareWith:)`. That mismatch is the most concrete remaining correctness issue in the document.
  - Recommended fix:
    - Keep the acceptance coordinator lifecycle-agnostic, but switch the primary production path to a scene-based delegate bridge.
    - Retain the app-delegate callback only as a compatibility shim if absolutely necessary.
  - Acceptance criteria:
    - Cold-start and warm-start acceptance both work through the scene path on iPhone/iPad.
    - No production path depends solely on the deprecated app-delegate callback.

- [Medium] The proposal still needs an explicit concurrency and serialization boundary for share sync.
  - Evidence:
    - `DOC-03`, `DOC-04`, `DOC-07`
  - Why it matters:
    - Accept, refresh, revoke, cache bootstrap, and publish all touch the same shared state. Serial draining per `ownerID/shareID` is helpful, but still too abstract without a concrete actor or serial-executor model.
  - Recommended fix:
    - Define one serialized ownership model per `ownerID/shareID` and explicitly state where CloudKit I/O, cache writes, publish work, and UI projection happen.
  - Acceptance criteria:
    - Concurrent accept/refresh/revoke/publish scenarios converge deterministically.
    - Tests prove no duplicate drains or cross-share contamination.

- [Medium] Local cache evolution and rollback policy are still under-specified.
  - Evidence:
    - `DOC-03`, `DOC-04`, `DOC-07`
  - Why it matters:
    - The proposal now chooses per-share SwiftData stores, but it still does not define local cache schema versioning, migration, rollback handling, or bounded cleanup policy for orphaned namespaces.
  - Recommended fix:
    - Add a local cache schema version, migration/bootstrap contract, and namespace retention/cleanup policy.
  - Acceptance criteria:
    - Upgrades across cache schema changes either preserve or cleanly rebuild shared caches.
    - Incompatible caches surface a defined recovery state rather than crashing or silently disappearing.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict:
  - Dense financial context vs. first-viewport clarity.
  - Tradeoff:
    - Showing identity, freshness, state, and metrics at once maximizes raw information, but weakens hierarchy on small screens.
  - Decision:
    - Prioritize a single primary shared-detail hero surface for active state and a single dominant state banner for non-active states.
  - Owner:
    - Product design

- Conflict:
  - System-first sharing UI vs. product-specific consent and recovery.
  - Tradeoff:
    - Native CloudKit UI improves trust and lowers implementation risk, but it does not fully explain full-goal-set scope, revoke impact, or acceptance success semantics.
  - Decision:
    - Keep system-first invite management, but require product-owned scope preview, success/empty states, and revoke confirmation/recovery layers.
  - Owner:
    - Product design + iOS architecture

- Conflict:
  - SwiftUI simplicity vs. correct CloudKit acceptance lifecycle.
  - Tradeoff:
    - App-delegate bridging may look simpler, but it conflicts with Apple’s current scene-based guidance.
  - Decision:
    - Use a lifecycle-agnostic acceptance coordinator with a scene-based primary production bridge.
  - Owner:
    - iOS architecture lead

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Replace deprecated app-delegate acceptance path with scene-based primary acceptance bridge | Architecture | iOS architecture lead | Now | Existing acceptance coordinator concept | Share acceptance matches Apple scene-based guidance and passes cold/warm-start tests |
| P1 | Add explicit post-acceptance success state and invitee empty state | UX | Product design | Next | Current `Goals` shell IA | Invite acceptance never feels ambiguous or broken |
| P1 | Add destructive revoke confirmation and recovery contract | UX | Product design | Next | Current owner-management flow | Owners understand revoke impact before committing |
| P1 | Define actor/serialization model for shared sync layer | Architecture | iOS architecture lead | Next | Existing outbox/publish contract | Concurrent share-sync flows resolve deterministically |
| P1 | Simplify active shared-detail first viewport and lock motion contract | UI | Product design | Next | Current visual contract | Shared-detail feels intentional, not dense or jumpy |
| P1 | Define stable multi-owner ordering and row ordering | UI/UX | Product design | Next | Existing owner-grouping decision | Grouped shared lists remain stable across refreshes |
| P2 | Add local cache schema version and migration/rollback policy | Architecture | iOS architecture lead | Later | Chosen SwiftData cache model | Shared caches survive schema evolution safely |

## 6. Execution Plan
- Now (0-2 weeks):
  - Correct the acceptance lifecycle hook.
  - Add explicit invitee success/empty states.
  - Add revoke confirmation and recovery semantics.
- Next (2-6 weeks):
  - Define the serialized shared-sync execution model.
  - Simplify the shared-detail viewport hierarchy and add motion rules.
  - Lock deterministic owner grouping order.
- Later (6+ weeks):
  - Add cache schema evolution and rollback policy, then validate the full system under upgrade and revocation edge cases.

## 7. Open Questions
- Should the proposal keep any app-delegate fallback at all once the scene-based acceptance bridge is added?
- Are the kill-switch thresholds intended to be final release criteria or beta-phase starter thresholds?
- Does owner-group ordering need product semantics such as recency or alphabetical owner name, or is any stable order acceptable?
