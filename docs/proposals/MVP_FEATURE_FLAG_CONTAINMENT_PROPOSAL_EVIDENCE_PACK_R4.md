# Evidence Pack

## Repeat Review Freshness Note
- This is a repeat `proposal-readiness` review of [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md).
- The proposal and the reusable baseline were both edited after [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R3.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R3.md).
- This round reuses `R3` and refreshes only the slices that changed materially: the retained dashboard containment contract, the diagnostics boundary, and the new source-based containment tests.

## A. Repo-Local Proposal / Document Inventory
| Evidence ID | Source / Path / Artifact | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|
| DOC-01 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:76](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L76) | 2026-04-13 | High | The proposal now makes diagnostics explicitly dashboard-local and says Settings/About has no separate diagnostics row in the first Apple MVP. | Old diagnostics ambiguity could be carried forward incorrectly. | Confirms the main `R3` diagnostics gap was addressed semantically. |
| DOC-02 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:109](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L109) | 2026-04-13 | High | The retained goal-dashboard section now names `GoalDashboardContract.defaultUtilityActionOrder`, `GoalDashboardSceneAssembler`, and `GoalDashboardLegacyWidgetMigration` as required teardown/remap owners for hidden CTA IDs. | The review could restate already-closed dashboard findings. | Confirms the main `R3` dashboard containment gap was addressed in the proposal. |
| DOC-03 | [current-system-baseline.md:93](/Users/user/Documents/CryptoSavingsTracker/.review-baselines/current-system-baseline.md#L93) | 2026-04-13 | High | The reusable baseline now has an explicit Diagnostics Boundary that matches the new proposal direction. | Baseline freshness could be overstated. | Confirms the baseline was updated along with the proposal. |
| DOC-04 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R3.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R3.md) | 2026-04-13 | High | `R3` found two remaining gaps: hidden `view_history` owners and ambiguous Settings diagnostics placement. | Delta from `R3` could be misstated. | Establishes what this repeat review needed to re-check. |

## B. Reusable Baseline Inputs
| Evidence ID | Artifact / Slice | Status (`Reused | Partially refreshed | Missing`) | Covered Surfaces | Verified On | Confidence | Freshness Notes | Relevance |
|---|---|---|---|---|---|---|---|
| BASE-01 | [current-system-baseline.md](/Users/user/Documents/CryptoSavingsTracker/.review-baselines/current-system-baseline.md) | `Reused` | Apple public MVP contract, retained goal-dashboard CTA boundary, startup owner boundary, legacy navigation boundary, diagnostics boundary | 2026-04-13 | High | The baseline now reflects the post-`R3` diagnostics and retained-dashboard contract. No additional baseline refresh was needed beyond validating the new diagnostics wording against current tests. | Keeps this round grounded in the latest reusable contract. |

## C. Scope, Out-of-Scope, and Intentional Deferrals
- In scope:
  - Post-`R3` proposal changes around diagnostics and retained dashboard containment
  - Current source-based containment tests that now validate those sections
  - Proposal/code/baseline alignment for the affected slices only
- Out of scope:
  - Runtime simulator validation
  - Android follow-up scope
  - Full implementation audit
- Deferred intentionally:
  - Broader dead-code cleanup outside the reviewed retained-contract slices
- Assumptions:
  - Apple-first MVP scope and first-release no-migration UX remain accepted constraints.
  - Proposal review should judge readiness, not rerun the implementation audit.

## D. Affected Screens / Navigation / Entry-Point Slice
| Evidence ID | Screen / Surface / Entry Point | Source (`Baseline | Targeted refresh | Proposal`) | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|---|
| NAV-01 | [SettingsView.swift:17](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift#L17) | `Targeted refresh` | 2026-04-13 | High | Settings still exposes only display currency, appearance, support, and version; there is no diagnostics row. | Diagnostics placement could be misread from the proposal alone. | Confirms the repo still matches the intended dashboard-local diagnostics surface. |
| NAV-02 | [GoalDashboardScreen.swift:254](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L254) and [GoalDashboardScreen.swift:618](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L618) | `Targeted refresh` | 2026-04-13 | High | The retained public diagnostics affordance is still the goal-dashboard hard-error flow and `view_diagnostics` action. | Diagnostics surface ownership could be misstated. | Confirms the live retained surface matches the proposal's intended diagnostics home. |
| NAV-03 | [MVPContainmentContractTests.swift:164](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift#L164) | `Targeted refresh` | 2026-04-13 | High | Source-based containment tests now validate the diagnostics contract directly from proposal text. | Proposal/test drift can become a hidden release-gate failure. | Establishes the remaining validation seam. |

## E. Impacted Modules / Code-Path Map
| Evidence ID | File Path / Module / Symbol | Layer | Role in Flow | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|---|---|
| MAP-01 | [GoalDashboardContract.swift:51](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Models/GoalDashboardContract.swift#L51) | Shared contract | Retained utility action ordering | 2026-04-13 | High | `defaultUtilityActionOrder` now ends with `review_activity`, not `view_history`. | Closed `R3` issues could be repeated incorrectly. | Confirms the retained CTA contract was actually mirrored into source. |
| MAP-02 | [GoalDashboardLegacyWidgetMigration.swift:81](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/GoalDashboardLegacyWidgetMigration.swift#L81) | Migration utility | Legacy widget remapping | 2026-04-13 | High | History-oriented legacy widget types now remap to `review_activity`. | The proposal could appear ahead of current repo reality. | Confirms the proposal now names a real, existing remap point. |
| MAP-03 | [GoalDashboardSceneAssembler.swift:77](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift#L77) | Scene assembly | Retained dashboard utilities | 2026-04-13 | High | The assembled utility action now uses `review_activity` and no longer emits `view_history`. | The review could miss whether the scene layer caught up with the proposal. | Confirms the retained dashboard seam was materially closed. |
| MAP-04 | [MVPContainmentContractTests.swift:172](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift#L172) | Validation | Source-based proposal contract check | 2026-04-13 | High | The test expects the exact substring `Public diagnostics remains goal-dashboard-local` inside the proposal source. | Even a semantically correct proposal can still fail the release-gate test if wording drifts. | Primary evidence for the remaining finding. |
| MAP-05 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:76](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L76) | Proposal contract | Diagnostics boundary wording | 2026-04-13 | High | The proposal says `Diagnostics remains goal-dashboard-local through the retained hard-error diagnostics flow`, not the exact string the test asserts. | Review could overstate proposal/test alignment. | Shows the literal mismatch directly. |

## F. State Coverage Matrix
| State | Proposal Status (`Specified | Partial | Missing | Contradicted by repo | Deferred intentionally`) | Evidence IDs | Repo Touchpoints | Notes / Risks |
|---|---|---|---|---|
| Retained dashboard CTA containment | `Specified` | `DOC-02`, `MAP-01`, `MAP-02`, `MAP-03` | Goal-dashboard contract, scene assembly, legacy migration | The main `R3` dashboard finding is materially closed. |
| Diagnostics placement | `Specified` | `DOC-01`, `DOC-03`, `NAV-01`, `NAV-02` | Settings and goal-dashboard diagnostics surfaces | Diagnostics is now canonically dashboard-local in proposal, baseline, and repo. |
| Source-based validation of diagnostics placement | `Contradicted by repo` | `NAV-03`, `MAP-04`, `MAP-05` | `MVPContainmentContractTests` vs proposal source text | Validation now depends on one exact string the proposal does not currently contain. |

## G. Testing Strategy
| Evidence ID | Layer | Covered Surface | Current Coverage | Proposed Additions | Verified On | Confidence | Gap / Risk |
|---|---|---|---|---|---|---|---|
| TEST-01 | Source-based containment tests | Retained dashboard CTA contract | [MVPContainmentContractTests.swift:140](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift#L140) now checks contract, assembler, migration, copy, and screen for hidden CTA removal | None required for the retained-dashboard slice | 2026-04-13 | High | This slice now looks consistent. |
| TEST-02 | Source-based containment tests | Diagnostics boundary | [MVPContainmentContractTests.swift:164](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift#L164) validates the proposal text and retained UI surfaces | Align the proposal wording or relax the test to semantic matching | 2026-04-13 | High | Current proposal/test literal mismatch can fail validation even though product intent is clear. |

## H. Current Repo Reality / Contradictions
| Evidence ID | Repo Surface | Proposal Claim | Current Repo Reality | Verified On | Confidence | Implication |
|---|---|---|---|---|---|---|
| REAL-01 | Retained goal-dashboard CTA containment | Hidden history/planner CTA sources must be remapped away from public mode | Contract, scene assembly, legacy migration, and source-based tests now all point to `review_activity` instead of `view_history` | 2026-04-13 | High | The main `R3` retained-dashboard gap is closed. |
| REAL-02 | Diagnostics boundary validation | Diagnostics is dashboard-local and Settings/About has no separate row | Repo UI matches that contract, but the proposal and one source-based test now disagree on the exact canonical sentence | 2026-04-13 | High | Readiness is nearly clean, but the validation contract is not fully aligned yet. |

## I. Proposal Completeness Matrix
| Dimension | Status (`Specified | Partial | Missing | Contradicted by repo | Deferred intentionally`) | Evidence IDs | Notes |
|---|---|---|---|
| Problem / user intent | `Specified` | `DOC-01`, `DOC-02` | Apple-first containment remains coherent. |
| Scope boundaries | `Specified` | `DOC-01`, `DOC-03` | Diagnostics and retained dashboard boundaries are now explicit. |
| Reusable baseline coverage | `Specified` | `BASE-01` | Baseline is aligned with the current proposal for the reviewed slices. |
| Screen / surface definition | `Specified` | `NAV-01`, `NAV-02` | Diagnostics surface is now canonically dashboard-local. |
| Testing strategy | `Partial` | `TEST-01`, `TEST-02`, `REAL-02` | One exact-string proposal/test seam remains. |
| Dependencies / integration points | `Specified` | `MAP-01`, `MAP-02`, `MAP-03` | The retained dashboard teardown/remap points are now explicit and grounded in real code. |

## J. Assumptions, Open Questions, and Blockers
- ASSUMP-01: The post-`R3` retained-dashboard changes and diagnostics boundary are intentional and represent the proposal's current source of truth.
- BLOCKER-01: `MVPContainmentContractTests` now treats one exact diagnostics sentence as the canonical proposal contract, but [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:76](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L76) does not contain that exact phrase.
- QUESTION-01: Should the proposal adopt the exact canonical diagnostics sentence already hard-coded in the containment test, or should the test be loosened to semantic matching instead of literal source text?
