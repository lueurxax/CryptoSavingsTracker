# Complete Remaining UX Audit Remediation for CryptoSavingsTracker iOS

Status: Approved  
Approved at: 2026-04-10  
Platform: iOS  
Scope boundary date: 2026-04-04

## Executive Summary

This proposal converts the remaining UX remediation work into an implementation-ready finish plan. It preserves shipped Wave 1 work and existing release gates, names the active onboarding, goals, and settings/family-sharing seams in source, replaces the disputed color-literal baseline with the repository's canonical burndown method, and adds user-facing outcome metrics for Waves 2 through 4.

The program remains bound to the 2026-04-04 in-scope snapshot, closes all P0 and P1 issues in that snapshot plus regressions introduced during remediation, and avoids schema redesign, CloudKit truth-model changes, family-sharing capability drift, and repo-wide architecture rewrites.

## Problem

The repository does not need another UX strategy document. It needs a bounded finish plan for the already approved remediation program that matches current code ownership and release governance. Remaining scope is concentrated in:

- Goals and Goal Detail
- Onboarding
- Family Sharing and CloudKit-adjacent Settings surfaces

### User-Facing Evidence

- First-run onboarding currently commits completion even when goal creation fails, which creates a silent success outcome instead of transparent recovery.
- Goals entry points are split across an active iOS shell in `ContentView`, legacy coordinator routes, and an older `GoalsListView` flow, which risks inconsistent empty-state, add/edit, and recovery behavior.
- Family sharing and sync trust surfaces remain high-risk because `SettingsView` is the user-facing shell for Family Access and Local Bridge Sync while the family-sharing coordinator already owns freshness and error presentation.
- Historical product analytics were not available in the handoff, so the plan adds Phase 0 baseline measurement instead of inventing retrospective evidence.

## Goals

- Complete a Phase 0 implementation-gap audit against the approved 2026-04-04 proposal with stable requirement identifiers and explicit evidence paths.
- Fix all remaining P0 and P1 UX issues in Waves 2 through 4 plus any Wave 1 regressions discovered during verification.
- Name the authoritative production entry points and forbidden changes for onboarding, goals, and Wave 4 settings/family-sharing work before implementation begins.
- Use the repository's canonical release gates, runbooks, and artifact locations as the only acceptance surface.
- Add lightweight user-facing measurement so closeout can show UX improvement, not only engineering completion.

## Non-Goals

- Rewrite the approved proposal from scratch.
- Android remediation.
- Persistence schema redesign.
- CloudKit truth-model changes.
- Owner or invitee capability changes.
- Repo-wide replacement of state, error, or freshness abstractions.
- New information architecture, new top-level navigation, or net-new product features.

## Source of Truth and Decision Rules

- The approved 2026-04-04 proposal remains the normative scope and acceptance source.
- Shipped Wave 1 behavior and release evidence win over stale wording unless they violate an explicit invariant.
- The canonical color-literal method is the existing burndown contract:
  - `docs/design/baselines/ios-visual-literals-baseline.txt`
  - `docs/design/visual-literal-baseline-targets.v1.json`
  - published `literal-baseline-burndown-report.json`
- The prior 44-occurrence number is retired and must not be used for execution decisions.
- Broad grep counts are informative for risk review but are not the acceptance baseline because they do not match the governed repository method.
- If Phase 0 finds more than 2x provisional effort, a change outside the allowed runtime/coordinator bounds, or materially higher P0/P1 volume than expected, the program pauses for scope and staffing review before implementation continues.
- Any newly discovered P0 is pulled forward immediately; later-wave P1 issues stay in-wave unless they block the active user journey or release evidence.

## Scope

### In Scope

- Wave 2: Goals and Goal Detail
- Wave 3: Onboarding
- Wave 4: Family Sharing and CloudKit-adjacent Settings surfaces
- Phase 5 closeout
- Wave 1 regressions discovered during verification
- Targeted adoption-gap cleanup on touched screens and reused components

### Out of Scope

- Untouched surfaces outside the 2026-04-04 inventory unless they regress an active acceptance path
- Local Bridge Sync runtime semantics, package validation, or import/apply behavior except where Settings integration, ordering, copy, or accessibility regresses due to Wave 4 work
- Family-sharing namespace semantics, freshness-policy rules, publish semantics, invitee read-only rules, or CloudKit storage contracts
- Preview-only or dead-code cleanup that is not needed to close an approved requirement

## UX and UI Notes

### Global Rules

- Keep the existing finance-first visual direction and token contract.
- Do not use color alone for state communication; pair status color with copy and system symbology where state is user-visible.
- Dynamic Type, large-text readability, VoiceOver semantics, touch-target sizing, and explicit recovery states remain release criteria for P0/P1 fixes.
- Use user-facing sync language in UI copy by default. Technical CloudKit terminology stays in runbooks, diagnostics, and operator-facing text unless operationally necessary on screen.

### Wave 2 Guidance

- Preserve the row rhythm used by `UnifiedGoalRowView` and current grouped-list spacing.
- Zero-data states are explicit scope: zero goals, zero transactions, and first-action guidance must show intentional empty states rather than blank sections or placeholder `EmptyView` fallthrough.
- Primary goal actions must expose hierarchy clearly: create, edit, add asset, add transaction, and lifecycle actions must be discoverable without relying on truncation or color-only cues.

### Wave 3 Guidance

- Recoverable onboarding failures use inline error presentation plus a visible retry affordance, not silent completion and not a modal-only dead end.
- Onboarding retries must retain step progress, selected template, and captured profile state unless the user explicitly skips or resets.

### Wave 4 Guidance

- `SettingsView` remains the user-facing shell.
- Copy should say `sync`, `shared with family`, `read-only`, and `up to date` instead of leaking internal CloudKit language where not required.
- Family Access must remain visible before Local Bridge Sync and read-only invitee semantics must be obvious from list and detail states.

## Architecture and Implementation Approach

Preferred approach: continue the approved wave-based remediation model, but make Phase 0 an explicit contract-freezing step that names active production surfaces, requirement identifiers, canonical metrics, and forbidden changes before Wave 2 starts.

### Phase 0 Artifacts

- `docs/release/visual-system/phase0/requirement-index.json`
- `docs/release/visual-system/phase0/remaining-scope-audit.json`

Minimum fields:

- `requirement_id`
- `source_section`
- `wave_or_phase`
- `severity`
- `status`
- `evidence_path`
- `implementation_notes`
- `owner_surface`
- `forbidden_change_check`

### Wave 2 Authoritative Surfaces

- Active iOS goals shell: `ios/CryptoSavingsTracker/Views/ContentView.swift -> GoalsList`
- Goal detail shell: `ios/CryptoSavingsTracker/Views/Components/DetailContainerView.swift -> GoalDetailView.swift`
- Add goal: `AddGoalView` launched from the `ContentView` goals toolbar
- Edit goal: `EditGoalView` presented from the active goals shell

Supporting surfaces:

- `ios/CryptoSavingsTracker/Views/GoalsListView.swift`
- `ios/CryptoSavingsTracker/Views/GoalDetailView.swift`
- `ios/CryptoSavingsTracker/Navigation/Coordinator.swift`
- `ios/CryptoSavingsTracker/Views/DashboardView.swift`

Classification rules:

- `GoalsListContainer` is deferred cleanup or preview-only unless Phase 0 finds a live route into it.
- Legacy routes in `Coordinator.swift` and `DashboardView.swift` stay in scope only to normalize parity with the authoritative goals shell or to reroute into it.

Forbidden changes:

- No new goals navigation architecture.
- No unrelated macOS split-view redesign.
- No broad rewrite of `UnifiedGoalRowView` or planning components outside touched states.

### Wave 3 Authoritative Surfaces

- Entry gate: `ios/CryptoSavingsTracker/Views/OnboardingContentView.swift`
- Persisted onboarding state: `ios/CryptoSavingsTracker/Utilities/OnboardingManager.swift`
- Step flow and retry presentation: `ios/CryptoSavingsTracker/Views/Onboarding/OnboardingFlowView.swift`
- Goal creation service contract: `ios/CryptoSavingsTracker/Services/PersistenceMutationServices.swift`

Truth model:

- `OnboardingManager.hasCompletedOnboarding` is the only persisted completion signal for real user flows.
- Onboarding displays only when onboarding is incomplete and no goals exist.
- `completeOnboarding()` may be called only after successful goal creation or after an explicit user skip path.
- Recoverable `createGoalFromTemplate` failures must not commit onboarding completion.
- Retry UX belongs in `OnboardingFlowView`.
- `currentStep`, `userProfile`, and `selectedTemplate` remain intact across recoverable failures.

Explicit exception:

- UI-test seeding and production-capture helpers may continue to force completion for deterministic harnesses, but they are not the production user contract.

Forbidden changes:

- No new onboarding persistence model.
- No skip-path removal.
- No coupling onboarding completion to unrelated app-launch helpers.

### Wave 4 Authoritative Surfaces

- Settings shell: `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift`
- Family Access UI: `ios/CryptoSavingsTracker/Views/FamilySharing/*`
- Family-sharing coordinator: `ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift -> FamilyShareAcceptanceCoordinator`
- Trust gates:
  - `docs/runbooks/cloudkit-cutover-release-gate.md`
  - `docs/runbooks/family-sharing-release-gate.md`

In scope:

- Settings row order, copy, accessibility, and navigation into Family Access and Local Bridge Sync
- Family-sharing view-state copy, unavailable or revoked messaging, and presentation wiring needed to close approved UX issues
- Settings-level orchestration changes needed to keep family-sharing alerts, pending share sheets, and row summaries coherent

Out of scope:

- Local Bridge Sync runtime logic, package validation, approval semantics, or apply behavior
- FamilyShareAcceptanceCoordinator publish semantics, freshness timers, namespace execution semantics, or owner/invitee capability rules
- CloudKit cutover or storage contracts

Allowed coordinator changes:

- Presentation mapping for existing view states
- Wiring retry and refresh triggers to existing coordinator APIs
- User-facing copy and summary generation
- Alert and sheet orchestration needed for touched settings and family-sharing flows

Forbidden coordinator changes:

- Freshness-policy thresholds or timer lifecycles
- Publish suppression semantics
- Namespace migration, reconciliation barrier, or shared-root semantics
- Invitee read-only behavior

## Release and Evidence Model

- No parallel artifact system is introduced. Every new execution artifact stays inside an existing release tree.
- Artifact locations:
  - `docs/release/visual-system/<wave>/...`
  - `docs/release/navigation/<wave>/...`
  - `docs/release/cloudkit/<release-id>/...`
  - `docs/release/visual-system/phase0/...`

### Canonical Metric Method

Visual literal baseline:

- Baseline file: `docs/design/baselines/ios-visual-literals-baseline.txt`
- Targets file: `docs/design/visual-literal-baseline-targets.v1.json`
- Validator script: `scripts/check_visual_literal_baseline_burndown.py`
- Published reports:
  - `docs/release/visual-system/wave1/literal-baseline-burndown-report.json`
  - `docs/release/visual-system/latest/literal-baseline-burndown-report.json`
- Current canonical count: `206`
- Current Wave 1 limit: `210`
- Wave 2 limit: `180`
- Wave 3 limit: `140`

### Minimum Test Matrix

- Wave 2:
  - `VisualRuntimeAccessibilityUITests`
  - `ExecutionUserFlowUITests` for touched add/edit/detail flows
  - Goal-dashboard and visual-system evidence used by touched goal surfaces
  - Navigation release governance checks for changed goals navigation or modal behavior
- Wave 3:
  - Runtime accessibility assertions for onboarding screens
  - Targeted onboarding happy-path and injected-failure-path coverage
  - Navigation dirty-dismiss and presentation checks if onboarding flow presentation changes
- Wave 4:
  - `FamilyShareAcceptanceCoordinatorTests`
  - Freshness unit gates listed in `docs/runbooks/family-sharing-release-gate.md`
  - Deterministic family-sharing UI evidence listed in the same runbook
  - `LocalBridgeSyncUITests` for settings-entry parity only if Settings navigation or ordering changes
  - `CloudKitCutoverTests` and `PersistenceControllerTests` if touched code reaches CloudKit-adjacent settings orchestration

## Rollout Plan

1. Phase 0: Remaining-Scope Audit and Contract Freeze
2. Wave 2: Goals and Goal Detail
3. Wave 3: Onboarding
4. Wave 4: Family Sharing and CloudKit-Adjacent Settings
5. Phase 5: Closeout

## Success Metrics

### Hard Closure Targets

- 100% of P0 issues in the 2026-04-04 scope snapshot are fixed before closeout.
- 100% of P1 issues in the 2026-04-04 scope snapshot are fixed before closeout.

### User Outcome Metrics

- Wave 2: no silent dead ends on remediated flows and at least 90% first-attempt completion across the scripted task set before closeout
- Wave 3: happy-path onboarding completes deterministically and recoverable failure paths preserve progress and reach completion without forced restart
- Wave 4: users can correctly identify shared, read-only, up-to-date, and unavailable states in every required certification scenario

### Engineering and Evidence KPIs

- Meet the canonical wave budget and introduce zero new visual literal violations at signoff
- `print()` calls in user-facing views on remediated surfaces: `0`
- `EmptyView` placeholders in remediated P0/P1 surfaces where explicit user state is required: `0`
- Forced single-line truncation on remediated critical financial content and primary CTAs: `0`
- Runtime accessibility signal remains on the acceptance path for touched flows

## Risks and Mitigations

- Goals work lands in the wrong stack and duplicates remediation  
  Mitigation: `ContentView -> GoalsList` is treated as the authoritative iOS shell.
- Onboarding still silently exits on failure or loses progress on retry  
  Mitigation: Wave 3 truth model forbids completion commit on recoverable failure and requires progress retention.
- Wave 4 changes bleed into trust-sensitive runtime semantics  
  Mitigation: allowed and forbidden coordinator changes are explicit.
- Color-literal scope ambiguity destabilizes planning again  
  Mitigation: execution is bound to the canonical burndown method and the 44 baseline is retired.
- The program reads as engineering-only without user impact evidence  
  Mitigation: each wave has a user-facing outcome metric and Phase 0 includes baseline measurement work.
- One-engineer staffing proves insufficient after Phase 0  
  Mitigation: mandatory post-Phase-0 staffing checkpoint and pause conditions for 2x scope growth.

## Open Questions

- Should Phase 0 baseline measurement use lightweight product telemetry, scripted QA proxy metrics, or both for Waves 2 and 3?  
  Default answer: use both where implementation cost is small; otherwise scripted QA proxies remain the official baseline.
- Should surviving legacy goals routes be rerouted directly into the authoritative `ContentView` goals shell during Wave 2, or remain as parity-maintained secondary entry points until closeout?  
  Default answer: prefer rerouting if it reduces duplicate UX logic without changing top-level information architecture or navigation policy.

## Freeze Note

This proposal is frozen as the implementation source of truth. All review feedback that blocked approval was resolved in the final revision. No further proposal modifications are permitted; scope changes require a formal change request.
