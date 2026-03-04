# Commit Dock Scroll Collapse Proposal

> Compress the "Ready to commit to this plan?" bottom dock into a compact floating button when the user scrolls into the goal list, reclaiming ~90pt of vertical space for planning interactions.

| Metadata | Value |
|----------|-------|
| Status | Reviewed |
| Last Updated | 2026-03-01 |
| Review Pass | UI + UX + Architecture — 3 passes (2026-03-01) |
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

### 5.4 Transition design

**Primary axis**: height + opacity (one axis only). Scale and shadow transitions are removed to prevent perceptual jitter on lower-end devices.

Because the parent receives a discrete `DockPhase` (not continuous progress), the transition is a single animated state change, not a multi-phase interpolation:

| Phase change | Animation |
|-------------|-----------|
| `.expanded` → `.collapsed` | Dock height shrinks to FAB height, expanded content fades out, FAB fades in. Single `.easeInOut(duration: 0.25)` curve. |
| `.collapsed` → `.expanded` | Reverse of above. Same curve and duration. |

**Reduce Motion**: instant swap (no animation). `animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: phase)`.

**Acceptance criterion**: no visible ghosting or frame jump at 60fps on iPhone SE and iPhone 15 Pro Max.

### 5.5 Reset and persistence behavior

The dock phase persists within a tab session to avoid unexpected layout changes. Auto-expand happens only on explicit lifecycle boundaries, not on return from overlays.

| Event | Dock behavior | Rationale |
|-------|--------------|-----------|
| **Initial load** | Expanded | Fresh planning session starts fully expanded |
| **Plan reload / data refresh** | Expanded | New data warrants full context review |
| **Tab switch** (Goals ↔ Adjust ↔ Stats) | Expanded | Different content context, reset scroll position |
| **Budget sheet dismissal** | **Preserved** (no reset) | Intentional continuity: user returns to same context, layout should not jump (see §5.5.2) |
| **Confirmation alert dismissal** | Preserved | Brief overlay, same context |
| **Scroll to top gesture** | Expanded via normal hysteresis | Scroll position crosses exit threshold naturally |

**Key change from earlier draft**: budget sheet dismissal no longer resets the dock.

### 5.5.2 UX note: phase preservation on overlay dismissal

When an overlay (budget sheet, confirmation alert) dismisses and the scroll offset resets to 0, the dock may remain collapsed while the content scrolls to the top. This is **intentional continuity behavior** — the user returns to the same planning context they left, and the dock phase preserves their working state.

Potential user perception: scroll position is at top but dock is still collapsed. This is acceptable because:
1. The user did not explicitly scroll to top — the system programmatically reset scroll.
2. Any subsequent user scroll will naturally cross the exit threshold and expand the dock.
3. The collapsed FAB still provides full commit action access.

**Verification**: usability test must confirm users do not report confusion when returning from budget sheet with preserved dock phase. If usability testing shows confusion, fall back to always expanding on overlay dismissal (change `sheetDismiss` to return `.expanded` in the phase reducer).

### 5.5.1 Event-origin phase reducer

When budget sheet dismisses, the existing `onChange(of: showingBudgetSheet)` resets `tabScrollOffset` to 0. This creates a conflict: scroll is at 0 (which would compute progress=0, below the exit threshold), but we want to preserve the dock phase.

**Design**: instead of a brittle one-shot boolean suppress flag (vulnerable to rapid event ordering and complex overlay sequences), the phase reducer receives **tagged scroll events** that carry their origin. Only user-driven scroll events can change phase; programmatic resets are ignored.

```swift
/// Origin of a scroll-offset change.
enum ScrollOrigin {
    case userScroll           // finger-driven scroll gesture
    case programmaticReset(ProgrammaticResetReason)
}

enum ProgrammaticResetReason {
    case sheetDismiss     // budget sheet, confirmation alert, etc.
    case tabSwitch        // Goals ↔ Adjust ↔ Stats
    case planReload       // data refresh
}

/// Phase reducer: deterministic, testable, no transient boolean state.
private func reduceDockPhase(
    current: DockPhase,
    progress: CGFloat,
    origin: ScrollOrigin
) -> DockPhase {
    switch origin {
    case .userScroll:
        // Normal hysteresis
        if current == .expanded && progress >= 0.60 { return .collapsed }
        if current == .collapsed && progress <= 0.45 { return .expanded }
        return current

    case .programmaticReset(.sheetDismiss):
        return current  // preserve phase (continuity)

    case .programmaticReset(.tabSwitch),
         .programmaticReset(.planReload):
        return .expanded  // explicit lifecycle reset
    }
}
```

This ensures:
- Scroll-driven phase changes work normally during user scrolling.
- Sheet/overlay dismissals do not trigger phase recompute, regardless of event ordering.
- Tab switch and plan reload deterministically reset to `.expanded`.
- Multi-overlay sequences (e.g., budget sheet → confirmation alert → dismiss both) are handled correctly because each reset carries its own origin tag.

**Acceptance criteria**:
- Returning from budget sheet preserves dock phase even though scroll offset resets to 0.
- Deterministic unit tests cover multi-event sequences (overlay + tab + scroll interleaving) with no unintended phase flips.
- Tab switch correctly resets both scroll and phase.

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

The FAB must read as the same component family as the expanded dock and pass visual QA against the Budget Health Card. This means using the shared material/stroke/elevation token system rather than a hard-tinted button with a fixed black shadow.

| Property | Value |
|----------|-------|
| Button style | `.borderedProminent` (system accent color) |
| Shape | `Capsule()` via `.clipShape(Capsule())` |
| Shadow | Adaptive: `.shadow(color: Color.primary.opacity(shadowOpacity), radius: 4, y: 2)` where `shadowOpacity` = 0.12 light / 0.20 dark (matches dock material elevation) |
| Stroke | `.overlay(Capsule().stroke(baselineStroke, lineWidth: 1))` — same `baselineStroke` token used by Budget Health Card and expanded dock |
| Internal padding | `.padding(.horizontal, 16)`, `.padding(.vertical, 10)` |
| Alignment | Trailing edge within `.safeAreaInset` container |
| Container padding | 12pt horizontal, 8pt vertical (within the safe area inset view) |
| Container surface | `.regularMaterial` (same as expanded dock — FAB floats on the same glass surface) |
| Icon | `lock.fill` (same as expanded button) |
| Label | "Lock Plan" (shortened from "Lock Plan & Start Tracking") |
| Font | `.subheadline` + `.fontWeight(.semibold)` |

**Design token coherence**: the FAB container shares `.regularMaterial` and `baselineStroke` with the expanded dock and Budget Health Card. The `.borderedProminent` button sits atop this glass surface. Shadow uses `Color.primary` with adaptive opacity rather than fixed `.black` to maintain contrast in both appearances.

### 6.3 FAB positioning within safe area inset

The FAB is **not** a free-floating overlay. It remains inside the `.safeAreaInset(edge: .bottom)` container, but the container's height shrinks from ~130-145pt to ~56pt. This ensures the scroll content inset adjusts automatically and avoids content overlap.

```swift
// Expanded mode: full VStack content
// Collapsed mode: trailing-aligned capsule button
.safeAreaInset(edge: .bottom, spacing: 0) {
    CommitDock(phase: dockPhase,
              showConfirmation: $showStartTrackingConfirmation)
}
```

### 6.4 FAB action and consequence framing

Tapping the FAB triggers the same `showStartTrackingConfirmation = true` as the expanded button. The confirmation alert and flow remain unchanged.

**Explicit consequence at point of action**: because the collapsed FAB removes the informational preamble ("This will lock in your monthly amounts..."), the confirmation alert must carry full consequence framing. The existing confirmation alert already states the consequence, but the preamble copy should be reviewed to ensure it repeats the outcome:

```
Title: "Start Tracking?"
Message: "This will lock your planned monthly amounts and begin tracking
          contributions for this month. You can undo within \(undoWindowString)."
```

**Single source of truth for undo copy**: the undo window string must be generated from `MonthlyPlanningSettings.shared.undoGracePeriodHours` (canonical source, default 24h). The current implementation in `MonthlyPlanningContainer.swift` (line ~161) hardcodes "24 hours" — this must be replaced with the settings-derived string as part of this proposal's implementation. Both the expanded dock description and the confirmation alert must read from the same computed property:

```swift
/// Canonical undo window string — single source of truth.
private var undoWindowString: String {
    let hours = MonthlyPlanningSettings.shared.undoGracePeriodHours
    if hours == 0 { return "no undo available" }
    if hours < 24 { return "\(hours) hours" }
    let days = hours / 24
    return days == 1 ? "24 hours" : "\(days) days"
}
```

**Acceptance criteria**:
- In moderated testing, users can correctly state the outcome of tapping the FAB (in both expanded and collapsed modes) before confirming.
- Confirmation alert text is generated from `undoGracePeriodHours` path — no hardcoded copy anywhere in the dock or alert.
- Existing hardcoded "24 hours" in `MonthlyPlanningContainer.swift` is replaced with the settings-derived string.

### 6.5 FAB entrance/exit animation

- **Entrance** (expanded → collapsed): opacity 0→1, duration 0.25s (aligned with dock height transition).
- **Exit** (collapsed → expanded): opacity 1→0, duration 0.25s.
- No scale animation (removed to reduce perceptual jitter — see §5.4).
- Skip all animations when Reduce Motion is enabled (instant opacity swap).

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
    ^
    |  (.onPreferenceChange reads DockPhasePreferenceKey)
  PlanningView
    |
  iOSCompactPlanningView
    @State localDockPhase: DockPhase = .expanded
    |  (exposed via .preference(key: DockPhasePreferenceKey.self))
    v
  onScrollGeometryChange → hysteresis → DockPhase
```

```swift
enum DockPhase: Equatable {
    case expanded   // scroll near top (progress < exit threshold)
    case collapsed  // scroll past enter threshold
}
```

1. `iOSCompactPlanningView` tracks scroll offset via `onScrollGeometryChange` (iOS 18+) — replaces the unreliable `GeometryReader` + `PreferenceKey` pattern that doesn't fire during continuous scrolling.
2. Hysteresis logic (enter 0.60 / exit 0.45) converts progress into a `DockPhase` enum.
3. The child writes `localDockPhase` (@State) only when the phase **changes** (at most a few times per gesture).
4. The child exposes `localDockPhase` upward via `DockPhasePreferenceKey` (a custom `PreferenceKey`).
5. `MonthlyPlanningContainerContent` reads the phase via `.onPreferenceChange(DockPhasePreferenceKey.self)` and stores it in `@State dockPhase`.
6. `CommitDock` (in the `.safeAreaInset`) reads `dockPhase` from the container — a discrete value, not a continuous stream.

### Performance contract

| Signal | Frequency | Scope |
|--------|-----------|-------|
| `contentOffset.y` (CGFloat) | Every scroll frame | Local to `iOSCompactPlanningView` only |
| `localDockPhase` (enum, @State) | On threshold transitions | Local, exposed via PreferenceKey |
| `dockPhase` (enum, @State) | On threshold transitions | Container reads via `.onPreferenceChange` |

Instruments acceptance criterion: no sustained >16ms main-thread spikes during fast scroll.

### Why PreferenceKey instead of @Binding?

The original design proposed `@Binding` for simplicity. During implementation, we discovered that `@Binding` writes from `onPreferenceChange` callbacks (the old scroll tracking approach) are **silently suppressed** by SwiftUI's layout-phase engine. Attempts to work around this (`DispatchQueue.main.async`, `onChange`, `@Published`) all failed.

The final architecture uses `onScrollGeometryChange` (iOS 18+) for scroll tracking — its `action` closure runs outside the layout phase, so `@State` writes work reliably. The local `@State` is then exposed to the parent via `DockPhasePreferenceKey`. Despite the original concern that PreferenceKey can't reach `.safeAreaInset` siblings, it works because `.onPreferenceChange` on the parent captures the value before the sibling branch.

### Why not environment?

Environment values propagate downward. The dock phase needs to flow from a child (PlanningView) to a sibling (the dock), which environment doesn't support.

### Why onScrollGeometryChange instead of GeometryReader?

The original `GeometryReader` + `PreferenceKey` scroll offset probe doesn't reliably re-evaluate preferences during continuous scrolling. Inside `LazyVStack`, the probe is unloaded when scrolled out of view. As a `.background`, preferences don't fire during scroll. `onScrollGeometryChange` (iOS 18+) is purpose-built for this and fires on every scroll frame.

### Platform-specific handling

- **iOS compact**: full collapse behavior using the discrete phase via PreferenceKey.
- **iOS regular / macOS**: `dockPhase` is always `.expanded`; dock remains permanently expanded. The `CommitDock` checks `horizontalSizeClass` and skips collapse logic.

---

## 8) Visual and Layout Rules

### 8.1 Surface treatment (unified token set)

All dock modes share the same material family for visual coherence:

| Mode | Surface | Stroke | Elevation/Shadow |
|------|---------|--------|-----------------|
| Expanded dock | `.regularMaterial` | `baselineStroke` (1pt) | None (flat on content) |
| Collapsed container | `.regularMaterial` (same surface, shorter) | `baselineStroke` (1pt) | Adaptive shadow (see §6.2) |
| FAB button | `.borderedProminent` atop material container | — | Inherits container shadow |
| Divider | Visible only in expanded mode | — | — |

**Acceptance criterion**: in light and dark modes, FAB reads as same component family as expanded dock and passes side-by-side visual QA against Budget Health Card.

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
- FAB shadow uses `Color.primary` with adaptive opacity (`0.12` light, `0.20` dark) — see §6.2.
- `baselineStroke` token is already trait-aware via `UIColor.separator` (see Budget Health Card pattern).

---

## 9) Accessibility Requirements

### 9.1 VoiceOver

**New addition**: the current dock has no accessibility grouping. This proposal adds it.

- **Expanded dock**: `.accessibilityElement(children: .combine)` with:
  - Label: `"Ready to commit to this plan. Lock Plan and Start Tracking."`
  - Hint: `"Double tap to lock your planned monthly amounts and start tracking contributions."`
- **Collapsed FAB**: explicit accessibility label (not relying on visual label alone) with:
  - Label: `"Lock Plan and Start Tracking"`  (full intent, not shortened "Lock Plan")
  - Hint: `"Double tap to lock your planned monthly amounts and start tracking contributions."`

### 9.1.1 Focus ownership contract

Deterministic focus rules across phase transitions. **Key constraint**: focus moves only if the currently focused element belongs to the dock subtree. If user focus is elsewhere (e.g., in the goal list), focus is preserved — no steal.

| Transition | Dock owns focus? | Focus behavior |
|-----------|-----------------|----------------|
| Expanded → Collapsed | Yes | Focus moves to the FAB button |
| Expanded → Collapsed | No | Focus stays on current element (no steal) |
| Collapsed → Expanded | Yes | Focus moves to the expanded "Lock Plan & Start Tracking" button |
| Collapsed → Expanded | No | Focus stays on current element (no steal) |
| Tab switch (resets to expanded) | N/A | Focus moves to the first content element in the new tab |

**Implementation**:

```swift
/// Only redirect focus when dock subtree currently owns it.
private func handlePhaseChange(from old: DockPhase, to new: DockPhase) {
    guard dockHasFocus else { return }  // preserve user context
    switch new {
    case .collapsed: focusTarget = .fab
    case .expanded:  focusTarget = .expandedButton
    }
}
```

Use `.accessibilityFocused($focusTarget)` with an enum binding. The `dockHasFocus` guard checks `AccessibilityFocusState` before redirecting.

**Acceptance criteria**:
- VoiceOver focus remains stable when user focus is outside dock during transitions.
- VoiceOver focus transfers correctly when dock subtree owns focus.
- Automated UI tests assert both paths (dock-focused and non-dock-focused transitions).

### 9.2 Reduce Motion

When `@Environment(\.accessibilityReduceMotion)` is true:
- Snap between expanded and collapsed at thresholds (no animated interpolation).
- FAB entrance/exit: instant opacity change, no scale animation.
- Dock height: instant change, no animated transition.

### 9.3 Dynamic Type

At accessibility type sizes:
- Expanded dock: allow description to wrap to 3 lines (upgrade from 2), then truncate.
- Expanded dock: allow height to grow above 145pt (no hard cap).
- FAB label: use `.minimumScaleFactor(0.8)` to keep "Lock Plan" text visible at large sizes before truncating. Do **not** accept icon-only as sufficient — the action is high-consequence and requires textual clarity.
- FAB: enforce min 44pt height regardless of text size.
- FAB accessibility label always carries full intent ("Lock Plan and Start Tracking") regardless of visual truncation.

**Acceptance criterion**: at AX5 size, FAB control remains understandable without relying on icon meaning alone.

### 9.4 Minimum touch targets

- Expanded button: full-width, 44pt minimum height (per HIG).
- Collapsed FAB: `.frame(minHeight: 44)`.

---

## 10) Motion and Haptics

### 10.1 Collapse transition (single state machine)

One animation drives all visual changes, keyed on `DockPhase`:

```swift
.animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: phase)
```

- **Height**: dock container animates from ~130-145pt to ~56pt (or reverse).
- **Expanded content opacity**: fades out/in with the same curve.
- **FAB opacity**: fades in/out with the same curve.
- No staggered fades, no scale, no independent shadow animation.

This single-axis approach prevents the perceptual jitter that comes from simultaneous fade + height + scale + shadow transitions.

### 10.2 Reduce Motion

When enabled: instant state swap, no animation. The `.animation(nil, value:)` path produces a zero-duration transition.

### 10.3 Haptics

- No haptic on collapse/expand (frequent scroll-driven event, would be annoying).
- Existing system haptic on confirmation alert presentation is sufficient.

---

## 11) Telemetry

Track events through a `CommitDockAnalytics` helper (same pattern as `BudgetHealthAnalytics`).

### Transition-edge dedupe (session-scoped)

Collapse/expand events fire **only on `DockPhase` transitions**, not on every scroll frame. Because the hysteresis logic already emits discrete state changes, telemetry naturally dedupes. An additional cooldown prevents rapid oscillation noise.

**Important**: cooldown and counters are scoped to a session instance (not global static) to prevent cross-instance suppression and KPI distortion. Each `CommitDock` view owns its analytics tracker.

### Session lifecycle contract

A **planning session** is defined as a single continuous visit to the Monthly Planning screen:
- **Start**: `CommitDock.onAppear` (planning screen becomes visible).
- **End**: `CommitDock.onDisappear` (user navigates away, app backgrounds, or view is torn down).
- **Reset**: tracker creates a new instance on each `onAppear`. Counters and cooldown state do not persist across sessions.

This ties session identity to SwiftUI view lifecycle, which is deterministic and testable. If the planning screen is re-entered (e.g., navigate away and back), a new session begins with fresh counters.

```swift
/// Session-scoped analytics tracker — one per planning-screen visit.
final class CommitDockAnalyticsTracker {
    private let transitionCooldown: TimeInterval = 1.0
    private var lastTransitionTimestamp: Date?
    private(set) var sessionCollapseCount = 0
    private(set) var sessionExpandCount = 0

    func logPhaseChange(to phase: DockPhase) {
        let now = Date()
        if let last = lastTransitionTimestamp,
           now.timeIntervalSince(last) < transitionCooldown {
            return  // suppress rapid oscillation
        }
        lastTransitionTimestamp = now
        switch phase {
        case .collapsed:
            sessionCollapseCount += 1
            CommitDockAnalytics.log(.collapsed, properties: [
                "session_collapse_count": "\(sessionCollapseCount)"
            ])
        case .expanded:
            sessionExpandCount += 1
            CommitDockAnalytics.log(.expanded, properties: [
                "session_expand_count": "\(sessionExpandCount)"
            ])
        }
    }

    func reset() {
        lastTransitionTimestamp = nil
        sessionCollapseCount = 0
        sessionExpandCount = 0
    }
}
```

In `CommitDock`:
```swift
@State private var analyticsTracker = CommitDockAnalyticsTracker()

// Reset on each planning-screen visit
.onAppear { analyticsTracker.reset() }
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

### Phase reducer (lives in iOSCompactPlanningView)

```swift
/// Event-origin-aware phase reducer. See §5.5.1 for full design.
/// Called from scroll tracking (userScroll) and onChange handlers
/// (programmaticReset). Writes to parent binding only on transitions.
private func applyScrollEvent(progress: CGFloat, origin: ScrollOrigin) {
    let newPhase = reduceDockPhase(
        current: dockPhase,
        progress: progress,
        origin: origin
    )
    if newPhase != dockPhase {
        dockPhase = newPhase
    }
}
```

### Files expected to change

| File | Changes |
|------|---------|
| `ios/CryptoSavingsTracker/Views/Planning/CommitDock.swift` | **NEW** — `DockPhase` enum, collapsible dock with expanded/FAB modes, accessibility, analytics |
| `ios/CryptoSavingsTracker/Views/Planning/MonthlyPlanningContainer.swift` | Add `@State dockPhase`, read via `.onPreferenceChange(DockPhasePreferenceKey.self)`, replace inline `startTrackingDock` with `CommitDock` |
| `ios/CryptoSavingsTracker/Views/Planning/PlanningView.swift` | Add `@State localDockPhase`, expose via `DockPhasePreferenceKey`, replace `GeometryReader` scroll probe with `onScrollGeometryChange`, apply hysteresis |
| `ios/CryptoSavingsTracker/Utilities/CommitDockAnalytics.swift` | **NEW** — telemetry helper with transition-edge dedupe |
| `ios/CryptoSavingsTrackerTests/CommitDockPhaseTests.swift` | **NEW** — unit tests for hysteresis state machine, Reduce Motion gating, size class gating |
| `ios/CryptoSavingsTrackerTests/CommitDockAnalyticsTests.swift` | **NEW** — unit tests for telemetry emission rules and dedupe |
| `ios/CryptoSavingsTrackerUITests/MonthlyPlanningUITests.swift` | Add VoiceOver focus stability tests, update accessibility identifiers |

### Unit test strategy

Hysteresis, Reduce Motion, and size class gating are logic-heavy and regression-prone. These must have deterministic unit tests, not only manual QA:

| Test file | Coverage |
|-----------|----------|
| `CommitDockPhaseTests.swift` | Hysteresis state machine: enter/exit thresholds, gap behavior, rapid oscillation suppression |
| `CommitDockPhaseTests.swift` | Event-origin reducer: `userScroll` triggers transitions, `sheetDismiss` preserves phase, `tabSwitch`/`planReload` force `.expanded` |
| `CommitDockPhaseTests.swift` | Multi-event sequences: overlay + tab + scroll interleaving produces deterministic phase |
| `CommitDockPhaseTests.swift` | Reduce Motion gating: phase changes still work, only animation is suppressed |
| `CommitDockPhaseTests.swift` | Size class gating: non-compact always returns `.expanded` |
| `CommitDockAnalyticsTests.swift` | Transition-edge dedupe: events fire only on phase changes |
| `CommitDockAnalyticsTests.swift` | Cooldown: rapid transitions within 1s are suppressed |
| `CommitDockAnalyticsTests.swift` | Session-scoped: independent tracker instances have independent counts (no cross-instance bleed) |
| `CommitDockAnalyticsTests.swift` | Session lifecycle: `reset()` clears counters and cooldown; simulates onAppear/onDisappear cycle |
| `CommitDockAnalyticsTests.swift` | Session counter bounds |

UI tests remain for integration paths (visual transition, VoiceOver focus stability, content inset behavior).

**Acceptance criterion**: CI catches threshold, accessibility, and telemetry regression without manual reproduction.

### Design debt cleanup (scoped to touched files)

- Replace `Color.green` with `AccessibleColors.success` in expanded dock icon.
- Replace `.foregroundColor(.secondary)` with `.foregroundStyle(.secondary)` in dock description.
- Add `.accessibilityElement(children: .combine)` to expanded dock content.

---

## 13) QA Acceptance Criteria

### Functional
1. Expanded dock visible at top of scroll (default state).
2. Dock collapses to FAB when user scrolls past 96pt (~60% of collapse distance).
3. FAB expands back to full dock when user scrolls back above 72pt (~45% of collapse distance).
4. Hysteresis prevents flicker at threshold boundary.
5. FAB tap triggers the same confirmation alert as the expanded button.
6. Confirmation alert copy explicitly states consequence in both modes.
7. Collapse is coordinated: dock collapses first (~96pt), then Budget Health Card (~128pt).
8. Tab switching (Goals/Adjust/Stats) resets dock to expanded.
9. Budget sheet dismissal preserves current dock phase (no auto-reset).
10. Collapse behavior is disabled on iPad (regular size class) and macOS.

### Performance
11. No sustained >16ms main-thread spikes during fast scroll (Instruments).
12. Binding propagation is discrete (enum), not continuous (CGFloat) — verify with breakpoints.
13. Content area does not visually jump when transitioning between modes.
14. No visible ghosting or frame jump at 60fps on iPhone SE and iPhone 15 Pro Max.

### Accessibility
15. Reduce Motion enabled: instant snap between states, no animated interpolation.
16. Dynamic Type at AX5: FAB retains readable text label (not icon-only).
17. Dynamic Type: dock grows for accessibility sizes; FAB maintains 44pt min height.
18. VoiceOver: both modes announce correctly with full consequence semantics.
19. VoiceOver: focus transfers deterministically on phase transitions (expanded button ↔ FAB).
20. VoiceOver: no re-announcement of non-interactive elements during transitions.

### Visual
21. Dark mode: expanded and collapsed render correctly on dark material.
22. FAB reads as same component family as expanded dock (glass surface, adaptive shadow, shared stroke).
23. FAB center within 80pt of trailing edge on iPhone 15 Pro Max (reachability criterion).
24. On iPhone SE with both widgets collapsed: at least 2 full goal rows visible.
25. Post-implementation screenshot matrix (SE + Pro Max, light + dark, default + AX3 + AX5) attached before flag default changes.

### Telemetry
26. Collapse/expand events fire only on phase transitions (not every scroll frame).
27. Rapid scroll oscillation does not produce more than one event per second.
28. Per-session event volume is bounded and KPI variance is stable across builds.
29. Telemetry counters are session-scoped — no cross-instance bleed between dock instances.

### Focus & Context
30. VoiceOver focus is not stolen when user focus is outside dock subtree during phase transition.
31. Budget sheet dismissal preserves dock phase via event-origin reducer (not boolean flag).
32. Confirmation copy uses canonical `undoGracePeriodHours` source (no hardcoded placeholder).
33. Multi-event sequences (overlay + tab + scroll interleaving) produce deterministic phase.
34. Usability check: users do not report confusion when returning from budget sheet with preserved dock phase.
35. Runtime screenshot matrix (not previews) attached and visually signed off before flag default changes.

---

## 14) Rollout Plan

1. ~~Implement behind feature flag~~ → **Always enabled** (feature flag removed; collapse is the default behavior on iOS compact).
2. **Post-implementation runtime screenshot matrix** (gate for step 3):
   - Capture expanded and collapsed commit dock in **simulator runtime** (not Xcode Previews — runtime captures material compositing, shadow contrast, and inset animation that previews may not reproduce accurately).
   - Combinations:
     - Devices: iPhone SE, iPhone 15 Pro Max.
     - Appearances: light, dark.
     - Dynamic Type: default, AX3, AX5.
   - Attach captures to PR or proposal appendix. Visual QA must sign off both appearances before flag default changes.
3. Validate expanded/collapsed transitions on:
   - iPhone SE (smallest compact viewport).
   - iPhone 15 Pro Max (largest compact viewport).
   - Both light and dark modes.
   - Dynamic Type at default and accessibility-large sizes.
   - Reduce Motion enabled.
4. Internal dogfood for at least one planning cycle.
5. Validate telemetry events fire correctly (session-scoped, no cross-instance bleed).
6. Compare planning session metrics (goal edits, time-to-commit) with flag on vs off.
7. **Rollback thresholds** (automatic flag disable if any triggered):

   | Metric | Threshold | Measurement window |
   |--------|-----------|-------------------|
   | P95 main-thread frame time regression | >20% vs baseline (flag off) | 48h rolling |
   | Commit conversion rate drop | >5% relative decrease | 7-day cohort |
   | Transition event rate anomaly | >3x expected per-session bound | 24h rolling |
   | Crash rate in planning screen | Any increase >0.1% absolute | 48h rolling |

   Go/no-go decisions are threshold-based, not subjective. If telemetry infrastructure cannot measure a threshold at launch, that threshold is treated as blocking until instrumented.

8. Enable by default after validation passes all thresholds for one full planning cycle.

---

## 15) Product Decisions (v1)

1. Collapsed form is a FAB pill (not a thin strip) to maintain visual weight for the primary monthly action.
2. FAB visual label is "Lock Plan" (shortened from "Lock Plan & Start Tracking") for density. Accessibility label carries full intent.
3. Dock collapses before the Budget Health Card (earlier threshold at 0.60 vs 0.80) because bottom chrome is more disruptive to scrolling.
4. No haptic on collapse/expand (scroll-driven, would be annoying).
5. ~~Feature flag defaults to `false`~~ → Always enabled (no feature flag).
6. Collapse only applies to iOS compact layout; iPad and macOS keep the full dock permanently.
7. Tab switching resets the dock to expanded. Budget sheet dismissal preserves current phase (continuity over predictability — see review conflict #3).
8. FAB is **trailing-aligned** within the `.safeAreaInset` (not a free-floating overlay). Reachability criterion: FAB center within 80pt of trailing edge on iPhone 15 Pro Max.
9. **[Review]** Single-axis transition (height + opacity) preferred over multi-axis choreography. Frame stability on small devices takes priority over polish (review conflict #2).
10. **[Review]** FAB shares glass surface tokens (`.regularMaterial`, `baselineStroke`, adaptive shadow) with expanded dock for visual coherence.
11. **[Review]** Parent receives discrete `DockPhase` enum, not raw `CGFloat` progress. Hysteresis logic stays in child view.
12. **[Review]** VoiceOver focus moves only when dock subtree owns focus; otherwise user context is preserved (review conflict #4).
13. **[Review]** Telemetry cooldown is session-scoped (instance), not global static (review conflict #5).
14. **[Review]** Budget sheet dismissal preserves dock phase via event-origin reducer; phase is source of truth over scroll offset (§5.5.1).
15. **[Review]** Trailing FAB placement ships in v1. Post-rollout ergonomics validation will check left-handed reachability; adjust placement only if measurable tap-friction gap appears (see §16).

---

## 16) Open Questions

> **Resolved**: ~~FAB position: trailing-aligned or centered?~~ Review decision: **trailing-aligned**. Measurable criterion: on iPhone 15 Pro Max held one-handed (right), the FAB center must fall within the natural thumb arc (bottom-right quadrant, within 80pt of trailing edge). This matches iOS FAB conventions and maximizes reachability on large phones. QA checklist item added (§13, Visual #22).

> **Resolved**: ~~Label on FAB: "Lock Plan" with icon or icon-only?~~ Review decision: keep text label at all sizes. Icon-only is not acceptable for a high-consequence financial action. Use `.minimumScaleFactor(0.8)` to preserve readability at large Dynamic Type. Full intent carried by accessibility label regardless.

> **Deferred to post-rollout**: left-handed reachability. Trailing placement optimizes for right-thumb use. A post-rollout study comparing tap success/latency by handedness proxy will determine if symmetric placement (e.g., centered, or leading option) is needed. Explicit deferral — not a gap.

---

## 17) Related Documentation

- [MONTHLY_PLANNING.md](MONTHLY_PLANNING.md) — Monthly planning architecture and execution flow.
- [MONTHLY_PLANNING_BUDGET_HEALTH_WIDGET.md](MONTHLY_PLANNING_BUDGET_HEALTH_WIDGET.md) — Budget Health Card scroll collapse (reference pattern).
- [COMPONENT_REGISTRY.md](COMPONENT_REGISTRY.md) — Shared component inventory.

---

## Appendix A: Review Findings (2026-03-01)

### A.1 UI Review

| Severity | Finding | Fix applied |
|----------|---------|-------------|
| Medium | FAB visual language not coherent with glass surface — prominent tint + hard shadow feels detached from material layer | §6.2: adaptive shadow with `Color.primary`, shared `baselineStroke`, `.regularMaterial` container. §8.1: unified token set table. |
| Medium | Transition choreography overloaded — simultaneous fade, height, scale, and shadow causes perceptual jitter | §5.4: single-axis transition (height + opacity only). §6.5: scale removed. §10.1: single state machine drives all changes. |
| Low | Primary action readability degrades at large type — icon-only comprehension is weak for high-consequence action | §9.3: `.minimumScaleFactor(0.8)`, no icon-only acceptance. Full accessibility label at all sizes. |

### A.2 UX Review

| Severity | Finding | Fix applied |
|----------|---------|-------------|
| High | Commitment intent becomes less explicit in collapsed state — finance actions need explicit consequence framing at point of action | §6.4: confirmation preamble copy repeats consequence. §9.1: accessibility label carries full intent ("Lock Plan and Start Tracking"), hint repeats consequence. |
| Medium | State reset policy can break continuity — auto-expand on sheet return causes unexpected layout change | §5.5: persist collapse phase within session. Budget sheet dismissal no longer resets. Reset only on tab switch or plan reload. |
| Medium | Accessibility plan lacks deterministic focus contract — "must not lose focus" is not implementable without explicit target | §9.1.1: focus ownership table for each transition. `.accessibilityFocused` binding synced with `DockPhase`. UI test assertions. |

### A.3 Architecture Review

| Severity | Finding | Fix applied |
|----------|---------|-------------|
| High | Continuous binding propagation risks render churn — scroll updates trigger frequent parent recomposition | §7: discrete `DockPhase` enum replaces `CGFloat` binding. Hysteresis stays in child. Parent sees only state transitions. Performance contract added. |
| High | Telemetry events need transition-edge dedupe — threshold oscillation can inflate counts | §11: events fire only on phase transitions. 1s cooldown suppresses rapid oscillation. Per-session counters bound event volume. |
| Medium | Test strategy heavy on manual QA, light on deterministic unit seams | §12: added `CommitDockPhaseTests` and `CommitDockAnalyticsTests`. Unit tests cover state machine, dedupe, Reduce Motion, and size class gating. |

### A.4 Cross-Discipline Conflict Resolutions (Pass 1)

| # | Conflict | Tradeoff | Decision | Owner |
|---|----------|----------|----------|-------|
| 1 | Compact label density ("Lock Plan") vs financial clarity | UI density and scan speed vs explicit consequence at tap point | Keep compact visual label, enforce explicit accessibility semantics and confirmation preamble | Product + Design + iOS |
| 2 | Richer motion polish vs scroll performance headroom | Perceived delight vs frame stability on small devices | Simplify transition stack, prioritize stable frame pacing | iOS |
| 3 | Deterministic reset behavior vs user continuity | Predictable defaults vs preserving in-flow context | Preserve state within session/tab; reset only on explicit lifecycle boundary | UX + iOS |

---

## Appendix B: Review Findings — Pass 2 (2026-03-01)

### B.1 UI Findings

| Severity | Finding | Fix applied |
|----------|---------|-------------|
| Medium | FAB alignment unresolved — affects thumb reach, visual balance, and QA criteria | §16: resolved as trailing-aligned with measurable reachability criterion (80pt from trailing edge). §15 #8 updated. QA #23 added. |
| Low | Runtime visual evidence missing for collapsed commit dock | §14: post-implementation screenshot matrix gate added (SE + Pro Max, light + dark, default + AX sizes). QA #25 added. |

### B.2 UX Findings

| Severity | Finding | Fix applied |
|----------|---------|-------------|
| High | VoiceOver focus contract can steal focus during scroll transitions when user focus is outside dock | §9.1.1: conditional focus move — only when dock subtree owns focus. `dockHasFocus` guard added. Tests assert both paths. QA #30 added. |
| Medium | Confirmation copy uses placeholder `[X] hours` instead of canonical source | §6.4: references `MonthlyPlanningSettings.shared.undoGracePeriodHours`. No hardcoded copy. QA #32 added. |

### B.3 Architecture Findings

| Severity | Finding | Fix applied |
|----------|---------|-------------|
| High | Telemetry cooldown is global static — cross-instance suppression distorts KPIs | §11: session-scoped `CommitDockAnalyticsTracker` class, one per `CommitDock` instance. No mutable global static state. QA #29 added. |
| Medium | Phase persistence conflicts with scroll reset on budget-sheet dismissal | §5.5.1: event-origin phase reducer (replaced boolean suppress flag in R3). UI test specified. QA #31 added. |
| Medium | Related-doc reference drift (`_PROPOSAL` suffix) | §17: link corrected to `MONTHLY_PLANNING_BUDGET_HEALTH_WIDGET.md`. |

### B.4 Cross-Discipline Conflict Resolutions (Pass 2)

| # | Conflict | Decision |
|---|----------|----------|
| 4 | Aggressive VO focus guidance vs user context continuity | Preserve focus unless dock was active focus owner |
| 5 | Telemetry noise suppression vs analytics fidelity | Session-scoped dedupe, not global static cooldown |
| 6 | Alignment aesthetics vs thumb reach | Trailing-aligned with measurable 80pt reachability criterion |

---

## Appendix C: Review Findings — Pass 3 (R3) (2026-03-01)

### C.1 UI Findings

| Severity | Finding | Fix applied |
|----------|---------|-------------|
| Medium | Dark-mode runtime validation still incomplete — preview captures don't cover material compositing and inset animation | §14: screenshot matrix explicitly requires **simulator runtime** captures (not previews). Visual QA signoff gate added. QA #35 added. |
| Low | Trailing-only reachability over-optimizes one-hand posture (right-handed bias) | §15 #15: trailing ships v1 with explicit post-rollout ergonomics validation. §16: handedness deferred with documented rationale. |

### C.2 UX Findings

| Severity | Finding | Fix applied |
|----------|---------|-------------|
| Medium | Phase-preservation can feel inconsistent without user-visible context (scroll at top, dock collapsed) | §5.5.2: new UX note documenting intentional continuity behavior. Usability test gate. Fallback path defined if users report confusion. QA #34 added. |
| Medium | Canonical copy alignment not yet reconciled with current hardcoded "24 hours" in MonthlyPlanningContainer | §6.4: locked single source of truth via `undoWindowString` computed property from `undoGracePeriodHours`. Explicit implementation task to replace hardcoded copy. |

### C.3 Architecture Findings

| Severity | Finding | Fix applied |
|----------|---------|-------------|
| High | `suppressPhaseRecompute` boolean is vulnerable to sequencing edge cases (multiple overlays, animation frames, tab changes) | §5.5.1: replaced with event-origin phase reducer (`ScrollOrigin` + `ProgrammaticResetReason`). Deterministic, testable, no transient boolean state. Unit tests cover multi-event sequences. QA #33 added. |
| Medium | Session-scoped analytics lacks explicit session lifecycle contract (start/end/reset) | §11: defined session lifecycle (onAppear → onDisappear), `reset()` method on tracker, test coverage for lifecycle transitions. |
| Medium | Rollout plan misses numeric rollback thresholds | §14 #7: added threshold table (frame time, conversion, event rate, crash rate) with measurement windows. Go/no-go is threshold-based. |

### C.4 Cross-Discipline Conflict Resolutions (Pass 3)

| # | Conflict | Decision | Owner |
|---|----------|----------|-------|
| 7 | Phase continuity on overlay dismiss vs strict scroll-state determinism | Keep continuity, replace boolean with event-origin reducer | iOS + UX |
| 8 | Trailing FAB reachability optimization vs broad-handed ergonomics | Ship trailing v1 with explicit post-rollout ergonomics validation | Product + Design |
| 9 | Lightweight telemetry implementation vs strong KPI interpretability | Add explicit session contract + numeric rollout thresholds | iOS + Data |

---

*Last updated: 2026-03-01*
