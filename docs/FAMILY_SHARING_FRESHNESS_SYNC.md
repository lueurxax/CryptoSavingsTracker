# Family Sharing Freshness Sync

| Metadata | Value |
|----------|-------|
| Status | Implemented |
| Last Updated | 2026-03-22 |
| Platform | iOS 18+, iPadOS 18+ |
| Audience | Developers, QA, Release Managers |

## Overview

`Family Sharing Freshness Sync` is the shipped trust layer for read-only shared goals. It keeps invitee-visible projections current after owner-side mutations and exchange-rate drift, and it makes freshness explicit in both the shared-goals list and read-only detail surfaces.

This document replaces the implementation proposal chain. It describes the runtime contract that now exists in code.

Related docs:

- [FAMILY_SHARING.md](FAMILY_SHARING.md) for the broader CloudKit family-sharing model
- [runbooks/family-sharing-release-gate.md](runbooks/family-sharing-release-gate.md) for rollout, incident response, and pre-release gates

## User-Facing Contract

### Shared With You List

Invitees see freshness per namespace, not per app and not per individual goal row.

- The list surface renders [`FamilyShareFreshnessHeaderView`](../ios/CryptoSavingsTracker/Views/FamilySharing/FamilyShareFreshnessHeaderView.swift) from [`SharedGoalsSectionView`](../ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift).
- The header uses [`FamilyShareFreshnessLabel`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift) as the single copy model for visible text and VoiceOver text.
- The canonical publish timestamp is `projectionServerTimestamp` when present, with `publishedAt` as fallback.
- Recovery actions are stateful:
  - `Retry Refresh` for stale and materially outdated namespaces
  - `Retry` for temporarily unavailable namespaces
  - `Try Again` for failed manual refresh attempts
  - `Remove` for removed or no-longer-shared namespaces
- `Checked just now — no newer update yet` is a transient secondary line, not a replacement for the primary freshness message.

### Detail Surface

The goal detail screen renders a dedicated `Freshness` card below the primary financial summary.

- [`SharedGoalDetailView`](../ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift) injects the same [`FamilyShareFreshnessLabel`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift) model used by the list header.
- [`FamilyShareFreshnessCardView`](../ios/CryptoSavingsTracker/Views/FamilySharing/FamilyShareFreshnessCardView.swift) shows:
  - the primary freshness message,
  - `Last shared`,
  - `Rates as of`.
- At default Dynamic Type sizes, provenance rows include both relative and exact timestamps inline.
- At accessibility Dynamic Type sizes, exact timestamps collapse behind per-row disclosure controls instead of being removed.

### Freshness Tiers

Freshness is composite. The governing dependency can be either publish age or rate age.

| Tier | Typical Copy | Governing Condition |
|------|--------------|--------------------|
| `active` | `Shared 5m ago` | Projection and rates are within active thresholds |
| `recentlyStale` | `Shared 2h ago` or `Rates are 2h old` | Older than active, but below stale threshold |
| `stale` | `Last shared 2d ago — values may have changed` or `Rates are 2d old — values may have changed` | Publish age or rate age crossed stale threshold |
| `materiallyOutdated` | `Rates are 4d old — values may have changed significantly` | Severe age or rate drift risk |
| `temporarilyUnavailable` | `Shared goals temporarily unavailable` | Fetch/bootstrap failure path |
| `removedOrNoLongerShared` | `This shared goal set is no longer available` | Owner revoked or deleted the namespace |

Source of truth:

- [`FamilyShareFreshnessPolicy.swift`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessPolicy.swift)
- [`FamilyShareFreshnessLabel.swift`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift)

## Runtime Architecture

### Owner Pipeline

Owner-side freshness maintenance is assembled inside [`FamilyShareAcceptanceCoordinator`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift) and started from `startFreshnessPipeline()`.

1. [`FamilyShareProjectionMutationObserver`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionMutationObserver.swift) listens to `sharedGoalDataDidChange` notifications and classifies them into semantic dirty reasons.
2. [`FamilyShareForegroundRateRefreshDriver`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareForegroundRateRefreshDriver.swift) keeps exchange-rate refresh attempts active during long owner foreground sessions.
3. [`FamilyShareRateDriftEvaluator`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareRateDriftEvaluator.swift) compares newly refreshed rates against the last published goal amounts and emits `.rateDrift` only when the configured materiality threshold is exceeded.
4. [`FamilyShareProjectionAutoRepublishCoordinator`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareProjectionAutoRepublishCoordinator.swift) is the single publish ingress for a namespace. It owns:
   - debounce and coalescing,
   - trailing publish behavior,
   - dirty-state persistence across relaunch,
   - content-hash dedup,
   - exponential backoff,
   - reconciliation barrier checks.
5. [`FamilyShareReconciliationBarrier`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareReconciliationBarrier.swift) suppresses publishes when the local owner device is still behind known CloudKit import state.
6. [`FamilyShareProjectionPublishCoordinator`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift) and [`FamilyShareCloudKitStore`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift) write the projection payload to CloudKit.

The runtime rule is simple: no component outside the namespace actor boundary publishes directly. All publish-triggering flows funnel through the auto-republish coordinator.

### Invitee Pipeline

Invitee freshness state is driven by [`FamilyShareInviteeRefreshScheduler`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareInviteeRefreshScheduler.swift).

- Foreground entry triggers refresh subject to cooldown.
- First visibility of a `Shared with You` section triggers refresh subject to the same cooldown.
- Manual retry bypasses passive waiting but still respects the active checking/cooldown rules.
- Scheduler substates are per namespace:
  - `idle`
  - `checking`
  - `refreshSucceeded`
  - `checkedNoNewData`
  - `refreshFailed`
  - `cooldown`

On successful refresh, the coordinator rehydrates the namespace cache and the UI recomputes the freshness label from the new projection metadata.

### Rollout and Teardown

The freshness pipeline is currently controlled by the same rollout flag as family sharing itself:

- [`FamilyShareRollout.flagEnabled`](../ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareRollout.swift)
- [`FamilyShareRollout.isFreshnessPipelineEnabled()`](../ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareRollout.swift)

If the rollout is disabled, the coordinator does not start owner mutation observation, foreground rate refresh, rate-drift evaluation, or invitee refresh scheduling. Rollback behavior and validation live in [runbooks/family-sharing-release-gate.md](runbooks/family-sharing-release-gate.md).

## Data Contract

Freshness metadata is additive on top of the shared projection payload and the invitee cache model.

Primary model definitions:

- [`FamilyShareProjectionPayload`](../ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift)
- [`FamilySharedDatasetCache`](../ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift)
- [`FamilyShareCloudKitStore`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift)

| Field | Purpose | Notes |
|------|---------|-------|
| `projectionVersion` | Monotonic projection generation number | Still an `Int`/`Int64`, not a timestamp |
| `activeProjectionVersion` | Version currently visible to invitees | Flips after the publish is durable |
| `publishedAt` | Device-local publish timestamp | Fallback display timestamp only |
| `projectionServerTimestamp` | Canonical server-assigned ordering timestamp | Preferred freshness clock source |
| `rateSnapshotTimestamp` | Timestamp of exchange rates used to compute `currentAmount` | Needed for rate-governed freshness |
| `contentHash` | Semantic hash of invitee-visible state | Enables dedup and safe no-op publishes |

Implementation notes:

- `projectionServerTimestamp` is populated from the CloudKit root record and falls back to `CKRecord.modificationDate` when needed during readback.
- `contentHash` protects against duplicate publishes of semantically identical payloads.
- Cache schema remains additive and rehydratable from CloudKit.

## UI Surface Map

| Surface | File | Responsibility |
|---------|------|----------------|
| Shared list section | [`SharedGoalsSectionView.swift`](../ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift) | Injects per-namespace freshness header and visibility trigger |
| List freshness header | [`FamilyShareFreshnessHeaderView.swift`](../ios/CryptoSavingsTracker/Views/FamilySharing/FamilyShareFreshnessHeaderView.swift) | Primary freshness messaging, recovery CTA, VoiceOver |
| Read-only goal detail | [`SharedGoalDetailView.swift`](../ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift) | Places the `Freshness` card in the detail composition |
| Detail freshness card | [`FamilyShareFreshnessCardView.swift`](../ios/CryptoSavingsTracker/Views/FamilySharing/FamilyShareFreshnessCardView.swift) | Provenance rows, accessibility disclosure behavior |

## Testing and Evidence

The freshness sync contract is guarded by focused unit suites and UI flows.

### Unit Suites

- [`FamilyShareAcceptanceCoordinatorTests.swift`](../ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift)
- [`FamilyShareFreshnessLabelTests.swift`](../ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessLabelTests.swift)
- [`FamilyShareFreshnessPolicyTests.swift`](../ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessPolicyTests.swift)
- [`FamilyShareForegroundRateRefreshDriverTests.swift`](../ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareForegroundRateRefreshDriverTests.swift)
- [`FamilyShareInviteeRefreshSchedulerTests.swift`](../ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeRefreshSchedulerTests.swift)
- [`FamilyShareRateDriftEvaluatorTests.swift`](../ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareRateDriftEvaluatorTests.swift)
- [`FamilyShareReconciliationBarrierTests.swift`](../ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareReconciliationBarrierTests.swift)
- [`FamilyShareProjectionAutoRepublishCoordinatorTests.swift`](../ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareProjectionAutoRepublishCoordinatorTests.swift)
- [`FamilyShareInviteeOrderingTests.swift`](../ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeOrderingTests.swift)
- [`FamilyShareMaterialityPolicyTests.swift`](../ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareMaterialityPolicyTests.swift)

### UI and Release Gates

Release-critical expectations live in [runbooks/family-sharing-release-gate.md](runbooks/family-sharing-release-gate.md), including:

- deterministic UI test invocations for list and detail freshness behavior,
- two-Apple-ID smoke validation,
- telemetry and rollback thresholds,
- incident response for stale publish, rate drift, and namespace corruption.

## Related Code Map

For production wiring, start here:

- [`FamilyShareServices.swift`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift)
- [`CryptoSavingsTrackerApp.swift`](../ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift)
- [`FamilyShareRollout.swift`](../ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareRollout.swift)

For storage and transport:

- [`FamilySharingSupport.swift`](../ios/CryptoSavingsTracker/Models/FamilySharing/FamilySharingSupport.swift)
- [`FamilyShareCloudKitStore.swift`](../ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareCloudKitStore.swift)

For invitee UI:

- [`SharedGoalsSectionView.swift`](../ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift)
- [`SharedGoalDetailView.swift`](../ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalDetailView.swift)
