# Family Sharing: Read-Only Goal Access

| Metadata | Value |
|----------|-------|
| Status | Implemented |
| Last Updated | 2026-03-18 |
| Platform | iOS 18+, iPadOS 18+ |
| Audience | Developers |

## Overview

Family Sharing allows the goal owner to grant household members strict read-only access to the full goal set using CloudKit sharing. Invitees see a dedicated consumer experience with no editing or planning authority.

This feature is higher priority than `Local Bridge Sync` and must remain shipped before any further bridge expansion.

---

## Product Model

### Share Unit

The share unit is the owner's full goal set — not individual goals.

- Granting access makes all current goals visible
- Newly created goals become visible automatically after projection refresh
- No goal-by-goal allowlists
- Revocation applies per invitee, not per goal

### Permission Model

One non-owner permission: `readOnly`.

Allows: goal name, emoji, status, target amount, deadline, progress, forecast state, current-month summary, contribution summaries.

Does not allow: editing goals/assets/transactions, monthly execution, planning settings, bridge/import tools.

### Enforcement

Read-only access is enforced at both UI and service layers:

- `FamilyShareAccessGuard` rejects write attempts at mutation service boundaries (Goal, Asset, Transaction, MonthlyPlan)
- Invitee views use dedicated read-only screens, not owner views with buttons removed
- Deep links into edit/planning/import flows fail closed for invitees
- `UICloudSharingController` is configured with `availablePermissions = [.allowPrivate, .allowReadOnly]`

---

## Architecture

### Data Flow

```
Owner's authoritative CloudKit-backed store
    |
    v
FamilyShareProjectionPublishCoordinator (publishes projection)
    |
    v
CloudKit privateCloudDatabase (projection root + goal records)
    |
    v (CKShare with read-only participants)
    |
CloudKit sharedCloudDatabase (invitee reads)
    |
    v
FamilyShareNamespaceActor (per-namespace actor)
    |
    v
FamilyShareNamespaceRegistry (isolated SwiftData cache per ownerID/shareID)
    |
    v
Invitee read-only UI
```

### Key Design Decisions

1. **Projection model, not live graph**: Invitees read from a dedicated projection dataset, not the owner's write-oriented record graph.
2. **Isolated cache per namespace**: Each `ownerID/shareID` pair gets its own SwiftData container backed by separate SQLite files.
3. **Actor-based concurrency**: `FamilyShareNamespaceActor` serializes accept/refresh/revoke/publish per namespace. Cross-namespace work runs concurrently.
4. **Atomic publish**: `activeProjectionVersion` flips only after all child records for that version are durably published. Failed publishes leave the previous version visible.
5. **Scene-based acceptance**: `windowScene(_:userDidAcceptCloudKitShareWith:)` routes through `FamilyShareAcceptanceCoordinator` for both cold-start and warm-start.

### CloudKit Record Topology

| Record Type | Zone | Naming Pattern |
|-------------|------|----------------|
| `FamilyShareProjectionRoot` | `family-share.{ownerID}.{shareID}.zone` | `family-share.{ownerID}.{shareID}.root` |
| `FamilySharedGoalProjection` | Same zone | `family-share.{ownerID}.{shareID}.goal.{goalID}` |
| `CKShare` | Same zone | `family-share.{ownerID}.{shareID}.share` |

---

## Repository Layout

### Models

| File | Contents |
|------|----------|
| `Models/FamilySharing/FamilySharingSupport.swift` | Permission enum, lifecycle states (owner + invitee), namespace ID, projection payloads, SwiftData cache models (`FamilySharedDatasetCache`, `FamilySharedGoalCache`, `FamilySharedOwnerSectionCache`), cache schema versioning |

### Services

| File | Contents |
|------|----------|
| `Services/FamilySharing/FamilyShareServices.swift` | Protocols (`FamilyShareStateProviding`, `ProjectionPublishing`, `OwnerSharingServicing`, `CacheMigrating`, `NamespaceManaging`, `SceneAccepting`), `FamilyShareNamespaceActor`, `FamilyShareNamespaceExecutionHub`, `FamilyShareAccessGuard`, `FamilyShareProjectionPublishCoordinator`, `FamilyShareAcceptanceCoordinator` (main entry point), `FamilyShareSceneDelegateBridge` |
| `Services/FamilySharing/FamilyShareCloudKitStore.swift` | CloudKit sync implementation: `FamilyShareCloudSyncing` protocol, `DefaultFamilyShareCloudKitStore` (publish, accept, fetch, refresh, revoke), `FamilyShareRootRecordLocatorStore` |

### Utilities

| File | Contents |
|------|----------|
| `Utilities/FamilySharing/FamilyShareRollout.swift` | Feature flag (`family_readonly_sharing_enabled`), remote config, debug override, telemetry tracker (27 events), redaction |
| `Utilities/FamilySharing/FamilyShareCacheStore.swift` | `FamilyShareNamespaceStore`, `FamilyShareNamespaceStoreFactory`, `FamilyShareNamespaceRegistry` (LRU, max 2 open stores) |
| `Utilities/FamilySharing/FamilyShareAppDelegate.swift` | Scene configuration for share acceptance |
| `Utilities/FamilySharing/FamilyShareTestSeeder.swift` | 9 test scenarios for UI/integration testing |

### Views

| File | Contents |
|------|----------|
| `Views/FamilySharing/FamilySharingModels.swift` | View models: `FamilySharedGoalSummary`, `FamilyShareOwnerSection`, `FamilyShareScopePreviewModel`, `FamilyAccessModel` |
| `Views/FamilySharing/FamilySharingComponents.swift` | Reusable components: `FamilySharingCard`, `FamilySharingBadge`, `FamilySharingStateBanner`, `FamilySharingStatusChip` |
| `Views/FamilySharing/FamilyAccessView.swift` | Owner management: share, scope preview, participants, status |
| `Views/FamilySharing/FamilyShareScopePreviewSheet.swift` | Mandatory pre-share disclosure with staged sections |
| `Views/FamilySharing/FamilyShareParticipantsView.swift` | Participant list with state and revoke |
| `Views/FamilySharing/FamilyCloudSharingControllerSheet.swift` | `UICloudSharingController` wrapper |
| `Views/FamilySharing/SharedGoalsSectionView.swift` | Owner-grouped shared goals with header and state banner |
| `Views/FamilySharing/SharedGoalRowView.swift` | Individual shared goal row with owner chip |
| `Views/FamilySharing/SharedGoalDetailView.swift` | Read-only goal detail with metrics, freshness, state |

---

## Lifecycle States

### Invitee States

| State | Trigger | Primary Action |
|-------|---------|----------------|
| `invitePendingAcceptance` | Invite exists, not accepted | Accept |
| `emptySharedDataset` | Accepted, zero goals | Retry |
| `active` | Reconciliation within 24h | View, pull to refresh |
| `stale` | No reconciliation for >24h | View cached, retry |
| `temporarilyUnavailable` | Account/network/bootstrap failure | Retry |
| `revoked` | Owner revoked access | Ask owner to re-share |
| `removedOrNoLongerShared` | Dataset deleted/unpublished | Dismiss |

### Owner States

| State | Trigger | Primary Action |
|-------|---------|----------------|
| `notShared` | No participants | Share with Family |
| `invitePending` | Invite sent, not accepted | Manage Participants |
| `sharedActive` | Active participants | Manage Participants |
| `revoked` | Participant removed | Done |
| `shareFailed` | Create/invite failed | Retry |

---

## Navigation & UI

### Entry Points

- **Owner**: `Settings -> Family Access`
- **Invitee**: `Goals` root with dedicated `Shared Goals` section (not in Settings)

### Multi-Owner Grouping

- Shared goals grouped by owner with `SharedGoalsOwnerHeaderView`
- Each row has an inline owner chip visible even when section header scrolls offscreen
- Owner groups sorted by display name (locale-aware), fallback to `ownerID` then `shareID`
- Owned and shared rows are never interleaved

### Visual Rules

- Glass reserved for navigation chrome and section framing only
- Financial metrics, freshness, and recovery states use opaque/near-opaque surfaces
- Non-active states (stale, unavailable, revoked, removed) dominate the first viewport
- Shared-row chrome is distinct from owned-goal rows

---

## Namespace Lifecycle

- Stores open lazily on acceptance or explicit access
- Max 2 namespace stores open concurrently (LRU eviction)
- Revoked namespaces purge within 24h of confirmed revocation
- Reopen is idempotent (no leaked store instances)

### Cache Migration

- Versioned schema (`FamilyShareCacheSchema.currentVersion`)
- `FamilyShareCacheMigrationCoordinator` handles migrate/rebuild/quarantine
- Incompatible newer schemas fail closed with `temporarilyUnavailable`
- Rebuild-first strategy (cache is non-authoritative, rehydratable from CloudKit)

---

## Projection Publishing

### Publish Triggers

Goal create, update, archive/restore/close, delete; monthly status change; contribution summary change; owner display-name change; share creation/revoke/participant transitions.

### Atomic Publish Contract

1. Owner mutations enqueue a `FamilyShareProjectionOutboxItem`
2. `FamilyShareProjectionPublishCoordinator` drains serially per namespace
3. Child projection records written under the next `projectionVersion`
4. `activeProjectionVersion` flips only after full child set is durable
5. Failed publish: invitees continue reading previous version
6. Retry is idempotent — no duplicate records

### Shared Projection Fields

**Included**: owner display name, dataset share ID, goal ID/name/emoji, currency, target/current amount, progress %, deadline, status, forecast, current month summary, last updated, contribution summary.

**Excluded**: wallet addresses, raw transaction IDs, planning drafts, migration/repair state, bridge state, settings, telemetry.

---

## Feature Flag & Rollout

Flag: `family_readonly_sharing_enabled`

Sources (priority order): debug override > remote config > release default.

Kill switch disables new creation and new acceptance first. Existing accepted shares degrade to `stale`/`temporarilyUnavailable`, not silent disappearance.

### Kill-Switch Thresholds

| Metric | Threshold | Window | Minimum Sample |
|--------|-----------|--------|----------------|
| `family_share_create_failed` rate | >5.0% | Rolling 6h | 100 creates |
| `family_share_accept_failed` rate | >5.0% | Rolling 6h | 100 accepts |
| `family_share_unavailable_viewed` rate | >10.0% | Rolling 24h | 500 opens |
| Cache bootstrap failure rate | >2.0% | Rolling 24h | 100 bootstraps |

---

## Telemetry

27 events tracked via `FamilyShareTelemetryTracker`. Key events:

- `family_share_create_started/succeeded/failed`
- `family_share_accept_succeeded/failed`
- `family_share_revoked`
- `family_share_refresh_stale`
- `family_share_temporarily_unavailable`
- `family_share_empty_viewed`
- `family_share_removed_viewed`
- `family_share_namespace_migration_failed`
- `family_share_namespace_rebuild_started/succeeded`

### Redaction

- Goal names, money amounts, participant emails never logged
- IDs logged only as SHA256 hashes via `FamilyShareTelemetryRedactor`
- Support diagnostics separate identifiers from financial payload

---

## Dependency Injection

All family sharing services registered in `DIContainer`:

- `familyShareNamespaceRegistry`
- `familyShareRollout`
- `familyShareTelemetryTracker`
- `familyShareCloudKitStore`
- `familyShareStateProvider`
- `familyShareInviteeStateProvider`
- `familyShareProjectionPublisher`
- `familyShareProjectionPublishCoordinator`
- `familyShareOwnerSharingService`
- `familyShareCacheMigrationCoordinator`
- `familyShareAcceptanceCoordinator` (main entry point)
- `familyShareAccessGuard` (used by mutation services)

---

## Testing

### Test Seeder Scenarios

| Scenario | Description |
|----------|-------------|
| `ownerNotShared` | Owner with no participants |
| `ownerSharedActive` | Owner with active sharing |
| `inviteeActive` | Single-owner active shared goals |
| `inviteeMultiOwner` | Multiple owners grouped |
| `inviteeEmpty` | Accepted share, zero goals |
| `inviteeStale` | Cached data, no recent reconciliation |
| `inviteeRevoked` | Access revoked |
| `inviteeRemoved` | Dataset no longer available |
| `inviteeUnavailable` | Bootstrap/network failure |

### Unit Tests

`FamilyShareAcceptanceCoordinatorTests`: share creation, telemetry, multi-owner grouping, reset, bootstrap-safe error handling.

### UI Tests

`FamilySharingUITests`: end-to-end flows using test seeder scenarios.
