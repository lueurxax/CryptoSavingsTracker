# MVP Feature-Flag Containment Proposal Implementation Audit R2

| Field | Value |
|---|---|
| Proposal | `docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md` |
| Repository Root | `.` |
| Git SHA | `ff1e05a7aaf97e000a2c760c08cb2a935a6386db` |
| Working Tree | `dirty` |
| Audited At | `2026-04-13T23:16:57+0300` |
| Proposal State | `Active (Approved)` |
| Platform Scope | `iOS (shared Apple code compiled for visionOS)` |
| Overall Conformance | `Partial` |
| Overall Readiness | `Not Ready` |
| Audit Confidence | `High` |

## Verdict

Track 1 is now green at the requirement level: every in-scope `REQ-*` item in the proposal is implemented on the audited tree. The previously open gaps from `R1` are closed: the bootstrap map now owns `platformBridgePlan`, the explicit retained crypto-tracking vocabulary is wired into the public asset flow, and the retained smoke suite now passes on the same tree.

The overall verdict still cannot be `Implemented` under this audit model because the required same-tree full regression gate is red. `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=A94EC3F4-A1EA-4A43-8568-8E1DD2CF7611' test` failed with `192 tests in 33 suites` and `19 issues`; the concrete blocking suite is `Wave1UXContractTests`, which still catches raw `.green/.orange/.red/.secondary` colors in hidden `LocalBridgeSyncView`. That regression is outside the public MVP proposal contract, but it still blocks a successful repository-wide readiness verdict.

## Track 0: Proposal Contract Snapshot

### Scope

- Keep only onboarding, dashboard, goals, goal dashboard, assets, manual transactions, and settings public.
- Hide planning, reminders, family sharing, local bridge, CSV import/export, budget modules, forecast modules, comparison, and shortcuts in public builds.
- Enforce containment structurally through route absence, startup gating, runtime policy, and mutation boundaries.

### Locked Decisions

- The first Apple MVP is a containment release, not a code-deletion release.
- Public runtime mode is `release_mvp`; hidden behavior may exist only behind internal/debug seams.
- First public release must not show migration banners, cleanup messaging, or transition UX.
- Goal dashboard remains public, but only with the retained CTA contract.
- Startup ownership must live in the bootstrap plan map.

### Primary User Flows

1. Onboard, create a goal, and land in the retained Apple shell.
2. Add fiat or crypto assets, optionally attach a wallet address, and manage allocations.
3. Review the root dashboard and goal dashboard, then take a retained next action.
4. Add and review manual transactions without waking retired reminder or automation runtime.
5. Open Settings / About without seeing hidden-feature controls or transition chrome.

## Proposal Fidelity / Divergence Inventory

### Matches

- Public Apple shell is constrained to `Dashboard`, `Goals`, and `Settings`.
- Public goal lifecycle, asset flows, manual transactions, dashboard copy, and settings copy match the retained MVP contract.
- Hidden-runtime gating disables reminders, automation, family sharing, notification prompts, and forecast modules in `release_mvp`.
- Bootstrap ownership is now routed through `AppBootstrapPlan`, including the proposal-required `platformBridgePlan`.
- Proposal-defined retained smoke proof exists and passes.

### Divergences

- No requirement-level divergences were found in this revision.

### Ambiguities / Evidence Gaps

- The proposal includes shared Apple code compiled for visionOS, but this audit validated iOS simulator behavior and shared source contracts only.
- The app scheme `CryptoSavingsTracker` is not configured for the `test` action, so the canonical full regression gate had to use `CryptoSavingsTrackerTests`.

## Track 1: Objective Proposal-Conformance Audit

### Requirement Summary

| Status | Count |
|---|---:|
| Implemented | 11 |
| Partially Implemented | 0 |
| Missing | 0 |
| Not Verifiable | 0 |

### Requirement Audit

#### REQ-001 Public Apple shell and route graph expose only retained MVP surfaces
- Proposal Source: `Scope` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:41-65`), `Legacy Navigation Disposition` (`:134-151`), `Acceptance Criteria` (`:78`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence References:
  - `ios/CryptoSavingsTracker/Views/ContentView.swift:10-23`
  - `ios/CryptoSavingsTracker/Views/ContentView.swift:61-84`
  - `ios/CryptoSavingsTrackerTests/GoalDashboardNavigationContractTests.swift:44-89`
  - targeted retained smoke run passed with `GoalDashboardNavigationContractTests` and `PublicMVPHiddenRuntimeContractTests`
- Gap / Note: Public shell ownership is now explicitly limited to dashboard, goals, and settings, and the coordinator contract test proves hidden planner/flex routes are absent from the public graph.

#### REQ-002 Goal lifecycle keeps only retained goal fields and lifecycle actions in public builds
- Proposal Source: `Acceptance Criteria` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:71`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence References:
  - `ios/CryptoSavingsTracker/Views/AddGoalView.swift:325`
  - `ios/CryptoSavingsTracker/Views/AddGoalView.swift:445-449`
  - `ios/CryptoSavingsTracker/Views/AddGoalView.swift:570`
  - `ios/CryptoSavingsTracker/Views/EditGoalView.swift:237-249`
  - `ios/CryptoSavingsTracker/Views/EditGoalView.swift:408-414`
  - `ios/CryptoSavingsTracker/Services/GoalLifecycleService.swift:25-103`
  - targeted retained smoke run passed with `GoalLifecycleServiceTests`
- Gap / Note: Public goal forms stay on retained fields only, and archive / finish / delete explicitly retire legacy reminder runtime before mutating the goal.

#### REQ-003 Asset management supports fiat and crypto, optional wallet tracking, and retained write guards
- Proposal Source: `Acceptance Criteria` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:72`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence References:
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:137-157`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:450-516`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:517-579`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:677-682`
  - `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:137-139`
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift`
- Gap / Note: Fiat remains manual-only, crypto wallet entry is optional, and owner-write enforcement remains in place for shared/read-only contexts.

#### REQ-004 Crypto tracking exposes the retained public state model plus stale fallback
- Proposal Source: `Acceptance Criteria` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:73`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence References:
  - `ios/CryptoSavingsTracker/Models/BalanceState.swift:12-49`
  - `ios/CryptoSavingsTracker/Models/BalanceState.swift:108-130`
  - `ios/CryptoSavingsTracker/ViewModels/AssetViewModel.swift:47-60`
  - `ios/CryptoSavingsTracker/Views/AssetRowView.swift:51-57`
  - `ios/CryptoSavingsTracker/Views/AssetRowView.swift:143-147`
  - `ios/CryptoSavingsTracker/Views/AssetDetailView.swift:31-55`
  - `ios/CryptoSavingsTracker/Views/AssetDetailView.swift:129-133`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:137-157`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:501-516`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift:670-673`
  - `ios/CryptoSavingsTrackerTests/CryptoTrackingVocabularyContractTests.swift:5-22`
  - `ios/CryptoSavingsTrackerTests/BalanceStateTests.swift:6-66`
  - targeted retained smoke run passed with `CryptoTrackingVocabularyContractTests` and `BalanceStateTests`
- Gap / Note: The retained vocabulary is now explicit in model, view-model, add flow, row/detail UI, and source-contract tests. Last-successful-value guidance is also defended directly.

#### REQ-005 Manual transaction flow updates balances and history only and does not reactivate retired runtime
- Proposal Source: `Acceptance Criteria` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:74`), `P2 Exit Criteria` (`:224-225`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence References:
  - `ios/CryptoSavingsTracker/Views/AddTransactionView.swift:161-181`
  - `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift:272-310`
  - `ios/CryptoSavingsTracker/Utilities/NotificationManager.swift:60-64`
  - `ios/CryptoSavingsTracker/Services/AutomationScheduler.swift:35-58`
  - `ios/CryptoSavingsTrackerTests/NotificationManagerTests.swift:35-61`
  - `ios/CryptoSavingsTrackerTests/AutomationSchedulerTests.swift:20-36`
- Gap / Note: Transaction persistence updates transaction/balance history, while reminder and automation schedulers remain structurally gated off in public MVP mode.

#### REQ-006 Root dashboard and first-release experience stay within the retained MVP contract
- Proposal Source: `Acceptance Criteria` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:75-77`), `P1 Exit Criteria` (`:214-216`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence References:
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift:134-173`
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift:197-218`
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift:474-497`
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift:38-64`
- Gap / Note: The retained dashboard contract is explicit (`Portfolio Overview`, `Active Goals`, `Recent Activity`, `Next Step`) and the source contract rejects migration/update chrome.

#### REQ-007 Goal dashboard emits only the retained public CTA set
- Proposal Source: `Retained Goal Dashboard Contract` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:82-116`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence References:
  - `ios/CryptoSavingsTracker/Models/GoalDashboardContract.swift:51-56`
  - `ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift:19-30`
  - `ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift:72-92`
  - `ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift:571-714`
  - `ios/CryptoSavingsTracker/Utilities/GoalDashboardLegacyWidgetMigration.swift:14-99`
  - `ios/CryptoSavingsTrackerTests/GoalDashboardNavigationContractTests.swift:91-115`
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift:204-220`
- Gap / Note: Default utility order, assembled CTA states, and legacy widget migration all stay inside the retained CTA allow-list and no longer revive planner/forecast/history-era actions.

#### REQ-008 Settings / About remains limited to retained MVP preferences and support metadata
- Proposal Source: `Acceptance Criteria` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:76`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-found`
- Evidence References:
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift:19-61`
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift:53`
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift:225-237`
- Gap / Note: Public settings is now reduced to display currency, appearance, support, and version; diagnostics stays dashboard-local as required.

#### REQ-009 `release_mvp` disables hidden runtime capabilities by default
- Proposal Source: `Release Modes` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:155-184`)
- Status: `Implemented`
- Evidence Type: `code`, `tests-run`
- Evidence References:
  - `ios/CryptoSavingsTracker/Utilities/NotificationManager.swift:37-46`
  - `ios/CryptoSavingsTracker/Utilities/NotificationManager.swift:49-64`
  - `ios/CryptoSavingsTracker/Services/AutomationScheduler.swift:35-58`
  - `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareRollout.swift:223-247`
  - `ios/CryptoSavingsTrackerTests/PublicMVPHiddenRuntimeContractTests.swift:6-29`
  - `ios/CryptoSavingsTrackerTests/NotificationManagerTests.swift:35-61`
  - `ios/CryptoSavingsTrackerTests/AutomationSchedulerTests.swift:20-36`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareRolloutTests.swift:17-48`
  - targeted retained smoke run passed with `PublicMVPHiddenRuntimeContractTests`, `NotificationManagerTests`, `AutomationSchedulerTests`, and `FamilyShareRolloutTests`
- Gap / Note: Public MVP mode defaults hidden runtime off and the source/runtime tests now prove that default instead of merely implying it.

#### REQ-010 Bootstrap replacement map is fully implemented and owns all startup side effects
- Proposal Source: `Bootstrap Replacement Map` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:118-132`), `P1 Exit Criteria` (`:214`)
- Status: `Implemented`
- Evidence Type: `code`
- Evidence References:
  - `ios/CryptoSavingsTracker/Utilities/BootstrapPolicyResolver.swift:66-117`
  - `ios/CryptoSavingsTracker/Utilities/BootstrapPolicyResolver.swift:163-210`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:21-33`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift:44-48`
- Gap / Note: `AppBootstrapPlan` now includes `platformBridgePlan`, and the app root asserts that the removed delegate bridge seam stays disabled instead of owning it implicitly.

#### REQ-011 Apple retained-contract smoke tests pass on the audited tree
- Proposal Source: `P3 — Transition validation and parity hardening` (`docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:229-236`)
- Status: `Implemented`
- Evidence Type: `tests-run`
- Evidence References:
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=A94EC3F4-A1EA-4A43-8568-8E1DD2CF7611' -derivedDataPath /tmp/proposal-audit-derived-data.96Y56u test -only-testing:CryptoSavingsTrackerTests/MVPContainmentContractTests -only-testing:CryptoSavingsTrackerTests/PublicMVPHiddenRuntimeContractTests -only-testing:CryptoSavingsTrackerTests/GoalDashboardNavigationContractTests -only-testing:CryptoSavingsTrackerTests/GoalLifecycleServiceTests -only-testing:CryptoSavingsTrackerTests/NotificationManagerTests -only-testing:CryptoSavingsTrackerTests/AutomationSchedulerTests -only-testing:CryptoSavingsTrackerTests/FamilySharing/FamilyShareRolloutTests -only-testing:CryptoSavingsTrackerTests/CryptoTrackingVocabularyContractTests -only-testing:CryptoSavingsTrackerTests/BalanceStateTests`
  - Result: `** TEST SUCCEEDED **`
- Gap / Note: The retained smoke gate that was red in `R1` is now green on the same tree.

## Track 2: Expert Multi-Lens Review

### Lens Scorecard

| Lens | Status | Summary |
|---|---|---|
| Architecture | `Amber` | Proposal architecture is implemented, but repo-wide regression reproducibility is weaker than it should be because the app scheme is not test-enabled. |
| Product | `Green` | No material public-MVP product drift was found after the latest fixes. |
| UI | `Amber` | Hidden `LocalBridgeSyncView` still violates the repo’s semantic color contract and blocks the full suite. |
| UX | `Green` | No material public-MVP UX deviations were found beyond the implemented proposal contract. |
| Readiness | `Red` | Same-tree full regression is red, so the audited tree is not ready for a successful implementation signoff. |

### Expert Findings

#### ARCH-001 Canonical full-regression entry point is still ambiguous
- Severity: `Minor`
- Confidence: `High`
- Related Proposal Items: roll-up gate for successful implementation verdicts
- Evidence Type: `tests-run`
- Evidence References:
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination 'id=A94EC3F4-A1EA-4A43-8568-8E1DD2CF7611' test`
  - Result: `xcodebuild: error: Scheme CryptoSavingsTracker is not currently configured for the test action.`
- Why It Matters: A successful audit requires a clear same-tree full regression gate. Today that gate exists only by convention through `CryptoSavingsTrackerTests`, not through the app scheme a maintainer would reasonably try first.
- Recommended Action: Either configure `CryptoSavingsTracker` for the `test` action or document `CryptoSavingsTrackerTests` as the canonical full gate in repo docs and release checklists.

#### UI-001 Hidden Local Bridge view still hardcodes raw status colors
- Severity: `Major`
- Confidence: `High`
- Related Proposal Items: none directly; shared UI-contract debt outside the public MVP proposal surface
- Evidence Type: `code`, `tests-found`
- Evidence References:
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:282`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:299`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:318`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:965-971`
  - `ios/CryptoSavingsTrackerTests/Wave1UXContractTests.swift:114-133`
- Why It Matters: This screen is hidden from public MVP users, so it is not a proposal-conformance defect. It is still a repository-quality defect because the shared UI contract expects semantic accessible colors, and this one file is enough to sink the full suite.
- Recommended Action: Replace raw `.green`, `.orange`, `.red`, and `.secondary` usages in `LocalBridgeSyncView` with the shared semantic tokens (`AccessibleColors.success`, `.warning`, `.error`, `.secondaryText`) so the hidden surface no longer blocks the engineering gate.

#### READY-001 Same-tree full regression is red, so a successful implementation signoff is still blocked
- Severity: `Critical`
- Confidence: `High`
- Related Proposal Items: successful roll-up requirement for `Overall Conformance = Implemented`
- Evidence Type: `tests-run`
- Evidence References:
  - `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=A94EC3F4-A1EA-4A43-8568-8E1DD2CF7611' -derivedDataPath /tmp/proposal-audit-full-derived-data.xll98C test`
  - Result: `✘ Suite Wave1UXContractTests failed after 0.165 seconds with 12 issues.`
  - Result: `✘ Test run with 192 tests in 33 suites failed after 3.755 seconds with 19 issues.`
  - narrowing evidence from `ios/CryptoSavingsTrackerTests/Wave1UXContractTests.swift:114-133` and `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift:282,299,318,965-971`
- Why It Matters: Under this audit model, all-REQ-green is not enough. A successful implementation verdict also requires passing same-tree full regression evidence, and that gate is currently red.
- Recommended Action: Fix the hidden local-bridge semantic-color regression, rerun the full `CryptoSavingsTrackerTests` gate on the same tree, and only then re-audit for an `Implemented` verdict.

## Verification Log

- `python3 /Users/user/.agents/skills/proposal-implementation-audit/scripts/report_path.py /Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md`
- `git rev-parse HEAD`
- `git status --short`
- `date +%Y-%m-%dT%H:%M:%S%z`
- focused proposal reads for:
  - executive summary
  - goals / scope / acceptance criteria
  - retained goal-dashboard contract
  - bootstrap replacement map
  - release modes
  - phase exit criteria
- focused code reads for:
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift`
  - `ios/CryptoSavingsTracker/Utilities/BootstrapPolicyResolver.swift`
  - `ios/CryptoSavingsTracker/Utilities/MVPContainmentRuntime.swift`
  - `ios/CryptoSavingsTracker/Utilities/NotificationManager.swift`
  - `ios/CryptoSavingsTracker/Services/AutomationScheduler.swift`
  - `ios/CryptoSavingsTracker/Services/GoalLifecycleService.swift`
  - `ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareRollout.swift`
  - `ios/CryptoSavingsTracker/Models/BalanceState.swift`
  - `ios/CryptoSavingsTracker/ViewModels/AssetViewModel.swift`
  - `ios/CryptoSavingsTracker/Views/AddAssetView.swift`
  - `ios/CryptoSavingsTracker/Views/AssetRowView.swift`
  - `ios/CryptoSavingsTracker/Views/AssetDetailView.swift`
  - `ios/CryptoSavingsTracker/Views/AddTransactionView.swift`
  - `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift`
  - `ios/CryptoSavingsTracker/Views/ContentView.swift`
  - `ios/CryptoSavingsTracker/Views/DashboardView.swift`
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift`
  - `ios/CryptoSavingsTracker/Models/GoalDashboardContract.swift`
  - `ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift`
  - `ios/CryptoSavingsTracker/Utilities/GoalDashboardLegacyWidgetMigration.swift`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift`
- focused test reads for:
  - `ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift`
  - `ios/CryptoSavingsTrackerTests/PublicMVPHiddenRuntimeContractTests.swift`
  - `ios/CryptoSavingsTrackerTests/GoalDashboardNavigationContractTests.swift`
  - `ios/CryptoSavingsTrackerTests/CryptoTrackingVocabularyContractTests.swift`
  - `ios/CryptoSavingsTrackerTests/BalanceStateTests.swift`
  - `ios/CryptoSavingsTrackerTests/NotificationManagerTests.swift`
  - `ios/CryptoSavingsTrackerTests/AutomationSchedulerTests.swift`
  - `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareRolloutTests.swift`
  - `ios/CryptoSavingsTrackerTests/Wave1UXContractTests.swift`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=A94EC3F4-A1EA-4A43-8568-8E1DD2CF7611' -derivedDataPath /tmp/proposal-audit-derived-data.96Y56u test -only-testing:CryptoSavingsTrackerTests/MVPContainmentContractTests -only-testing:CryptoSavingsTrackerTests/PublicMVPHiddenRuntimeContractTests -only-testing:CryptoSavingsTrackerTests/GoalDashboardNavigationContractTests -only-testing:CryptoSavingsTrackerTests/GoalLifecycleServiceTests -only-testing:CryptoSavingsTrackerTests/NotificationManagerTests -only-testing:CryptoSavingsTrackerTests/AutomationSchedulerTests -only-testing:CryptoSavingsTrackerTests/FamilySharing/FamilyShareRolloutTests -only-testing:CryptoSavingsTrackerTests/CryptoTrackingVocabularyContractTests -only-testing:CryptoSavingsTrackerTests/BalanceStateTests`  
  Result: `** TEST SUCCEEDED **`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTracker -destination 'id=A94EC3F4-A1EA-4A43-8568-8E1DD2CF7611' -derivedDataPath /tmp/proposal-audit-full-derived-data.XXXXXX test`  
  Result: `xcodebuild: error: Scheme CryptoSavingsTracker is not currently configured for the test action.`
- `xcodebuild -project ios/CryptoSavingsTracker.xcodeproj -scheme CryptoSavingsTrackerTests -destination 'id=A94EC3F4-A1EA-4A43-8568-8E1DD2CF7611' -derivedDataPath /tmp/proposal-audit-full-derived-data.xll98C test`  
  Result: `✘ Suite Wave1UXContractTests failed after 0.165 seconds with 12 issues.`  
  Result: `✘ Test run with 192 tests in 33 suites failed after 3.755 seconds with 19 issues.`

## Recommended Next Actions

- Fix the semantic-color regressions in `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift`.
- Rerun the full `CryptoSavingsTrackerTests` gate on the same tree and require `** TEST SUCCEEDED **` before another implementation audit.
- Optionally harden audit reproducibility by making the app scheme test-enabled or explicitly documenting the canonical full regression scheme.
