# Proposal: Comprehensive UX Audit and Remediation

> Systematic identification and resolution of all user-facing UX defects across the CryptoSavingsTracker iOS/macOS application

| Metadata | Value |
|----------|-------|
| Run ID | D4F404B7-8D3D-483A-956E-5C95F201FD63 |
| Status | Draft (Revision 2) |
| Priority | P0 |
| Last Updated | 2026-03-30 |
| Platform | iOS 18.0+ / macOS 15.5+ |
| Scope | Error handling, accessibility, navigation, visual consistency, in-code TODOs |
| Architecture | MVVM + Service Layer + DI (SwiftUI) |
| Persistence | CloudKit (Phase 1 cutover complete) |
| Prior Run (1) | 6443B516 (state_4, avg 7.75/10, high_confidence convergence, 10 blockers resolved in Rev 3) |
| Prior Run (2) | 5C948C22 (state_4, avg 9.0/10, conditional_approve, 1 blocker PO-B-01) |

---

## Revision History

| Revision | Date | Changes |
|----------|------|---------|
| 1 | 2026-03-30 | Initial draft for Run 2. Carries forward all content from Run 1's Revision 3 (which addressed all 10 blocking issues). Additionally addresses all 30 non-blocking issues from 4 reviewers (ARCH-03 through ARCH-09, PO-NB-01 through PO-NB-07, UX-04 through UX-10, UI-04 through UI-12) to target aggregate score above 9. Key additions: error deduplication via service-layer broadcasting (ARCH-03), FreshnessPolicy injectable configuration (ARCH-05), GoalEditViewModel dual-error-surface clarification (ARCH-07), XCTest-native snapshot approach (ARCH-09), test environment setup (PO-NB-01), baseline snapshot (PO-NB-02), user-outcome success criteria (PO-NB-03), fallback list maintenance (PO-NB-06), component validation tests (PO-NB-07), CoalescedErrorBannerView VoiceOver expanded spec (UX-04), FreshnessIndicatorView extension to 3 screens (UX-05), retry timeout/escalation rules (UX-06), help system as contextual sheet (UX-07), MonthlyExecutionView mid-flow spec (UX-08), fallback currency reduced-scope banner (UX-09), visual regression verification (UX-10), banner positioning rules (UI-04), onboarding error UX detail (UI-05), freshness visual escalation (UI-06), ChartErrorView icon in Phase 5 (UI-07), @ScaledMetric dimensional contracts (UI-08), ErrorBannerView token migration (UI-09), ErrorBannerView adaptive layout (UI-11), help navigation target (UI-12), legacy method sunset plan (ARCH-04). |
| 2 | 2026-03-30 | **Resolves PO-B-01** (sole blocker from Run 2 conditional approval at 9.0/10). Adds mandatory Phase 0: Baseline Metrics Recording (30 min) gating Phase 1 start. Phase 0 includes 4 explicit recording steps with concrete tools and data sources. Section 8.5 Baseline Snapshot table updated with recording instructions and fillable fields. Section 7.1 rollout diagram updated to show Phase 0 -> Phase 1 dependency. Section 7.3 effort estimates updated to include Phase 0 (total now 24.5-33.5h). Appendix A updated with Phase 0 file list. Added Section 11: Non-Blocking Implementation Guidance cataloguing all 30 non-blocking issues and 26 suggestions from Run 2 reviewers as execution-phase reference. Added 8 recurring themes with recommended resolutions. No architectural, scope, or specification changes -- all prior content preserved. |

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Goals](#2-goals)
3. [Non-Goals](#3-non-goals)
4. [Audit Findings Summary](#4-audit-findings-summary)
5. [UX/UI Design Notes](#5-uxui-design-notes)
6. [Architecture and Implementation Plan](#6-architecture-and-implementation-plan)
7. [Rollout Strategy](#7-rollout-strategy)
8. [Success Metrics](#8-success-metrics)
9. [Risks and Mitigations](#9-risks-and-mitigations)
10. [Open Questions](#10-open-questions)
11. [Non-Blocking Implementation Guidance](#11-non-blocking-implementation-guidance-run-2-reviewer-feedback)

---

## 1. Problem Statement

The CryptoSavingsTracker application has accumulated UX defects across five distinct problem domains that collectively degrade user trust, accessibility, and visual polish. While the codebase has strong foundational infrastructure (type system, error component library, protocols), the integration of these foundations into the actual user-facing screens is incomplete. Users encounter:

- **Silent failures**: ViewModels catch exchange rate errors and silently skip allocations, causing users to see "$0.00 progress" on the dashboard without any explanation. The user may believe their savings are gone.
- **Inaccessible controls**: Hardcoded font sizes that break Dynamic Type (77 instances across 22 files, including 45 in onboarding alone), chart data points invisible to VoiceOver, and missing accessibility labels on interactive controls.
- **Inconsistent error recovery**: Some ViewModels expose error states; others silently swallow exceptions. Only 4 of 9 ViewModels conform to the `ErrorAwareViewModel` protocol. A separate global `ErrorHandler.shared` singleton can fire alerts simultaneously with per-ViewModel error states, with no defined interaction contract.
- **Visual drift**: Chart error handling uses a parallel `ChartError` type system (6 cases) instead of the unified `UserFacingError`/`ErrorTranslator` pipeline. `CompactChartErrorView` duplicates `ErrorBannerView` with different styling. `ErrorBannerView` itself uses raw `Color` values instead of `AccessibleColors` design tokens.
- **Incomplete TODO items**: In-code stubs for error display (`AddTransactionView`) and help navigation (`ChartErrorView`) remain unimplemented.
- **Onboarding blind spot**: The user's first experience has 45 hardcoded font sizes (40 in OnboardingStepViews + 5 in OnboardingFlowView), zero user-facing error handling (network failures silently complete onboarding), and incomplete VoiceOver coverage.

### Quantified Gap

| Layer | Target Coverage | Current Coverage | Gap |
|-------|----------------|-----------------|-----|
| ViewModel -> ErrorAwareViewModel | 9/9 ViewModels | 4/9 conforming | 5 ViewModels |
| ErrorTranslator -> AppError mapping | 25/25 cases | 9/25 cases (16 fall to generic) | 16 cases |
| View -> AsyncContentView integration | All async screens | ~0/15 (component exists, not used) | Full |
| Accessibility -> Dynamic Type (no hardcoded font sizes) | 100% text/layouts | 77 hardcoded `.system(size:)` instances across 22 files (68 literal + 9 proportional) | 77 instances |
| Accessibility -> Chart data point VoiceOver | All interactive charts | 1/4 chart types (ProgressRingView only) | 3 chart types |
| ErrorHandler.shared vs ErrorAwareViewModel routing | Defined contract | No contract | Full |
| In-code TODOs resolved | 2/2 | 0/2 | 2 |
| ErrorBannerView using AccessibleColors tokens | 100% | 0% (uses raw Color) | Full |

---

## 2. Goals

1. **Zero silent failures**: Every service error propagates through ViewModel to View with a user-readable explanation and (where applicable) a retry action.
2. **Universal tri-state views**: Every asynchronous screen has loading, content, and error states via `AsyncContentView`.
3. **Complete ErrorAwareViewModel adoption**: All 9 ViewModels conform to the protocol with `viewState`, `lastSuccessfulLoad`, and `retry()`.
4. **Defined error routing contract**: Clear rules governing when errors use `ErrorHandler.shared` (global alert) vs. per-ViewModel `viewState` (inline), with suppression to prevent double-presentation.
5. **WCAG AA accessibility**: All text uses semantic font styles for Dynamic Type; no color-only status indicators; chart data points are VoiceOver-accessible.
6. **Unified error taxonomy**: Bridge `ChartError` into the `AppError`/`UserFacingError`/`ErrorTranslator` pipeline; deprecate `CompactChartErrorView` in favor of `ErrorBannerView`.
7. **Complete ErrorTranslator**: Map all 25 `AppError` cases to `UserFacingError` with distinct or grouped messages (16 currently unmapped), including financial reassurance clauses.
8. **Resolve all in-code TODOs**: Implement error state display in `AddTransactionView` and help system navigation in `ChartErrorView`.
9. **Graceful offline degradation**: `AddGoalView` works with cached currency list when CoinGecko is unreachable. Onboarding handles network failures with user-visible feedback. Fallback currency list shows reduced-scope indicator.
10. **Error deduplication on list screens**: When a shared root cause (e.g., exchange rate failure) affects N items, show one top-level banner instead of N per-item error states, using service-layer error broadcasting.
11. **Error-to-recovery in 2 taps or fewer**: Every retryable error provides a recovery path within 2 user actions, including pull-to-refresh as a universal fallback.
12. **Design token compliance**: All error components use `AccessibleColors` tokens instead of raw `Color` values before mass adoption across 15+ screens.

---

## 3. Non-Goals

- **Full rebrand or typography redesign** - Visual System Unification (docs/VISUAL_SYSTEM_UNIFICATION.md) has its own wave-based rollout; this proposal fixes functional UX defects only.
- **Android parity** - Android uses a separate toolchain (Kotlin/Compose). Parity implications are documented but not implemented here.
- **visionOS UI** - Platform capabilities defined but UI not yet implemented.
- **Offline mutation queuing** - Covered by a separate Offline-First proposal.
- **Analytics/telemetry for error rates** - Future work; we fix the UX first.
- **Chart-specific advanced palette redesign** - Covered by Data Viz Motion ADR.
- **New feature development** - This proposal is remediation-only. Note: `CoalescedErrorBannerView` is acknowledged as new component scope (~2-3 hours) with an explicit MVP fallback (stacked `ErrorBannerView` instances) if cut.
- **Full iPad redesign** - Only fixes minimum accessibility and layout consistency; comprehensive iPad layout is separate work.
- **EmptyStateView redesign** - The existing `EmptyStateView` with its 7 factory methods and illustration system is adequate. Only gap is `EmptyGoalsView` button accessibility; fixed in Phase 5.
- **Legacy async-throws method removal** - The additive ServiceResult migration adds `*Result` methods alongside existing methods. Full removal of legacy methods is tracked follow-up work (see Section 10, OQ-8).

---

## 4. Audit Findings Summary

### 4.1 Error Handling and Recovery UX (P0 - Trust and Correctness)

**Source**: `docs/proposals/RESILIENT_ERROR_HANDLING_RECOVERY_UX_PROPOSAL.md` + line-level code audit

**Infrastructure status**: The foundational types and components are already implemented but not integrated.

| Component | File | Status |
|-----------|------|--------|
| `ServiceResult<T>` enum (4 cases: fresh/cached/fallback/failure) | `Utilities/ServiceResult.swift` | Exists (90% complete) |
| `ViewState` enum (5 cases: idle/loading/loaded/error/degraded) | `Utilities/ServiceResult.swift` | Exists (95% complete) |
| `UserFacingError` struct | `Utilities/ServiceResult.swift` | Exists (95% complete) |
| `ErrorTranslator` | `Utilities/ServiceResult.swift` | Exists (36% - maps 9/25 AppError cases) |
| `ErrorAwareViewModel` protocol | `Protocols/ErrorAwareViewModel.swift` | Exists (100% spec complete) |
| `AsyncContentView` | `Views/Components/AsyncContentView.swift` | Exists (95% complete) |
| `ErrorBannerView` | `Views/Components/ErrorBannerView.swift` | Exists (95% complete; uses raw colors, not AccessibleColors tokens) |
| `ErrorStateView` | `Views/Components/ErrorStateView.swift` | Exists (90% complete; missing secondary action) |
| `FreshnessIndicatorView` | `Views/Components/FreshnessIndicatorView.swift` | Exists (90% complete; single visual state, no escalation) |
| `ErrorHandler.shared` (global singleton) | `Utilities/ErrorHandling.swift` | Exists (legacy, no interaction contract with ErrorAwareViewModel) |

**AppError enum - verified 25 cases** (source: `Utilities/ErrorHandling.swift`):

| Category | Cases | Count |
|----------|-------|-------|
| Network | `networkUnavailable`, `invalidURL(String)`, `requestTimeout`, `invalidResponse`, `decodingFailed(String)`, `rateLimited` | 6 |
| API-Specific | `apiKeyInvalid`, `apiQuotaExceeded`, `coinNotFound(String)`, `chainNotSupported(String)`, `addressInvalid(String)` | 5 |
| Data | `goalNotFound`, `assetNotFound`, `transactionNotFound`, `saveFailed`, `deleteFailed`, `modelContextUnavailable` | 6 |
| Calculation | `invalidAmount`, `invalidDate`, `calculationFailed`, `currencyConversionFailed` | 4 |
| Platform | `featureUnavailable(String)`, `permissionDenied(String)`, `widgetUpdateFailed`, `notificationsFailed` | 4 |
| **Total** | | **25** |

**ErrorTranslator coverage - 9 explicitly mapped, 16 unmapped**:

| Mapped (9) | Unmapped (16) |
|-----------|---------------|
| `networkUnavailable` | `invalidURL`, `invalidResponse`, `decodingFailed` |
| `requestTimeout` | `coinNotFound`, `chainNotSupported`, `addressInvalid` |
| `apiKeyInvalid` | `goalNotFound`, `assetNotFound`, `transactionNotFound` |
| `apiQuotaExceeded` | `deleteFailed` |
| `rateLimited` | `invalidAmount`, `invalidDate` |
| `currencyConversionFailed` | `featureUnavailable`, `permissionDenied` |
| `saveFailed` | `widgetUpdateFailed`, `notificationsFailed` |
| `calculationFailed` | |
| `modelContextUnavailable` | |

**ViewModel conformance audit**:

| ViewModel | ErrorAwareViewModel | viewState | retry() | Error Exposure | Failure Pattern |
|-----------|:--:|:--:|:--:|------|------|
| GoalViewModel | Yes | Yes | Yes | No @Published error | Silent log + `continue` (skips allocations) |
| AssetViewModel | Yes | Yes | Yes | `balanceError: String?` | Cache fallback |
| DashboardViewModel | Yes | Yes | Yes | No @Published error | Silent log + continue |
| GoalRowViewModel | Yes | Yes | Yes | `hasError: Bool` (flag only) | Flag never set to true |
| MonthlyExecutionViewModel | No | No | No | `error: Error?` (raw) | Sets error property |
| MonthlyPlanningViewModel | No | No | No | `error: Error?` (raw) | Sets error property |
| GoalEditViewModel | No | No | No | None | Throws to caller |
| GoalDashboardViewModel | No | No | No | None | Delegated |
| CurrencyViewModel | No | No | No | None | Silent (service handles) |

**Critical user-facing defects**:

| ID | Defect | Root Cause (verified) | Impact | Affected Screen |
|----|--------|----------------------|--------|----------------|
| ERR-01 | Silent "$0.00 progress" when exchange rates fail | `GoalViewModel.calculateCurrentTotal()` (line 93-100) catches exchange rate errors and calls `continue`, skipping the allocation entirely. When all allocations fail, total = 0.0. Note: `ExchangeRateService.getFallbackRate()` correctly returns `nil` (never fakes rates). | User sees "$0.00 progress" and may believe savings are gone | Dashboard, GoalDetail |
| ERR-02 | CoinGecko failure blocks goal creation entirely | No cached/fallback currency list | User cannot create goals offline | AddGoalView |
| ERR-03 | GoalViewModel swallows exchange rate errors | `calculateCurrentTotal()` logs error but never sets `viewState` to `.error` | Progress shows 0% without explanation | GoalDetail, GoalRow |
| ERR-04 | DashboardViewModel chart sections fail silently | Chart data errors caught and logged but not surfaced to viewState | Charts blank with no error state | DashboardView |
| ERR-05 | MonthlyExecutionViewModel has raw Error, no retry | Uses `error: Error?` property instead of `ErrorAwareViewModel` | User stuck on error with no recovery | MonthlyExecutionView |
| ERR-06 | CurrencyViewModel has no error handling at all | No error property, no viewState | Currency list may be empty silently | AddGoalView, EditGoalView |
| ERR-07 | ChartError parallel type system | 6-case `ChartError` enum with own `ChartLoadingState` separate from `ViewState`/`UserFacingError` | Error UX inconsistent between charts and other views | All chart views |
| ERR-08 | ErrorTranslator missing 16 AppError cases | Default fallback returns generic "Something Went Wrong" | Untranslated errors show unhelpful message | Various |
| ERR-09 | GoalRowViewModel `hasError` flag never set | `hasError: Bool` exists but no code path sets it to `true` | Error state unreachable on goal rows | GoalsListView |
| ERR-10 | Onboarding swallows network errors | `createGoalFromTemplate()` catches error, prints to console, completes onboarding anyway | User's first goal may silently fail to create | OnboardingFlowView |
| ERR-11 | ErrorHandler.shared and ErrorAwareViewModel can fire simultaneously | No suppression mechanism | User sees duplicate error presentation | Any screen with both patterns |

### 4.2 Accessibility and Dynamic Type (P1)

**Source**: `docs/proposals/ACCESSIBILITY_DYNAMIC_TYPE_HARDENING_PROPOSAL.md` + line-level verified code audit

> **Audit accuracy note**: Three findings from a prior revision (A11Y-01, A11Y-02, A11Y-06) were confirmed as false positives via line-level code verification and have been removed. Remaining findings are verified against source.

**Removed false positives** (verified correct in source):
- ~~A11Y-01~~: GoalRequirementRow toggle already has `.frame(minWidth: 44, minHeight: 44)` at line 306.
- ~~A11Y-02~~: CompactGoalRequirementRow badge includes `Image(systemName: requirement.status.systemImageName)` alongside color circle at line 184. Not color-only.
- ~~A11Y-06~~: GoalRequirementRow status includes `Image(systemName: statusIcon)` alongside color circle at line 210. Not color-only.

**Verified findings**:

| ID | Defect | Severity | File | Line(s) | Verified |
|----|--------|----------|------|---------|:--:|
| A11Y-03 | DashboardView widget remove button lacks accessibility label | HIGH | DashboardView.swift | 455-461 | Yes |
| A11Y-04 | DashboardView empty state icon uses hardcoded `.system(size: 48)` | HIGH | DashboardView.swift | 271 | Yes |
| A11Y-05 | PlanningView uses hardcoded `.system(size: 40)` and `.system(size: 64)` | HIGH | Planning/PlanningView.swift | 526, 1136 | Yes |
| A11Y-07 | GoalDetailView progress ring uses fixed 180pt height | MEDIUM | GoalDetailView.swift | 268, 278 | Yes |
| A11Y-08 | Chart placeholders use fixed 40pt heights | MEDIUM | DashboardView.swift | 212-220 | Yes |
| A11Y-09 | SimpleStackedBarView uses fixed 40pt heights and widths | MEDIUM | Charts/SimpleStackedBarView.swift | 80, 87, 116, 141 | Yes |
| A11Y-10 | GoalDetailView assets section fixed 200pt height | MEDIUM | GoalDetailView.swift | 307 | Yes |
| A11Y-11 | Missing accessibility identifiers on goal navigation links | LOW | GoalsListView.swift | 62-64 | Yes |
| A11Y-12 | OnboardingFlowView + OnboardingStepViews: 45 hardcoded `.system(size:)` font sizes (5 + 40 respectively) | HIGH | Onboarding/OnboardingFlowView.swift, Onboarding/OnboardingStepViews.swift | Multiple | Yes |
| A11Y-13 | EnhancedLineChartView: interactive data points have no VoiceOver labels; drag-to-select announces nothing | HIGH | Charts/EnhancedLineChartView.swift | 107-126 | Yes |
| A11Y-14 | LineChartView: view-level label only ("Balance History"), no data point detail | MEDIUM | Charts/LineChartView.swift | 56 | Yes |
| A11Y-15 | CompactProgressRingView: no accessibility elements defined (full ProgressRingView has excellent a11y) | MEDIUM | Charts/ProgressRingView.swift | (compact variant) | Yes |
| A11Y-16 | EmptyGoalsView: action button lacks accessibility label | LOW | Views/EmptyGoalsView.swift | (button) | Yes |
| A11Y-17 | Dashboard components: 4 hardcoded `.system(size: N)` across EnhancedDashboardComponents (18pt, 24pt, 20pt) and DashboardComponents (40pt) | MEDIUM | Dashboard/EnhancedDashboardComponents.swift, Dashboard/DashboardComponents.swift | 70, 82, 322, 366 | Yes |
| A11Y-18 | Empty state components: 5 hardcoded `.system(size: N)` across EmptyStateView (48/64pt, 24pt, 32pt), EmptyGoalsView (64pt), EmptyDetailView (48pt) | MEDIUM | Components/EmptyStateView.swift, Components/EmptyGoalsView.swift, Components/EmptyDetailView.swift | 50, 257, 280, 17, 38 | Yes |
| A11Y-19 | Chart proportional fonts: 9 `.system(size: size * N)` instances using proportional sizing instead of `@ScaledMetric` across ProgressRingView (6), SparklineChartView (1), StackedBarChartView (2) | MEDIUM | Charts/ProgressRingView.swift, Charts/SparklineChartView.swift, Charts/StackedBarChartView.swift | Multiple | Yes |
| A11Y-20 | Miscellaneous components: 6 hardcoded `.system(size: N)` across HeroProgressView (42pt), FlexAdjustmentSlider (16pt), GoalSwitcherBar (32pt), MonthlyPlanningWidget (14pt, 32pt), ChartErrorView (48pt) | MEDIUM | Components/HeroProgressView.swift, Components/FlexAdjustmentSlider.swift, Components/GoalSwitcherBar.swift, Components/MonthlyPlanningWidget.swift, Components/ChartErrorView.swift | 57, 244, 142, 109, 399, 21 | Yes |
| A11Y-21 | Remaining views: 4 hardcoded `.system(size: N)` across AssetDetailView (32pt), GoalComparisonView (48pt), TransactionHistoryView (48pt), GoalRequirementRow (14pt) | MEDIUM | Views/AssetDetailView.swift, Goals/GoalComparisonView.swift, TransactionHistoryView.swift, Planning/GoalRequirementRow.swift | 100, 81, 227, 211 | Yes |

### 4.3 Navigation and Presentation Consistency (P1)

**Source**: `docs/NAVIGATION_PRESENTATION_CONSISTENCY.md`

Current status from the document's hard cutover governance section:

| Check | Status |
|-------|--------|
| NAV001 (Forbidden API) | 0 open findings |
| NAV002 (Missing decision tag) | 0 open findings |
| NAV003 (Preview segregation) | 0 open findings |
| Hard-cutover scanner | Pass |

The navigation architecture is clean. Remaining work is enforcement and edge-case hardening:

| ID | Defect | Severity |
|----|--------|----------|
| NAV-01 | Dirty-form dismissal behavior not verified in all MOD-02 flows (budget edit, goal edit, contribution edit) | MEDIUM |
| NAV-02 | iPad popover-to-sheet fallback for MOD-01 not validated end-to-end | LOW |
| NAV-03 | MonthlyExecutionView error recovery path unclear when tracking fails mid-flow | MEDIUM |

### 4.4 Visual System Consistency (P2)

**Source**: `docs/VISUAL_SYSTEM_UNIFICATION.md`

| ID | Defect | Severity |
|----|--------|----------|
| VIS-01 | ChartErrorView uses custom color scheme separate from token system | LOW |
| VIS-02 | ExchangeRateWarningView is domain-specific, not reusable, makes network call on every appear | MEDIUM |
| VIS-03 | ErrorBannerView uses only 2 distinct colors for 4 error categories | LOW |
| VIS-04 | CompactChartErrorView duplicates ErrorBannerView with different styling (padding, corners, backgrounds) | MEDIUM |
| VIS-05 | ErrorBannerView uses raw `Color(.orange, .red)` instead of `AccessibleColors` tokens (lines 82-98) | MEDIUM |

### 4.5 In-Code TODOs and FIXMEs (P1)

| ID | File | Line | TODO | Severity |
|----|------|------|------|----------|
| TODO-01 | Views/AddTransactionView.swift | 183 | "Add error state display to UI" | HIGH |
| TODO-02 | Views/Components/ChartErrorView.swift | 85 | "Implement help system navigation" | MEDIUM |

---

## 5. UX/UI Design Notes

### 5.1 Error Routing Contract: ErrorHandler.shared vs. ErrorAwareViewModel

The codebase has two error presentation mechanisms that currently lack an interaction contract:

1. **`ErrorHandler.shared`** - A `@MainActor` singleton with `@Published currentError` and `showingError`, consumed by `ErrorAlertModifier` to show modal alerts. Fire-and-forget.
2. **`ErrorAwareViewModel.viewState`** - Per-ViewModel `ViewState` enum consumed by `AsyncContentView` to show inline error states. Contextual, retryable.

**Decision**: Screens that adopt `AsyncContentView` with `ErrorAwareViewModel` handle errors inline. `ErrorHandler.shared` is reserved for fire-and-forget operations where no ViewModel owns the error context.

| Error Origin | Routing | Presentation | Rationale |
|-------------|---------|--------------|-----------|
| ViewModel conforming to ErrorAwareViewModel | Per-ViewModel `viewState` via `setError()` | Inline via `AsyncContentView` (ErrorStateView or ErrorBannerView) | ViewModel owns the context, can provide retry |
| Fire-and-forget operation (widget update, notification registration) | `ErrorHandler.shared.handle()` | Modal alert via `ErrorAlertModifier` | No owning ViewModel; user must acknowledge |
| Background service refresh (no visible screen) | Logged only via `AppLog` | None (deferred to next screen load) | Avoid interrupting user with unrelated errors |

**Suppression rule**: A ViewModel conforming to `ErrorAwareViewModel` MUST NOT also call `ErrorHandler.shared.handle()` for the same error. Phase 3 includes an audit of all `ErrorHandler.shared.handle()` call sites in conforming ViewModels to replace with `setError()`.

**Enforcement**:
- Add code comment convention: `// ERROR-ROUTING: global` or `// ERROR-ROUTING: viewmodel` at each error handling site.
- Document in `docs/ERROR_ROUTING_CONTRACT.md` (Phase 1 deliverable).
- New ViewModel code MUST use `*Result` methods from Phase 2. Legacy `async throws` methods are for backward compatibility only (see Section 10, OQ-8 sunset plan).

### 5.2 Error Tier Decision Matrix

Three tiers of error communication, with explicit governing rules:

| Tier | Component | When to Use | Visual Weight |
|------|-----------|-------------|---------------|
| **T1: Blocking** | `ErrorStateView` | Zero usable data AND no cache available | Full-screen, requires user action |
| **T2: Inline Banner** | `ErrorBannerView` | Cached/stale data available but refresh failed | Non-blocking, dismissible, above content |
| **T3: Freshness** | `FreshnessIndicatorView` | Data loaded but age > freshness threshold | Subtle, informational, with visual escalation |

**Screen-by-failure-mode matrix**:

| Screen | Network Down (no cache) | Network Down (has cache) | API Error (retryable) | API Error (non-retryable) | Data Error | Mid-Flow Save Failure |
|--------|:--:|:--:|:--:|:--:|:--:|:--:|
| DashboardView | T1 (first load) / T2 (refresh) | T2 + T3 | T2 | T2 + "Go to Settings" | T1 | N/A |
| GoalDetailView | T2 (goal data is local) | T2 + T3 | T2 | T2 | T1 | N/A |
| AddGoalView (currency list) | T2 (with fallback list + reduced-scope banner) | T2 | T2 | T2 + "Go to Settings" | T1 | N/A |
| MonthlyExecutionView | T1 (initial load) | T2 + T3 | T2 | T2 | T1 | T2 (see Section 5.20) |
| MonthlyPlanningView | T1 | T2 + T3 | T2 | T2 | T1 | N/A |
| GoalsListView | T2 (goals are local) | T2 + T3 | T2 (coalesced) | T2 | T1 | N/A |
| OnboardingFlowView | T2 (allow offline completion; see Section 5.18) | T2 | T2 | T2 | T2 | N/A |
| AddTransactionView | T2 | T2 | T2 | T2 | T1 | N/A |

**Freshness thresholds** (injectable via `FreshnessPolicy`, see Section 5.2.1):
- Exchange rates: stale after 5 minutes, warning after 30 minutes
- Balance data: stale after 15 minutes, warning after 1 hour
- Currency list: stale after 24 hours

**Governing rule**: If in doubt, prefer T2 (inline banner) over T1 (blocking). T1 should only appear when the screen literally cannot render any meaningful content.

#### 5.2.1 FreshnessPolicy Injectable Configuration

Freshness thresholds are operational parameters that may need tuning based on CoinGecko API plan tier, user behavior patterns, or market volatility. Rather than hardcoding them, define an injectable configuration:

```swift
struct FreshnessPolicy {
    let staleThreshold: TimeInterval
    let warningThreshold: TimeInterval

    static let exchangeRate = FreshnessPolicy(staleThreshold: 300, warningThreshold: 1800)
    static let balance = FreshnessPolicy(staleThreshold: 900, warningThreshold: 3600)
    static let currencyList = FreshnessPolicy(staleThreshold: 86400, warningThreshold: 172800)
}
```

- Registered in `DIContainer` with static factory defaults.
- Overridable via `Config.plist` for per-environment tuning (aligns with existing `Config.plist` pattern for non-secret configuration).
- Services consume `FreshnessPolicy` from DI instead of hardcoded constants.
- Phase 1 deliverable (Step 1.9).

### 5.3 State Transition Contract

Every async screen MUST implement the following state transitions with consistent animation:

```
                    +----------------------------+
                    |                            |
    +-------+  load()  +---------+  success  +--------+
    | idle  |-------->| loading |-------->| loaded |
    |       |         |         |         |        |
    +-------+         +----+----+         +---+----+
                          |                    |
                     failure                refresh failure
                          |                    |
                          v                    v
                    +---------+         +-----------+
                    |  error  |         | degraded  |
                    |  (T1)   |         |  (T2/T3)  |
                    +----+----+         +-----+-----+
                         |                    |
                    retry()              retry()
                         |                    |
                         v                    v
                    +---------+         +---------+
                    | loading |         | loading  |
                    +---------+         |(content  |
                                        | visible) |
                                        +---------+
```

**Animation rules** (applied via `AsyncContentView`):

| Transition | Animation | Duration |
|-----------|-----------|----------|
| idle -> loading | `.easeIn` | 0.2s |
| loading -> loaded | `.easeOut` with content fade-in | 0.3s |
| loading -> error | `.easeOut` | 0.3s |
| loaded -> degraded | `.spring(response: 0.3)` banner slide-down | 0.3s |
| error -> loading (retry) | `.easeIn` | 0.2s |
| degraded -> loaded (refresh success) | `.spring(response: 0.3)` banner slide-up dismiss | 0.3s |
| error/degraded -> loaded (success feedback) | Banner transitions to `.success` style (green, checkmark) for 1.5s, then slides up to dismiss | 1.8s total |

**Critical rule**: During retry from `degraded` state, content MUST remain visible with a subtle loading indicator (spinner in navigation bar or inline `ProgressView` overlay at reduced opacity). Content MUST NOT be replaced by a full-screen loading state.

**Haptic feedback**: Error/degraded state transitions trigger `UINotificationFeedbackGenerator.notification(.warning)`. Successful retry recovery triggers `.notification(.success)`. Implemented centrally in `AsyncContentView` for consistency.

#### 5.3.1 Retry Behavior Rules

Every retry interaction follows these escalation rules:

| Rule | Specification |
|------|--------------|
| **Timeout** | 15 seconds per retry attempt. After timeout, show "Still trying... [Cancel]" inline in the banner. |
| **Cancellation** | User can cancel a retry, returning to the pre-retry error/degraded state. Cancel button appears after 5s timeout. |
| **Failure escalation** | After 3 consecutive failures of the same error, change retry button text to "Try Later" and disable automatic retry. Manual retry remains available via pull-to-refresh. |
| **Retry indicator** | Spinner replaces the "Retry" text in the banner button (not a separate indicator). |
| **Cooldown** | No automatic cooldown between manual retries. Rate limiting is the service layer's responsibility (via `RateLimiter`). |

### 5.4 Error Deduplication Pattern for List Screens

When multiple items share the same root-cause error (e.g., `ExchangeRateService` failure affecting all `GoalRowView` instances), the list screen MUST coalesce errors.

**Rule**: One top-level banner per unique root cause, NOT per-item banners.

```
+---------------------------------------------------+
| [!] Exchange rates unavailable              [Retry]|
| Affecting 5 goals. Using cached rates from 2h ago  |
+---------------------------------------------------+
| Goal 1: "Bitcoin Savings"     $1,200 (cached)      |
| Goal 2: "ETH Fund"           $850 (cached)         |
| Goal 3: "Emergency Crypto"   $2,100 (cached)       |
+---------------------------------------------------+
```

#### 5.4.1 Service-Layer Error Broadcasting (Deduplication Interface)

Rather than coupling parent ViewModels to child ViewModel internals, error deduplication uses service-layer broadcasting:

```swift
// ExchangeRateService already knows about its own errors.
// Publish a shared error state that all consumers can observe.
protocol ExchangeRateServiceProtocol {
    // Existing methods...
    var serviceError: AnyPublisher<AppError?, Never> { get }  // NEW
}
```

**Pattern**:
1. Each service publishes its current error state via a `@Published` property exposed through the protocol.
2. Child ViewModels (e.g., `GoalRowViewModel`) observe the service's error state and self-transition to `.degraded("Using cached data")` when the service errors.
3. The list-level banner (e.g., in `GoalsListView`) observes the same service error directly to show a single coalesced banner.
4. The banner's "Retry" action calls the service's retry method, which clears the published error on success.
5. Child ViewModels auto-recover when the service error clears (Combine subscription).

**Benefits over parent-inspects-children**:
- No parent-child ViewModel coupling.
- Service layer owns the error state (aligned with MVVM).
- Error deduplication is automatic -- the service publishes once, N consumers observe.
- Independently testable (mock service error publisher in tests).

**Implementation**: Phase 3, Step 3.10. Services that participate: `ExchangeRateService`, `BalanceService`, `CoinGeckoService`.

### 5.5 Dashboard Multi-Error Coalescing

When the Dashboard has multiple concurrent failures, apply priority coalescing:

```
+---------------------------------------------------+
|  [!] 3 services experiencing issues          [v]  |
+---------------------------------------------------+
|  Expanded (tap chevron):                           |
|                                                    |
|  [Network] Exchange rates unavailable     [Retry]  |
|  Using cached rates from 2 hours ago               |
|                                                    |
|  [Network] Balance refresh failed         [Retry]  |
|  Showing balances from 45 minutes ago              |
|                                                    |
|  [Calc] Chart calculation error           [Retry]  |
|  Portfolio allocation chart unavailable             |
|                                                    |
|                                    [Retry All]     |
+---------------------------------------------------+
| [Normal dashboard content with cached/partial data]|
+---------------------------------------------------+
```

**Collapsed state progressive disclosure**: When collapsed, show the highest-priority error inline: "Exchange rates unavailable (+2 more)" so users get actionable info without expanding. Follows iOS notification grouping patterns.

**Coalescing rules**:

| Rule | Specification |
|------|--------------|
| Collapse threshold | >= 2 concurrent errors: show collapsed summary with count badge. == 1: show single `ErrorBannerView` directly |
| Priority ordering | Network > API Key > Data Corruption > Calculation > Unknown |
| Max expanded errors | 5 visible; additional errors collapsed with "+N more" |
| Per-error actions | Individual "Retry" button per expanded error |
| Bulk action | "Retry All" button at bottom of expanded list |
| Dismiss behavior | Dismissing collapsed banner dismisses all. Individual errors can be dismissed within expanded view |

**Visual specification**:

| Property | Value |
|----------|-------|
| Corner radius | 10pt (matches `ErrorBannerView`) |
| Collapsed background | Highest-severity category color among contained errors (per `AccessibleColors` token mapping: `dataCorruption` > `apiKey` > `network` > `unknown`) |
| Collapsed title | `.subheadline.semibold` |
| Collapsed icon | Category icon of highest-severity error |
| Collapsed detail | Highest-priority error title + "(+N more)" in `.caption` |
| Chevron | SF Symbol `chevron.down`, rotation animated with `.spring(response: 0.3)` |
| Expanded items | `VStack(spacing: 8)` of individual error rows |
| Expanded max height | `ScrollView` capped at 400pt; content scrolls if exceeded |
| Expanded behavior | Pushes content down (not overlay) |
| Padding | 12pt (matches `ErrorBannerView`) |
| "Retry All" button | `.bordered` style, `.controlSize(.small)`, bottom of expanded VStack with 12pt top spacing |

**VoiceOver interaction specification**:

| State | Element | Accessibility |
|-------|---------|---------------|
| Collapsed | Banner container | `.accessibilityLabel("3 services experiencing issues. Most urgent: Exchange rates unavailable.")` `.accessibilityHint("Double-tap to expand error list.")` |
| Expanded | Banner container | `.accessibilityContainer(isModal: false)` |
| Expanded | Collapse chevron | `.accessibilityLabel("Collapse error list")` `.accessibilityHint("Double-tap to collapse.")` |
| Expanded | Each error row | `.accessibilityElement(children: .combine)` `.accessibilityLabel("[title]: [message]")` `.accessibilityValue("[recoverySuggestion]")` `.accessibilityHint("Double-tap to retry.")` |
| Expanded | "Retry All" button | `.accessibilityLabel("Retry all failed services")` `.accessibilityHint("Retries all 3 failed services.")` |
| On Retry All | Announcement | `UIAccessibility.post(notification: .announcement, argument: "Retrying 3 services")` |
| On Retry All result | Announcement | `"2 of 3 services recovered"` or `"All services recovered"` |
| On individual dismiss | Announcement | `"Error dismissed. 2 remaining."` |
| Tab order | Sequential | Collapse chevron -> error 1 -> error 2 -> ... -> "Retry All" |

**Component**: New `CoalescedErrorBannerView` wrapping multiple `UserFacingError` instances (Phase 4 deliverable). Extracted from `DashboardViewModel` via a `DashboardErrorAggregator` coordinator object that observes per-section error states and produces a `[UserFacingError]` array. This keeps `DashboardViewModel`'s responsibilities bounded and makes coalescing logic independently testable.

**MVP fallback** (if `CoalescedErrorBannerView` is cut from scope): Dashboard uses stacked `ErrorBannerView` instances in a `VStack(spacing: 8)` without coalescing interaction. Functionally equivalent (all errors visible with individual retry) but without collapsed/expanded toggle.

### 5.6 ChartErrorView.compact Resolution

**Decision**: `CompactChartErrorView` is **deprecated**. Chart inline errors will use `ErrorBannerView` with chart-specific icon/message via the `ChartError.toUserFacingError()` bridge.

**Rationale**: Both components serve the same purpose (inline, non-blocking, retryable error) but diverge in:
- Padding (12pt vs 12pt horizontal)
- Corner radius (8pt vs 10pt)
- Background color derivation (hardcoded `AccessibleColors.warningBackground` vs category-mapped)
- Typography (`.caption2` vs `.caption`)
- Layout (no title vs title + message)

Maintaining two components for the same pattern creates visual inconsistency and maintenance burden.

**Migration path**:
1. Add `ChartError.toUserFacingError()` extension mapping all 6 cases (Phase 1).
2. Replace `CompactChartErrorView` usages with `ErrorBannerView(error: chartError.toUserFacingError(), ...)` (Phase 4).
3. Mark `CompactChartErrorView` as `@available(*, deprecated, message: "Use ErrorBannerView with ChartError.toUserFacingError()")` (Phase 1).
4. Keep full `ChartErrorView` (blocking variant with help navigation) - it serves a distinct purpose.
5. Update `docs/COMPONENT_REGISTRY.md`.
6. Phase 7 verification gate: `CompactChartErrorView` active usages == 0 (grep check).

### 5.7 Accessibility Design Rules

- **Font sizes**: Use semantic styles (`.body`, `.headline`, `.subheadline`, `.caption`, `.title`, `.largeTitle`) exclusively. Replace all `.system(size: N)` instances. Preserve `.fontDesign(.rounded)` modifier where onboarding uses rounded design (see Section 5.18).
- **Chart data points**: Interactive chart selections must announce value, date, and context via VoiceOver `.accessibilityValue` (e.g., "March 15: $1,250.45 USD").
- **Status indicators**: Icon + text label, never color-only. Already verified correct for GoalRequirementRow and CompactGoalRequirementRow.
- **Layout**: Use adaptive stacks that reflow at large accessibility text sizes.
- **VoiceOver**: Explicit `accessibilityLabel` and `accessibilityHint` on every interactive element, including icon-only buttons.
- **Accessibility identifiers**: Add to all navigation links and interactive elements for UI test automation.

**Semantic font mapping reference**:

| Hardcoded Size | Semantic Replacement | Typical Usage | Notes |
|---------------|---------------------|---------------|-------|
| 60-64pt | `.largeTitle` | Hero icons, celebration states | Renders ~34pt at default; verify visual hierarchy |
| 40-48pt | `.title` | Section headers, empty state icons | Use `@ScaledMetric` for SF Symbol sizing |
| 28pt | `.title2` | Welcome/completion titles | Add `.fontDesign(.rounded)` in onboarding |
| 24pt | `.title3` | Sub-section headers | |
| 20pt | `.headline` | Feature highlights | |
| 16-18pt | `.body` | Body text, option labels | |
| 14pt | `.subheadline` or `.footnote` | Secondary text, captions | |

**@ScaledMetric dimensional contracts** (for elements that need precise sizing):

| Component | Property | Default | Min | Max | RelativeTo |
|-----------|----------|---------|-----|-----|-----------|
| Progress ring (GoalDetailView) | `ringHeight` | 180pt | 120pt | 280pt | `.body` |
| Chart bars (SimpleStackedBarView) | `barWidth` | 40pt | 24pt | 64pt | `.caption` |
| Chart bar container | `containerHeight` | 200pt | 120pt | 360pt | `.body` |
| SF Symbol icons in error views | `iconSize` | 48pt | 32pt | 72pt | `.title` |
| Proportional chart fonts | `baseFontSize` | Per current value | 0.7x | 1.5x | `.caption` |

### 5.8 Error Recovery UX Contract

Every retryable error must provide a single-tap retry path:

| Error Location | Recovery UX |
|---------------|-------------|
| Full-screen error | "Try Again" button in `ErrorStateView` |
| Inline banner | "Retry" button in `ErrorBannerView` |
| Chart error | "Try Again" button in `ChartErrorView` (full) |
| Form save failure | Re-enabled "Save" button with error banner above |
| Multi-error dashboard | Individual "Retry" per error + "Retry All" in `CoalescedErrorBannerView` |
| List screen shared error | "Retry" in top-level banner retries all affected items (via service-layer broadcast) |
| Pull-to-refresh | `.refreshable{}` on all scrollable async screens (persistent recovery path) |

Non-retryable errors (e.g., `apiKeyInvalid`) must show a secondary action directing users to the resolution path (e.g., "Go to Settings" in `ErrorStateView`).

### 5.9 AsyncContentView Degraded State Upgrade

The current `AsyncContentView` degraded state renders a static warning banner with no retry or dismiss affordance, creating a dead-end state that contradicts the state transition contract (Section 5.3). This upgrade closes that gap.

**Upgraded component interface** (Phase 1 deliverable):

```swift
struct AsyncContentView<Content: View, Loading: View, ErrorContent: View>: View {
    let state: ViewState
    var onRetryDegraded: (() async -> Void)?   // NEW
    var onDismissDegraded: (() -> Void)?        // NEW
    @ViewBuilder let content: () -> Content
    @ViewBuilder let loading: () -> Loading
    @ViewBuilder let error: (UserFacingError) -> ErrorContent
}
```

**Degraded state rendering**: When `viewState == .degraded(message)`, render using `ErrorBannerView` internally:
1. Synthesize a `UserFacingError` with `.network` category, the degraded message as `message`, and `isRetryable = (onRetryDegraded != nil)`.
2. Pass `onRetryDegraded` as the banner's `onRetry` closure.
3. Pass `onDismissDegraded` as the banner's `onDismiss` closure.
4. Apply `.transition(.move(edge: .top).combined(with: .opacity))` with `.spring(response: 0.3)` per the animation table in Section 5.3.

**Backward compatibility**: Both closures default to `nil`. Existing callers that pass no closures get the current behavior (banner without retry/dismiss buttons). New callers opt in to recovery affordances.

**Critical behavior during retry**: When `onRetryDegraded` is invoked, show a subtle inline `ProgressView` overlay at 0.3 opacity over the content area. Content MUST remain visible. Do NOT transition to `.loading` state.

**Empty-loaded note**: `AsyncContentView`'s `.loaded` state does not distinguish empty from populated. The ViewModel is responsible for showing `EmptyStateView` within the content closure when data is empty. No `.loaded(isEmpty:)` variant is needed.

### 5.10 ErrorStateView Secondary Action Interface

Non-retryable errors (e.g., `apiKeyInvalid`, `permissionDenied`) require a secondary action that directs users to the resolution path without coupling `ErrorStateView` to navigation.

**Component interface**:

```swift
struct ErrorStateView: View {
    let error: UserFacingError
    let onRetry: (() async -> Void)?
    let secondaryAction: SecondaryAction?   // NEW

    struct SecondaryAction {
        let title: String
        let systemImage: String?
        let action: () -> Void
    }
}
```

**Visual specification**:
- Button style: `.plain` with `.subheadline` font and `.accentColor` foreground
- Position: Below the primary "Try Again" button with 12pt spacing
- When both primary and secondary are present, they stack vertically within `ContentUnavailableView`'s `actions` closure
- When only secondary is present (non-retryable error), it becomes the sole action button
- Icon: Optional SF Symbol rendered inline via `Label(title, systemImage:)` when provided

**Caller wiring example**:

```swift
ErrorStateView(
    error: userFacingError,
    onRetry: nil,
    secondaryAction: .init(
        title: "Go to Settings",
        systemImage: "gear",
        action: { appCoordinator.navigate(to: .settings) }
    )
)
```

`ErrorStateView` remains navigation-agnostic. The caller wires the action closure to `AppCoordinator` or equivalent navigation mechanism.

### 5.11 Pull-to-Refresh Recovery Path

Every scrollable async screen MUST support `.refreshable{}` as a persistent, universally discoverable recovery path. This ensures users who dismiss an error banner still have a way to trigger refresh.

**Screens requiring `.refreshable{}`**:

| Screen | Refresh Handler | Phase |
|--------|----------------|-------|
| `DashboardView` | Calls `viewModel.retry()` on all dashboard section ViewModels | 4.15 |
| `GoalsListView` | Calls `viewModel.retry()` which refreshes all goal rows | 4.15 |
| `GoalDetailView` | Calls `viewModel.retry()` to refresh allocations and exchange rates | 4.15 |
| `MonthlyPlanningView` | Calls `viewModel.retry()` to refresh planning data | 4.15 |

**Interaction with error state**: Pull-to-refresh triggers the same `retry()` method as the error banner's "Retry" button. If the screen is in `.degraded` state, a successful refresh transitions to `.loaded` and dismisses the degraded banner per Section 5.3 animation rules. No additional auto-dismiss logic needed -- the state machine handles it.

### 5.12 Post-Onboarding Failure Empty State

When a user completes onboarding but the template goal creation failed (ERR-10), they arrive at an empty Dashboard with no context about what happened. This creates a confusing "just did setup but app is empty" experience.

**Trigger condition**: `OnboardingManager.hasCompletedOnboarding == true` AND `goals.isEmpty` AND the onboarding session recorded a goal creation failure (stored as a transient flag in `OnboardingManager`).

**Wireframe**:

```
+---------------------------------------------------+
|                                                    |
|              [!] Setup Incomplete                  |
|                                                    |
|   Your savings goal from setup couldn't be         |
|   created (check your connection).                 |
|                                                    |
|        [  Try Again  ]    [Create Goal Manually]   |
|                                                    |
+---------------------------------------------------+
```

**Component**: Context-aware variant of `DashboardView`'s empty state. Uses existing `EmptyStateView` factory pattern with a new `.onboardingFailure` case.

**Actions**:
- "Try Again": Retries the original `createGoalFromTemplate()` call with the saved template parameters.
- "Create Goal Manually": Navigates to `AddGoalView` via `AppCoordinator`.

**Clearing**: Once a goal is successfully created (by either path), the transient flag clears and the Dashboard renders normally.

**Deliverable**: Phase 4.11 sub-deliverable alongside onboarding error handling.

### 5.13 Banner Positioning and Scroll Interaction Rules

Error banners must behave consistently across all 15+ screens adopting `AsyncContentView`:

| Screen Type | Banner Position | Scroll Behavior |
|-------------|----------------|-----------------|
| List/Dashboard screens | Section header within `ScrollView`/`List` | Scrolls with content; visible at scroll top |
| Form screens (AddGoal, AddTransaction, EditGoal) | Above the form `ScrollView` (outside it) | Stays visible with keyboard; does not scroll away |
| Detail screens (GoalDetail, AssetDetail) | Top of content within `ScrollView` | Scrolls with content |

**Keyboard interaction**: On form screens, the error banner is positioned outside the scroll view (between navigation bar and form). When the keyboard appears, the banner remains visible. The form content scrolls independently.

**Pull-to-refresh success**: Automatically transitions `viewState` from `degraded -> loading -> loaded`, dismissing the banner via the state machine. No additional auto-dismiss logic needed.

**AsyncContentView degraded banner**: Inherently rendered above content (current implementation). This is correct for all screen types.

### 5.14 FreshnessIndicatorView Extension and Visual Escalation

#### Extended Integration

After banner dismissal, users see cached/stale content with no remaining indicator. Extend `FreshnessIndicatorView` to persist as a T3 signal on key screens:

| Screen | Position | Shows When | Phase |
|--------|----------|-----------|-------|
| `DashboardView` | Navigation bar subtitle or section header | `viewState == .degraded` OR data age > stale threshold | 4.1 |
| `GoalDetailView` | Below progress ring | `viewState == .degraded` OR exchange rate age > stale threshold | 4.2 |
| `GoalsListView` | List header | `viewState == .degraded` OR exchange rate age > stale threshold | 4.12 |
| `AssetDetailView` | Below balance display | Balance age > stale threshold | 4.4 |

**Persistence rule**: `FreshnessIndicatorView` remains visible even after error banner dismissal, providing continuous freshness awareness. It disappears when data is refreshed below the stale threshold.

#### Visual Escalation

Two visual states based on `FreshnessPolicy` thresholds:

| State | Condition | Appearance |
|-------|-----------|------------|
| **Normal stale** | Past stale threshold, below warning threshold | `.caption2`, `.tertiary` foreground, `clock` SF Symbol icon |
| **Warning stale** | Past warning threshold | `.caption2`, `AccessibleColors.warning` foreground, `exclamationmark.triangle` SF Symbol icon |

**Relationship to T2 banner**: The T2 `ErrorBannerView` appears independently (from ViewModel `viewState`) when a refresh attempt fails. `FreshnessIndicatorView` shows the timestamp regardless of banner state. Both can be visible simultaneously: banner for actionable error, indicator for informational timestamp.

### 5.15 Help System Navigation Specification (TODO-02)

`ChartErrorView` has a "Learn More" button that currently prints to console (TODO-02). This section specifies the navigation target.

**Approach**: Contextual help sheet with offline support.

**Component**: `ChartHelpSheetView` -- a simple sheet presenting:
1. **Header**: "Why am I seeing this?" in `.headline`
2. **Cause explanation**: From `ChartError.recoverySuggestion` or hardcoded per-error-type content
3. **Steps to resolve**: Bulleted list specific to the error type
4. **Fallback action**: "Contact Support" link (opens `mailto:` URL)

**Help content by anchor**:

| `helpAnchor` value | Sheet Title | Content Summary |
|--------------------|-------------|-----------------|
| `data-requirements` | Not Enough Data | "This chart needs at least [min] data points. Add more transactions or wait for more price history." |
| `network-troubleshooting` | Connection Issues | "Check Wi-Fi/cellular. The app will retry automatically when connected." |
| `currency-conversion` | Conversion Unavailable | "Exchange rates are temporarily unavailable. Your data is safe. Rates update automatically." |
| `date-range` | Invalid Date Range | "The selected dates don't contain enough data. Try expanding the range." |
| `calculation` | Calculation Error | "A calculation couldn't complete. Try refreshing. If persistent, contact support." |

**Fallback if help system is out of scope**: Replace the "Learn More" button with a `.disclosureGroup` that expands inline to show the `recoverySuggestion` text. No navigation required, works offline, resolves TODO-02 meaningfully.

**Decision**: Use inline `.disclosureGroup` for Phase 4 (simpler, offline-capable). Full help sheet is tracked as follow-up. This resolves TODO-02 without creating a new navigation pattern.

**Phase 4, Step 4.8 deliverable**.

### 5.16 ErrorBannerView Token Migration

Before deploying `ErrorBannerView` across 15+ screens, migrate from raw `Color` values to `AccessibleColors` tokens:

| Current (raw) | Target (token) | Location |
|---------------|---------------|----------|
| `.orange` (icon color for network) | `AccessibleColors.warning` | Line 85 |
| `.red` (icon color for apiKey/dataCorruption) | `AccessibleColors.error` | Line 87 |
| `.orange.opacity(0.1)` (background for network) | `AccessibleColors.warningBackground` | Line 93 |
| `.red.opacity(0.1)` (background for apiKey/dataCorruption) | `AccessibleColors.errorBackground` (new token if needed) | Line 95 |

**Add `errorBackground` token** to `AccessibleColors` if it does not exist (`.red.opacity(0.1)` equivalent with dark mode adaptation).

**Phase 1 deliverable** (Step 1.10). Small change (4 color value swaps + 1 potential token addition) that prevents token drift across all 15+ deployment sites.

### 5.17 Fallback Currency List Reduced-Scope Indicator

When the fallback currency list (50 coins) is shown instead of the full CoinGecko catalog (13,000+), users may think the app doesn't support their altcoin and abandon goal creation.

**Banner specification**: When displaying the fallback list, show a `FreshnessIndicatorView`-style banner at the top of the currency picker:

```
+---------------------------------------------------+
| [i] Showing popular cryptocurrencies.             |
|     Connect to the internet for the full list.    |
+---------------------------------------------------+
```

- Style: `.caption` text, `AccessibleColors.warning` foreground, `info.circle` icon
- Position: Pinned above the search field in `SearchableCurrencyPicker`
- Dismissible: No (informational, persists while using fallback list)
- VoiceOver: `.accessibilityLabel("Showing popular cryptocurrencies. Connect to the internet for the full list.")`

**Phase 4, Step 4.3 sub-deliverable**.

### 5.18 Onboarding Error UX Specification

Onboarding is the user's first experience. Error handling must be especially careful:

**Error banner position**: Between step content and navigation buttons (above Next/Back). This keeps the error visible without obscuring step content.

**Next button behavior**: Next button remains enabled when goal creation fails. Tapping Next with a failed template shows confirmation dialog:
- Title: "Continue without a starter goal?"
- Message: "You can create goals anytime from the dashboard."
- Actions: "Continue" (default, non-destructive) / "Try Again" (attempts retry)

**Progress indicator**: Unaffected by error state. Progress shows steps completed, not success/failure of background operations.

**Font design preservation**: When replacing hardcoded `.system(size: N, weight: .bold, design: .rounded)` with semantic styles in Phase 5, apply `.fontDesign(.rounded)` modifier to preserve onboarding's friendly tone:

```swift
// Before:
.font(.system(size: 28, weight: .bold, design: .rounded))

// After:
.font(.title2.bold()).fontDesign(.rounded)
```

This maintains onboarding character while gaining Dynamic Type support.

**Phase 4, Steps 4.11 and 4.13; Phase 5, Step 5.7**.

### 5.19 ErrorBannerView Adaptive Layout at Accessibility Sizes

At AX5 text size, `ErrorBannerView`'s `HStack` layout will overflow horizontally. Since this component deploys to 15+ screens, its accessibility behavior must be specified:

**Adaptive layout rule**: At accessibility text sizes (detected via `@Environment(\.dynamicTypeSize)`), reflow from `HStack` to `VStack`:

| Size Category | Layout |
|--------------|--------|
| Default through XXXL | `HStack`: icon + title/message stack + spacer + retry button + dismiss button |
| AX1 through AX5 | `VStack`: icon + title + message (full width, no `.lineLimit`) + `HStack` of retry + dismiss buttons |

**Implementation**: Wrap in `ViewThatFits` or use `@Environment(\.dynamicTypeSize)` conditional. Remove `.lineLimit(2)` at accessibility sizes to show full recovery suggestion text.

**Phase 5, Step 5.18 (new step)**.

### 5.20 MonthlyExecutionView Mid-Flow Error Specification

Monthly execution is a **stateful flow** -- the user marks contributions as completed one by one across the month. Error handling must preserve partial progress:

| Scenario | Error Tier | Behavior |
|----------|-----------|----------|
| **Initial load failure** (no data) | T1 (full-screen `ErrorStateView`) | Block screen; user retries loading |
| **Initial load failure** (has cache) | T2 (inline banner) | Show cached execution state with freshness indicator |
| **Mid-flow save failure** (mark contribution) | T2 (inline banner) | Already-completed contributions preserved in local state and visually distinct. Banner: "Contribution saved locally but sync failed. [Retry Sync]" |
| **Mid-flow save failure** (undo) | T2 (inline banner) | Undo preserved locally. Banner: "Undo saved locally but sync failed. [Retry Sync]" |

**Key rules**:
1. **Partial progress preserved**: Completed contributions remain marked in local state regardless of sync failure.
2. **Visual distinction**: Unsynced contributions show a small `cloud.slash` icon badge.
3. **Retry scope**: "Retry Sync" only re-attempts the failed sync operation, not the entire load.
4. **T1 only for initial load**: Never show a full-screen error for mid-flow save failures.

**Phase 3, Step 3.1 (ViewModel); Phase 4, Step 4.5 (View)**.

---

## 6. Architecture and Implementation Plan

### Phase 0: Baseline Metrics Recording (Est. 30 min) -- MANDATORY GATE

> **Purpose**: Record pre-implementation baseline values for all post-ship monitoring signals (Section 8.5). Without recorded baselines, the success criterion ("meeting or exceeding all baseline thresholds") is unmeasurable. Phase 1 MUST NOT begin until Phase 0 is complete and baseline values are committed.
>
> **Owner**: PR author (proposal implementer).

| Step | Action | Tool/Source | Output |
|------|--------|-------------|--------|
| 0.1 | Record crash-free rate | Xcode Organizer > Crashes > "Crash Free Rate" for the current App Store build (or latest TestFlight build if not yet in App Store). If no production build exists, record "N/A (pre-release)" and use first TestFlight build rate as baseline. | Percentage value committed to Section 8.5 table |
| 0.2 | Count "missing data" / "zero balance" support tickets | Search support channel (email, GitHub Issues, or internal tracker) for tickets containing "missing data", "zero balance", "$0.00", "blank", "empty dashboard" keywords from the last 30 days. Record count and date range. | Ticket count committed to Section 8.5 table |
| 0.3 | Record CI pass rate | Run `xcodebuild test` 3 times locally (or check last 10 CI runs if CI is configured). Record pass rate as percentage. If no CI history exists, run tests locally and record result. | Pass rate committed to Section 8.5 table |
| 0.4 | Commit baseline values | Update Section 8.5 "Baseline Snapshot" table with recorded values. Create a git commit with message: `chore: record Phase 0 baseline metrics for UX audit`. This commit serves as the immutable baseline record. | Git commit SHA as proof of baseline recording |

**Gate condition**: Phase 1 may begin only after Step 0.4 commit is pushed. The baseline values serve as the reference point for post-ship success evaluation.

**If metrics are unavailable**: For any signal where data is genuinely unavailable (e.g., no App Store release yet, no support channel), record "N/A -- [reason]" with a note explaining the gap. The baseline for that signal becomes the first measurement taken after initial deployment.

### Phase 1: Foundation Completion (Est. 3-4 hours)

Complete the existing infrastructure before wiring it into screens.

| Step | Action | Files | Rationale |
|------|--------|-------|-----------|
| 1.1 | Complete `ErrorTranslator` for all 25 `AppError` cases with reassurance clauses on financial-impact messages (see Appendix D for full mapping) | `Utilities/ServiceResult.swift` | 16 unmapped cases produce generic messages; financial-impact messages need "your savings are safe" reassurance |
| 1.2 | Add `ChartError.toUserFacingError()` bridge extension for all 6 `ChartError` cases | `Models/ChartError.swift` | Unify parallel error systems |
| 1.3 | Add secondary action support to `ErrorStateView` per Section 5.10 interface spec | `Views/Components/ErrorStateView.swift` | Enables "Go to Settings" for non-retryable errors; `SecondaryAction` struct with title, systemImage?, action closure |
| 1.4 | Upgrade `AsyncContentView` degraded state with `onRetryDegraded`/`onDismissDegraded` closures, a11y labels, state transition animations, and haptic feedback per Sections 5.9, 5.3 | `Views/Components/AsyncContentView.swift` | Closes dead-end degraded state gap; renders degraded banner via `ErrorBannerView` internally |
| 1.5 | Add fallback currency list (top 50 coins by market cap, ~5KB embedded JSON, with `lastUpdated` field; refreshed once per app release cycle) | New: `Utilities/FallbackCurrencyList.swift` | Enables offline goal creation |
| 1.6 | Document error routing contract (inline DocC + standalone markdown) | New: `docs/ERROR_ROUTING_CONTRACT.md` | ErrorHandler.shared vs ErrorAwareViewModel rules per Section 5.1. Include inline code comments at each routing site. |
| 1.7 | Deprecate `CompactChartErrorView` | `Views/Components/ChartErrorView.swift` | Mark `@available(*, deprecated)` per Section 5.6 |
| 1.8 | Unit tests for expanded `ErrorTranslator` (25 cases) and `ChartError` bridge (6 cases), including reassurance clause verification. Write tests first (TDD) | New: `Tests/ErrorTranslatorTests.swift` | Verify all 31 error-to-message mappings |
| 1.9 | Add `FreshnessPolicy` injectable struct with static factory defaults, registered in `DIContainer` | `Utilities/FreshnessPolicy.swift` (new), `DIContainer` (modify) | Configurable freshness thresholds per Section 5.2.1 |
| 1.10 | Migrate `ErrorBannerView` colors from raw `.orange`/`.red` to `AccessibleColors` tokens per Section 5.16; add `errorBackground` token if needed | `Views/Components/ErrorBannerView.swift`, `Utilities/AccessibleColors.swift` | Design token compliance before mass deployment |
| 1.11 | Component validation tests: render `AsyncContentView`, `ErrorBannerView`, `ErrorStateView`, `FreshnessIndicatorView` in all `ViewState` cases to verify correct rendering before Phase 4 mass adoption | New: `Tests/ErrorComponentTests.swift` | Catch component bugs before deploying to 15+ screens |

**ErrorTranslator grouping for the 16 unmapped cases**:

| Group | Cases | User-Facing Title | Distinct Message? |
|-------|-------|-------------------|:-:|
| Connection detail | `invalidURL`, `invalidResponse`, `decodingFailed` | "Connection Error" | Shared title, distinct recovery suggestions |
| Not found (API) | `coinNotFound`, `chainNotSupported`, `addressInvalid` | Per-case titles | Yes (include the coin/chain/address from associated value) |
| Not found (data) | `goalNotFound`, `assetNotFound`, `transactionNotFound` | "Item Not Found" | Yes (specify which item type) |
| Delete failure | `deleteFailed` | "Delete Failed" | Yes |
| Input validation | `invalidAmount`, `invalidDate` | "Invalid Input" | Yes (specify amount vs date) |
| Platform feature | `featureUnavailable`, `permissionDenied` | Per-case titles | Yes (include feature/permission from associated value) |
| Platform background | `widgetUpdateFailed`, `notificationsFailed` | "Background Update Failed" | Shared (non-critical; these use ErrorHandler.shared per routing contract) |

### Phase 2: Service Layer Retrofit (Est. 3-4 hours)

**Migration strategy**: Additive methods alongside existing `async throws` protocol methods. This ensures zero breaking changes to callers, mocks, or test doubles.

```swift
// Example pattern: ExchangeRateServiceProtocol
protocol ExchangeRateServiceProtocol {
    // Existing (preserved, unchanged)
    func fetchRate(from: String, to: String) async throws -> Double

    // New (added alongside)
    func fetchRateResult(from: String, to: String) async -> ServiceResult<Double>

    // New: service-level error broadcasting for deduplication (Section 5.4.1)
    var serviceError: AnyPublisher<AppError?, Never> { get }
}

// Default implementation wraps existing method for backward compatibility
extension ExchangeRateServiceProtocol {
    func fetchRateResult(from: String, to: String) async -> ServiceResult<Double> {
        do {
            let rate = try await fetchRate(from: from, to: to)
            return .fresh(rate)
        } catch let error as AppError {
            return .failure(error)
        } catch {
            return .failure(.networkUnavailable)
        }
    }
}
```

**Why additive, not replacement**: The additive strategy provides:
- **Zero breaking changes**: Existing callers continue to compile unchanged.
- **Incremental adoption**: ViewModels migrate to `*Result` methods one at a time.
- **Rollback safety**: If a `ServiceResult`-based method causes regressions, revert the ViewModel caller to the throws-based method without touching the service layer.

**Test double guidance**: Mock/test double implementations SHOULD override `*Result` methods directly rather than relying on the default extension wrapper, to ensure the `ServiceResult` code path is explicitly exercised in tests.

| Step | Action | Files | Impact |
|------|--------|-------|--------|
| 2.1 | Add `fetchRateResult` to `ExchangeRateService` with cache-aware return + `serviceError` publisher | `Services/ExchangeRateService.swift`, `Services/Protocols/ServiceProtocols.swift` | Returns `.cached(rate, age:)` when using cache; publishes errors for deduplication |
| 2.2 | Add `fetchCurrencyListResult` to `CoinGeckoService` with fallback list integration (returns `.fallback(embeddedList, reason: .networkUnavailable)` when offline) | `Services/CoinGeckoService.swift`, `Services/Protocols/ServiceProtocols.swift` | Transparent fallback -- CurrencyViewModel gets a list regardless of network |
| 2.3 | Add result-returning methods to `GoalCalculationService` | `Services/GoalCalculationService.swift` | Propagates rate errors instead of silent fallback |
| 2.4 | Add `fetchBalanceResult` to `BalanceService` with cache metadata + `serviceError` publisher | `Services/BalanceService.swift`, `Services/Protocols/ServiceProtocols.swift` | Shows balance freshness; publishes errors for deduplication |
| 2.5 | Unit tests for all new `*Result` methods | New/modified test files | Verify ServiceResult for success, cache, fallback, failure paths |

### Phase 3: ViewModel Layer Retrofit (Est. 3-4 hours)

Bring all 9 ViewModels to `ErrorAwareViewModel` conformance. Audit and remove all `ErrorHandler.shared.handle()` calls from conforming ViewModels.

| Step | Action | Files | Current State |
|------|--------|-------|--------------|
| 3.1 | `MonthlyExecutionViewModel` -> `ErrorAwareViewModel` with mid-flow error handling per Section 5.20 | `ViewModels/MonthlyExecutionViewModel.swift` | Has raw `error: Error?`, no viewState/retry. Must handle mid-flow save failures as T2, preserving partial progress |
| 3.2 | `MonthlyPlanningViewModel` -> `ErrorAwareViewModel` | `ViewModels/MonthlyPlanningViewModel.swift` | Has raw `error: Error?`, no viewState/retry |
| 3.3 | `GoalEditViewModel` -> `ErrorAwareViewModel` (async save path ONLY; form validation remains via existing `validationErrors` properties) | `ViewModels/GoalEditViewModel.swift` | Throws to caller, no error state. Note: `retry()` maps to "retry save", not "retry validation". Dual-error-surface documented. |
| 3.4 | `GoalDashboardViewModel` -> `ErrorAwareViewModel` | `ViewModels/GoalDashboardViewModel.swift` | Delegates to DashboardVM, no own state |
| 3.5 | `CurrencyViewModel` -> `ErrorAwareViewModel` | `ViewModels/CurrencyViewModel.swift` | No error handling at all |
| 3.6 | Fix `GoalViewModel.calculateCurrentTotal()` to surface errors instead of silent `continue` | `ViewModels/GoalViewModel.swift` | Lines 93-100: catches error, logs, continues. Fix: accumulate errors, set viewState to `.degraded` if some allocations failed, `.error` if all failed |
| 3.7 | Fix `DashboardViewModel` to surface per-section errors via `DashboardErrorAggregator` coordinator | `ViewModels/DashboardViewModel.swift`, new `ViewModels/DashboardErrorAggregator.swift` | Silently swallows chart/section errors. New aggregator observes per-section errors, produces `[UserFacingError]` for CoalescedErrorBannerView |
| 3.8 | Fix `GoalRowViewModel` to observe service-layer error broadcasts (Section 5.4.1) | `ViewModels/GoalRowViewModel.swift` | Flag exists but never set true. Subscribes to `ExchangeRateService.serviceError`; self-transitions to `.degraded` on service error |
| 3.9 | Audit and remove `ErrorHandler.shared.handle()` calls from all 9 conforming ViewModels | All ViewModel files | Replace with `setError()` per routing contract |
| 3.10 | Add service-layer error broadcasting to `ExchangeRateService`, `BalanceService`, `CoinGeckoService` per Section 5.4.1 | Service files | Enable automatic error deduplication via publisher |
| 3.11 | ViewModel unit tests for all error state transitions | New test files | Verify: error paths reach viewState, retry resets state, degraded shows cached data, mid-flow saves preserve progress |

### Phase 3.5: Validation Spike (Est. 1-2 hours)

**Purpose**: User-testable checkpoint before committing to full view-layer integration. Wire `AsyncContentView` into exactly 2 P0 screens to validate the error contract end-to-end.

| Step | Action | Files | Validation Target |
|------|--------|-------|-------------------|
| 3.5.1 | Wire `AsyncContentView` into `DashboardView` with `CoalescedErrorBannerView` (or stacked `ErrorBannerView` MVP fallback) + `FreshnessIndicatorView` | `Views/DashboardView.swift` | Validates: ErrorAwareViewModel contract, error tier matrix for Dashboard, multi-error coalescing UX, freshness indicator |
| 3.5.2 | Wire `AsyncContentView` into `GoalDetailView` with `ErrorBannerView` for exchange rate errors + `FreshnessIndicatorView` | `Views/GoalDetailView.swift` | Validates: degraded state with cached data, retry flow, "Your savings are safe" reassurance copy, freshness indicator |
| 3.5.3 | Demo to product stakeholder | N/A | Sign-off on: (a) error tier selections correct, (b) degraded state UX acceptable, (c) reassurance messaging appropriate, (d) freshness indicators useful |

**Gate**: Phase 4 proceeds only after stakeholder sign-off on Phase 3.5 demo. If significant UX issues surface, iterate on Sections 5.2/5.9 before proceeding.

**Merge note**: Phase 3.5 changes ship in PR 3 (ViewModels) since they are minimal view wiring that validates the ViewModel contract. Phase 4 then expands to remaining screens.

### Phase 4: View Layer Integration (Est. 6-7 hours)

Wire error/loading/empty components into screens. Includes onboarding flow.

| Step | Action | Files | Fixes |
|------|--------|-------|-------|
| 4.1 | Wrap `DashboardView` in `AsyncContentView` with `CoalescedErrorBannerView` + `FreshnessIndicatorView` (extending Phase 3.5) | `Views/DashboardView.swift` | ERR-04, ERR-11 |
| 4.2 | Add `ErrorBannerView` + `FreshnessIndicatorView` to `GoalDetailView` for exchange rate errors | `Views/GoalDetailView.swift` | ERR-01, ERR-03 |
| 4.3 | Add currency list error handling to `AddGoalView` (T2 with fallback list + reduced-scope banner per Section 5.17) | `Views/AddGoalView.swift` | ERR-02 |
| 4.4 | Add `FreshnessIndicatorView` to `AssetDetailView` | `Views/AssetDetailView.swift` | Balance freshness |
| 4.5 | Add error + loading states to `MonthlyExecutionView` via `AsyncContentView` with mid-flow spec per Section 5.20 | `Views/Planning/MonthlyExecutionView.swift` | ERR-05 |
| 4.6 | Wire `CurrencyViewModel` error state into goal forms | `Views/AddGoalView.swift`, `Views/EditGoalView.swift` | ERR-06 |
| 4.7 | Implement error state display in `AddTransactionView` (banner positioned above form, outside scroll view per Section 5.13) | `Views/AddTransactionView.swift` | TODO-01 |
| 4.8 | Implement help navigation in `ChartErrorView` as inline `.disclosureGroup` per Section 5.15 | `Views/Components/ChartErrorView.swift` | TODO-02 |
| 4.9 | Replace `CompactChartErrorView` usages with `ErrorBannerView` | Chart view files using CompactChartErrorView | VIS-04 |
| 4.10 | Refactor `ExchangeRateWarningView` to use `ErrorBannerView` internally | `Views/Components/ExchangeRateWarningView.swift` | VIS-02 |
| 4.11 | Add error handling + retry UI to `OnboardingFlowView.createGoalFromTemplate()` per Section 5.18 + context-aware post-onboarding-failure empty state on DashboardView per Section 5.12 | `Views/Onboarding/OnboardingFlowView.swift`, `Views/DashboardView.swift` | ERR-10, post-onboarding empty state |
| 4.12 | Add error deduplication banner + `FreshnessIndicatorView` to `GoalsListView` header (observing service-layer error broadcasts per Section 5.4.1) | `Views/GoalsListView.swift` | ERR-09, dedup |
| 4.13 | Add error banner to onboarding for network-dependent steps per Section 5.18 (banner between content and nav buttons) | `Views/Onboarding/OnboardingFlowView.swift` | Onboarding offline scenario |
| 4.14 | Create `CoalescedErrorBannerView` component per Section 5.5 visual spec + VoiceOver spec; wire into `DashboardView` via `DashboardErrorAggregator` | New: `Views/Components/CoalescedErrorBannerView.swift`, `Views/DashboardView.swift` | Dashboard multi-error coalescing |
| 4.15 | Add `.refreshable{}` pull-to-refresh to DashboardView, GoalsListView, GoalDetailView, MonthlyPlanningView per Section 5.11 | `Views/DashboardView.swift`, `Views/GoalsListView.swift`, `Views/GoalDetailView.swift`, `Views/Planning/MonthlyPlanningView.swift` | Universal recovery path after banner dismissal |

### Phase 5: Accessibility Remediation (Est. 5-7 hours)

> **Scope**: Verified 77 hardcoded `.system(size:)` instances across 22 files (68 literal + 9 proportional). Estimate includes non-onboarding font clusters.
>
> **File overlap with Phase 4**: `DashboardView.swift`, `GoalDetailView.swift`, `GoalsListView.swift`, and `OnboardingFlowView.swift` are modified in both Phase 4 and Phase 5. Accessibility changes to these files (Phase 5a) run AFTER Phase 4 commits.
>
> **OnboardingFlowView sequencing**: OnboardingFlowView font size changes are Phase 5a (sequential after Phase 4). Phase 4 insertions/deletions in OnboardingFlowView will shift line targets despite the ~60-line gap between change regions. Sequential execution avoids merge conflicts.
>
> **Visual regression verification**: After Phase 5 implementation, Phase 7 includes side-by-side visual comparison at DEFAULT text size for onboarding, dashboard empty states, and hero icons (Section 5.7 mapping reduces some rendered sizes). Use `.dynamicTypeSize` range caps where needed to preserve visual hierarchy.

| Step | Action | Files | Fixes | Phase 5a/5b |
|------|--------|-------|-------|:-:|
| 5.1 | Add accessibility label to DashboardView widget remove button | `Views/DashboardView.swift` | A11Y-03 | 5a |
| 5.2 | Replace hardcoded `.system(size: N)` with semantic font styles in DashboardView (1 instance) | `Views/DashboardView.swift` | A11Y-04, A11Y-08 | 5a |
| 5.3 | Replace hardcoded `.system(size: N)` in PlanningView (2 instances) | `Views/Planning/PlanningView.swift` | A11Y-05 | 5b |
| 5.4 | Replace fixed-height progress ring with `@ScaledMetric`-based adaptive sizing: `@ScaledMetric(relativeTo: .body) private var ringHeight: CGFloat = 180` constrained to `min(120, max(ringHeight, 280))` | `Views/GoalDetailView.swift` | A11Y-07, A11Y-10 | 5a |
| 5.5 | Replace fixed chart bar dimensions with `@ScaledMetric`: `barWidth: 40pt` (min 24, max 64), container: `.frame(minHeight: 120, idealHeight: 200, maxHeight: 360)` | `Charts/SimpleStackedBarView.swift` | A11Y-09 | 5b |
| 5.6 | Add accessibility identifiers to goal navigation links | `Views/GoalsListView.swift` | A11Y-11 | 5a |
| 5.7 | Replace all 45 hardcoded `.system(size: N)` in onboarding with semantic styles; preserve `.fontDesign(.rounded)` per Section 5.18 | `Views/Onboarding/OnboardingFlowView.swift`, `Views/Onboarding/OnboardingStepViews.swift` | A11Y-12 | **5a** |
| 5.8 | Add VoiceOver data point labels to EnhancedLineChartView interactive selections | `Charts/EnhancedLineChartView.swift` | A11Y-13 | 5b |
| 5.9 | Add VoiceOver data point labels to LineChartView | `Charts/LineChartView.swift` | A11Y-14 | 5b |
| 5.10 | Add accessibility elements to CompactProgressRingView + replace 6 proportional `.system(size: size * N)` with `@ScaledMetric`-based sizing in ProgressRingView | `Charts/ProgressRingView.swift` | A11Y-15, A11Y-19 | 5b |
| 5.11 | Add accessibility label to EmptyGoalsView button + replace hardcoded font in EmptyGoalsView (1 instance) | `Views/EmptyGoalsView.swift` | A11Y-16, A11Y-18 | 5b |
| 5.12 | Accessibility snapshot tests at Default and AX5 for P0 flows using XCTest-native UI test screenshots with image attachment comparison (zero external dependencies). Block on P0 flows (Dashboard, GoalDetail, MonthlyPlanning); warn-only on secondary flows initially. Baseline images tracked in git. | New test files | Regression prevention | 5a |
| 5.13 | Replace hardcoded `.system(size: N)` in dashboard components (4 instances) | `Views/Dashboard/EnhancedDashboardComponents.swift`, `Views/Dashboard/DashboardComponents.swift` | A11Y-17 | 5a |
| 5.14 | Replace hardcoded `.system(size: N)` in empty state components (4 instances) | `Views/Components/EmptyStateView.swift`, `Views/Components/EmptyDetailView.swift` | A11Y-18 | 5b |
| 5.15 | Replace proportional `.system(size: size * N)` with `@ScaledMetric` in SparklineChartView (1) and StackedBarChartView (2) | `Charts/SparklineChartView.swift`, `Charts/StackedBarChartView.swift` | A11Y-19 | 5b |
| 5.16 | Replace hardcoded `.system(size: N)` in miscellaneous components (6 instances) including ChartErrorView 48pt icon -> `@ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 48` | `Views/Components/HeroProgressView.swift`, `Views/Components/FlexAdjustmentSlider.swift`, `Views/Components/GoalSwitcherBar.swift`, `Views/Components/MonthlyPlanningWidget.swift`, `Views/Components/ChartErrorView.swift` | A11Y-20, UI-07 | 5b |
| 5.17 | Replace hardcoded `.system(size: N)` in remaining views (4 instances) | `Views/AssetDetailView.swift`, `Views/Goals/GoalComparisonView.swift`, `Views/TransactionHistoryView.swift`, `Views/Planning/GoalRequirementRow.swift` | A11Y-21 | 5b |
| 5.18 | Add adaptive layout to `ErrorBannerView` at accessibility sizes per Section 5.19: reflow HStack to VStack, remove `.lineLimit(2)` | `Views/Components/ErrorBannerView.swift` | UI-11 | 5b |

### Phase 6: Navigation Edge Cases (Est. 1-2 hours)

| Step | Action | Files | Fixes |
|------|--------|-------|-------|
| 6.1 | Verify dirty-dismiss for all MOD-02 flows (budget, goal, contribution) | Planning views, goal edit views | NAV-01 |
| 6.2 | Validate MonthlyExecutionView error recovery path with new AsyncContentView and mid-flow spec | `Views/Planning/MonthlyExecutionView.swift` | NAV-03 |
| 6.3 | Test iPad MOD-01 popover fallback | Components presenting MOD-01 sheets | NAV-02 |

### Phase 7: Verification (Est. 2-3 hours)

| Step | Action |
|------|--------|
| 7.1 | Full build (iOS + macOS) passes with zero warnings |
| 7.2 | All existing unit tests pass |
| 7.3 | All existing UI tests pass |
| 7.4 | New error-state unit tests pass (ErrorTranslator 31 cases, ViewModel error paths, component render tests) |
| 7.5 | New accessibility snapshot tests pass |
| 7.6 | Manual VoiceOver walkthrough per Section 8.3 checklist |
| 7.7 | Manual network-off testing per Appendix C verification matrix |
| 7.8 | Human tester sign-off on all 15 verification scenarios (Section 8.2) |
| 7.9 | Visual regression check: side-by-side comparison at DEFAULT text size for onboarding screens, DashboardView empty states, and PlanningView hero icons. Approve visual hierarchy or apply `.dynamicTypeSize` range caps where needed |
| 7.10 | Grep verification: `CompactChartErrorView` active usages == 0 |

---

## 7. Rollout Strategy

### 7.1 Phased Execution

```
Phase 0 (Baseline) --> Phase 1 (Foundation) --> Phase 2 (Services) --> Phase 3 (ViewModels)
   [GATE]                                                                   |
                                                                    Phase 3.5 (Spike)
                                                                            |
                                                          +-----------------+
                                                          v
                                                    Phase 4 (Views) --> Phase 5a*
                                                          |                  |
Phase 5b (A11Y: PlanningView, Charts, EmptyState,   -----+                  |
          Components, remaining views)                                       |
Phase 6 (Navigation) --------------------------------------------------------|
                                                                             |
                                                                  Phase 7 (Verification)
```

> **GATE**: Phase 0 completion (baseline values committed) is a hard prerequisite for Phase 1 start.

*Phase 5a = accessibility changes to files also modified in Phase 4 (DashboardView, GoalDetailView, GoalsListView, **OnboardingFlowView**, OnboardingStepViews, dashboard components). These run sequentially after Phase 4 commits.
*Phase 5b = accessibility changes to files NOT modified in Phase 4 (PlanningView, charts, empty state components, miscellaneous components, remaining views, ErrorBannerView adaptive layout). These run in parallel with Phase 4.

### 7.2 MVP Cut-Line

If total effort exceeds the 32-hour budget, the following scope-reduction fallback applies:

**MVP (Minimum Shippable Increment)** - resolves all P0 silent-failure defects:

| Scope | Phases | Content |
|-------|--------|---------|
| **IN** | Phase 0 | Baseline Metrics Recording: crash-free rate, support tickets, CI pass rate committed to Section 8.5 |
| **IN** | Phase 1 | Foundation: ErrorTranslator completion (25 cases with reassurance copy), ChartError bridge, ErrorStateView secondary action, AsyncContentView degraded upgrade, fallback currency list, error routing contract, CompactChartErrorView deprecation, FreshnessPolicy, ErrorBannerView token migration, component validation tests, unit tests |
| **IN** | Phase 2 | Services: All additive `*Result` methods + service-layer error broadcasting |
| **IN** | Phase 3 + 3.5 | ViewModels: All 9 ErrorAwareViewModel conformances, error routing audit, DashboardErrorAggregator, service-layer dedup, validation spike |
| **IN** | Phase 4: 4.1-4.7 | Views: DashboardView, GoalDetailView, AddGoalView, AssetDetailView, MonthlyExecutionView, goal forms, AddTransactionView (ERR-01 through ERR-06, TODO-01) |
| **OUT** | Phase 4: 4.8-4.15 | Views: ChartErrorView help nav, CompactChartErrorView replacement, ExchangeRateWarningView refactor, onboarding error handling, GoalsList dedup, CoalescedErrorBannerView, pull-to-refresh |
| **OUT** | Phase 5 | Accessibility: All font size fixes, VoiceOver, snapshot tests, ErrorBannerView adaptive layout |
| **OUT** | Phase 6 | Navigation: Edge cases |

**OUT items ship in the next sprint as a P1 follow-up PR.**

**Decision trigger**: If Phase 3.5 demo occurs at cumulative hour 14+ (of 32 budget), activate the MVP cut-line. Ship Phases 1-3.5 + Phase 4 (4.1-4.7) as the MVP PR. Remaining phases become separate follow-up PRs.

### 7.3 Estimated Total Effort

| Phase | Estimate | Cumulative |
|-------|----------|-----------|
| Phase 0: Baseline Metrics Recording | 0.5 hours | 0.5 hours |
| Phase 1: Foundation | 3-4 hours | 3.5-4.5 hours |
| Phase 2: Services | 3-4 hours | 6.5-8.5 hours |
| Phase 3: ViewModels | 3-4 hours | 9.5-12.5 hours |
| Phase 3.5: Validation Spike | 1-2 hours | 10.5-14.5 hours |
| Phase 4: Views (incl. onboarding, CoalescedErrorBannerView, pull-to-refresh, FreshnessIndicatorView extension) | 6-7 hours | 16.5-21.5 hours |
| Phase 5: Accessibility (77 font fixes, charts, VoiceOver, snapshots, ErrorBannerView adaptive) | 5-7 hours | 21.5-28.5 hours |
| Phase 6: Navigation | 1-2 hours | 22.5-30.5 hours |
| Phase 7: Verification (incl. visual regression check) | 2-3 hours | 24.5-33.5 hours |
| **Total** | **24.5-33.5 hours** | |

### 7.4 Incremental Merge Strategy

Each phase is merged as an independent PR. Each PR leaves the app in a compilable, test-passing state:

0. **PR 0**: Phase 0 (Baseline) - Records baseline metrics in Section 8.5 table. Documentation-only commit. Gates all subsequent work.
1. **PR 1**: Phase 1 (Foundation) - Pure additions, deprecation markers, token migration, component tests. No behavior change.
2. **PR 2**: Phase 2 (Services) - New additive methods alongside existing ones + service-layer error publishers. Zero breaking changes to callers.
3. **PR 3**: Phase 3 + 3.5 (ViewModels + Spike) - Protocol conformance, error routing audit, DashboardErrorAggregator, validation spike on 2 screens.
4. **PR 4**: Phase 4 (Views) - User-visible error/loading states, onboarding error handling, CoalescedErrorBannerView, pull-to-refresh, FreshnessIndicatorView extension.
5. **PR 5**: Phase 5 (Accessibility) - All 77 font size fixes, label additions, chart VoiceOver, snapshot tests, ErrorBannerView adaptive layout.
6. **PR 6**: Phase 6+7 (Navigation + Verification) - Edge cases and final validation.

**Rollback plan per phase**:

| Phase | Rollback Impact |
|-------|----------------|
| Phase 0 | Revert commit. Baseline values removed. Re-record before proceeding. |
| Phase 1 | Revert PR. No downstream impact (foundation additions only). |
| Phase 2 | Revert PR. ViewModels fall back to existing `async throws` methods automatically (new methods are additive). |
| Phase 3 + 3.5 | Revert PR. Views revert to pre-ErrorAwareViewModel behavior. Services unaffected. Validation spike screens revert. |
| Phase 4 | Revert PR. Views revert to prior state. ViewModels still have conformance but views don't consume it. |
| Phase 5 | Revert PR. Layout returns to hardcoded sizes. No functional impact. |
| Phase 6 | Revert PR. Navigation edge cases remain unverified but no regression. |

---

## 8. Success Metrics

### 8.1 Quantitative (Code Artifacts)

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| ViewModels conforming to ErrorAwareViewModel | 4/9 (44%) | 9/9 (100%) | Protocol conformance check |
| AppError cases mapped in ErrorTranslator | 9/25 (36%) | 25/25 (100%) | Unit test: `ErrorTranslatorTests` |
| ChartError cases bridged to UserFacingError | 0/6 (0%) | 6/6 (100%) | Unit test: `ErrorTranslatorTests` |
| Async screens with tri-state (loading/content/error) | ~0/15 | 15/15 (100%) | Code audit of AsyncContentView usage |
| Hardcoded `.system(size:)` font usages | 77 (68 literal + 9 proportional, across 22 files) | 0 | `grep -r "\.system(size:" Views/ Charts/` |
| In-code TODOs resolved | 0/2 | 2/2 | Source search for TODO-01, TODO-02 |
| Chart types with VoiceOver data point labels | 1/4 | 4/4 | Accessibility audit |
| ErrorHandler.shared calls from conforming VMs | Unknown (audit in Phase 3) | 0 | Code audit |
| CompactChartErrorView active usages | Active | 0 (deprecated) | grep for CompactChartErrorView |
| ErrorBannerView using AccessibleColors tokens | 0% | 100% | Code review |
| Services with error broadcasting publisher | 0/3 | 3/3 | Protocol conformance |

### 8.2 Qualitative (User Outcomes) - Manual Test Matrix

Each scenario MUST be tested by a human tester with explicit pass/fail sign-off. **Testing owner**: PR author for each phase. **Timing**: Must complete before merge of the Phase 4 PR (not post-merge).

| # | Scenario | Steps | Pass Criteria | Sign-Off |
|---|----------|-------|---------------|:--:|
| 1 | Dashboard with no network | Disable network, open dashboard | Cached data shown with freshness indicator; coalesced error banner for refresh failures with retry; no blank sections | [ ] |
| 2 | Create goal offline | Disable network, tap Add Goal | Fallback currency list loads (50 coins) with "Showing popular cryptocurrencies" banner; goal creation succeeds; freshness indicator shown | [ ] |
| 3 | Exchange rate failure | Mock CoinGecko 500, open GoalDetail | Banner: "Price data temporarily unavailable. Your savings are safe..." Retry present. Progress is NOT $0.00. Freshness indicator visible. | [ ] |
| 4 | Chart data unavailable | Mock calculation failure, open dashboard | Chart section shows error with "Try Again"; other sections unaffected | [ ] |
| 5 | VoiceOver on planning rows | Enable VoiceOver, navigate Monthly Planning | Status read as descriptive text with icon context, not color references | [ ] |
| 6 | Dynamic Type AX5 | Set text size to AX5, navigate all screens including onboarding | No clipped buttons, no overlapping text, all controls reachable. ErrorBannerView reflows to VStack. | [ ] |
| 7 | Dirty form dismiss | Edit a goal, swipe to dismiss | Confirmation dialog: "Keep Editing" / "Discard" | [ ] |
| 8 | Complete onboarding offline | Disable network, complete onboarding flow | Error banner appears between content and nav buttons when goal template creation fails; Next button enabled with "Continue without starter goal?" confirmation; can dismiss and complete | [ ] |
| 9 | Multi-error dashboard | Mock exchange rate + balance + chart failures, open dashboard | Coalesced banner: "Exchange rates unavailable (+2 more)"; expandable; "Retry All" works; VoiceOver announces count and top error | [ ] |
| 10 | Chart VoiceOver interaction | Enable VoiceOver, navigate to EnhancedLineChartView, select data point | VoiceOver announces: value, date, context (e.g., "March 15: $1,250.45 USD") | [ ] |
| 11 | List error deduplication | Mock exchange rate failure, open Goals list with 5+ goals | Single top-level error banner with "Affecting 5 goals"; goals show "cached" indicator, not individual errors; banner observes service-layer error directly | [ ] |
| 12 | All tests pass | Run `xcodebuild test` | Zero failures | [ ] |
| 13 | Post-onboarding failure empty state | Complete onboarding with network off (goal creation fails), arrive at Dashboard | Context-aware empty state: "Your savings goal from setup couldn't be created"; "Try Again" retries template; "Create Goal Manually" navigates to AddGoalView | [ ] |
| 14 | Pull-to-refresh recovery | Open Dashboard with network off (shows degraded), dismiss error banner, pull-to-refresh | Refresh triggers retry; success transitions to loaded state and dismisses degraded banner. Success haptic feedback. | [ ] |
| 15 | Retry escalation | Open screen with network off, tap Retry 3 times in succession (all fail) | After 3rd failure, button text changes to "Try Later". Manual retry still works via pull-to-refresh. | [ ] |

#### 8.2.1 Test Environment Setup

| Requirement | Approach |
|-------------|----------|
| **Network manipulation** (scenarios 1, 2, 3, 8, 11, 14, 15) | Use Network Link Conditioner (macOS system preference) set to "100% Loss" profile. Alternatively, use Charles Proxy rules to block CoinGecko/Tatum API domains. |
| **Mock API responses** (scenarios 3, 4, 9) | Inject mock service implementations via `DIContainer` test configuration. Create `MockCoinGeckoService` that returns `.failure(.networkUnavailable)` or `.failure(.calculationFailed)` per scenario. |
| **Multi-failure simulation** (scenario 9) | Configure 3 mock services simultaneously: `MockExchangeRateService(.failure)`, `MockBalanceService(.failure)`, `MockGoalCalculationService(.failure)`. |
| **Device** | iPhone 16 simulator (iOS 18+) for all scenarios. iPad Pro simulator for scenario 7 (verify sheet presentation). |
| **Automation candidates** | Scenarios 1, 2, 3, 7, 8, 12 are automatable with mock injection; file follow-up tickets for UI test automation after manual verification. |

### 8.3 User-Outcome Success Criteria

| Criterion | Target | Measurement |
|-----------|--------|-------------|
| Error-to-recovery tap count | <= 2 taps for all retryable errors | Manual walkthrough of each error scenario; count taps from error appearance to successful recovery |
| Zero blank/zero data with cache available | No screen shows $0.00 or blank when cached data exists | Scenarios 1, 3, 11 in manual test matrix |
| VoiceOver goal creation | VoiceOver users can complete goal creation flow without sighted assistance | VoiceOver-only walkthrough by tester: create goal, select currency, set target, save |
| Error-to-recovery time | < 5 seconds for single retry on fast network | Time from "Retry" tap to loaded state on Wi-Fi |

### 8.4 VoiceOver Audit Checklist

Screen-by-screen pass criteria (all must pass before merge):

| Screen | Pass Criteria |
|--------|--------------|
| Dashboard | All section headers, error banners (single and coalesced), widget controls, and chart summaries announced with meaningful labels. Coalesced banner expandable via VoiceOver. |
| GoalDetail | Progress ring percentage, allocation amounts, error banners announced. Cached-data indicator announced. Freshness indicator announced. |
| GoalsList | Goal names, progress, navigation links all have identifiers; deduplication banner announced |
| MonthlyPlanning | Requirement status announced as text (not color); all interactive controls labeled |
| AddGoal | Currency picker, form fields, error states, fallback indicator all accessible. Reduced-scope banner announced. |
| Onboarding | All steps navigable; progress indicator announced; error banner announced; completion state announced |
| Charts (Enhanced) | Data points announce value and date on selection. Chart trend summary provided. |
| Charts (Progress) | Both full and compact ring variants announce percentage, current, target |

### 8.5 Post-Ship Monitoring Plan

**Baseline Snapshot** (recorded in Phase 0 -- MANDATORY before Phase 1 begins):

| Signal | Data Source | Recording Method | Current Baseline | Target Post-Merge |
|--------|-------------|-----------------|-----------------|-------------------|
| Crash-free rate | Xcode Organizer > Crashes | Open Organizer, select current build, read "Crash Free Rate" percentage. If pre-release, use latest TestFlight build or record "N/A (pre-release)". | ___ % (Phase 0, Step 0.1) | >= baseline |
| "Missing data" / "zero balance" support tickets | Support channel (email / GitHub Issues / internal tracker) | Search for keywords: "missing data", "zero balance", "$0.00", "blank", "empty dashboard" in last 30 days. Record count and date range searched. | ___ tickets in ___-to-___ (Phase 0, Step 0.2) | 0 new tickets with these keywords |
| CI pass rate | Local `xcodebuild test` (3 runs) or last 10 CI runs | Record pass count / total runs as percentage. Note any pre-existing flaky tests by name. | ___ % (___ / ___ runs) (Phase 0, Step 0.3) | 100% |
| Accessibility snapshot test stability | N/A (new in Phase 5) | Baseline established after Phase 5.12 ships. First 1-week window post-merge serves as stability baseline. | N/A (new) | No flaky failures over 1 week |

**Recording gate**: Phase 0, Step 0.4 commits the filled-in baseline values to this table via a dedicated git commit. Phase 1 MUST NOT begin until this commit exists.

In the first week after merge, "success" is defined as meeting or exceeding all baseline thresholds. If any baseline was recorded as "N/A", that signal is monitored from first available measurement onward.

---

## 9. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **ServiceResult migration breaks existing callers** | **Low** | High | Additive method strategy: new `*Result` methods alongside existing `async throws`. Zero protocol conformance breaks. Existing tests, mocks, callers unchanged. Rollback = revert ViewModel callers only. Test doubles override `*Result` methods directly (not default extension). |
| **ViewModel error state surfaces too many alerts** | Medium | Medium | Error tier decision matrix (Section 5.2) governs which tier per screen/failure. `CoalescedErrorBannerView` prevents flooding. Error deduplication via service-layer broadcasting (Section 5.4.1). |
| **ErrorHandler.shared and ErrorAwareViewModel fire simultaneously** | **High** (current state) | Medium | Error routing contract (Section 5.1) defines exclusive ownership. Phase 3.9 audits all call sites. ErrorHandler.shared calls removed from conforming VMs. |
| **Accessibility layout changes break visual design** | Low | Medium | Accessibility snapshot tests at Default + AX5. Semantic fonts render at same baseline size as hardcoded equivalents. `@ScaledMetric` with min/max constraints (Section 5.7). Phase 7.9 visual regression check. `.fontDesign(.rounded)` preserves onboarding character. |
| **Large PR surface area** | High | Medium | Phased merge strategy (6 PRs). Phase 4/5 file overlap explicitly sequenced (5a after 4, 5b parallel). Each PR independently compilable and testable. MVP cut-line (Section 7.2) provides scope-reduction fallback. |
| **Effort exceeds 33-hour budget** | Medium | Medium | MVP cut-line (Section 7.2) defines Phases 1-3.5 + Phase 4 (4.1-4.7) as minimum shippable increment. Phase 3.5 validation spike provides early checkpoint at ~14 hours. Remaining phases ship as P1 follow-up. |
| **ChartError bridge introduces regressions** | Low | Medium | Bridge adds extension method, doesn't modify ChartError itself. CompactChartErrorView deprecated, not deleted. Full ChartErrorView unchanged. Phase 7.10 grep verification gate. |
| **Inconsistent state transitions across 15 screens** | Medium | Medium | State transition contract (Section 5.3) defines standard animations. `AsyncContentView` implements transitions centrally; screens inherit them. Haptic feedback centralized. |
| **Scope creep into architectural refactoring** | Medium | Medium | Non-goals boundary explicit. CoalescedErrorBannerView acknowledged as new component scope with MVP fallback. Error routing contract documents existing behavior. Additive ServiceResult strategy avoids protocol refactoring. |
| **Onboarding changes break first-run experience** | Low | High | Error handling is additive (new banner). Font size changes use semantic equivalents with `.fontDesign(.rounded)` preserved. Verification scenario #8 validates. |
| **False positives in audit data** | **Low** | Medium | All remaining findings verified line-by-line against source. 3 false positives already removed. AppError count verified (25). ERR-01 root cause verified (GoalViewModel, not ExchangeRateService). |
| **Component bugs propagate to 15+ screens** | Low | High | Phase 1.11 adds component validation tests before Phase 4 mass adoption. All ViewState cases rendered and verified. |
| **Service-layer error broadcasting creates memory leaks** | Low | Medium | Use `weak` references in Combine subscriptions. ViewModel `cancellables` set deallocates subscriptions on deinit. Standard Combine ownership pattern. |

---

## 10. Open Questions

| # | Question | Impact | Resolution | Status |
|---|----------|--------|-----------|--------|
| 1 | Should `ChartError` be fully replaced or bridged? | Architecture cleanliness vs. scope | **Bridge first**: add `ChartError.toUserFacingError()` extension. Deprecate `CompactChartErrorView`. Full `ChartError` removal is follow-up work. | Resolved |
| 2 | How many coins in the fallback currency list? | Offline coverage vs. binary size | **Top 50 by market cap** with id, symbol, name, `lastUpdated` field. ~5KB JSON embedded. Covers 95%+ of user selections. Refreshed once per app release cycle. | Resolved |
| 3 | Should `ErrorBannerView` auto-dismiss? | UX clarity vs. missed notifications | **No auto-dismiss** for errors. Users must explicitly dismiss. Auto-dismiss for success banners only (1.5s per Section 5.3). | Resolved |
| 4 | Should `ExchangeRateWarningView` be replaced or refactored? | Code reuse vs. domain specificity | **Refactor** to use `ErrorBannerView` internally, keeping domain-specific logic but unifying visual presentation. | Resolved |
| 5 | How to handle concurrent Dashboard errors? | Error flood vs. information | **Priority coalescing** via `CoalescedErrorBannerView` with progressive disclosure (highest-priority error in collapsed state). Spec in Section 5.5. DashboardErrorAggregator coordinator for independent testability. | Resolved |
| 6 | Should accessibility snapshot tests block CI? | Reliability vs. safety | **Block on P0 flows** (Dashboard, GoalDetail, MonthlyPlanning) at Default + AX5 sizes; warn-only on secondary flows initially. XCTest-native UI test screenshots (zero external dependencies). Baseline images tracked in git. Promote to blocking after 1 release cycle of stability. | Resolved |
| 7 | Should onboarding silently complete when goal creation fails? | First-run quality vs. simplicity | **No**. Show error banner with retry (Section 5.18). Next button remains enabled with "Continue without starter goal?" confirmation. Post-failure empty state on Dashboard (Section 5.12). | Resolved |
| 8 | When should legacy `async throws` service methods be deprecated? | API surface hygiene vs. scope | **Out of scope for this proposal.** Tracked follow-up: after all ViewModel callers migrate to `*Result` methods, mark original methods `@available(*, deprecated)`. New ViewModel code MUST use `*Result` methods (documented in error routing contract, Phase 1.6). Mock implementations SHOULD override `*Result` directly. | Resolved (deferred) |
| 9 | What error deduplication interface should parent/child VMs use? | Coupling vs. simplicity | **Service-layer broadcasting** (Section 5.4.1). No parent-child ViewModel coupling. Services publish error state; VMs and list-level banners subscribe independently. | Resolved |
| 10 | How should `GoalEditViewModel` handle dual error surfaces? | Protocol clarity vs. flexibility | ErrorAwareViewModel conformance for **async save path only**. `retry()` = retry save. Form validation continues via existing `validationErrors` properties. Documented in Phase 3.3. | Resolved |

---

## 11. Non-Blocking Implementation Guidance (Run 2 Reviewer Feedback)

> The following items were catalogued as non-blocking issues and suggestions during Run 2's conditional approval (avg 9.0/10). They do not require proposal revision but should be addressed during implementation where feasible. Implementers should reference this section during each phase.

### 11.1 Non-Blocking Issues (30)

#### From Architect (5)

| ID | Issue | Recommended Resolution | Phase |
|----|-------|----------------------|-------|
| ARCH-01 | macOS `.refreshable` behavior differs from iOS pull-to-refresh (no pull gesture) | Add platform note to Section 5.11. On macOS, provide explicit "Refresh" toolbar button as alternative. Use `PlatformCapabilities` to conditionally add toolbar item. | 4 |
| ARCH-02 | `GoalsListView` `.refreshable` may already exist via `GoalsListContainer` | Verify before adding duplicate. If present, wire to `viewModel.retry()`. | 4 |
| ARCH-03 | `AsyncContentView` degraded-state upgrade creates new dependency on `ErrorBannerView` | Acceptable coupling -- both are error component family. Document in component registry. | 1 |
| ARCH-04 | Retry failure counter scope and lifecycle unspecified | Use per-ViewModel counter property. Reset on any successful load. Counter survives view re-renders but resets on ViewModel `deinit`. | 3 |
| ARCH-05 | Preview files should be excluded from Phase 5 font remediation scope | Exclude `*Preview.swift` files from the 77-instance font remediation count. Preview files are developer-facing only. | 5 |

#### From UX Designer (10)

| ID | Issue | Recommended Resolution | Phase |
|----|-------|----------------------|-------|
| UX-R2-01 | Dual spinner ambiguity during degraded-state retry | Use banner Retry button spinner only (per Section 5.3.1). No navigation bar spinner during degraded retry. | 4 |
| UX-R2-02 | Pull-to-refresh unreachable on T1 full-screen `ErrorStateView` after retry escalation | Wrap `ErrorStateView` content in a minimal `ScrollView` to enable `.refreshable`, or keep "Try Again" button always tappable regardless of escalation state. | 4 |
| UX-R2-03 | Post-onboarding failure transient flag risks stale resurrection after goal deletion | Add 24-hour TTL to the transient flag in `OnboardingManager`. After TTL, flag auto-clears regardless of goal state. | 4 |
| UX-R2-04 | CoalescedErrorBannerView collapse threshold of 2 feels premature for dashboard | Consider raising threshold to 3 during implementation. Test with 2 vs 3 during Phase 3.5 validation spike. | 4 |
| UX-R2-05 | Success banner 1.5s auto-dismiss too fast for VoiceOver users | Extend auto-dismiss to 3s when `UIAccessibility.isVoiceOverRunning`. Ensure VoiceOver announcement completes before dismiss. | 4 |
| UX-R2-06 | `FreshnessIndicatorView` is awareness-only with no action path | Add tap gesture on indicator that scrolls to/shows nearest retry action. Low priority -- implement if time permits. | 4 |
| UX-R2-07 | MonthlyExecutionView mid-flow unsynced badge accumulation at scale | If 5+ unsynced items accumulate, coalesce into single "5 items pending sync" banner. | 4 |
| UX-R2-08 | Reassurance copy assumes existing portfolio context (unhelpful for new users) | Vary reassurance copy based on portfolio state: new users get "Your goal is saved locally" vs existing users get "Your savings are safe". | 1 |
| UX-R2-09 | No animation spec for initial-load-into-degraded state (cache available, refresh fails immediately) | Animate banner in after 0.15s delay (let content render first). Use `.spring(response: 0.3)` slide-down. | 4 |
| UX-R2-10 | Haptic feedback uses iOS-only `UINotificationFeedbackGenerator` without macOS guard | Wrap in `PlatformCapabilities` check. On macOS, use `NSHapticFeedbackManager` or skip haptics. | 1 |

#### From UI Designer (8)

| ID | Issue | Recommended Resolution | Phase |
|----|-------|----------------------|-------|
| UI-R2-01 | Layout token fragmentation not addressed alongside color token migration | Define shared `ErrorComponentTokens` constants (padding: 12pt, cornerRadius: 10pt, spacing: 8pt) in Phase 1 alongside color tokens. | 1 |
| UI-R2-02 | CoalescedErrorBannerView interactive state machine lacks dedicated test step | Add Phase 4.14b: unit tests for collapse/expand, individual dismiss, Retry All, VoiceOver announcements. | 4 |
| UI-R2-03 | Vertical stacking order undefined when T2 banner and T3 freshness indicator coexist | Define: T2 banner above T3 indicator with 8pt spacing. Banner pushes indicator down. | 4 |
| UI-R2-04 | `@ScaledMetric` clamping formula inverted in Step 5.4 description | Fix to `min(max(ringHeight, 120), 280)` (clamp between min and max, not the reverse). | 5 |
| UI-R2-05 | Dark mode verification absent from Phase 7 | Add Phase 7.8b: verify all error components in dark mode. Check `AccessibleColors` token adaptation. | 7 |
| UI-R2-06 | `errorBackground` token conditional language misleading -- token may already exist | Check `AccessibleColors.swift` first. If token exists, use it directly. Remove "if needed" language. | 1 |
| UI-R2-07 | Fallback currency reduced-scope banner styling mismatch with `FreshnessIndicatorView` | Align styling: use same `.caption` size, same icon treatment, same foreground color. | 4 |
| UI-R2-08 | Success banner visual treatment referenced but not specified as component | Define success banner: green `AccessibleColors.success` background, checkmark icon, `.caption` text, auto-dismiss 1.5s (3s VoiceOver). Consider adding to Appendix E. | 4 |

#### From Product Owner (7)

| ID | Issue | Recommended Resolution | Phase |
|----|-------|----------------------|-------|
| PO-NB-01 | CoalescedErrorBannerView: consider defaulting to MVP fallback | Default to stacked `ErrorBannerView` MVP. Only implement full `CoalescedErrorBannerView` if Phase 3.5 demo confirms need. | 4 |
| PO-NB-02 | No instrumentation plan for ongoing error encounter rate measurement | File follow-up ticket for analytics/telemetry. Out of scope per Non-Goals but document the gap. | Post |
| PO-NB-03 | Phase 3.5 iteration budget undefined; MVP cut-line may trigger prematurely | Allow up to 2 iterations on Phase 3.5 demo feedback before activating MVP cut-line. | 3.5 |
| PO-NB-04 | Manual test matrix timing underspecified for Phase 5 and Phase 6 PRs | Phase 5 PR requires scenarios 5, 6, 10 sign-off. Phase 6 PR requires scenario 7 sign-off. | 5, 6 |
| PO-NB-05 | Fallback currency list staleness detection not automated | File follow-up ticket for CI check comparing embedded list age against configurable threshold. | Post |
| PO-NB-06 | No production data cited to validate severity rankings | Severity rankings based on code-level impact analysis (verified). Production data validates post-ship. | Post |
| PO-NB-07 | Onboarding font remediation lacks quantitative visual regression pass/fail criteria | Define: rendered size difference > 10% at default text size = regression. Verify in Phase 7.9. | 7 |

### 11.2 Recurring Themes (8)

These themes appeared across multiple reviewers and should be monitored throughout implementation:

| # | Theme | Sources | Recommended Approach |
|---|-------|---------|---------------------|
| 1 | CoalescedErrorBannerView is the highest-complexity single deliverable | PO-NB-01, UI-R2-02 | Default to stacked-ErrorBannerView MVP. Upgrade to full component only if validated in Phase 3.5 spike. Add dedicated test step (Phase 4.14b) if full component retained. |
| 2 | macOS platform behavioral differences | ARCH-01, UX-R2-10 | Add explicit macOS platform notes to Sections 5.11 and 5.3. Use `PlatformCapabilities` wrapper for haptics and pull-to-refresh alternatives. |
| 3 | Animation and transition edge cases | UX-R2-01, UX-R2-09, UI-R2-03 | Use banner Retry button spinner only (no dual spinner). Animate banner in after 0.15s delay for initial-load-into-degraded. Define T2-above-T3 with 8pt spacing. |
| 4 | Measurement and verification gaps | PO-B-01 (resolved), PO-NB-02, UI-R2-05, PO-NB-07 | Phase 0 resolves baseline recording. Add dark mode verification to Phase 7. Define 10% threshold for visual regression. File follow-up for error rate instrumentation. |
| 5 | Success banner visual treatment underspecified | UI-R2-08, UX-R2-05 | Define success banner component tokens during Phase 4. Extend auto-dismiss to 3s when VoiceOver active. |
| 6 | Layout token standardization | UI-R2-01, UI-R2-07 | Define `ErrorComponentTokens` shared constants in Phase 1 alongside color migration. |
| 7 | Retry state management details | ARCH-04, UX-R2-02 | Per-ViewModel counter, reset on success. Wrap `ErrorStateView` in `ScrollView` for `.refreshable` reachability. |
| 8 | Onboarding edge cases | UX-R2-03, PO-NB-07 | Add 24h TTL to transient flag. Define 10% rendered-size regression threshold. |

### 11.3 Suggestions (26)

Run 2 reviewers provided 26 suggestions (4 from Architect, 10 from UX, 4 from UI, 8 from PO). These are optional enhancements that may improve quality but are not required for approval. They are preserved in the Run 2 review artifacts at:
- Architect: `/artifacts/state_4_proposal_reviewed.2/proposal_reviewer_architect/1/proposal_review_architect`
- UX: `/artifacts/state_4_proposal_reviewed.2/proposal_reviewer_ux/1/proposal_review_ux`
- UI: `/artifacts/state_4_proposal_reviewed.2/proposal_reviewer_ui/1/proposal_review_ui`
- PO: `/artifacts/state_4_proposal_reviewed.2/proposal_reviewer_product_owner/1/proposal_review_po`

Implementers should consult these artifacts for additional polish opportunities during each phase.

---

## Appendix A: Files Modified by Phase

### Phase 0 (Baseline Metrics Recording)
- This proposal document (modify - fill in Section 8.5 baseline values)
- No source code changes

### Phase 1 (Foundation)
- `Utilities/ServiceResult.swift` (modify - expand ErrorTranslator to 25 cases with reassurance clauses)
- `Models/ChartError.swift` (modify - add `toUserFacingError()` extension)
- `Views/Components/ErrorStateView.swift` (modify - add secondary action per Section 5.10)
- `Views/Components/AsyncContentView.swift` (modify - degraded state upgrade with onRetry/onDismiss per Section 5.9, a11y labels, transition animations, haptic feedback)
- `Views/Components/ChartErrorView.swift` (modify - deprecate CompactChartErrorView)
- `Views/Components/ErrorBannerView.swift` (modify - migrate to AccessibleColors tokens per Section 5.16)
- `Utilities/AccessibleColors.swift` (modify - add `errorBackground` token if needed)
- `Utilities/FallbackCurrencyList.swift` (new)
- `Utilities/FreshnessPolicy.swift` (new - injectable freshness thresholds)
- `DIContainer` (modify - register FreshnessPolicy)
- `docs/ERROR_ROUTING_CONTRACT.md` (new)
- `Tests/ErrorTranslatorTests.swift` (new - 31 test cases)
- `Tests/ErrorComponentTests.swift` (new - component validation tests)

### Phase 2 (Services)
- `Services/ExchangeRateService.swift` (modify - add `fetchRateResult` + `serviceError` publisher)
- `Services/CoinGeckoService.swift` (modify - add `fetchCurrencyListResult` with embedded fallback)
- `Services/GoalCalculationService.swift` (modify - add result-returning methods)
- `Services/BalanceService.swift` (modify - add `fetchBalanceResult` + `serviceError` publisher)
- `Services/Protocols/ServiceProtocols.swift` (modify - add new protocol methods with defaults + publisher requirements)
- Existing/new service test files (modify/new)

### Phase 3 (ViewModels)
- All 9 files in `ViewModels/` (modify)
- `ViewModels/DashboardErrorAggregator.swift` (new - error coalescing coordinator)
- New ViewModel error test files (new)

### Phase 3.5 (Validation Spike)
- `Views/DashboardView.swift` (modify - AsyncContentView wiring + FreshnessIndicatorView)
- `Views/GoalDetailView.swift` (modify - AsyncContentView wiring + FreshnessIndicatorView)

### Phase 4 (Views)
- `Views/DashboardView.swift` (modify - CoalescedErrorBannerView, pull-to-refresh, post-onboarding empty state, FreshnessIndicatorView extension)
- `Views/GoalDetailView.swift` (modify - pull-to-refresh, FreshnessIndicatorView)
- `Views/AddGoalView.swift` (modify - fallback list + reduced-scope banner)
- `Views/AssetDetailView.swift` (modify - FreshnessIndicatorView)
- `Views/AddTransactionView.swift` (modify - error banner above form)
- `Views/EditGoalView.swift` (modify)
- `Views/Planning/MonthlyExecutionView.swift` (modify - AsyncContentView + mid-flow spec)
- `Views/Planning/MonthlyPlanningView.swift` (modify - pull-to-refresh)
- `Views/Components/ChartErrorView.swift` (modify - help navigation as disclosureGroup)
- `Views/Components/ExchangeRateWarningView.swift` (modify)
- `Views/Components/CoalescedErrorBannerView.swift` (new - moved from Phase 1)
- `Views/Onboarding/OnboardingFlowView.swift` (modify - error handling + confirmation dialog)
- `Views/GoalsListView.swift` (modify - deduplication banner + FreshnessIndicatorView, pull-to-refresh)
- Chart view files using CompactChartErrorView (modify)

### Phase 5 (Accessibility)

**Phase 5a** (after Phase 4 commits - shared files):
- `Views/DashboardView.swift` (modify - a11y labels, font)
- `Views/GoalDetailView.swift` (modify - @ScaledMetric adaptive sizing)
- `Views/GoalsListView.swift` (modify - a11y identifiers)
- `Views/Onboarding/OnboardingFlowView.swift` (modify - 5 font sizes + .fontDesign(.rounded))
- `Views/Onboarding/OnboardingStepViews.swift` (modify - 40 font sizes + .fontDesign(.rounded))
- `Views/Dashboard/EnhancedDashboardComponents.swift` (modify - 3 fonts)
- `Views/Dashboard/DashboardComponents.swift` (modify - 1 font)
- New accessibility snapshot test files (new)

**Phase 5b** (parallel with Phase 4 - independent files):
- `Views/Planning/PlanningView.swift` (modify - 2 fonts)
- `Charts/SimpleStackedBarView.swift` (modify - @ScaledMetric dynamic sizing)
- `Charts/EnhancedLineChartView.swift` (modify - VoiceOver)
- `Charts/LineChartView.swift` (modify - VoiceOver)
- `Charts/ProgressRingView.swift` (modify - CompactProgressRingView a11y + 6 @ScaledMetric proportional fonts)
- `Charts/SparklineChartView.swift` (modify - 1 @ScaledMetric proportional font)
- `Charts/StackedBarChartView.swift` (modify - 2 @ScaledMetric proportional fonts)
- `Views/EmptyGoalsView.swift` (modify - button a11y + 1 font)
- `Views/Components/EmptyStateView.swift` (modify - 3 fonts)
- `Views/Components/EmptyDetailView.swift` (modify - 1 font)
- `Views/Components/HeroProgressView.swift` (modify - 1 font)
- `Views/Components/FlexAdjustmentSlider.swift` (modify - 1 font)
- `Views/Components/GoalSwitcherBar.swift` (modify - 1 font)
- `Views/Components/MonthlyPlanningWidget.swift` (modify - 2 fonts)
- `Views/Components/ChartErrorView.swift` (modify - 1 font -> @ScaledMetric 48pt icon)
- `Views/AssetDetailView.swift` (modify - 1 font)
- `Views/Goals/GoalComparisonView.swift` (modify - 1 font)
- `Views/TransactionHistoryView.swift` (modify - 1 font)
- `Views/Planning/GoalRequirementRow.swift` (modify - 1 font)
- `Views/Components/ErrorBannerView.swift` (modify - adaptive layout at accessibility sizes)

### Phase 6 (Navigation)
- `Views/Planning/MonthlyExecutionView.swift` (verify/modify)
- Planning and goal edit views (verify)

### File Overlap Summary

| File | Phase 4 Changes | Phase 5 Changes | Sequencing |
|------|-----------------|-----------------|-----------|
| `DashboardView.swift` | AsyncContentView, CoalescedErrorBannerView, pull-to-refresh, post-onboarding empty state, FreshnessIndicatorView | a11y labels, semantic fonts (1 instance) | 5a: after Phase 4 |
| `GoalDetailView.swift` | ErrorBannerView, pull-to-refresh, FreshnessIndicatorView | @ScaledMetric adaptive sizing | 5a: after Phase 4 |
| `GoalsListView.swift` | deduplication banner, pull-to-refresh, FreshnessIndicatorView | a11y identifiers | 5a: after Phase 4 |
| `OnboardingFlowView.swift` | error handling (lines ~140-169) | font sizes (5 instances, lines ~229-280) + .fontDesign(.rounded) | **5a: after Phase 4** |
| `OnboardingStepViews.swift` | (none) | font sizes (40 instances) + .fontDesign(.rounded) | 5a: sequential with OnboardingFlowView |
| `EnhancedDashboardComponents.swift` | (none) | 3 font fixes | 5a: after DashboardView Phase 4 |
| `DashboardComponents.swift` | (none) | 1 font fix | 5a: after DashboardView Phase 4 |

---

## Appendix B: Dependency on Existing Proposals

| Existing Document | Relationship | Action |
|-------------------|-------------|--------|
| `docs/proposals/RESILIENT_ERROR_HANDLING_RECOVERY_UX_PROPOSAL.md` (Draft) | This proposal implements Phases 1-5 of that proposal | Supersedes: update status to "In Progress" upon execution |
| `docs/proposals/ACCESSIBILITY_DYNAMIC_TYPE_HARDENING_PROPOSAL.md` (Draft) | This proposal implements the critical fixes | Partial implementation: covers P0/P1 items; P2 deferred |
| `docs/NAVIGATION_PRESENTATION_CONSISTENCY.md` (Current) | Reference: verifies compliance, fixes edge cases | No changes to the policy document |
| `docs/VISUAL_SYSTEM_UNIFICATION.md` (Current) | Reference: functional UX defects that intersect | No changes to the policy document |
| `docs/COMPONENT_REGISTRY.md` (Current) | Must update for new/deprecated components | Update with `CoalescedErrorBannerView` (Phase 4), `FallbackCurrencyList` (Phase 1), `DashboardErrorAggregator` (Phase 3), CompactChartErrorView deprecation (Phase 1), `FreshnessPolicy` (Phase 1), `ChartHelpSheetView` content (Phase 4) |

---

## Appendix C: Verification Matrix

| # | Scenario | Steps | Expected Result |
|---|----------|-------|----------------|
| 1 | Dashboard with no network | Disable network, open dashboard | Cached data with freshness indicator; coalesced error banner for refresh failures with retry; no blank sections |
| 2 | Create goal offline | Disable network, tap Add Goal | Fallback currency list loads (50 coins) with reduced-scope banner; goal creation succeeds with cached rates; freshness indicator shown |
| 3 | Exchange rate failure | Mock CoinGecko 500, open GoalDetail | Banner with reassurance copy. Retry present. Progress NOT $0.00. Freshness indicator visible. |
| 4 | Chart data unavailable | Mock calculation failure, open dashboard | Chart section shows error with "Try Again"; other sections unaffected |
| 5 | VoiceOver on planning rows | Enable VoiceOver, navigate Monthly Planning | Status announced as descriptive text (e.g., "On track", "Behind schedule") |
| 6 | Dynamic Type AX5 | Set text size to AX5, navigate all screens including onboarding | No clipped buttons, no overlapping text, all controls reachable. ErrorBannerView reflows to VStack layout. |
| 7 | Dirty form dismiss | Edit a goal, swipe to dismiss | Confirmation: "Keep Editing" / "Discard" |
| 8 | Complete onboarding offline | Disable network, complete onboarding flow | Error banner between content and nav buttons; Next button enabled with confirmation dialog; can dismiss and complete |
| 9 | Multi-error dashboard | Mock 3 service failures, open dashboard | Coalesced banner with progressive disclosure; expandable to individual errors; Retry All retries all; VoiceOver announces count |
| 10 | Chart VoiceOver interaction | Enable VoiceOver, select EnhancedLineChartView data point | Announces value, date, context (e.g., "March 15: $1,250.45 USD") |
| 11 | List error deduplication | Mock exchange rate failure, open Goals list with 5+ goals | Single top-level banner, not 5 individual error states. Goals show cached indicator. Service-layer broadcasting verified. |
| 12 | All tests pass | Run `xcodebuild test` | Zero failures |
| 13 | Post-onboarding failure empty state | Complete onboarding offline (goal creation fails), open Dashboard | Context-aware empty state with "Try Again" and "Create Goal Manually" actions |
| 14 | Pull-to-refresh recovery | Open Dashboard offline (degraded), dismiss banner, pull-to-refresh | Refresh triggers retry; success transitions to loaded state with success haptic |
| 15 | Retry escalation | Open screen offline, tap Retry 3x (all fail) | Button changes to "Try Later" after 3rd failure; pull-to-refresh still works |

---

## Appendix D: ErrorTranslator Complete Mapping

### AppError -> UserFacingError (25 cases)

| Case | Title | Message | Recovery Suggestion | Retryable | Category |
|------|-------|---------|-------------------|:-:|---------|
| `networkUnavailable` | No Connection | Unable to reach the server. **Your savings are unaffected.** | Check your internet connection and try again. We'll show the latest values once reconnected. | Yes | network |
| `invalidURL(String)` | Connection Error | The request could not be completed. | Try again. If the problem persists, contact support. | Yes | network |
| `requestTimeout` | Request Timed Out | The server is taking too long to respond. **Your assets are safe.** | Check your connection and try again. | Yes | network |
| `invalidResponse` | Connection Error | Received an unexpected response from the server. | Try again. If the problem persists, the service may be experiencing issues. | Yes | network |
| `decodingFailed(String)` | Connection Error | The data received could not be processed. | Try again. If the problem persists, an app update may be needed. | Yes | network |
| `rateLimited` | Rate Limited | Too many requests. Please wait a moment. | Wait a few seconds and try again. | Yes | network |
| `apiKeyInvalid` | API Key Issue | Your API key is invalid or expired. | Go to Settings to update your API key. | No | apiKey |
| `apiQuotaExceeded` | Rate Limit Reached | You've exceeded the API usage limit. | Wait a few minutes or upgrade your API plan. | Yes | network |
| `coinNotFound(String)` | Coin Not Found | The cryptocurrency "[coin]" could not be found. | Check the coin name and try again. | No | unknown |
| `chainNotSupported(String)` | Chain Not Supported | The blockchain "[chain]" is not currently supported. | Choose a supported blockchain. | No | unknown |
| `addressInvalid(String)` | Invalid Address | The wallet address "[address]" is not valid. | Check the address format and try again. | No | unknown |
| `goalNotFound` | Goal Not Found | The savings goal could not be found. It may have been deleted. | Return to the goals list. | No | dataCorruption |
| `assetNotFound` | Asset Not Found | The asset could not be found. It may have been removed. | Return to the assets list. | No | dataCorruption |
| `transactionNotFound` | Transaction Not Found | The transaction could not be found. | Return to the transaction list. | No | dataCorruption |
| `saveFailed` | Save Failed | Your changes could not be saved. | Try again. If the problem persists, check available storage. | Yes | dataCorruption |
| `deleteFailed` | Delete Failed | The item could not be deleted. | Try again. If the problem persists, restart the app. | Yes | dataCorruption |
| `modelContextUnavailable` | Data Unavailable | The app's data store is temporarily unavailable. | Restart the app. If the problem persists, check iCloud settings. | No | dataCorruption |
| `invalidAmount` | Invalid Amount | The amount entered is not valid. | Enter a positive number. | No | unknown |
| `invalidDate` | Invalid Date | The date entered is not valid. | Select a valid date. | No | unknown |
| `calculationFailed` | Calculation Error | A calculation could not be completed. | Try again. If the problem persists, check your input values. | Yes | unknown |
| `currencyConversionFailed` | Conversion Error | Price data is temporarily unavailable. **Your savings are safe** -- we just can't show the current value right now. | Check your connection and try again. Exchange rates will update automatically when available. | Yes | network |
| `featureUnavailable(String)` | Feature Unavailable | "[feature]" is not available on this device or OS version. | Update to the latest OS version. | No | unknown |
| `permissionDenied(String)` | Permission Required | "[permission]" access is required for this feature. | Go to Settings > Privacy to grant access. | No | unknown |
| `widgetUpdateFailed` | Widget Update Failed | The widget could not be updated with the latest data. | The widget will update automatically on next refresh. | No | unknown |
| `notificationsFailed` | Notification Error | Notifications could not be configured. | Check notification permissions in Settings. | No | unknown |

### ChartError -> UserFacingError Bridge (6 cases)

| Case | Title | Message | Retryable | Category |
|------|-------|---------|:-:|---------|
| `dataUnavailable(String)` | Chart Data Unavailable | [context from associated value] | Yes | unknown |
| `networkError(String)` | Chart Update Failed | [message from associated value]. **Your assets are safe.** | Yes | network |
| `conversionError(from:to:)` | Conversion Error | Currency conversion from [from] to [to] failed. **Your savings are safe** -- showing last known values. | Yes | network |
| `calculationError(String)` | Chart Calculation Error | [context from associated value] | Yes | unknown |
| `invalidDateRange` | Invalid Date Range | The selected date range is not valid for this chart. | No | unknown |
| `insufficientData(min:actual:)` | Not Enough Data | This chart requires at least [min] data points. You have [actual]. | No | unknown |

---

## Appendix E: Error Component Visual Comparison

| Property | ErrorBannerView | ErrorStateView | ChartErrorView (full) | CoalescedErrorBannerView | FreshnessIndicatorView |
|----------|----------------|----------------|----------------------|--------------------------|----------------------|
| **Corner radius** | 10pt | N/A (ContentUnavailableView) | 0 (inline) | 10pt | 0 (inline) |
| **Padding** | 12pt | System | 16pt | 12pt | 4pt |
| **Background** | `AccessibleColors` token by category | System | None | Highest-severity token | None |
| **Typography** | `.caption` title, `.caption2` message | `.headline` title, `.subheadline` desc | `.headline` title, `.subheadline` desc | `.subheadline.semibold` collapsed | `.caption2` |
| **Icon** | Category-mapped SF Symbol | Category-mapped SF Symbol | `exclamationmark.triangle` 48pt (@ScaledMetric) | Highest-severity category icon | `clock` / `exclamationmark.triangle` |
| **Action buttons** | Retry (`.bordered`), Dismiss (`.plain` X) | Try Again (`.bordered`), Secondary (`.plain`) | Try Again (`.bordered`), Learn More (`.bordered`) | Per-error Retry + Retry All (`.bordered`) | None |
| **Accessibility** | `.accessibilityElement(children: .combine)` | `.accessibilityElement(children: .combine)` | `.accessibilityElement(children: .combine)` | `.accessibilityContainer` with per-error elements | `.accessibilityElement` |
| **Adaptive layout** | HStack -> VStack at AX sizes | System-managed | Fixed | HStack -> VStack at AX sizes | Single line |
| **Animation** | `.spring(response: 0.3)` slide | `.easeOut` | None | `.spring(response: 0.3)` expand/collapse | None |
