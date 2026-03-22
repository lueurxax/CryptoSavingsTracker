# Shared Goals Freshness Sync Proposal

> Incident mapping: owner updates goals/assets on one device, but invitee-side shared goals on another device stay stale; exchange rate drift silently distorts shared progress

| Metadata | Value |
|---|---|
| Status | Draft |
| Priority | P0 Trust and Correctness |
| Last Updated | 2026-03-22 |
| Review Baseline | `SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_TRIAD_REVIEW_R8.md` |
| Platform | iOS |
| Scope | Read-only family sharing freshness, owner-side projection republish, exchange rate drift, invitee-side refresh contract, push notification |
| Affected Runtime | `FamilyShareServices`, `FamilyShareCloudKitStore`, `ExchangeRateService`, `PersistenceMutationServices`, family-sharing mutation hooks, invitee refresh behavior |

---

## 0) Incident Summary

The current family-sharing implementation behaves like a manually published snapshot, not like an always-fresh shared goal set.

Observed user failures:

1. the owner updates goals or assets on device A,
2. the invitee opens the app on device B,
3. `Shared with You` still shows old values or old goal structure.

Additionally:

4. crypto exchange rates change (e.g., BTC +10%),
5. the owner does not make any explicit edit,
6. the invitee still sees the old `currentAmount` and `progressRatio` baked into the last published snapshot.

Both failures are trust problems. Read-only sharing is only useful if the invitee can rely on the numbers as current enough to make the screen feel truthful.

## 0.1 Current Implementation Gap

Current behavior is structurally incomplete:

1. shared projection publish is triggered when the owner explicitly starts sharing, not when shared data changes,
2. `currentAmount` and `progressRatio` are **baked-in snapshot values** computed at publish time using `goal.manualTotal` — they do not update when exchange rates change,
3. `ExchangeRateService` has a 5-minute cache TTL but **no notification mechanism** (`ratesDidRefresh` or equivalent) — there is no way for downstream consumers to react to rate changes,
4. `GoalMutationService` posts **no notifications** after goal create, save, archive, or restore — the mutation notification surface in `PersistenceMutationServices` is inconsistent across mutation types,
5. invitee refresh pulls the current shared projection snapshot, but does not cause owner data to be republished,
6. there is no automatic freshness contract that defines when invitee data should update after owner changes or rate drift,
7. there is no user-facing distinction between:
   - "owner has not republished yet",
   - "invitee has not refreshed yet",
   - "rates have changed but nobody republished",
   - "owner has not opened the app recently",
   - "shared dataset is temporarily unavailable".

Result: both devices can be healthy individually while the shared surface is stale. Rate-driven progress drift compounds silently.

## 0.2 Why Exchange Rate Drift Matters

The projection publishes `currentAmount` and `progressRatio` as pre-computed values. These depend on exchange rates at the time of publish:

- `currentAmount` = sum of allocated asset values converted to goal currency via `GoalCalculationService`
- `progressRatio` = `currentAmount / targetAmount`

If BTC drops 20% overnight and the owner does not open the app, the invitee still sees yesterday's progress numbers. For a financial tracking app, showing a 65% progress bar when the real number is 52% is misleading.

This is not a minor polish issue. It is a correctness problem that undermines the core value proposition of shared visibility.

## 1) Problem

`Shared with You` currently violates the most important expectations of a read-only financial sharing feature:

1. owner changes should propagate without requiring the owner to manually restart sharing,
2. exchange rate changes should update shared progress without requiring any owner action,
3. invitee refresh should mean "get the latest published truth", not "show me the same stale snapshot again",
4. the system should have an explicit freshness SLA and state model with concrete numeric thresholds,
5. the invitee should know how fresh the displayed data is,
6. the invitee should understand whether staleness is caused by technical issues or by the owner not having opened the app,
7. telemetry and support should be able to distinguish publish failure from fetch failure from rate staleness.

Without this, the feature looks unreliable even when CloudKit itself is working.

## 2) Goal

Deliver a proper freshness model for shared goals so that:

1. owner-side mutations are republished automatically,
2. exchange rate drift triggers republish when the impact is material,
3. invitee-side shared goals refresh predictably,
4. the invitee can see when data was last updated and why it might be stale,

with a clear runtime contract and user-visible recovery states.

## 3) Non-Goals

This proposal does not include:

1. a redesign of participant management,
2. a redesign of the invitee list IA or card layout,
3. Android implementation in the same pass,
4. changing the read-only permission model,
5. invitee-side rate recalculation (invitees see what the owner published, not independently computed values),
6. background app refresh for the owner app (owner must be in foreground for rate-triggered republish in v1).

### 3.1 Known Limitation: Owner-Absent Staleness

In v1, rate-drift republish requires the owner app to be in foreground. If the owner does not open the app for days, the invitee will see data that is days old. This is a fundamental limitation of the foreground-only design.

Mitigation in v1:

1. the invitee surface explicitly communicates projection age (Section 8.2, 8.3),
2. multi-day staleness shows distinct copy that signals the data may be significantly outdated (Section 6.4),
3. the rate freshness indicator warns when rates are stale (Section 8.3).

Future mitigation (post-v1):

1. `BGAppRefreshTask` for periodic owner-side rate refresh and republish,
2. invitee-side local rate recalculation as an optional secondary display.

## 4) Decision-Locked Fix Direction

The following decisions are locked:

1. owner-side shared projection must republish automatically after authoritative mutations that affect shared-goal semantics,
2. owner-side shared projection must republish automatically when exchange rate changes materially alter any goal's `currentAmount`,
3. invitee-side freshness must not depend on the owner re-opening `Family Access` or manually tapping `Share with Family`,
4. shared projection publishing must be debounced/coalesced; one editing burst or rate refresh must not create one CloudKit publish per field change,
5. invitee refresh remains a pull model in v1, augmented by CloudKit zone subscription push in v2,
6. manual refresh remains available as an explicit recovery affordance,
7. freshness states must distinguish:
   - `active`,
   - `stale` (with tiered severity based on age),
   - `temporarilyUnavailable`,
   - `removedOrNoLongerShared`,
8. the projection must include `rateSnapshotTimestamp` so invitees and diagnostics can assess rate freshness,
9. `currentAmount` in the canonical projection rebuild must be computed via a pure domain calculator (`GoalProgressCalculator`) extracted from `GoalCalculationService`, not via `goal.manualTotal` or presentation-bound view models,
10. all freshness events (mutation dirty, rate-drift dirty, debounce, publish, failure, backoff) must be consumed by a single serialized owner per namespace (`FamilyShareProjectionAutoRepublishCoordinator`, one instance per namespace within `FamilyShareNamespaceActor`) — no competing view-triggered or lifecycle-triggered refresh paths may bypass the coordinator; publish execution delegates to the existing `FamilyShareProjectionPublishCoordinator` (Section 6.1.1),
11. telemetry must separate:
    - owner publish requested/succeeded/failed,
    - invitee refresh requested/succeeded/failed,
    - stale view exposure (with duration bucket),
    - rate-drift-triggered publish,
    - excessive publish churn,
12. shared-goal freshness is a product contract with an SLA, not a best-effort side effect.

## 5) Product Contract

### 5.1 User-Facing Freshness Contract

When an owner changes shared-goal data on one device, or when exchange rates change materially:

1. the system should automatically republish the shared projection,
2. the invitee should see the updated shared goals by the next natural refresh boundary,
3. if refresh cannot complete, the invitee must see an explicit unhealthy state instead of silently stale data,
4. the invitee should see a composite freshness indicator derived from `FamilyShareFreshnessLabel` (e.g., "Shared 5 minutes ago" or "Rates are 2 hours old").

Initial SLA targets for v1:

1. owner mutation to successful projection republish: usually under 30 seconds on healthy connectivity,
2. exchange rate refresh to republish (when material): usually under 60 seconds on healthy connectivity,
3. invitee app entering foreground with an existing shared dataset: silent refresh attempt within 5 seconds,
4. invitee opening `Shared with You` after a successful owner republish: updated data visible within 60 seconds under healthy connectivity.

### 5.1.1 Concrete Staleness Thresholds

The existing FAMILY_SHARING.md defines `active` as "reconciliation within 24h". This proposal replaces that with a composite trust model.

**Composite freshness rule**: the effective freshness state is governed by the **older** of `projectionPublishedAt` and `rateSnapshotTimestamp`. A projection that was published 5 minutes ago but used 6-hour-old rates is `stale`, not `active`. This prevents a surface from appearing healthy while showing materially stale rate-based progress.

| Internal State | Threshold (applies to the older of publish age and rate age) | Rationale |
|---|---|---|
| `active` | effective age < 30 minutes | Rates refresh every 5 min; 30 min covers several cycles |
| `recentlyStale` | 30 min <= effective age < 4 hours | Rates may have drifted meaningfully |
| `stale` | 4 hours <= effective age < 24 hours | Crypto can swing 5-20% in hours; data should not be trusted silently |
| `materiallyOutdated` | effective age >= 24 hours | Data is unreliable for financial decisions |
| `temporarilyUnavailable` | refresh failure with no safe cached data | Cannot show any trustworthy data |

**Freshness ownership**: freshness is evaluated and displayed **per namespace/owner section**, not as a single aggregate across all shared datasets. The live product groups shared goals by owner namespace; each namespace section has its own `projectionPublishedAt` and `rateSnapshotTimestamp`. Freshness is therefore inherently per-namespace:

1. each namespace section header shows its own primary freshness message derived from that namespace's composite effective age,
2. two namespace sections on the same list may show different freshness tiers simultaneously (e.g., one `active`, one `stale`),
3. no single header, banner, or aggregate label may imply that all shared datasets share the same freshness state,
4. `FamilyShareFreshnessLabel` is instantiated per namespace, not per list.

**Visible UX**: each namespace section shows one primary freshness message and one optional recovery action, to keep the compact surface scannable (see Section 8.2). Richer tier detail (rate age, exact timestamps) is available behind the detail view or an info affordance.

The `materiallyOutdated` tier must not blame the owner or imply negligence. Copy should focus on data freshness, not owner behavior.

This is not a real-time streaming guarantee. It is a clear, trustworthy freshness contract.

### 5.2 What Counts as Shared Data

Automatic republish must be triggered by mutations that change invitee-visible semantics, including:

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

### 5.3 Exchange Rate Drift as Republish Trigger

Exchange rate changes affect `currentAmount` and `progressRatio` for every goal where assets are denominated in a different currency than the goal target.

Rate-drift republish rules:

1. after `ExchangeRateService` completes a rate refresh, the republish coordinator must recompute `currentAmount` for all shared goals using `GoalProgressCalculator`,
2. if **any** goal's `currentAmount` changed by more than the materiality threshold compared to the last published snapshot, a republish is triggered,
3. if no goal's `currentAmount` changed materially, no republish occurs (avoids churn from sub-cent fluctuations),
4. the materiality threshold for v1 is **1% of `targetAmount`** or **$5 equivalent** (whichever is **larger**), evaluated per goal,
5. rate-drift republish uses the same debounce/coalescing pipeline as mutation-triggered republish,
6. the republish coordinator must store the last published `currentAmount` per goal to evaluate materiality without requiring a CloudKit fetch.

Materiality threshold rationale:

- "whichever is larger" ensures the $5 floor catches small goals (prevents churn on a $50 goal from $0.50 fluctuations) while 1% catches large goals (prevents churn on a $50K goal from $5 noise).
- Expected republish frequency: on a volatile day (BTC +-10%), a user with 5 goals ranging $100-$50K should see ~2-4 rate-drift publishes per foreground session, not dozens.

#### 5.3.1 Materiality Policy for Non-USD Goals (`FamilyShareMaterialityPolicy`)

The "$5 equivalent" floor must be deterministic across all goal currencies:

1. **Quote currency**: the goal's own `currency` is the quote currency — materiality is evaluated in the same unit the invitee sees,
2. **Conversion source**: `ExchangeRateService` cached rate from the same refresh batch that triggered evaluation — no separate rate lookup,
3. **Conversion path**: `$5 USD` is converted to the goal's currency at the current `USD → goalCurrency` rate. If the rate is unavailable, fall back to the 1% threshold only (skip the absolute floor),
4. **Rounding**: the converted floor is rounded to the goal currency's minor units (e.g., 2 decimals for EUR, 0 for JPY) using `.bankers` rounding,
5. **Comparison**: `abs(newAmount - lastPublishedAmount) > max(0.01 * targetAmount, convertedFloor)` triggers dirty,
6. **Policy object**: a single `FamilyShareMaterialityPolicy` encapsulates the threshold rule, conversion, and rounding. All materiality checks — rate-drift evaluator, telemetry, and tests — reference this policy. No threshold constants outside this object.

Example:

| Goal Currency | Target | $5 USD equivalent | Effective Floor | 1% of Target | Materiality Threshold |
|---|---|---|---|---|---|
| USD | $10,000 | $5.00 | $5.00 | $100.00 | $100.00 (1% wins) |
| USD | $200 | $5.00 | $5.00 | $2.00 | $5.00 (floor wins) |
| EUR | 8,000 | ~4.60 | 4.60 | 80.00 | 80.00 (1% wins) |
| JPY | 500,000 | ~750 | 750 | 5,000 | 5,000 (1% wins) |
| BTC | 1.0 | ~0.00005 | 0.00005 | 0.01 | 0.01 (1% wins) |

### 5.4 Owner Foreground Rate Refresh Pipeline

When the owner app enters foreground:

1. `ExchangeRateService` checks rate cache freshness (5-minute TTL),
2. if rates are stale, a rate refresh is requested,
3. on successful rate refresh, the republish coordinator evaluates materiality for all shared goals,
4. if material change detected, a debounced republish is enqueued,
5. if no material change, no action is taken.

This pipeline ensures that even if the owner makes no explicit edits, the invitee sees rate-adjusted progress after the owner simply opens the app.

### 5.5 Foreground Rate-Refresh Driver and Periodic Guard

The live `ExchangeRateService` is an on-demand cache/fetch service — it refreshes rates when a consumer requests them and the cache has expired, but it does not proactively refresh on a timer. To meet the 5-minute freshness SLA during long foreground sessions, the freshness pipeline must include its own **active refresh driver**:

1. `FamilyShareForegroundRateRefreshDriver` (new component) runs a repeating timer at the rate TTL interval (5 minutes) while the owner app is in foreground and sharing is active,
2. on each tick, the driver calls `ExchangeRateService.refreshRatesIfStale()` — this triggers a rate fetch only if the cache has expired (5-minute TTL), making it a no-op when rates are already fresh,
3. after a successful rate refresh, `ExchangeRateService` posts `exchangeRatesDidRefresh`, which the rate-drift evaluator receives and evaluates for materiality,
4. the driver is started when the app enters foreground and at least one namespace is actively shared; it is suspended on background entry or when no sharing is active,
5. the driver uses the `FamilyShareScheduler` seam for testability (virtual time in tests).

Additionally, a periodic guard check runs every 15 minutes as a safety net:

6. the guard verifies that at least one rate-refresh cycle has completed in the last TTL window,
7. if the guard detects a missed refresh (e.g., the driver timer was skipped due to system throttling), it forces a rate fetch and evaluation,
8. the guard is suspended on background entry.

This design guarantees that during a foreground session with active sharing, rate-drift evaluation occurs at least every 5 minutes (driven by the refresh driver), with the 15-minute guard as a fallback safety net. No namespace can exceed the stated 5-minute TTL without a refresh/evaluation attempt.

### 5.6 CloudKit Write Volume Estimate

Each projection publish writes 1 root record + N goal records. For a user with 10 goals, one publish = 11 CKRecord saves.

Expected volume per foreground session under normal usage:

| Scenario | Publishes | CKRecord Saves |
|---|---|---|
| Owner edits 3 goals in a burst | 1 | 11 |
| Owner edits + rate drift triggers | 2 | 22 |
| 1-hour session with 15-min periodic check, one drift | 2-3 | 22-33 |
| Heavy editing day (10 separate edit bursts + 3 drift triggers) | ~8 | ~88 |

CloudKit per-user daily limits are undocumented but generally in the thousands of record saves. The expected daily volume of <100 saves is well within safe bounds.

If `family_share_auto_publish_failed` shows `CKError.requestRateLimited` errors, the exponential backoff (Section 6.2) handles it. Monitoring via `family_share_publish_backoff_entered` telemetry detects systemic issues.

## 6) Proposed Runtime Model

### 6.1 Owner-Side Automatic Projection Republish

Introduce a dedicated owner-side freshness pipeline with a single serialized event owner **per namespace**:

1. authoritative mutation completes in the owner datastore,
2. mutation emits a `sharedProjectionDirty` event with affected goal IDs and reason,
3. `FamilyShareProjectionAutoRepublishCoordinator` consumes all dirty events through a single typed event stream,
4. coordinator debounces and coalesces bursts,
5. coordinator rebuilds one canonical shared projection from current owner truth using `GoalProgressCalculator` for `currentAmount` (not `goal.manualTotal`),
6. coordinator publishes the new projection to CloudKit via the existing atomic publish path,
7. publication updates local owner shared-state metadata, last-published snapshot, and telemetry.

#### 6.1.1 Per-Namespace Executor Composition

The repo already has per-namespace isolation via `FamilyShareNamespaceActor` (managed by `FamilyShareNamespaceExecutionHub`) and publish tracking via `FamilyShareProjectionPublishCoordinator`. The new auto-republish coordinator must compose with — not replace or duplicate — these existing components.

**Authoritative execution ownership per namespace**:

```
FamilyShareNamespaceActor (per-namespace actor — already exists)
  └── owns: namespace lifecycle state, acceptance, revocation
  └── owns: projection payload cache
  └── delegates publish to: FamilyShareProjectionPublishCoordinator (already exists)
        └── owns: outbox tracking, atomic CloudKit publish
        └── delegates CloudKit write to: FamilyShareCloudKitStore.modify() (atomic, already exists)

FamilyShareProjectionAutoRepublishCoordinator (NEW — per-namespace instance)
  └── owns: dirty event stream, debounce/coalescing, backoff, retry
  └── lives INSIDE FamilyShareNamespaceActor (or is called exclusively by it)
  └── triggers publish VIA FamilyShareProjectionPublishCoordinator (never calls CloudKit directly)
  └── triggers rebuild VIA GoalProgressCalculator (pure domain, no @MainActor)
```

**Composition rules**:

1. `FamilyShareProjectionAutoRepublishCoordinator` is instantiated **per namespace** by `FamilyShareNamespaceExecutionHub`, not as a singleton,
2. the auto-republish coordinator runs within or is called exclusively by the owning `FamilyShareNamespaceActor` — it inherits the actor's serialization guarantee,
3. the auto-republish coordinator does not call `FamilyShareCloudKitStore` directly — it delegates publish execution to `FamilyShareProjectionPublishCoordinator`, preserving the existing outbox and atomic publish semantics,
4. `FamilyShareProjectionPublishCoordinator` remains the sole publish execution owner — no component bypasses it to write to CloudKit,
5. legacy refresh paths (`refreshAllState()` in `FamilyShareAcceptanceCoordinator`, manual refresh from `FamilyAccessView`) must be bridged through the auto-republish coordinator for any publish-triggering action:
   - **read-only refresh** (fetching invitee projection, checking namespace health): remains in `FamilyShareAcceptanceCoordinator` — no publish involved,
   - **publish-triggering actions** (manual re-share, forced republish): must route through `FamilyShareProjectionAutoRepublishCoordinator` as a `manualRefresh` dirty event, so coalescing and backoff still apply,
6. no component outside the `FamilyShareNamespaceActor` boundary may trigger a publish — accept, refresh, revoke, publish, and republish all flow through the namespace actor.

**Migration from current state**:

1. the existing `FamilyShareProjectionPublishCoordinator` is retained as the publish execution layer,
2. the new auto-republish coordinator is added as the dirty-event/debounce layer that sits above it,
3. direct calls to `publishProjection()` from view code or `FamilyAccessView` are replaced with dirty-event emissions into the auto-republish coordinator,
4. `refreshAllState()` continues to handle invitee-side read operations but no longer triggers owner-side publishes directly.

### 6.2 Debounce and Coalescing Contract

Automatic republish must be rate-limited:

1. editing bursts across a short window are collapsed into one publish,
2. rate-drift dirty events use the same pipeline as mutation dirty events,
3. repeated mutations or rate changes while one publish is in flight must enqueue at most one trailing publish,
4. the last state wins; invitee should get the newest canonical state, not a queue of intermediate states,
5. failure should not permanently stop future publishes.

Initial v1 defaults:

1. debounce window for mutations: 2 seconds,
2. debounce window for rate-drift: 5 seconds (rates are less urgent than explicit edits),
3. maximum in-flight publish concurrency: 1 per namespace,
4. trailing publish after in-flight completion if additional dirty events arrived,
5. exponential backoff for repeated publish failures: 5s, 15s, 60s, 300s cap.

### 6.3 Invitee Refresh Contract

Invitee-side refresh in v1 is automatic pull on important lifecycle boundaries:

1. after invitation acceptance,
2. when the app enters foreground,
3. when `Shared with You` becomes visible for the first time in a foreground session,
4. when the user explicitly taps refresh or retry,
5. (v2) when a CloudKit zone subscription push notification is received.

Additional rules:

1. foreground refresh should be skipped if the namespace was refreshed within the last 30 seconds,
2. list rendering should not block on network if a cached projection exists,
3. stale cached data may render briefly, but only if accompanied by the correct freshness semantics,
4. silent refresh must update the section when newer projection data is fetched,
5. the invitee surface must show a primary freshness indicator derived from `FamilyShareFreshnessLabel` using composite effective age (not raw `publishedAt` alone).

### 6.4 Freshness State Semantics

The invitee surface must use a **composite** freshness model (replacing the single 24h threshold from FAMILY_SHARING.md), evaluated **per namespace**.

**Effective age** = `max(age(projectionPublishedAt), age(rateSnapshotTimestamp))`, where both timestamps belong to the same namespace's projection. This ensures that stale rates escalate the primary freshness state even if the projection was published recently.

Each namespace section carries its own independent freshness state. Mixed-freshness scenarios (one namespace `active`, another `stale`) are expected and displayed truthfully per section.

Internal states (evaluated per namespace):

1. `active`
   - effective age < 30 minutes.
2. `recentlyStale`
   - effective age is 30 minutes to 4 hours.
3. `stale`
   - effective age is 4 hours to 24 hours.
4. `materiallyOutdated`
   - effective age is 24+ hours.
5. `temporarilyUnavailable`
   - refresh failed and safe rendering requires suppressing the normal active dataset.
6. `removedOrNoLongerShared`
   - the share or dataset is no longer available to the invitee.

`recentlyStale`, `stale`, and `materiallyOutdated` are all allowed to render the last known shared dataset.

#### 6.4.1 Terminal State: Removed or Revoked Namespaces

When a share is revoked by the owner or the dataset is no longer available, the namespace enters the `removedOrNoLongerShared` terminal state. This state has specific rules to prevent stale financial data from remaining visible:

**Terminal-state behavior**:

1. all cached financial rows (goal names, amounts, progress) are **removed immediately** — no outdated financial amounts may remain visible after revocation,
2. the namespace section is replaced with a non-financial explanatory state:
   - Copy: "This shared goal set is no longer available"
   - Icon: `person.crop.circle.badge.minus`
   - No retry action — revocation is permanent from the invitee's perspective,
3. navigation into revoked goal detail is **blocked** — tapping the explanatory state does nothing; any deep links to revoked goals redirect to the shared goals list,
4. a **dismiss/remove affordance** (swipe-to-delete or trailing "Remove" button) allows the invitee to clear the orphaned namespace from their list,
5. after dismissal, the namespace is removed from the invitee's cached state and no longer appears in the list.

**Detection**:

1. revocation is detected when a fetch returns `CKError.zoneNotFound`, `.unknownItem`, or `.participantMayNeedVerification`,
2. if the fetch returns a valid projection but with an empty goal list, the namespace transitions to the `empty` variant (Section 6.4.2), not `removedOrNoLongerShared`,
3. the terminal state is persisted locally so the explanatory state survives app relaunch until the user dismisses it.

**Privacy rule**: cached financial data from a revoked share must be purged from the local cache (not just hidden) to prevent accidental or forensic exposure of the owner's data after revocation.
`temporarilyUnavailable` may suppress the normal dataset if safety requires it.

**No screen can remain in `active` state when rate age is already past the `recentlyStale` threshold.**

#### 6.4.2 Empty State and Freshness Precedence

An explicit `empty/noSharedGoals` state participates in the freshness state model:

| Condition | Display | Freshness Chrome |
|---|---|---|
| No shared namespaces exist (never accepted an invitation) | Empty-state explanation only ("No shared goals yet") | None — no freshness label, no retry action |
| Namespace exists but contains zero goals (owner removed all goals) | Namespace header with "No shared goals in this group" | Freshness label reflects namespace age (owner may republish with goals later) |
| Namespace exists, fetch failed, no cached data | `temporarilyUnavailable` state | Error freshness label with retry |

Precedence rules:

1. freshness messaging is suppressed entirely when no shared namespace exists — the empty-state explanation is the only visible element,
2. a namespace with zero goals still shows its freshness tier because the namespace is live and the owner may add goals,
3. `temporarilyUnavailable` takes priority over empty only when a namespace was previously populated and a fetch failure prevents rendering,
4. the empty state must never show stale/unavailable freshness chrome that implies data exists when it does not.

#### 6.4.3 Stale-Cause and Recovery Substates

The primary freshness tier (Section 6.4) describes **data age**. To give users actionable recovery information, each stale-or-worse tier carries an additional **cause/recovery substate** that distinguishes "old data" from "failed refresh":

| Substate | Trigger | User-Facing Copy (appended to primary freshness) | Recovery Action |
|---|---|---|---|
| `idle` | Normal display, no refresh in progress | (none — primary message only) | "Retry Refresh" (if stale or worse) |
| `checking` | Refresh in progress | "Checking for updates..." | (disabled, shows spinner) |
| `refreshFailed` | Latest refresh attempt failed (network error, CloudKit error) | "Couldn't refresh — showing last shared update" | "Try Again" |
| `checkedNoNewData` | Refresh succeeded but returned the same or older projection (no newer publish exists) | "Checked just now — no newer update yet" | (none — retry is not meaningful until owner republishes) |
| `refreshSucceeded` | Refresh completed, newer data available | (none — primary message updates to new tier) | (none) |
| `cooldown` | Retry attempted within 30-second cooldown window | (same as before retry) | "Try Again" (disabled with countdown or grayed) |

Substate rules:

1. `checking` replaces the recovery action with a progress indicator — the user knows the system is actively trying,
2. `refreshFailed` clearly distinguishes "we tried and failed to fetch" from "no newer data exists" — the former shows "Couldn't refresh", the latter never appears as a failure,
3. `checkedNoNewData` is a distinct non-error state — the refresh technically succeeded but the owner has not published a newer projection. The user sees the primary freshness message (based on data age) **plus** an appended secondary line: "Checked just now — no newer update yet". This state does **not** show a retry action because retrying would produce the same result until the owner republishes. The primary age-based message remains the dominant first line and is never replaced by the `checkedNoNewData` copy,
4. CTA mapping by cause:
   - **fetch failed** (network/CloudKit error): "Try Again" (retrying may help),
   - **no newer projection** (successful fetch, same content): no CTA (retrying cannot help until owner acts),
   - **data is old** (stale tier, idle substate): "Retry Refresh" (a newer projection may exist),
5. `cooldown` prevents tap-spam by disabling the retry button for 30 seconds after the last attempt, with visual feedback (grayed state or brief countdown),
6. substates are transient UI state, not persisted — they reset on app relaunch,
7. stale copy must never blame the owner: "Couldn't refresh" refers to the system; "no newer update yet" is neutral,
8. `refreshFailed` substate falls back to the data-age primary message after 60 seconds of inactivity (auto-dismiss), so the screen does not permanently show a failure banner,
9. `checkedNoNewData` substate falls back to `idle` after 120 seconds (the last-checked note disappears and the primary freshness message stands alone).

### 6.5 Rate-Aware Republish Pipeline

The rate-drift pipeline operates alongside the mutation pipeline:

```
ExchangeRateService.ratesDidRefresh notification
    |
    v
FamilyShareRateDriftEvaluator
    - reads last published snapshot (local cache)
    - recomputes currentAmount for each shared goal using GoalProgressCalculator
    - compares against last published currentAmount
    - if any delta exceeds materiality threshold:
        |
        v
    emits sharedProjectionDirty(reason: .rateDrift, affectedGoalIDs: [...])
        |
        v
    FamilyShareProjectionAutoRepublishCoordinator (same debounce pipeline)
```

Key contract:

1. `FamilyShareRateDriftEvaluator` does NOT trigger a rate refresh itself; it reacts to `ExchangeRateService` completing a refresh,
2. the evaluator stores the last published amounts in a lightweight local snapshot (not in CloudKit),
3. the evaluator runs on the same actor as the republish coordinator to avoid races,
4. rate-drift dirty events carry `reason: .rateDrift` so telemetry can distinguish them from mutation-triggered publishes.

### 6.6 Projection Metadata and Canonical Freshness Model

The shared projection payload must include rate provenance metadata:

1. `rateSnapshotTimestamp` — the timestamp of the exchange rates used to compute `currentAmount` values in this projection,
2. `projectionPublishedAt` — when this projection version was published (already exists as `publishedAt`).

#### 6.6.1 Canonical Clock Source and Skew Handling

Freshness timestamps must be sourced from authoritative clocks to prevent bad device time from making stale data appear fresh or vice versa:

**Time provenance per timestamp**:

| Timestamp | Canonical Source | Rationale |
|---|---|---|
| `projectionPublishedAt` | `CKRecord.modificationDate` (server-assigned) | Server time is globally consistent; cannot be spoofed by device clock |
| `rateSnapshotTimestamp` | `ExchangeRateService` response timestamp (API-server-assigned when available, device `Date()` as fallback) | Rate freshness should reflect when the rate was actually fetched from the upstream API |
| Freshness evaluation (age calculation) | Invitee device `Date()` | Age is computed locally by comparing server-sourced timestamps against local time |

**Clock skew handling**:

1. **Future timestamp clamping**: if `projectionPublishedAt` or `rateSnapshotTimestamp` is in the future relative to the invitee's device clock (indicating device or server clock skew), the effective age is clamped to zero — the projection is treated as `active` but a telemetry event `family_share_clock_skew_detected` is emitted with the skew magnitude,
2. **Skew tolerance**: a 60-second tolerance window is applied before flagging skew — timestamps up to 60 seconds in the future are treated as zero-age without telemetry (accounts for minor clock drift),
3. **Owner clock skew**: because `projectionPublishedAt` is server-assigned (`CKRecord.modificationDate`), owner device clock skew does not affect the publish timestamp. `rateSnapshotTimestamp` uses the API response time when available, minimizing owner-clock dependency,
4. **Invitee clock skew**: if the invitee's device clock is significantly behind, all projections may appear older than they are — this is an inherent limitation of device-local age computation. Telemetry tracks anomalous age values (> 30 days) as potential skew indicators,
5. **NTP sync**: the app does not implement its own NTP sync and cannot directly query whether `Set Automatically` is enabled. Instead, clock-skew diagnostics are based on **observed timestamp anomalies**: if freshness age computations produce anomalous values (e.g., effective age > 30 days, or multiple projections arrive with future timestamps), telemetry records the anomaly via `family_share_clock_skew_detected`. This is best-effort — the app cannot distinguish "user disabled automatic time" from "server clock drift" and does not attempt to.

**Test cases for clock skew**:

1. owner-fast: `projectionPublishedAt` is 5 minutes in the future relative to invitee clock — freshness shows `active` (clamped), telemetry fires,
2. owner-slow: `projectionPublishedAt` is 30 minutes older than actual — freshness correctly shows `recentlyStale` (conservative, acceptable),
3. invitee-fast: invitee clock is 2 hours ahead — projections appear 2 hours older than they are (conservative, acceptable),
4. invitee-slow: invitee clock is 2 hours behind — projections appear 2 hours fresher than they are — future-timestamp clamping prevents false `active` only when the projection timestamp is in the future; if the invitee clock is merely slow, this is a user-side issue mitigated by automatic time setting.

**Canonical freshness string model**: one `FamilyShareFreshnessLabel` struct produces all freshness copy for both list and detail surfaces. Surfaces may vary in density (list shows one line, detail may show more), but they must use the same effective-age basis, the same trust semantics, and the same composite rule (`max(publishAge, rateAge)`).

List surface:

1. one primary freshness message derived from the composite effective age (see Section 8.2),
2. one optional secondary rate-age detail, shown only when rate age is the governing dependency and differs meaningfully from publish age.

Detail surface:

1. the same primary freshness message as the list,
2. expanded provenance section with two rows:
   - **"Last shared"**: relative time as primary display (e.g., "5 min ago"), with exact local timestamp visible inline in secondary text (e.g., "5 min ago (Mar 22, 2:14 PM)"),
   - **"Rates as of"**: relative time as primary display, with exact local timestamp visible inline in the same format,
3. richer tier explanation behind an info affordance when the state is `stale` or worse.

**Provenance format contract** (canonical — this section governs all detail-view provenance rendering):

At all Dynamic Type sizes, both provenance rows ("Last shared" and "Rates as of") remain visible in the Freshness card. Exact local timestamps use a **disclosure pattern**: a `chevron.right` affordance on each provenance row expands to show the exact timestamp inline below the relative time. This is the single canonical rule — there is no separate "always inline" vs "collapse" behavior.

| Dynamic Type Size | Relative Time | Exact Timestamp | Disclosure State |
|---|---|---|---|
| Default through XXXL | Visible inline | Visible inline (expanded by default) | Auto-expanded |
| AX1 through AX5 | Visible inline | Behind disclosure chevron (collapsed by default) | User-expandable, one tap |

Rules:

1. relative-time provenance rows are always visible at all sizes — they never collapse or disappear,
2. at default through XXXL sizes, exact timestamps are shown inline and the disclosure chevron is auto-expanded (user sees both without tapping),
3. at AX1 through AX5, exact timestamps are collapsed by default behind the disclosure chevron to protect the financial summary from being pushed below the fold — but one tap expands them inline within the card (no separate sheet, no further navigation),
4. VoiceOver reads the relative time first; exact timestamps are in a child accessibility group that the user can navigate into,
5. the Freshness card must never push `Current` / `Target` below the fold at any Dynamic Type size.

### 6.7 CloudKit Zone Subscription for Invitee Push (v2)

In v2, add a `CKRecordZoneSubscription` on each accepted namespace's zone:

1. when the owner publishes a new projection version, CloudKit sends a silent push notification to all participants,
2. the invitee app receives the notification via `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`,
3. the notification triggers the invitee refresh scheduler to fetch the new projection immediately,
4. this reduces the latency from "next foreground boundary" to "within seconds of publish".

Requirements for v2:

1. `remote-notification` background mode (already declared),
2. `CKRecordZoneSubscription` created during acceptance for each namespace zone,
3. subscription cleanup on revocation or dataset removal,
4. no user-facing notification — this is a silent data update.

v1 does not depend on push; it uses pull-on-lifecycle-boundary as the baseline.

### 6.8 Multi-Device Owner Coordination

If the owner uses multiple devices (iPhone + iPad), both may attempt to republish. A naive last-writer-wins approach is **not** safe because publish payloads are rebuilt from local `Goal` state, and a lagging device may not have imported the latest CloudKit changes. A stale device could therefore publish an older semantic snapshot with a newer server timestamp, regressing the invitee's visible truth.

Core rules:

1. every owner device must pass a **pre-publish reconciliation barrier** before publishing (Section 6.8.1),
2. the republish coordinator must be idempotent — publishing the same semantic state twice is a no-op from the invitee's perspective,
3. no distributed lock or leader election is required — the reconciliation barrier ensures local state is current before publish,
4. invitee-side must use monotonic version comparison to prevent transient regression from any remaining race window (Section 6.8.2).

#### 6.8.1 Pre-Publish Reconciliation Barrier

Before the auto-republish coordinator is allowed to publish, it must verify that its local SwiftData store reflects the latest CloudKit truth. This prevents a lagging owner device from publishing a semantically older snapshot.

**Barrier mechanism**: CloudKit import fence.

```
Auto-republish coordinator receives dirty event
    |
    v
1. Check CloudKit sync status for the owner's private database zone
    |
    v
2. If pending imports exist:
    - Wait for import completion (with timeout)
    - Re-snapshot local Goal state AFTER import completes
    |
    v
3. If import fence cannot be satisfied (timeout, error):
    - Suppress publish
    - Keep namespace dirty for retry on next cycle
    - Emit telemetry: family_share_publish_suppressed_stale_local
    |
    v
4. If import fence is satisfied:
    - Snapshot local Goal state
    - Compute projection via GoalProgressCalculator
    - Include a content hash in the projection payload
    - Proceed to publish
```

**Import fence implementation**:

1. the coordinator queries `NSPersistentCloudKitContainer`'s import state via `NSPersistentCloudKitContainer.EventType.import` history tokens, or observes `NSPersistentCloudKitContainer.eventChangedNotification` for pending import events,
2. if the last successful import timestamp is older than the last known remote mutation (tracked via the namespace's `CKServerChangeToken`), the device is considered lagging,
3. a lagging device must wait up to 10 seconds for import completion before suppressing publish,
4. the 10-second timeout is configurable via `FamilyShareFreshnessPolicy` and testable via `FamilyShareScheduler` seam,
5. if the device has been offline and comes back online, the barrier naturally holds publish until CloudKit sync delivers any pending remote changes.

**Content hash for semantic deduplication**:

1. the projection payload includes a `contentHash` computed from **all invitee-visible state**, including:
   - canonical goal data (goal IDs, `currentAmount` values, `targetAmount` values, allocation structure),
   - rate snapshot timestamp,
   - root record metadata visible to invitees: owner display name, participant list, participant count,
2. `contentHash` is a lightweight SHA-256 of the sorted, deterministic canonical payload — any field change that affects what the invitee sees must change the hash,
3. the invitee uses `contentHash` as a secondary deduplication check: if an incoming projection has the same `contentHash` as the cached projection, it is treated as a no-op regardless of version ordering,
4. this ensures that even if a stale device passes the barrier (because imports completed just before publish), its semantically identical payload does not cause unnecessary UI churn,
5. `.participantChange` dirty events (owner display-name, participant add/remove) produce a different `contentHash` because root metadata is included in the hash — these publishes are never incorrectly deduplicated.

**Scenarios**:

| Scenario | Barrier Behavior | Outcome |
|---|---|---|
| Device A edits goal, publishes; Device B opens later | Device B's import fence detects pending import; waits for sync; publishes with merged state | Invitee sees correct merged state |
| Device A edits goal, publishes; Device B opens with stale state, edits a different goal | Device B's import fence waits for import of A's changes; after import, B rebuilds with both changes; publishes | Invitee sees both changes |
| Device B is offline for hours, comes back | Import fence holds until CloudKit sync completes; only then publishes | No stale publish |
| Device B's import times out (10s) | Publish suppressed; namespace stays dirty; retries on next cycle | Invitee sees A's last publish (no regression) |
| Both devices are fully synced and publish concurrently | Both pass barrier; both publish semantically identical payloads; invitee deduplicates via `contentHash` | No regression, no churn |

**Telemetry**:

1. `family_share_publish_suppressed_stale_local` — with `pendingImportAge`, `namespaceID` (hashed),
2. `family_share_reconciliation_barrier_waited` — with `waitDurationMs`, `importCompleted: Bool`,
3. `family_share_content_hash_dedup` — invitee discarded incoming projection because `contentHash` matched cached.

#### 6.8.2 Version and Ordering Contract

The live system uses an `Int`-based `projectionVersion` and `activeProjectionVersion` for atomic publish topology. This proposal introduces a separate server-assigned timestamp for freshness ordering. These two concerns are explicitly separated:

**Atomic publish token** (`projectionVersion: Int`):

1. retained as-is from the current implementation,
2. the auto-republish coordinator increments `projectionVersion` (Int) when preparing a new publish,
3. child goal records are written under the new version number,
4. `activeProjectionVersion` on the root record is flipped to the new version after all children are saved,
5. this preserves the existing atomic publish topology — invitees only see a consistent set of records.

**Pre-migration ordering fallback** (`projectionServerTimestamp: Date`) — NEW field:

1. set to `CKRecord.modificationDate` of the root projection record returned by CloudKit after successful atomic publish,
2. stored in the projection payload alongside `projectionVersion` (Int),
3. used by telemetry, diagnostics, and publish-timing analysis,
4. used by the invitee **only as a pre-migration fallback** when `contentHash` is `nil` (see ordering logic below). For post-migration payloads where `contentHash` is present, `contentHash` is the authoritative ordering signal — `projectionServerTimestamp` is not consulted for accept/reject decisions.

**Invitee ordering logic** (three-phase, fail-closed):

1. **Phase 1 — Atomic version check**: incoming `projectionVersion` (Int) must be >= cached `activeProjectionVersion` (Int). If less, discard (incomplete publish from old topology),
2. **Phase 2 — Content dedup**: if `contentHash` matches cached, treat as no-op regardless of version or timestamp (prevents UI churn from identical publishes). This check runs **before** freshness ordering to prevent semantically identical payloads from causing churn even when timestamps differ,
3. **Phase 3 — Semantic freshness check**: if `contentHash` differs (semantic change detected), accept the incoming projection unconditionally — a different hash proves newer semantic truth regardless of timestamp ordering. If the incoming `contentHash` is `nil` (pre-migration), fall back to `projectionServerTimestamp` comparison and accept only if strictly newer.

This ordering ensures that **semantic change always wins over timestamp ordering**. A stale device that passes the reconciliation barrier and publishes content-identical data is deduplicated by `contentHash` (Phase 2). A device that publishes semantically different data is always accepted (Phase 3) because the reconciliation barrier guarantees it has imported upstream changes. Timestamp ordering is only used as a tiebreaker for pre-migration payloads without `contentHash`.

**Schema migration** (updated from Section 7.0.4):

| Field | Live Schema | New Schema | Migration |
|---|---|---|---|
| `projectionVersion` | `Int` | `Int` (unchanged) | No migration needed |
| `activeProjectionVersion` | `Int` | `Int` (unchanged) | No migration needed |
| `projectionServerTimestamp` | (does not exist) | `Date?` | Defaults to `nil` for existing records. Invitee ordering treats `nil` as "unknown — accept any incoming projection with a non-nil timestamp" |
| `contentHash` | (does not exist) | `String?` | Defaults to `nil`; `nil` disables content dedup (always accept). Non-nil for all new publishes |
| `rateSnapshotTimestamp` | (does not exist) | `Date` | Defaults to `projectionPublishedAt` (unchanged from R3) |

**Rollback safety**: since `projectionVersion` (Int) is unchanged, rolling back the freshness pipeline leaves the atomic publish contract intact. The new `projectionServerTimestamp` and `contentHash` fields are additive — older clients ignore them, newer clients treat `nil` as "accept any."

**Test coverage**:

1. atomic publish topology works correctly with `Int` version increments,
2. invitee three-phase ordering: (1) Int topology check, (2) `contentHash` match → no-op, (3) `contentHash` differs → accept unconditionally,
3. pre-migration fallback: `contentHash` nil → fall back to `projectionServerTimestamp` comparison,
4. mixed-schema cache (old records without `contentHash` or `projectionServerTimestamp`) gracefully falls back,
5. rollback to pre-freshness code does not break publish or fetch,
6. lagging device with import fence timeout does not publish.

### 6.9 Offline Mutation Queue and Durable Dirty-State Persistence

When the owner device is offline:

1. mutations complete locally in the CloudKit-backed SwiftData store (CloudKit handles deferred sync),
2. the republish coordinator detects that the publish failed due to connectivity,
3. the coordinator marks the projection as dirty-pending,
4. when connectivity returns and CloudKit syncs the local mutations, the coordinator fires a trailing republish,
5. the invitee sees the update after both CloudKit sync and projection publish complete.

**Durable dirty-state persistence**:

The coordinator's dirty-pending state must survive app termination, kill, and LRU cache eviction. Without persistence, a kill/relaunch or namespace cache eviction can strand a share in stale state until some unrelated future action triggers a new dirty event.

1. dirty-pending state per namespace is persisted to `UserDefaults` (lightweight) or the app's local store — not in-memory only,
2. the persisted state includes: `namespaceID`, `isDirty: Bool`, `dirtyReason: FamilyShareProjectionDirtyReason`, `dirtySince: Date`,
3. on app launch, the coordinator checks for persisted dirty namespaces and enqueues trailing republishes after the freshness pipeline initializes and the reconciliation barrier is satisfied,
4. on `FamilyShareNamespaceExecutionHub` namespace eviction (LRU), the dirty flag is persisted before the actor is deallocated — re-hydration on next access re-reads the persisted flag and re-enqueues if needed,
5. successful publish clears the persisted dirty flag for that namespace,
6. rollback (Section 10.2) clears all persisted dirty flags to prevent orphaned retry loops.

**Recovery sequence after kill/relaunch**:

```
App launch
    |
    v
1. FamilyShareRollout.isEnabled()? — if no, skip
    |
    v
2. Read persisted dirty flags from store
    |
    v
3. For each dirty namespace:
    a. Satisfy reconciliation barrier (import fence)
    b. Rebuild projection via GoalProgressCalculator
    c. Publish via coordinator (debounce applies)
    d. Clear persisted dirty flag on success
```

This ensures that no share remains silently stale after an app crash, low-memory termination, or namespace eviction.

## 7) Architecture Changes

### 7.0 Infrastructure Prerequisites

Before the freshness pipeline can be built, three shared services require modifications:

#### 7.0.1 ExchangeRateService Changes

`ExchangeRateService` currently has no notification mechanism and no externally callable refresh trigger. Two changes are required:

**Notification** — add:

1. `Notification.Name.exchangeRatesDidRefresh` posted after every successful rate fetch batch completes,
2. the notification carries `userInfo` with:
   - `refreshedPairs: Set<CurrencyPair>` — which pairs were refreshed,
   - `rateSnapshotTimestamp: Date` — timestamp of the rate snapshot,
3. the notification fires per-batch (not per-pair) to avoid N notifications for N currency lookups,
4. this is a modification to a shared service used across the entire app — coordinate to avoid unintended side effects.

**Refresh API** — add `refreshRatesIfStale()` to `ExchangeRateServiceProtocol`:

```swift
protocol ExchangeRateServiceProtocol {
    // ... existing API ...

    /// Triggers a rate fetch if the cache has expired (TTL elapsed).
    /// No-op if rates are still fresh. Posts `exchangeRatesDidRefresh`
    /// on successful fetch. Used by `FamilyShareForegroundRateRefreshDriver`
    /// to proactively keep rates current during foreground sessions.
    func refreshRatesIfStale() async
}
```

Rules:
1. `refreshRatesIfStale()` checks the cache TTL (5 minutes) — if rates are still fresh, it returns immediately without a network call,
2. if the cache has expired, it performs a rate fetch using the same logic as the existing on-demand path,
3. on success, it posts `exchangeRatesDidRefresh` (same as any other rate fetch),
4. this method is the entry point used by `FamilyShareForegroundRateRefreshDriver` (Section 5.5) to actively drive rate freshness during long foreground sessions,
5. the method must be testable via the existing `FamilyShareRateRefreshSource` seam (Section 7.1.1).

#### 7.0.2 PersistenceMutationServices Notification Normalization

The current notification surface is inconsistent:

| Service | Current Notifications | Gap |
|---|---|---|
| `GoalMutationService` | None | No notifications after create, save, archive, restore |
| `AssetMutationService` | Notifications from view layer only | No service-layer notifications |
| `TransactionMutationService` | `.goalProgressRefreshed`, `.monthlyPlanningAssetUpdated` | Adequate |
| `AllocationService` | `.monthlyPlanningAssetUpdated` | Missing family-share-specific event |

Normalize so that every mutation type that affects shared semantics posts a consistent `Notification.Name.sharedGoalDataDidChange` from the service layer (not the view). This notification carries `affectedGoalIDs` in `userInfo`.

#### 7.0.3 Pure Domain Calculator Extraction

`GoalCalculationService` is currently `@MainActor` and constructs presentation-layer view models. It is not safe for background republish or rate-drift evaluation.

Extract a pure, non-UI calculation service:

1. introduce `GoalProgressCalculator` in the domain/service layer,
2. `GoalProgressCalculator` must be:
   - not `@MainActor`,
   - not dependent on any view model types,
   - deterministic and unit-testable,
   - callable from the republish coordinator's actor context,
3. `GoalProgressCalculator` accepts sendable value-type inputs only:

```swift
struct GoalProgressInput: Sendable {
    let goalID: UUID
    let currency: String
    let targetAmount: Decimal
    let allocations: [AllocationInput]  // asset currency, allocated amount
}

struct AllocationInput: Sendable {
    let assetCurrency: String
    let allocatedAmount: Decimal
}

struct RateSnapshot: Sendable {
    let rates: [CurrencyPair: Decimal]  // from -> to = rate
    let timestamp: Date
}
```

4. the coordinator maps SwiftData managed objects into these snapshots before calling the calculator — no `@Model` types cross the boundary,
5. `GoalProgressCalculator` computes: `currentAmount` (allocation-aware, currency-converting using `RateSnapshot`), `progressRatio`, `forecastState`,
6. `GoalProgressCalculator` must compile without importing SwiftData or any view-model types,
7. `GoalCalculationService` becomes a thin presentation wrapper that calls `GoalProgressCalculator` internally if needed by views,
8. the republish coordinator and rate-drift evaluator depend only on `GoalProgressCalculator`, never on `GoalCalculationService`.

#### 7.0.4 Projection Cache Schema Migration

The proposal introduces `rateSnapshotTimestamp`, `projectionServerTimestamp`, `contentHash`, and tiered freshness states. Existing cached projections do not have these fields. The existing `projectionVersion` (Int) and `activeProjectionVersion` (Int) are unchanged.

Migration rules:

1. cached projections missing `rateSnapshotTimestamp` must default to `projectionPublishedAt` as the rate timestamp (conservative: treats rates as same age as publish),
2. `projectionVersion` (Int) and `activeProjectionVersion` (Int) are unchanged — no migration needed for the atomic publish topology,
3. cached projections missing `projectionServerTimestamp` (Date) must default to `nil` — invitee ordering treats `nil` as "accept any incoming projection with a non-nil timestamp,"
4. cached projections missing `contentHash` must default to `nil` — content dedup is disabled (always accept),
5. missing freshness metadata must resolve to `recentlyStale` (not `active`) — absence of metadata never produces a false healthy state,
6. the cache migration runs once at app launch when the freshness pipeline is first enabled,
7. upgrade tests must prove version monotonicity and state preservation across schema transitions,
8. rollback safety: removing the freshness pipeline code leaves `projectionVersion` (Int) intact; additive fields (`projectionServerTimestamp`, `contentHash`, `rateSnapshotTimestamp`) are ignored by older code.

**Schema migration matrix**:

| Field | Payload | Cache | CloudKit Record | Migration |
|---|---|---|---|---|
| `projectionVersion` | `Int` (existing) | `Int` (existing) | Root record `Int` (existing) | None |
| `activeProjectionVersion` | `Int` (existing) | `Int` (existing) | Root record `Int` (existing) | None |
| `projectionPublishedAt` | `Date` (existing) | `Date` (existing) | Root record (existing) | None |
| `projectionServerTimestamp` | `Date` (new) | `Date?` (new) | Not stored — derived from `CKRecord.modificationDate` post-publish | Default `nil` for existing |
| `contentHash` | `String` (new) | `String?` (new) | Root record `String` (new, optional) | Default `nil` for existing |
| `rateSnapshotTimestamp` | `Date` (new) | `Date?` (new) | Root record `Date` (new, optional) | Default to `projectionPublishedAt` |

### 7.1 New Components

Introduce the following concepts:

1. `FamilyShareProjectionDirtyReason` — enum: `.goalMutation(goalIDs)`, `.assetMutation(goalIDs)`, `.transactionMutation(goalIDs)`, `.rateDrift(goalIDs)`, `.importOrRepair`, `.manualRefresh`, `.participantChange`
2. `FamilyShareProjectionAutoRepublishCoordinator` — debounced publisher with dirty queue and backoff (per-namespace instance, see Section 6.1.1)
3. `FamilyShareProjectionMutationObserver` — hooks into `PersistenceMutationService` notification layer
4. `FamilyShareRateDriftEvaluator` — listens to rate refresh, evaluates materiality via `GoalProgressCalculator`, emits dirty events
5. `FamilyShareFreshnessPolicy` — defines SLA thresholds (30m/4h/24h), cooldown windows, composite staleness boundaries
6. `FamilyShareFreshnessLabel` — canonical freshness string model instantiated per namespace, shared between list and detail surfaces
7. `FamilyShareInviteeRefreshScheduler` — owns foreground/visibility/cooldown/subscription refresh
8. `FamilyShareRefreshResult` — outcome type for invitee refresh attempts
9. `FamilyShareLastPublishedSnapshot` — lightweight local cache of last published `currentAmount` per goal for materiality comparison, includes `contentHash`
10. `FamilyShareReconciliationBarrier` — pre-publish import fence that prevents stale-device publish (Section 6.8.1)
11. `FamilyShareContentHasher` — deterministic SHA-256 hasher for projection payload semantic deduplication (includes root metadata: owner display name, participant list)
12. `FamilyShareDirtyStateStore` — persisted dirty-pending flags per namespace, survives kill/relaunch/LRU eviction (Section 6.9)
13. `FamilyShareForegroundRateRefreshDriver` — active 5-minute timer that triggers `ExchangeRateService.refreshRatesIfStale()` during foreground sessions with active sharing (Section 5.5)

#### 7.1.1 Testability Seams

All time-based, scheduling, and I/O behavior must be injectable for deterministic testing. The following seam protocols are required:

```swift
/// Clock seam — replaces Date() and enables virtual time in tests
protocol FamilyShareClock: Sendable {
    func now() -> Date
}

struct SystemClock: FamilyShareClock {
    func now() -> Date { Date() }
}

/// Scheduler seam — replaces Timer/DispatchQueue for debounce and periodic checks
protocol FamilyShareScheduler: Sendable {
    func scheduleDebounce(delay: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable
    func schedulePeriodic(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> any FamilyShareCancellable
}

protocol FamilyShareCancellable: Sendable {
    func cancel()
}

/// Publish transport seam — replaces CloudKit publish for unit tests
protocol FamilySharePublishTransport: Sendable {
    func publish(payload: FamilyShareProjectionPayload, namespaceID: FamilyShareNamespaceID) async throws -> FamilySharePublishReceipt
}

struct FamilySharePublishReceipt: Sendable {
    let serverTimestamp: Date  // CKRecord.modificationDate
    let recordCount: Int
}

/// Rate refresh seam — replaces ExchangeRateService notification for unit tests
protocol FamilyShareRateRefreshSource: Sendable {
    var ratesDidRefresh: AsyncStream<RateRefreshEvent> { get }
}

struct RateRefreshEvent: Sendable {
    let refreshedPairs: Set<CurrencyPair>
    let rateSnapshotTimestamp: Date
    let rates: [CurrencyPair: Decimal]
}
```

**Injection points**:

| Component | Injected Seams | Default (Production) |
|---|---|---|
| `FamilyShareProjectionAutoRepublishCoordinator` | `FamilyShareClock`, `FamilyShareScheduler`, `FamilySharePublishTransport` | `SystemClock`, `GCDScheduler`, `CloudKitPublishTransport` |
| `FamilyShareRateDriftEvaluator` | `FamilyShareClock`, `FamilyShareRateRefreshSource` | `SystemClock`, `NotificationCenterRateRefreshSource` |
| `FamilyShareFreshnessPolicy` | `FamilyShareClock` | `SystemClock` |
| `FamilyShareInviteeRefreshScheduler` | `FamilyShareClock`, `FamilyShareScheduler` | `SystemClock`, `GCDScheduler` |

**Test benefits**:

1. debounce/coalescing tests advance virtual time instead of sleeping — tests run in milliseconds, not seconds,
2. periodic check tests control exactly when intervals fire — no flaky timing,
3. publish failure/backoff tests inject deterministic errors via `FamilySharePublishTransport`,
4. freshness tier tests set exact timestamps via `FamilyShareClock` — no dependency on wall clock,
5. rate-drift tests inject controlled rate refresh events via `FamilyShareRateRefreshSource`.

### 7.2 Publish-Trigger Inventory and Mutation Hook Boundary

Shared projection auto-republish must hook into the authoritative mutation layer, not into SwiftUI views. Every current and proposed publish trigger must route through the auto-republish coordinator's dirty-event stream. No direct calls to `FamilyShareProjectionPublishCoordinator.publish()` are permitted outside the namespace actor boundary.

#### 7.2.1 Complete Trigger Inventory

The following table maps **every** publish trigger from the live system and this proposal to one coordinator event path:

| Trigger Source | Current Behavior | Coordinator Event Path | Dirty Reason |
|---|---|---|---|
| **Goal create/edit/delete** | No notification (gap) | `sharedGoalDataDidChange` notification (Section 7.0.2) -> `FamilyShareProjectionMutationObserver` -> dirty event | `.goalMutation(goalIDs)` |
| **Asset add/edit/delete** | View-layer notification only (gap) | `sharedGoalDataDidChange` notification (Section 7.0.2) -> `FamilyShareProjectionMutationObserver` -> dirty event | `.assetMutation(goalIDs)` |
| **Transaction add/import/delete** | `.goalProgressRefreshed` / `.monthlyPlanningAssetUpdated` | `sharedGoalDataDidChange` notification -> observer -> dirty event | `.transactionMutation(goalIDs)` |
| **Allocation changes** | `.monthlyPlanningAssetUpdated` | `sharedGoalDataDidChange` notification -> observer -> dirty event | `.assetMutation(goalIDs)` |
| **Exchange rate refresh** | No notification (gap) | `exchangeRatesDidRefresh` notification (Section 7.0.1) -> `FamilyShareRateDriftEvaluator` -> dirty event (if material) | `.rateDrift(goalIDs)` |
| **Import/bridge/dedup/backfill** | No notification | `sharedGoalDataDidChange` notification -> observer -> dirty event | `.importOrRepair` |
| **Manual "Share with Family" tap** | Direct `publishProjection()` call | Bridged: emits `.manualRefresh` dirty event into coordinator | `.manualRefresh` |
| **Share lifecycle: initial accept** | Direct publish in acceptance flow | Bridged: acceptance flow emits dirty event after initial setup | `.manualRefresh` |
| **Share lifecycle: revoke/stop sharing** | Direct record deletion | **Not a publish trigger** — revocation deletes records atomically; no projection rebuild needed | N/A (delete path) |
| **Participant added/removed** | Participant metadata update on root record | Bridged: participant change emits dirty event (updates root record participant metrics) | `.participantChange` |
| **Owner display-name change** | `syncRootParticipantMetrics()` direct call | Bridged: display-name change notification -> dirty event | `.participantChange` |
| **Periodic foreground check (15 min)** | Does not exist (new) | Timer fires -> rate refresh -> `FamilyShareRateDriftEvaluator` -> dirty event (if material) | `.rateDrift(goalIDs)` |
| **Legacy `refreshAllState()` (read-only)** | Fetches projections, updates UI | **Not a publish trigger** — read-only refresh continues to operate outside the publish coordinator | N/A (read path) |
| **Legacy manual refresh from `FamilyAccessView`** | May call `publishProjection()` directly | **Deprecated**: replaced with `.manualRefresh` dirty event into coordinator | `.manualRefresh` |

#### 7.2.2 Deprecated Direct Callers

The following direct calls to `FamilyShareProjectionPublishCoordinator.publish()` or `FamilyShareCloudKitStore.publishProjection()` must be replaced with dirty-event emissions:

1. `FamilyAccessView` manual "Share with Family" button — replace with `.manualRefresh` dirty event,
2. `FamilySharingComponents` inline refresh actions — replace with `.manualRefresh` dirty event,
3. `syncRootParticipantMetrics()` owner-name updates — replace with `.participantChange` dirty event,
4. any acceptance-flow publish after initial share setup — replace with `.manualRefresh` dirty event.

After migration, `FamilyShareProjectionPublishCoordinator.publish()` is callable **only** from within `FamilyShareNamespaceActor` / `FamilyShareProjectionAutoRepublishCoordinator`. All other callers are compile-time errors (enforced by making `publish()` `internal` to the namespace actor module or by protocol restriction).

#### 7.2.3 New Dirty Reason: `.participantChange`

Add to `FamilyShareProjectionDirtyReason`:

```swift
case participantChange  // owner display-name update, participant added/removed
```

This covers share lifecycle and identity updates that affect the root record but not goal data. Participant changes use the same debounce/coalescing pipeline as other dirty events.

View-level button taps are not sufficient because background or non-UI mutations would bypass them.

### 7.3 Canonical Projection Rebuild

Automatic republish must rebuild the entire canonical shared projection from current owner truth, not patch records field-by-field from the mutation source.

**`currentAmount` computation path**: The canonical rebuild must compute `currentAmount` via `GoalProgressCalculator` (pure domain calculator, allocation-aware, currency-converting — see Section 7.0.3), not via `goal.manualTotal` or the presentation-bound `GoalCalculationService`. This ensures that:

1. allocated asset values are properly converted to goal currency using fresh exchange rates,
2. multi-asset goals with different denominations are summed correctly,
3. the rate-drift evaluator and the published projection use the same computation path,
4. projection rebuild can run on the coordinator's actor without `@MainActor` requirement.

> **Implementation note**: The current `makeProjectionPayload()` in `FamilyShareServices.swift` (line 1676) uses `goal.manualTotal`. This must be replaced with `GoalProgressCalculator.calculateProgress(for:)` or equivalent.

Additional reasons for full rebuild:

1. avoids drift between owner truth and shared projection,
2. ensures `currentAmount` always uses the latest rates,
3. keeps shared-goals redesign semantics intact,
4. makes publish idempotent,
5. simplifies recovery after partial failures.

### 7.4 Invitee Refresh Scheduler

Invitee refresh must be scheduled by one policy component, not by scattered view hooks.

The scheduler owns:

1. foreground-triggered refresh,
2. first-visibility refresh,
3. cooldown suppression (30-second minimum between refreshes),
4. stale threshold evaluation (using tiered thresholds from Section 6.4),
5. push-notification-triggered refresh (v2),
6. telemetry for refresh outcomes and stale exposure.

## 8) UX Contract

### 8.1 Owner UX

The owner should not need to manually re-share after normal edits or rate changes.

Owner-side UI rules:

1. no new blocking confirmation for normal automatic republish,
2. optional lightweight status only when automatic republish fails repeatedly,
3. `Family Access` may show:
   - `Up to date` — last publish succeeded and no pending dirty state,
   - `Syncing shared goals` — publish in progress or debounce pending,
   - `Needs attention` — repeated publish failures.
4. the owner is never asked to intervene for normal rate-drift republishes.

### 8.2 Invitee UX

The invitee should not need to guess whether the numbers are current.

**List view** — one primary freshness message per namespace section, one optional recovery action:

1. `Shared with You` silently refreshes all namespaces on foreground and first visibility,
2. each namespace section header shows exactly one primary freshness line derived from that namespace's composite effective age (Section 6.4). The **grammar splits by governing dependency** — publish age and rate age produce different copy to avoid misleading the user about what is stale:

   **When publish age governs** (publish age >= rate age):
   - `active`: "Shared 5 min ago" (normal tone),
   - `recentlyStale`: "Shared 2 hours ago" (informational),
   - `stale`: "Last shared 8 hours ago — values may have changed" (warning),
   - `materiallyOutdated`: "Last shared 3 days ago — values may have changed significantly" (prominent warning),

   **When rate age governs** (rate age > publish age, and rate age escalates the tier):
   - `recentlyStale`: "Rates are 2 hours old" (rate staleness leads; share time moves to detail provenance),
   - `stale`: "Rates are 8 hours old — values may have changed" (rate staleness primary),
   - `materiallyOutdated`: "Rates are 3 days old — values may have changed significantly" (rate staleness primary),

   In all rate-governed tiers, rate age **always leads**. Share time ("Shared 5 min ago") is never the opening phrase — it is demoted to secondary provenance visible in the detail-view Freshness card only. This ensures a user can tell in one glance that stale rates, not share recency, are the governing problem.

3. the primary message must always reflect the **governing dependency** — no rate-governed stale header begins with "Shared X ago"; rate age always leads when it governs the composite tier,
4. when rate age governs, the actual share time is preserved as secondary provenance in the detail-view Freshness card — it is never shown in the list header (to avoid foregrounding apparent freshness when money values are rate-stale),
5. warning copy **replaces** the normal header — it does not stack on top of it,
6. if refresh succeeds, the section updates in place,
7. if refresh fails and safe rendering cannot continue, show `temporarilyUnavailable`,
8. manual action remains available:
   - `Retry Refresh` for stale/materiallyOutdated,
   - `Retry` for unavailable,
9. stale-cause substates (Section 6.4.3) overlay the primary message when applicable:
   - `checking`: "Checking for updates..." replaces recovery action with spinner,
   - `refreshFailed`: "Couldn't refresh — showing last shared update" with "Try Again" action,
   - `checkedNoNewData`: primary age message preserved + secondary note "Checked just now — no newer update yet" appended below; no retry action (retrying is not meaningful),
   - `cooldown`: recovery action is disabled for 30 seconds after last attempt.

**Detail view** — same primary message plus expanded provenance in a dedicated card:

1. the primary financial summary (`Current` / `Target` / progress bar) remains the **first-scan dominant** element at the top of the detail view,
2. a dedicated **"Freshness" card** is placed below the primary financial summary, structured as:

   ```
   ┌─────────────────────────────────────────────┐
   │  Freshness                                   │
   │  ─────────────────────────────────────────── │
   │  [icon] Shared 5 min ago                     │  ← primary freshness (from FamilyShareFreshnessLabel)
   │                                              │
   │  Last shared    5 min ago (Mar 22, 2:14 PM)  │  ← provenance row 1: relative + exact
   │  Rates as of    5 min ago (Mar 22, 2:14 PM)  │  ← provenance row 2: relative + exact
   │                                              │
   │  [i] Why is this stale?                      │  ← info affordance (stale+ tiers only)
   └─────────────────────────────────────────────┘
   ```

3. the Freshness card must **never** push `Current` / `Target` below the fold at any Dynamic Type size,
4. provenance disclosure follows the canonical rule in Section 6.6: at default through XXXL, exact timestamps are auto-expanded inline; at AX1+, exact timestamps are behind a disclosure chevron (collapsed by default, one tap to expand inline). Provenance rows (relative time) are always visible,
5. relative time is always the first read in each provenance row; exact timestamps are in secondary text style,
6. when both timestamps are identical (rate age == publish age), the "Rates as of" row is collapsed with "(same as shared update)" note,
7. info affordance with tier explanation is shown only when the state is `stale` or worse.

**Compact-layout contract for namespace section header**:

The namespace section header must render cleanly at iPhone 15 width at the largest supported Dynamic Type size. The following collapse order governs what is shown when space is constrained:

| Priority | Element | Behavior Under Space Pressure |
|---|---|---|
| 1 (highest) | Namespace title (owner name / section label) | Always visible; truncates with ellipsis only as last resort |
| 2 | Primary freshness message | Always visible on a dedicated line below the title; wraps to two lines if needed |
| 3 | Recovery action ("Retry Refresh" / "Try Again") | Always tappable; placed trailing on the freshness line or below it; never overlaps row content |
| 4 (lowest) | Secondary share-time provenance (when rate age governs) | Collapses (hidden) when the header would exceed two lines; moved to detail view |

**Concrete header composition matrix**:

| Freshness Tier | Governing Dep. | Line 1 | Line 2 | Action | Format |
|---|---|---|---|---|---|
| `active` | (either) | "Alice's Goals" | "Shared 5 min ago" | (none) | Inline text, `freshness.normal` |
| `recentlyStale` | publish | "Alice's Goals" | "Shared 2h ago" | (none) | `clock` icon, `freshness.informational` |
| `recentlyStale` | rate | "Alice's Goals" | "Rates are 2h old" | (none) | `clock` icon, `freshness.informational` |
| `stale` | publish | "Alice's Goals" | "Last shared 8h ago — values may have changed" | "Retry Refresh" trailing | `exclamationmark.triangle`, `freshness.warning` |
| `stale` | rate | "Alice's Goals" | "Rates are 8h old — values may have changed" | "Retry Refresh" trailing | `exclamationmark.triangle`, `freshness.warning` |
| `materiallyOutdated` | publish | "Alice's Goals" | "Last shared 3d ago — values may have changed significantly" | "Retry Refresh" trailing | `exclamationmark.triangle.fill`, `freshness.critical` |
| `materiallyOutdated` | rate | "Alice's Goals" | "Rates are 3d old — values may have changed significantly" | "Retry Refresh" trailing | `exclamationmark.triangle.fill`, `freshness.critical` |
| `temporarilyUnavailable` | N/A | "Alice's Goals" | "Shared goals temporarily unavailable" | "Retry" trailing | `wifi.slash`, `status.error` |
| `removedOrNoLongerShared` | N/A | "Alice's Goals" | "This shared goal set is no longer available" | "Remove" trailing | `person.crop.circle.badge.minus`, `status.inactive` |
| `checking` (substate) | N/A | "Alice's Goals" | "Checking for updates..." | (spinner) | `freshness.informational` |
| `checkedNoNewData` (substate) | N/A | "Alice's Goals" | "{primary age message}\nChecked just now — no newer update yet" | (none) | `freshness.informational` |
| `refreshFailed` (substate) | N/A | "Alice's Goals" | "Couldn't refresh — showing last shared update" | "Try Again" trailing | `freshness.warning` |
| `cooldown` (substate) | N/A | "Alice's Goals" | "{primary age message}" | "Try Again" (disabled/grayed) | Same as underlying tier |
| `idle` (substate) | N/A | "Alice's Goals" | "{primary age message}" | "Retry Refresh" (if stale+) | Same as underlying tier |

Notes:
- `active` and `recentlyStale` are inline text-first states — no card or banner escalation,
- `stale` and `materiallyOutdated` use warning/critical tokens but remain inline text — no card,
- `temporarilyUnavailable` and `removedOrNoLongerShared` are the only states that may use card/banner escalation if needed for visual weight,
- the header never renders both an action and secondary share-time provenance on the same line; if both are needed, the action takes trailing and provenance moves to detail,
- "Alice's Goals" is a placeholder — real owner names may be long; the title truncates with ellipsis at 1 line.

**Locale-aware timestamp formatting**:

Exact timestamps in the Freshness card must respect the device locale and layout direction:

1. use `Date.FormatStyle` (or `DateFormatter` with `.dateStyle = .medium`, `.timeStyle = .short`) — never hardcoded `"Mar 22, 2:14 PM"` format strings,
2. relative times use `RelativeDateTimeFormatter` with `.abbreviated` style for list headers and `.full` style for detail provenance,
3. **RTL layouts**: provenance rows reverse label/value order; disclosure chevrons flip to `chevron.left`,
4. **Long-format locales** (e.g., German, Japanese): if a provenance row exceeds the card width, the exact timestamp wraps to a second line below the relative time — it is never truncated,
5. the Freshness card width is flexible (matches the detail-view content width); it does not have a fixed pixel width that can clip long date strings.

**Multi-namespace compactness policy**:

When two or more namespaces are visible in the shared-goals list, or when Dynamic Type is AX1 or larger, the following density rules apply to prevent status chrome from dominating the first viewport:

1. secondary provenance (share time when rate governs) is suppressed from all namespace headers — it is available in the detail-view Freshness card only,
2. each namespace header is capped at two lines: title (line 1) + primary freshness message or recovery action (line 2),
3. `active` and `recentlyStale` headers suppress the freshness icon to save horizontal space,
4. on iPhone 15 with three or more namespaces, the first goal row of the first namespace must remain visible without scrolling,
5. these density rules override the single-namespace layout rules above.

When only one namespace is visible and Dynamic Type is below AX1, the full header layout (up to three lines) applies.

Rules:

1. primary freshness copy must always win — secondary share-time provenance collapses before the primary message truncates,
2. recovery action and secondary provenance are mutually exclusive on the same line: if both would render, the recovery action takes the trailing position and secondary provenance collapses to the detail view,
3. the recovery action must maintain a minimum 44x44pt tap target regardless of Dynamic Type size,
4. stale/unavailable recovery actions must not compete with the first goal row's tap target — a minimum 8pt vertical gap separates the header from the first row,
5. the section header never exceeds three lines total (title + freshness + optional recovery) at the largest Dynamic Type size.

**Cross-surface rules**:

1. list and detail both use `FamilyShareFreshnessLabel` for the primary message — no divergence in timestamp grammar or trust semantics,
2. staleness copy must never blame or reference the owner's behavior — focus on data age, not people,
3. at iPhone 15 width and the largest supported Dynamic Type size, the section renders without overlap or truncation, exactly one primary freshness message is visible, and primary shared-goal rows remain immediately scannable.

### 8.3 Freshness Visual Contract

Each freshness tier maps to named semantic tokens:

| Internal State | Token | Icon | Contrast | VoiceOver |
|---|---|---|---|---|
| `active` | `freshness.normal` | none | N/A | "Shared {time} ago" announced only on explicit refresh, not on silent background update |
| `recentlyStale` | `freshness.informational` | `clock` (SF Symbol) | >= 4.5:1 (AA) | "Shared {time} ago" (publish-governed) or "Rates are {rate-age} old" (rate-governed) |
| `stale` | `freshness.warning` | `exclamationmark.triangle` | >= 4.5:1 (AA) | "Warning: last shared {time} ago, values may have changed" (publish-governed) or "Warning: rates are {rate-age} old, values may have changed" (rate-governed) |
| `materiallyOutdated` | `freshness.critical` | `exclamationmark.triangle.fill` | >= 4.5:1 (AA) | "Warning: last shared {time} ago, values may have changed significantly" (publish-governed) or "Warning: rates are {rate-age} old, values may have changed significantly" (rate-governed) |
| `temporarilyUnavailable` | `status.error` (app-wide) | `wifi.slash` | >= 4.5:1 (AA) | "Shared goals temporarily unavailable. Activate Retry to check again." |
| `removedOrNoLongerShared` | `status.inactive` (app-wide) | `person.crop.circle.badge.minus` | >= 4.5:1 (AA) | "This shared goal set is no longer available." |

**VoiceOver copy conventions**: VoiceOver strings intentionally differ from visual copy: they use a "Warning:" prefix for `stale`/`materiallyOutdated` tiers (visual copy does not), use commas instead of em-dashes for natural speech flow, and use "Activate" instead of "Tap" for action prompts.

**Accessibility rules**:

1. silent background refreshes must not steal VoiceOver focus or trigger double-announcement,
2. status updates use `accessibilityLiveRegion(.polite)` — announced only when the user is not actively interacting,
3. recovery actions (`Retry Refresh`, `Retry`) are accessible buttons with explicit labels,
4. all freshness tokens pass WCAG AA contrast in both light and dark mode.

### 8.4 Motion and Transition Contract

Freshness state changes and value refreshes must animate predictably to maintain financial trust:

**Row stability rules**:

1. silent refresh must preserve row order and scroll position — no list re-sort or jump,
2. value changes (amounts, progress) use a subtle content transition (`.contentTransition(.numericText())` or equivalent) — not a full row replacement,
3. freshness-label changes use `.contentTransition(.opacity)` to crossfade between tiers — no slide, bounce, or scale animation,
4. no success-banner choreography on silent refresh — the freshness label updates in place without celebratory motion.

**State transition animations**:

| Transition | Animation | Duration |
|---|---|---|
| `active` to `recentlyStale` | Crossfade freshness label | 0.3s |
| `recentlyStale` to `stale` | Crossfade freshness label + icon appearance | 0.3s |
| `stale` to `active` (after successful refresh) | Crossfade freshness label + icon removal | 0.3s |
| `temporarilyUnavailable` to `active` (recovery) | Crossfade full section content | 0.35s |
| `active` to `temporarilyUnavailable` | Crossfade to unavailable state | 0.35s |
| Value amount change | Numeric content transition | 0.25s |

**Reduce Motion rules**:

1. when `UIAccessibility.isReduceMotionEnabled` is true, all nonessential animation is removed — state changes apply immediately without transition,
2. content transitions for values and labels are replaced with instant swaps,
3. the `checking` spinner is replaced with a static "Checking..." text label,
4. essential semantics (tier change, value update) are still communicated via VoiceOver announcements regardless of motion preference.

**VoiceOver interaction rules**:

1. silent background refreshes must not steal VoiceOver focus or trigger announcements — updates apply silently,
2. user-initiated refresh ("Retry Refresh" tap) announces the outcome: "Updated" on success or "Couldn't refresh" on failure via `UIAccessibility.post(notification: .announcement)`,
3. tier escalation (e.g., `active` to `stale`) is announced via `accessibilityLiveRegion(.polite)` — only when the user is not actively interacting with a different element,
4. tier de-escalation (e.g., `stale` to `active`) is not announced unless the user explicitly triggered a refresh.

## 9) Telemetry and Diagnostics

Add and/or formalize events:

1. `family_share_auto_publish_requested` — with `reason` property (mutation, rateDrift, importRepair, manual)
2. `family_share_auto_publish_coalesced` — burst collapsed
3. `family_share_auto_publish_succeeded` — with `goalCount`, `publishDurationMs`
4. `family_share_auto_publish_failed` — with `errorCode` (including `requestRateLimited`)
5. `family_share_rate_drift_evaluated` — with `materialGoalCount` and `maxDeltaPct`
6. `family_share_rate_drift_below_threshold` — evaluated but no publish needed
7. `family_share_invitee_foreground_refresh_requested`
8. `family_share_invitee_push_refresh_requested` (v2)
9. `family_share_invitee_refresh_succeeded` — with `projectionAgeSeconds` (age of fetched projection at refresh time)
10. `family_share_invitee_refresh_failed`
11. `family_share_invitee_stale_viewed` — with `staleDurationSeconds` and `staleTier` (recentlyStale/stale/materiallyOutdated)
12. `family_share_publish_backoff_entered`
13. `family_share_publish_recovered`
14. `family_share_offline_publish_queued`
15. `family_share_offline_publish_drained`
16. `family_share_rate_snapshot_age_at_publish` — `rateSnapshotAgeSeconds` at the time of projection publish (measures data quality, not just plumbing health)
17. `family_share_clock_skew_detected` — with `skewSeconds` (magnitude of future timestamp beyond 60s tolerance) and `timestampSource` (projectionPublishedAt or rateSnapshotTimestamp)
18. `family_share_freshness_rollback` — emitted once per rollout disable transition, with `discardedDirtyEventCount` and `activeTimerCount` at teardown time
19. `family_share_invitee_refresh_substate_changed` — with `fromSubstate`, `toSubstate` (idle/checking/refreshFailed/checkedNoNewData/cooldown), `namespaceID` (hashed)
20. `family_share_publish_suppressed_stale_local` — reconciliation barrier suppressed publish due to pending imports, with `pendingImportAge`, `namespaceID` (hashed)
21. `family_share_reconciliation_barrier_waited` — with `waitDurationMs`, `importCompleted: Bool`
22. `family_share_content_hash_dedup` — invitee discarded incoming projection because `contentHash` matched cached
23. `family_share_invitee_checked_no_new_data` — manual refresh succeeded but no newer projection exists, with `projectionAge`
24. `family_share_namespace_revoked_terminal` — namespace entered terminal removed/revoked state, with `cachedDataPurged: Bool`

Diagnostics payload must stay redacted and must not log:

1. goal names,
2. raw owner display names,
3. emails,
4. raw record names,
5. financial amounts.

Rate drift telemetry may log `maxDeltaPct` (percentage change) and `rateSnapshotAgeSeconds` since neither is a financial amount.

## 10) Rollout and Rollback Boundary Contract

The freshness pipeline introduces new observers, timers, periodic checks, push handlers, and offline queue behavior. All of these must be gated by `FamilyShareRollout.isEnabled()` at well-defined boundaries, and rollback must produce a quiescent state with no orphaned side effects.

### 10.1 Rollout Check Points

`FamilyShareRollout.isEnabled()` must be checked at the following ingress points — if disabled, the operation is a no-op:

| Boundary | Component | Behavior When Disabled |
|---|---|---|
| Mutation observer subscription | `FamilyShareProjectionMutationObserver` | Observer is not registered; mutation notifications are ignored |
| Rate-drift evaluator subscription | `FamilyShareRateDriftEvaluator` | Rate refresh notifications are ignored; no materiality evaluation |
| Auto-republish coordinator activation | `FamilyShareProjectionAutoRepublishCoordinator` | Coordinator is not started; dirty events are dropped |
| Debounce timer creation | `FamilyShareProjectionAutoRepublishCoordinator` | No timers created |
| Periodic foreground check | `FamilyShareProjectionAutoRepublishCoordinator` | Periodic timer is not scheduled |
| Publish execution | `FamilyShareProjectionPublishCoordinator` | Publish is rejected (existing gate) |
| Push notification handler | `FamilyShareInviteeRefreshScheduler` | Push is acknowledged but refresh is skipped |
| Offline queue drain | `FamilyShareProjectionAutoRepublishCoordinator` | Queued dirty events are not drained |
| Invitee refresh scheduler activation | `FamilyShareInviteeRefreshScheduler` | Foreground and visibility refresh triggers are not registered |

### 10.2 Rollback Teardown Contract

When `FamilyShareRollout.isEnabled()` transitions from `true` to `false` (runtime disable or remote config kill-switch):

1. **Timers**: all debounce timers and periodic check timers owned by the auto-republish coordinator are cancelled immediately,
2. **Observers**: mutation observer and rate-drift evaluator notification subscriptions are removed,
3. **Dirty queue**: pending dirty events are discarded (not persisted across rollback),
4. **In-flight publish**: if a publish is currently in flight, it is allowed to complete (cancellation mid-write risks CloudKit inconsistency), but no subsequent publishes are permitted,
5. **Push subscriptions**: invitee push-triggered refresh is disabled; push notifications are acknowledged but not acted upon,
6. **Offline queue**: pending offline dirty events are discarded,
7. **UI state**: the invitee surface falls back to the last cached projection with its existing freshness state — no UI churn or flash of error state,
8. **Telemetry**: a `family_share_freshness_rollback` event is emitted with reason and the count of discarded dirty events.

### 10.3 Rollback Safety Verification

A flag-off test must prove:

1. no `FamilyShareProjectionMutationObserver` subscription is active,
2. no debounce or periodic timer is running,
3. no push-triggered refresh fires,
4. no publish attempt is made,
5. no rate-drift evaluation runs,
6. cached invitee UI remains stable (no flash, no error state, no stale-label regression),
7. `family_share_freshness_rollback` telemetry is emitted exactly once per disable transition.

## 11) Delivery Plan


### Phase 0: Infrastructure Prerequisites

1. add `Notification.Name.exchangeRatesDidRefresh` and `refreshRatesIfStale()` to `ExchangeRateService` and `ExchangeRateServiceProtocol` (Section 7.0.1),
2. normalize `PersistenceMutationServices` notification surface so all mutation types post consistent `sharedGoalDataDidChange` from the service layer (Section 7.0.2),
3. extract `GoalProgressCalculator` as a pure, non-`@MainActor` domain calculator (Section 7.0.3),
4. define projection cache schema migration for `rateSnapshotTimestamp`, `projectionServerTimestamp`, `contentHash`, and freshness metadata (Section 7.0.4),
5. bridge or retire legacy view-triggered refresh paths per the publish-trigger inventory (Section 7.2.1, 7.2.2),
6. implement testability seam protocols (`FamilyShareClock`, `FamilyShareScheduler`, `FamilySharePublishTransport`, `FamilyShareRateRefreshSource`) (Section 7.1.1),
7. implement rollout check points at all ingress boundaries (Section 10.1),
8. implement pre-publish reconciliation barrier with CloudKit import fence (Section 6.8.1),
9. implement separated version contract: retain `projectionVersion` (Int) for atomic topology, add `contentHash` as authoritative post-migration ordering signal, add `projectionServerTimestamp` (Date) as pre-migration fallback (Section 6.8.2),
10. complete publish-trigger inventory and deprecate all direct publish callers outside namespace actor boundary (Section 7.2.2).

Release gate:

1. `ExchangeRateService` posts notification after every successful rate batch and exposes `refreshRatesIfStale()` on the protocol,
2. `GoalMutationService`, `AssetMutationService`, `AllocationService` all post `sharedGoalDataDidChange` from the service layer,
3. `GoalProgressCalculator` is callable from non-`@MainActor` contexts and produces identical results to the existing `GoalCalculationService` for all goals,
4. cached projections without freshness metadata resolve to `recentlyStale` (not `active`),
5. no legacy refresh path can trigger a publish outside the coordinator — all triggers in Section 7.2.1 inventory are routed through coordinator,
6. all time-based tests run against virtual time via injected `FamilyShareClock` and `FamilyShareScheduler`,
7. flag-off scenario proves no observer/timer/push activity and stable cached UI (Section 10.3),
8. pre-publish reconciliation barrier prevents stale-device publish — lagging device test proves suppression,
9. `projectionVersion` (Int) retained for atomic topology; `contentHash` is authoritative ordering signal; `projectionServerTimestamp` (Date) is pre-migration fallback only; schema migration is rollback-safe.

### Phase 1: Owner Automatic Republish + Basic Invitee Refresh

Ship owner-side auto-republish and invitee-side automatic refresh together so that every phase delivers user-visible value.

Owner side:

1. add mutation observer boundary hooking into normalized `PersistenceMutationService` notifications per trigger inventory (Section 7.2.1),
2. add per-namespace debounced republish coordinator within `FamilyShareNamespaceActor` (Section 6.1.1),
3. route all publish triggers from inventory (Section 7.2.1) through the coordinator — deprecate direct callers (Section 7.2.2),
4. integrate pre-publish reconciliation barrier (Section 6.8.1) — coordinator checks import fence before every publish,
5. switch `makeProjectionPayload()` from `goal.manualTotal` to `GoalProgressCalculator` for `currentAmount`,
6. store last-published snapshot with `contentHash` for materiality comparison and dedup,
7. add publish telemetry and failure state, including reconciliation barrier telemetry.

Invitee side:

1. add refresh scheduler with foreground and first-visibility triggers,
2. add cooldown suppression (30-second minimum),
3. implement tiered staleness thresholds (30m/4h/24h) from Section 6.4,
4. add per-namespace `FamilyShareFreshnessLabel`-driven composite freshness display in section header,
5. add dependency-aware freshness grammar from Section 8.2 (publish-governed vs rate-governed copy),
6. add stale-cause and recovery substates (`checking`, `refreshFailed`, `checkedNoNewData`, `cooldown`) from Section 6.4.3,
7. add empty-state freshness precedence from Section 6.4.2,
8. add terminal-state contract for removed/revoked namespaces from Section 6.4.1,
9. add compact-layout with concrete header composition matrix from Section 8.2,
10. add detail-view Freshness card below financial summary from Section 8.2,
11. add motion and transition contract from Section 8.4,
12. align section state transitions with refresh outcomes.

Release gate:

1. owner edits trigger automatic republish without manual re-share,
2. one mutation burst results in one published projection version,
3. repeated failures surface `Needs attention` rather than silently freezing,
4. invitee sees new data on next foreground entry after owner republish,
5. invitee section header shows per-namespace composite freshness from `FamilyShareFreshnessLabel`,
6. staleness tiers display correct copy based on composite effective age,
7. mixed-freshness namespaces show independent freshness states,
8. `checking`, `refreshFailed`, and `checkedNoNewData` substates are visually distinct from age-based staleness,
9. empty-state freshness precedence is correct (no stale/unavailable chrome when no namespaces exist),
10. revoked namespace shows terminal state with no financial data visible and dismiss affordance,
11. pre-publish reconciliation barrier prevents stale-device publish,
12. all publish triggers from inventory (Section 7.2.1) route through coordinator — no direct callers remain,
13. freshness grammar distinguishes rate-governed from publish-governed staleness — "Shared 5 min ago" never appears when rates are stale and composite tier is `stale` or worse,
14. durable dirty-state persistence survives kill/relaunch — dirty namespace resumes publish on next launch.

**Visual proof prerequisite** (required before Phase 1 UI implementation begins):

Proposed-state captures or SwiftUI previews must be produced for the following scenarios before any invitee UI work is merged:

1. namespace header: `active`, `stale` (publish-governed), `stale` (rate-governed), `materiallyOutdated`, `temporarilyUnavailable`, `removedOrNoLongerShared` — at iPhone 15 width,
2. namespace header: `stale` (rate-governed) with long owner name — at largest supported Dynamic Type size,
3. detail-view Freshness card: `active` with both provenance rows — at default Dynamic Type,
4. detail-view Freshness card: `stale` with collapsed exact timestamps (disclosure chevron) — at AX5 Dynamic Type,
5. dark mode variants of items 1-4,
6. VoiceOver reading order for namespace header and Freshness card.

These captures validate that the compact-layout contract, Freshness card placement, and provenance rules produce a viable native-looking surface. If captures reveal layout issues, the contract must be amended before implementation.

### Phase 2: Rate-Drift Republish

1. add `FamilyShareRateDriftEvaluator` listening to `ExchangeRateService.exchangeRatesDidRefresh`,
2. implement materiality threshold comparison (1% or $5, whichever is larger) against last-published snapshot,
3. route rate-drift dirty events into the same republish coordinator,
4. add owner foreground rate refresh -> materiality check -> republish pipeline,
5. add periodic foreground guard (15-minute safety net) — primary evaluation is driven by rate-refresh notifications every ~5 minutes (Section 5.5),
6. add `rateSnapshotTimestamp` to projection metadata,
7. add rate freshness indicator for invitee (Section 8.3),
8. add rate-drift telemetry events,
9. add `family_share_rate_snapshot_age_at_publish` quality metric.

Release gate:

1. exchange rate change that moves any goal's `currentAmount` past materiality threshold triggers automatic republish,
2. owner foreground entry refreshes rates and republishes if material,
3. invitee sees rate-adjusted progress without owner taking any explicit action,
4. rate-drift publishes are distinguishable in telemetry from mutation publishes,
5. p95 `rateSnapshotAgeSeconds` at publish time is under 600s (10 min).

### Phase 3: Push-Driven Invitee Refresh (v2)

1. create `CKRecordZoneSubscription` per accepted namespace zone,
2. handle silent push in `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`,
3. route push-triggered refresh through the refresh scheduler,
4. clean up subscriptions on revocation/removal,
5. add push-specific telemetry.

Release gate:

1. invitee receives updated data within seconds of owner publish (when both devices are online),
2. push-triggered refresh does not bypass cooldown or create duplicate fetches,
3. subscriptions are properly cleaned up on share lifecycle changes.

### Phase 4: Operability Hardening

1. add telemetry dashboards / release gate thresholds,
2. add support runbook for publish vs refresh vs rate-drift incidents,
3. add backoff and repeated-failure handling,
4. verify imports/bridge/dedup paths also trigger republish when they mutate shared semantics,
5. add offline mutation queue drain-on-connectivity,
6. verify multi-device owner publish is idempotent with three-phase invitee ordering check (Section 6.8.2),
7. verify rollout/rollback teardown contract (Section 10.2): flag-off produces quiescent state with no orphaned timers, observers, or push handlers,
8. verify clock-skew handling (Section 6.6.1): future-timestamp clamping, skew telemetry, anomalous-age detection.

Release gate:

1. support can distinguish owner publish failure from invitee fetch failure from rate-drift lag,
2. rollout can be monitored for publish churn and stale-rate regressions,
3. offline edits result in eventual republish when connectivity returns.

## 12) Acceptance Criteria

This proposal is complete when:

1. updating a shared goal on the owner device no longer requires manually pressing `Share with Family`,
2. updating assets or transactions that change the shared goal total triggers automatic republish,
3. exchange rate changes that materially alter any goal's `currentAmount` (>1% of target or >$5, whichever is larger) trigger automatic republish,
4. `currentAmount` in the projection is computed via `GoalProgressCalculator` (pure domain calculator, allocation-aware, currency-converting),
5. the owner opening the app triggers rate refresh and, if material, republish — without any explicit user action,
6. invitee app foreground triggers silent refresh under the freshness policy,
7. invitee receives updated goal totals and structure after owner republish within the defined SLA on healthy connectivity,
8. invitee section header shows freshness derived from `FamilyShareFreshnessLabel` using composite effective age (not raw `projectionPublishedAt`),
9. staleness is tiered: `active` (<30m), `recentlyStale` (30m-4h), `stale` (4h-24h), `materiallyOutdated` (24h+),
10. staleness copy scales with projection age and never blames the owner,
11. unavailable state is explicit when safe rendering cannot continue,
12. projection metadata includes `rateSnapshotTimestamp`,
13. publish and refresh telemetry are separated, include reason/trigger, and are redacted,
14. data quality metric `rateSnapshotAgeSeconds` is tracked at publish time,
15. mutation hooks cover non-UI paths such as import/dedup/backfill where shared semantics change,
16. `ExchangeRateService` posts `exchangeRatesDidRefresh` notification,
17. `PersistenceMutationServices` notification surface is normalized so all mutation types notify from the service layer,
18. owner and invitee no longer need to use sharing UI as a manual sync workaround,
19. rate-drift telemetry can be monitored separately from mutation-triggered telemetry,
20. invitee monotonic version check prevents regression during multi-device owner races,
21. `GoalProgressCalculator` is extracted as a pure non-`@MainActor` domain calculator separate from `GoalCalculationService`,
22. all freshness events are consumed by a single serialized coordinator — no competing view-triggered or lifecycle-triggered refresh paths bypass it,
23. freshness state is composite: governed by `max(publishAge, rateAge)` — no screen appears `active` when rates are stale,
24. list and detail surfaces use the same canonical freshness string model (`FamilyShareFreshnessLabel`),
25. each freshness tier has a named semantic token, passes WCAG AA contrast, and VoiceOver does not steal focus on silent refresh,
26. older cached projections without freshness metadata resolve to `recentlyStale` on upgrade, never to false `active`,
27. freshness is evaluated and displayed per namespace/owner section — two sections with different ages show independent freshness tiers,
28. stale-cause substates (`checking`, `refreshFailed`, `checkedNoNewData`, `cooldown`) are visually distinct from age-based staleness and provide actionable recovery feedback,
29. detail provenance shows both `projectionPublishedAt` and `rateSnapshotTimestamp` with exact local timestamps inline alongside relative times,
30. empty state (no shared namespaces) suppresses all freshness chrome — no stale/unavailable labels appear when no shared data exists,
31. compact-layout contract is satisfied: at iPhone 15 width at the largest Dynamic Type size, the section header shows title + primary freshness without overlap, secondary detail collapses before primary truncates, and recovery action maintains 44x44pt tap target,
32. freshness-tier transitions use crossfade content transitions; `Reduce Motion` removes all nonessential animation,
33. silent refresh does not steal VoiceOver focus or announce; user-initiated refresh announces outcome,
34. `FamilyShareProjectionAutoRepublishCoordinator` is a per-namespace instance within `FamilyShareNamespaceActor` — no publish bypasses the namespace actor boundary,
35. the auto-republish coordinator delegates publish execution to `FamilyShareProjectionPublishCoordinator` — no direct CloudKit writes,
36. `projectionVersion` (Int) is retained for atomic publish topology; `contentHash` is the authoritative post-migration ordering signal; `projectionServerTimestamp` (Date) is pre-migration fallback only,
37. invitee ordering uses three-phase check: (1) atomic version (Int), (2) `contentHash` dedup (match → no-op), (3) `contentHash` differs → accept unconditionally; `projectionServerTimestamp` is pre-migration fallback only (Section 6.8.2),
38. `projectionPublishedAt` is sourced from `CKRecord.modificationDate`; future timestamps within 60s tolerance are treated as zero-age; beyond 60s, age is clamped to zero with telemetry,
39. all time-based tests use injected `FamilyShareClock` and `FamilyShareScheduler` — no real sleeps,
40. rollout disable tears down all observers, timers, and push handlers; cached invitee UI remains stable; `family_share_freshness_rollback` telemetry is emitted,
41. (R4) pre-publish reconciliation barrier prevents a lagging owner device from publishing a semantically older snapshot — import fence holds publish until local state is current,
42. (R4) `contentHash` semantic deduplication prevents UI churn from identical publishes across devices,
43. (R4) freshness grammar splits by governing dependency — publish-governed copy uses "Shared X ago", rate-governed copy names rate staleness explicitly,
44. (R4) `checkedNoNewData` substate shows non-error outcome after successful refresh with no newer projection — distinct from `refreshFailed`,
45. (R4) revoked/removed namespace purges cached financial data, blocks detail navigation, and provides dismiss affordance,
46. (R4) all publish triggers from the complete inventory (Section 7.2.1) route through one coordinator — share lifecycle, participant changes, owner identity updates, and legacy paths are all covered,
47. (R4) schema migration is rollback-safe: `projectionVersion` (Int) unchanged, additive fields (`projectionServerTimestamp`, `contentHash`) are ignored by older code,
48. (R4) detail-view Freshness card is placed below primary financial summary and never pushes `Current`/`Target` below the fold at any Dynamic Type size,
49. (R7) durable dirty-state persistence: killing and relaunching the app between mutation and publish still yields exactly one eventual republish without user intervention,
50. (R7) `FamilyShareForegroundRateRefreshDriver` actively triggers rate refresh every 5 minutes during foreground sessions with active sharing — no namespace exceeds the stated TTL without a refresh attempt,
51. (R7) `FamilyShareMaterialityPolicy` correctly evaluates non-USD goals: converts $5 floor to goal currency, rounds to minor units, falls back to 1% when rate is unavailable,
52. (R7) `checkedNoNewData` substate preserves the underlying age-tier message and appends "Checked just now — no newer update yet" as secondary; no retry action is shown,
53. (R7) locale-aware timestamp formatting: long-format locales and RTL layouts render provenance without truncation or undefined overflow; `Date.FormatStyle` is used for all timestamps.

## 13) Test Plan

Required tests:

1. unit tests for debounce/coalescing:
   - many mutations in one burst produce one publish,
   - trailing dirty event produces one follow-up publish,
   - mixed mutation + rate-drift events coalesce correctly.
2. unit tests for mutation observer coverage:
   - goal edit triggers observer (after Section 7.0.2 normalization),
   - asset mutation triggers observer,
   - transaction mutation triggers observer,
   - allocation change triggers observer,
   - import/backfill path triggers observer.
3. unit tests for rate-drift evaluator:
   - rate change above materiality threshold triggers dirty event,
   - rate change below materiality threshold does not trigger dirty event,
   - materiality threshold per goal is correctly evaluated (1% of targetAmount or $5, whichever is larger),
   - multiple goals with different currencies are evaluated independently,
   - `GoalProgressCalculator` is used for `currentAmount` computation (not `manualTotal` or `GoalCalculationService`).
4. unit tests for refresh scheduler:
   - foreground refresh,
   - cooldown suppression (within 30s),
   - tiered stale threshold transitions (30m, 4h, 24h),
   - (v2) push-triggered refresh.
5. unit tests for tiered staleness UX:
   - projection age < 30m shows `active` state,
   - projection age 30m-4h shows `recentlyStale` with informational copy,
   - projection age 4h-24h shows `stale` with warning copy,
   - projection age > 24h shows `materiallyOutdated` with prominent warning.
6. integration tests for publish/fetch loop:
   - owner mutation -> publish -> invitee refresh -> updated projection,
   - rate change -> evaluate materiality via GoalProgressCalculator -> publish -> invitee refresh -> updated amounts.
7. integration tests for rate-drift pipeline:
   - `ExchangeRateService.exchangeRatesDidRefresh` -> evaluator -> dirty -> coordinator -> publish,
   - rate refresh with no material change -> no publish.
8. UI tests for invitee freshness:
   - active refresh,
   - tiered staleness display with correct copy at each tier,
   - unavailable state,
   - updated totals appearing after owner mutation simulation,
   - freshness header text matches canonical grammar ("Shared {time} ago" or "Rates are {rate-age} old"),
   - rate freshness indicator when rates are old.
9. integration tests for offline queue:
   - owner edits offline -> dirty queued -> connectivity returns -> publish fires.
10. unit tests for multi-device idempotency:
    - two publishes of the same semantic state result in the same projection content,
    - invitee rejects projection with version < current cached version.
11. infrastructure prerequisite tests:
    - `ExchangeRateService` posts notification after rate batch refresh,
    - `GoalMutationService` posts `sharedGoalDataDidChange` after create, edit, archive, restore,
    - `AssetMutationService` posts `sharedGoalDataDidChange` after create, delete.
12. data quality telemetry test:
    - `family_share_rate_snapshot_age_at_publish` is emitted with every auto-publish,
    - `family_share_invitee_refresh_succeeded` includes `projectionAgeSeconds`.
13. composite freshness tests:
    - projection with recent publish but stale rates shows `recentlyStale` or worse (not `active`),
    - projection with stale publish but fresh rates uses publish age as governing dependency,
    - `max(publishAge, rateAge)` determines the tier in all cases.
14. coordinator serialization tests:
    - interleaved mutation and rate-drift events coalesce into one publish,
    - legacy `refreshAllState()` read-only operations do NOT trigger owner-side publishes (read path remains separate from publish coordinator),
    - no duplicate publishes under concurrent dirty events.
15. canonical freshness label tests:
    - list and detail produce the same primary message for the same composite state,
    - relative time grammar is consistent across surfaces.
16. cache migration tests:
    - cached projection without `rateSnapshotTimestamp` resolves to `recentlyStale`,
    - cached projection without `projectionVersion` defaults to version 0,
    - incoming projection with version >= 1 supersedes migrated cache.
17. accessibility tests:
    - silent refresh does not steal VoiceOver focus,
    - freshness tokens pass WCAG AA contrast in light and dark mode,
    - recovery actions have explicit VoiceOver labels.
18. (R3) namespace-level freshness tests:
    - two namespaces with different effective ages show independent freshness tiers on the same list,
    - `FamilyShareFreshnessLabel` is instantiated per namespace, not per list,
    - updating one namespace's freshness does not affect the other namespace's display.
19. (R3) stale-cause substate tests:
    - `checking` substate shows progress indicator and disables retry action,
    - `refreshFailed` substate shows "Couldn't refresh — showing last shared update" and enables "Try Again",
    - `cooldown` substate disables retry button for 30 seconds after last attempt,
    - `refreshFailed` auto-dismisses to age-based primary message after 60 seconds of inactivity,
    - all substates run against injected `FamilyShareClock` (no real sleeps).
20. (R3) detail provenance format tests:
    - detail view shows both relative time and exact local timestamp for `projectionPublishedAt`,
    - detail view shows both relative time and exact local timestamp for `rateSnapshotTimestamp`,
    - when both timestamps are identical, "Rates as of" row collapses with "(same as shared update)" note.
21. (R3) empty-state freshness precedence tests:
    - no shared namespaces: empty-state explanation only, no freshness chrome,
    - namespace with zero goals: namespace header shows freshness tier,
    - `temporarilyUnavailable` with previously populated namespace: error freshness label with retry.
22. (R3) compact-layout tests:
    - at iPhone 15 width and largest Dynamic Type size: title + primary freshness visible without overlap,
    - secondary rate-age detail collapses before primary message truncates,
    - recovery action maintains 44x44pt tap target,
    - section header never exceeds three lines.
23. (R3) motion and transition tests:
    - silent refresh preserves row order and scroll position,
    - freshness-label change uses crossfade transition,
    - `Reduce Motion` suppresses all nonessential animation,
    - `active` to `stale` transition crossfades label and adds icon,
    - `temporarilyUnavailable` to `active` recovery crossfades full section content.
24. (R3) per-namespace executor composition tests:
    - auto-republish coordinator is per-namespace instance, not singleton,
    - auto-republish coordinator delegates publish to `FamilyShareProjectionPublishCoordinator`,
    - legacy `refreshAllState()` read operations do not trigger owner-side publishes,
    - manual re-share from `FamilyAccessView` routes through coordinator as `manualRefresh` dirty event,
    - no component outside `FamilyShareNamespaceActor` boundary can trigger a publish.
25. (R3, updated R7) separated version and ordering tests:
    - `projectionVersion` (Int) increments correctly for atomic publish topology,
    - `projectionServerTimestamp` (Date) is set from `CKRecord.modificationDate` after successful publish,
    - invitee Phase 1: rejects projection with `projectionVersion` (Int) < cached `activeProjectionVersion`,
    - invitee Phase 2: `contentHash` matches cached → no-op (no UI churn),
    - invitee Phase 3: `contentHash` differs → accept unconditionally (semantic change),
    - pre-migration fallback: `contentHash` is `nil` → fall back to `projectionServerTimestamp` comparison, accept only if strictly newer,
    - `projectionServerTimestamp` is never consulted when `contentHash` is present on both sides.
26. (R3) clock-skew tests:
    - owner-fast: `projectionPublishedAt` 5 minutes in future — freshness shows `active` (clamped), telemetry fires,
    - timestamp within 60-second tolerance: no telemetry,
    - timestamp beyond 60-second tolerance: age clamped to zero, `family_share_clock_skew_detected` emitted,
    - all clock-skew tests use injected `FamilyShareClock`.
27. (R3) rollout/rollback tests:
    - flag-off: no mutation observer subscription active,
    - flag-off: no debounce or periodic timer running,
    - flag-off: no push-triggered refresh fires,
    - flag-off: no publish attempt made,
    - flag-off: cached invitee UI remains stable (no flash, no error state),
    - flag-off: `family_share_freshness_rollback` telemetry emitted exactly once per disable transition,
    - in-flight publish at rollback time is allowed to complete but no subsequent publishes fire.
28. (R3) testability seam verification:
    - all debounce tests advance virtual time via `FamilyShareScheduler` — no real sleeps,
    - all freshness-tier tests set exact timestamps via `FamilyShareClock`,
    - publish failure tests inject errors via `FamilySharePublishTransport`,
    - rate-drift tests inject events via `FamilyShareRateRefreshSource`.
29. (R4) pre-publish reconciliation barrier tests:
    - lagging device with pending CloudKit imports: publish suppressed, namespace stays dirty,
    - import fence satisfied after wait: publish proceeds with merged state,
    - import fence timeout (10s): publish suppressed, telemetry emitted,
    - offline device comes back online: barrier holds until sync completes,
    - two fully-synced devices publish concurrently: `contentHash` dedup prevents churn.
30. (R4, updated R7) separated version contract tests:
    - `projectionVersion` (Int) increments correctly for atomic publish topology,
    - `projectionServerTimestamp` (Date) is set from `CKRecord.modificationDate`,
    - invitee three-phase ordering: (1) rejects lower Int version, (2) `contentHash` match → no-op, (3) `contentHash` differs → accept unconditionally,
    - pre-migration fallback (`contentHash` nil): falls back to `projectionServerTimestamp` comparison,
    - mixed-schema cache (old records without `projectionServerTimestamp`): graceful fallback,
    - rollback: removing freshness pipeline leaves Int-based publish intact.
31. (R4) complete publish-trigger inventory tests:
    - share lifecycle (accept, revoke) routes through coordinator,
    - participant added/removed routes through coordinator as `.participantChange`,
    - owner display-name change routes through coordinator,
    - manual re-share from `FamilyAccessView` routes through coordinator as `.manualRefresh`,
    - no direct calls to `publish()` exist outside namespace actor boundary (compile-time or runtime check).
32. (R4) dependency-aware freshness grammar tests:
    - publish-governed copy: `publishAge=2h, rateAge=10m` -> "Shared 2 hours ago",
    - rate-governed copy: `publishAge=5m, rateAge=6h` -> "Rates are 6 hours old — values may have changed" with secondary "Shared 5 min ago",
    - `active` with both ages < 30m: "Shared X min ago" (publish-governed by default),
    - VoiceOver grammar matches visual copy for both governing dependencies.
33. (R4) `checkedNoNewData` substate tests:
    - manual refresh succeeds, returns same `contentHash`: shows "Checked — no newer update yet" with last-checked time,
    - no retry action shown for `checkedNoNewData` (retrying is not meaningful),
    - substate auto-dismisses to `idle` after 120 seconds,
    - user can distinguish `checkedNoNewData` from `refreshFailed`.
34. (R4) terminal removed/revoked namespace tests:
    - revocation detected via `CKError.zoneNotFound`: financial rows removed, terminal state shown,
    - no outdated financial amounts visible after revocation,
    - navigation into revoked goal detail is blocked,
    - dismiss affordance clears orphaned namespace from list,
    - cached financial data is purged (not just hidden) for privacy.
35. (R4, updated R7) detail-view Freshness card tests:
    - `Current` / `Target` remain first-scan dominant above the Freshness card,
    - at default through XXXL: Freshness card shows both provenance rows with exact timestamps auto-expanded inline,
    - at AX1+: exact timestamps collapse behind disclosure chevron (one tap expands inline within the card),
    - Freshness card never pushes financial summary below fold at any Dynamic Type size.
36. (R7) durable dirty-state persistence tests:
    - kill app between mutation and publish: dirty flag persisted; on relaunch, republish fires automatically,
    - namespace LRU eviction: dirty flag persisted before deallocation; re-hydration re-enqueues republish,
    - successful publish clears persisted dirty flag,
    - rollback (rollout disabled) clears all persisted dirty flags.
37. (R7) foreground rate-refresh driver tests:
    - `FamilyShareForegroundRateRefreshDriver` timer fires every 5 minutes during foreground session with active sharing,
    - driver is suspended on background entry and when no sharing is active,
    - 15-minute guard detects missed refresh and forces rate fetch,
    - no namespace exceeds the 5-minute TTL without a refresh/evaluation attempt,
    - driver uses injected `FamilyShareScheduler` (virtual time in tests).
38. (R7) multi-namespace compactness policy tests:
    - with three namespaces on iPhone 15: first goal row of first namespace visible without scrolling,
    - with two+ namespaces: secondary provenance suppressed from all headers,
    - with two+ namespaces: headers capped at two lines (title + freshness),
    - AX1+ Dynamic Type: icon suppressed for `active` and `recentlyStale` headers.
39. (R7) non-USD materiality policy tests:
    - EUR goal: $5 USD converted to EUR at current rate, rounded to 2 decimals with `.bankers` rounding,
    - JPY goal: $5 USD converted to JPY, rounded to 0 decimals,
    - BTC goal: $5 USD converted to BTC, compared using `max(1%, convertedFloor)`,
    - USD→goalCurrency rate unavailable: falls back to 1% threshold only (no absolute floor),
    - all threshold checks use `FamilyShareMaterialityPolicy` (no external threshold constants).

## 14) Open Questions Resolved

1. Should v1 depend on CloudKit push subscriptions for invitee live updates?
   - No. v1 uses automatic republish plus automatic pull refresh on key lifecycle boundaries. v2 adds `CKRecordZoneSubscription` push.
2. Should owner-side republish be partial or full projection rebuild?
   - Full rebuild from authoritative owner truth with fresh rates via `GoalProgressCalculator`.
3. Should manual refresh remain after automatic refresh exists?
   - Yes. It remains as explicit recovery and support tooling.
4. Should the invitee recalculate `currentAmount` using local rates?
   - No in v1. Invitees display the owner's published values. This ensures both owner and invitee see the same numbers. Rate freshness is conveyed via `rateSnapshotTimestamp`. Future direction: invitee-side local rate recalculation as an optional secondary display.
5. Should rate-drift republish happen in background?
   - No in v1. Rate-drift republish requires the owner app to be in foreground (rates refresh on foreground entry or periodically during active sessions). Future direction: `BGAppRefreshTask` for periodic background rate refresh and republish.
6. What materiality threshold prevents excessive churn from rate fluctuations?
   - 1% of `targetAmount` or $5 equivalent (whichever is **larger**), evaluated per goal. The $5 floor prevents churn on small goals; the 1% cap prevents churn on large goals. Expected: 2-4 rate-drift publishes per foreground session on a volatile day.
7. (updated R4/R7) How does the system handle the owner having multiple devices?
   - Pre-publish reconciliation barrier ensures each device has imported upstream CloudKit changes before publishing (Section 6.8.1). Invitee uses three-phase ordering: (1) Int topology check, (2) `contentHash` dedup, (3) `contentHash` differs → accept unconditionally. `projectionServerTimestamp` is pre-migration fallback only. `contentHash` covers all invitee-visible state including root metadata (Section 6.8.2).
8. What happens when the owner does not open the app for days?
   - The invitee sees tiered staleness: after 30 min "recentlyStale", after 4 hours "stale" with warning, after 24 hours "materiallyOutdated" with prominent warning. Copy focuses on data age, not owner behavior. Post-v1, `BGAppRefreshTask` can mitigate this.
9. Which computation path should be used for `currentAmount` in the projection?
   - `GoalProgressCalculator.calculateProgress(for:)` — a pure, non-`@MainActor` domain calculator extracted from the existing `GoalCalculationService` (Section 7.0.3). The current `goal.manualTotal` in `makeProjectionPayload()` must be replaced. This ensures the republish coordinator can run without `@MainActor` and produces the same results as the owner-facing dashboard.
10. Does `ExchangeRateService` currently have a notification mechanism?
    - No. Adding `Notification.Name.exchangeRatesDidRefresh` is a Phase 0 prerequisite (Section 7.0.1). The notification must fire per-batch with refreshed pair metadata and rate snapshot timestamp.
11. Are `PersistenceMutationServices` notifications consistent across mutation types?
    - No. `GoalMutationService` posts no notifications; `AssetMutationService` notifies from the view layer only. Normalizing the notification surface is a Phase 0 prerequisite (Section 7.0.2).
12. Should stale `rateSnapshotTimestamp` escalate the primary freshness state even when `projectionPublishedAt` is recent?
    - Yes. Freshness is composite: `effective age = max(publishAge, rateAge)`. A surface cannot show `active` when rates are 6 hours old, even if the projection was published 5 minutes ago. This is the core trust guarantee (Section 5.1.1, 6.4).
13. Which surface owns the canonical freshness grammar for shared goals?
    - Both list and detail use the same `FamilyShareFreshnessLabel` model. Surfaces may vary in density but not in timestamp meaning or trust semantics (Section 6.6, 8.2).
14. (R2) Should the detail view show additional warning-specific copy beyond the shared primary label?
    - No. Detail shows the same primary freshness line from `FamilyShareFreshnessLabel` plus expanded provenance (both timestamps as relative time with exact local timestamp inline). No additional warning copy beyond the primary message.
15. (R2) Should `temporarilyUnavailable` and `removedOrNoLongerShared` get dedicated semantic tokens?
    - They reuse existing app-wide token families: `status.error` for unavailable and `status.inactive` for removed. Dedicated icons and VoiceOver labels are defined in Section 8.3.
16. (R2) How is `$5 equivalent` computed for non-USD goals?
    - Via `FamilyShareMaterialityPolicy` (Section 5.3.1): convert $5 USD to goal currency using the same `ExchangeRateService` batch rates, round to goal currency minor units, compare using `max(1%, convertedFloor)`. If USD→goalCurrency rate is unavailable, fall back to 1% only.
17. (R2) What is the sendable input boundary for `GoalProgressCalculator`?
    - `GoalProgressInput` and `RateSnapshot` are `Sendable` value types (Section 7.0.3). The coordinator maps SwiftData managed objects into these snapshots before calling the calculator. No `@Model` types cross the boundary.
18. How are older cached projections without freshness metadata handled on upgrade?
    - Missing `rateSnapshotTimestamp` defaults to `projectionPublishedAt`. Missing `projectionVersion` defaults to `0`. Missing freshness metadata resolves to `recentlyStale`, never to false `active`. Migration runs once at launch (Section 7.0.4).
19. (R3) Should the visible freshness line live on each namespace/owner section header, or is there an approved aggregate pattern for mixed-freshness shared datasets?
    - Per-namespace section header. Freshness is evaluated and displayed per namespace. No aggregate pattern is approved — a single line cannot truthfully represent mixed-freshness datasets. Each `FamilyShareFreshnessLabel` is instantiated per namespace (Section 5.1.1, 6.4).
20. (R3, updated R7) For detail provenance, should exact timestamps always be visible inline, or available behind a disclosure affordance?
    - At default through XXXL Dynamic Type: exact timestamps are auto-expanded inline within the Freshness card. At AX1+: exact timestamps collapse behind a disclosure chevron (one tap expands inline within the card). Relative-time provenance rows remain visible at all sizes. This is the single canonical rule defined in Section 6.6.
21. (R3) How does the auto-republish coordinator compose with the existing `FamilyShareNamespaceActor` and `FamilyShareProjectionPublishCoordinator`?
    - The auto-republish coordinator is a per-namespace instance that lives inside `FamilyShareNamespaceActor` and delegates publish execution to the existing `FamilyShareProjectionPublishCoordinator`. It does not replace either component — it adds dirty-event/debounce logic above the existing publish path. Legacy refresh reads remain in `FamilyShareAcceptanceCoordinator`; only publish-triggering actions route through the auto-republish coordinator (Section 6.1.1).
22. (R3, updated R4) How does `projectionVersion` become globally monotonic across owner devices?
    - Concerns are separated: `projectionVersion` (Int) is retained for atomic publish topology; `projectionServerTimestamp` (Date) is pre-migration fallback only; `contentHash` is the authoritative semantic ordering signal. Invitee ordering is three-phase: (1) Int version topology check, (2) `contentHash` dedup (match → no-op), (3) `contentHash` differs → accept unconditionally. `projectionServerTimestamp` is only consulted when `contentHash` is nil (pre-migration). A pre-publish reconciliation barrier (import fence) prevents a lagging device from publishing older semantic state (Section 6.8.1, 6.8.2).
23. (R3) What is the canonical clock source for freshness timestamps?
    - `projectionPublishedAt` uses `CKRecord.modificationDate` (server-assigned). `rateSnapshotTimestamp` uses the API response timestamp when available, device `Date()` as fallback. Future timestamps beyond 60-second tolerance are clamped to zero-age with telemetry (Section 6.6.1).
24. (R3) How are time-based behaviors tested deterministically?
    - All time-dependent components accept injected `FamilyShareClock`, `FamilyShareScheduler`, `FamilySharePublishTransport`, and `FamilyShareRateRefreshSource` seam protocols. Tests run against virtual time, not real sleeps (Section 7.1.1).
25. (R3) What happens to freshness pipeline components when rollout is disabled?
    - All observers, timers, and push handlers are torn down. Pending dirty events are discarded. In-flight publish is allowed to complete but no subsequent publishes fire. Cached invitee UI remains stable. `family_share_freshness_rollback` telemetry is emitted (Section 10.2).
26. (R4, updated R8) Will the final design keep one explicit atomic publish token and add a separate server timestamp field, or fully migrate the topology/version contract away from the current Int schema?
    - Keep `projectionVersion` (Int) for atomic publish topology. Add `contentHash` (String) as the **authoritative** post-migration ordering signal — a different hash means semantic change and is accepted unconditionally. Add `projectionServerTimestamp` (Date) as a **pre-migration fallback only** — it is consulted only when `contentHash` is nil on one or both sides. Schema migration is additive and rollback-safe (Section 6.8.2, 7.0.4).
27. (R4) What concrete reconciliation barrier proves an owner device has imported the required upstream state before it is allowed to republish?
    - A CloudKit import fence: the coordinator queries `NSPersistentCloudKitContainer` import history tokens and waits (up to 10s) for pending imports to complete before snapshotting local Goal state. If the fence times out, publish is suppressed and the namespace stays dirty for the next cycle. Additionally, a `contentHash` in the payload provides secondary semantic deduplication to prevent identical publishes from causing UI churn (Section 6.8.1).
28. (R4) How should the invitee handle a successful refresh that returns no newer projection?
    - A distinct `checkedNoNewData` substate shows "Checked — no newer update yet" with last-checked time. No retry action is shown because retrying cannot produce newer data until the owner republishes. The substate auto-dismisses after 120 seconds (Section 6.4.3).
29. (R4) What happens to cached financial data when a share is revoked?
    - Financial rows are removed immediately. Cached data is purged (not just hidden) for privacy. The namespace shows a terminal explanatory state with a dismiss affordance. Navigation into revoked goal detail is blocked (Section 6.4.1).
30. (R4, updated R6) How does the freshness grammar handle rate-governed staleness vs publish-governed staleness?
    - Grammar splits by governing dependency. Publish-governed: "Shared X ago." Rate-governed: **rate age always leads** — "Rates are X old" (never "Shared X ago — rates are..."). Share time is demoted to detail-view-only provenance when rate age governs, so a user can tell in one glance what is stale (Section 8.2).
31. (R6) Should `contentHash` cover the full invitee-visible payload, or should the proposal define separate metadata and goal-data hash semantics?
    - Full invitee-visible payload in a single hash. The hash covers goal data (IDs, amounts, allocations), rate snapshot timestamp, AND root metadata (owner display name, participant list, participant count). This ensures that `.participantChange` dirty events always produce a different hash and are never deduplicated away. Splitting into separate hashes adds complexity without benefit since the hash is lightweight (Section 6.8.1).
32. (R6) Which migration rule is canonical for missing `projectionServerTimestamp`: default to `projectionPublishedAt` or default to `nil`?
    - Default to `nil`. The canonical migration rule in Section 7.0.4 and Section 6.8.2 both specify `nil`. Invitee ordering treats `nil` as "unknown — accept any incoming projection with a non-nil timestamp." There is no fallback to `projectionPublishedAt` for this field (that fallback applies only to `rateSnapshotTimestamp`).
33. (R6, confirmed R7) At the largest supported Dynamic Type size, are exact provenance timestamps still always visible inline, or is a disclosure pattern the intended final behavior?
    - In-card disclosure chevron. Section 6.6 defines the single canonical rule: at default through XXXL, exact timestamps are auto-expanded inline. At AX1+, exact timestamps collapse behind a disclosure chevron (one tap expands inline within the card). Relative-time provenance rows remain visible at all sizes. The expansion happens within the Freshness card itself — there is no separate sheet or navigation.

## 15) Why This Proposal Is the Right Scope

This proposal deliberately fixes the real trust problem:

1. not just stale copy,
2. not just a retry button,
3. not just "tell users to refresh",
4. not just "tell owners to open Family Access again",
5. not just ignoring that exchange rates affect every number the invitee sees.

The problem is that shared goals currently lack a freshness contract that covers both explicit edits and implicit value drift.
The correct solution is to define and implement that contract across publish, rate evaluation, fetch, states, telemetry, and recovery.
