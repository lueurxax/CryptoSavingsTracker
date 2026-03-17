# CloudKit Read-Only Family Sharing Proposal

## Status
Decision-locked draft (P0 priority; must ship before further Local Bridge Sync rollout)

## Decision Lock
The product direction in this document is decision-locked for sequencing:

1. Read-only family access to goals is a higher-priority user outcome than `Local Bridge Sync`.
2. New delivery work for `Local Bridge Sync` must not outrank or bypass this feature.
3. `Local Bridge Sync` remains valid as a separate capability, but its forward rollout is gated on this read-only sharing flow shipping first.

## Review-Driven Locked Decisions
This proposal incorporates review feedback from `CLOUDKIT_READONLY_FAMILY_SHARING_PROPOSAL_TRIAD_REVIEW_R1.md`, adjusted for the later decision to remove goal-by-goal sharing.

Locked decisions:

1. v1 share scope is the owner's full goal set, not selected goals.
2. v1 invitee surfaces are in scope on iPhone and iPad only.
3. macOS is explicitly out of scope for v1 invitee consumption despite the existing macOS app shell.
4. Owner management is system-first where possible for invite creation and participant management, with custom product UI for pre-share disclosure and app-specific state presentation.
5. Invitee consumption uses a dedicated shared-goals surface, not the owner goal detail with actions removed.
6. Shared data is ingested from CloudKit shared-database records into a dedicated local read-only cache path, not into the owner's authoritative store.
7. Freshness state is normative: `stale` begins after 24 hours without a successful shared-dataset reconciliation.

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
| Share acceptance routing | App-level acceptance coordinator | App-level acceptance coordinator | Out of scope |
| Participant management | System-first share management plus app disclosure/summary surface | System-first share management plus app disclosure/summary surface | Out of scope |

Navigation rules:

1. `Shared Goals` does not live in Settings for invitees.
2. `Shared Goals` coexists with owned goals inside the top-level `Goals` shell as a separate section.
3. If a user has both owned and shared goals, the shell shows both sections explicitly rather than mixing them into one undifferentiated list.
4. The owner creates and manages household access from `Settings -> Family Access`, not from per-goal menus.

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
1. Cold-start invite acceptance is routed through an app-level share-acceptance coordinator launched from the scene/application lifecycle entry point.
2. Already-running invite acceptance routes through the same coordinator without requiring app restart.
3. Rejected invites, account-unavailable cases, and partially loaded shares terminate in explicit product states, not silent failure.

### Ingestion Path
1. Shared projection records are read from CloudKit shared-database records.
2. The app mirrors accepted shared projection data into a dedicated local read-only cache/store for rendering, offline tolerance, and state recovery.
3. Owner authoritative data and invitee shared cache never share the same write path.
4. Revocation and shared-record removal must remove or invalidate the local shared cache without touching owner authoritative data.

### Runtime Ownership
1. Acceptance, refresh, and revoke processing belong to a dedicated family-sharing sync layer, not to owner planning or bridge services.
2. The invitee UI reads only from the shared read-only cache/view-model path.
3. Owner mutation flows never read from invitee cache state to determine authoritative updates.

### Failure Handling
The storage topology must explicitly surface:

1. `accountUnavailable`,
2. `inviteRejected`,
3. `shareLoadPartial`,
4. `sharedDatabaseUnavailable`,
5. `cacheBootstrapFailed`.

Each failure maps to a visible product state, retry policy, and telemetry event.

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

### Idempotent Overwrite Rules
1. Republishing overwrites root and child projection records by stable ID.
2. Missing child records in a newer publish are deleted from the projection dataset.
3. Republishing the same semantic dataset must not create duplicate shared goal records.

### Cleanup Rules
1. Owner goal deletion removes the matching `FamilySharedGoalProjection`.
2. Revoking one participant does not require per-participant duplicate projection datasets; one shared dataset may serve multiple read-only participants.
3. When the last participant is removed, the shared projection root and child records are deleted.
4. Cleanup failure must fail visible and retryable; it must not silently leave active-looking orphan shares.

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

## Freshness and Lifecycle Matrix
Lifecycle and freshness rules are normative.

Freshness SLA:

1. `active` means the shared dataset completed successful reconciliation with CloudKit shared data within the past 24 hours.
2. `stale` means cached shared data exists, but no successful reconciliation has completed for more than 24 hours.
3. `temporarilyUnavailable` means the app cannot currently render a trusted shared dataset because shared-database access, account state, or cache bootstrap is failing.

| State | Trigger | User-facing copy contract | Timestamp treatment | Allowed actions | Analytics |
| --- | --- | --- | --- | --- | --- |
| `invitePendingAcceptance` | Invite exists but invitee has not accepted | `Invitation pending` plus owner identity | No `As of`; show invite sent/received context when available | Accept, dismiss | `family_share_invite_pending_viewed` |
| `active` | Successful reconciliation within 24h and share active | `Read-only shared by {owner}` | Show `As of {publishedAt}` and optionally `Checked {lastReconciledAt}` | View only, pull to refresh/retry refresh | `family_share_active_viewed` |
| `stale` | Cached data exists but no successful reconciliation for >24h | `This shared view may be out of date` | Show last successful `As of` timestamp prominently | View cached data, retry refresh | `family_share_stale_viewed` |
| `temporarilyUnavailable` | No trusted render path due to account/network/shared-db/bootstrap failure | `Shared goals temporarily unavailable` with reason-specific recovery copy | Show last successful timestamp only if one exists | Retry, close | `family_share_unavailable_viewed` |
| `revokedOrRemoved` | Share revoked, owner removed share, or records removed and confirmed | `Access removed` | No fresh timestamp; optionally show removed time if known | Dismiss/remove from local list | `family_share_revoked_viewed` |

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

## Lifecycle, Freshness, and Revocation Contract
The shared-goal experience must expose explicit lifecycle states rather than silently failing.

Minimum owner-side states:

1. `notShared`,
2. `invitePending`,
3. `sharedActive`,
4. `revoked`,
5. `shareFailed`.

Minimum invitee-side states:

1. `invitePendingAcceptance`,
2. `active`,
3. `stale`,
4. `revokedOrRemoved`,
5. `temporarilyUnavailable`.

Required behavior:

1. shared goal detail always shows `last updated` freshness context,
2. stale data is visible as stale, not silently treated as current,
3. revocation removes interactive access to the shared goal surface,
4. owner goal deletion removes that goal from the invitee-visible shared dataset rather than leaving orphaned readonly data,
5. completed or archived goals may remain visible in read-only mode if household sharing remains active, but they remain non-editable.
6. newly created goals appear in the invitee-visible shared dataset automatically after projection refresh.

## Product Surfaces

### Owner Surface
The owner gets a dedicated `Share with Family` action from a global owner-managed surface such as Settings or a household-access destination, not from goal detail.

System-first management rule:

1. Use native system share-management UI for invite creation and participant management where possible.
2. Use product-owned UI for pre-share disclosure, visibility review, participant-state summary, and revoke consequence copy.

Required owner actions:

1. start sharing the full goal set,
2. copy/send invite,
3. see who has access,
4. revoke access,
5. review what information is visible in read-only mode,
6. understand that all current and future goals become visible while access is active.

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

### Shared Detail Visual Contract
The shared-detail surface is a dedicated read-only screen, not the owner goal detail with controls removed.

Required anatomy:

1. top identity row: `Shared by {owner}`,
2. persistent read-only badge,
3. `As of` / `Last updated` placement above or immediately under the primary summary,
4. progress, target, deadline, and current-month summary cards,
5. no trailing action menu and no floating owner CTA region,
6. footer or inline explanation that this surface is read-only.

State cards:

1. `active`: standard shared summary with owner identity and freshness,
2. `stale`: visible warning card that cached data may be out of date,
3. `temporarilyUnavailable`: full-width recovery card with retry action,
4. `revokedOrRemoved`: removed-access card with no financial interaction controls.

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
3. Owner sees a clear explanation of read-only access.
4. Owner selects the invite target.
5. App creates or updates the shared read-only projection dataset for the owner's full goal set.
6. Invite is sent.

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
9. Shared-goal lifecycle states surface explicit pending, active, stale, and revoked/unavailable outcomes.
10. The proposal is treated as higher-priority than `Local Bridge Sync` in delivery sequencing and release planning.
11. No user-facing documentation or settings copy positions `Local Bridge Sync` as the answer for ordinary spouse/family goal visibility.

## Delivery Phases

### Phase A: Share Projection Foundation
1. Freeze bridge expansion above maintenance while this proposal is in flight.
2. Define projection schema for shared full-goal-set visibility.
3. Define owner/invitee permission model.
4. Define projection publishing and refresh contract.
5. Define CloudKit share-root contract for projection records.
6. Implement share-acceptance coordinator and shared-cache bootstrap path.

### Phase B: Owner Sharing Surface
1. Add owner-side `Share with Family`.
2. Add invite management and revoke flow.
3. Add visibility review copy for what is shared.
4. Add owner-side state handling for pending, active, revoked, and failed sharing.

### Phase C: Invitee Read-Only Experience
1. Add `Shared Goals` entry point.
2. Add read-only list and goal detail dashboard.
3. Remove all editing affordances from invitee surfaces.
4. Add freshness and revoked/unavailable states for invitees.

### Phase D: Release Gate
1. Validate owner-only write authority.
2. Validate invite acceptance and revocation.
3. Validate absence of editing and bridge controls in shared view.
4. Validate service-layer rejection for non-owner write attempts.
5. Validate projection privacy envelope and excluded fields.
6. Mark this proposal complete before the next `Local Bridge Sync` expansion milestone.

## Test and Release Gates
1. Owner can create a household share and expose all current goals through the shared projection dataset.
2. Newly created goals appear for an already-authorized invitee after projection refresh, without manual re-sharing.
3. Invitee can accept a share and see the goals in `Shared Goals`.
4. Invitee cannot mutate data through hidden routes, deep links, or reused edit screens.
5. Revocation removes access without deleting owner data.
6. Projection refresh updates invitee-visible progress and freshness timestamp.
7. Stale or unavailable sync states are visible and non-destructive.
8. Bridge release planning artifacts continue to show this feature as higher priority until completion.

## Rollout and Operability
This feature is a sequencing gate and must ship with the same operational rigor as other CloudKit surface changes.

### Feature Flag and Kill Switch
1. `family_readonly_sharing_enabled` gates owner creation, invite acceptance routing, and invitee `Shared Goals` surface exposure.
2. Kill switch behavior disables new invite creation and new invite acceptance UI first.
3. Existing accepted shares must fail into explicit `temporarilyUnavailable` or cached `stale` states rather than silently disappearing without explanation.

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
5. kill-switch activation and rollback expectations.

## Open Questions Resolved
1. macOS invitee surface:
   - out of scope for v1.
2. Participant management approach:
   - system-first for invite creation/participant management, custom UI for disclosure and app-specific states.
3. Freshness SLA:
   - `stale` begins after 24 hours without successful reconciliation; `temporarilyUnavailable` is used when no trusted render path exists now.

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
