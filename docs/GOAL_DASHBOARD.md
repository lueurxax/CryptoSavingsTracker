# Goal Dashboard

> Decision-first goal dashboard with deterministic next-action CTA and scene-model architecture

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-03-16 |
| Platform | iOS first, Android parity required |
| Audience | Developers |

---

## Overview

The Goal Dashboard is a per-goal screen accessed from Goal Detail. It answers four questions:

1. Where am I relative to target and deadline?
2. What is the best next action now?
3. Can I reach deadline at current pace?
4. What changed recently?

All modules consume typed slices from a single `GoalDashboardSceneModel`, assembled by `GoalDashboardSceneAssembler`. No raw model queries are allowed in dashboard modules.

---

## Module Order

All size classes use the same semantic order:

1. `goal_snapshot` - progress summary (current/target/remaining/days)
2. `next_action` - deterministic primary CTA
3. `forecast_risk` - pace projection with confidence
4. `contribution_activity` - month contribution sum and recent rows
5. `allocation_health` - over-allocation and concentration warnings
6. `utilities` - secondary actions and settings

**Layout:** iPhone uses single column; iPad/macOS uses adaptive two-column. `next_action` is always above fold.

---

## Scene Model Architecture

### Ownership

- iOS: `GoalDashboardViewModel` + `GoalDashboardSceneAssembler`
- Android: `GoalDashboardViewModel` + matching assembler/use-case
- Views consume scene-model slices only

### Schema

```swift
struct GoalDashboardSceneModel {
    let goalId: UUID
    let goalLifecycle: GoalLifecycleState         // active, paused, finished, archived
    let currency: String
    let generatedAt: Date
    let freshness: DataFreshnessState             // fresh, stale, hardError
    let freshnessUpdatedAt: Date?
    let freshnessReason: String?

    let snapshot: SnapshotSlice
    let nextAction: NextActionSlice
    let forecastRisk: ForecastRiskSlice
    let contributionActivity: ContributionActivitySlice
    let allocationHealth: AllocationHealthSlice
    let utilities: UtilitiesSlice
    let telemetryContext: DashboardTelemetryContext
}
```

### Update Triggers

Scene recompute fires on: goal change, allocation change, transaction insert/update/delete, balance refresh, exchange-rate refresh, explicit user refresh, app foreground when stale threshold passed.

### Module States

Each module implements: `loading`, `ready`, `empty`, `error`, `stale`. Each `error` and `stale` state has an explicit recovery action.

| Module | `error` recovery | `stale` recovery |
|--------|-------------------|-------------------|
| `goal_snapshot` | Retry Data Sync | Refresh Snapshot |
| `next_action` | Retry Data Sync | Refresh Data |
| `forecast_risk` | Retry Forecast | Refresh Forecast |
| `contribution_activity` | Reload Activity | Refresh Activity |
| `allocation_health` | Recompute Allocation Health | Refresh Allocations |
| `utilities` | Open Goal Details | Continue |

---

## Next Action Resolver

Exactly one primary CTA is rendered per dashboard state. Priority order (top wins):

| Priority | Resolver State | Condition | Primary CTA | Secondary CTA |
|----------|---------------|-----------|-------------|---------------|
| 1 | `hard_error` | freshness = hardError | Retry Data Sync | View Diagnostics |
| 2 | `goal_finished_or_archived` | lifecycle in finished/archived | View Goal History | Create New Goal |
| 3 | `goal_paused` | lifecycle = paused | Resume Goal | Edit Goal |
| 4 | `over_allocated` | overAllocated = true | Rebalance Allocations | Open Allocation Health |
| 5 | `no_assets` | zero assets | Add First Asset | Edit Goal |
| 6 | `no_contributions` | month sum = 0 | Add First Contribution | Open Activity |
| 7 | `stale_data` | freshness = stale | Refresh Data | Continue With Last Data |
| 8 | `behind_schedule` | forecastRisk = offTrack | Plan This Month | Add Contribution |
| 9 | `on_track` | default | Log Contribution | Open Forecast |

For `hard_error`, a diagnostics sheet is mandatory with: reason code, last successful refresh timestamp, and actionable next-step guidance in plain language.

---

## Forecast Explainability

Each `forecast_risk` card in `ready`, `stale`, and `error` states shows:

- Assumption basis: "Based on last {N} days of contributions"
- Recency: "Updated {relative time}" + absolute timestamp in details
- Confidence level: Low / Medium / High
- Disclosure action: "Why this status?"

Status may not be shown without assumption basis + recency. If confidence is Low, `next_action` cannot suggest optimistic copy.

---

## Status Chips

| Status | Icon | Text | Accessibility Label |
|--------|------|------|---------------------|
| `on_track` | `checkmark.circle.fill` | On Track | On track: current pace can reach deadline |
| `at_risk` | `exclamationmark.triangle.fill` | At Risk | At risk: current pace may miss deadline |
| `off_track` | `xmark.octagon.fill` | Off Track | Off track: current pace will miss deadline |

Contrast: text >= 4.5:1 (WCAG AA), non-text indicators >= 3:1.

---

## Navigation

- Canonical route: `goal/{goalId}/dashboard`
- iOS entry: `GoalDetailView` -> `GoalDashboardScreen`
- Android entry: `GoalDetailScreen` -> `goal/{goalId}/dashboard` -> `GoalDashboardScreen`
- Legacy dashboard routes have been removed

---

## Rollback Thresholds

Rollback is mandatory if any condition is met:

1. Crash-free rate delta <= -0.30pp vs stable release (rolling 24h, >= 2,000 sessions)
2. Duplicate-load rate > 0.50% (rolling 6h, >= 500 opens)
3. CTA resolver mismatch > 1.00% in QA suite for 2 consecutive runs

Rollback mechanism: git/hotfix revert only (no runtime feature toggle). See `docs/runbooks/goal-dashboard-release-gate.md`.

---

## Cross-Platform Parity

Shared parity artifact: `shared-test-fixtures/goal-dashboard/goal_dashboard_parity.v1.json`

Required keys: module IDs, state IDs, CTA resolver state IDs, copy keys, status chip IDs. Release fails on iOS/Android drift. Parity artifact changes require semver bump + joint iOS/Android lead approval.

---

## Source Files

### iOS

| File | Purpose |
|------|---------|
| `Views/Dashboard/GoalDashboardScreen.swift` | Canonical dashboard entry |
| `ViewModels/GoalDashboardViewModel.swift` | Scene model owner |
| `Services/GoalDashboardSceneAssembler.swift` | Scene assembly from services |
| `Models/GoalDashboardSceneModel.swift` | Typed scene model + slices |
| `Utilities/GoalDashboardSceneWireCodec.swift` | Wire format encoding |

---

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [COMPONENT_REGISTRY.md](COMPONENT_REGISTRY.md) - UI component catalog
- [Runbook: Goal Dashboard Release Gate](runbooks/goal-dashboard-release-gate.md)
