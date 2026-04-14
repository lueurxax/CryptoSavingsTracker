# Consolidated Review

## 0. Review Mode and Proposal Evidence Summary
- Mode used: `proposal-readiness`
- Evidence completeness: `Partial`
- Proposal / docs reviewed:
  - [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md)
  - [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R2.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R2.md)
  - [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R2.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_TRIAD_REVIEW_R2.md)
  - [current-system-baseline.md](/Users/user/Documents/CryptoSavingsTracker/.review-baselines/current-system-baseline.md)
- Reusable baseline used:
  - [current-system-baseline.md](/Users/user/Documents/CryptoSavingsTracker/.review-baselines/current-system-baseline.md)
- Baseline reused:
  - Apple-first public MVP contract
  - First-release no-migration UX constraint
  - Retained goal-dashboard disallowed CTA list
- Baseline refreshed:
  - Retained goal-dashboard utility-action ownership
  - Settings/About diagnostics wording versus current retained UI
- Baseline freshness: `Partially refreshed`
- Proposal-specific integration context:
  - None
- Targeted context refresh performed:
  - [GoalDashboardContract.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Models/GoalDashboardContract.swift)
  - [GoalDashboardSceneAssembler.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift)
  - [GoalDashboardLegacyWidgetMigration.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/GoalDashboardLegacyWidgetMigration.swift)
  - [GoalDashboardScreen.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift)
  - [SettingsView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift)
  - [GoalDashboardNextActionResolverTests.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/GoalDashboardNextActionResolverTests.swift)
  - [MVPContainmentContractTests.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift)
- External research used: `None`
- Research pack:
  - None
- Sources reused:
  - Proposal, baseline, `R2` review, `R2` evidence pack
- Sources refreshed:
  - Goal-dashboard utility CTA sources
  - Settings/About retained surface
- Time-sensitive external guidance:
  - None
- Code areas inspected:
  - Retained goal-dashboard CTA assembly and utility rendering
  - Legacy widget migration
  - Settings/About retained surface
- Current repo contradictions found:
  - `view_history` is still emitted from utility defaults and legacy widget migration even though the proposal now forbids it.
  - Settings does not currently expose any diagnostics status, while the proposal still leaves that surface ambiguous.
- Runtime evidence used: `None`
- Provenance of key evidence:
  - Proposal + baseline for intended contract
  - Current source files and tests for repo reality
- Remaining assumptions:
  - The newly added bootstrap replacement map and legacy navigation disposition close the main `R2` architecture gaps at the proposal level.
- Remaining blockers:
  - The retained goal-dashboard contract still does not call out all real teardown/remap owners for `view_history`.
  - The Settings diagnostics contract is still underspecified.

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `High`
- Proposal completeness signal: `Mixed`
- Top risks:
  1. `view_history` is now banned by the proposal, but current repo reality still emits it from three non-resolver owners that the document does not name directly.
  2. The Settings acceptance line still leaves diagnostics placement and gating undefined, so implementation and tests can diverge while all claiming compliance.
  3. The next revision could look "done" because the large `R2` blockers are closed, while these smaller but real seams remain.
- Top opportunities:
  1. `R2`'s biggest gaps are materially closed: bootstrap-map ownership and legacy-navigation disposition are now written down.
  2. The remaining work is narrow contract hardening, not another broad scope rewrite.
  3. One more proposal pass could plausibly move this to `Green`.

## 2. Proposal Scope and Completeness
- In scope:
  - Retained goal-dashboard CTA containment
  - Settings/About diagnostics wording
  - Current repo contradictions that could make the updated proposal incomplete in practice
- Out of scope:
  - Runtime simulator validation
  - Android containment
  - Full implementation audit
- Deferred intentionally:
  - General dead-code cleanup not attached to retained dashboard/settings surfaces
- Most important baseline refreshes performed:
  - Re-checked the retained goal-dashboard CTA boundary after the new `review_activity` contract landed
  - Re-checked Settings/About against the proposal's remaining diagnostics wording
- Most important contradictions with current repo:
  - Utility defaults, scene assembly, and legacy widget migration still revive `view_history`
  - Settings/About has no diagnostics row despite the acceptance line implying one may exist
- Most important missing or partial states:
  - Legacy persisted dashboard layouts are not explicitly covered by the retained CTA containment text
  - Diagnostics surface ownership is still not canonical

## 3. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | Amber | High | Partial | 0 | 1 | 0 | 0 |
| UX | Amber | High | Partial | 0 | 0 | 1 | 0 |
| iOS Architecture | Amber | High | Partial | 0 | 1 | 0 | 0 |

## 4. Findings by Discipline

### 4.1 UI / iOS Architecture Findings
- Finding ID: `F-ARCH-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `BASE-01`, `NAV-01`, `NAV-02`, `MAP-01`, `MAP-02`, `MAP-03`, `MAP-04`, `REAL-01`
  Why it matters:
  The proposal now correctly disallows `view_history` for the retained public goal dashboard, but current repo reality shows that this CTA still survives outside the next-action resolver path the document mainly talks about. [GoalDashboardContract.swift:51](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Models/GoalDashboardContract.swift#L51) still keeps `view_history` in `defaultUtilityActionOrder`, [GoalDashboardSceneAssembler.swift:77](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift#L77) still assembles a visible `View History` utility button, and [GoalDashboardLegacyWidgetMigration.swift:81](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/GoalDashboardLegacyWidgetMigration.swift#L81) still maps legacy widget types back to `view_history`. The retained screen renders all utility actions from upstream state in [GoalDashboardScreen.swift:468](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L468), but no longer handles `view_history` in [GoalDashboardScreen.swift:606](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L606). The proposal therefore risks being implemented "correctly" at the resolver/test layer while still shipping a dead or hidden-history CTA through utility defaults or widget migration.
  Recommended fix:
  Add one explicit retained-dashboard teardown clause naming all owners that must stop emitting disallowed CTA IDs:
  1. `GoalDashboardContract.defaultUtilityActionOrder`
  2. utility-action assembly in `GoalDashboardSceneAssembler`
  3. legacy widget migration mapping in `GoalDashboardLegacyWidgetMigration`
  Also require contract tests on assembled utility actions and legacy migration results, not only next-action resolver outputs.
  Acceptance criteria:
  No retained public Apple dashboard state, default utility order, or legacy widget migration path emits `view_history`; if old history-oriented widget types are preserved, they remap to a retained CTA such as `review_activity` instead.
  Confidence:
  `High`

### 4.2 UX Findings
- Finding ID: `F-UX-01`
  Severity: `Medium`
  Evidence IDs: `DOC-03`, `NAV-03`, `NAV-04`, `MAP-05`, `MAP-06`, `REAL-02`
  Why it matters:
  The Settings acceptance criterion still says Settings exposes diagnostics status "when allowed", but the proposal never says what "allowed" means, who owns that surface, or whether diagnostics is supposed to live in Settings/About at all. Current repo reality points the other way: [SettingsView.swift:17](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift#L17) has no diagnostics row, while the only public diagnostics affordance found in this review is the goal-dashboard hard-error flow in [GoalDashboardSceneAssembler.swift:516](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/GoalDashboardSceneAssembler.swift#L516) and [GoalDashboardScreen.swift:618](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Dashboard/GoalDashboardScreen.swift#L618). That leaves the proposal with two possible truths: diagnostics is dashboard-local, or diagnostics also belongs in Settings/About. Tests and implementation can diverge until the document chooses one.
  Recommended fix:
  Canonicalize the diagnostics surface in the proposal:
  1. Either remove diagnostics from the Settings acceptance line and make goal-dashboard diagnostics the only public surface.
  2. Or specify the exact Settings/About row, gate, owner, and copy when diagnostics status is allowed.
  Acceptance criteria:
  The proposal defines exactly one public diagnostics contract for Apple MVP, with explicit placement, gating, and test ownership.
  Confidence:
  `High`

## 5. Cross-Discipline Conflicts and Decisions
- Conflict:
  The proposal is now cleaner than the remaining repo seams it is trying to contain.
- Tradeoff:
  Keeping the spec high-level makes it easier to read, but the refreshed code shows that hidden CTA leakage already survives in utility defaults and migration helpers the proposal does not currently name.
- Decision:
  Keep the new Apple-first structure, but harden the proposal with one more layer of concrete ownership around retained dashboard teardown and diagnostics placement.
- Owner:
  Proposal author + Apple containment owner

## 6. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P0 | Add explicit retained-dashboard teardown/remap owners for disallowed CTA IDs, including utility defaults and legacy widget migration | iOS Architecture | Proposal author | Now | None | No retained dashboard source can emit `view_history` in public Apple mode | `F-ARCH-01` |
| P1 | Canonicalize the public diagnostics surface and remove the Settings ambiguity | UX | Proposal author | Now | None | Diagnostics has one documented home, gate, and test owner | `F-UX-01` |
| P2 | Extend containment tests from resolver IDs to utility action assembly, legacy widget migration, and the finalized diagnostics contract | UI / iOS | Apple owner | Next | P0, P1 | Source-based regression suite defends the final retained contract end-to-end | `F-ARCH-01`, `F-UX-01` |

## 7. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Retained dashboard CTA containment | Whether disallowed CTA IDs are absent from all retained dashboard sources | No `view_history` in utility defaults, scene assembly, legacy migration, or rendered utilities | Do not sign off based only on next-action resolver tests | Before next repeat review | Hold if any public retained dashboard source still emits `view_history` |
| Diagnostics surface contract | Whether diagnostics has one documented public home | Proposal names one owner, one gate, and one test owner | Do not leave "when allowed" undefined | Before next repeat review | Hold if Settings and dashboard can both claim to be canonical |
| Containment regression coverage | Whether tests defend the actual retained sources | Contract tests cover utility-action sources and finalized diagnostics placement | Do not rely on copy-only or resolver-only coverage | Before implementation signoff | Hold if retained-source coverage is still partial |

## 8. Evidence Gaps and Open Questions

### Evidence Gaps
- GAP-01: This round stayed doc/code-based and did not run simulator validation for the retained dashboard utilities or diagnostics surfaces.

### Open Questions
- QUESTION-01: Should legacy widget types that used to map to history be dropped completely or remapped to `review_activity`?
- QUESTION-02: Does public Apple MVP actually need a Settings/About diagnostics row, or should diagnostics stay goal-dashboard-local?

## Appendix A. Evidence Pack
- [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R3.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R3.md)
