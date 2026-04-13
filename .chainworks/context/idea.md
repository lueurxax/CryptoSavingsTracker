# Idea Brief: Comprehensive UX Audit and Remediation

| Metadata | Value |
|----------|-------|
| Run ID | D4F404B7-8D3D-483A-956E-5C95F201FD63 |
| Stage | state_1_idea_received |
| Iteration | 1 |
| Attempt | 1 |
| Created | 2026-03-30 |
| Source Language | ru (translated) |
| Prior Run (2) | 5C948C22-950D-43B3-AA2B-C75885E2074F (reached state_4, avg 9.0/10, conditional_approve, 1 blocker) |
| Prior Run (1) | 6443B516-2D1D-4AAA-A8B4-4AD992BBBC46 (reached state_4, avg 7.75/10, 10 blockers, high_confidence convergence) |

---

## Original Idea (verbatim)

> Необходимо через xcode mcp review(или агалогичным способом если не доступно) собрать все проблемы текущего UX и исправить их

## Normalized Summary

Perform a comprehensive UX audit of the CryptoSavingsTracker application using Xcode MCP tooling (build diagnostics, navigator issues, preview rendering) and supplementary static analysis to identify all current UX defects, then implement fixes for every issue found.

---

## Scope

### Platforms in Scope

- **iOS** (SwiftUI, production-ready, iOS 18.0+)
- **macOS** (SwiftUI, production-ready, macOS 15.5+)

### Platforms Out of Scope

- Android (separate toolchain; Xcode MCP not applicable)
- visionOS (UI not yet implemented)

### Audit Method

1. **Primary:** Xcode MCP tooling -- `XcodeListNavigatorIssues`, `BuildProject`, `XcodeRefreshCodeIssuesInFile`, `RenderPreview` for per-view visual inspection.
2. **Supplementary:** Static code analysis (grep for known anti-patterns), review of existing proposal documents, in-code TODO/FIXME scan, accessibility audit against documented requirements.

---

## Project Surface Area

The iOS/macOS codebase under `ios/CryptoSavingsTracker/`:

| Category | Count |
|----------|-------|
| SwiftUI View files | 156 |
| Reusable Components | 47 |
| Chart Components | 11+ |
| ViewModels | 11 |
| Services | 34 |
| Models (SwiftData) | 29 |
| Utilities | 40+ |
| UI Test files | 11+ |
| UX/Design docs | 20+ |
| Proposal docs | 26+ |

### Major Screen Families

| Screen Family | Key Views | Key ViewModel |
|---------------|-----------|---------------|
| Dashboard | `DashboardView`, `GoalDashboardScreen`, `WhatIfView` | `DashboardViewModel`, `GoalDashboardViewModel` |
| Goals | `GoalsListView`, `GoalDetailView`, `AddGoalView`, `EditGoalView` | `GoalViewModel`, `GoalEditViewModel`, `GoalRowViewModel` |
| Monthly Planning | `MonthlyPlanningView`, `PlanningView`, `MonthlyExecutionView` | `MonthlyPlanningViewModel`, `MonthlyExecutionViewModel` |
| Assets | `AddAssetView`, `AssetDetailView`, `AddTransactionView` | `AssetViewModel` |
| Family Sharing | `FamilyAccessView`, `SharedGoalDetailView` | (uses GoalViewModel) |
| Settings | `SettingsView`, `LocalBridgeSyncView` | (direct service calls) |
| Onboarding | `OnboardingFlowView`, `OnboardingStepViews` | (local state) |

---

## Known UX Problem Domains (from existing documentation)

### 1. Error Handling and Recovery UX (P0)

- **Source:** `docs/proposals/RESILIENT_ERROR_HANDLING_RECOVERY_UX_PROPOSAL.md`
- Silent service-layer failures (ExchangeRateService returns 0.0; dashboard shows "$0.00 progress")
- Missing `@Published var error` in GoalViewModel, AssetViewModel, MonthlyExecutionViewModel
- No retry buttons, no inline error banners, no "last updated" timestamps
- Network failures block core functionality (goal creation requires CoinGecko reachability)
- Charts crash or show blank space when data is unavailable

### 2. Accessibility and Dynamic Type (P1)

- **Source:** `docs/proposals/ACCESSIBILITY_DYNAMIC_TYPE_HARDENING_PROPOSAL.md`
- Touch targets below 44x44pt on critical controls
- Text truncation at large accessibility text sizes
- Missing VoiceOver labels/hints on status cards and CTAs
- Fragile layout constraints with fixed sizes

### 3. Navigation and Presentation Consistency (P1)

- **Source:** `docs/NAVIGATION_PRESENTATION_CONSISTENCY.md`
- Dirty-form dismissal not consistently handled across flows
- Modal presentation rules (MOD-01..MOD-05) need enforcement
- iPad layout consistency gaps

### 4. Visual System Consistency (P2)

- **Source:** `docs/VISUAL_SYSTEM_UNIFICATION.md`
- Token-only visuals not fully enforced
- Surface/elevation/state system not uniformly applied
- Cross-platform token parity gaps

### 5. In-Code TODOs (verified in prior runs)

- `ChartErrorView.swift:85`: "Implement help system navigation"
- `AddTransactionView.swift:183`: "Add error state display to UI"
- Additional TODOs to be discovered during audit

---

## Expected Deliverables

1. **UX Audit Report** -- Categorized list of all UX defects found (Xcode issues + static analysis + visual inspection), with severity and affected files.
2. **Implementation Plan** -- Prioritized fix plan grouped by problem domain, with Phase 0 baseline recording.
3. **Code Changes** -- Fixes for all identified UX issues, with tests where applicable.
4. **Verification** -- Post-fix build confirmation, preview renders, and test pass.

---

## Constraints

- Follow MVVM architecture (`Models -> Services -> ViewModels -> Views`)
- Preserve existing test coverage; never disable or skip failing tests
- No secrets in code; use `Config.plist` and `KeychainManager`
- Follow project coding conventions (4-space indent, 120-char wrap, PascalCase types, camelCase props)
- Prefer `PlatformCapabilities` over `#if os()` guards
- Check `docs/COMPONENT_REGISTRY.md` before adding new components
- Update all goal row variants when modifying goal display logic (GoalRowView, GoalSidebarRow, UnifiedGoalRowView)
- Persistence is CloudKit (Phase 1 cutover complete); SwiftData/SQLite is legacy

---

## Prior Run Learnings

### Run 1: 6443B516 (3 review iterations, final avg 7.75/10)

- Reached `state_4_proposal_reviewed` with 3 review iterations
- 10 blocking items remained: concrete implementation details, success metrics, rollback criteria, component reuse specifics, error recovery flow details, accessibility testing plan
- Convergence assessment was "high_confidence" -- reviewers agreed direction was correct
- Key themes: CoalescedErrorBannerView premature/underspecified, hardcoded font count underestimate (~45 vs ~77), AsyncContentView degraded state gap, scope/effort risk management absent

### Run 2: 5C948C22 (2 review iterations, final avg 9.0/10)

- Built on Run 1 convergence; all 10 prior blockers resolved
- Reached **conditional approval** with 9.0/10 average across 4 reviewers (Architect, UX, UI, Product Owner)
- **1 remaining blocker** (PO-B-01): Baseline metrics recording must be gated as Phase 0 (30 min spike)
  - Record crash-free rate, "missing data"/"zero balance" tickets, CI pass rate
  - Commit baseline values to proposal
  - Gate Phase 1 start on Phase 0 completion
- 30 non-blocking issues + 26 suggestions catalogued as implementation guidance
- 8 recurring themes identified: CoalescedErrorBannerView complexity, macOS platform differences, animation edge cases, measurement gaps, success banner underspec, layout token standardization, retry state management, onboarding edge cases
- Proposal strengths (consensus): verified audit data, additive migration strategy, service-layer error broadcasting, Phase 3.5 validation spike, MVP cut-line, component validation tests

### Carryover for This Run

This run must:
1. Resolve PO-B-01 (add Phase 0 baseline recording) in the proposal revision
2. Carry forward the 30 non-blocking issues and 26 suggestions as implementation guidance
3. Progress beyond state_4 into implementation (state_5+)
4. Leverage the high convergence (9.0/10) to minimize further review cycles

---

## Risk Notes

- **Xcode MCP availability:** If Xcode MCP tools are unavailable or return incomplete results, fall back to static analysis, code review, and manual preview rendering.
- **Scope creep:** The audit may surface architectural issues beyond UX. Document but do not fix unless they directly cause user-facing defects.
- **Cross-platform drift:** Fixes to iOS UX may widen the gap with Android. Document parity implications for future Android work.
- **Large surface area:** 156 view files require prioritization by severity; audit P0/P1 domains first.
- **Prior run blocker carryover:** PO-B-01 must be resolved before implementation can begin; fast-track revision expected.
