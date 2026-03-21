# Shared Goals Freshness Sync Proposal

> Incident mapping: owner updates goals/assets on one device, but invitee-side shared goals on another device stay stale

| Metadata | Value |
|---|---|
| Status | Draft |
| Priority | P0 Trust and Correctness |
| Last Updated | 2026-03-21 |
| Platform | iOS |
| Scope | Read-only family sharing freshness, owner-side projection republish, invitee-side refresh contract |
| Affected Runtime | `FamilyShareServices`, `FamilyShareCloudKitStore`, family-sharing mutation hooks, invitee refresh behavior |

---

## 0) Incident Summary

The current family-sharing implementation behaves like a manually published snapshot, not like an always-fresh shared goal set.

Observed user failure:

1. the owner updates goals or assets on device A,
2. the invitee opens the app on device B,
3. `Shared with You` still shows old values or old goal structure.

This is a trust problem, not a minor sync lag. Read-only sharing is only useful if the invitee can rely on the numbers as current enough to make the screen feel truthful.

## 0.1 Current Implementation Gap

Current behavior is structurally incomplete:

1. shared projection publish is triggered when the owner explicitly starts sharing, not when shared data changes,
2. invitee refresh pulls the current shared projection snapshot, but does not cause owner data to be republished,
3. there is no automatic freshness contract that defines when invitee data should update after owner changes,
4. there is no user-facing distinction between:
   - "owner has not republished yet",
   - "invitee has not refreshed yet",
   - "shared dataset is temporarily unavailable".

Result: both devices can be healthy individually while the shared surface is stale.

## 1) Problem

`Shared with You` currently violates the most important expectation of a read-only financial sharing feature:

1. owner changes should propagate without requiring the owner to manually restart sharing,
2. invitee refresh should mean "get the latest published truth", not "show me the same stale snapshot again",
3. the system should have an explicit freshness SLA and state model,
4. telemetry and support should be able to distinguish publish failure from fetch failure.

Without this, the feature looks unreliable even when CloudKit itself is working.

## 2) Goal

Deliver a proper freshness model for shared goals so that owner-side mutations are republished automatically and invitee-side shared goals refresh predictably, with a clear runtime contract and user-visible recovery states.

## 3) Non-Goals

This proposal does not include:

1. a redesign of participant management,
2. a redesign of the invitee list IA or card layout,
3. Android implementation in the same pass,
4. a full CloudKit push-first architecture for background live sync in v1,
5. changing the read-only permission model.

## 4) Decision-Locked Fix Direction

The following decisions are locked:

1. owner-side shared projection must republish automatically after authoritative mutations that affect shared-goal semantics,
2. invitee-side freshness must not depend on the owner re-opening `Family Access` or manually tapping `Share with Family`,
3. shared projection publishing must be debounced/coalesced; one editing burst must not create one CloudKit publish per field change,
4. invitee refresh remains a pull model in v1, but it becomes automatic on key lifecycle boundaries,
5. manual refresh remains available as an explicit recovery affordance,
6. freshness states must distinguish:
   - `active`,
   - `stale`,
   - `temporarilyUnavailable`,
   - `removedOrNoLongerShared`,
7. telemetry must separate:
   - owner publish requested/succeeded/failed,
   - invitee refresh requested/succeeded/failed,
   - stale view exposure,
   - excessive publish churn,
8. shared-goal freshness is a product contract with an SLA, not a best-effort side effect.

## 5) Product Contract

## 5.1 User-Facing Freshness Contract

When an owner changes shared-goal data on one device:

1. the system should automatically republish the shared projection,
2. the invitee should see the updated shared goals by the next natural refresh boundary,
3. if refresh cannot complete, the invitee must see an explicit unhealthy state instead of silently stale data.

Initial SLA target for v1:

1. owner mutation to successful projection republish: usually under 30 seconds on healthy connectivity,
2. invitee app entering foreground with an existing shared dataset: silent refresh attempt within 5 seconds,
3. invitee opening `Shared with You` after a successful owner republish: updated data visible within 60 seconds under healthy connectivity.

This is not a real-time streaming guarantee. It is a clear, trustworthy pull-based freshness contract.

## 5.2 What Counts as Shared Data

Automatic republish must be triggered only by mutations that change invitee-visible semantics, including:

1. goal created,
2. goal deleted,
3. goal renamed,
4. goal emoji changed,
5. target amount changed,
6. currency changed,
7. deadline changed,
8. goal completion/archival state changed if it affects shared lifecycle,
9. asset or transaction mutations that change the goal's current total,
10. data repair, import, merge, dedup, or migration flows that change the invitee-visible goal snapshot.

Non-shared local-only settings must not trigger shared projection republish.

## 6) Proposed Runtime Model

## 6.1 Owner-Side Automatic Projection Republish

Introduce a dedicated owner-side freshness pipeline:

1. authoritative mutation completes in the owner datastore,
2. mutation emits a `sharedProjectionDirty` event with affected goal IDs and reason,
3. a debounced republish coordinator coalesces bursts,
4. coordinator rebuilds one canonical shared projection from current owner truth,
5. coordinator publishes the new projection to CloudKit,
6. publication updates local owner shared-state metadata and telemetry.

This coordinator must be the only path that publishes automatic owner updates after sharing is already active.

## 6.2 Debounce and Coalescing Contract

Automatic republish must be rate-limited:

1. editing bursts across a short window are collapsed into one publish,
2. repeated mutations while one publish is in flight must enqueue at most one trailing publish,
3. the last mutation wins; invitee should get the newest canonical state, not a queue of intermediate states,
4. failure should not permanently stop future publishes.

Initial v1 defaults:

1. debounce window: 2 seconds,
2. maximum in-flight publish concurrency: 1 per namespace,
3. trailing publish after in-flight completion if additional dirty events arrived,
4. exponential backoff for repeated publish failures, capped to a short recovery window.

## 6.3 Invitee Refresh Contract

Invitee-side refresh in v1 is automatic pull on important lifecycle boundaries:

1. after invitation acceptance,
2. when the app enters foreground,
3. when `Shared with You` becomes visible for the first time in a foreground session,
4. when the user explicitly taps refresh or retry.

Additional rules:

1. foreground refresh should be skipped if the namespace was refreshed very recently,
2. list rendering should not block on network if a cached projection exists,
3. stale cached data may render briefly, but only if accompanied by the correct freshness semantics,
4. silent refresh must update the section when newer projection data is fetched.

## 6.4 Freshness State Semantics

The invitee surface must use these meanings:

1. `active`
   - last successful refresh is within freshness SLA or no stale signal exists.
2. `stale`
   - cached shared data exists, but the app could not confirm freshness within the SLA window.
3. `temporarilyUnavailable`
   - refresh failed and safe rendering requires suppressing the normal active dataset.
4. `removedOrNoLongerShared`
   - the share or dataset is no longer available to the invitee.

`stale` is allowed to render the last known shared dataset.
`temporarilyUnavailable` may suppress the normal dataset if safety requires it.

## 7) Architecture Changes

## 7.1 New Components

Introduce the following concepts:

1. `FamilyShareProjectionDirtyReason`
2. `FamilyShareProjectionAutoRepublishCoordinator`
3. `FamilyShareProjectionMutationObserver`
4. `FamilyShareFreshnessPolicy`
5. `FamilyShareInviteeRefreshScheduler`
6. `FamilyShareRefreshResult`

## 7.2 Mutation Hook Boundary

Shared projection auto-republish must hook into the authoritative mutation layer, not into SwiftUI views.

The hook boundary must cover:

1. goal create/edit/delete flows,
2. asset add/edit/delete flows,
3. transaction add/import/delete flows,
4. import/bridge/dedup/backfill flows that touch invitee-visible shared values.

View-level button taps are not sufficient because background or non-UI mutations would bypass them.

## 7.3 Canonical Projection Rebuild

Automatic republish must rebuild the entire canonical shared projection from current owner truth, not patch records field-by-field from the mutation source.

Reasons:

1. avoids drift between owner truth and shared projection,
2. keeps shared-goals redesign semantics intact,
3. makes publish idempotent,
4. simplifies recovery after partial failures.

## 7.4 Invitee Refresh Scheduler

Invitee refresh must be scheduled by one policy component, not by scattered view hooks.

The scheduler owns:

1. foreground-triggered refresh,
2. first-visibility refresh,
3. cooldown suppression,
4. stale threshold evaluation,
5. telemetry for refresh outcomes and stale exposure.

## 8) UX Contract

## 8.1 Owner UX

The owner should not need to manually re-share after normal edits.

Owner-side UI rules:

1. no new blocking confirmation for normal automatic republish,
2. optional lightweight status only when automatic republish fails repeatedly,
3. `Family Access` may show:
   - `Up to date`,
   - `Syncing shared goals`,
   - `Needs attention`.

The owner should only be asked to intervene when automatic republish repeatedly fails.

## 8.2 Invitee UX

The invitee should not need to guess whether the numbers are current.

Invitee UX rules:

1. `Shared with You` silently refreshes on foreground and first visibility,
2. if refresh succeeds, the section updates in place,
3. if refresh fails but a recent dataset exists, show `stale`,
4. if refresh fails and safe rendering cannot continue, show `temporarilyUnavailable`,
5. manual action remains available:
   - `Retry Refresh` for stale,
   - `Retry` for unavailable.

## 9) Telemetry and Diagnostics

Add and/or formalize events:

1. `family_share_auto_publish_requested`
2. `family_share_auto_publish_coalesced`
3. `family_share_auto_publish_succeeded`
4. `family_share_auto_publish_failed`
5. `family_share_invitee_foreground_refresh_requested`
6. `family_share_invitee_refresh_succeeded`
7. `family_share_invitee_refresh_failed`
8. `family_share_invitee_stale_viewed`
9. `family_share_publish_backoff_entered`
10. `family_share_publish_recovered`

Diagnostics payload must stay redacted and must not log:

1. goal names,
2. raw owner display names,
3. emails,
4. raw record names,
5. financial amounts.

## 10) Delivery Plan

## Phase 1: Owner Automatic Republish

1. add mutation observer boundary,
2. add debounced republish coordinator,
3. route authoritative shared-data mutations into the coordinator,
4. ensure rebuild-from-owner-truth publish path,
5. add publish telemetry and failure state.

Release gate:

1. owner edits no longer require manual re-share,
2. one mutation burst results in one published projection version,
3. repeated failures surface `Needs attention` rather than silently freezing.

## Phase 2: Invitee Automatic Refresh

1. add refresh scheduler,
2. trigger refresh on foreground and first visibility,
3. add cooldown suppression,
4. add stale threshold evaluation,
5. align section state transitions with refresh outcomes.

Release gate:

1. invitee sees new data after owner republish on the next natural refresh boundary,
2. stale vs unavailable is deterministic,
3. manual refresh remains functional.

## Phase 3: Operability Hardening

1. add telemetry dashboards / release gate thresholds,
2. add support runbook for publish vs refresh incidents,
3. add backoff and repeated-failure handling,
4. verify imports/bridge/dedup paths also trigger republish when they mutate shared semantics.

Release gate:

1. support can distinguish owner publish failure from invitee fetch failure,
2. rollout can be monitored for publish churn and stale-rate regressions.

## 11) Acceptance Criteria

This proposal is complete when:

1. updating a shared goal on the owner device no longer requires manually pressing `Share with Family`,
2. updating assets or transactions that change the shared goal total triggers automatic republish,
3. invitee app foreground triggers silent refresh under the freshness policy,
4. invitee receives updated goal totals and structure after owner republish within the defined SLA on healthy connectivity,
5. stale state is explicit when the app cannot confirm freshness,
6. unavailable state is explicit when safe rendering cannot continue,
7. publish and refresh telemetry are separated and redacted,
8. mutation hooks cover non-UI paths such as import/dedup/backfill where shared semantics change,
9. owner and invitee no longer need to use sharing UI as a manual sync workaround.

## 12) Test Plan

Required tests:

1. unit tests for debounce/coalescing:
   - many mutations in one burst produce one publish,
   - trailing dirty event produces one follow-up publish.
2. unit tests for mutation observer coverage:
   - goal edit,
   - asset mutation,
   - transaction mutation,
   - import/backfill path.
3. unit tests for refresh scheduler:
   - foreground refresh,
   - cooldown suppression,
   - stale threshold transition.
4. integration tests for publish/fetch loop:
   - owner mutation -> publish -> invitee refresh -> updated projection.
5. UI tests for invitee freshness:
   - active refresh,
   - stale state,
   - unavailable state,
   - updated totals appearing after owner mutation simulation.

## 13) Open Questions Resolved

1. Should v1 depend on CloudKit push subscriptions for invitee live updates?
   - No. v1 uses automatic republish plus automatic pull refresh on key lifecycle boundaries.
2. Should owner-side republish be partial or full projection rebuild?
   - Full rebuild from authoritative owner truth.
3. Should manual refresh remain after automatic refresh exists?
   - Yes. It remains as explicit recovery and support tooling.

## 14) Why This Proposal Is the Right Scope

This proposal deliberately fixes the real trust problem:

1. not just stale copy,
2. not just a retry button,
3. not just "tell users to refresh",
4. not just "tell owners to open Family Access again".

The problem is that shared goals currently lack a freshness contract.
The correct solution is to define and implement that contract across publish, fetch, states, telemetry, and recovery.
