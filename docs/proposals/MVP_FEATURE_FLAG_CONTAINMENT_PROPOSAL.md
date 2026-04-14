# MVP Feature-Flag Containment Proposal

Status: Approved  
Approved at: 2026-04-12  
Platform: Apple public release scope (iOS + shared Apple code compiled for visionOS)  
Source artifact: `state_7_implementation_started.1/lead_orchestrator/1/approved_proposal`

## Executive Summary

Ship CryptoSavingsTracker as a focused personal goal tracker without deleting the broader codebase. Apple production builds expose only goals, assets, crypto tracking, manual transactions, dashboards, onboarding, and settings; all other capabilities remain in source but are structurally contained behind local release policy flags, route manifests, startup gating, and mutation-boundary rules so hidden features cannot wake up through startup hooks, deep links, background workers, or legacy schedulers.

The user direction is respected: this proposal does not require broad code deletion. However, simple view-level flag hiding is not sufficient for production because the current Apple app still performs retired work during startup, scene registration, background scheduling, and write flows. The resulting effort is intentionally M rather than S-M because the MVP must close those runtime seams while keeping the codebase intact for future re-enablement.

Decision: Adopt feature-flag containment with a policy kernel as the production strategy. Keep the codebase; disable non-MVP behavior structurally, not cosmetically.

## Problem

The current product mixes personal goal tracking with planning, reminders, automation, family sharing, bridge sync, exports, and advanced dashboarding. That breadth creates user confusion and release risk. The user no longer wants a deletion-led pruning program; they want a production-safe MVP that hides non-core functionality behind flags while preserving the code for later reuse.

## Goals

- Ship a production-safe MVP without deleting the non-MVP codebase.
- Guarantee that production users cannot reach planning, reminder, family-sharing, bridge, export, shortcut, or advanced-dashboard behavior.
- Keep SwiftData, CloudKit, and Android Room contracts unchanged.
- Define one retained product contract for onboarding, dashboard, goal detail, asset flows, transactions, and settings.
- Resolve startup, scene, scheduler, and transition seams explicitly so hidden code does not execute accidentally.
- Preserve the codebase for later re-enablement while preventing feature-flag debt from contaminating the steady-state MVP runtime.
- Keep the first public Apple release free of migration banners, cleanup messaging, and customer-facing transition UX.

## Non-Goals

- Broad code deletion as part of the MVP release program.
- Remote config or server-driven rollout infrastructure.
- Schema redesign for SwiftData, CloudKit, or Room.
- Reintroducing hidden features through debug-only entry points in public builds.
- Customer-facing visionOS launch readiness in this MVP.
- Android public containment for the same release window. Android follow-up is tracked separately after the Apple scope is stable.

## Scope

### Retained Product Surfaces

- Onboarding
- Root dashboard
- Goals list
- Goal detail
- Goal dashboard
- Asset add/edit
- ManageAssetAllocation workspace
- Transaction history
- Settings/About

### Hidden in Public Builds

- Monthly planning
- Execution automation
- Reminder settings and reminder UX
- Notification permission prompts
- Family sharing UI and participant management
- Local bridge sync
- CSV import/export
- Budget calculator and budget-health surfaces
- Forecast and advanced dashboard modules
- Goal comparison
- Shortcuts

Data contract rule: Retired data remains in storage and stays non-destructively preserved; the MVP hides related UI and runtime behavior rather than migrating or deleting records.

## Acceptance Criteria

- Goal lifecycle: A user can create, edit, archive/finish, and delete a goal with name, currency, target amount, start date, and target date. No goal form exposes reminder, planning, or sharing fields in public builds.
- Asset management: A user can add fiat or crypto assets, optionally attach a wallet address and network for crypto tracking, edit allocations, and remove assets. Public builds never show sharing metaphors for allocation management.
- Crypto tracking: Crypto assets surface explicit states: Connecting, Syncing, Connected, Stale, Needs Attention. Last successful values remain visible when refresh fails. Wallet addresses are optional and read-only from a security perspective.
- Manual transactions: A user can add, edit, and review manual transactions. Transaction save updates balances and history only; it does not reschedule reminders or reactivate retired automations.
- Dashboard: The root dashboard and goal dashboard show actual progress, recent activity, explicit stale/error states, and one clear next action. Public builds do not show planning widgets, forecast cards, or custom widget layouts.
- Settings: Settings exposes display currency, appearance, support, and version information. Public diagnostics remains goal-dashboard-local through the retained hard-error diagnostics flow; Settings/About does not expose a separate diagnostics status row in the first Apple MVP. Public settings do not show planning, sharing, bridge, export, reminder, or cleanup-transition controls.
- First-release experience: A first-time production user sees no migration banner, no "What changed in this update" row, no transition help article CTA, and no family-share handoff messaging.
- Route absence: No public route, deep link, scene, Settings row, or startup hook reaches hidden features on iOS or shared Apple code compiled for visionOS.

## Retained Goal Dashboard Contract

Public Apple release mode keeps the goal dashboard, but only as a retained MVP surface. Its next-action system must stay inside the retained Apple feature set and must not reopen planning, forecast, or planner-era history flows.

Allowed public goal-dashboard CTA IDs:

- `retry_data_sync`
- `view_diagnostics`
- `review_activity`
- `create_new_goal`
- `resume_goal`
- `edit_goal`
- `rebalance_allocations`
- `open_allocation_health`
- `add_first_asset`
- `add_first_contribution`
- `add_contribution`
- `log_contribution`
- `refresh_data`
- `continue_last_data`

Disallowed public goal-dashboard CTA IDs and copy themes:

- `plan_this_month`
- `open_forecast`
- `view_goal_history`
- `view_history`
- any copy that tells the user to open Monthly Planning, Forecast, or planner-only recovery screens

Retained goal-dashboard rules:

- Finished goals may offer `review_activity` and `create_new_goal`, but not planner/history destinations.
- Behind-schedule goals may offer `add_contribution` and `edit_goal`, but not planning recovery.
- On-track goals may offer `log_contribution` and `review_activity`, but not forecast exploration.
- `GoalDashboardContract.defaultUtilityActionOrder`, utility-action assembly in `GoalDashboardSceneAssembler`, and `GoalDashboardLegacyWidgetMigration` must all stop emitting disallowed IDs in public Apple mode.
- Legacy dashboard widget types that previously mapped to history must remap to `review_activity` rather than reviving `view_history`.
- Goal-dashboard tests and copy catalogs must defend this retained CTA set directly, including default utility ordering, assembled utility actions, and legacy widget migration outputs.

## Bootstrap Replacement Map

The policy-kernel rollout is not complete until every current Apple startup side effect has an explicit owner and mode boundary. The map below is the required source of truth.

| Current owner | Side effect | Target owner | `release_mvp` | `debug_internal` | Disposition / teardown order |
|---|---|---|---|---|---|
| `CryptoSavingsTrackerApp.init` | `performDeferredCloudStoreCleanupIfNeeded()` | `AppBootstrapPlan.persistenceBootstrap` | Enabled before container open | Enabled | Keep, but route through bootstrap plan first |
| `CryptoSavingsTrackerApp.init` | `performLegacyLocalStoreCleanupIfNeeded()` | `AppBootstrapPlan.persistenceBootstrap` | Enabled before container open | Enabled | Keep, ordered immediately after deferred cleanup |
| `CryptoSavingsTrackerApp.init` task | `cloudKitHealthMonitor.startMonitoring()` | `BootstrapPolicyResolver.monitoringPlan` | Enabled after startup throttle, never before test/preview gating | Enabled | Move out of app root once kernel lands |
| `CryptoSavingsTrackerApp` body | UI-test goal seeding / reset hooks | `BootstrapPolicyResolver.testHarnessPlan` | Disabled | Enabled only for XCTest / UITEST launches | Remain test-only and unreachable in public runtime |
| `CryptoSavingsTrackerApp` body | visual capture routing (`VISUAL_CAPTURE_*`) | `BootstrapPolicyResolver.visualCapturePlan` | Disabled | Enabled only for preview / capture runs | Remain internal-only seam |
| `CryptoSavingsTrackerApp` body | onboarding shell selection | `BootstrapPolicyResolver.rootShellPlan` | Enabled | Enabled | Retained public owner after kernel migration |
| `CryptoSavingsTrackerApp` app delegate router | app-level delegate bridging | `BootstrapPolicyResolver.platformBridgePlan` | Enabled only for retained Apple runtime needs | Enabled | Audit before any hidden-feature delegate is reintroduced |

Kernel rule: after migration, no startup side effect remains implicit in `CryptoSavingsTrackerApp`; each one must belong to one row in this map or be deleted.

## Legacy Navigation Disposition

The old `AppCoordinator` graph still exists in source. Public Apple containment is not complete until its disposition is explicit.

Coordinator-owned route disposition:

| Owner | Route / surface | Public Apple disposition |
|---|---|---|
| `AppCoordinator` | `dashboard`, `goalsList`, `goalDetail`, `assetDetail`, `transactionHistory`, `settings` | Retain only until equivalent retained shell ownership is proven; remove `AppCoordinator` dependency from public views during containment hardening |
| `AppCoordinator` | `monthlyPlanning`, `monthlyPlanningSettings`, `flexAdjustment` | Hidden in public builds; isolate from public navigation and mark debug-only until deleted |
| `SettingsCoordinator` | `notifications`, `monthlyPlanning`, `exportData`, `importData`, `debug` | Hidden in public builds; debug-only or delete |
| `DashboardCoordinator` | `monthlyPlanning`, `flexAdjustment`, `portfolioAnalysis`, `performanceMetrics`, `alerts` | Hidden in public builds; debug-only or delete |

Legacy navigation rules:

- No retained public Apple view may require `@EnvironmentObject AppCoordinator` once containment hardening is complete.
- Route-absence validation must cover both the active root shell and the legacy coordinator graph until the old graph is deleted or isolated.
- Any retained view still coupled to `AppCoordinator` is technical debt to retire before implementation signoff.

## Release Modes

### `release_mvp`

Steady-state public MVP runtime for the first Apple release.

Enabled capabilities:

- `goal_lifecycle`
- `asset_management`
- `crypto_tracking`
- `manual_transactions`
- `root_dashboard`
- `goal_dashboard`
- `onboarding`
- `settings`
- `analytics_adapter`

Disabled capabilities:

- `monthly_planning`
- `execution`
- `reminders`
- `notification_permission_prompts`
- `family_sharing`
- `local_bridge`
- `csv_import_export`
- `budget_modules`
- `forecast_modules`
- `advanced_charts`
- `goal_comparison`
- `shortcuts`

### `debug_internal`

Non-production diagnostics and validation mode.

Rules:

- May expose gated diagnostics and hidden legacy surfaces for engineering verification.
- Cannot redefine the public MVP product contract.

## Implementation Phases

### P0 — Approval and baseline gate

Dates: 2026-04-13 to 2026-04-19

Exit criteria:

- Approve this proposal and release modes.
- Approve bootstrap replacement map.
- Approve visual/state contract and Apple-first scope boundary.
- Create and approve `.review-baselines/current-system-baseline.md`.

### P1 — Policy kernel and manifest containment

Dates: 2026-04-20 to 2026-05-03

Exit criteria:

- BootstrapPolicyResolver and AppBootstrapPlan are the only startup owners.
- Apple route manifests exclude hidden features in public modes.
- Public Apple settings and dashboard surfaces contain no migration or cleanup UX.

### P2 — Mutation-boundary and UX hardening

Dates: 2026-05-04 to 2026-05-17

Exit criteria:

- Scheduler ownership ban is enforced.
- Reminder runtime is cancellation-only.
- Dashboard, goal dashboard, onboarding, and crypto-tracking states match the retained product contract.
- Token-parity review passes.

### P3 — Transition validation and parity hardening

Dates: 2026-05-18 to 2026-05-31

Exit criteria:

- Apple retained-contract smoke tests pass without migration chrome or hidden-feature re-entry.
- Canonical same-tree Apple full regression gate uses `CryptoSavingsTrackerTests`, because the app scheme `CryptoSavingsTracker` is build-only and not configured for the `test` action.
- Android follow-up proposal is authored separately before any Android public MVP release claim.

### P4 — Release gate and staged rollout

Dates: 2026-06-01 to 2026-06-14

Exit criteria:

- Public-mode route absence verified on Apple public surfaces.
- Crash-free and hidden-runtime-no-op dashboards are operational.
- Wave-based rollout criteria and pause triggers are approved for Apple release only.

## Success Metrics

### Primary KPIs

- Activation rate: >= 65% create first goal within 3 days
- Core-loop completion: >= 45% of activated users reach goal -> asset -> transaction or balance sync -> dashboard within 7 days
- 7-day retention: >= 30%
- 30-day retention: >= 15%
- Median time to first value: <= 10 minutes

### Release Health

- Crash-free sessions: >= 99.5%
- Public route absence: 100% of public-mode smoke tests pass
- Retired runtime no-op compliance: No production startup or mutation path schedules retired work
