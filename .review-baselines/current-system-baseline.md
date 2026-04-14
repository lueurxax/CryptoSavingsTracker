# Current System Baseline

Date: 2026-04-13  
Scope: Apple public MVP containment (`iOS + shared Apple code compiled for visionOS`)

## Public MVP Contract

Retained public Apple surfaces:
- Onboarding
- Root dashboard
- Goals list
- Goal detail
- Goal dashboard
- Asset add/edit
- ManageAssetAllocation workspace
- Transaction history
- Settings/About

Hidden in public Apple builds:
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

## First-Release Constraint

This baseline assumes the first public App Store release has no installed customer base.

Public Apple builds therefore must not ship:
- migration banners
- `What changed in this update` cleanup messaging
- transition help article CTAs
- family-share handoff or migration guidance surfaces

## Runtime Containment Rules

- Hidden features remain in source but must be unreachable from public Apple routes, deep links, scenes, settings rows, startup hooks, schedulers, and mutation-boundary side effects.
- Reminder data may remain in storage only as cleanup state; public Apple goal forms and dashboards must not expose reminder controls or messaging.
- Hidden-feature containment is structural, not cosmetic. Public Apple runtime must not schedule or revive retired work.

## Retained Goal Dashboard Boundary

Allowed public next-action IDs:
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

Disallowed public next-action IDs:
- `plan_this_month`
- `open_forecast`
- `view_goal_history`
- `view_history`

Goal-dashboard copy must not direct the user to Monthly Planning, Forecast, or planner-only history surfaces.
`GoalDashboardContract.defaultUtilityActionOrder`, assembled dashboard utilities, and legacy widget migration must all remap history-oriented affordances to retained IDs such as `review_activity`.

## Startup Owner Boundary

Current Apple startup side effects must be explicitly mapped before containment signoff:
- persistence cleanup before container open
- CloudKit health monitoring after startup throttle
- UI-test seeding/reset hooks
- visual capture routing
- root shell selection
- app-delegate platform bridging

No startup side effect should remain implicit at app root once the bootstrap replacement map is implemented.

## Legacy Navigation Boundary

- The legacy `AppCoordinator` graph is not part of the public Apple MVP contract.
- Any hidden routes owned by the old coordinator graph must be debug-only or deleted.
- Retained public Apple views should not depend on `@EnvironmentObject AppCoordinator` once containment hardening is complete.

## Diagnostics Boundary

- Public Apple MVP exposes diagnostics only through the retained goal-dashboard hard-error flow.
- Settings/About does not have a separate diagnostics status row in the first Apple MVP.

## Platform Boundary

- This baseline does not claim Android parity for the same release window.
- Android containment is a separate follow-up scope and must not be cited as done by Apple-only MVP evidence.

## Verification Boundary

- The canonical same-tree Apple full regression gate runs through the `CryptoSavingsTrackerTests` scheme.
- The app scheme `CryptoSavingsTracker` is build-only for this containment baseline and is not the authoritative `test` entrypoint.

## Source of Truth

This baseline matches:
- [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md)
- [GoalDashboardContract.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Models/GoalDashboardContract.swift)
- [GoalDashboardLegacyWidgetMigration.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/GoalDashboardLegacyWidgetMigration.swift)
- [SettingsView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift)
- [DashboardView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/DashboardView.swift)
- [MVPContainmentContractTests.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift)
