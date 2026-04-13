# MVP Feature-Flag Containment Proposal

Status: Approved  
Approved at: 2026-04-12  
Platform: iOS + Android parity  
Source artifact: `state_7_implementation_started.1/lead_orchestrator/1/approved_proposal`

## Executive Summary

Ship CryptoSavingsTracker as a focused personal goal tracker without deleting the broader codebase. Production builds expose only goals, assets, crypto tracking, manual transactions, dashboards, onboarding, and settings; all other capabilities remain in source but are structurally contained behind local release policy flags, route manifests, startup gating, and mutation-boundary rules so hidden features cannot wake up through startup hooks, deep links, background workers, or legacy schedulers.

The user direction is respected: this proposal does not require broad code deletion. However, simple view-level flag hiding is not sufficient for production because the current app still performs retired work during startup, scene registration, background scheduling, and write flows. The resulting effort is intentionally M rather than S-M because the MVP must close those runtime seams while keeping the codebase intact for future re-enablement.

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

## Non-Goals

- Broad code deletion as part of the MVP release program.
- Remote config or server-driven rollout infrastructure.
- Schema redesign for SwiftData, CloudKit, or Room.
- Reintroducing hidden features through debug-only entry points in public builds.
- Customer-facing visionOS launch readiness in this MVP.

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
- Settings: Settings exposes display currency, appearance, support, diagnostics status when allowed, and a persistent "What changed in this update" help row. Public settings do not show planning, sharing, bridge, export, or reminder controls.
- Migration experience: Existing users see a one-time migration banner explaining the focused MVP and linking to a support article. Hidden data is described as preserved, not deleted.
- Route absence: No public route, deep link, scene, bottom-nav item, Settings row, or startup hook reaches hidden features on iOS, macOS, Android, or shared Apple code compiled for visionOS.

## Release Modes

### `release_mvp`

Steady-state public MVP runtime after transition window.

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
- `migration_help_article`

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

### `release_transition_family_share`

Bounded first public MVP release that preserves fail-closed handling for legacy family-share handoff only.

Extra enabled capabilities:

- `family_share_transition_interceptor`

Extra rules:

- May intercept legacy family-share acceptance and show migration guidance.
- Must not expose family-sharing creation, management, refresh, or participant mutation.
- Expires after max 30 days or first maintenance release, whichever comes first.

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
- Approve visual/state contract and migration copy.
- Create and approve `.review-baselines/current-system-baseline.md`.
- Decide FS-TRANSITION-01 teardown timing.

### P1 — Policy kernel and manifest containment

Dates: 2026-04-20 to 2026-05-03

Exit criteria:

- BootstrapPolicyResolver and AppBootstrapPlan are the only startup owners.
- Apple and Android route manifests exclude hidden features in public modes.
- Migration banner and support article destination exist.

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

- FS-TRANSITION-01 is validated as fail-closed only.
- Android parity lands no later than one sprint after iOS retained-contract readiness.
- Migrated-user coach mark and Share Feedback affordance are live if approved.

### P4 — Release gate and staged rollout

Dates: 2026-06-01 to 2026-06-14

Exit criteria:

- Public-mode route absence verified on all platforms.
- Crash-free, migration-signal, and support-signal dashboards are operational.
- Wave-based rollout criteria and pause triggers are approved.

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
