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
  - Apple CloudKit participant, share-acceptance, sharing-controller, and shared-data guidance
  - Apple HIG guidance for activity views and destructive alerts
  - CFPB 2024 personal financial data rights final rule
- Xcode screenshots captured:
  - `docs/screenshots/review-cloudkit-family-sharing-r2/current-goals-root-no-shared-entry-preview-iphone-light.png`
  - `docs/screenshots/review-cloudkit-family-sharing-r2/current-goal-detail-owner-surface-preview-iphone-light.png`
  - `docs/screenshots/review-cloudkit-family-sharing-r2/current-settings-local-bridge-entry-preview-iphone-light.png`
- Remaining assumptions:
  - Full-goal-set sharing intentionally means future goals auto-share until access is revoked.
  - The feature remains proposal-only, so current-state preview evidence is sufficient for shell validation.
  - Collaborative multi-writer family planning remains out of scope.

## 1. Executive Summary
- Overall readiness: `Amber-Green`
- Top 3 risks:
  1. The proposal still lacks an atomic publish contract between owner writes and shared projection refresh, so invitees can theoretically see partially advanced state.
  2. Full-goal-set sharing is now explicit, but the owner trust moment before sending the invite is still not strong enough for a finance app.
  3. The local read-only cache and multi-owner invitee experience are still not fully nailed down.
- Top 3 opportunities:
  1. The proposal is materially stronger than `R1`: platform scope, navigation IA, share acceptance, projection schema, lifecycle states, and rollout basics are now present.
  2. The owner-vs-invitee split is now directionally correct: global owner management, dedicated invitee read-only surfaces, and no owner-detail reuse.
  3. The remaining gaps are narrower and implementation-oriented rather than foundational.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 7 | 0 | 1 | 2 | 0 |
| UX (Financial) | 7 | 0 | 1 | 1 | 1 |
| iOS Architecture | 6 | 0 | 1 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Shared-detail state hierarchy is still not locked tightly enough.
  - Evidence:
    - `DOC-05`, `DOC-06`, `SCR-02`
  - Why it matters:
    - The proposal now defines the right ingredients for a read-only detail screen, but it still does not force a strict visual priority order. In a finance surface, `stale`, `temporarilyUnavailable`, or `revokedOrRemoved` must dominate the first viewport; otherwise users will anchor on money/progress metrics and miss the trust state.
  - Recommended fix:
    - Lock the shared-detail vertical order: owner identity, read-only badge, dominant state banner/card, freshness line, then financial summary cards.
    - State banners for `stale`, `temporarilyUnavailable`, and `revokedOrRemoved` should override the normal active composition rather than sit beside it.
  - Acceptance criteria:
    - Every non-active state is recognizable in the first viewport on iPhone and iPad without scrolling.
    - The shared-detail layout cannot visually resemble the active state when data is stale, unavailable, or revoked.

- [Medium] Owner and invitee entry points still need clearer visual separation.
  - Evidence:
    - `DOC-02`, `DOC-09`, `DOC-10`, `SCR-01`, `SCR-03`
  - Why it matters:
    - The proposal correctly splits owner management into Settings and invitee consumption into `Goals`, but it still leaves too much room for implementation to make both areas look like ordinary settings/list rows. That weakens orientation and platform trust.
  - Recommended fix:
    - Specify a distinct row treatment for `Family Access` in Settings and a distinct section/header treatment for `Shared Goals` in the `Goals` shell.
  - Acceptance criteria:
    - A user can tell from the first screen whether they are in owner-management context or invitee-consumption context.
    - `Shared Goals` is visually separable from owned goals before a row is opened.

- [Medium] Material, contrast, and surface rules remain under-specified.
  - Evidence:
    - `DOC-05`, `DOC-06`, `WEB-05`, `WEB-09`
  - Why it matters:
    - The proposal now has anatomy, but not enough visual-system rules. Without explicit material and contrast guidance, a dense financial read-only surface can drift into decorative translucency or weak legibility.
  - Recommended fix:
    - Add material tokens for headers, metric cards, state banners, and recovery cards, and explicitly define opaque fallback rules for dark mode and dense-data states.
  - Acceptance criteria:
    - The design spec names the intended surface treatment for every shared-goals component and state.
    - No critical metric or state label depends on translucency for legibility.

### 3.2 UX Review Findings
- [High] Pre-share scope disclosure is still not explicit enough for a finance app.
  - Evidence:
    - `DOC-01`, `DOC-05`, `DOC-06`, `WEB-10`
  - Why it matters:
    - The proposal now says all current and future goals become visible while access is active, which is the right truth. But it still stops short of requiring a real scope-preview/acknowledgment step before the invite is sent. In a money app, users need to understand future-goal auto-sharing, visible fields, excluded fields, and revoke behavior before consent is committed.
  - Recommended fix:
    - Add a mandatory pre-share scope preview with explicit acknowledgment before sending the invite.
    - That preview should enumerate: current-goal coverage, future-goal auto-sharing, visible fields, excluded fields, and revoke behavior.
  - Acceptance criteria:
    - The share flow cannot send an invite until the owner has seen and acknowledged the scope preview.
    - The preview explicitly states that future goals will also be shared while access remains active.

- [Medium] Invitee ownership context in the `Goals` shell is still under-specified.
  - Evidence:
    - `DOC-02`, `DOC-05`, `DOC-06`, `SCR-01`, `SCR-02`, `QUESTION-01`
  - Why it matters:
    - The proposal now separates shared and owned goals, but it still does not define how shared rows are labeled when a user owns some goals and receives others, or when one invitee receives shared datasets from multiple different owners. In a finance app, ownership should never need to be inferred.
  - Recommended fix:
    - Require persistent ownership labels/badges at row level and define owner grouping rules for `Shared Goals` when multiple owners are present.
  - Acceptance criteria:
    - A user can identify whether a row is owned or shared without opening it.
    - Multiple-owner shared datasets are grouped or labeled in a way that prevents ambiguity.

- [Low] Lifecycle states need stronger accessibility and reason-specific trust copy.
  - Evidence:
    - `DOC-05`, `DOC-06`, `DOC-07`
  - Why it matters:
    - The state matrix is much better than `R1`, but it still does not require enough reason-specific explanation or accessibility behavior for `stale`, `temporarilyUnavailable`, and `revokedOrRemoved`.
  - Recommended fix:
    - Add reason-specific copy requirements plus VoiceOver, Dynamic Type, and non-color-only state signaling requirements.
  - Acceptance criteria:
    - Each non-active state explains why the data is in that state and what the user can do next.
    - Screen readers and large-text layouts preserve ownership and freshness context.

### 3.3 Architecture Review Findings
- [High] The proposal still needs an atomic publish boundary between owner writes and shared projection refresh.
  - Evidence:
    - `DOC-04`, `DOC-05`, `DOC-07`
  - Why it matters:
    - The schema and publish triggers are now much stronger, but there is still no explicit guarantee that owner mutations and projection republish move as one recoverable unit. Without that boundary, a crash or transient failure can leave invitees with partially advanced or semantically inconsistent shared state.
  - Recommended fix:
    - Add a dedicated family-sharing projection outbox/coordinator.
    - Owner mutations should enqueue projection publish work atomically, and `projectionVersion`/`publishedAt` should advance only after successful idempotent publish completion.
  - Acceptance criteria:
    - A crash or network failure between owner edit and publish never leaves invitees with partially updated shared records.
    - Retry is idempotent and converges to the authoritative owner state without duplicate projection records.

- [Medium] The local read-only cache/store is still too abstract.
  - Evidence:
    - `DOC-03`, `DOC-04`, `QUESTION-01`, `QUESTION-02`
  - Why it matters:
    - The proposal now correctly separates authoritative owner data from invitee cache state, but it still does not lock the cache technology or namespace boundary. That leaves room for collisions, cleanup bugs, and testing ambiguity, especially if one invitee holds shares from multiple owners.
  - Recommended fix:
    - Lock whether the cache is a separate SwiftData container, separate SQLite file, or another isolated cache layer, and key it by `ownerID/shareID`.
  - Acceptance criteria:
    - Multiple owner shares can coexist without collisions.
    - Revoking one share removes only that share namespace.
    - Cache rebuild and migration operate independently per share.

- [Medium] Share-acceptance routing and test seams are still not tied concretely enough to the current SwiftUI app shell.
  - Evidence:
    - `DOC-03`, `DOC-09`, `DOC-10`, `DOC-12`, `WEB-02`
  - Why it matters:
    - The proposal now names an app-level acceptance coordinator, but it still does not lock the exact lifecycle hook or injectable seams the current `CryptoSavingsTrackerApp` will use. That keeps cold-start/warm-start acceptance and deterministic testing less concrete than they should be.
  - Recommended fix:
    - Specify the exact iOS acceptance hook in this app and define protocols for accept, refresh, revoke, and cache bootstrap so the coordinator is injectable from the SwiftUI app shell.
  - Acceptance criteria:
    - Cold-start and warm-start invite acceptance both flow through the same coordinator path.
    - Unit and UI tests can simulate accept, revoke, stale, and unavailable states without real CloudKit dependency.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict:
  - Full-goal-set simplicity vs future-goal privacy surprise.
  - Tradeoff:
    - Full-goal-set sharing simplifies product and schema design, but it raises the trust bar because future goals auto-share by default.
  - Decision:
    - Keep full-goal-set sharing for v1, but make scope preview and owner acknowledgment mandatory before the first invite is sent.
  - Owner:
    - Product design

- Conflict:
  - System-first share management vs app-specific household explanation.
  - Tradeoff:
    - Native CloudKit sharing UI improves platform trust and lowers implementation risk, but it does not fully explain the product-specific meaning of “all goals, read-only, future goals included.”
  - Decision:
    - Keep invite creation/participant management system-first, but require a product-owned disclosure and visibility-review layer before and after the system UI.
  - Owner:
    - Product design + iOS architecture

- Conflict:
  - Lightweight cache abstraction vs hard authority isolation.
  - Tradeoff:
    - Leaving cache internals flexible preserves implementation freedom, but it weakens operability, cleanup, and testability.
  - Decision:
    - Lock the cache namespace and persistence boundary at proposal level before implementation begins.
  - Owner:
    - iOS architecture lead

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Add atomic projection publish contract with outbox/coordinator semantics | Architecture | iOS architecture lead | Now | Existing projection schema | No partial shared-state exposure across crash/retry scenarios |
| P0 | Add mandatory pre-share scope preview and owner acknowledgment | UX | Product design | Now | Locked full-goal-set model | Owners explicitly acknowledge future-goal auto-sharing and visible/excluded fields |
| P1 | Lock cache technology/namespace model for multi-owner safety | Architecture | iOS architecture lead | Next | P0 publish boundary | Multiple shares coexist without collisions or cleanup bleed |
| P1 | Define owner-grouping and ownership labeling rules in `Shared Goals` | UX/UI | Product design | Next | Current IA decision | Users can identify owner vs shared context at a glance, including multi-owner cases |
| P1 | Lock shared-detail visual priority order and state banner dominance | UI | Product design | Next | Existing shared-detail anatomy | Stale/unavailable/revoked states are visible in first viewport |
| P1 | Specify exact SwiftUI app-shell acceptance hook and test seams | Architecture | iOS architecture lead | Next | Current app lifecycle | Cold/warm accept flows and state simulations are deterministic in tests |
| P2 | Add material/contrast/accessibility rules for shared-goals surfaces | UI/UX | Product design | Later | Shared-detail layout | Final design is visually native and accessible across light/dark and Dynamic Type |

## 6. Execution Plan
- Now (0-2 weeks):
  - Add the atomic publish boundary.
  - Add the pre-share scope preview and acknowledgment requirement.
  - Decide and document the cache namespace/persistence boundary.
- Next (2-6 weeks):
  - Finish shared-goals list grouping and shared-detail visual hierarchy.
  - Lock the exact app-shell acceptance hook and protocol seams.
  - Convert the current rollout section into measurable operational gates.
- Later (6+ weeks):
  - Polish material/accessibility details and validate the final shared-goals surface across dark mode, Dynamic Type, and multi-owner data density.

## 7. Open Questions
- How should `Shared Goals` be grouped when one invitee receives shared datasets from multiple owners?
- Does the local read-only cache/store need to be locked now as a separate SwiftData container / SQLite file / other cache layer, or is architectural flexibility still acceptable?
- What quantitative thresholds should trigger the kill switch in rollout?
