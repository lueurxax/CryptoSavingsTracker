# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `proposal-readiness`
- Overall readiness: `Red`
- Confidence: `High`
- Evidence completeness: `Partial`
- Documents / repo inputs reviewed:
  - [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md)
  - [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R1.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R1.md)
  - [SettingsView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift)
  - [DashboardView.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/DashboardView.swift)
  - [MVPContainmentContractTests.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift)
  - [AppNavHost.kt](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/AppNavHost.kt)
  - [Screen.kt](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/Screen.kt)
  - [SettingsScreen.kt](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/settings/SettingsScreen.kt)
  - [AddEditGoalScreen.kt](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/goals/AddEditGoalScreen.kt)
  - [OnboardingScreen.kt](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/onboarding/OnboardingScreen.kt)
  - [strings.xml](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/res/values/strings.xml)
- External sources reviewed:
  - None required
- Build/run attempts:
  - None in this mode
- Remaining assumptions:
  - This is the first public App Store release with no installed customer base, so customer-facing migration / cleanup messaging is out of scope unless the proposal proves otherwise.
- Remaining blockers:
  - Customer-facing migration surfaces remain part of the documented MVP contract.
  - Android still violates the claimed public containment contract.
  - `.review-baselines/current-system-baseline.md` does not exist.

## 1. Executive Summary
- The draft is not ready to guide implementation as written. It still codifies a migration program for end users even though the release context is a first public launch with no existing customer base.
- The document also overstates current cross-platform readiness. Android still publishes retired routes and retained surfaces that directly contradict the proposal's own hidden-feature contract.
- The fastest path to readiness is to simplify, not to add more transition machinery: collapse to a single public MVP mode, remove customer-facing migration UX, and either finish Android containment or explicitly narrow platform scope.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | Red | High | Partial | 0 | 2 | 0 | 0 |
| UX / Product | Red | High | Partial | 1 | 0 | 0 | 0 |
| Cross-Platform Architecture | Red | High | Partial | 0 | 1 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UX / Product Findings
- Finding ID: `F-UX-01`
  Severity: `Critical`
  Evidence IDs: `DOC-01`, `CODE-01`, `ARCH-01`, `ARCH-02`, `ARCH-03`
  Why it matters:
  The proposal still treats user-facing migration messaging as part of the MVP itself: a persistent `What changed in this update` row, a one-time migration banner, a support article, transition-only family-share guidance, migrated-user coach marks, and migration/support rollout dashboards. That is incompatible with the actual release context described by the user: this is the first public App Store release, there is no installed customer base yet, and customer-facing cleanup banners are not allowed. The repo is already aligned to the wrong contract on Apple: [SettingsView.swift:34](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift#L34), [DashboardView.swift:13](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/DashboardView.swift#L13), and [MVPContainmentContractTests.swift:11](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTrackerTests/MVPContainmentContractTests.swift#L11) actively encode these surfaces.
  Recommended fix:
  Delete the migration program from the public MVP contract. Concretely:
  1. Remove the `What changed in this update` and migration-banner requirements from [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:74](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L74) and [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:75](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L75).
  2. Remove `migration_help_article` from [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:95](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L95).
  3. Delete `release_transition_family_share` and its migration-guidance behavior from [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:112](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L112).
  4. Remove migrated-user coach marks, Share Feedback, and migration/support-signal rollout gates from [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:178](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L178) and [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:187](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L187).
  5. Update Apple implementation/tests so public release mode no longer expects those surfaces.
  Acceptance criteria:
  A first-time production user sees no migration banner, no `What changed` cleanup row, no transition help article CTA, and no migration-specific rollout instrumentation in the public MVP contract.
  Confidence:
  `High`

### 3.2 Cross-Platform Architecture Findings
- Finding ID: `F-ARCH-01`
  Severity: `High`
  Evidence IDs: `DOC-02`, `CODE-02`, `ARCH-04`, `ARCH-05`
  Why it matters:
  The proposal declares `Platform: iOS + Android parity` and states that no public route, deep link, scene, bottom-nav item, or Settings row reaches hidden features. Current Android code is not close to that contract. [AppNavHost.kt:58](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/AppNavHost.kt#L58) still renders a `Planning` bottom-nav item; [AppNavHost.kt:124](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/AppNavHost.kt#L124) and [AppNavHost.kt:263](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/AppNavHost.kt#L263) still wire planning/execution/history screens; [AppNavHost.kt:183](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/AppNavHost.kt#L183) still exposes asset sharing; and [Screen.kt:14](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/Screen.kt#L14) plus [Screen.kt:37](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/Screen.kt#L37) still publish those routes structurally.
  Recommended fix:
  Pick one of two honest scopes and document it explicitly:
  1. Narrow the proposal to Apple-only MVP containment for this release and remove `Android parity` wording until Android is actually contained.
  2. Keep parity in scope, but add explicit Android work items and keep proposal approval blocked until navigation, route contracts, and public entry points are pruned or policy-gated.
  Acceptance criteria:
  Either the proposal scope is downgraded from `iOS + Android parity`, or Android public navigation no longer exposes planning, execution, plan history, or asset-sharing routes in release mode.
  Confidence:
  `High`

### 3.3 UI Findings
- Finding ID: `F-UI-01`
  Severity: `High`
  Evidence IDs: `DOC-02`, `CODE-03`, `ARCH-06`
  Why it matters:
  Even within surfaces the proposal claims are retained, Android still exposes retired functionality. [SettingsScreen.kt:146](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/settings/SettingsScreen.kt#L146) shows a public `Export Data (CSV)` button, which directly conflicts with the proposal's hidden `csv_import_export` contract and public-settings rule. [AddEditGoalScreen.kt:232](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/goals/AddEditGoalScreen.kt#L232) still exposes reminder controls, contradicting [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md:69](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL.md#L69). [OnboardingScreen.kt:273](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/onboarding/OnboardingScreen.kt#L273) and [strings.xml:11](/Users/user/Documents/CryptoSavingsTracker/android/app/src/main/res/values/strings.xml#L11) still market `Smart Reminders`, which conflicts with the retained-product story in the same document.
  Recommended fix:
  Remove or gate Android CSV export, reminder controls, and reminder marketing before calling the retained contract done. If that work is not in the immediate release path, revise the proposal so it no longer claims those retained Android surfaces already conform.
  Acceptance criteria:
  Android public Settings does not expose CSV export, Android goal create/edit does not expose reminder controls, and Android onboarding copy no longer markets reminders in release mode.
  Confidence:
  `High`

### 3.4 Process / Evidence Findings
- Finding ID: `F-PROC-01`
  Severity: `Medium`
  Evidence IDs: `BASE-01`
  Why it matters:
  The proposal's own `P0` exit criteria require creating and approving `.review-baselines/current-system-baseline.md`, but that baseline file does not exist. That makes future repeat reviews noisier and weakens any claim that the containment baseline is formally frozen.
  Recommended fix:
  Create the baseline only after scope is corrected. A baseline captured against the current over-scoped draft would just freeze the wrong contract.
  Acceptance criteria:
  A reviewed `.review-baselines/current-system-baseline.md` exists and matches the corrected scope of the proposal.
  Confidence:
  `High`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict:
  The document is trying to solve two different problems at once: first-release MVP containment and migration of legacy users/features.
  Tradeoff:
  Keeping the migration story makes the proposal look more "complete," but it directly violates the simpler and more correct first-release requirement.
  Decision:
  Remove transition storytelling from the public MVP contract first. Only after that should the team decide whether Android parity is part of this same release document or a separate follow-up.
  Owner:
  Proposal author

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P0 | Remove public migration/cleanup UX from the proposal and from Apple release-mode expectations | UX / Product | Proposal author + Apple owner | Now | None | No banner / `What changed` / migration-help requirements remain in the public MVP contract | `F-UX-01` |
| P0 | Decide whether this proposal remains truly cross-platform or is rescaled to Apple-only containment | Architecture | Proposal author + mobile leads | Now | `F-UX-01` cleanup | Platform scope in the header matches the actual release plan | `F-ARCH-01` |
| P1 | If parity stays in scope, remove Android planning/sharing routes and retired retained-surface affordances | Android UI / Architecture | Android owner | Next | Platform-scope decision | Android release mode no longer exposes planning, execution, sharing, CSV export, or reminders | `F-ARCH-01`, `F-UI-01` |
| P2 | Create the missing review baseline after scope correction | Process | Proposal author | Next | Scope correction | `.review-baselines/current-system-baseline.md` exists and is approved | `F-PROC-01` |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Public MVP product contract | Whether first-time users see only the intended MVP with no cleanup messaging | Proposal diff removes migration clauses; Apple code/tests stop expecting banner/help-row behavior | No customer-facing migration UX in release mode | Before next proposal approval | Hold if any public migration CTA remains |
| Android containment | Whether Android actually matches the claimed hidden-feature contract | Public nav graph and retained surfaces no longer expose planning/sharing/export/reminders | Do not keep `Android parity` in the proposal while those routes remain public | Before parity signoff | Hold if `Planning`, `AssetSharing`, CSV export, or reminders remain public |
| Review repeatability | Whether future reviews can reuse an approved baseline instead of ad hoc context refresh | `.review-baselines/current-system-baseline.md` exists after scope correction | Do not baseline the wrong scope | Before next repeat review | Hold if baseline is still missing |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- GAP-01: There is no approved reusable baseline file for this proposal family.
- GAP-02: This review did not run simulator/build validation because the material blockers were already evident in proposal text plus current code.

### Open Questions
- QUESTION-01: Is Android truly in scope for the same release proposal, or should this document be rewritten as Apple-first containment?
- QUESTION-02: Should the current iOS migration surfaces be deleted outright, or preserved only in debug/internal tooling once the proposal is corrected?

## Appendix A. Evidence Pack
- [MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R1.md](/Users/user/Documents/CryptoSavingsTracker/docs/proposals/MVP_FEATURE_FLAG_CONTAINMENT_PROPOSAL_EVIDENCE_PACK_R1.md)
