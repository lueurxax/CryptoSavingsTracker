# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `proposal-readiness`
- Overall readiness: `Amber`
- Confidence: `High`
- Evidence completeness: `Partial`
- Documents / repo inputs reviewed:
  - [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md)
  - [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R2.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R2.md)
  - [current-system-baseline.md](/Users/user/Documents/CryptoSavingsTracker/.review-baselines/current-system-baseline.md)
  - [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R1.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R1.md)
  - [CryptoSavingsTrackerApp.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift)
  - [Navigation/Coordinator.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Navigation/Coordinator.swift)
  - [GoalDashboardSceneAssembler.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift)
  - [GoalDashboardScreen.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift)
  - [GoalDashboardCopyCatalog.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/GoalDashboardCopyCatalog.swift)
  - [GoalDashboardNextActionResolverTests.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/GoalDashboardNextActionResolverTests.swift)
  - [DashboardComponents.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/DashboardComponents.swift)
  - [TransactionHistoryView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/TransactionHistoryView.swift)
  - [AssetDetailView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/AssetDetailView.swift)
- External sources reviewed:
  - None required
- Build/run attempts:
  - None in this mode
- Remaining blockers:
  - The proposal still lacks a concrete bootstrap replacement map.
  - Retained goal-dashboard actions still leak hidden planning / forecast / history semantics in current repo reality.
  - Legacy navigation ownership is still not explicitly retired or isolated.

## 1. Executive Summary
- The main `R1` blockers are materially closed. The proposal is now Apple-only, customer-facing migration chrome is removed from the public contract, and the reusable baseline exists.
- The remaining issues are narrower and architectural. The updated proposal still does not say how startup ownership is migrated into the promised policy kernel, and it still understates retained-surface drift in the current goal dashboard and legacy navigation graph.
- This is no longer a `Red` proposal, but it is not implementation-clean yet. The next revision should focus on explicit owner migration and retained-surface teardown, not on re-litigating product scope.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | Amber | High | Partial | 0 | 1 | 0 | 0 |
| UX | Amber | High | Partial | 0 | 1 | 0 | 0 |
| iOS Architecture | Amber | High | Partial | 0 | 2 | 0 | 0 |

## 3. Findings by Discipline

### 3.1 UI / UX Findings
- Finding ID: `F-UX-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `MAP-01`, `MAP-02`, `MAP-03`, `MAP-04`, `REAL-01`
  Why it matters:
  The proposal now says public Apple builds hide planning and forecast modules and keep the retained goal dashboard focused on actual progress, activity, and one clear next action. Current repo reality still defends the opposite contract. [GoalDashboardSceneAssembler.swift:652](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift#L652) emits `Plan This Month`, [GoalDashboardSceneAssembler.swift:676](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift#L676) emits `Open Forecast`, [GoalDashboardScreen.swift:600](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L600) tells the user to open Monthly Planning, and [GoalDashboardCopyCatalog.swift:20](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/GoalDashboardCopyCatalog.swift#L20) still says `Plan this month now.` The current tests actively preserve this drift: [GoalDashboardNextActionResolverTests.swift:51](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/GoalDashboardNextActionResolverTests.swift#L51) asserts `plan_this_month` for behind-schedule state.
  Recommended fix:
  Add an explicit retained goal-dashboard contract section to the proposal and retire all hidden-feature CTA/copy IDs from the retained path. Concretely:
  1. Replace `plan_this_month`, `open_forecast`, and history paths that imply planning screens with retained-MVP actions only.
  2. Update the proposal's acceptance criteria to state which exact goal-dashboard CTAs are allowed in public Apple release mode.
  3. Rewrite copy catalog and resolver tests to defend the retained action set instead of planner-era recovery.
  Acceptance criteria:
  No retained goal-dashboard CTA, copy key, or handler references Monthly Planning, Forecast, or non-retained history surfaces in public Apple mode.
  Confidence:
  `High`

### 3.2 iOS Architecture Findings
- Finding ID: `F-ARCH-01`
  Severity: `High`
  Evidence IDs: `DOC-02`, `MAP-05`, `DATA-01`, `DATA-02`, `REAL-02`
  Why it matters:
  The proposal's containment strategy depends on `BootstrapPolicyResolver`, `AppBootstrapPlan`, and an approved bootstrap replacement map, but the document never actually includes that map. Current startup ownership is still spread through [CryptoSavingsTrackerApp.swift:26](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift#L26), [CryptoSavingsTrackerApp.swift:34](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift#L34), [CryptoSavingsTrackerApp.swift:60](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift#L60), and [CryptoSavingsTrackerApp.swift:190](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift#L190): store cleanup, health-monitor startup, UI-test seeding, and visual-capture branching still live at app root. Repo search during this review found no current implementations of `BootstrapPolicyResolver` or `AppBootstrapPlan` under `ios/CryptoSavingsTracker`. Without a concrete owner map, implementers still do not know which startup side effects move into the kernel, which remain app-root, and which are debug/test-only seams.
  Recommended fix:
  Add a proposal section named `Bootstrap Replacement Map` with a table for every current startup owner:
  - current owner
  - side effect
  - target owner
  - release-mode gating
  - debug/test-only disposition
  - teardown order
  Acceptance criteria:
  Every startup side effect currently owned in `CryptoSavingsTrackerApp` is assigned to an explicit target owner and mode in the proposal, and no unresolved startup owner remains outside the map.
  Confidence:
  `High`

- Finding ID: `F-ARCH-02`
  Severity: `High`
  Evidence IDs: `DOC-02`, `NAV-02`, `NAV-03`, `MAP-06`, `MAP-07`, `REAL-03`
  Why it matters:
  The proposal says Apple route manifests exclude hidden features in public mode, but it does not account for the legacy coordinator graph that still ships in the repo. [Navigation/Coordinator.swift:117](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Navigation/Coordinator.swift#L117), [Navigation/Coordinator.swift:215](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Navigation/Coordinator.swift#L215), and [Navigation/Coordinator.swift:329](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Navigation/Coordinator.swift#L329) still own monthly-planning destinations, while retained views such as [TransactionHistoryView.swift:14](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/TransactionHistoryView.swift#L14) and [AssetDetailView.swift:17](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/AssetDetailView.swift#L17) still require `@EnvironmentObject AppCoordinator`. At the same time, the active shell does not install [withNavigationCoordinator()](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Navigation/Coordinator.swift#L365), and [DashboardComponents.swift:626](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/DashboardComponents.swift#L626) opens `TransactionHistoryView(asset:)` directly. That leaves the proposal with an unresolved two-graph state: it never says whether the coordinator graph is deleted, isolated to debug, or migrated into the retained Apple manifest.
  Recommended fix:
  Add an explicit `Legacy Navigation Disposition` subsection:
  1. Enumerate the current coordinator-owned routes.
  2. Mark each as `Retain`, `Delete`, or `Debug-only`.
  3. Remove `AppCoordinator` dependencies from retained public views.
  4. Update route-absence validation to include the old coordinator graph, not only the new root shell.
  Acceptance criteria:
  No retained public Apple view depends on `AppCoordinator`, and no public navigation owner still resolves hidden routes such as monthly planning or monthly planning settings.
  Confidence:
  `High`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict:
  The proposal's product scope is now simpler than the current retained goal-dashboard and navigation code contracts.
  Tradeoff:
  The document became cleaner after `R1`, but the repo still carries planner-era retained actions and a second nav owner that the proposal does not name.
  Decision:
  Treat the Apple-first scope correction as accepted, and focus the next revision on explicit owner teardown/migration rather than on adding more feature-flag prose.
  Owner:
  Proposal author + Apple implementation owner

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P0 | Add the missing `Bootstrap Replacement Map` to the proposal | iOS Architecture | Proposal author | Now | None | Startup owners, side effects, and mode boundaries are explicitly mapped | `F-ARCH-01` |
| P0 | Define and enforce the retained goal-dashboard CTA/copy contract | UX / UI / iOS | Proposal author + dashboard owner | Now | None | No retained goal-dashboard path references planning/forecast/history outside retained MVP surfaces | `F-UX-01` |
| P1 | Add `Legacy Navigation Disposition` and remove `AppCoordinator` from retained public views | iOS Architecture | Apple owner | Next | `F-ARCH-01` owner map helps | Public Apple views no longer depend on the legacy coordinator graph | `F-ARCH-02` |
| P2 | Extend containment tests to cover goal-dashboard CTA IDs/copy and legacy coordinator removal | QA / iOS | Apple owner | Next | P0/P1 design decisions | Regression suite defends the corrected retained contract | `F-UX-01`, `F-ARCH-02` |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Startup containment | Whether all startup side effects have an explicit owner and mode boundary | Bootstrap map exists and is reviewed against `CryptoSavingsTrackerApp` | Do not claim kernel ownership without mapping all current app-root side effects | Before next proposal approval | Hold if any startup owner remains implicit |
| Retained goal-dashboard contract | Whether public Apple next actions stay inside the retained MVP | Resolver IDs, copy keys, and screen handlers contain only retained actions | Do not allow planning/forecast/history leakage through next-action recovery | Before next repeat review | Hold if `plan_this_month`, `open_forecast`, or equivalent copy remains |
| Route-manifest containment | Whether hidden routes are absent across all public Apple nav owners | Legacy coordinator graph is explicitly retired or isolated | Do not validate only the new shell while the old graph still ships | Before implementation signoff | Hold if `AppCoordinator` still owns hidden public routes |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- GAP-01: The reusable baseline exists now, but it does not yet cover startup-owner migration or legacy navigation ownership.
- GAP-02: This review remained code/doc-based and did not run simulator validation for the retained goal-dashboard path.

### Open Questions
- QUESTION-01: Is the legacy coordinator graph meant to be deleted outright, or preserved only for debug/internal tooling?
- QUESTION-02: What is the exact retained goal-dashboard CTA set for Apple public release mode?

## Appendix A. Evidence Pack
- [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R2.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R2.md)
