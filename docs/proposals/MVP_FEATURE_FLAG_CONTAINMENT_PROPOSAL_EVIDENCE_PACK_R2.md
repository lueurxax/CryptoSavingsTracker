# Evidence Pack

## Repeat Review Freshness Note
- This is a repeat `proposal-readiness` review of [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md).
- The proposal was edited after [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R1.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R1.md), and `.review-baselines/current-system-baseline.md` now exists.
- This round reuses the `R1` product constraint, but refreshes the affected Apple-only slices that changed materially: scope/baseline, retained goal-dashboard actions, startup ownership, and legacy navigation ownership.

## A. Repo-Local Proposal / Document Inventory
| Evidence ID | Source / Path / Artifact | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|
| DOC-01 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md) | 2026-04-13 | High | The proposal is now Apple-only, removes customer-facing migration UX, and adds a first-release no-migration contract. | Closed `R1` findings could be incorrectly carried forward. | Confirms the main product/scope correction. |
| DOC-02 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md) | 2026-04-13 | High | The proposal still depends on `BootstrapPolicyResolver`, `AppBootstrapPlan`, route-manifest containment, and Apple retained-contract smoke tests. | Architecture gaps could be understated. | Core source for remaining architecture review. |
| DOC-03 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R1.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R1.md) | 2026-04-13 | High | `R1` blockers were Apple-first scope, removal of migration UX, and baseline creation. | The repeat review could restate already-closed issues. | Establishes what changed since `R1`. |

## B. Reusable Baseline Inputs
| Evidence ID | Artifact / Slice | Status (`Reused | Partially refreshed | Missing`) | Covered Surfaces | Verified On | Confidence | Freshness Notes | Relevance |
|---|---|---|---|---|---|---|---|
| BASE-01 | [current-system-baseline.md](/Users/user/Documents/CryptoSavingsTracker/.review-baselines/current-system-baseline.md) | `Partially refreshed` | Apple public MVP contract, first-release constraint, platform boundary | 2026-04-13 | High | Baseline is now present and aligned with the updated proposal, but it does not cover retained goal-dashboard CTA drift, startup-owner migration, or legacy coordinator ownership. | Keeps evidence completeness at `Partial`. |

## C. Scope, Out-of-Scope, and Intentional Deferrals
- In scope:
  - Apple-only public MVP containment in the updated proposal
  - Current Apple retained goal-dashboard contract
  - Current Apple startup ownership
  - Current Apple navigation ownership for retained asset / transaction flows
- Out of scope:
  - Android follow-up scope
  - Runtime simulator validation
  - CloudKit migration proposal family
- Deferred intentionally:
  - Broad dead-code inventory for all hidden features not attached to retained public flows
- Assumptions:
  - The first public App Store release still has no installed customer base.
  - Review should focus on proposal/code alignment for the Apple public slice.
- Open questions:
  - Should the legacy `AppCoordinator` graph be removed or isolated as debug-only?
  - Should goal-dashboard next actions be simplified to only retained MVP affordances?
- Blockers:
  - The proposal still lacks a concrete bootstrap replacement map.
  - The retained goal dashboard still carries hidden-feature CTAs/copy in current repo reality.

## D. Affected Screens / Navigation / Entry-Point Slice
| Evidence ID | Screen / Surface / Entry Point | Source (`Baseline | Targeted refresh | Proposal`) | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|---|
| NAV-01 | [ContentView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/ContentView.swift) | `Targeted refresh` | 2026-04-13 | High | Active Apple root shell is now a simple Dashboard / Goals / Settings shell. | Public-root containment could be misread if a second nav owner still matters. | Confirms the main Apple shell is cleaner than `R1`. |
| NAV-02 | [DashboardComponents.swift:623](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/DashboardComponents.swift#L623) | `Targeted refresh` | 2026-04-13 | High | A retained dashboard sheet still opens [TransactionHistoryView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/TransactionHistoryView.swift) directly. | Retained-flow ownership seams could be missed. | Ties retained dashboard UI to legacy nav dependencies. |
| NAV-03 | [Navigation/Coordinator.swift:298](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Navigation/Coordinator.swift#L298) | `Targeted refresh` | 2026-04-13 | High | Legacy coordinator graph still owns destinations for `monthlyPlanning` and `monthlyPlanningSettings`. | Route-containment claims could be overstated. | Core evidence for the legacy navigation-owner finding. |

## E. Impacted Modules / Code-Path Map
| Evidence ID | File Path / Module / Symbol | Layer | Role in Flow | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|---|---|
| MAP-01 | [GoalDashboardSceneAssembler.swift:649](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift#L649) | Scene assembly | Retained goal dashboard next actions | 2026-04-13 | High | The retained goal dashboard still emits `plan_this_month` and `open_forecast` CTAs. | Proposal could overstate hidden-feature removal in a retained surface. | Core evidence for goal-dashboard contract drift. |
| MAP-02 | [GoalDashboardScreen.swift:600](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L600) | Screen behavior | Retained goal dashboard action handling | 2026-04-13 | High | `plan_this_month` still tells the user to open Monthly Planning, and `view_goal_history` still references planning/history screens. | Hidden-feature references could survive in public UX. | Confirms the drift is user-visible, not just internal action IDs. |
| MAP-03 | [GoalDashboardNextActionResolverTests.swift:51](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/GoalDashboardNextActionResolverTests.swift#L51) | Tests | Contract enforcement | 2026-04-13 | High | Tests still assert that behind-schedule state resolves to `plan_this_month`. | The planner CTA could be inadvertently preserved by regression coverage. | Shows the current repo defends the wrong retained CTA contract for the updated proposal. |
| MAP-04 | [GoalDashboardCopyCatalog.swift:20](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/GoalDashboardCopyCatalog.swift#L20) | Copy catalog | Retained goal dashboard copy | 2026-04-13 | High | Copy still says `Plan this month now.` | Planner-era messaging may remain even if UI chrome is cleaned up elsewhere. | Confirms content drift beyond resolver IDs. |
| MAP-05 | [CryptoSavingsTrackerApp.swift:26](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift#L26) and [CryptoSavingsTrackerApp.swift:180](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift#L180) | App root | Startup ownership | 2026-04-13 | High | App root still directly owns store cleanup, health-monitor startup, UI-test bootstrap, and visual-capture flow branching. | Proposal's policy-kernel strategy could be under-specified. | Core evidence for the bootstrap-map finding. |
| MAP-06 | [Navigation/Coordinator.swift:76](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Navigation/Coordinator.swift#L76) and [Navigation/Coordinator.swift:205](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Navigation/Coordinator.swift#L205) | Navigation ownership | Legacy retained/retired route graph | 2026-04-13 | High | `AppCoordinator`, `SettingsCoordinator`, and `DashboardCoordinator` still own monthly-planning and monthly-planning-settings destinations. | Hidden routes may remain structurally alive outside the new shell. | Core evidence for the legacy navigation-owner finding. |
| MAP-07 | [TransactionHistoryView.swift:14](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/TransactionHistoryView.swift#L14) and [AssetDetailView.swift:17](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/AssetDetailView.swift#L17) | Retained views | Legacy nav dependency | 2026-04-13 | High | Retained views still require `@EnvironmentObject AppCoordinator`. | Retained public flows remain coupled to the old route graph. | Confirms the coordinator is not isolated to hidden views only. |

## F. Data / API / Persistence / Auth Touchpoints
| Evidence ID | Touchpoint | File / Module / Doc | Direction | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|---|---|
| DATA-01 | Startup persistence cleanup | [CryptoSavingsTrackerApp.swift:34](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift#L34) | App launch -> persistence | 2026-04-13 | High | Store cleanup still happens at app-root startup before any policy kernel exists. | Startup decomposition could break persistence invariants if moved blindly. | Shows why the bootstrap map must be explicit. |
| DATA-02 | CloudKit health monitoring | [CryptoSavingsTrackerApp.swift:60](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift#L60) | App launch -> monitoring | 2026-04-13 | High | Health monitoring is still launched directly from app root. | Policy-kernel ownership could be misassigned. | Another startup side effect the proposal must map. |

## G. Current Host-System Integration Surfaces
| Evidence ID | Surface / Seam / Owner | Source (`Baseline | Targeted refresh | Current repo`) | Verified On | Confidence | Key Fact | Conflict / Proposal Risk | Relevance |
|---|---|---|---|---|---|---|---|
| INT-01 | Goal dashboard next-action contract | `Current repo` | 2026-04-13 | High | Retained goal dashboard still depends on planner/forecast/history action states and copy. | Conflicts with hidden-feature contract in the updated proposal. | Drives the top remaining proposal issue. |
| INT-02 | Startup ownership | `Current repo` | 2026-04-13 | High | App root remains the real startup owner; the proposal names a future kernel but not the migration map. | Makes the core containment mechanism underspecified. | Drives the bootstrap-map finding. |
| INT-03 | Legacy navigation coordinator | `Current repo` | 2026-04-13 | High | A second nav owner still exists and still owns retired destinations. | Route-manifest containment is not fully specified until this graph is handled. | Drives the legacy navigation-owner finding. |

## H. State Coverage Matrix
| State | Proposal Status (`Specified | Partial | Missing | Contradicted by repo | Deferred intentionally`) | Evidence IDs | Repo Touchpoints | Notes / Risks |
|---|---|---|---|---|
| Entry | `Specified` | `DOC-01`, `NAV-01` | [ContentView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/ContentView.swift) | Apple root shell is defined clearly now. |
| Happy path | `Partial` | `DOC-01`, `MAP-01`, `MAP-02` | Goal dashboard, transaction history, asset detail | Retained happy path is clearer, but goal-dashboard next actions still leak hidden features. |
| Loading | `Partial` | `DOC-01`, `MAP-05` | Startup task, dashboard loading | Proposal does not map startup-owner transitions in detail. |
| Empty | `Specified` | `DOC-01`, `NAV-01` | Root dashboard / goals shell | No new concern in this round. |
| Validation error | `Partial` | `DOC-01`, `MAP-05` | Startup and retained dashboard | Proposal does not say which owner surfaces startup containment failures. |
| Backend error | `Partial` | `MAP-05`, `DATA-02` | Health monitor, startup | Startup monitoring ownership is still ambiguous. |
| Offline / degraded | `Partial` | `DOC-01`, `MAP-05` | Health monitor, dashboards | Proposal names the contract, but not the owner map. |
| Retry / recovery | `Contradicted by repo` | `MAP-01`, `MAP-02`, `MAP-03`, `MAP-04` | Goal dashboard | Current recovery path still points toward hidden planning/forecast behavior. |
| Auth / permission expiry | `Deferred intentionally` |  |  | Not a primary slice for this proposal round. |
| Rollback / cancellation | `Partial` | `DOC-02`, `MAP-05`, `MAP-06` | Startup + route graph | Rollback is still conceptual until bootstrap and nav-owner migrations are specified. |

## I. Feature Flags / Rollout / Rollback
| Evidence ID | Mechanism / Flag | Scope | Rollout Plan | Rollback Path | Verified On | Confidence | Notes |
|---|---|---|---|---|---|---|---|
| FLAG-01 | `release_mvp` / `debug_internal` in [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:82](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L82) | Apple public MVP | Specified at proposal level | Partial | 2026-04-13 | High | Public/debug split is clearer now, but the proposal still does not map how active startup and nav owners switch under those modes. |

## J. Analytics / Instrumentation
| Evidence ID | Event / Signal | Purpose | Trigger Point | Verified On | Confidence | Gap / Risk |
|---|---|---|---|---|---|---|
| METRIC-01 | `analytics_adapter`, hidden-runtime-no-op dashboards | Release health | Proposal only | 2026-04-13 | Medium | Instrumentation intent exists, but ownership is unclear until the bootstrap map exists. |

## K. Testing Strategy
| Evidence ID | Layer | Covered Surface | Current Coverage | Proposed Additions | Verified On | Confidence | Gap / Risk |
|---|---|---|---|---|---|---|---|
| TEST-01 | Source-based unit/contract tests | Apple retained shell | [MVPContainmentContractTests.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift) now guards migration-chrome removal | Add explicit coverage for goal-dashboard CTA contract and legacy coordinator removal/isolation | 2026-04-13 | High | Existing containment tests do not cover the remaining goal-dashboard and nav-owner seams. |
| TEST-02 | Goal dashboard contract tests | Goal dashboard next actions | [GoalDashboardNextActionResolverTests.swift:51](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/GoalDashboardNextActionResolverTests.swift#L51) still defends `plan_this_month` | Rewrite to retained-MVP CTAs only | 2026-04-13 | High | The old planner CTA is regression-protected today. |

## L. Current Repo Reality / Contradictions
| Evidence ID | Repo Surface | Proposal Claim | Current Repo Reality | Verified On | Confidence | Implication |
|---|---|---|---|---|---|---|
| REAL-01 | Goal dashboard retained surface | Hidden features include planning and forecast modules; retained dashboard should not reopen them | Goal dashboard still emits `plan_this_month`, `open_forecast`, and history/planning guidance | 2026-04-13 | High | Proposal is still ahead of current retained-surface reality. |
| REAL-02 | Startup ownership | `BootstrapPolicyResolver` and `AppBootstrapPlan` become sole startup owners | App root still directly owns startup side effects, and the proposal omits the promised replacement map | 2026-04-13 | High | Proposal is incomplete on its core architecture mechanism. |
| REAL-03 | Route-manifest containment | Apple route manifests exclude hidden features in public mode | Legacy coordinator graph still owns hidden destinations, and retained views still depend on it | 2026-04-13 | High | Proposal does not yet fully account for the active route graph inventory. |

## M. Proposal Completeness Matrix
| Dimension | Status (`Specified | Partial | Missing | Contradicted by repo | Deferred intentionally`) | Evidence IDs | Notes |
|---|---|---|---|
| Problem / user intent | `Specified` | `DOC-01` | Apple-first MVP direction is now coherent. |
| Scope boundaries | `Specified` | `DOC-01`, `BASE-01` | `R1` scope blockers are closed. |
| Reusable baseline coverage | `Partial` | `BASE-01` | Baseline exists, but misses startup/nav/goal-dashboard seams. |
| Screen / surface definition | `Partial` | `DOC-01`, `REAL-01` | Retained goal-dashboard contract is still inconsistent with repo reality. |
| Navigation / entry points | `Partial` | `NAV-02`, `NAV-03`, `REAL-03` | Legacy coordinator disposition is not specified. |
| State handling | `Partial` | `MAP-01`, `MAP-02`, `INT-01` | Retry/recovery on goal dashboard still points at hidden features. |
| Data / API contract | `Specified` | `DOC-01` | No new major concern this round. |
| Persistence / caching | `Partial` | `MAP-05`, `DATA-01` | Startup persistence responsibilities remain unmapped. |
| Permissions / auth expiry | `Deferred intentionally` |  | Not the main slice in this round. |
| Feature flags / rollout / rollback | `Partial` | `FLAG-01`, `REAL-02` | Modes exist, but owner migration is not specified. |
| Analytics / instrumentation | `Partial` | `METRIC-01` | Signals are named but not operationalized by owner. |
| Testing strategy | `Partial` | `TEST-01`, `TEST-02` | Existing tests still defend planner-era goal-dashboard behavior. |
| Dependencies / integration points | `Partial` | `MAP-05`, `MAP-06`, `MAP-07` | Startup and nav ownership seams are still under-specified. |

## N. Assumptions, Open Questions, and Blockers
- ASSUMP-01: Apple-first scope and first-release no-migration UX are now accepted constraints.
- ASSUMP-02: Proposal readiness can remain `Partial` without simulator evidence because the remaining gaps are architectural, not runtime-only.
- QUESTION-01: Is the legacy `AppCoordinator` graph intended for deletion, debug-only isolation, or migration into the retained Apple route manifest?
- QUESTION-02: Should behind-schedule and on-track goal-dashboard states use only retained MVP actions such as `Add Contribution`, `Edit Goal`, `View Activity`, and allocation adjustment?
- BLOCKER-01: The proposal still lacks the concrete bootstrap replacement map it says must be approved.
- BLOCKER-02: Retained goal-dashboard next-action behavior still points to hidden planning/forecast/history surfaces.
- BLOCKER-03: Legacy route ownership is still not explicitly resolved.
