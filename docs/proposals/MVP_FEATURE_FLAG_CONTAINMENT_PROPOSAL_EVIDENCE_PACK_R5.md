# Evidence Pack

## Repeat Review Freshness Note
- This is a repeat `proposal-readiness` review of [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md).
- The proposal was edited after [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R4.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R4.md).
- This round rechecked only the `R4` validation seam plus the already-hardened retained-dashboard and diagnostics boundaries.

## A. Repo-Local Proposal / Document Inventory
| Evidence ID | Source / Path / Artifact | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|
| DOC-01 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:76](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L76) | 2026-04-13 | High | The proposal now contains the exact diagnostics phrase `Public diagnostics remains goal-dashboard-local` and still states that Settings/About has no separate diagnostics status row. | `R4` could be incorrectly carried forward. | Confirms the last literal wording seam was addressed. |
| DOC-02 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:109](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L109) | 2026-04-13 | High | The retained goal-dashboard section still explicitly names utility ordering, scene assembly, and legacy widget migration as containment owners. | Dashboard containment could be overstated. | Confirms the `R3` dashboard fixes are still present. |
| DOC-03 | [current-system-baseline.md:93](/Users/user/Documents/CryptoSavingsTracker/.review-baselines/current-system-baseline.md#L93) | 2026-04-13 | High | The reusable baseline remains aligned with dashboard-local diagnostics and no Settings diagnostics row. | Baseline freshness could be overstated. | Confirms the baseline still matches the proposal. |
| DOC-04 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R4.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R4.md) | 2026-04-13 | High | `R4` left one remaining blocker: exact-string drift between the proposal and a containment test. | This round could miss whether the last blocker really closed. | Establishes the repeat-review target. |

## B. Reusable Baseline Inputs
| Evidence ID | Artifact / Slice | Status (`Reused | Partially refreshed | Missing`) | Covered Surfaces | Verified On | Confidence | Freshness Notes | Relevance |
|---|---|---|---|---|---|---|---|
| BASE-01 | [current-system-baseline.md](/Users/user/Documents/CryptoSavingsTracker/.review-baselines/current-system-baseline.md) | `Reused` | Apple public MVP contract, retained goal-dashboard boundary, diagnostics boundary | 2026-04-13 | High | No additional baseline refresh was needed in this round; the reviewed slices remain fresh and aligned. | Keeps the repeat review grounded in the current reusable contract. |

## C. Scope, Out-of-Scope, and Intentional Deferrals
- In scope:
  - The `R4` diagnostics validation seam
  - Continued alignment of retained-dashboard containment wording with current repo sources
  - Baseline/proposal/source consistency for the reviewed slices
- Out of scope:
  - Runtime simulator validation
  - Android scope
  - Full implementation audit
- Deferred intentionally:
  - General dead-code cleanup outside the reviewed contract slices
- Assumptions:
  - Proposal readiness remains the goal, not proof of shipped implementation.

## D. Affected Screens / Navigation / Entry-Point Slice
| Evidence ID | Screen / Surface / Entry Point | Source (`Baseline | Targeted refresh | Proposal`) | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|---|
| NAV-01 | [SettingsView.swift:17](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift#L17) | `Targeted refresh` | 2026-04-13 | High | Settings still has no diagnostics row. | Diagnostics placement could be misstated. | Confirms public diagnostics remains dashboard-local in current repo reality. |
| NAV-02 | [GoalDashboardScreen.swift:254](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L254) and [GoalDashboardScreen.swift:618](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L618) | `Targeted refresh` | 2026-04-13 | High | Diagnostics remains exposed through the retained goal-dashboard hard-error flow and `view_diagnostics`. | Diagnostics contract could be misread from prose alone. | Confirms the retained UI still matches the proposal. |
| NAV-03 | [MVPContainmentContractTests.swift:164](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift#L164) | `Targeted refresh` | 2026-04-13 | High | The containment test still validates the proposal text literally, and the updated proposal now satisfies that exact expectation. | A hidden validation seam could remain. | Confirms the last `R4` blocker is closed. |

## E. Impacted Modules / Code-Path Map
| Evidence ID | File Path / Module / Symbol | Layer | Role in Flow | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|---|---|
| MAP-01 | [GoalDashboardContract.swift:51](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Models/GoalDashboardContract.swift#L51) | Shared contract | Retained utility ordering | 2026-04-13 | High | `defaultUtilityActionOrder` still uses `review_activity` and no longer contains `view_history`. | Proposal/dashboard alignment could be overstated. | Confirms the retained contract remains synced in source. |
| MAP-02 | [GoalDashboardLegacyWidgetMigration.swift:81](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/GoalDashboardLegacyWidgetMigration.swift#L81) | Migration utility | Legacy widget remapping | 2026-04-13 | High | History-oriented widgets still remap to `review_activity`. | The proposal could drift from the actual migration logic. | Confirms legacy migration remains aligned. |
| MAP-03 | [GoalDashboardSceneAssembler.swift:77](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift#L77) | Scene assembly | Retained dashboard utilities | 2026-04-13 | High | The scene assembler still emits `review_activity`, not `view_history`. | Proposal/repo sync could be overstated. | Confirms the scene layer remains aligned. |
| MAP-04 | [MVPContainmentContractTests.swift:172](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift#L172) and [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:76](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L76) | Validation | Literal proposal contract check | 2026-04-13 | High | The proposal now contains the exact diagnostics substring the source-based containment test asserts. | The `R4` blocker could appear closed when it is not. | Direct evidence that the last validation seam is closed. |

## F. State Coverage Matrix
| State | Proposal Status (`Specified | Partial | Missing | Contradicted by repo | Deferred intentionally`) | Evidence IDs | Repo Touchpoints | Notes / Risks |
|---|---|---|---|---|
| Retained dashboard CTA containment | `Specified` | `DOC-02`, `MAP-01`, `MAP-02`, `MAP-03` | Goal-dashboard contract, scene assembly, legacy migration | No new contradictions found in this round. |
| Diagnostics placement | `Specified` | `DOC-01`, `DOC-03`, `NAV-01`, `NAV-02` | Settings and goal-dashboard diagnostics surfaces | Proposal, baseline, and repo still agree on dashboard-local diagnostics. |
| Source-based diagnostics validation | `Specified` | `NAV-03`, `MAP-04` | Proposal text and `MVPContainmentContractTests` | The `R4` literal wording gap is closed. |

## G. Testing Strategy
| Evidence ID | Layer | Covered Surface | Current Coverage | Proposed Additions | Verified On | Confidence | Gap / Risk |
|---|---|---|---|---|---|---|---|
| TEST-01 | Source-based containment tests | Retained dashboard CTA contract | Contract, scene assembly, migration, copy, screen, and resolver drift checks remain present | None required for this review round | 2026-04-13 | High | No material test gap found for the reviewed slices. |
| TEST-02 | Source-based containment tests | Diagnostics boundary | Proposal wording, no Settings diagnostics row, and dashboard-local diagnostics flow are all covered | None required for this review round | 2026-04-13 | High | The prior literal mismatch is now resolved. |

## H. Current Repo Reality / Contradictions
| Evidence ID | Repo Surface | Proposal Claim | Current Repo Reality | Verified On | Confidence | Implication |
|---|---|---|---|---|---|---|
| REAL-01 | Retained goal-dashboard containment | Hidden history/planner CTA sources are remapped away from public mode | Contract, scene assembly, legacy migration, and containment tests remain aligned on `review_activity` | 2026-04-13 | High | No material contradiction found. |
| REAL-02 | Diagnostics boundary | Public diagnostics is dashboard-local and Settings/About has no separate row | Proposal, baseline, retained UI, and containment test are now aligned | 2026-04-13 | High | The `R4` blocker is closed. |

## I. Proposal Completeness Matrix
| Dimension | Status (`Specified | Partial | Missing | Contradicted by repo | Deferred intentionally`) | Evidence IDs | Notes |
|---|---|---|---|
| Problem / user intent | `Specified` | `DOC-01`, `DOC-02` | Apple-first MVP containment remains coherent. |
| Scope boundaries | `Specified` | `DOC-01`, `DOC-03` | Reviewed slices are explicit and aligned. |
| Reusable baseline coverage | `Specified` | `BASE-01` | Baseline is fresh for the reviewed surfaces. |
| Screen / surface definition | `Specified` | `NAV-01`, `NAV-02` | Diagnostics and retained dashboard surfaces are clearly placed. |
| State handling | `Specified` | `DOC-02`, `MAP-01`, `MAP-02`, `MAP-03` | Retained dashboard containment is explicit and grounded in current repo reality. |
| Testing strategy | `Specified` | `TEST-01`, `TEST-02`, `MAP-04` | Source-based validation now matches the proposal text for the reviewed slices. |
| Dependencies / integration points | `Specified` | `MAP-01`, `MAP-02`, `MAP-03` | Reviewed integration seams are explicitly covered. |

## J. Assumptions, Open Questions, and Blockers
- ASSUMP-01: Proposal readiness remains independent from runtime simulator evidence in this round.
- BLOCKERS: None for the reviewed slices.
- OPEN QUESTIONS: None material for proposal readiness in this round.
