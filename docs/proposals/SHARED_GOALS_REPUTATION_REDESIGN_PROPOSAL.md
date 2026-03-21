# Shared Goals Reputation Redesign Proposal

> Incident mapping: client-visible shared-goals list layout failure on iPhone invitee screen

| Metadata | Value |
|---|---|
| Status | Draft |
| Priority | P0 Reputation Recovery |
| Last Updated | 2026-03-21 |
| Platform | iOS |
| Scope | Shared goals invitee-surface IA, row layout, ownership copy, state hierarchy |
| Affected UI | `ContentView`, `SharedGoalsSectionView`, `SharedGoalRowView`, `SharedGoalDetailView`, `FamilySharingModels` |

---

## 0) Incident Summary

A client screenshot shows the new `Shared Goals` list in a visually broken state:

1. a large green circular badge with `Shared by family` wraps into multiple lines,
2. owner identity is rendered as `iPhone` instead of a human label,
3. the section uses excessive nested card chrome,
4. ownership, state, progress, and monetary values compete for attention.

This is not a minor polish issue. It makes a financial sharing feature look unreviewed and undermines trust.

## 0.1 Why This Is a Reputation Incident

Read-only family sharing is a trust-sensitive feature. Users should immediately understand:

1. whose goal this is,
2. whether they can edit it,
3. whether the goal is healthy or in an exceptional state,
4. how close the goal is to the target.

The current screen communicates none of these cleanly. The visual failure is obvious even in a casual photo, which makes it a product reputation problem rather than a normal design backlog item.

## 0.2 Why This Proposal Is a Redesign, Not a Hotfix

The incident was triggered by poor generic design decisions, not by a single broken constraint.

Because of that, the correct response is not:

1. hide one badge,
2. tweak one spacing token,
3. patch one label and move on.

The correct response is to redesign the shared-goals invitee surface so that ownership, status, progress, and trust signals have a coherent information architecture. The client is willing to wait for a proper solution, so this proposal intentionally treats the incident as a trigger for a focused redesign, not a quick visual bandage.

## 1) Problem

The current shared-goals list has five structural design flaws:

1. Ownership is expressed as a decorative badge instead of factual metadata.
2. Active state uses `Shared by family` as if it were a status label.
3. The row hierarchy is overloaded:
   title, share ownership, monthly summary, status, progress, and amounts all compete.
4. The section is nested inside an additional card container, which creates clutter and makes each row look cramped.
5. Share availability state and goal lifecycle state are conflated into the same visual treatment, so the user cannot tell whether a goal itself is healthy or the share is unhealthy.

## 2) Goal

Deliver a proper redesign for the shared-goals invitee surface so it feels deliberate, trustworthy, and human-readable on first glance, without changing the underlying CloudKit sharing model.

## 3) Non-Goals

This redesign does not include:

1. CloudKit sharing architecture changes,
2. participant management redesign,
3. full shared-detail redesign,
4. Android parity in the same pass,
5. a broader family-sharing feature rebrand.

## 4) Decision-Locked Fix Direction

The following decisions are locked for this redesign:

1. Remove the decorative circular `Shared by family` badge from shared goal rows.
2. Ownership and state must be represented separately.
3. Healthy shared rows must not show a generic `Shared by family` status chip.
4. Device names must never be shown as the primary owner identity in the invitee list.
5. The outer shared-owner card wrapper must be removed; the list should use standard section grouping plus standalone row cards.
6. Shared row metadata must collapse to one stable ownership line:
   `Shared by {ownerName} · Read-only`
7. If no trusted human-readable owner name is available, the fallback must be:
   `Shared by family member · Read-only`
8. `currentMonthSummary` must not be shown on the list row by default.
9. Financial progress and amounts are the primary signal; status is secondary and only elevated when exceptional.
10. Share availability is a section-level concern; goal lifecycle is a row-level concern.
11. The only default row-level lifecycle chips in v1 redesign are `Achieved` and `Expired`.
12. The current full-width green explainer banner is removed from the invitee list first viewport.
13. One canonical invitee projection owns owner identity, share availability, goal lifecycle, row summary, and detail semantics.
14. One owner-identity resolver owns blocked-label suppression and deterministic neutral fallback naming.
15. Section header, section banner, and section primary action semantics must come from the same source of truth as row and detail semantics.
16. Persisted cache records, preview fixtures, and UI-test seeds must migrate to the new contract and must not be allowed to rehydrate legacy copy or state fields.

## 5) Proposed UX Contract

## 5.1 Screen Information Architecture

The iPhone goals screen should keep this order:

1. monthly planning widget,
2. `Shared with You`,
3. `Your Goals`.

`Shared Goals` should be renamed to `Shared with You` because the screen is invitee-facing and the copy should reflect the user’s perspective.

Top-of-screen entry treatment is locked:

1. remove the current full-width green explainer banner,
2. use the section title `Shared with You` as the only primary entry cue,
3. if helper copy is still needed, it may appear once as a subdued secondary line directly under the section title, not as a separate green callout surface,
4. no `Shared Goals` copy remains on the invitee list.

## 5.2 Owner Grouping Contract

Shared goals stay grouped by owner, but the grouping must be visually lighter:

1. use a standard owner section header,
2. remove the extra outer card surface around the owner group,
3. keep standalone shared goal cards directly under the owner header,
4. preserve sticky or visually persistent owner cues where platform list behavior supports them.
5. replace the removed owner-card chrome with explicit section spacing and divider rules.

Owner header content:

1. owner display name,
2. optional shared-state summary only when the owner section is not healthy,
3. optional goal count if needed for scannability.
4. if multiple unresolved owner identities exist, the header may use deterministic neutral labels such as `Family member 1`, `Family member 2`, but must not fall back to device names.

Replacement owner-group affordance:

1. owner header sits on plain list background, not inside an extra card,
2. header-to-first-row spacing is visually tighter than section-to-section spacing,
3. rows in the same owner group are separated by consistent vertical spacing,
4. adjacent owner groups are separated by a stronger divider or spacing break than rows within a group,
5. any optional background banding must remain subtle and must not recreate nested-card noise,
6. the same grouping affordance must remain readable in both light and dark appearances.

## 5.3 Shared Goal Row Contract

Each shared row must follow a strict 4-layer hierarchy:

1. Top row:
   emoji tile, goal title, optional exceptional status chip, chevron.
2. Metadata row:
   `Shared by {ownerName} · Read-only`
3. Progress row:
   progress bar only.
4. Amount row:
   `{currentAmount} of {targetAmount}`

Example:

- `Piano for daughter`
- `Shared by Anna · Read-only`
- progress bar
- `EUR 0 of EUR 500`

### 5.3.1 Row Compression Contract

The redesign must define explicit narrow-width and Dynamic Type behavior.

Layout priority order:

1. goal title,
2. amount row,
3. ownership metadata,
4. lifecycle chip,
5. chevron.

Compression rules:

1. title stays at max 2 lines before any other text is allowed to break,
2. ownership metadata stays on a single truncated line,
3. lifecycle chip never wraps,
4. generic positive share chips do not exist in the row at all,
5. if horizontal space becomes constrained, the lifecycle chip moves below the title before the title or metadata become unreadable,
6. if the amount row can no longer remain legible on one line, it may switch to a two-line stacked amount layout before overlap is allowed,
7. on a 320pt-wide device at the largest supported Dynamic Type size, title, ownership metadata, lifecycle chip, and amount row must remain readable without overlap or clipped text.

## 5.4 Status Contract

Status must no longer be conflated with ownership, and the redesign must explicitly separate two different state axes.

Axis A: share availability state, owned by the owner section:

1. `invitePendingAcceptance`
2. `emptySharedDataset`
3. `active`
4. `stale`
5. `temporarilyUnavailable`
6. `revoked`
7. `removedOrNoLongerShared`

Rules for share availability state:

1. it is communicated at section level, not as a generic row chip,
2. `active` must not render a decorative positive status chip on every row,
3. `stale`, `temporarilyUnavailable`, `revoked`, and `removedOrNoLongerShared` must use section-level state treatment first,
4. when a section is not healthy, section-level state messaging has priority over row-level decorative states,
5. section-level state messaging suppresses only the generic positive share chip path, not meaningful row-level lifecycle chips.

Axis B: goal lifecycle or goal outcome state, owned by the row:

1. healthy in-progress goal:
   - no chip by default.
2. achieved goal:
   - green chip: `Achieved`
3. expired goal:
   - warning/error chip: `Expired`

When a section is unhealthy:

1. `Achieved` remains visible when it is true,
2. `Expired` remains visible when it is true,
3. no additional row-level share-health chip is shown,
4. the section banner is the only share-health warning pattern.

Non-default row summaries:

1. `Just started`
2. `On track for this month`
3. `Retry refresh to confirm latest total`

These may remain available for detail screens or diagnostics, but they must not occupy the default shared-goal row.

This keeps normal rows calm, gives exceptional states a clear place, and removes the current ambiguity where `Shared by family` pretends to be a status.

### 5.4.1 Section-Level Unhealthy State Pattern

All unhealthy owner sections must use one stable component pattern.

Component contract:

1. one icon,
2. one title line,
3. one supporting copy block capped to two lines in the default list viewport,
4. optional primary action underneath when the state requires recovery,
5. one tint per severity level,
6. one banner per owner section, never repeated per row.

Suppression rules:

1. no row-level share-health badge or duplicate warning copy beneath the same section banner,
2. healthy rows beneath the section remain visually calm,
3. row-level lifecycle chips stay visible when meaningful.

## 5.5 Ownership Copy Contract

The owner label must be human-first.

Source priority:

1. trusted person name from CloudKit share identity,
2. trusted app-level owner display name,
3. fallback `family member`.

Blocked raw owner labels in user-facing UI:

1. `iPhone`
2. `iPad`
3. `Mac`
4. `Unknown device`
5. other device-like placeholders

If the resolved owner name matches a blocked device-style label, the row must use:

- `Shared by family member · Read-only`

If multiple unresolved owners are visible at once:

1. the row metadata may stay `Shared by family member · Read-only`,
2. the owner section header must add a deterministic neutral disambiguator,
3. no row or section may expose the raw device name as the fallback identity.

## 5.6 Visual Style Contract

The visual treatment must shift from decorative green surfaces to quiet financial clarity.

Rules:

1. no text inside circular badges,
2. no large green ownership badge,
3. one row card surface only,
4. neutral or near-opaque card backgrounds,
5. progress bar and amounts are the primary visual signal,
6. ownership metadata uses secondary text styling,
7. status color is reserved for actual exceptional state signaling.

## 5.7 Shared Detail Alignment

The shared detail screen should align with the same semantic contract:

1. ownership shown as factual metadata,
2. `Read-only` shown clearly,
3. no reuse of `Shared by family` as a decorative active-state badge,
4. no device-name owner labels.

This proposal does not redesign the full detail screen end-to-end, but the detail screen must not contradict the redesigned list contract.

## 5.8 Canonical Invitee Projection Contract

The redesign must not be implemented as view-only cleanup over the current overloaded model.

Canonical projection requirement:

1. introduce one invitee-facing projection contract that is the only user-facing source for list and detail,
2. the projection owns:
   - `ownerDisplayName`,
   - `ownerIdentityKind`,
   - `shareAvailabilityState`,
   - `goalLifecycleState`,
   - `rowSummaryStyle`,
   - `amount/progress display fields`,
   - `detail header semantics`,
3. list and detail read this projection, not legacy `ownerChip` or `currentMonthSummary` fields,
4. existing overloaded fields may remain temporarily behind an adapter, but they are no longer direct UI inputs,
5. state-axis mapping must be exhaustive and unit-tested.

### 5.8.1 Section Projection Ownership

Section semantics must not remain view-derived.

Locked contract:

1. the same mapper that emits row and detail semantics must also emit section-boundary semantics,
2. this may be implemented as:
   - one canonical invitee projection with embedded section semantics,
   - or one canonical row/detail projection plus one formal `InviteeOwnerSectionProjection` derived by the same mapper,
3. whichever implementation is chosen, section semantics are not computed ad hoc in views.

The section projection owns:

1. owner header title,
2. owner header subtitle suppression,
3. unhealthy-state banner title,
4. unhealthy-state banner supporting copy,
5. primary action title,
6. primary action availability,
7. group-level scannability metadata such as optional goal count,
8. unresolved multi-owner neutral disambiguation.

View-level restrictions:

1. no view computes `summaryCopy` directly,
2. no view computes `primaryActionTitle` directly,
3. no view recomposes legacy share-state semantics from raw state enums or strings,
4. section, row, and detail must all be fed from the same owned mapping boundary.

Owner identity resolver requirement:

1. one dedicated resolver in the projection/data layer normalizes owner identity,
2. blocked labels are suppressed there, not in scattered view code,
3. the same resolver must be used by:
   - CloudKit-backed runtime mapping,
   - local cache mapping,
   - previews,
   - UI-test fixtures,
4. unresolved multi-owner naming must be deterministic.

## 5.9 Migration and Deprecation Contract

The redesign changes user-facing semantics, so it requires an explicit migration and deprecation path.

Persisted/cache migration:

1. any cached or persisted invitee projection data using legacy list semantics must be either:
   - deterministically adapted into the new projection contract,
   - or invalidated and rebuilt,
2. no old cached record may resurrect:
   - `Shared Goals` as invitee section copy,
   - `Shared by family` as a generic positive row status,
   - blocked device-like owner labels,
   - direct `ownerChip` or `currentMonthSummary` row rendering.

Fixture and preview migration:

1. preview models must be updated to express the new contract directly,
2. UI-test seeds must be updated to emit the new projection contract rather than legacy copy fields,
3. no test fixture should pass only because the view still accepts legacy overloaded fields.

Deprecation boundary:

1. legacy fields such as `ownerChip` and `currentMonthSummary` may remain temporarily inside adapters for compatibility,
2. they are deprecated as direct user-facing inputs,
3. list and detail views must not bind to them directly after the redesign migration lands.

## 6) Layout and Accessibility Safeguards

The redesigned surface must explicitly prevent a repeat of the screenshot failure.

Rules:

1. title max 2 lines,
2. metadata row max 1 line,
3. status chip must never wrap,
4. no critical text inside circular surfaces,
5. row must remain readable at larger Dynamic Type sizes,
6. if horizontal space becomes constrained, chip priority drops before title and ownership metadata become illegible,
7. VoiceOver must read the row in this order:
   goal name, owner, read-only, state if exceptional, current amount, target amount.
8. multiple unresolved owners must still be visually distinguishable at section level without leaking device-style owner names.
9. list and detail must expose the same owner identity and read-only semantics for the same shared goal.
10. active healthy sections default to section title plus owner identity only; no extra helper subtitle or duplicate explanatory surface appears in the first viewport.

## 7) Implementation Scope

Primary files for this redesign:

1. `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/ContentView.swift`
2. `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift`
3. `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalRowView.swift`
4. `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingComponents.swift`
5. `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/FamilySharingModels.swift`
6. `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift`
7. `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift`
8. `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift`
9. `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareTestSeeder.swift`
10. `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift`
11. persisted family-sharing cache / projection compatibility path in the family-sharing data layer

Implementation tasks:

1. Remove the top-level green explainer banner from the invitee list and replace it with one coherent `Shared with You` entry treatment.
2. Remove outer owner-group card surface from `SharedGoalsSectionView`.
3. Add the replacement owner-group affordance: header spacing, section separation, and light/dark-safe grouping treatment.
4. Redesign `SharedGoalRowView` around the new 4-layer hierarchy and the explicit row-compression contract.
5. Change active-state row behavior to omit the generic share chip.
6. Normalize owner identity and block device-name fallbacks through one dedicated resolver.
7. Introduce one canonical invitee projection and route both list and detail through it.
8. Split share availability mapping from goal lifecycle mapping so the row no longer treats sharing health as a goal status.
9. Move `currentMonthSummary` out of the shared row default layout.
10. Update shared-detail header semantics to match the same projection and ownership contract.
11. Add deterministic unresolved-multi-owner fixtures for previews and UI tests.
12. Migrate or invalidate old cached/seeded invitee semantics so legacy copy and blocked owner labels cannot reappear after rollout.

## 8) Acceptance Criteria

The redesign is complete only when all of the following are true:

1. No shared goal row contains a circular badge with wrapped ownership text.
2. No invitee row shows `iPhone`, `iPad`, `Mac`, or `Unknown device` as the visible owner label.
3. Active shared rows no longer use `Shared by family` as a status chip.
4. The shared-owner group no longer nests rows inside an extra decorative card.
5. In the first viewport of a default-size iPhone screen, there is one coherent shared-surface entry treatment and no competing green explainer banner.
6. In the first viewport of a default-size iPhone screen, at least two consecutive shared rows show all four core layers without critical truncation:
   title, ownership line, progress bar, amount row.
7. On a 320pt-wide device at the largest supported Dynamic Type size, title, ownership metadata, chip, and amount row remain readable without overlap, wrapped chip text, or clipped amount values.
8. Exceptional statuses remain visible without competing with ownership metadata.
9. Share availability state is rendered at section level and is no longer reused as a decorative healthy row chip.
10. `Achieved` and `Expired` remain visible when applicable, including inside stale, unavailable, removed, or otherwise unhealthy sections.
11. Multiple unresolved owner identities remain distinguishable at section level without exposing raw device names.
12. One canonical projection feeds both list and detail, and neither surface reads legacy `ownerChip` or `currentMonthSummary` directly.
13. Section header, banner, and primary action semantics come from the same owned mapper contract as row and detail semantics.
14. Old cached or seeded invitee data cannot reintroduce `Shared Goals`, `Shared by family` as a generic row state, blocked owner labels, or legacy row semantics after migration.

## 9) Test and Evidence Plan

Required evidence:

1. before/after screenshots on iPhone,
2. long goal title preview,
3. long owner name preview,
4. blocked device-name fallback preview,
5. Dynamic Type preview at large accessibility size,
6. multi-owner unresolved identity preview,
7. before/after evidence with two owner groups visible in the same viewport,
8. UI test assertion that no circular or wrapped `Shared by family` ownership badge remains on shared-goal rows,
9. UI test assertion that owner fallback is `family member` when the source label is device-like,
10. UI test assertion that section-level unhealthy state does not force a generic positive share chip onto active rows,
11. unit test coverage for canonical invitee projection mapping,
12. unit test coverage for deterministic owner-identity normalization and unresolved multi-owner fallback naming,
13. migration test coverage for pre-change cached/seeded invitee data adapting or invalidating correctly,
14. parity test coverage proving section, row, and detail semantics are emitted from the same mapper boundary.

Recommended runtime scenarios:

1. active shared goal,
2. achieved shared goal,
3. expired shared goal,
4. stale shared goal,
5. unavailable owner section,
6. missing owner display name,
7. two unresolved owners visible at the same time,
8. achieved goal inside a healthy share section,
9. expired goal inside a healthy share section,
10. achieved goal inside a stale or unavailable share section,
11. expired goal inside a stale or unavailable share section,
12. pre-change cached invitee data loaded after redesign migration,
13. pre-change seeded fixture loaded through UI tests after redesign migration.

## 10) Rollout

This should ship as an incident-driven redesign, not as a quick band-aid or a later polish batch.

Recommended sequence:

1. redesign the list row and owner grouping,
2. normalize owner labels and copy,
3. align shared detail header semantics,
4. capture evidence pack,
5. release in the next family-sharing build after design evidence review.

## 11) Open Questions Resolved

1. Is the main issue copy or layout?
   - both, but layout is the visible incident trigger.
2. Should ownership remain a badge?
   - no, ownership becomes metadata.
3. Should active state always show a pill?
   - no, active rows stay visually calm.
4. Should device names ever be shown to invitees?
   - no.
5. Should this remain a quick hotfix?
   - no, the incident is the trigger for a proper redesign of the affected shared-goals surface.
6. Should share health and goal lifecycle remain one combined row state?
   - no, share health is section-level and goal lifecycle is row-level.
7. Should the current green explainer banner remain at the top of the invitee list?
   - no, it is removed and replaced by one coherent `Shared with You` entry treatment.
8. Can list and detail continue to read legacy `ownerChip` and `currentMonthSummary` directly?
   - no, both must migrate to one canonical invitee projection.
9. Where does blocked owner-label normalization live?
   - in one dedicated owner-identity resolver in the projection/data layer.
10. Who owns section header, banner, and primary action semantics?
   - the same mapping boundary that owns row and detail semantics.
11. How are old cached and seeded semantics handled?
   - they must be adapted or invalidated deterministically; they cannot be allowed to resurrect legacy copy or state behavior.
