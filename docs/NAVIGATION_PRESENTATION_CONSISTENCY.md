# Navigation and Presentation Consistency

> Cross-platform navigation architecture, modal policy, and CI enforcement for finance-critical flows

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-03-04 |
| Platform | iOS + Android |
| Audience | Developers |

---

## Table of Contents

1. [Overview](#overview)
2. [iOS architecture policy](#ios-architecture-policy)
3. [iOS presentation contract](#ios-presentation-contract)
4. [Dismissal and unsaved-change policy](#dismissal-and-unsaved-change-policy)
5. [Android parity](#android-parity)
6. [Enforcement and CI](#enforcement-and-ci)
7. [Accessibility contract](#accessibility-contract)
8. [Hard cutover governance](#hard-cutover-governance)
9. [Test and observability requirements](#test-and-observability-requirements)
10. [File locations](#file-locations)
11. [Related documentation](#related-documentation)

---

## Overview

The navigation and presentation system enforces one executable policy per platform for navigation containers, modal presentation, and transition behavior. This eliminates mixed `NavigationView`/`NavigationStack` usage, standardizes modal intent through decision IDs (`MOD-01...MOD-05`), and ensures cross-platform journey parity with CI gates.

### Design principles

- Predictable modal behavior per user intent.
- Zero legacy APIs in active iOS views.
- Journey-level parity for top recurring iOS/Android flows.
- Deterministic cancel/recovery behavior in money-related flows.

### Scope

In scope:
- iOS hard-cutover from `NavigationView`/`ActionSheet` patterns.
- iOS modal consistency via decision IDs `MOD-01...MOD-05`.
- Android parity hardening for the top 5 shared journeys.
- CI, lint, and release-gate definitions without runtime migration toggles.

Out of scope:
- Full iPad redesign beyond minimum defaults for `MOD-01...MOD-05`.
- Visual redesign unrelated to navigation/presentation behavior.
- Non-mobile platforms (macOS/visionOS).

---

## iOS architecture policy

- Root container for active iOS views: `NavigationStack` only.
- Legacy `NavigationView` is forbidden in active source paths (preview/test allowlist only).
- Route-state ownership model:
  - App-level route transitions use coordinator path state.
  - Feature-local stacks are allowed for intra-feature drill-down only.
  - Mixed ownership in one flow requires explicit ADR exception.
- Action selection uses `confirmationDialog` (legacy `ActionSheet` forbidden).

---

## iOS presentation contract

All modal/dialog call-sites must reference one decision ID below and include a machine-checkable annotation `// NAV-MOD: MOD-xx`.

### Decision ID matrix

| Decision ID | Use case | API | Presentation rules |
|-------------|----------|-----|-------------------|
| MOD-01 | Quick pick / lightweight form | `.sheet` | Title inline, dismiss by swipe allowed when form is clean, detents `.medium/.large` when content permits. |
| MOD-02 | Keyboard-heavy numeric input (budget/planning edits) | `.sheet` | Default large detent, explicit keyboard dismiss control, `interactiveDismissDisabled(isDirty)`. |
| MOD-03 | Multi-step guided commit flow | `.fullScreenCover` | Full-screen with persistent progress/context; explicit Cancel + primary action in toolbar. |
| MOD-04 | Destructive or irreversible choice | `confirmationDialog` | Clear destructive labeling, cancel always present, no silent fallback behavior. |
| MOD-05 | Blocking validation failure requiring immediate correction | `.sheet` or in-flow blocking panel | Must preserve context and explain recovery action; style must not change by runtime/test mode. |

### Standard toolbar anatomy

- Leading: Back/Cancel.
- Trailing: primary CTA (Save/Continue/Confirm).
- Destructive actions never share primary visual emphasis with safe actions.

### Compact overflow rules

| Decision ID | Title behavior | Button priority | Secondary action strategy |
|-------------|---------------|-----------------|--------------------------|
| MOD-01 | Single-line title; truncate tail if needed. | Primary action always visible in toolbar. | Secondary actions move into contextual menu if width is constrained. |
| MOD-02 | Short semantic title only (no dynamic numeric payload in title). | `Save`/`Apply` is pinned and never collapses. | `Cancel` remains explicit; tertiary actions move below form or into menu; keyboard toolbar fallback must expose `Done` + primary action when keyboard is up. |
| MOD-03 | Progress title may wrap to 2 lines max. | Commit CTA pinned; Back/Cancel pinned. | Non-critical helper actions move to overflow menu. |
| MOD-04 | Short decision prompt with explicit destructive label. | Destructive and Cancel always visible. | No tertiary controls in dialog. |
| MOD-05 | Error title + one-line recovery hint. | Primary recovery action pinned. | Alternate recovery actions collapse to list row/menu. |

### `MOD-02` compact hierarchy

- Priority order: `primary CTA` > `cancel/back` > `secondary text/helpers`.
- Primary CTA never truncates, collapses, or moves off-screen.
- Title truncates tail at 1 line before any primary action layout compromise.
- Secondary helper text may collapse into overflow/menu first.

### Transition behavior contract

- Present/dismiss animations use platform-default timing (no custom animation overrides).
- Keyboard-heavy forms must provide deterministic keyboard dismiss affordance.
- Dismiss result must preserve orientation: user returns to the same logical context anchor.
- Interrupted drag-dismiss on dirty form must bounce back to the current modal state, then show discard confirmation (`Keep Editing` / `Discard`).

### iPad defaults

| Decision ID | iPad default container | Dismiss rule | Notes |
|-------------|----------------------|--------------|-------|
| MOD-01 | Popover preferred; fallback `.sheet` when content exceeds popover affordance | Tap outside allowed only when clean | Keep initiating context visible where possible |
| MOD-02 | `.sheet` with large-form presentation | Dirty state blocks dismiss and triggers confirmation | Keyboard + CTA must remain visible in regular width |
| MOD-03 | `.fullScreenCover` only for true multi-step commit | Explicit cancel/confirm required | Preserve progress context and confirmation state |
| MOD-04 | `confirmationDialog` anchored to invoking control | Cancel always visible | Destructive action visually isolated |
| MOD-05 | In-flow blocking panel or sheet based on severity | No silent dismiss during unresolved blocking validation | Recovery path must be explicit and testable |

---

## Dismissal and unsaved-change policy

### Dirty-dismiss confirmation

- Dirty financial forms (edited but uncommitted) must intercept dismiss/back/drag.
- Required confirmation on dirty dismiss:
  - `Keep Editing` (default).
  - `Discard` (destructive).
- No silent data loss on cancel.
- After discard/cancel, the parent screen must show deterministic state (no partial application).

### Dirty-state contract

- A form is dirty only when canonicalized persisted fields change (`initialCanonical != currentCanonical`).
- Non-persistent UI state (focus, keyboard visibility, temporary scroll position) never marks dirty.
- Async preview calculations do not mark dirty unless they modify persisted fields.
- Reverting edited fields back to canonical initial value clears dirty state.

### Dirty-state matrix

| Form | Canonical fields | Dirty trigger | Dirty clear rule | Owner |
|------|-----------------|---------------|------------------|-------|
| Budget edit | amount, frequency, currency | any canonical field mutation | all canonical fields equal baseline | Planning team |
| Goal edit | target amount, deadline, title | any canonical field mutation | all canonical fields equal baseline | Goals team |
| Contribution edit | execution amount/date/type | any canonical field mutation | all canonical fields equal baseline | Execution team |

---

## Android parity

- Android uses single `NavHost` graph + centralized route definitions.
- Android implements equivalent journey behavior for iOS decision IDs (MOD-01...MOD-05), even if UI primitives differ.
- Compose Material 3 dialogs/sheets follow the same intent/risk semantics as iOS.

### Top parity journeys (release-gated)

1. Goal create/edit.
2. Monthly budget adjust.
3. Destructive delete confirmation.
4. Goal contribution edit/cancel.
5. Planning flow cancel/recovery.

### Parity script template

Each journey is validated with a 6-step script:
1. Entry preconditions and launch point.
2. Primary action path.
3. Cancel path.
4. Validation error path.
5. Recovery path.
6. Confirmation/final state assertion.

---

## Enforcement and CI

### Forbidden API lint

CI check fails PRs on forbidden iOS APIs in active paths:
- Forbidden: `NavigationView`, `.actionSheet`, `ActionSheet`.
- Scope: `ios/CryptoSavingsTracker/Views/**`, `ios/CryptoSavingsTracker/Navigation/**`.

Syntax-aware parsing rules:
- Exclude tokens inside `#Preview { ... }` blocks.
- Exclude `PreviewProvider` declarations.
- Evaluate all other declarations as active code.
- Fallback: if syntax parser is unavailable, preview code must be in dedicated preview-only files (`*Preview*.swift`).

### Decision-ID annotation check

Every modal/dialog call-site must include a nearby annotation `// NAV-MOD: MOD-xx`. CI verifies annotation exists and matches a valid decision ID.

### CI jobs

| Job name | Command | Blocking scope | Owner |
|----------|---------|---------------|-------|
| `policy-nav-ios-forbidden-apis` | `scripts/check_navigation_policy.py` | iOS views | Mobile Platform Team |
| `policy-nav-android-parity-matrix` | `scripts/check_android_navigation_parity_matrix.py` | Android parity | Mobile Platform Team |
| `policy-nav-mod02-compact-snapshots` | `scripts/check_mod02_compact_artifacts.py` | MOD-02 flows | Mobile Platform Team |

### Compact screenshot artifact gate

- Applies when PR touches files mapped to `MOD-02`.
- Requires both compact baseline and updated snapshot diff artifacts.
- PR fails when artifacts are missing or diff exceeds approved threshold.

### Temporary allowlist policy

- Active file: `docs/testing/navigation-policy-allowlist.v1.json`.
- Each exemption must be removed before release package promotion.

### CI parser ADR

ADR ID: `ADR-NAV-CI-PARSER-001` (Accepted 2026-03-03)

- Primary parser: `SwiftSyntax`-based scanner for iOS UI source files.
- Fallback: if parser fails, CI requires preview extraction to `*Preview*.swift` before merge.
- Rule IDs: `NAV001` forbidden API, `NAV002` missing decision tag, `NAV003` preview segregation fallback.
- Authoritative document: `docs/design/ADR-NAV-CI-PARSER-001.md`.

---

## Accessibility contract

- Minimum tappable target for interactive controls: 44x44 pt (or platform-equivalent).
- Primary actions require explicit VoiceOver/TalkBack labels.
- Critical states must not rely on color-only differentiation.
- Dynamic type must keep primary actions visible and non-overlapping on compact devices.

---

## Hard cutover governance

The runtime migration layer has been removed. Navigation/presentation policy is always-on as the single production behavior.

### Current status

- `NAV001`: 0 open findings.
- `NAV002`: 0 open findings.
- `NAV003`: 0 open findings.
- Hard-cutover scanner: pass (no migration-layer references in active code paths).

### Cleanup completed

1. Runtime: feature flag evaluators, registries, and migration override settings removed from active source.
2. Test/CI: migration API tests removed; telemetry/policy/parity guardrail coverage retained.
3. Governance: deprecated kill-switch artifacts archived.
4. Release evidence: policy/parity/guardrails/mod02 artifacts regenerated for current release snapshot.

### Rollback strategy

- Standard release rollback process (no runtime kill switch).
- Technical owner: Mobile Platform Team.
- Rollout go/no-go owner: Engineering Manager.
- Every release candidate must pass policy + parity + release evidence gates.

---

## Test and observability requirements

### UI test coverage

- Modal open/edit/cancel/return flow.
- Dirty-dismiss confirmation behavior.
- Compact and large device variants.

### Snapshot test coverage

- Modal-open and post-dismiss states for priority flows.
- Parity-reviewed journeys per platform.

### Analytics events

| Event | Required properties | Source screen/flow |
|-------|--------------------|--------------------|
| `nav_flow_started` | `journey_id`, `platform`, `entry_point` | all 5 parity journeys |
| `nav_flow_completed` | `journey_id`, `platform`, `duration_ms`, `result` | all 5 parity journeys |
| `nav_cancelled` | `journey_id`, `platform`, `is_dirty`, `cancel_stage` | modal/dialog flows |
| `nav_discard_confirmed` | `journey_id`, `platform`, `form_type` | dirty-dismiss flows |
| `nav_recovery_completed` | `journey_id`, `platform`, `recovery_path`, `success` | validation/recovery paths |

### Metric guardrails (release gate)

| Metric | Alert threshold | Severity | Owner | Action window |
|--------|----------------|----------|-------|---------------|
| Completion rate | drop > 2 pp vs baseline | High | Product Analytics | 24h |
| Cancel-to-retry rate | increase > 10% relative vs baseline | Medium | Product Analytics + UX Lead | 48h |
| Time-to-success (P50) | regression > 10% vs baseline | Medium | iOS Lead + Android Lead | 48h |
| Recovery success rate | below 95% | High | Product Analytics + Engineering Manager | 24h |

---

## File locations

| Component | Path |
|-----------|------|
| iOS navigation policy checker | `scripts/check_navigation_policy.py` |
| Android parity checker | `scripts/check_android_navigation_parity_matrix.py` |
| MOD-02 compact artifact gate | `scripts/check_mod02_compact_artifacts.py` |
| Hard cutover scanner | `scripts/check_navigation_hard_cutover.py` |
| CI workflow | `.github/workflows/navigation-policy-gates.yml` |
| CI parser ADR | `docs/design/ADR-NAV-CI-PARSER-001.md` |
| Policy allowlist | `docs/testing/navigation-policy-allowlist.v1.json` |
| Migration ledger | `docs/runbooks/navigation-migration-ledger.csv` |
| Release governance runbook | `docs/runbooks/navigation-release-governance.md` |

---

## Related documentation

- [Architecture](ARCHITECTURE.md) - iOS system architecture and design patterns
- [Monthly Planning](MONTHLY_PLANNING.md) - Planning flow navigation context
- [Visual System Unification](VISUAL_SYSTEM_UNIFICATION.md) - Visual token system and CI gates
- [Style Guide](STYLE_GUIDE.md) - Documentation conventions

---

*Last updated: 2026-03-04*
