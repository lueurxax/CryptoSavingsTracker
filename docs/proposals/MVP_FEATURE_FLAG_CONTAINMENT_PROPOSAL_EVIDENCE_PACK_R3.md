# Evidence Pack

## Repeat Review Freshness Note
- This is a repeat `proposal-readiness` review of [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md).
- The proposal and the reusable baseline were both edited after [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R2.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R2.md).
- This round reuses `R2` for the now-closed bootstrap-map and legacy-navigation gaps, and refreshes only the slices that still looked unstable after those edits: retained goal-dashboard CTA containment and the Settings/About diagnostics contract.

## A. Repo-Local Proposal / Document Inventory
| Evidence ID | Source / Path / Artifact | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|
| DOC-01 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:80](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L80) | 2026-04-13 | High | The proposal now defines an explicit retained goal-dashboard contract and disallows `view_history` in public Apple mode. | Review could overstate an already-closed goal-dashboard issue. | Primary contract source for this round. |
| DOC-02 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:116](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L116) and [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:132](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L132) | 2026-04-13 | High | The proposal now includes both the bootstrap replacement map and the legacy navigation disposition table. | Closed `R2` findings could be repeated incorrectly. | Confirms the main `R2` architecture blockers were addressed in the document itself. |
| DOC-03 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:76](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L76) | 2026-04-13 | High | The Settings acceptance contract still says Settings exposes diagnostics status "when allowed", but does not define the gate or surface owner. | Settings/About implementation can diverge without anyone violating the literal text. | Primary source for the diagnostics ambiguity. |
| DOC-04 | [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R2.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R2.md) | 2026-04-13 | High | `R2` centered on a missing bootstrap map, retained CTA drift, and unresolved legacy navigation ownership. | Delta from `R2` could be misstated. | Establishes what this repeat review needed to re-check. |

## B. Reusable Baseline Inputs
| Evidence ID | Artifact / Slice | Status (`Reused | Partially refreshed | Missing`) | Covered Surfaces | Verified On | Confidence | Freshness Notes | Relevance |
|---|---|---|---|---|---|---|---|
| BASE-01 | [current-system-baseline.md:48](/Users/user/Documents/CryptoSavingsTracker/.review-baselines/current-system-baseline.md#L48) | `Partially refreshed` | Retained goal-dashboard CTA boundary, first-release constraint, startup and legacy-nav boundaries | 2026-04-13 | High | Baseline now matches the new proposal on `review_activity`, disallowed `view_history`, and the first-release no-banner rule. This round still needed targeted code refresh because the runtime sources may not have caught up. | Keeps the review grounded in the latest repo-local contract. |

## C. Scope, Out-of-Scope, and Intentional Deferrals
- In scope:
  - Retained goal-dashboard CTA containment after the `R2` proposal edits
  - Settings/About acceptance wording for diagnostics status
  - Current repo seams that could still conflict with the updated proposal
- Out of scope:
  - Runtime simulator validation
  - Android scope
  - Full implementation audit of every containment clause
- Deferred intentionally:
  - Broad dead-code cleanup outside the refreshed dashboard/settings slices
- Assumptions:
  - Apple-first public MVP and first-release no-migration UX remain accepted constraints.
  - This round should review proposal/code alignment, not reopen already-closed scope debates.
- Open questions:
  - Should legacy widget migrations that used to point at history now drop those widgets, or remap them to `review_activity`?
  - Should diagnostics exist in Settings/About at all, or stay a goal-dashboard hard-error surface only?

## D. Affected Screens / Navigation / Entry-Point Slice
| Evidence ID | Screen / Surface / Entry Point | Source (`Baseline | Targeted refresh | Proposal`) | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|---|
| NAV-01 | [GoalDashboardScreen.swift:468](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L468) | `Targeted refresh` | 2026-04-13 | High | The utilities card renders every action in `utilities.actions`, so hidden or stale CTA IDs become visible buttons if upstream assembly still emits them. | CTA drift could be understated as "internal only". | Confirms the `view_history` seam is user-facing. |
| NAV-02 | [GoalDashboardScreen.swift:606](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L606) | `Targeted refresh` | 2026-04-13 | High | `handleAction` no longer handles `view_history`, while it does handle `review_activity` and `view_diagnostics`. | Public runtime can end up with a dead button if stale action IDs survive assembly. | Shows the current retained screen and the assembled action list are already out of sync. |
| NAV-03 | [SettingsView.swift:17](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift#L17) | `Targeted refresh` | 2026-04-13 | High | Settings currently exposes display currency, appearance, support, and version only; there is no diagnostics status row. | The acceptance contract could be read more broadly than the current retained surface. | Grounds the Settings diagnostics ambiguity in current repo reality. |
| NAV-04 | [GoalDashboardScreen.swift:254](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L254) | `Targeted refresh` | 2026-04-13 | High | The only active public diagnostics affordance found in retained Apple UI is the goal-dashboard hard-error path and its Diagnostics sheet. | Proposal readers may assume a second diagnostics surface exists in Settings when it does not. | Confirms the current canonical diagnostics surface. |

## E. Impacted Modules / Code-Path Map
| Evidence ID | File Path / Module / Symbol | Layer | Role in Flow | Verified On | Confidence | Key Fact | Risk if Wrong | Relevance |
|---|---|---|---|---|---|---|---|---|
| MAP-01 | [GoalDashboardContract.swift:51](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Models/GoalDashboardContract.swift#L51) | Shared contract | Default retained utility ordering | 2026-04-13 | High | `defaultUtilityActionOrder` still includes `view_history`. | The proposal could look implemented while one shared contract source still revives the hidden action. | First concrete owner for the remaining CTA conflict. |
| MAP-02 | [GoalDashboardSceneAssembler.swift:77](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift#L77) | Scene assembly | Goal-dashboard utility action assembly | 2026-04-13 | High | The assembler still constructs a visible `DashboardAction(id: "view_history", title: "View History", ...)`. | Hidden CTA drift can still reach the screen layer. | Second concrete owner for the remaining CTA conflict. |
| MAP-03 | [GoalDashboardLegacyWidgetMigration.swift:81](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/GoalDashboardLegacyWidgetMigration.swift#L81) | Migration utility | Legacy widget -> retained utility mapping | 2026-04-13 | High | `progressRing` and `lineChart` still map to `view_history`. | Previously saved widget layouts can repopulate the hidden CTA through migration. | Third concrete owner for the remaining CTA conflict. |
| MAP-04 | [GoalDashboardNextActionResolverTests.swift:110](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/GoalDashboardNextActionResolverTests.swift#L110) | Tests | Retained CTA contract enforcement | 2026-04-13 | High | Tests now treat `view_history` as a hidden ID. | Proposal readers may think the conflict is fully covered by tests when the utility path still bypasses that coverage. | Shows partial but incomplete contract hardening. |
| MAP-05 | [SettingsView.swift:19](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift#L19) | Settings UI | Current retained Settings/About surface | 2026-04-13 | High | No diagnostics state or diagnostics row is currently defined in Settings. | Settings acceptance text can drift away from the actual retained surface. | Concrete evidence for the diagnostics ambiguity. |
| MAP-06 | [GoalDashboardSceneAssembler.swift:516](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift#L516) and [GoalDashboardScreen.swift:618](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L618) | Diagnostics flow | Public diagnostics trigger and screen ownership | 2026-04-13 | High | Diagnostics is explicitly modeled as a goal-dashboard next-action secondary CTA, not as a Settings/About status surface. | The proposal could accidentally define two conflicting diagnostics homes. | Shows where diagnostics actually lives today. |

## F. State Coverage Matrix
| State | Proposal Status (`Specified | Partial | Missing | Contradicted by repo | Deferred intentionally`) | Evidence IDs | Repo Touchpoints | Notes / Risks |
|---|---|---|---|---|
| Retained dashboard happy path | `Partial` | `DOC-01`, `MAP-01`, `MAP-02`, `MAP-03` | Goal-dashboard contract, utility assembly, legacy migration | The proposal bans `view_history`, but the refreshed repo slice shows three still-active owners. |
| Retained dashboard recovery / secondary actions | `Specified` | `DOC-01`, `MAP-04`, `NAV-04` | Diagnostics CTA and `review_activity` contract | Next-action contract is clearer than in `R2`. |
| Legacy persisted dashboard customization | `Partial` | `MAP-03` | Legacy widget migration | Proposal does not explicitly say how hidden legacy widget types are remapped or dropped. |
| Settings/About happy path | `Partial` | `DOC-03`, `MAP-05` | Settings form | The proposal names a diagnostics status without defining the gate or placement. |
| Diagnostics / degraded state disclosure | `Partial` | `DOC-03`, `MAP-06`, `NAV-04` | Goal dashboard hard-error path | Current repo has one clear diagnostics surface, but the proposal wording suggests a second possible surface. |

## G. Testing Strategy
| Evidence ID | Layer | Covered Surface | Current Coverage | Proposed Additions | Verified On | Confidence | Gap / Risk |
|---|---|---|---|---|---|---|---|
| TEST-01 | Source-based containment tests | Public Settings and root containment | [MVPContainmentContractTests.swift:38](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift#L38) now guards migration-chrome removal and hidden Settings destinations | Add one explicit assertion for the canonical diagnostics surface once the proposal decides whether Settings should have it | 2026-04-13 | High | Settings diagnostics behavior can remain ambiguous because it is not defended anywhere. |
| TEST-02 | Goal-dashboard contract tests | Next-action hidden CTA IDs | [GoalDashboardNextActionResolverTests.swift:110](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/GoalDashboardNextActionResolverTests.swift#L110) excludes `view_history` in resolver outcomes | Extend contract coverage to `defaultUtilityActionOrder`, assembled utility actions, and legacy widget migration | 2026-04-13 | High | Current test hardening stops at resolver outputs, not at utility sources that still emit `view_history`. |

## H. Current Repo Reality / Contradictions
| Evidence ID | Repo Surface | Proposal Claim | Current Repo Reality | Verified On | Confidence | Implication |
|---|---|---|---|---|---|---|
| REAL-01 | Retained goal-dashboard CTA contract | Public Apple mode disallows `view_history` across the retained goal dashboard | Shared utility defaults, scene assembly, and legacy widget migration still emit `view_history`, and the screen still renders whatever arrives | 2026-04-13 | High | The updated proposal is directionally correct, but still understates where the remaining conflict lives. |
| REAL-02 | Settings/About diagnostics contract | Settings exposes diagnostics status "when allowed" | Current retained Apple UI only exposes diagnostics through the goal-dashboard hard-error path; Settings has no diagnostics status row | 2026-04-13 | High | The proposal leaves too much room for divergent implementations and tests. |

## I. Proposal Completeness Matrix
| Dimension | Status (`Specified | Partial | Missing | Contradicted by repo | Deferred intentionally`) | Evidence IDs | Notes |
|---|---|---|---|
| Problem / user intent | `Specified` | `DOC-01`, `DOC-02` | Apple-first containment intent is stable now. |
| Scope boundaries | `Specified` | `DOC-02`, `BASE-01` | `R2` scope and owner-map blockers are materially closed. |
| Reusable baseline coverage | `Partial` | `BASE-01` | Baseline is good enough, but this round still needed targeted refresh for dashboard utility sources and Settings diagnostics wording. |
| Screen / surface definition | `Partial` | `DOC-03`, `NAV-03`, `NAV-04` | Diagnostics surface is not canonically placed. |
| State handling | `Partial` | `DOC-01`, `MAP-01`, `MAP-02`, `MAP-03` | Hidden CTA teardown points are still under-specified. |
| Testing strategy | `Partial` | `TEST-01`, `TEST-02` | Current tests harden only part of the retained CTA contract. |
| Dependencies / integration points | `Partial` | `MAP-03`, `REAL-01` | Legacy widget migration remains a live integration seam the proposal does not call out directly. |

## J. Assumptions, Open Questions, and Blockers
- ASSUMP-01: The new bootstrap replacement map and legacy navigation disposition are sufficient to close the main `R2` architecture findings at the proposal level.
- ASSUMP-02: No runtime evidence is required for this repeat readiness review because the remaining gaps are doc/code contract issues, not simulator-only questions.
- QUESTION-01: Should legacy dashboard widget migrations that previously mapped to history now drop those widgets entirely or remap them to `review_activity`?
- QUESTION-02: Is diagnostics meant to stay dashboard-local, or does the product actually need a Settings/About status row in public Apple mode?
- BLOCKER-01: The retained goal-dashboard section still does not name utility defaults and legacy widget migration as mandatory teardown/remap points for disallowed CTA IDs.
- BLOCKER-02: The Settings diagnostics acceptance line is still too ambiguous to produce one stable UI/test contract.
