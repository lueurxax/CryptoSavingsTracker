# MVP Feature-Flag Containment Proposal Implementation Audit R1

| Field | Value |
|---|---|
| Proposal | `docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md` |
| Repository Root | `.` |
| Git SHA | `ff1e05a7aaf97e000a2c760c08cb2a935a6386db` |
| Working Tree | `dirty` |
| Audited At | `2026-04-13T22:45:55+0300` |
| Proposal State | `Active (Approved)` |
| Platform Scope | `iOS (shared Apple code compiled for visionOS)` |
| Overall Conformance | `Not Implemented` |
| Overall Readiness | `Not Ready` |
| Audit Confidence | `High` |

## Verdict

The current tree materially implements public-MVP containment: the retained Apple shell is narrowed, hidden-runtime gates exist, the retained goal-dashboard CTA contract is wired, settings are reduced, and reminder / automation / family-sharing runtime is shut off in `release_mvp`. The proposal is still **not implemented** because one in-scope requirement is currently `Missing` and two others are only `Partially Implemented`.

The hard blocker is proposal-defined proof. `P3` requires Apple retained-contract smoke tests to pass, and the same-tree targeted smoke runs are red today. Separately, the bootstrap replacement map is still incomplete: the proposal requires `BootstrapPolicyResolver.platformBridgePlan`, but startup still owns `@UIApplicationDelegateAdaptor(AppDelegateRouter.self)` directly in `CryptoSavingsTrackerApp`.

This audit was performed against the current dirty local worktree, including uncommitted proposal, runtime, and test changes.

## Proposal Contract

### Scope

- Ship a focused Apple MVP without deleting the broader codebase.
- Keep only onboarding, dashboard, goals, goal dashboard, asset flows, manual transactions, and settings public.
- Hide planning, reminders, family sharing, bridge sync, exports, advanced dashboarding, comparison, and shortcuts in public builds.
- Enforce containment structurally through startup ownership, route absence, runtime policy, and mutation boundaries.

### Locked Decisions

- Feature-flag containment is the production strategy; broad code deletion is explicitly out of scope.
- Public runtime is `release_mvp`; diagnostics and hidden surfaces are restricted to `debug_internal`.
- First public release must show no migration banners, “What changed” rows, transition help CTA, or family-share handoff messaging.
- Goal dashboard remains public, but only with the retained CTA set.
- Startup side effects must move under the bootstrap plan map; no implicit startup owners remain.

### Acceptance Criteria

- Goal lifecycle supports create, edit, archive / finish, and delete using only retained goal fields.
- Asset management supports fiat and crypto, with optional wallet / network for crypto.
- Crypto tracking exposes explicit user-facing states: `Connecting`, `Syncing`, `Connected`, `Stale`, `Needs Attention`.
- Manual transactions affect balances and history only; they do not reactivate reminder / automation runtime.
- Root dashboard and goal dashboard stay within the retained MVP contract and exclude planner / forecast / custom widget paths.
- Settings exposes only display currency, appearance, support, version, and dashboard-local diagnostics.
- Public routes, deep links, scenes, settings rows, and startup hooks do not reach hidden features.

### Test / Evidence Requirements

- Proposal phase exits require:
  - bootstrap ownership consolidation
  - scheduler / reminder shutdown
  - retained dashboard / onboarding / crypto states matching the product contract
  - Apple retained-contract smoke tests passing without migration chrome or hidden-feature re-entry

### Explicit Exclusions

- No remote config rollout system.
- No schema redesign.
- No public Android containment in this release window.
- No customer-facing visionOS launch readiness claim.
- No reintroduction of hidden features through debug-only seams in public builds.

### Primary User Flows

1. Onboard, create a goal, and land in the retained MVP shell.
2. Add fiat or crypto assets, optionally attach a wallet address, and manage allocations.
3. Review root dashboard and goal dashboard, then take a retained next action.
4. Add and review manual transactions without waking retired runtime.
5. Open Settings / About without seeing hidden-feature controls or transition chrome.

## Proposal Fidelity / Divergence Inventory

### Matches

- Public Apple shell is constrained to dashboard, goals, and settings.
- Legacy planner / forecast / comparison routes are absent from the public coordinator graph.
- Goal dashboard utility actions and next actions stay inside the retained CTA allow-list.
- `release_mvp` disables family sharing, reminders, notification prompts, automation scheduling, and forecast modules.
- Settings / About is reduced to preferences, support, and version.

### Divergences

- Bootstrap ownership is not fully consolidated because `platformBridgePlan` is missing and app delegate bridging still lives in the app root.
- The retained crypto flow does not surface the proposal’s explicit public state vocabulary.
- Proposal-required Apple retained smoke tests do not currently pass on the audited tree.

### Ambiguities / Evidence Gaps

- The proposal mentions shared Apple code compiled for visionOS, but this audit validated iOS simulator behavior and shared code paths only.
- No successful same-tree full regression gate was run because the proposal’s targeted retained smoke gate already failed, which prevents a successful overall verdict under the audit rules.

## Requirement Summary

| Status | Count |
|---|---:|
| Implemented | 8 |
| Partially Implemented | 2 |
| Missing | 1 |
| Not Verifiable | 0 |

## Requirement Audit

### REQ-001 Public Apple shell and route graph expose only retained MVP surfaces
- Proposal Source: `Scope` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:41-65`), `Legacy Navigation Disposition` (`:134-151`), `Acceptance Criteria` (`:78`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/ContentView.swift:10-15`
  - `ios/CryptoSavingsTracker/Views/ContentView.swift:65-83`
  - `ios/CryptoSavingsTracker/Navigation/Coordinator.swift:114-123`
  - `ios/CryptoSavingsTrackerTests/GoalDashboardNavigationContractTests.swift:44-89`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=A94EC3F4-A1EA-4A43-8568-8E1DD2CF7611' -derivedDataPath /tmp/proposal-audit-derived-data.XXXXXX test -only-testing:CryptoSavingsTrackerTests/PublicMVPHiddenRuntimeContractTests -only-testing:CryptoSavingsTrackerTests/GoalDashboardNavigationContractTests -only-testing:CryptoSavingsTrackerTests/NotificationManagerTests -only-testing:CryptoSavingsTrackerTests/AutomationSchedulerTests -only-testing:CryptoSavingsTrackerTests/GoalLifecycleServiceTests -only-testing:CryptoSavingsTrackerTests/FamilySharing/FamilyShareRolloutTests` executed with `GoalDashboardNavigationContractTests` passing.
- Gap / Note: The active public shell is limited to `Dashboard`, `Goals`, and `Settings`, and the public coordinator graph does not expose planner-era routes.

### REQ-002 Goal lifecycle keeps only retained goal fields and lifecycle actions in public builds
- Proposal Source: `Acceptance Criteria` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:71-72`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/AddGoalView.swift:362-452`
  - `ios/CryptoSavingsTracker/Views/AddGoalView.swift:570-575`
  - `ios/CryptoSavingsTracker/Views/EditGoalView.swift:212-285`
  - `ios/CryptoSavingsTracker/Views/EditGoalView.swift:401-415`
  - `ios/CryptoSavingsTracker/Views/EditGoalView.swift:597-625`
  - `ios/CryptoSavingsTracker/Services/GoalLifecycleService.swift:25-102`
  - `ios/CryptoSavingsTrackerTests/GoalLifecycleServiceTests.swift:26-95`
  - `xcodebuild ... -only-testing:CryptoSavingsTrackerTests/GoalLifecycleServiceTests ...` executed with the suite passing.
- Gap / Note: Public goal forms expose retained fields only: name, currency, target amount, deadline, and start date. Archive / finish / delete flows explicitly clear retired reminder state instead of reactivating old runtime.

### REQ-003 Asset management supports fiat and crypto, optional wallet tracking, and retained write guards
- Proposal Source: `Acceptance Criteria` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:72-73`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:139-144`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:173-188`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:476-555`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:647-648`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:651-656`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:726-734`
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift:88-101`
- Gap / Note: Fiat assets stay manual-only, crypto assets can omit wallet configuration, and write access remains guarded for shared / read-only contexts.

### REQ-004 Crypto tracking exposes the retained public state model plus stale fallback
- Proposal Source: `Acceptance Criteria` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:73`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/ViewModels/AssetViewModel.swift:43-95`
  - `ios/CryptoSavingsTracker/ViewModels/AssetViewModel.swift:143-173`
  - `ios/CryptoSavingsTracker/Models/BalanceState.swift:11-58`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:476-555`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:726-734`
  - `rg -n "Connecting|Syncing|Connected|Needs Attention|Stale" ios/CryptoSavingsTracker/Views/AssetRowView.swift ios/CryptoSavingsTracker/Views/AssetDetailView.swift ios/CryptoSavingsTracker/Views/AddAssetView.swift ios/CryptoSavingsTracker/ViewModels/AssetViewModel.swift ios/CryptoSavingsTracker/Models/BalanceState.swift ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift` returned only `ios/CryptoSavingsTracker/Models/BalanceState.swift:50`.
- Gap / Note: Optional wallet configuration and stale-data fallback exist, but the public retained asset flow does not prove the explicit state vocabulary promised by the proposal. The current retained state model is still `loading / loaded / error` with `cached` and `offline` wording.

### REQ-005 Manual transaction flow updates balances and history only and does not reactivate retired runtime
- Proposal Source: `Acceptance Criteria` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:74`), `P2 Exit Criteria` (`:224-225`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/TransactionHistoryView.swift:33-111`
  - `ios/CryptoSavingsTracker/Views/AddTransactionView.swift:161-177`
  - `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:255-315`
  - `ios/CryptoSavingsTracker/Services/AutomationScheduler.swift:36-38`
  - `ios/CryptoSavingsTracker/Services/AutomationScheduler.swift:57-59`
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift:225-234`
  - `ios/CryptoSavingsTrackerTests/AutomationSchedulerTests.swift:20-36`
  - `xcodebuild ... -only-testing:CryptoSavingsTrackerTests/AutomationSchedulerTests ...` executed with the suite passing.
- Gap / Note: Transaction creation writes the transaction, adjusts allocation state when needed, and posts local refresh notifications. The audited transaction path contains no reminder scheduling or automation scheduling calls, and public MVP scheduling is hard-gated off.

### REQ-006 Root dashboard and first-release experience stay within the retained MVP contract
- Proposal Source: `Acceptance Criteria` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:75-77`), `P1 Exit Criteria` (`:214-216`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift:134-173`
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift:197-223`
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift:230-242`
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift:474-499`
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift:38-74`
- Gap / Note: The root dashboard is fixed to the retained contract (`Portfolio Overview`, `Active Goals`, `Recent Activity`, `Next Step`) and no migration banner / transition row is present in the inspected public dashboard or settings surfaces.

### REQ-007 Goal dashboard emits only the retained public CTA set
- Proposal Source: `Retained Goal Dashboard Contract` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:82-116`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Models/GoalDashboardContract.swift:51-56`
  - `ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift:19-38`
  - `ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift:64-91`
  - `ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift:224-243`
  - `ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift:511-715`
  - `ios/CryptoSavingsTracker/Utilities/GoalDashboardLegacyWidgetMigration.swift:81-97`
  - `ios/CryptoSavingsTrackerTests/GoalDashboardNavigationContractTests.swift:91-115`
  - `xcodebuild ... -only-testing:CryptoSavingsTrackerTests/GoalDashboardNavigationContractTests ...` executed with the suite passing.
- Gap / Note: Forecast assembly is structurally disabled in public mode, default utility ordering is retained-only, and legacy widget migration remaps history-style widgets to `review_activity`.

### REQ-008 Settings / About remains limited to retained MVP preferences and support metadata
- Proposal Source: `Acceptance Criteria` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:76`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence:
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:20-42`
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift:210-223`
- Gap / Note: Settings shows only display currency, appearance, support, and version. Diagnostics remains dashboard-local rather than becoming a separate settings status surface.

### REQ-009 `release_mvp` disables hidden runtime capabilities by default
- Proposal Source: `Release Modes` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:155-184`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/MVPContainmentRuntime.swift:8-50`
  - `ios/CryptoSavingsTracker/Utilities/NotificationManager.swift:37-47`
  - `ios/CryptoSavingsTracker/Utilities/NotificationManager.swift:49-64`
  - `ios/CryptoSavingsTracker/Utilities/NotificationManager.swift:149-153`
  - `ios/CryptoSavingsTracker/Utilities/NotificationManager.swift:199-203`
  - `ios/CryptoSavingsTracker/Utilities/NotificationManager.swift:235-239`
  - `ios/CryptoSavingsTracker/Services/AutomationScheduler.swift:36-38`
  - `ios/CryptoSavingsTracker/Services/AutomationScheduler.swift:57-59`
  - `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareRollout.swift:210-246`
  - `ios/CryptoSavingsTrackerTests/NotificationManagerTests.swift:35-61`
  - `ios/CryptoSavingsTrackerTests/AutomationSchedulerTests.swift:20-36`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareRolloutTests.swift:17-48`
  - `xcodebuild ... -only-testing:CryptoSavingsTrackerTests/NotificationManagerTests -only-testing:CryptoSavingsTrackerTests/AutomationSchedulerTests -only-testing:CryptoSavingsTrackerTests/FamilySharing/FamilyShareRolloutTests ...` executed with all three suites passing.
- Gap / Note: Public MVP defaults hidden runtime off for family sharing, prompts, reminder scheduling, automation scheduling, and forecast modules. The negative source test for this area exists but currently fails for its own repository-path bug, so it is not needed for positive proof.

### REQ-010 Bootstrap replacement map is fully implemented and owns all startup side effects
- Proposal Source: `Bootstrap Replacement Map` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:118-132`), `P1 Exit Criteria` (`:214`)
- Status: `Partially Implemented`
- Evidence Type: `code`
- Evidence:
  - `ios/CryptoSavingsTracker/Utilities/BootstrapPolicyResolver.swift:66-153`
  - `ios/CryptoSavingsTracker/Utilities/BootstrapPolicyResolver.swift:156-203`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:21-31`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:43-47`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:166-184`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:428`
  - `rg -n "platformBridgePlan|UIApplicationDelegateAdaptor|AppDelegateRouter" ios/CryptoSavingsTracker/Utilities/BootstrapPolicyResolver.swift ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift`
- Gap / Note: `AppBootstrapPlan` now owns persistence cleanup, monitoring, UI-test harness, visual capture, and root shell selection. The proposal-required `platformBridgePlan` does not exist, and app-level delegate bridging still lives directly in `CryptoSavingsTrackerApp`.

### REQ-011 Apple retained-contract smoke tests pass on the audited tree
- Proposal Source: `P3 — Transition validation and parity hardening` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:229-236`)
- Status: `Missing`
- Evidence Type: `tests-run`
- Evidence:
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=A94EC3F4-A1EA-4A43-8568-8E1DD2CF7611' -derivedDataPath /tmp/proposal-audit-derived-data.XXXXXX test -only-testing:CryptoSavingsTrackerTests/MVPContainmentContractTests` failed with 1 issue at `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift:207`
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift:198-208`
  - `ios/CryptoSavingsTrackerTests/GoalDashboardNextActionResolverTests.swift:112`
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=A94EC3F4-A1EA-4A43-8568-8E1DD2CF7611' -derivedDataPath /tmp/proposal-audit-derived-data.XXXXXX test -only-testing:CryptoSavingsTrackerTests/PublicMVPHiddenRuntimeContractTests -only-testing:CryptoSavingsTrackerTests/GoalDashboardNavigationContractTests -only-testing:CryptoSavingsTrackerTests/NotificationManagerTests -only-testing:CryptoSavingsTrackerTests/AutomationSchedulerTests -only-testing:CryptoSavingsTrackerTests/GoalLifecycleServiceTests -only-testing:CryptoSavingsTrackerTests/FamilySharing/FamilyShareRolloutTests` failed with 1 issue in `PublicMVPHiddenRuntimeContractTests`
  - `ios/CryptoSavingsTrackerTests/PublicMVPHiddenRuntimeContractTests.swift:29-37`
- Gap / Note: The proposal explicitly requires passing retained smoke tests, and that proof is absent on the current tree. One failure is an over-broad assertion against another test file’s hidden-ID fixture, and the other is a broken repository-root helper; both still count as failing same-tree smoke evidence until fixed and rerun.

## Expert Findings

### ARCH-001 Bootstrap ownership remains split between the policy kernel and the app root
- Severity: `Major`
- Confidence: `High`
- Related Proposal Items: `REQ-010`, bootstrap replacement map
- Evidence Type: `code`
- Evidence References:
  - `ios/CryptoSavingsTracker/Utilities/BootstrapPolicyResolver.swift:66-203`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:21-31`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:24`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:428`
- Why It Matters: The proposal makes startup ownership a locked architectural decision. Leaving app delegate bridging outside the bootstrap map preserves exactly the kind of implicit startup seam the proposal is trying to eliminate.
- Recommended Action: Add the missing `platformBridgePlan` owner and move app-level delegate bridging under the bootstrap plan, or explicitly amend the proposal if delegate routing is intentionally excluded from kernel ownership.

### PROD-001 The retained crypto-tracking contract overstates what the public flow currently proves
- Severity: `Major`
- Confidence: `High`
- Related Proposal Items: `REQ-004`, `P2` retained product contract
- Evidence Type: `code`
- Evidence References:
  - `ios/CryptoSavingsTracker/ViewModels/AssetViewModel.swift:43-95`
  - `ios/CryptoSavingsTracker/Models/BalanceState.swift:11-58`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:476-555`
- Why It Matters: Crypto tracking is one of the core retained MVP jobs. The proposal promises a specific public state model, but the current retained flow only proves generic loading / cached / offline behavior.
- Recommended Action: Decide whether the shipped product contract is the explicit state vocabulary or the current generic balance-state model. Then align code, tests, and proposal to one contract.

### UI-001 Retained asset surfaces do not expose the promised explicit crypto status labels
- Severity: `Major`
- Confidence: `Medium`
- Related Proposal Items: `REQ-004`
- Evidence Type: `code`
- Evidence References:
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:476-555`
  - `ios/CryptoSavingsTracker/Views/AssetRowView.swift`
  - `ios/CryptoSavingsTracker/Views/AssetDetailView.swift`
  - `rg -n "Connecting|Syncing|Connected|Needs Attention|Stale" ios/CryptoSavingsTracker/Views/AssetRowView.swift ios/CryptoSavingsTracker/Views/AssetDetailView.swift ios/CryptoSavingsTracker/Views/AddAssetView.swift ios/CryptoSavingsTracker/ViewModels/AssetViewModel.swift ios/CryptoSavingsTracker/Models/BalanceState.swift ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift`
- Why It Matters: This is a UI-level contract difference, not just an internal model difference. A user cannot see the proposed retained status system in the audited asset UI.
- Recommended Action: Add explicit retained status presentation to the asset row / detail flow, or simplify the proposal so it matches the actual UI that is intended to ship.

### UX-001 Current stale / degraded crypto messaging is more technical and less task-oriented than the proposal contract
- Severity: `Major`
- Confidence: `Medium`
- Related Proposal Items: `REQ-004`
- Evidence Type: `code`
- Evidence References:
  - `ios/CryptoSavingsTracker/ViewModels/AssetViewModel.swift:91-95`
  - `ios/CryptoSavingsTracker/Models/BalanceState.swift:27-47`
- Why It Matters: The proposal’s retained states imply a user-facing recovery model. Today the user gets `cached`, `offline`, and `Some balance data may be stale`, which communicates data origin but not the retained task state the proposal promised.
- Recommended Action: Align stale / degraded copy and recovery affordances with a single retained UX model, then defend it with explicit source tests or runtime UI tests.

### READY-001 Proposal-defined retained smoke proof is currently red
- Severity: `Critical`
- Confidence: `High`
- Related Proposal Items: `REQ-011`, `P3` exit criteria
- Evidence Type: `tests-run`
- Evidence References:
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift:198-208`
  - `ios/CryptoSavingsTrackerTests/GoalDashboardNextActionResolverTests.swift:112`
  - `ios/CryptoSavingsTrackerTests/PublicMVPHiddenRuntimeContractTests.swift:29-37`
  - both targeted `xcodebuild` smoke commands listed in the Verification Log below
- Why It Matters: Even if most runtime containment is present, the proposal explicitly requires passing retained smoke proof before implementation signoff. That proof is absent right now, so the repository is not ready for an “Implemented” claim.
- Recommended Action: Fix the failing smoke tests, rerun the retained smoke suite on the same tree, and only then run the canonical full regression gate needed for a successful overall verdict.

## Verification Log

- `python3 /Users/user/.agents/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md`
- `git rev-parse HEAD`
- `git status --short`
- `date +%Y-%m-%dT%H:%M:%S%z`
- `sed -n '1,240p' /Users/user/.agents/skills/proposal-implementation-audit/SKILL.md`
- `nl -ba docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md | sed -n '214,245p'`
- Focused proposal reads of `docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md` covering summary, scope, acceptance criteria, retained goal-dashboard contract, bootstrap map, release modes, and phase exits.
- Focused code reads across:
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift`
  - `ios/CryptoSavingsTracker/Utilities/BootstrapPolicyResolver.swift`
  - `ios/CryptoSavingsTracker/Utilities/MVPContainmentRuntime.swift`
  - `ios/CryptoSavingsTracker/Utilities/NotificationManager.swift`
  - `ios/CryptoSavingsTracker/Services/AutomationScheduler.swift`
  - `ios/CryptoSavingsTracker/Services/GoalLifecycleService.swift`
  - `ios/CryptoSavingsTracker/Views/ContentView.swift`
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift`
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift`
  - `ios/CryptoSavingsTracker/Views/AddGoalView.swift`
  - `ios/CryptoSavingsTracker/Views/EditGoalView.swift`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift`
  - `ios/CryptoSavingsTracker/Views/AddTransactionView.swift`
  - `ios/CryptoSavingsTracker/Views/TransactionHistoryView.swift`
  - `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift`
  - `ios/CryptoSavingsTracker/Models/GoalDashboardContract.swift`
  - `ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift`
  - `ios/CryptoSavingsTracker/Utilities/GoalDashboardLegacyWidgetMigration.swift`
  - `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareRollout.swift`
- Focused test reads across:
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift`
  - `ios/CryptoSavingsTrackerTests/PublicMVPHiddenRuntimeContractTests.swift`
  - `ios/CryptoSavingsTrackerTests/GoalDashboardNavigationContractTests.swift`
  - `ios/CryptoSavingsTrackerTests/AutomationSchedulerTests.swift`
  - `ios/CryptoSavingsTrackerTests/NotificationManagerTests.swift`
  - `ios/CryptoSavingsTrackerTests/GoalLifecycleServiceTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareRolloutTests.swift`
- `rg -n "platformBridgePlan|UIApplicationDelegateAdaptor|AppDelegateRouter" ios/CryptoSavingsTracker/Utilities/BootstrapPolicyResolver.swift ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift`
- `rg -n "Connecting|Syncing|Connected|Needs Attention|Stale" ios/CryptoSavingsTracker/Views/AssetRowView.swift ios/CryptoSavingsTracker/Views/AssetDetailView.swift ios/CryptoSavingsTracker/Views/AddAssetView.swift ios/CryptoSavingsTracker/ViewModels/AssetViewModel.swift ios/CryptoSavingsTracker/Models/BalanceState.swift ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift`
- `rg -n "scheduleReminders|scheduleAutomationNotifications|checkAndExecuteAutomation|NotificationManager|AutomationScheduler|addTransaction|createTransaction|saveTransaction" ios/CryptoSavingsTracker/Views/AddTransactionView.swift ios/CryptoSavingsTracker/Services ios/CryptoSavingsTracker/ViewModels ios/CryptoSavingsTracker/Repositories`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=A94EC3F4-A1EA-4A43-8568-8E1DD2CF7611' -derivedDataPath /tmp/proposal-audit-derived-data.JeKsVw test -only-testing:CryptoSavingsTrackerTests/MVPContainmentContractTests`  
  Result: `** TEST FAILED **`; `MVPContainmentContractTests` failed with 1 issue at `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift:207`.
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=A94EC3F4-A1EA-4A43-8568-8E1DD2CF7611' -derivedDataPath /tmp/proposal-audit-derived-data.XXXXXX test -only-testing:CryptoSavingsTrackerTests/PublicMVPHiddenRuntimeContractTests -only-testing:CryptoSavingsTrackerTests/GoalDashboardNavigationContractTests -only-testing:CryptoSavingsTrackerTests/NotificationManagerTests -only-testing:CryptoSavingsTrackerTests/AutomationSchedulerTests -only-testing:CryptoSavingsTrackerTests/GoalLifecycleServiceTests -only-testing:CryptoSavingsTrackerTests/FamilySharing/FamilyShareRolloutTests`  
  Result: `** TEST FAILED **`; `GoalDashboardNavigationContractTests`, `NotificationManagerTests`, `AutomationSchedulerTests`, `GoalLifecycleServiceTests`, and `FamilyShareRolloutTests` passed; `PublicMVPHiddenRuntimeContractTests` failed because its `repositoryRoot()` helper resolves `/Users/user/Documents/CryptoSavingsTracker/ios` instead of the repository root.

## Recommended Next Actions

- Fix the retained smoke suite before claiming implementation complete:
  - narrow `MVPContainmentContractTests` so it validates runtime / public contract instead of forbidding hidden IDs inside unrelated test fixtures
  - fix `PublicMVPHiddenRuntimeContractTests.repositoryRoot()` to resolve the actual repository root
- Complete the bootstrap map by adding `platformBridgePlan` ownership or explicitly revising the proposal’s startup-owner contract.
- Either implement the retained explicit crypto state model in public asset UI or downgrade the proposal to the simpler `loading / cached / offline` model the code currently proves.
- After those fixes, rerun the retained smoke gate and then the repository’s canonical full regression gate on the same tree before attempting another successful audit verdict.
