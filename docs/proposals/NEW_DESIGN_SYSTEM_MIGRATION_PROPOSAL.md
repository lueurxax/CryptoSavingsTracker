# New Design System Migration Proposal

| Metadata | Value |
|---|---|
| Status | Draft |
| Created | 2026-04-26 |
| Platform | iOS first, Android/macOS parity follow-up |
| Scope | Design-system adoption for primary finance flows |
| Design source | `docs/design/` |

---

## 1) Problem

`docs/design` has been replaced with a new design-system package: brand assets, token CSS, preview cards, and an iOS UI kit for the main product loop. The current app still uses the previous visual contract in `AccessibleColors`, `VisualComponentTokens`, existing SwiftUI surfaces, and legacy release-gate documentation.

The new package introduces a stronger branded direction: midnight surfaces, honey-amber primary actions, glass-style finance cards, updated neutral ramps, and refreshed previews for Goals List, Goal Dashboard, Monthly Planning, and Log Contribution. This conflicts with parts of the existing visual-system documentation that still define blue as the single interactive accent and reference token/schema files that were removed from `docs/design`.

Without a governed migration, the app will drift into mixed visual languages: some screens will use the new amber/midnight brand layer, while release-blocking flows, tests, and docs continue enforcing the old blue-first token contract.

## 2) Goals

1. Make the new design system the canonical source for primary iOS product surfaces.
2. Resolve token and documentation conflicts before touching production UI.
3. Migrate complete user-flow slices instead of isolated components.
4. Preserve finance-app trust requirements: WCAG AA contrast, Dynamic Type, non-color status cues, deterministic recovery states, and restrained motion.
5. Keep the migration reviewable by shipping behind explicit preview/internal gates until each flow is visually and functionally complete.

## 3) Non-Goals

- No broad product IA rewrite.
- No Android implementation in the first migration wave.
- No chart engine rewrite beyond token alignment.
- No new paid features or App Store metadata work.
- No removal of existing accessibility and recovery behavior.
- No public release of partially migrated primary flows.

## 4) Design-System Decisions

### Canonical Brand Roles

The proposal treats the new visual direction as intentional:

- `brand.primary` becomes honey amber `#F5A623`.
- `brand.background.dark` becomes midnight `#05080F` / `#0A0F1F`.
- `interactive.primary` should use amber for primary CTAs in migrated branded flows.
- Existing blue remains available for informational links, chart series, focus rings, and non-primary data accents until a separate accessibility pass proves amber is suitable everywhere.

This avoids forcing amber into all legacy blue roles at once, while still making the new brand visible in the first migrated screens.

### Surface Policy

Migrate from generic `.regularMaterial` usage to named design-system surfaces:

- `CSTSurface.canvas`
- `CSTSurface.card`
- `CSTSurface.glassCard`
- `CSTSurface.sheet`
- `CSTSurface.row`
- `CSTSurface.statusTint`

The implementation may still use SwiftUI native material internally, but views must consume named tokens rather than ad hoc `.regularMaterial`, raw gradients, or per-view shadows.

### Component Scope

The first production slice should match the new iOS UI kit:

1. Goals List
2. Goal Dashboard
3. Monthly Planning
4. Log Contribution Sheet

These four surfaces form the core loop: choose goal -> understand status -> plan this month -> log contribution.

## 5) Proposed Migration Approach

### Recommended Approach: Contract First, Flow Slices Second

Migrate in four phases:

1. **Phase 0: Design contract reconciliation**
   - Update the design-system source-of-truth docs so `docs/design/README.md`, `colors_and_type.css`, previews, and `docs/VISUAL_SYSTEM_UNIFICATION.md` agree.
   - Replace references to deleted token/schema/baseline files with the new source structure, or restore machine-readable token files generated from `colors_and_type.css`.
   - Define the amber/blue split explicitly.
   - Produce a token mapping table from CSS variables to Swift tokens.

2. **Phase 1: Token layer and primitives**
   - Introduce a new Swift token layer, for example `DesignSystemColors`, `DesignSystemTypography`, `DesignSystemSpacing`, `DesignSystemSurfaces`, and `DesignSystemMotion`.
   - Keep compatibility aliases for `AccessibleColors` and `VisualComponentTokens` where needed.
   - Add preview/test fixtures for light, dark, high contrast, and Dynamic Type sizes.

3. **Phase 2: Core loop UI migration**
   - Migrate complete flow slices in this order:
     1. Log Contribution Sheet
     2. Goals List row and list summary
     3. Goal Dashboard cards and module chrome
     4. Monthly Planning summary, stale banner, goal rows, and commit dock
   - Avoid shipping a screen where only one card uses the new style and the rest remains old.

4. **Phase 3: Release gates and cleanup**
   - Add visual snapshots for light/dark migrated screens.
   - Add accessibility assertions for contrast, touch targets, status labels, and Dynamic Type clipping.
   - Remove obsolete visual-token references and stale release-gate files only after the new gates pass.

### Alternatives Considered

#### Alternative A: Big-Bang UI Rewrite

Rewrite all primary iOS views directly from the HTML kit.

Rejected because the app has complex live data, CloudKit, allocation, planning, and recovery states. A big-bang rewrite would risk regressions in App Store-ready flows.

#### Alternative B: Token Swap Only

Change existing colors and radii globally without restructuring components.

Rejected because the new design system includes component behavior and hierarchy, not just colors. Token swapping would leave mixed spacing, old card anatomy, inconsistent status chips, and unclear CTA hierarchy.

#### Alternative C: Preview-Only Brand Layer

Keep production UI unchanged and use the new design only for marketing/screenshots.

Rejected because the user-facing TestFlight app would diverge from the design source and screenshots would stop representing the real product.

## 6) Implementation Plan

### Phase 0: Reconcile Design Docs

Deliverables:

- `docs/design/README.md` updated to describe the amber/midnight system consistently.
- `docs/VISUAL_SYSTEM_UNIFICATION.md` updated or superseded by a new current visual-system contract.
- Machine-readable token source restored or generated from `colors_and_type.css`.
- Migration map:
  - CSS token
  - Swift token
  - current usage
  - migrated usage
  - status: `new`, `mapped`, `deprecated`, `needs decision`

Acceptance:

- No docs claim blue is the only primary CTA color while previews use amber.
- No release-gate docs reference missing `docs/design/schemas/*` or deleted baseline files.

### Phase 1: Swift Design-System Layer

Deliverables:

- `Utilities/DesignSystem/DesignSystemColors.swift`
- `Utilities/DesignSystem/DesignSystemTypography.swift`
- `Utilities/DesignSystem/DesignSystemSpacing.swift`
- `Utilities/DesignSystem/DesignSystemSurfaces.swift`
- `Utilities/DesignSystem/DesignSystemComponents.swift`

Acceptance:

- Primary CTA, status chips, card surfaces, rows, sheets, and text styles can be built without raw visual literals in feature views.
- Existing `AccessibleColors` continues to compile and can forward to the new token layer where behavior is equivalent.

### Phase 2A: Log Contribution Sheet

Reason to start here: contained surface, important core action, lower navigation risk.

Changes:

- Apply sheet radius, modal elevation, scrim, form row, asset chip, and primary Save action tokens.
- Preserve save-failure behavior and entered amount/note state.
- Ensure amount display uses tabular numerics.

Acceptance:

- Save failure does not dismiss entered data.
- Dynamic Type does not clip amount, asset, date, or save/cancel actions.
- Light and dark snapshots match the new sheet direction.

### Phase 2B: Goals List

Changes:

- Replace goal rows with the new card/row anatomy: emoji avatar, title, saved/target amount, deadline, progress bar/ring, explicit status chip.
- Apply summary tile styling for total saved.
- Use non-color status cues for On Track / At Risk / Off Track.

Acceptance:

- Each row remains tappable with at least 44pt target height.
- Status is readable without color.
- Long goal names and large amounts truncate or wrap predictably.

### Phase 2C: Goal Dashboard

Changes:

- Align module order with the UI kit and `docs/GOAL_DASHBOARD.md`.
- Apply new card surface, progress ring, next-action CTA, forecast, contribution, allocation, and utilities styling.
- Keep existing scene-model architecture and recovery states.

Acceptance:

- `next_action` remains above the fold on iPhone.
- Forecast cards keep assumption basis, recency, confidence, and recovery actions.
- No module directly queries raw models; views consume scene-model slices.

### Phase 2D: Monthly Planning

Changes:

- Apply new summary card, stale banner, compact goal rows, sliders/steppers, and sticky commit dock.
- Preserve existing planning math, stale-draft semantics, and commit/draft behavior.

Acceptance:

- Monthly total updates immediately with edits.
- Stale banner uses explicit warning text and icon.
- Commit dock remains reachable and avoids overlap with tab bars and keyboard.

### Phase 3: Verification and Release Gate

Deliverables:

- Snapshot artifacts for migrated flows:
  - Goals List light/dark
  - Goal Dashboard light/dark
  - Monthly Planning light/dark
  - Log Contribution Sheet light/dark
- Accessibility report for:
  - WCAG AA contrast
  - Dynamic Type
  - VoiceOver labels
  - touch target minimums
  - Reduce Motion behavior
- Release checklist confirming no mixed-style primary flow ships.

Acceptance:

- Focused unit tests pass for migrated view models/helpers.
- UI smoke test opens each migrated surface.
- Release build succeeds.

## 7) Rollout Strategy

Use the existing preview/internal gating pattern:

1. Land token layer behind no visible behavior change.
2. Enable migrated screens only in Preview/Internal mode.
3. Run TestFlight validation with migrated flows.
4. Promote one complete flow only after screenshots, accessibility checks, and functional smoke tests pass.

Rollback:

- Keep old components available during active migration.
- Each Phase 2 slice must be revertible by disabling the migrated screen route/component wrapper.
- Do not delete legacy components until the replacement has shipped in TestFlight and passed validation.

## 8) Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Design docs conflict with previews | Developers implement different systems | Phase 0 blocks UI work until source-of-truth is reconciled |
| Amber CTA fails contrast in some contexts | Accessibility regression | Keep amber on midnight/white only where contrast is proven; keep blue for info/focus/chart roles |
| Glass surfaces reduce readability | Finance data becomes harder to scan | Use glass only through named surfaces with contrast tests; keep dense rows on calm solid surfaces when needed |
| Mixed visual language ships | Product feels unfinished | Migrate by complete flow slices and gate public release |
| Existing planning/dashboard logic regresses | Core app functionality breaks | Preserve scene models/services; migrate presentation only first |
| Raw literals creep back in | Design system becomes unenforceable | Restore or replace visual lint gates after token reconciliation |

## 9) Success Metrics

- All four core iOS surfaces use the new design tokens through named Swift APIs.
- Zero new raw color/shadow/radius literals in migrated views outside token modules.
- No clipped critical finance copy at large Dynamic Type.
- Status chips always include icon + text.
- Core loop can be completed in TestFlight:
  1. open a goal,
  2. review dashboard,
  3. open monthly plan,
  4. log contribution,
  5. return to updated state.

## 10) Open Decisions

1. Should the public primary CTA color become amber everywhere after migration, or only inside the branded core loop?
2. Should the old machine-readable token manifest be restored, or should `colors_and_type.css` become the generated artifact from a new token source?
3. Should Android wait until iOS proves the design system, or should token reconciliation include Android in Phase 1?
4. Should the new glass style be used in Settings, or should Settings remain closer to native flat list rows?

## 11) Recommended Next Step

Approve Phase 0 as the first implementation proposal. It is the smallest safe starting point because it prevents the team from implementing contradictory token rules and gives the rest of the migration a stable contract.
