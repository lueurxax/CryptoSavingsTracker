# Monthly Planning Budget Health Widget Proposal

> Consolidate "Budget Needs Attention" and "Monthly Budget" into one high-signal widget to free vertical space and keep risk actions obvious.

| Metadata | Value |
|----------|-------|
| Status | ✅ Implemented |
| Last Updated | 2026-03-01 |
| Platform | iOS |
| Audience | Product, Developers, QA |

---

## 1) Executive Summary

The current Monthly Planning header uses two stacked budget blocks:

1. `Budget Needs Attention` (notice-style warning)
2. `Monthly Budget` (budget summary card with CTA)

They communicate almost the same thing, consume too much vertical space, and reduce the usable area for the goals list.  
Proposal: replace both with one **Budget Health Card** that adapts by state (`noBudget`, `healthy`, `notApplied`, `needsRecalculation`, `atRisk`, `severeRisk`, `staleFX`).

Expected impact:
- More visible goals above the fold on compact iPhones.
- Less duplicated messaging.
- Faster path from risk detection to corrective action.

---

## 2) Problem Statement

### Current UX issues

- **Duplicate signal**: user sees warning twice before seeing first goal row.
- **Low working area**: list under `Goals / Adjust / Stats` is compressed in high-risk scenarios.
- **Decision fatigue**: multiple CTAs with overlapping intent ("Review Budget" and "Fix Budget Shortfall").
- **Inconsistent hierarchy**: severity is distributed across two cards instead of one primary decision surface.

### Product risk

- Users with many goals (most important planning case) spend more time scrolling chrome than editing goals.
- Important correction flows become slower in exactly the critical state (`monthly budget at risk`).

---

## 3) Product Goals and Non-Goals

### Goals

- Show one clear budget status per month.
- Keep risk + corrective CTA visible and actionable.
- Reclaim vertical space for planning list interactions.
- Support mixed fiat/crypto planning with explicit conversion context.

### Non-Goals

- Redesigning full planning tabs (`Goals`, `Adjust`, `Stats`).
- Changing budget calculator algorithm itself.
- Replacing execution tracking UI.

---

## 4) Proposed Information Architecture

### Header composition (compact iOS)

1. Sticky segmented control (`Goals / Adjust / Stats`)
2. **Budget Health Card** (single card, stateful)
3. KPI strip (`Monthly Total / Goals / Next Due`) - compact
4. Goal list / tab content

### Scroll behavior

- In expanded state, full Budget Health Card is visible.
- After scroll threshold, card collapses into compact strip:
  - state-specific status copy (see 5.2 and 5.2.1)
  - optional compact risk count for risk states when width allows
  - single-word state-specific CTA (`Set`, `Edit`, `Apply`, `Review`, `Fix`, `Refresh`)

This keeps signal persistent without reintroducing two full cards.

---

## 5) Budget Health Card Specification

### 5.1 Card anatomy

1. **Title row**: `Monthly Budget` + trailing action (`Edit`).
2. **Primary number**: budget amount in budget currency.
3. **Status line**: icon + short state text (`18 goals at risk`, `All deadlines achievable`).
4. **Primary insight**: one sentence explaining impact (`Short by US$4,399 this month`).
5. **Primary CTA**: one button only.
6. **Secondary text**: next constrained goal and minimum required amount (when applicable).

### 5.2 State matrix

| State | Trigger | Visual Tone | Primary CTA | Secondary Info | Collapsed Strip |
|------|---------|-------------|-------------|----------------|-----------------|
| `noBudget` | monthlyBudget is nil | neutral | `Set Budget` | "Set a monthly amount to optimize contributions." | "No budget set" + `Set` |
| `healthy` | feasible and applied | success | `Edit` | "All deadlines achievable." | "On track" + `Edit` |
| `notApplied` | budget exists, not applied to current month | info | `Apply Budget` | "Budget saved, not applied this month." | "Budget not applied" + `Apply` |
| `needsRecalculation` | budget exists, applied month/signature changed after goal/month update | warning | `Recalculate` | "Your goals or month changed. Recalculate allocations." | "Needs review" + `Review` |
| `atRisk` | infeasible, shortfall > 0 and <= 25% of min required | warning | `Fix Budget Shortfall` | shortfall amount + minimum required + next constraining goal | "Short by X" + `Fix` |
| `severeRisk` | infeasible and severe threshold met (see 5.5) | danger | `Fix Budget Shortfall` | stronger risk text + minimum required + next constraining goal | "Short by X" + `Fix` |
| `staleFX` | rates too old / missing conversion for active goals and feasibility is not trustworthy | warning-neutral | `Refresh Rates` | timestamp + affected currencies | "Rates outdated" + `Refresh` |

### 5.2.1 Collapsed strip contract

Collapsed strip is a separate interaction surface with strict density rules:

1. One-line status copy (max 20-24 chars before truncation).
2. CTA label is always one word.
3. Risk count (`N at risk`) is optional and only shown when width permits.
4. No long-form helper text in collapsed mode.

Collapsed CTA vocabulary (v1):
- `Set`, `Edit`, `Apply`, `Review`, `Fix`, `Refresh`

### 5.3 State precedence (deterministic)

Use this resolution algorithm to avoid ambiguous rendering when multiple conditions are true:

Step 1 (global guard):
1. If `monthlyBudget == nil` -> `noBudget`.

Step 2 (budget-present states, highest first):
1. `staleFX` (**only when feasibility cannot be trusted or computed**)
2. `severeRisk`
3. `atRisk`
4. `notApplied`
5. `needsRecalculation`
6. `healthy`

Examples:
- `atRisk` + `staleFX` -> `staleFX` (confidence problem must be resolved first).
- `notApplied` + `needsRecalculation` -> `notApplied` (apply action has priority).
- `severeRisk` + `notApplied` -> `severeRisk`.

### 5.4 Copy principles

- One primary sentence, no duplicate warnings.
- Action-oriented labels (`Fix`, `Apply`, `Refresh`), never two equivalent CTAs.
- For risk states, always include numeric deficit and minimum required.

### 5.5 Severity thresholds (v1)

Use this initial rule:
- `severeRisk` when shortfall ratio is > 25% **or** affected goals ratio is >= 40%.
- `atRisk` otherwise when shortfall > 0.

Notes:
- This keeps severe classification sensitive to broad goal impact, not only raw deficit percent.
- Thresholds should be re-tuned using production telemetry after rollout.

---

## 6) Fiat + Crypto UX Constraints (must-have)

Because users can plan with both fiat and crypto:

- **Never imply addresses for fiat assets** in this widget (fiat has no blockchain address).
- Always show:
  - budget currency,
  - display currency basis,
  - FX rate freshness (`as of HH:mm`).
- If conversion data is stale/missing:
  - downgrade confidence (state `staleFX`),
  - block misleading "all good" messaging,
  - allow fixing path (`Refresh Rates`) before save/apply.

For mixed currency risk copy:
- "Short by US$X (converted from EUR/BTC holdings at current rates)."

---

## 7) Interaction Design

### Primary flows

1. **At risk user**
   - Sees one budget card with warning accents (not full-card tint).
   - Taps `Fix Budget Shortfall`.
   - Lands in the existing Budget Plan sheet (v1 behavior).

2. **Healthy user**
   - Sees clean summary + optional `Edit`.
   - No warning noise.

3. **Stale FX user**
   - Sees conversion warning state.
   - Refreshes rates, then state recomputes.

### Secondary actions

- Keep `Edit` in top-right text button.
- No dismiss action in v1. Risk messaging persists until state is resolved.

### Budget CTA destination (scope)

- V1 behavior: primary budget CTA opens the existing Budget Plan sheet (`showingBudgetSheet = true`).
- V2 follow-up: optional contextual pre-highlight inside the sheet (shortfall-focused mode).

---

## 8) Visual and Layout Rules (iPhone compact)

- Max expanded card height target: **160-190pt** (target, not hard cap).
- Collapsed strip height target: **48-56pt**.
- Always keep at least one full goal row visible with default text size on iPhone 15.
- Card spacing:
  - top/bottom outer spacing: 8pt,
  - internal vertical rhythm: 6-8pt,
  - CTA min height: 40pt.

### 8.1 Surface treatment (single visual language)

Budget Health Card must use one shared container surface across all states:

- **Primary surface**: `.regularMaterial`
- **Fallback surface** (when material is undesirable): `Color(UIColor.secondarySystemGroupedBackground)`
- **Shape**: `RoundedRectangle(cornerRadius: 12)`

`.regularMaterial` is adaptive and must be validated in both light and dark modes.

State should **not** be communicated by full-card background washes.

Use semantic color only in compact accents:
- leading accent strip (2-3pt),
- state icon tint,
- state badge/pill tint,
- CTA tint (when needed).

### 8.2 Color token mapping

Use app semantic tokens from `AccessibleColors` instead of raw `Color.green/orange/red`.

| State | Tone | Token |
|------|------|-------|
| `noBudget` | neutral | system secondary (`.secondary`) |
| `healthy` | success | `AccessibleColors.success` |
| `notApplied` | info | `AccessibleColors.primaryInteractive` |
| `needsRecalculation` | review warning | `AccessibleColors.warning` |
| `atRisk` | warning | `AccessibleColors.warning` |
| `severeRisk` | danger | `AccessibleColors.error` |
| `staleFX` | caution | `AccessibleColors.warning` |

Background helpers for badges/chips:
- success: `AccessibleColors.successBackground`
- warning: `AccessibleColors.warningBackground`
- error: `AccessibleColors.errorBackground`

### 8.2.1 Adaptive token prerequisite (dark mode)

Before shipping the unified widget, status tokens used by this card must be adaptive for light/dark mode:

- `AccessibleColors.success`
- `AccessibleColors.warning`
- `AccessibleColors.error`
- `AccessibleColors.successBackground`
- `AccessibleColors.warningBackground`
- `AccessibleColors.errorBackground`

Requirement:
- these tokens should resolve through trait-aware dynamic colors, not fixed RGB-only values.
- dark mode variants must preserve contrast on `.regularMaterial`.

### 8.3 Component color usage rules

1. Card container color is fixed (from 8.1) for all states.
2. Title/primary numeric text remains `.primary`; supporting text remains `.secondary`.
3. State icon + accent strip use state token from 8.2.
4. For risk states, primary CTA may be tinted with the state token; for non-risk states, use `AccessibleColors.primaryInteractive`.
5. Avoid token mixing within one state (single semantic tone per state, except disabled/loading).

### 8.4 Typography hierarchy

| Element | Recommended style | Notes |
|--------|-------------------|-------|
| Title row (`Monthly Budget`) | `.caption` + `.foregroundStyle(.secondary)` | Keeps metadata tone lightweight |
| Primary number | `.title3` + `.fontWeight(.semibold)` | Main monetary anchor |
| Status line | `.subheadline` (+ state icon) | Promoted from caption; this is the primary status signal |
| Primary insight | `.caption` + `.fontWeight(.semibold)` + state tint | Keeps shortfall amount legible without overpowering number |
| Primary CTA label | `.subheadline` + `.fontWeight(.semibold)` | With `.buttonStyle(.borderedProminent)` |
| Secondary text | `.caption2` + `.foregroundStyle(.secondary)` | Constraint details and helper context |

Collapsed strip typography:
- status text: `.caption` or `.caption2` (depending on available width),
- amount or key signal: `.subheadline` + `.semibold`,
- CTA label: `.caption` + `.semibold`.

### 8.5 Border and stroke behavior

To avoid binary visual jumps between states:

1. Keep a baseline stroke in all states:
   - `RoundedRectangle(cornerRadius: 12).stroke(Color(UIColor.separator).opacity(0.55), lineWidth: 1)`
   - fallback: `.primary.opacity(0.12)` when `separator` is unsuitable
2. For warning/error states, layer a semantic accent stroke:
   - warning-like states: `AccessibleColors.warning.opacity(0.35)`
   - severe risk: `AccessibleColors.error.opacity(0.4)`
3. Animate stroke color/opacity changes, not line width toggles:
   - `.animation(.easeInOut(duration: 0.2), value: state)`
4. Do not switch between `0pt` and `1pt` based on feasibility.

### 8.5.1 Dark mode badge/chip backgrounds

For dark mode readability:

- status badge/chip backgrounds should use stronger opacity than light mode (target 0.15-0.20 range),
  or a neutral container base (`Color(UIColor.secondarySystemGroupedBackground)`) plus semantic tint overlay.
- avoid 0.10 semantic fills as the only background in dark mode for critical status chips.

### 8.6 Small-screen and Dynamic Type fallback order

Validate layout on smallest supported compact viewport and larger Dynamic Type categories.

If content would overflow:
1. Collapse/remove focus-goal secondary line first.
2. Primary insight wraps to max 2 lines, then truncates.
3. Keep status line single-line with icon.
4. Move FX conversion context into disclosure ("Rates details").
5. Keep primary number + primary CTA always visible.
6. Allow card to grow above 190pt when required for accessibility.

Dynamic Type behavior must stay aligned with Section 9.3.

### 8.7 Scroll collapse thresholds and transition tuning

To prevent visual overlap between expanded card (160-190pt) and collapsed strip:

1. Use normalized progress:
   - `progress = clamp(-scrollOffset / collapseDistance, 0...1)`
2. Recommended initial tuning for unified widget:
   - `collapseDistance = 160` (vs current 120)
   - strip enter threshold: `progress >= 0.80`
   - strip exit threshold: `progress <= 0.70` (hysteresis to prevent flicker)
3. Transition phases:
   - card content fades/scales mostly in `0.0...0.75`
   - strip fades in `0.75...0.90`
   - no hard swap at a single value
4. Layering:
   - collapsed strip should be above card during transition (`zIndex` higher than card)
   - card hit-testing should be disabled once mostly collapsed to avoid accidental taps

Equivalent scroll distance with `collapseDistance = 160`:
- strip appears around 128pt upward scroll (enter),
- strip hides around 112pt downward scroll (exit).

### 8.8 Dark mode validation rules

Required checks:

1. Surface readability on `.regularMaterial` in dark mode.
2. Accent and status token contrast on dark surfaces.
3. Baseline stroke visibility in dark mode (no near-invisible borders).
4. Badge/chip background legibility with semantic tint.

---

## 9) Accessibility Requirements

### 9.1 VoiceOver grouping and reading order

Budget Health Card should be exposed as one combined accessibility element in expanded and collapsed modes.

Required pattern:

```swift
.accessibilityElement(children: .combine)
.accessibilityLabel("Monthly Budget, \(state.accessibilityDescription)")
.accessibilityValue(state.accessibilityValueText)
.accessibilityHint("Double tap to \(primaryCTALabel)")
```

Requirements:
- Avoid noisy per-subview announcements for every text/icon/button fragment.
- Keep the same reading model in collapsed strip.
- CTA must remain separately focusable when needed for direct action.

### 9.2 Reduce Motion behavior

The collapse/expand transition must respect `@Environment(\.accessibilityReduceMotion)`.

- If reduce motion is ON: no animated collapse interpolation; snap between expanded and collapsed states.
- If reduce motion is OFF: use the tuned transition behavior from Section 8.7.
- Do not rely on implicit animations only; gate transitions with an explicit reduce-motion check.

### 9.3 Dynamic Type degradation sequence

At large accessibility sizes, preserve functional hierarchy in this order:

1. Secondary text hides first.
2. Primary insight wraps to max 2 lines, then truncates.
3. Status line stays single-line with icon.
4. Primary number and primary CTA remain visible at all times.

Additional rules:
- Minimum touch target: 44x44.
- Color is never the sole status signal (always pair icon/text/tone).

---

## 10) Motion, transitions, and haptics

### 10.1 State change transitions

When state changes (for example `severeRisk -> healthy`), transition content and tone smoothly:

- Use `withAnimation(.easeInOut(duration: 0.35))` for state container updates.
- Use `.contentTransition(.numericText())` for shortfall/amount text changes where supported.
- Avoid abrupt color snaps for accent/stroke updates.

### 10.2 Initial appearance

On first appearance, use subtle entrance:
- opacity: `0 -> 1`
- scale: `0.98 -> 1.0`
- duration: 0.20-0.25s

Skip this entrance when reduce motion is enabled.

### 10.3 Haptic feedback mapping (iOS)

Use existing `HapticManager` for meaningful state transitions:

- transition into `healthy` from risk states: `HapticManager.shared.notification(.success)`
- transition into `severeRisk`: `HapticManager.shared.notification(.warning)`
- optional for neutral edits (`healthy -> notApplied`): no notification haptic

Haptics are state-transition driven, not triggered on every rerender.

---

## 11) Telemetry and Success Metrics

Track events:

- `budget_health_card_impression` (state, tab, scroll_context)
- `budget_health_primary_cta_tap` (state, action)
- `budget_health_edit_tap`
- `budget_health_state_changed` (from_state, to_state, reason)
- `budget_health_collapsed_strip_tap` (state, action)

If dismiss is introduced in a later version:
- `budget_health_card_dismissed` (state, scope=session|month)

KPIs:
- Decrease time to first risk-fixing action.
- Increase percentage of sessions where `atRisk -> healthy` in same session.
- Reduce scroll depth before first goal edit in at-risk state.

---

## 12) Implementation Blueprint (iOS)

### Component strategy

- Evolve `BudgetSummaryCard` into `BudgetHealthCard`.
- Remove top-level `BudgetNoticesView` from `PlanningView`.
- Keep one source of truth for state from `MonthlyPlanningViewModel.budgetFeasibility` + FX freshness.
- Normalize visuals to one container surface and semantic accent tokens (see Section 8).
- Apply unified typography hierarchy and non-binary stroke transitions (see Sections 8.4 and 8.5).
- Enforce accessibility grouping and reduce-motion behavior (Section 9).
- Use explicit motion/haptic specs (Section 10).
- Align adjacent `StaleDraftBanner` styling when shown together with Budget Health Card.

### 12.1 Design debt cleanup guardrails

The new widget implementation must fix existing UI debt in touched files:

1. Replace raw status colors (`Color.green`, `Color.orange`, `Color.red`) with `AccessibleColors` tokens.
2. Use `.clipShape(RoundedRectangle(cornerRadius: 12))` for card shaping; do not introduce `.cornerRadius()` in new widget code.
3. Prefer `.foregroundStyle(...)` over `.foregroundColor(...)` in the new widget implementation.
4. Define card surface through a shared constant/token (`BudgetHealthCardStyle.surface`) rather than ad-hoc per-state background values.
5. Accessibility grouping must remove fragmented VoiceOver announcements from replaced budget widgets.
6. Adaptive dark-mode status tokens are required before enabling the feature flag.

### 12.2 Scope of cleanup

To avoid "boil the ocean" refactors, styling API cleanup is scoped to files touched by this initiative.

- Required: touched budget/planning files are internally consistent with new rules.
- Out of scope for this phase: mass migration across all planning files.

### 12.3 Module implementation notes

- Planning module currently has minimal haptic usage; this feature introduces the first explicit planning-state haptic transitions.
- Planning module currently has limited accessibility grouping; this feature sets the baseline contract for grouped state cards.
- Legacy notice components being retired contain raw color debt; no additional cleanup is needed outside the replacement path.

### 12.4 Deferred technical debt (tracked, not in this scope)

- Existing `.cornerRadius()` usage in sibling planning screens outside touched files.
- Broad `.foregroundColor(...)` to `.foregroundStyle(...)` migration beyond touched files.

### Suggested API

```swift
enum BudgetHealthState {
    case noBudget
    case healthy
    case notApplied
    case needsRecalculation
    case atRisk(shortfall: Double, goalsAtRisk: Int)
    case severeRisk(shortfall: Double, goalsAtRisk: Int)
    case staleFX(lastUpdated: Date?, affectedCurrencies: [String])
}
```

```swift
struct BudgetHealthCard: View {
    let state: BudgetHealthState
    let budgetAmount: Double?
    let budgetCurrency: String
    let minimumRequired: Double?
    let nextConstrainedGoal: String?
    let nextDeadline: Date? // Displayed in secondary text when present
    let onPrimaryAction: () -> Void
    let onEdit: () -> Void
}
```

### Files expected to change

- `ios/CryptoSavingsTracker/Views/Planning/PlanningView.swift`
- `ios/CryptoSavingsTracker/Views/Planning/BudgetSummaryCard.swift` (rename or repurpose)
- `ios/CryptoSavingsTracker/Views/Planning/BudgetNoticesView.swift` (legacy component retired)
- `ios/CryptoSavingsTracker/ViewModels/MonthlyPlanningViewModel.swift` (state derivation for unified card)
- `ios/CryptoSavingsTracker/Views/Planning/StaleDraftBanner.swift` (visual alignment with unified card when stacked)
- `ios/CryptoSavingsTracker/Utilities/AccessibleColors.swift` (adaptive status/background token updates)
- UI tests in:
  - `ios/CryptoSavingsTrackerUITests/MonthlyPlanningUITests.swift`

---

## 13) QA Acceptance Criteria

1. In at-risk state, only one budget widget is visible (no duplicated warning card).
2. Widget always shows clear primary CTA.
3. With 15+ goals on iPhone 15, first list row remains visible without extra scroll.
4. Mixed-currency goals show conversion context; stale FX is not silently treated as healthy.
5. VoiceOver reads combined budget state in one element (label/value/hint) without noisy fragmented reading.
6. With Reduce Motion enabled, collapse/expand snaps without animated transition.
7. At large accessibility text sizes, degradation sequence follows Section 9.3.
8. Existing budget edit/apply flows remain functional.
9. New card uses semantic color tokens and fixed surface treatment (no full-card state washes).
10. Stroke behavior remains non-binary and visually stable across state transitions.
11. Dark mode visual validation passes for surface, stroke, token contrast, and chip readability.
12. Collapsed strip shows one-word CTA labels and state-correct copy per Section 5.2.
13. When stale draft banner is visible, spacing/corner/surface style remains visually coherent with the new card.

---

## 14) Rollout Plan

1. Ship unified card as the default Monthly Planning budget surface (legacy feature flag removed).
2. Add one-time migration handling for legacy notice dismissal state (`hasSeenBudgetMigrationNotice`); do not resurface dismissed migration notices as new alerts.
3. Run internal dogfood for at least one full planning cycle.
4. Validate telemetry and UX screenshots for:
   - light mode and dark mode variants for each state below,
   - no budget,
   - healthy,
   - needs recalculation,
   - not applied,
   - at risk,
   - severe risk,
   - stale FX.
5. Validate accessibility and motion behavior:
   - VoiceOver combined readout,
   - no fragmented VoiceOver announcement regression from retired budget widgets,
   - Reduce Motion snap behavior,
   - Dynamic Type AX-size degradation.
6. Remove old notice card after validation.

---

## 15) Product decisions (v1)

1. `notApplied` remains a separate state (distinct user intent and CTA: `Apply Budget`).
2. No dismiss for risk messaging in v1.
3. Risk severity starts with combined threshold (shortfall ratio + affected goals ratio), then tuned with telemetry.
4. One visual language: fixed card surface + semantic accent tokens; no state-wide background washes.
5. Collapse/expand must respect Reduce Motion and accessibility-first degradation rules.
6. Adaptive dark-mode status/background tokens are required prior to feature-flag rollout.
7. API cleanup scope is limited to touched files in this initiative.

---

## 16) Related documentation

- [MONTHLY_PLANNING.md](MONTHLY_PLANNING.md) - Monthly planning architecture and execution flow.
- [BUDGET_CALCULATOR.md](BUDGET_CALCULATOR.md) - Budget calculator behavior and feasibility rules.
- [COMPONENT_REGISTRY.md](COMPONENT_REGISTRY.md) - Shared component inventory for UI reuse.

---

*Last updated: 2026-03-01*
