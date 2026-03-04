# Budget Health Widget

> Consolidated budget status widget for the Monthly Planning view that adapts by state to show one clear budget signal with a single actionable CTA

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-03-01 |
| Platform | iOS |
| Audience | Developers |

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Budget health state](#budget-health-state)
4. [Card specification](#card-specification)
5. [Visual and layout rules](#visual-and-layout-rules)
6. [Accessibility](#accessibility)
7. [Motion and haptics](#motion-and-haptics)
8. [Fiat and crypto constraints](#fiat-and-crypto-constraints)
9. [Telemetry](#telemetry)
10. [API reference](#api-reference)
11. [File locations](#file-locations)
12. [Related documentation](#related-documentation)

---

## Overview

The Budget Health Widget replaces two previously separate budget blocks (`Budget Needs Attention` notice and `Monthly Budget` summary card) with a single stateful card. It reduces duplicated messaging, reclaims vertical space for the goals list, and provides a faster path from risk detection to corrective action.

### Design principles

- One clear budget status per month with a single primary CTA.
- Risk and corrective actions are always visible and actionable.
- Mixed fiat/crypto planning is supported with explicit conversion context.
- Scroll-collapse behavior keeps the signal persistent without consuming full-card space.

### Scope

The widget covers budget status rendering and interaction in the Monthly Planning view. It does not affect the budget calculator algorithm, the planning tabs (`Goals`, `Adjust`, `Stats`), or the execution tracking UI.

---

## Architecture

### Header composition (compact iOS)

1. Sticky segmented control (`Goals / Adjust / Stats`)
2. **Budget Health Card** (single card, stateful)
3. KPI strip (`Monthly Total / Goals / Next Due`) - compact
4. Goal list / tab content

### Scroll behavior

In expanded state, the full Budget Health Card is visible. After a scroll threshold, the card collapses into a compact strip containing:

- State-specific status copy (max 20-24 chars)
- Optional compact risk count when width allows
- Single-word CTA (`Set`, `Edit`, `Apply`, `Review`, `Fix`, `Refresh`)

### Component structure

```
PlanningView
├── StaleDraftBanner (optional)
├── Tab Selector (Goals / Adjust / Stats)
├── BudgetHealthCard (expanded)          ← primary budget surface
├── BudgetHealthCollapsedStrip (sticky)  ← shown on scroll
├── KPI summary strip
└── Goals list / active tab content
```

The state is derived from a single computed property `MonthlyPlanningViewModel.budgetHealthState` and flows into both the expanded card and collapsed strip.

---

## Budget health state

### State enum

```swift
enum BudgetHealthState: Equatable {
    case noBudget
    case healthy
    case notApplied
    case needsRecalculation
    case atRisk(shortfall: Double, goalsAtRisk: Int)
    case severeRisk(shortfall: Double, goalsAtRisk: Int)
    case staleFX(lastUpdated: Date?, affectedCurrencies: [String])
}
```

### State matrix

| State | Trigger | Visual tone | Primary CTA | Secondary info | Collapsed strip |
|-------|---------|-------------|-------------|----------------|-----------------|
| `noBudget` | `monthlyBudget` is nil | neutral | `Set Budget` | "Set a monthly amount to optimize contributions." | "No budget set" + `Set` |
| `healthy` | feasible and applied | success | `Edit` | "All deadlines achievable." | "On track" + `Edit` |
| `notApplied` | budget exists, not applied to current month | info | `Apply Budget` | "Budget saved, not applied this month." | "Budget not applied" + `Apply` |
| `needsRecalculation` | budget exists, applied month/signature changed after goal/month update | warning | `Recalculate` | "Your goals or month changed. Recalculate allocations." | "Needs review" + `Review` |
| `atRisk` | infeasible, shortfall > 0 and <= 25% of min required | warning | `Fix Budget Shortfall` | shortfall amount + minimum required + next constraining goal | "Short by X" + `Fix` |
| `severeRisk` | infeasible and severe threshold met | danger | `Fix Budget Shortfall` | stronger risk text + minimum required + next constraining goal | "Short by X" + `Fix` |
| `staleFX` | rates too old / missing conversion for active goals | warning-neutral | `Refresh Rates` | timestamp + affected currencies | "Rates outdated" + `Refresh` |

### State precedence

The ViewModel resolves states deterministically when multiple conditions are true:

**Step 1** (global guard):
1. If `monthlyBudget == nil` -> `noBudget`.

**Step 2** (budget-present states, highest priority first):
1. `staleFX` (only when feasibility cannot be trusted)
2. `severeRisk`
3. `atRisk`
4. `notApplied`
5. `needsRecalculation`
6. `healthy`

Examples:
- `atRisk` + `staleFX` -> `staleFX` (confidence problem must be resolved first)
- `notApplied` + `needsRecalculation` -> `notApplied` (apply action has priority)
- `severeRisk` + `notApplied` -> `severeRisk`

### Severity thresholds

- `severeRisk`: shortfall ratio > 25% **or** affected goals ratio >= 40%
- `atRisk`: shortfall > 0 but below the `severeRisk` threshold

This keeps severe classification sensitive to broad goal impact, not only raw deficit percent.

---

## Card specification

### Card anatomy

1. **Title row**: `Monthly Budget` + trailing `Edit` action
2. **Primary number**: budget amount in budget currency
3. **Status line**: icon + short state text (e.g. `18 goals at risk`, `All deadlines achievable`)
4. **Primary insight**: one sentence explaining impact (e.g. `Short by US$4,399 this month`)
5. **Primary CTA**: one button only
6. **Secondary text**: next constrained goal and minimum required amount (when applicable)

### Copy principles

- One primary sentence, no duplicate warnings.
- Action-oriented labels (`Fix`, `Apply`, `Refresh`), never two equivalent CTAs.
- For risk states, always include numeric deficit and minimum required.

### Collapsed strip

`BudgetHealthCollapsedStrip` is a separate component with strict density rules:

1. One-line status copy (max 20-24 chars before truncation).
2. CTA label is always one word.
3. Risk count (`N at risk`) is optional and shown only when width permits (uses `ViewThatFits`).
4. No long-form helper text in collapsed mode.

Collapsed CTA vocabulary: `Set`, `Edit`, `Apply`, `Review`, `Fix`, `Refresh`.

---

## Visual and layout rules

### Surface treatment

The card uses one shared container surface across all states:

- **Primary surface**: `.regularMaterial`
- **Fallback surface**: `Color(UIColor.secondarySystemGroupedBackground)`
- **Shape**: `RoundedRectangle(cornerRadius: 12)`

State is **not** communicated by full-card background washes. Semantic color is applied only in compact accents: leading accent strip (2-3pt), state icon tint, state badge/pill tint, CTA tint.

### Color token mapping

All colors use app semantic tokens from `AccessibleColors`:

| State | Tone | Token |
|-------|------|-------|
| `noBudget` | neutral | `.secondary` |
| `healthy` | success | `AccessibleColors.success` |
| `notApplied` | info | `AccessibleColors.primaryInteractive` |
| `needsRecalculation` | review warning | `AccessibleColors.warning` |
| `atRisk` | warning | `AccessibleColors.warning` |
| `severeRisk` | danger | `AccessibleColors.error` |
| `staleFX` | caution | `AccessibleColors.warning` |

Background tokens for badges/chips: `AccessibleColors.successBackground`, `warningBackground`, `errorBackground`.

All tokens are adaptive for light/dark mode using trait-aware dynamic colors. Dark mode variants preserve contrast on `.regularMaterial`.

### Component color usage rules

1. Card container color is fixed across all states.
2. Title/primary numeric text: `.primary`; supporting text: `.secondary`.
3. State icon + accent strip use the state token.
4. For risk states, primary CTA may be tinted with the state token; for non-risk states, use `AccessibleColors.primaryInteractive`.
5. Single semantic tone per state (no token mixing except disabled/loading).

### Typography hierarchy

| Element | Style | Notes |
|---------|-------|-------|
| Title row (`Monthly Budget`) | `.caption` + `.foregroundStyle(.secondary)` | Lightweight metadata tone |
| Primary number | `.title3` + `.fontWeight(.semibold)` | Main monetary anchor |
| Status line | `.subheadline` (+ state icon) | Primary status signal |
| Primary insight | `.caption` + `.fontWeight(.semibold)` + state tint | Shortfall amount legible without overpowering number |
| Primary CTA label | `.subheadline` + `.fontWeight(.semibold)` | With `.buttonStyle(.borderedProminent)` |
| Secondary text | `.caption2` + `.foregroundStyle(.secondary)` | Constraint details and helper context |

Collapsed strip typography:
- Status text: `.caption` or `.caption2` (width-dependent)
- Amount or key signal: `.subheadline` + `.semibold`
- CTA label: `.caption` + `.semibold`

### Border and stroke behavior

Non-binary strokes avoid visual jumps between states:

1. Baseline stroke in all states: `RoundedRectangle(cornerRadius: 12).stroke(Color(UIColor.separator).opacity(0.55), lineWidth: 1)`
2. Semantic accent stroke layered for warning/error states:
   - Warning-like: `AccessibleColors.warning.opacity(0.35)`
   - Severe risk: `AccessibleColors.error.opacity(0.4)`
3. Stroke color/opacity changes are animated: `.animation(.easeInOut(duration: 0.2), value: state)`
4. No `0pt` to `1pt` line width toggles.

### Dark mode badge/chip backgrounds

Status badge/chip backgrounds use stronger opacity in dark mode (target 0.15-0.20 range) or a neutral container base plus semantic tint overlay. 0.10 semantic fills are insufficient for critical status chips in dark mode.

### Scroll collapse thresholds

Normalized progress: `progress = clamp(-scrollOffset / collapseDistance, 0...1)`

Tuning values:
- `collapseDistance = 160`
- Strip enter threshold: `progress >= 0.80`
- Strip exit threshold: `progress <= 0.70` (hysteresis to prevent flicker)

Transition phases:
- Card content fades/scales in `0.0...0.75`
- Strip fades in `0.75...0.90`
- No hard swap at a single value
- Collapsed strip has higher `zIndex` during transition
- Card hit-testing is disabled once mostly collapsed

### Layout constraints (iPhone compact)

- Max expanded card height target: 160-190pt
- Collapsed strip height target: 48-56pt
- At least one full goal row visible on iPhone 15 with default text size
- Card spacing: 8pt outer, 6-8pt internal vertical rhythm, 40pt min CTA height

### Small-screen and Dynamic Type fallback order

If content overflows:
1. Collapse/remove focus-goal secondary line first
2. Primary insight wraps to max 2 lines, then truncates
3. Status line stays single-line with icon
4. FX conversion context moves into disclosure ("Rates details")
5. Primary number + primary CTA always visible
6. Card may grow above 190pt for accessibility

---

## Accessibility

### VoiceOver grouping

The card is exposed as one combined accessibility element:

```swift
.accessibilityElement(children: .combine)
.accessibilityLabel("Monthly Budget, \(state.accessibilityDescription)")
.accessibilityValue(state.accessibilityValueText)
.accessibilityHint("Double tap to \(primaryCTALabel)")
```

Requirements:
- No fragmented per-subview announcements
- Same reading model in collapsed strip
- CTA remains separately focusable when needed for direct action

### Reduce Motion

The collapse/expand transition respects `@Environment(\.accessibilityReduceMotion)`:
- Reduce Motion ON: snap between expanded and collapsed states (no interpolation)
- Reduce Motion OFF: use tuned transition from scroll collapse thresholds

### Dynamic Type degradation

At large accessibility sizes, preserve functional hierarchy:
1. Secondary text hides first
2. Primary insight wraps to max 2 lines, then truncates
3. Status line stays single-line with icon
4. Primary number and primary CTA always visible

Additional rules:
- Minimum touch target: 44x44
- Color is never the sole status signal (always pair icon/text/tone)

---

## Motion and haptics

### State change transitions

When state changes (e.g. `severeRisk` -> `healthy`):
- `withAnimation(.easeInOut(duration: 0.35))` for state container updates
- `.contentTransition(.numericText())` for shortfall/amount text changes
- No abrupt color snaps for accent/stroke updates

### Initial appearance

Subtle entrance animation:
- Opacity: `0 -> 1`
- Scale: `0.98 -> 1.0`
- Duration: 0.20-0.25s
- Skipped when Reduce Motion is enabled

### Haptic feedback (iOS)

Uses `HapticManager` for meaningful state transitions only:
- Transition into `healthy` from risk states: `.notification(.success)`
- Transition into `severeRisk`: `.notification(.warning)`
- Neutral edits (`healthy` -> `notApplied`): no haptic

Haptics are state-transition driven, not triggered on every re-render.

---

## Fiat and crypto constraints

Because users can plan with both fiat and crypto:

- **Never imply addresses for fiat assets** (fiat has no blockchain address).
- Always show: budget currency, display currency basis, FX rate freshness (`as of HH:mm`).
- If conversion data is stale/missing:
  - Downgrade confidence to `staleFX` state
  - Block misleading "all good" messaging
  - Allow fixing path (`Refresh Rates`) before save/apply

For mixed currency risk copy: "Short by US$X (converted from EUR/BTC holdings at current rates)."

---

## Telemetry

### Events

- `budget_health_card_impression` (state, tab, scroll_context)
- `budget_health_primary_cta_tap` (state, action)
- `budget_health_edit_tap`
- `budget_health_state_changed` (from_state, to_state, reason)
- `budget_health_collapsed_strip_tap` (state, action)

### KPIs

- Decrease time to first risk-fixing action
- Increase percentage of sessions where `atRisk` -> `healthy` in same session
- Reduce scroll depth before first goal edit in at-risk state

---

## API reference

### BudgetHealthState

**Location**: `ios/CryptoSavingsTracker/Views/Planning/BudgetSummaryCard.swift`

```swift
enum BudgetHealthState: Equatable {
    case noBudget
    case healthy
    case notApplied
    case needsRecalculation
    case atRisk(shortfall: Double, goalsAtRisk: Int)
    case severeRisk(shortfall: Double, goalsAtRisk: Int)
    case staleFX(lastUpdated: Date?, affectedCurrencies: [String])
}
```

Convenience properties:
- `isRiskState` - true for `atRisk` and `severeRisk`
- `isSevereRisk` - true for `severeRisk` only
- `accessibilityDescription` - VoiceOver label text
- `accessibilityValueText` - VoiceOver value text

### BudgetHealthCard

**Location**: `ios/CryptoSavingsTracker/Views/Planning/BudgetSummaryCard.swift`

```swift
struct BudgetHealthCard: View {
    let state: BudgetHealthState
    let budgetAmount: Double?
    let budgetCurrency: String
    let minimumRequired: Double?
    let nextConstrainedGoal: String?
    let nextDeadline: Date?
    let conversionContext: String?
    let onPrimaryAction: () -> Void
    let onEdit: () -> Void
}
```

### BudgetHealthCollapsedStrip

**Location**: `ios/CryptoSavingsTracker/Views/Planning/BudgetSummaryCard.swift`

Compact strip variant shown when the card is scroll-collapsed. Uses `ViewThatFits` for responsive width handling with one-word CTA labels.

### State derivation

**Location**: `ios/CryptoSavingsTracker/ViewModels/MonthlyPlanningViewModel.swift`

The `budgetHealthState` computed property resolves state using the precedence algorithm described above. Dependencies:

| Property | Purpose |
|----------|---------|
| `hasBudget` | Guard for `noBudget` |
| `budgetHasStaleRates` | Triggers `staleFX` |
| `budgetFeasibility` | Risk calculation from `BudgetCalculatorService` |
| `budgetAmount` | Shortfall computation |
| `isBudgetAppliedForCurrentMonth` | Triggers `notApplied` |
| `showBudgetRecalculationPrompt` | Triggers `needsRecalculation` |

---

## File locations

| Component | Path |
|-----------|------|
| BudgetHealthState, BudgetHealthCard, BudgetHealthCollapsedStrip | `ios/CryptoSavingsTracker/Views/Planning/BudgetSummaryCard.swift` |
| State derivation (`budgetHealthState`) | `ios/CryptoSavingsTracker/ViewModels/MonthlyPlanningViewModel.swift` |
| Integration into planning view | `ios/CryptoSavingsTracker/Views/Planning/PlanningView.swift` |
| Stale draft banner (visual alignment) | `ios/CryptoSavingsTracker/Views/Planning/StaleDraftBanner.swift` |
| Color tokens | `ios/CryptoSavingsTracker/Utilities/AccessibleColors.swift` |
| Haptic feedback | `ios/CryptoSavingsTracker/Utilities/HapticManager.swift` |
| UI tests | `ios/CryptoSavingsTrackerUITests/MonthlyPlanningUITests.swift` |

### Accessibility identifiers

- `budgetSummaryCard` - expanded card
- `budgetEntryCard` - no-budget state card
- `budgetHealthCollapsedStrip` - collapsed strip
- `budgetSummaryStatusRow`, `budgetSummaryShortfallText`, `budgetSummaryFXDisclosure` - content elements
- `setBudgetButton`, `budgetSummaryFixButton`, `applyBudgetButton` - CTA buttons

---

## Related documentation

- [Monthly Planning](MONTHLY_PLANNING.md) - Monthly planning architecture and execution flow
- [Budget Calculator](BUDGET_CALCULATOR.md) - Budget calculator behavior and feasibility rules
- [Component Registry](COMPONENT_REGISTRY.md) - Shared component inventory for UI reuse

---

*Last updated: 2026-03-01*
