# Commit Dock Scroll Collapse Proposal

> Compress the "Ready to commit to this plan?" bottom dock into a compact floating button when the user scrolls into the goal list, reclaiming ~90pt of vertical space for planning interactions.

| Metadata | Value |
|----------|-------|
| Status | Reviewed |
| Last Updated | 2026-03-01 |
| Review Pass | UI + UX + Architecture (2026-03-01) |
| Platform | iOS (compact) |
| Audience | Product, Developers, QA |
| Depends on | Budget Health Widget (v2.2) |

---

## 1) Executive Summary

The Monthly Planning screen currently has two fixed chrome regions that consume vertical space:

1. **Budget Health Card** (top, ~160-190pt) — already collapses on scroll (v2.2).
2. **Commit Dock** (bottom, ~130-145pt) — always fully expanded.

On an iPhone 15 with default text size, the combined chrome is ~300-335pt, leaving less than half the viewport for the goal list. Users with many goals (the most important planning case) spend more time scrolling chrome than editing goals.

Proposal: apply the same scroll-collapse pattern already proven on the Budget Health Card to the bottom Commit Dock. When the user scrolls down into the goal list, the dock collapses into a compact floating action button (FAB). When they scroll back to the top, it expands back to the full dock.

Expected impact:
- ~90pt of vertical space reclaimed when scrolled.
- First goal row visible without scrolling on compact iPhones with 10+ goals.
- Commit action remains accessible at all scroll depths.
- Consistent interaction pattern across both chrome regions (top and bottom collapse together).

---

## 2) Problem Statement

### Current UX issues

- **Excessive bottom chrome**: the full dock (~130-145pt) is permanently pinned via `.safeAreaInset(edge: .bottom)`, reducing the scrollable area for goals.
- **Redundant information at depth**: once the user has read "Ready to commit to this plan?" and the undo explanation, the informational text adds no value while scrolling through goals. Only the action button matters.
- **Asymmetric collapse**: the Budget Health Card at the top collapses on scroll, but the bottom dock stays fully expanded, creating an unbalanced feel.
- **Reduced goal visibility**: on iPhone SE or at large Dynamic Type, the combination of Budget Health Card + Commit Dock can leave room for only 1-2 visible goal rows.

### Product risk

- Users may not realize there are more goals below the fold.
- The commit action occupies screen space disproportionate to its frequency of use (tapped once per month).
- The informational text ("This will lock in your monthly amounts...") is read once but displayed permanently.

---

## 3) Product Goals and Non-Goals

### Goals

- Reclaim vertical space when the user is actively browsing/editing goals.
- Keep the commit action always reachable regardless of scroll position.
- Match the collapse behavior of the Budget Health Card for consistency.
- Respect Reduce Motion and Dynamic Type accessibility requirements.

### Non-Goals

- Changing the commit confirmation flow or alert text.
- Redesigning the execution tracking view.
- Modifying the state banner at the top of the container.
- Adding new commit-related features (e.g., partial commit, schedule commit).

---

## 4) Current Widget Anatomy

### Location and positioning

- **File**: `MonthlyPlanningContainer.swift`, `startTrackingDock` property.
- **Attachment**: `.safeAreaInset(edge: .bottom, spacing: 0)` on `PlanningView`.
- **Visibility**: only when `!isExecuting` (planning mode, not execution mode).

### Content breakdown

| Element | Font | Height contribution |
|---------|------|---------------------|
| Divider | — | ~1pt |
| Icon + "Ready to commit to this plan?" | `.headline` + `.title3` icon | ~28pt |
| Description (2 lines) | `.caption` | ~30pt |
| "Lock Plan & Start Tracking" button | `.borderedProminent`, `.regular` | ~44pt |
| Vertical padding | 12pt top + 12pt bottom | 24pt |
| Internal spacing (3 gaps x 8pt) | — | 24pt |
| **Total** | | **~130-145pt** |

### Current design debt

- Icon uses raw `Color.green` instead of `AccessibleColors.success`.
- Description text uses deprecated `.foregroundColor(.secondary)` instead of `.foregroundStyle(.secondary)`.
- No `.accessibilityElement(children: .combine)` grouping for VoiceOver.

### State dependencies

- `showStartTrackingConfirmation: Bool` — triggers the confirmation alert.
- `isExecuting: Bool` — hides the dock entirely during execution mode.

---

## 5) Proposed Behavior

### 5.1 Two modes

| Mode | Trigger | Content | Height |
|------|---------|---------|--------|
| **Expanded** (default) | Scroll near top (progress < exit threshold) | Full dock: icon, headline, description, full-width button | ~130-145pt |
| **Collapsed** (FAB) | Scroll past enter threshold | Compact pill button: icon + "Lock Plan" label, trailing-aligned | ~56pt |

### 5.2 Scroll collapse contract

The dock reads the same normalized scroll progress already computed by the Budget Health Card in `iOSCompactPlanningView`:

```
headerCollapseProgress = clamp(-tabScrollOffset / collapseDistance, 0...1)
```

Where `collapseDistance = 160` (existing constant in PlanningView). The dock does **not** define its own collapse distance — it shares the single progress value and uses different thresholds to collapse earlier than the Budget Health Card.

Dock collapse thresholds:

| Parameter | Value | Notes |
|-----------|-------|-------|
| Enter threshold | `0.60` | Dock collapses first, before the Budget Health Card (0.80) |
| Exit threshold | `0.45` | Hysteresis gap of 15% to prevent flicker |

Equivalent scroll distances (with `collapseDistance = 160`):
- Dock collapses at ~96pt upward scroll (0.60 x 160).
- Dock re-expands at ~72pt downward scroll (0.45 x 160).
- Budget Health Card collapses at ~128pt (0.80 x 160, existing behavior).

### 5.3 Collapse sequencing with Budget Health Card

When the user scrolls down, the collapse is coordinated through shared progress:

1. **0pt - 96pt scroll**: Commit Dock collapses first (bottom chrome shrinks).
2. **96pt - 128pt scroll**: Budget Health Card collapses (top chrome shrinks).

This ordering prioritizes goal list space from the bottom up, which feels more natural because the user's attention is moving downward into the content.

### 5.4 Transition phases

| Progress range | Dock behavior |
|----------------|---------------|
| 0.00 - 0.30 | Fully expanded, no visual change |
| 0.30 - 0.50 | Description text fades out, headline fades out |
| 0.50 - 0.60 | Dock height animates down, FAB fades in |
| 0.60+ | FAB fully visible, expanded content fully hidden |

When Reduce Motion is enabled: snap between expanded and collapsed at the enter/exit thresholds (no interpolation).

### 5.5 Reset behavior

The dock automatically returns to expanded when:
- **Tab switch**: `onChange(of: selectedTab)` resets `tabScrollOffset` to 0 (existing behavior).
- **Budget sheet dismissal**: `onChange(of: showingBudgetSheet)` resets scroll state (existing behavior).
- **Initial load**: `scrollProgress` starts at 0 (expanded by default).

---

## 6) Collapsed FAB Specification

### 6.1 Anatomy

```
                          [lock.fill icon] Lock Plan
```

- Single horizontal row: SF Symbol + label.
- Trailing-aligned within the `.safeAreaInset` region.
- `.borderedProminent` button style.
- Capsule shape.

### 6.2 Visual treatment

| Property | Value |
|----------|-------|
| Button style | `.borderedProminent` (system accent color) |
| Shape | `Capsule()` via `.clipShape(Capsule())` |
| Shadow | `.shadow(color: .black.opacity(0.15), radius: 6, y: 3)` |
| Internal padding | `.padding(.horizontal, 16)`, `.padding(.vertical, 10)` |
| Alignment | Trailing edge within `.safeAreaInset` container |
| Container padding | 12pt horizontal, 8pt vertical (within the safe area inset view) |
| Icon | `lock.fill` (same as expanded button) |
| Label | "Lock Plan" (shortened from "Lock Plan & Start Tracking") |
| Font | `.subheadline` + `.fontWeight(.semibold)` |

### 6.3 FAB positioning within safe area inset

The FAB is **not** a free-floating overlay. It remains inside the `.safeAreaInset(edge: .bottom)` container, but the container's height shrinks from ~130-145pt to ~56pt. This ensures the scroll content inset adjusts automatically and avoids content overlap.

```swift
// Expanded mode: full VStack content
// Collapsed mode: trailing-aligned capsule button
.safeAreaInset(edge: .bottom, spacing: 0) {
    CommitDock(scrollProgress: planningScrollProgress,
              showConfirmation: $showStartTrackingConfirmation)
}
```

### 6.4 FAB action

Tapping the FAB triggers the same `showStartTrackingConfirmation = true` as the expanded button. The confirmation alert and flow remain unchanged.

### 6.5 FAB entrance/exit animation

- **Entrance** (dock -> FAB): scale from 0.85 to 1.0, opacity 0 to 1, duration 0.2s.
- **Exit** (FAB -> dock): reverse, duration 0.2s.
- Skip animations when Reduce Motion is enabled (instant opacity swap).

---

## 7) Architecture: Bridging Scroll State

### Problem

The scroll offset is tracked inside `iOSCompactPlanningView` (child), but the Commit Dock lives in `MonthlyPlanningContainer` (parent's `.safeAreaInset`). The container has no access to the scroll position.

### Design constraint: minimize render churn

Raw `CGFloat` progress bindings update on every scroll frame (~60-120 Hz), which forces parent recomposition and `.safeAreaInset` relayout on every frame. This is the primary performance risk identified during architecture review.

**Solution**: the child computes the discrete dock phase locally and only propagates a `DockPhase` enum to the parent. The parent sees at most a few state transitions per scroll gesture, not continuous values.

### Propagation chain (discrete state)

```
MonthlyPlanningContainerContent
  @State dockPhase: DockPhase = .expanded
    |
    v  (passes as @Binding)
  PlanningView(dockPhase: $dockPhase)
    |
    v  (passes as @Binding)
  iOSCompactPlanningView(dockPhase: $dockPhase)
    |
    v  (writes discrete phase from scroll tracking)
  headerCollapseProgress → hysteresis → DockPhase
```

```swift
enum DockPhase: Equatable {
    case expanded   // scroll near top (progress < exit threshold)
    case collapsed  // scroll past enter threshold
}
```

1. `iOSCompactPlanningView` continues to compute `headerCollapseProgress` (CGFloat) from scroll offset — this stays local, never leaves the child.
2. Hysteresis logic (enter 0.60 / exit 0.45) converts progress into a `DockPhase` enum.
3. The child writes `dockPhase` only when the phase **changes** (at most a few times per gesture).
4. `MonthlyPlanningContainerContent` owns `@State private var dockPhase: DockPhase = .expanded`.
5. `CommitDock` (in the `.safeAreaInset`) reads `dockPhase` from the container — a discrete value, not a continuous stream.

### Performance contract

| Signal | Frequency | Scope |
|--------|-----------|-------|
| `headerCollapseProgress` (CGFloat) | Every scroll frame | Local to `iOSCompactPlanningView` only |
| `dockPhase` (enum) | On threshold transitions | Propagated to parent via `@Binding` |

Instruments acceptance criterion: no sustained >16ms main-thread spikes during fast scroll.

### Why not PreferenceKey?

PreferenceKeys propagate upward through the view hierarchy, but `.safeAreaInset` content is a sibling branch, not an ancestor. A `@Binding` is simpler and more direct.

### Why not environment?

Environment values propagate downward. The dock phase needs to flow from a child (PlanningView) to a sibling (the dock), which environment doesn't support.

### Platform-specific handling

- **iOS compact**: full collapse behavior using the discrete phase binding.
- **iOS regular / macOS**: `dockPhase` is always `.expanded`; dock remains permanently expanded. The `CommitDock` checks `horizontalSizeClass` and skips collapse logic.

---

## 8) Visual and Layout Rules

### 8.1 Surface treatment

| Mode | Surface |
|------|---------|
| Expanded dock | `.regularMaterial` (already implemented) |
| Collapsed container | `.regularMaterial` (same surface, just shorter) |
| FAB button | `.borderedProminent` (system-provided surface) |
| Divider | Visible only in expanded mode |

### 8.2 Color tokens

| Element | Current | Proposed |
|---------|---------|----------|
| Expanded icon | `Color.green` (raw) | `AccessibleColors.success` (design debt fix) |
| FAB tint | — | `AccentColor` (system default for `.borderedProminent`) |
| Description text | `.foregroundColor(.secondary)` (deprecated) | `.foregroundStyle(.secondary)` |
| Headline | `.headline` (system color) | Unchanged |

### 8.3 Typography

| Element | Expanded | Collapsed |
|---------|----------|-----------|
| Headline | `.headline` | N/A (hidden) |
| Description | `.caption`, 2-line | N/A (hidden) |
| Button label | System `.borderedProminent` default | `.subheadline` + `.semibold` |
| Icon | `.title3` | `.subheadline` |

### 8.4 Safe area and content inset

Critical requirement: the scroll view's bottom content inset must animate smoothly when the dock height changes. Because the dock stays inside `.safeAreaInset`, SwiftUI handles this automatically — the content inset is derived from the inset view's frame.

To avoid a hard snap:
- Animate the dock's height change with `withAnimation(.easeInOut(duration: 0.25))`.
- SwiftUI's layout system will smoothly adjust the scroll content inset.
- Test: verify that goals list does not visually jump during the transition.

### 8.5 Dark mode

- `.regularMaterial` is inherently adaptive (no changes needed for expanded).
- `.borderedProminent` adapts automatically to dark mode.
- FAB shadow: use adaptive opacity (`0.15` light, `0.25` dark) to remain visible on dark material.

---

## 9) Accessibility Requirements

### 9.1 VoiceOver

**New addition**: the current dock has no accessibility grouping. This proposal adds it.

- **Expanded dock**: `.accessibilityElement(children: .combine)` with:
  - Label: `"Ready to commit to this plan. Lock Plan and Start Tracking."`
  - Hint: `"Double tap to start tracking."`
- **Collapsed FAB**: inherits standard button accessibility from `.borderedProminent` with:
  - Label: `"Lock Plan"`
  - Hint: `"Double tap to start tracking."`
- Transition between modes must not cause VoiceOver to lose focus or re-announce unexpectedly.

### 9.2 Reduce Motion

When `@Environment(\.accessibilityReduceMotion)` is true:
- Snap between expanded and collapsed at thresholds (no animated interpolation).
- FAB entrance/exit: instant opacity change, no scale animation.
- Dock height: instant change, no animated transition.

### 9.3 Dynamic Type

At accessibility type sizes:
- Expanded dock: allow description to wrap to 3 lines (upgrade from 2), then truncate.
- Expanded dock: allow height to grow above 145pt (no hard cap).
- FAB label: may truncate at extreme sizes; icon alone (`lock.fill`) is sufficient to convey action.
- FAB: enforce min 44pt height regardless of text size.

### 9.4 Minimum touch targets

- Expanded button: full-width, 44pt minimum height (per HIG).
- Collapsed FAB: `.frame(minHeight: 44)`.

---

## 10) Motion and Haptics

### 10.1 Collapse transition

- Duration: 0.25s ease-in-out for dock height and content opacity changes.
- Content fades are staggered: description fades first (progress 0.30-0.45), then headline (0.40-0.55).
- Use `.animation(.easeInOut(duration: 0.25), value: isCollapsed)` for height changes.

### 10.2 FAB appearance

- Scale: 0.85 -> 1.0 over 0.2s.
- Opacity: 0 -> 1 over 0.2s.
- Shadow fades in alongside opacity.

### 10.3 Haptics

- No haptic on collapse/expand (frequent scroll-driven event, would be annoying).
- Existing system haptic on confirmation alert presentation is sufficient.

---

## 11) Telemetry

Track events through a `CommitDockAnalytics` helper (same pattern as `BudgetHealthAnalytics`).

### Transition-edge dedupe

Collapse/expand events fire **only on `DockPhase` transitions**, not on every scroll frame. Because the hysteresis logic already emits discrete state changes, telemetry naturally dedupes. An additional cooldown prevents rapid oscillation noise:

```swift
/// Minimum interval between collapse/expand events (same session).
private static let transitionCooldown: TimeInterval = 1.0
private static var lastTransitionTimestamp: Date?

static func logPhaseChange(to phase: DockPhase) {
    let now = Date()
    if let last = lastTransitionTimestamp,
       now.timeIntervalSince(last) < transitionCooldown {
        return  // suppress rapid oscillation
    }
    lastTransitionTimestamp = now
    log(phase == .collapsed ? .collapsed : .expanded)
}
```

### Events

| Event | Trigger | Properties |
|-------|---------|-----------|
| `commit_dock_impression` | `onAppear` | `mode: expanded\|collapsed` |
| `commit_dock_collapsed` | Phase transition to `.collapsed` (deduped) | `session_collapse_count` |
| `commit_dock_expanded` | Phase transition to `.expanded` (deduped) | `session_expand_count` |
| `commit_dock_fab_tap` | User taps collapsed FAB | — |
| `commit_dock_full_button_tap` | User taps expanded button | — |

### Bounded event volume

Per-session counters track total collapse/expand transitions. Expected bounds:
- Typical session: 1-3 transitions.
- Edge case (rapid scrolling): capped by 1s cooldown → max ~60 events in a 60s session.

### KPIs

- Percentage of commit actions initiated from collapsed FAB vs expanded dock.
- Whether collapse correlates with longer planning sessions (more goal edits).
- Scroll depth distribution when commit is tapped.
- Event volume per session is bounded and KPI variance is stable across builds.

---

## 12) Implementation Blueprint (iOS)

### Component strategy

1. Add `@State private var dockPhase: DockPhase = .expanded` to `MonthlyPlanningContainerContent`.
2. Pass as `@Binding` to `PlanningView`, then to `iOSCompactPlanningView`.
3. Inside `iOSCompactPlanningView`, apply hysteresis to `headerCollapseProgress` and write discrete `DockPhase` to the binding only on transitions.
4. Extract `startTrackingDock` into a new `CommitDock` view that reads `dockPhase` and renders expanded/collapsed content.
5. `CommitDock` uses `@Environment(\.horizontalSizeClass)` to skip collapse on non-compact layouts.

### Suggested API

```swift
/// Discrete dock phase — only two states cross the binding boundary.
enum DockPhase: Equatable {
    case expanded
    case collapsed
}

struct CommitDock: View {
    let phase: DockPhase
    @Binding var showConfirmation: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCollapsed: Bool {
        phase == .collapsed && sizeClass == .compact
    }

    var body: some View {
        VStack(spacing: 0) {
            if isCollapsed {
                collapsedContent
            } else {
                expandedContent
            }
        }
        .background(.regularMaterial)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: phase)
    }
}
```

### Hysteresis logic (lives in iOSCompactPlanningView)

```swift
/// Called from existing scroll tracking. Writes to parent binding
/// only when phase actually changes (not on every frame).
private func updateDockPhase(progress: CGFloat) {
    let newPhase: DockPhase
    if dockPhase == .expanded && progress >= 0.60 {
        newPhase = .collapsed
    } else if dockPhase == .collapsed && progress <= 0.45 {
        newPhase = .expanded
    } else {
        return  // within hysteresis band — no update
    }
    dockPhase = newPhase
}
```

### Files expected to change

| File | Changes |
|------|---------|
| `ios/CryptoSavingsTracker/Views/Planning/CommitDock.swift` | **NEW** — `DockPhase` enum, collapsible dock with expanded/FAB modes, accessibility, analytics |
| `ios/CryptoSavingsTracker/Views/Planning/MonthlyPlanningContainer.swift` | Add `@State dockPhase: DockPhase = .expanded`, pass as binding, replace inline `startTrackingDock` with `CommitDock` |
| `ios/CryptoSavingsTracker/Views/Planning/PlanningView.swift` | Add `dockPhase: Binding<DockPhase>` parameter, propagate to `iOSCompactPlanningView`, apply hysteresis and write discrete phase |
| `ios/CryptoSavingsTracker/Utilities/CommitDockAnalytics.swift` | **NEW** — telemetry helper with transition-edge dedupe |
| `ios/CryptoSavingsTrackerTests/CommitDockPhaseTests.swift` | **NEW** — unit tests for hysteresis state machine, Reduce Motion gating, size class gating |
| `ios/CryptoSavingsTrackerTests/CommitDockAnalyticsTests.swift` | **NEW** — unit tests for telemetry emission rules and dedupe |
| `ios/CryptoSavingsTrackerUITests/MonthlyPlanningUITests.swift` | Add VoiceOver focus stability tests, update accessibility identifiers |

### Design debt cleanup (scoped to touched files)

- Replace `Color.green` with `AccessibleColors.success` in expanded dock icon.
- Replace `.foregroundColor(.secondary)` with `.foregroundStyle(.secondary)` in dock description.
- Add `.accessibilityElement(children: .combine)` to expanded dock content.

---

## 13) QA Acceptance Criteria

1. Expanded dock visible at top of scroll (default state).
2. Dock collapses to FAB when user scrolls past 96pt (~60% of collapse distance).
3. FAB expands back to full dock when user scrolls back above 72pt (~45% of collapse distance).
4. Hysteresis prevents flicker at threshold boundary.
5. FAB tap triggers the same confirmation alert as the expanded button.
6. Reduce Motion enabled: snap between states, no animated interpolation.
7. Dynamic Type: dock grows for accessibility sizes; FAB maintains 44pt min height.
8. VoiceOver: both modes announce correctly; no focus loss during transition.
9. Dark mode: expanded and collapsed render correctly on dark material.
10. Collapse is coordinated: dock collapses first (~96pt), then Budget Health Card (~128pt).
11. Content area does not visually jump when transitioning between modes.
12. On iPhone SE with both widgets collapsed: at least 2 full goal rows visible.
13. Tab switching (Goals/Adjust/Stats) resets dock to expanded.
14. Budget sheet dismissal resets dock to expanded.
15. Collapse behavior is disabled on iPad (regular size class) and macOS.

---

## 14) Rollout Plan

1. Implement behind feature flag (`commitDockCollapseEnabled` in `MonthlyPlanningSettings`, default `false`).
2. Validate expanded/collapsed transitions on:
   - iPhone SE (smallest compact viewport).
   - iPhone 15 Pro Max (largest compact viewport).
   - Both light and dark modes.
   - Dynamic Type at default and accessibility-large sizes.
   - Reduce Motion enabled.
3. Internal dogfood for at least one planning cycle.
4. Validate telemetry events fire correctly.
5. Compare planning session metrics (goal edits, time-to-commit) with flag on vs off.
6. Enable by default after validation.

---

## 15) Product Decisions (v1)

1. Collapsed form is a FAB pill (not a thin strip) to maintain visual weight for the primary monthly action.
2. FAB label is "Lock Plan" (shortened from "Lock Plan & Start Tracking") for density.
3. Dock collapses before the Budget Health Card (earlier threshold at 0.60 vs 0.80) because bottom chrome is more disruptive to scrolling.
4. No haptic on collapse/expand (scroll-driven, would be annoying).
5. Feature flag defaults to `false` (opt-in during validation).
6. Collapse only applies to iOS compact layout; iPad and macOS keep the full dock permanently.
7. Tab switching and budget sheet dismissal reset the dock to expanded (consistent with existing Budget Health Card behavior).
8. FAB is trailing-aligned within the `.safeAreaInset` (not a free-floating overlay), so scroll content inset adjusts automatically.

---

## 16) Open Questions

1. **FAB position**: trailing-aligned (proposed) or centered? Trailing is more thumb-reachable on large phones, but centered is more visually balanced. Recommendation: trailing-aligned per iOS FAB conventions.
2. **Label on FAB**: "Lock Plan" with icon (proposed) or icon-only? Icon-only is more compact but less discoverable for first-time users. Recommendation: keep label; truncates gracefully at large Dynamic Type.

---

## 17) Related Documentation

- [MONTHLY_PLANNING.md](MONTHLY_PLANNING.md) — Monthly planning architecture and execution flow.
- [MONTHLY_PLANNING_BUDGET_HEALTH_WIDGET_PROPOSAL.md](MONTHLY_PLANNING_BUDGET_HEALTH_WIDGET_PROPOSAL.md) — Budget Health Card scroll collapse (reference pattern).
- [COMPONENT_REGISTRY.md](COMPONENT_REGISTRY.md) — Shared component inventory.

---

*Last updated: 2026-03-01*
