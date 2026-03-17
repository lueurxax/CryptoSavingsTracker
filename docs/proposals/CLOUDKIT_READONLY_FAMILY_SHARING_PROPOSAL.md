# CloudKit Read-Only Family Sharing Proposal

## Status
Decision-locked draft (P0 priority; must ship before further Local Bridge Sync rollout)

## Decision Lock
The product direction in this document is decision-locked for sequencing:

1. Read-only family access to goals is a higher-priority user outcome than `Local Bridge Sync`.
2. New delivery work for `Local Bridge Sync` must not outrank or bypass this feature.
3. `Local Bridge Sync` remains valid as a separate capability, but its forward rollout is gated on this read-only sharing flow shipping first.

## Review-Driven Locked Decisions
This proposal incorporates review feedback from:

1. `CLOUDKIT_READONLY_FAMILY_SHARING_PROPOSAL_TRIAD_REVIEW_R1.md`
2. `CLOUDKIT_READONLY_FAMILY_SHARING_PROPOSAL_TRIAD_REVIEW_R2.md`
3. `CLOUDKIT_READONLY_FAMILY_SHARING_PROPOSAL_EVIDENCE_PACK_R3.md`
4. `CLOUDKIT_READONLY_FAMILY_SHARING_PROPOSAL_TRIAD_REVIEW_R4.md`

where applicable, adjusted for the later decision to remove goal-by-goal sharing.

Locked decisions:

1. v1 share scope is the owner's full goal set, not selected goals.
2. v1 invitee surfaces are in scope on iPhone and iPad only.
3. macOS is explicitly out of scope for v1 invitee consumption despite the existing macOS app shell.
4. Owner management is system-first where possible for invite creation and participant management, with custom product UI for pre-share disclosure and app-specific state presentation.
5. Invitee consumption uses a dedicated shared-goals surface, not the owner goal detail with actions removed.
6. Shared data is ingested from CloudKit shared-database records into a dedicated local read-only cache path, not into the owner's authoritative store.
7. Freshness state is normative: `stale` begins after 24 hours without a successful shared-dataset reconciliation.
8. Projection publishing uses an atomic outbox/coordinator model so invitees never observe partially advanced shared state.
9. The owner must acknowledge a mandatory pre-share scope preview before the first invite is sent.
10. Multi-owner invitee consumption is grouped by owner, not flattened into one unlabeled shared list.
11. The read-only cache is an isolated SwiftData-backed store namespace per `ownerID/shareID`.
12. iPhone/iPad share acceptance routes through an explicit scene-based acceptance bridge into a single `FamilyShareAcceptanceCoordinator`.
13. The first-invite scope preview uses a staged summary sheet with a sticky primary CTA and first-viewport readability requirements.
14. Shared finance surfaces reserve glass for navigation chrome and section framing only; numeric cards, freshness, and recovery states use opaque or near-opaque surfaces.
15. Each `ownerID/shareID` namespace is owned by an explicit serialized executor/actor boundary for accept, refresh, revoke, bootstrap, cleanup, and publish coordination.
16. Shared-cache migration is versioned, rebuild-first where needed, and downgrade fail-closed.
17. Namespace stores are lazy-opened, explicitly purged after revoke/remove, and bounded by lifecycle/resource rules rather than remaining open indefinitely.

## Goal
Allow the owner of goals in CryptoSavingsTracker to grant family members on Apple devices strict read-only access to the full goal set, using CloudKit-backed sharing semantics and a dedicated consumer experience that does not expose editing or planning authority.

## Terminology and Platform Boundary
In this document, "family" means household members whom the owner explicitly invites using Apple-device sharing flows.

Boundary clarifications:

1. This is not a requirement to depend on Apple's Family Sharing purchase group.
2. The first shipping cut targets iPhone and iPad only, with Apple-account-backed invitees.
3. The product contract is invite-based household read access, not open public sharing.

## Platform Matrix and Navigation IA
The app shell contract for v1 is explicit:

| Concern | iPhone | iPad | macOS v1 |
| --- | --- | --- | --- |
| Owner entry point | `Settings -> Family Access` | `Settings -> Family Access` | Out of scope |
| Invitee entry point | `Goals` root with dedicated `Shared Goals` section | `Goals` root with dedicated `Shared Goals` section | Out of scope |
| Share acceptance routing | Scene-based acceptance coordinator bridge | Scene-based acceptance coordinator bridge | Out of scope |
| Participant management | System-first share management plus app disclosure/summary surface | System-first share management plus app disclosure/summary surface | Out of scope |

Navigation rules:

1. `Shared Goals` does not live in Settings for invitees.
2. `Shared Goals` coexists with owned goals inside the top-level `Goals` shell as a separate section.
3. If a user has both owned and shared goals, the shell shows both sections explicitly rather than mixing them into one undifferentiated list.
4. The owner creates and manages household access from `Settings -> Family Access`, not from per-goal menus.

Visual separation rules:

1. `Settings -> Family Access` uses a distinct management-row treatment and must not look like an ordinary static preference row.
2. `Shared Goals` uses a dedicated section/header treatment inside the `Goals` shell and must remain visually separable from owned goals in the first viewport.
3. Owned and shared sections cannot be interleaved row-by-row.

## Why This Is Higher Priority Than Local Bridge Sync
The product currently has a stronger user need for "my family can see progress safely" than for "I can manually bridge editable snapshots to Mac".

Priority rationale:

1. Family visibility is a core household use case directly tied to trust, accountability, and everyday value.
2. Read-only access is simpler for users to understand than signed-package bridge flows, trust records, import review, and manual apply.
3. The current bridge proposal already assumes this family-read requirement exists as a product truth, but it is not implemented.
4. A read-only family flow reduces pressure to expose unsafe ad hoc workarounds such as shared Apple IDs, screenshots, CSV exports, or manual status reporting.
5. The bridge is an operator workflow. Family sharing is an end-user workflow and therefore has higher product priority.

## Problem Statement
Today, the app supports CloudKit-backed authoritative storage and a separate `Local Bridge Sync` operator surface, but it does not give the user a first-class way to share goals with family members in read-only mode.

Current gaps:

1. No invite flow for family members.
2. No owner-managed permission model for goal visibility.
3. No read-only consumer UI that removes editing and planning controls.
4. No revocation and re-invite workflow for family access.
5. No product-safe alternative to manual exports for family visibility.

## Product Principles
1. The goal owner remains the only writer.
2. Family members receive visibility, not authority.
3. Shared viewing must feel native, not like an operator or export workflow.
4. Bridge workflows must not be used as a substitute for everyday family visibility.
5. Sensitive implementation details such as wallet addresses, raw transaction identifiers, and internal repair/migration state are not part of the family surface by default.

## Scope

### In Scope
1. Share the owner's full goal set with family members in read-only mode.
2. Owner-side invite, revoke, and access management.
3. Invitee-side read-only goal list and goal detail dashboard.
4. CloudKit-backed delivery for Apple-device consumers.
5. Read-only projections for progress, target, deadline, monthly status, and contribution summary signals that support household visibility.

### Out of Scope
1. Family-member editing of goals, plans, transactions, or allocations.
2. Shared execution tracking authority.
3. Shared monthly planning authoring.
4. Mac bridge editing as part of this flow.
5. Android implementation in the first shipping cut unless product scope explicitly expands later.

## Accepted Product Model

### Share Unit
The canonical share unit is the owner's full goal set.

Implications:

1. Granting access makes all current goals visible to that invitee.
2. Newly created goals become visible to existing invitees automatically unless access is revoked.
3. The product does not support goal-by-goal allowlists in the first shipping cut.
4. Revocation applies per invitee access grant, not per goal.

### Permission Model
The first shipping version supports one non-owner permission only:

1. `readOnly`

`readOnly` allows:

1. viewing goal name, emoji, status, target amount, deadline, aggregate progress, and forecast state,
2. viewing current-month status such as planned vs on-track/at-risk summary,
3. viewing contribution summaries and historical progress summaries that are safe for household visibility.

`readOnly` does not allow:

1. editing goal metadata,
2. editing assets or allocations,
3. editing transactions,
4. starting or finishing monthly execution,
5. changing planning settings,
6. importing bridge packages or using operator tools.

## Accepted Technical Direction
The product must not expose the live authoritative SwiftData graph directly to invitees.

Accepted direction:

1. Owner data remains authoritative in the owner's private CloudKit-backed runtime.
2. The app publishes a dedicated read-only shared projection dataset for the owner's goal set.
3. The shared projection dataset uses a dedicated share root, not the owner's live write-oriented record graph.
4. Invitees consume those projection records through a dedicated read-only surface.
5. Sharing is invite-based and revocable.
6. The shared projection path is one-way only: owner dataset -> shared projection dataset -> invitee read-only UI.

This proposal intentionally prefers a shared projection model over exposing the live write-oriented record graph. That keeps permissions, privacy, and UI gating simpler and safer.

## Share Acceptance and Storage Topology
CloudKit invitation handling and shared-data bootstrapping are part of the normative contract, not implementation detail left for later.

### Acceptance Entry Points
1. Cold-start invite acceptance is routed through a scene-based share-acceptance coordinator launched from the `UIWindowScene` lifecycle entry point.
2. Already-running invite acceptance routes through the same coordinator without requiring app restart.
3. Rejected invites, account-unavailable cases, and partially loaded shares terminate in explicit product states, not silent failure.

### Ingestion Path
1. Shared projection records are read from CloudKit shared-database records.
2. The app mirrors accepted shared projection data into a dedicated local read-only cache/store for rendering, offline tolerance, and state recovery.
3. The cache technology for v1 is a separate SwiftData container backed by isolated SQLite files.
4. Cache namespace is keyed by `ownerID/shareID`; each owner share dataset gets its own isolated store boundary.
5. Owner authoritative data and invitee shared cache never share the same write path.
6. Revocation and shared-record removal must remove or invalidate only the affected cache namespace without touching owner authoritative data or other owners' shared datasets.

### Runtime Ownership
1. Acceptance, refresh, and revoke processing belong to a dedicated family-sharing sync layer, not to owner planning or bridge services.
2. The invitee UI reads only from the shared read-only cache/view-model path.
3. Owner mutation flows never read from invitee cache state to determine authoritative updates.

### Namespace Executor Model
1. Each `ownerID/shareID` namespace is owned by a single serialized `FamilyShareNamespaceActor`.
2. `FamilyShareNamespaceActor` is the only runtime that may execute accept, refresh, revoke, cache bootstrap, cleanup, and namespace-local SwiftData writes for that namespace.
3. `FamilyShareProjectionPublishCoordinator` runs off-main and queues at most one active publish pipeline per namespace; overlapping publish triggers coalesce to the latest desired projection state.
4. CloudKit I/O, namespace migration, outbox draining, and SwiftData writes never run on the main actor.
5. A dedicated `@MainActor` shell adapter projects actor state into SwiftUI-observable UI state without owning storage mutations.
6. Cross-namespace work may run concurrently, but no single namespace may run two mutating pipelines simultaneously.

### App Shell Integration and Test Seams
The exact v1 SwiftUI app-shell integration is:

1. `CryptoSavingsTrackerApp` installs an iPhone/iPad-specific scene-based acceptance bridge for family-share acceptance.
2. `windowScene(_:userDidAcceptCloudKitShareWith:)` forwards accepted CloudKit shares into a single `FamilyShareAcceptanceCoordinator`.
3. Any app-level delegate glue exists only to support SwiftUI scene registration; the scene delegate acceptance path is authoritative for v1.
4. `CryptoSavingsTrackerApp` main `WindowGroup` observes that coordinator and refreshes `Shared Goals` state through the same path for both cold-start and already-running app acceptance.
5. The coordinator is injected into the SwiftUI shell rather than buried inside views.

Required injectable seams:

1. `FamilyShareAccepting`
2. `FamilyShareRefreshing`
3. `FamilyShareRevoking`
4. `FamilyShareCacheBootstrapping`
5. `FamilyShareStateProviding`

Tests must be able to simulate accept, revoke, stale, unavailable, and bootstrap-failure states without live CloudKit dependency.

### Namespace Migration and Rollback Contract
1. Every namespace store carries an explicit `cacheSchemaVersion`.
2. `FamilyShareCacheMigrationCoordinator` owns open, migrate, rebuild, quarantine, and version-compatibility decisions for each namespace.
3. Supported older namespace schemas migrate forward off-main and swap atomically into the active namespace path.
4. Incompatible newer schemas or corrupted namespace stores fail closed, are quarantined from active rendering, and surface explicit `temporarilyUnavailable` recovery state until rebuild succeeds.
5. Rebuild is the preferred strategy for incompatible namespace changes because the shared cache is non-authoritative and can be rehydrated from CloudKit shared data.
6. Downgraded app builds must not mutate newer namespace stores; they surface fail-closed recovery until a compatible rebuild path is available.

### Namespace Lifecycle and Resource Contract
1. Cold launch may open only a lightweight shared-namespace index; namespace stores themselves open lazily on invite acceptance, explicit shared-goal access, or owner-group expansion.
2. iPhone and iPad cold launch must not eager-open every namespace store when multiple shared owners exist.
3. At most two namespace stores may remain open concurrently on iPhone/iPad; additional namespaces reopen lazily and close through deterministic LRU/background eviction.
4. Revoked or removed namespaces purge on the next successful cleanup pass and no later than 24 hours after revocation/removal is confirmed.
5. Compaction, purge, and rebuild are background-only maintenance tasks and must never block first-viewport rendering.
6. Reopening the same namespace is idempotent and must not leak store/container instances.

### Failure Handling
The storage topology must explicitly surface:

1. `accountUnavailable`,
2. `inviteRejected`,
3. `shareLoadPartial`,
4. `sharedDatabaseUnavailable`,
5. `cacheBootstrapFailed`.

Each failure maps to a visible product state, retry policy, and telemetry event.

## Atomic Publish Boundary
Owner writes and shared projection refresh must have an explicit recoverable boundary.

### Publish Coordinator Contract
1. Owner authoritative mutations enqueue a `FamilyShareProjectionOutboxItem` atomically with the owner-side commit boundary.
2. `FamilyShareProjectionPublishCoordinator` drains outbox items serially per `ownerID/shareID`.
3. `projectionVersion` and `publishedAt` advance only after a full idempotent publish succeeds.
4. Invitees render only the last fully published `projectionVersion`.

### No Partial Exposure Rule
1. Child projection records for a new version are written under the next `projectionVersion`.
2. `FamilyShareProjectionRoot.activeProjectionVersion` flips only after the full child set for that version is durably published.
3. If publish fails midway, invitees continue reading the previous `activeProjectionVersion`.
4. Retry is idempotent and converges without duplicate projection records.

This is the normative mechanism that prevents partially advanced shared state after crash, network failure, or interrupted publish.

### CloudKit Sharing Mechanism
The accepted CloudKit mechanism for the first shipping cut is:

1. owner-private data remains in the owner's private authoritative dataset,
2. the app materializes a dedicated shared projection root for the owner's household-visible goal dataset,
3. the app attaches CloudKit sharing to that projection root rather than to the live owner graph,
4. invitees read shared projection data through the shared-database path,
5. CloudKit share participants for this feature are granted read-only permission only,
6. non-owner clients never receive write-authority flows for shared projection records.

This gives the product a native CloudKit-backed invite/revoke model without exposing the full owner graph to invitees.

## Executable Projection Schema Appendix
The projection contract must be concrete enough to build fixtures and integration tests without inventing new storage rules during implementation.

### Record Topology
1. `FamilyShareProjectionRoot`
2. `FamilySharedGoalProjection`

No owner-authoritative records are directly exposed as invitee-facing shared records.

### Stable Identity
1. `FamilyShareProjectionRoot.id` is stable per owner household share dataset.
2. `FamilySharedGoalProjection.id` is stable as `{rootID}:{goalID}`.
3. Stable IDs are reused across refreshes and idempotent overwrites.

### Version Fields
1. `schemaVersion` gates wire/schema compatibility.
2. `projectionVersion` advances monotonically on each successful republish of the shared dataset.
3. `publishedAt` records the authoritative publish timestamp for the shared dataset.
4. `activeProjectionVersion` on the root identifies the only invitee-visible version.

### Publish Triggers
Republish is required on:

1. goal create,
2. goal update,
3. goal archive/restore/close status change,
4. goal delete,
5. monthly status fields included in the projection changing,
6. contribution summary fields included in the projection changing,
7. owner display-name change relevant to shared identity copy,
8. share creation, revoke, or participant-state transitions that affect the visible dataset.

Republish is executed through the atomic publish coordinator, not by ad hoc direct writes from owner feature flows.

### Idempotent Overwrite Rules
1. Republishing overwrites root and child projection records by stable ID.
2. Missing child records in a newer publish are deleted from the projection dataset.
3. Republishing the same semantic dataset must not create duplicate shared goal records.

### Cleanup Rules
1. Owner goal deletion removes the matching `FamilySharedGoalProjection`.
2. Revoking one participant does not require per-participant duplicate projection datasets; one shared dataset may serve multiple read-only participants.
3. When the last participant is removed, the shared projection root and child records are deleted.
4. Cleanup failure must fail visible and retryable; it must not silently leave active-looking orphan shares.
5. Cache rebuild, cleanup, and migration operate independently per `ownerID/shareID` namespace.

## Shared Projection Contract
The shared projection dataset must be sufficient for household visibility and insufficient for accidental write workflows.

Dataset-level rules:

1. the projection represents the owner's full visible goal set, not a selectable subset,
2. the projection refresh contract covers both current goals and newly created goals,
3. invitees must not observe goal-level selection controls because selection is not part of the product model.

Minimum shared fields:

1. owner display name,
2. dataset share ID,
3. goal ID,
4. goal name and emoji,
5. goal currency,
6. target amount,
7. current aggregated amount,
8. progress percentage,
9. deadline,
10. goal status and forecast state,
11. current month summary,
12. last updated timestamp,
13. safe contribution summary fields needed for timeline visibility.

Excluded from shared projection by default:

1. wallet addresses,
2. raw blockchain transaction identifiers,
3. internal planning drafts,
4. migration/repair diagnostics,
5. operator-only bridge state,
6. settings and internal telemetry.

The owner-side scope preview must enumerate both visible and excluded field categories before the first invite is sent.

## Freshness and Lifecycle Matrix
Lifecycle and freshness rules are normative.

Freshness SLA:

1. `active` means the shared dataset completed successful reconciliation with CloudKit shared data within the past 24 hours.
2. `stale` means cached shared data exists, but no successful reconciliation has completed for more than 24 hours.
3. `temporarilyUnavailable` means the app cannot currently render a trusted shared dataset because shared-database access, account state, or cache bootstrap is failing.

| State | Trigger | User-facing copy contract | Timestamp treatment | Allowed actions | Analytics |
| --- | --- | --- | --- | --- | --- |
| `invitePendingAcceptance` | Invite exists but invitee has not accepted | `Invitation pending` plus owner identity | No `As of`; show invite sent/received context when available | Accept, dismiss | `family_share_invite_pending_viewed` |
| `emptySharedDataset` | Accepted share exists but there are currently no shared goals to render | `No shared goals right now` plus owner identity | Show last successful `As of` timestamp if one exists | Retry, dismiss | `family_share_empty_viewed` |
| `active` | Successful reconciliation within 24h and share active | `Read-only shared by {owner}` | Show `As of {publishedAt}` and optionally `Checked {lastReconciledAt}` | View only, pull to refresh/retry refresh | `family_share_active_viewed` |
| `stale` | Cached data exists but no successful reconciliation has completed for >24h | `This shared view may be out of date` | Show last successful `As of` timestamp prominently | View cached data, retry refresh | `family_share_stale_viewed` |
| `temporarilyUnavailable` | No trusted render path due to account/network/shared-db/bootstrap failure | `Shared goals temporarily unavailable` with reason-specific recovery copy | Show last successful timestamp only if one exists | Retry, close | `family_share_unavailable_viewed` |
| `revoked` | Owner explicitly revoked this participant | `Access revoked by {owner}` | No fresh timestamp; optionally show revoked time if known | Ask owner to re-share, dismiss | `family_share_revoked_viewed` |
| `removedOrNoLongerShared` | Shared dataset was deleted, unpublished, or is no longer available for this invitee | `Shared goals no longer available` | Show last successful timestamp only if it helps explain what changed | Dismiss | `family_share_removed_viewed` |

Reason-specific copy requirements:

1. `stale` must explain that the view is based on older shared data and may not reflect the latest owner changes.
2. `temporarilyUnavailable` must explain whether the reason is account state, network/shared-database access, or local cache/bootstrap failure when known.
3. `revoked` must explain that the owner removed access and that the next step is to ask the owner to share again if access is still needed.
4. `removedOrNoLongerShared` must explain that the shared dataset no longer exists or is no longer published for this invitee.

Accessibility requirements:

1. State must never be conveyed by color alone.
2. VoiceOver labels for shared rows and shared detail must include owner identity, read-only state, and freshness context.
3. Dynamic Type layouts must preserve first-viewport visibility for the dominant non-active state banner and ownership context.

Owner management states:

| State | Trigger | Copy contract | Primary action |
| --- | --- | --- | --- |
| `notShared` | No participants | `Invite family members to view all goals in read-only mode.` | `Share with Family` |
| `invitePending` | Invite created but not yet accepted | `Invitation pending` with invitee identity | `Manage Participants` |
| `sharedActive` | One or more active participants | `Shared with family in read-only mode` | `Manage Participants` |
| `revoked` | Participant was revoked | `Access removed` result state | `Done` |
| `shareFailed` | Create/invite/update failed | `Could not create household access` | `Retry` |

## Enforcement Contract
Read-only access must be enforced in both UI and mutation/service layers.

Required enforcement:

1. invitee surfaces use read-only scene/view models,
2. mutation entry points reject write attempts when the current context is a shared family dataset or any goal inside it,
3. deep links or stale routes into edit/planning/import flows fail closed for invitees,
4. background refresh for shared goals never upgrades invitee authority,
5. bridge/import/operator tools remain owner-only even if an invitee navigates into Settings.

Removing buttons is necessary but not sufficient. The runtime contract must reject non-owner writes.

## Derived Lifecycle Behavior Rules
The lifecycle matrix above is authoritative. The following derived behavior rules are also normative:

1. shared goal detail always shows `last updated` freshness context,
2. stale data is visible as stale, not silently treated as current,
3. revocation removes interactive access to the shared goal surface,
4. owner goal deletion removes that goal from the invitee-visible shared dataset rather than leaving orphaned readonly data,
5. completed or archived goals may remain visible in read-only mode if household sharing remains active, but they remain non-editable,
6. newly created goals appear in the invitee-visible shared dataset automatically after projection refresh,
7. accepted shares with zero visible goals render `emptySharedDataset` rather than a blank `Shared Goals` shell,
8. `revoked`, `removedOrNoLongerShared`, and `temporarilyUnavailable` render distinct copy and one clear primary next action rather than a single generic terminal card.

## Product Surfaces

### Owner Surface
The owner gets a dedicated `Share with Family` action from a global owner-managed surface such as Settings or a household-access destination, not from goal detail.

System-first management rule:

1. Use native CloudKit/system sharing UI on iPhone and iPad for invite creation and participant management in v1.
2. Use product-owned UI for pre-share disclosure, visibility review, participant-state summary, and revoke consequence copy.

Required owner actions:

1. start sharing the full goal set,
2. copy/send invite,
3. see who has access,
4. revoke access,
5. review what information is visible in read-only mode,
6. understand that all current and future goals become visible while access is active.

Mandatory pre-share scope preview:

1. The first invite cannot be sent until the owner views a scope-preview surface and explicitly acknowledges it.
2. The scope preview must enumerate:
   - all current goals are shared,
   - future goals auto-share while access remains active,
   - visible fields/categories,
   - excluded fields/categories,
   - revoke behavior and its effect.
3. The acknowledgment is product-owned even when invite creation later hands off to system sharing UI.

Pre-share preview layout contract:

1. The first-invite disclosure is a staged summary sheet, not a dense unstructured text sheet.
2. The first viewport shows a compact summary card covering the three core consent points:
   - all current goals are shared,
   - future goals auto-share while access remains active,
   - invitees receive read-only visibility only.
3. Detailed content is split into grouped expandable sections for visible data, excluded data, and revoke behavior.
4. The primary confirmation action stays sticky and persistently discoverable while the owner scrolls or expands details.
5. The sheet uses one glass chrome layer only; disclosure content itself renders on stable opaque or near-opaque surfaces.
6. The sheet must remain readable in large Dynamic Type, Increased Contrast, Reduce Motion, and Reduced Transparency modes without hiding the primary action.

First-use disclosure content is mandatory. Minimum semantic content:

1. `Invite specific Apple account users to view all of your goals in read-only mode.`
2. `They will not be able to edit goals, planning, transactions, or imports.`
3. `This is separate from Apple's Family Sharing purchase group.`

Owner management contract after sharing starts:

1. participant list with `pending`, `active`, `revoked`, and `failed` states,
2. visibility review for what household members can see,
3. explicit revoke action,
4. post-revoke result state,
5. retry path for failed share creation or failed participant updates.

### Invitee Surface
The invitee gets a dedicated read-only shared-goals experience.

Required invitee surfaces:

1. `Shared Goals` entry point,
2. list of goals shared with the invitee,
3. read-only goal dashboard/detail,
4. visible "Shared by {owner}" identity,
5. explicit absence of edit controls.

Multi-owner grouping rules:

1. `Shared Goals` is grouped by owner.
2. Each owner group uses a visible section header `Shared by {owner}` even if there is only one owner.
3. Each shared row includes a persistent ownership marker so ownership is still obvious when section headers scroll offscreen.
4. Owned-goal rows and shared-goal rows must remain distinguishable without opening a row.
5. Owner groups are sorted by owner display name using locale-aware ascending order.
6. If owner display names collide or are unavailable, stable secondary ordering falls back to `ownerID`, then `shareID`, so the same datasets render in the same order across launches and refreshes.
7. Owner section headers remain sticky while scrolling where platform list behavior supports it.
8. Every shared row carries an inline owner chip even when section headers are offscreen.
9. Shared rows use a dedicated chrome token that cannot be mistaken for an owned goal row.

### Shared Detail Visual Contract
The shared-detail surface is a dedicated read-only screen, not the owner goal detail with controls removed.

Required anatomy:

1. top identity row: `Shared by {owner}`,
2. persistent read-only badge,
3. dominant state banner/card when the state is not `active`,
4. `As of` / `Last updated` placement above or immediately under the primary summary,
5. progress, target, deadline, and current-month summary cards,
6. no trailing action menu and no floating owner CTA region,
7. footer or inline explanation that this surface is read-only.

State cards:

1. `active`: standard shared summary with owner identity and freshness,
2. `stale`: visible warning card that cached data may be out of date,
3. `temporarilyUnavailable`: full-width recovery card with retry action,
4. `revoked`: access-removed card with owner identity and one clear next step to ask the owner to re-share,
5. `removedOrNoLongerShared`: dataset-removed card with no financial interaction controls and a dismiss action.

Strict visual priority order:

1. owner identity row,
2. read-only badge,
3. dominant non-active state banner when applicable,
4. freshness line,
5. financial summary cards.

Non-active state rule:

1. `stale`, `temporarilyUnavailable`, `revoked`, and `removedOrNoLongerShared` must dominate the first viewport on iPhone and iPad.
2. Non-active states override the normal active composition; they do not appear as secondary chips beside active financial content.

Material and contrast rules:

1. Glass is reserved for navigation chrome, section framing, and non-data decorative headers only.
2. Shared section headers, numeric metric cards, freshness banners, state banners, and recovery cards use explicit semantic surface tokens with opaque or near-opaque materials.
3. Reduced Transparency mode uses solid-surface fallbacks for all shared financial cards and banners.
4. Critical state labels, timestamps, and key financial metrics must not rely on translucency for legibility.

### UI Contract
All editing entry points must be removed or disabled for invitees.

Examples:

1. no `Edit Goal`,
2. no `Add Asset`,
3. no `Add Transaction`,
4. no monthly planning authoring,
5. no bridge/import/apply controls.

Invitee copy must also communicate that the surface is shared and read-only, not merely missing buttons by accident.

## Sequencing and Priority Contract

### Priority Rule
Read-only family sharing is P0 relative to `Local Bridge Sync`.

### Rollout Rule
The next major sync-related user-facing milestone must be read-only family sharing, not new bridge expansion.

### Blocking Rule
`Local Bridge Sync` may remain in maintenance mode, but new rollout phases, scope expansion, or polish work must not be treated as a higher-priority delivery stream until this proposal ships.

This means:

1. read-only family sharing must be implemented before any new Phase 2A bridge expansion, any Phase 2B transport hardening work, or any bridge UX polish positioned as a user-facing priority,
2. read-only family sharing must be implemented before bridge is positioned as the primary answer to spouse/family visibility,
3. release planning must treat family sharing as the user-facing priority path,
4. bridge work remains an operator capability, not the substitute for household read access.

## Relationship to Local Bridge Sync
This feature does not replace `Local Bridge Sync`.

Instead, the responsibilities become cleanly separated:

1. `Read-Only Family Sharing` is the consumer-facing household visibility feature.
2. `Local Bridge Sync` is the operator-facing manual editing/import workflow for Mac.

The product must not route ordinary family visibility needs into bridge flows.

## User Flows

### Flow 1: Owner Enables Family Read-Only Access
1. Owner opens the global sharing surface.
2. Owner taps `Share with Family`.
3. Owner sees the mandatory scope preview and acknowledges it.
4. Owner proceeds into system-first invite creation/participant UI.
5. Owner selects the invite target.
6. App creates or updates the shared read-only projection dataset for the owner's full goal set.
7. Invite is sent.

### Flow 2: Family Member Accepts Invite
1. Invitee opens the invite on an Apple device.
2. Invitee accepts access.
3. Shared goals from the owner appear under `Shared Goals`.
4. Each shared goal clearly shows `Shared by {owner}` and read-only status.
5. Invitee opens a goal and sees read-only status only.

### Flow 3: Owner Revokes Access
1. Owner opens sharing management for household access.
2. Owner selects a family member.
3. Owner confirms revocation.
4. Invitee loses access to the shared goal surface for the owner's full goal set.

## Acceptance Criteria
1. The owner can grant a family member read-only access to the owner's full current goal set without giving edit rights.
2. Newly created goals become visible to already-authorized invitees without requiring per-goal re-sharing.
3. The invitee can see the shared goals on Apple devices in a dedicated read-only surface.
4. The invitee cannot access editing, planning, execution, import, or bridge actions for shared goals.
5. Shared data is limited to the accepted read-only projection contract.
6. CloudKit participant permission for invitees is read-only.
7. Revocation removes access without affecting the owner's authoritative dataset.
8. Read-only enforcement exists at both UI and mutation/service layers.
9. Shared-goal lifecycle states surface explicit pending, empty, active, stale, revoked, removed, and unavailable outcomes with reason-specific next action.
10. The first invite cannot be sent until the owner acknowledges the mandatory scope preview, and that preview keeps the primary CTA persistently discoverable while exposing current scope, future-goal auto-sharing, exclusions, and revoke behavior.
11. Shared goals from multiple owners are grouped and labeled so ownership is never ambiguous, including after scrolling away from the section header.
12. Non-active shared-detail states dominate the first viewport on iPhone and iPad, and all critical financial content sits on opaque or near-opaque surfaces rather than blur-dependent materials.
13. Atomic publish prevents invitees from observing partially advanced shared state.
14. Shared cache namespaces are isolated per `ownerID/shareID`, versioned, and migrate, rebuild, or fail closed deterministically across upgrade, rollback, and corruption cases.
15. Cold-start and warm-start share acceptance both route through the same injectable app-shell coordinator path.
16. Namespace execution uses a single serialized executor/actor boundary per `ownerID/shareID`, and overlapping accept/refresh/revoke/publish flows are deterministic and off-main for storage/network work.
17. Shared-goals cold launch does not eager-open every namespace store, and revoked/removed namespaces purge within the defined lifecycle window.
18. The proposal is treated as higher-priority than `Local Bridge Sync` in delivery sequencing and release planning.
19. No user-facing documentation or settings copy positions `Local Bridge Sync` as the answer for ordinary spouse/family goal visibility.

## Delivery Phases

### Phase A: Share Projection Foundation
1. Freeze bridge expansion above maintenance while this proposal is in flight.
2. Define projection schema for shared full-goal-set visibility.
3. Define owner/invitee permission model.
4. Define projection publishing and refresh contract.
5. Define CloudKit share-root contract for projection records.
6. Implement share-acceptance coordinator and shared-cache bootstrap path.
7. Define namespace actor/executor ownership and main-actor adapter boundaries.
8. Define namespace migration, rebuild, rollback, purge, and lazy-open rules.

### Phase B: Owner Sharing Surface
1. Add owner-side `Share with Family`.
2. Add invite management and revoke flow.
3. Add visibility review copy for what is shared.
4. Add owner-side state handling for pending, active, revoked, and failed sharing.
5. Implement staged pre-share scope preview with sticky primary CTA and accessibility-safe layout behavior.

### Phase C: Invitee Read-Only Experience
1. Add `Shared Goals` entry point.
2. Add read-only list and goal detail dashboard.
3. Remove all editing affordances from invitee surfaces.
4. Add freshness, empty, revoked, removed, and unavailable states for invitees.
5. Add sticky owner headers, inline owner chips, and shared-row chrome treatment.
6. Enforce opaque or near-opaque shared financial surfaces with reduced-transparency fallbacks.

### Phase D: Release Gate
1. Validate owner-only write authority.
2. Validate invite acceptance and revocation.
3. Validate absence of editing and bridge controls in shared view.
4. Validate service-layer rejection for non-owner write attempts.
5. Validate projection privacy envelope and excluded fields.
6. Validate namespace migration, downgrade fail-closed, corruption rebuild, and per-namespace race handling.
7. Validate Dynamic Type, Reduce Motion, Increased Contrast, and Reduced Transparency behavior for owner disclosure and invitee shared-detail surfaces.
8. Mark this proposal complete before the next `Local Bridge Sync` expansion milestone.

## Test and Release Gates
1. Owner can create a household share and expose all current goals through the shared projection dataset.
2. Owner cannot send the first invite without acknowledging the mandatory scope preview.
3. Newly created goals appear for an already-authorized invitee after projection refresh, without manual re-sharing.
4. Invitee can accept a share and see the goals in `Shared Goals`.
5. Cold-start and warm-start acceptance use the same scene-based coordinator path and are both test-covered.
6. Invitee sees owner-grouped shared-goals sections and persistent row-level ownership markers when multiple owners are present.
7. Invitee cannot mutate data through hidden routes, deep links, or reused edit screens.
8. Revocation removes access without deleting owner data.
9. Projection refresh updates invitee-visible progress and freshness timestamp.
10. The first-invite disclosure fits an iPhone first viewport as a staged summary sheet, keeps the primary CTA discoverable, and passes Dynamic Type, Reduce Motion, Increased Contrast, and Reduced Transparency checks.
11. `emptySharedDataset`, `revoked`, `removedOrNoLongerShared`, and `temporarilyUnavailable` render distinct copy and next-step actions instead of a blank or generic terminal shell.
12. Stale, unavailable, revoked, and removed shared-detail states dominate the first viewport and remain visually distinct from active state.
13. Shared metric cards, freshness banners, and recovery states remain legible in light, dark, increased-contrast, and reduced-transparency modes without critical data on blurred surfaces.
14. Sticky owner headers, inline owner chips, and shared-row chrome preserve owner identity from any scroll position.
15. A failed publish never exposes partially advanced shared state.
16. Namespace migration tests cover forward migration, downgrade fail-closed behavior, and corrupted-store rebuild.
17. Namespace race tests prove deterministic accept/refresh/revoke/publish outcomes with no duplicate projection versions and no main-thread storage writes.
18. Cache teardown for one `ownerID/shareID` namespace does not affect other owners' shared datasets.
19. Cold launch does not eager-open every namespace store when multiple owners exist, and revoked namespaces purge within the declared lifecycle window.
20. Bridge release planning artifacts continue to show this feature as higher priority until completion.

## Rollout and Operability
This feature is a sequencing gate and must ship with the same operational rigor as other CloudKit surface changes.

### Feature Flag and Kill Switch
1. `family_readonly_sharing_enabled` gates owner creation, invite acceptance routing, and invitee `Shared Goals` surface exposure.
2. Kill switch behavior disables new invite creation and new invite acceptance UI first.
3. Existing accepted shares must fail into explicit `temporarilyUnavailable` or cached `stale` states rather than silently disappearing without explanation.

Kill-switch thresholds are normative initial rollout thresholds for v1. They are not placeholders and remain in force until replaced by an explicit runbook/proposal update after beta or production evidence review:

1. rolling 6h `family_share_create_failed` rate > 5.0% with at least 100 create attempts,
2. rolling 6h `family_share_accept_failed` rate > 5.0% with at least 100 accept attempts,
3. rolling 24h `family_share_unavailable_viewed` rate > 10.0% with at least 500 shared-goal opens,
4. rolling 24h cache-bootstrap failure rate > 2.0% with at least 100 bootstrap attempts.

### Telemetry
Minimum events:

1. `family_share_create_started`
2. `family_share_create_succeeded`
3. `family_share_create_failed`
4. `family_share_accept_succeeded`
5. `family_share_accept_failed`
6. `family_share_revoked`
7. `family_share_refresh_stale`
8. `family_share_temporarily_unavailable`
9. `family_share_empty_viewed`
10. `family_share_removed_viewed`
11. `family_share_namespace_migration_failed`
12. `family_share_namespace_rebuild_started`
13. `family_share_namespace_rebuild_succeeded`

### Logging and Redaction
1. No goal names, money amounts, or participant emails are written to structured logs.
2. Goal, participant, and share identifiers are logged only in redacted or hashed form.
3. Support diagnostics must separate owner/share identifiers from financial payload fields.

### Support Runbook Expectations
Pre-release operations documentation must cover:

1. stuck invite acceptance,
2. revoked share still visible locally,
3. projection cleanup failure,
4. shared-database unavailable incidents,
5. namespace migration or downgrade fail-closed incidents,
6. namespace rebuild and corruption recovery,
7. kill-switch activation and rollback expectations.

## Open Questions Resolved
1. macOS invitee surface:
   - out of scope for v1.
2. Participant management approach:
   - system-first for invite creation/participant management, custom UI for disclosure and app-specific states.
3. Freshness SLA:
   - `stale` begins after 24 hours without successful reconciliation; `temporarilyUnavailable` is used when no trusted render path exists now.
4. Multi-owner grouping:
   - `Shared Goals` is grouped by owner, with persistent row-level ownership markers, locale-aware owner-name sorting, and stable secondary fallback ordering by `ownerID`, then `shareID`.
5. Cache technology and namespace:
   - separate SwiftData-backed cache store per `ownerID/shareID`.
6. Kill-switch thresholds:
   - use the normative initial rollout thresholds defined in `Rollout and Operability`; they are not placeholders and can change only through an explicit release-governance update after real rollout evidence review.
7. Share acceptance lifecycle hook:
   - v1 uses the scene-based acceptance path `windowScene(_:userDidAcceptCloudKitShareWith:)` feeding a single `FamilyShareAcceptanceCoordinator`.
8. First-release multi-owner shortcutting:
   - v1 keeps deterministic canonical owner grouping; no recency/pinned owner shortcut is required before first release if sticky owner cues are present.
9. Namespace concurrency:
   - one serialized `FamilyShareNamespaceActor` owns accept, refresh, revoke, bootstrap, cleanup, and namespace-local writes per `ownerID/shareID`.
10. Namespace migration and rollback:
   - migration is versioned, rebuild-first where needed, and downgrade fail-closed.
11. Namespace resource lifecycle:
   - namespace stores are lazy-opened, bounded in concurrent open count, background-compacted, and purged after revoke/remove within the declared lifecycle window.

## Non-Goals
1. Giving family members collaborative editing.
2. Sharing the bridge workspace.
3. Exposing raw financial internals not needed for household visibility.
4. Replacing CloudKit-backed authoritative storage.
5. Reordering priorities so bridge ships ahead of this feature.

## Summary
The product needs a native family-friendly visibility layer before it invests further in operator bridge workflows.

The strict sequencing from this proposal is:

1. CloudKit remains the durable source of truth.
2. Read-only family sharing ships as the next higher-priority sync-visible capability.
3. `Local Bridge Sync` continues only after this user-facing household access gap is closed.
