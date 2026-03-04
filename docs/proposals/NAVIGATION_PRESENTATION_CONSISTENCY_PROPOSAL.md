# Navigation and Presentation Consistency Proposal

> Audit mapping: issue #7 (mixed navigation/presentation patterns)

| Metadata | Value |
|---|---|
| Status | Draft |
| Last Updated | 2026-03-03 |
| Platform | iOS + Android |
| Scope | Navigation containers, modal/dialog policy, transition rules, CI enforcement, rollout governance |
| Owners | iOS Lead, Android Lead, Product Design Lead, Mobile Platform Team |
| Baseline Snapshot | 2026-03-03 (`rg` inventory from evidence pack R4) |

---

## 1) Problem

Different modules currently mix `NavigationView`, `NavigationStack`, legacy `ActionSheet`, and inconsistent modal styles (`.sheet` vs `.fullScreenCover`) in comparable flows.
This creates:
- inconsistent user expectations in finance-critical actions,
- higher regression risk during refactors,
- weak cross-platform parity guarantees.

Current baseline from evidence pack:
- iOS `NavigationView` usage in views: 26 hits.
- iOS `.actionSheet`/`ActionSheet` usage: 2 hits.
- iOS `.confirmationDialog` usage: 4 hits.
- iOS `.sheet` usage: 38 hits.
- iOS `.fullScreenCover` usage: 2 hits.

## 2) Goal

Define one executable navigation/presentation policy per platform and enforce it across feature modules with measurable rollout and CI gates.

Target outcomes:
- predictable modal behavior per user intent,
- zero legacy APIs in active iOS views,
- journey-level parity for top recurring iOS/Android flows.

## 2.1) Scope Boundaries

In scope:
- iOS active-source migration from `NavigationView`/`ActionSheet` patterns.
- iOS modal consistency via decision IDs `MOD-01...MOD-05`.
- Android parity hardening for the top 5 shared journeys.
- CI, lint, and release-gate definitions for navigation/presentation policy.

Out of scope for this proposal revision:
- full iPad redesign beyond minimum appendix defaults for `MOD-01...MOD-05`.
- visual redesign unrelated to navigation/presentation behavior.
- non-mobile platforms (macOS/visionOS).

## 2.2) Best-Practice Basis

This proposal follows platform and UX best practices validated in evidence pack R4:
- Apple SwiftUI navigation modernization (`NavigationStack`).
- Apple guidance for contextual actions and preserving user focus in modal interactions.
- Android Compose recommendation to centralize navigation with one `NavHost`.
- Material 3 consistency guidance for semantic component behavior.
- Financial UX trust lens: deterministic cancel/recovery behavior in money-related flows.

Reference pack:
- `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL_EVIDENCE_PACK_R4.md`

iPad follow-up artifact plan:
- target artifact: `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_IPAD_APPENDIX.md`
- owner: Product Design Lead + iOS Lead
- target date: 2026-03-17 (before first “Next” wave release candidate)

## 3) iOS Architecture Policy

- Root container for active iOS views: `NavigationStack` only.
- Legacy `NavigationView` is forbidden in active source paths (preview/test allowlist only).
- Route-state ownership model:
  - App-level route transitions use coordinator path state.
  - Feature-local stacks are allowed for intra-feature drill-down only.
  - Mixed ownership in one flow requires explicit ADR exception.
- Action selection uses `confirmationDialog` (legacy `ActionSheet` forbidden).

## 4) iOS Presentation Contract

All modal/dialog call-sites must reference one decision ID below.

| Decision ID | Use Case | API | Presentation Rules |
|---|---|---|---|
| MOD-01 | Quick pick / lightweight form | `.sheet` | Title inline, dismiss by swipe allowed when form is clean, detents `.medium/.large` when content permits. |
| MOD-02 | Keyboard-heavy numeric input (budget/planning edits) | `.sheet` | Default large detent, explicit keyboard dismiss control, `interactiveDismissDisabled(isDirty)`. |
| MOD-03 | Multi-step guided commit flow | `.fullScreenCover` | Full-screen with persistent progress/context; explicit Cancel + primary action in toolbar. |
| MOD-04 | Destructive or irreversible choice | `confirmationDialog` | Clear destructive labeling, cancel always present, no silent fallback behavior. |
| MOD-05 | Blocking validation failure requiring immediate correction | `.sheet` or in-flow blocking panel | Must preserve context and explain recovery action; style must not change by runtime/test mode. |

Standard toolbar/action anatomy (iOS):
- leading: Back/Cancel,
- trailing: primary CTA (Save/Continue/Confirm),
- destructive actions never share primary visual emphasis with safe actions.

Compact overflow rules (required for `MOD-01...MOD-05`):
| Decision ID | Title Behavior | Button Priority | Secondary Action Strategy |
|---|---|---|---|
| MOD-01 | Single-line title; truncate tail if needed. | Primary action always visible in toolbar. | Secondary actions move into contextual menu if width is constrained. |
| MOD-02 | Short semantic title only (no dynamic numeric payload in title). | `Save`/`Apply` is pinned and never collapses. | `Cancel` remains explicit; tertiary actions move below form or into menu; keyboard toolbar fallback must expose `Done` + primary action when keyboard is up. |
| MOD-03 | Progress title may wrap to 2 lines max. | Commit CTA pinned; Back/Cancel pinned. | Non-critical helper actions move to overflow menu. |
| MOD-04 | Short decision prompt with explicit destructive label. | Destructive and Cancel always visible. | No tertiary controls in dialog. |
| MOD-05 | Error title + one-line recovery hint. | Primary recovery action pinned. | Alternate recovery actions collapse to list row/menu. |

Transition behavior contract (all iOS modal flows):
- Present/dismiss animations use platform-default timing (no custom animation overrides in v1).
- Keyboard-heavy forms must provide deterministic keyboard dismiss affordance.
- Dismiss result must preserve orientation: user returns to the same logical context anchor.
- Interrupted drag-dismiss on dirty form must bounce back to the current modal state, then show discard confirmation (`Keep Editing` / `Discard`).

`MOD-02` compact hierarchy and truncation policy (normative):
- priority order: `primary CTA` > `cancel/back` > `secondary text/helpers`.
- primary CTA never truncates, collapses, or moves off-screen.
- title truncates tail at 1 line before any primary action layout compromise.
- secondary helper text may collapse into overflow/menu first.

## 5) Dismissal and Unsaved-Change Policy

- Dirty financial forms (edited but uncommitted) must intercept dismiss/back/drag.
- Required confirmation on dirty dismiss:
  - `Keep Editing` (default),
  - `Discard` (destructive).
- No silent data loss on cancel.
- After discard/cancel, the parent screen must show deterministic state (no partial application).

Dirty-state contract (all guarded forms):
- A form is dirty only when canonicalized persisted fields change (`initialCanonical != currentCanonical`).
- Non-persistent UI state (focus, keyboard visibility, temporary scroll position) never marks dirty.
- Async preview calculations do not mark dirty unless they modify persisted fields.
- Reverting edited fields back to canonical initial value clears dirty state.

Dirty-state matrix (minimum coverage):
| Form | Canonical Fields | Dirty Trigger | Dirty Clear Rule | Owner |
|---|---|---|---|---|
| Budget edit | amount, frequency, currency | any canonical field mutation | all canonical fields equal baseline | Planning team |
| Goal edit | target amount, deadline, title | any canonical field mutation | all canonical fields equal baseline | Goals team |
| Contribution edit | execution amount/date/type | any canonical field mutation | all canonical fields equal baseline | Execution team |

Canonicalization examples (required for deterministic dirty-state behavior):
| Form | Baseline Canonical | Edited Input | Canonicalized Edit | Dirty? | Reverted Input | Canonicalized Revert | Dirty After Revert? |
|---|---|---|---|---|---|---|---|
| Budget edit | `{amount: 100.00, frequency: monthly, currency: USD}` | `100`, `monthly`, `usd` | `{amount: 100.00, frequency: monthly, currency: USD}` | No | `100.00`, `monthly`, `USD` | `{amount: 100.00, frequency: monthly, currency: USD}` | No |
| Goal edit | `{title: "Emergency Fund", target: 5000.00, deadline: 2026-12-31}` | `Emergency Fund ` (trailing space) | `{title: "Emergency Fund", target: 5000.00, deadline: 2026-12-31}` | No | `Emergency Fund` | `{title: "Emergency Fund", target: 5000.00, deadline: 2026-12-31}` | No |
| Contribution edit | `{amount: 250.00, date: 2026-03-01, type: manual}` | `250.0`, `2026-03-01`, `manual` | `{amount: 250.00, date: 2026-03-01, type: manual}` | No | `250.00`, `2026-03-01`, `manual` | `{amount: 250.00, date: 2026-03-01, type: manual}` | No |

## 6) Android Parity Hardening

- Android remains on single `NavHost` graph + centralized route definitions.
- Android must implement equivalent journey behavior for iOS decision IDs (MOD-01...MOD-05), even if UI primitives differ.
- Compose Material 3 dialogs/sheets must follow the same intent/risk semantics as iOS.

Top parity journeys (release-gated):
1. Goal create/edit.
2. Monthly budget adjust.
3. Destructive delete confirmation.
4. Goal contribution edit/cancel.
5. Planning flow cancel/recovery.

Parity script template (must be executable on iOS and Android):
- Step 1: Entry preconditions and launch point.
- Step 2: Primary action path.
- Step 3: Cancel path.
- Step 4: Validation error path.
- Step 5: Recovery path.
- Step 6: Confirmation/final state assertion.

Parity scripts by journey:
| Journey | Entry | Action | Cancel | Validation Error | Recovery | Confirmation |
|---|---|---|---|---|---|---|
| Goal create/edit | Open goal editor from dashboard/goals list | Edit required fields and continue | Cancel at mid-edit | Submit invalid target/deadline combo | Fix fields and retry | Parent screen state matches chosen action |
| Monthly budget adjust | Open planning budget modal | Change amount and save | Cancel after mutation | Submit unsupported/invalid amount format | Resolve validation hint and retry save | Budget card reflects saved or unchanged state |
| Destructive delete confirmation | Trigger delete from detail/list | Confirm destructive action | Cancel destructive action | Trigger delete when dependency constraint exists | Resolve constraint path then retry | Entity removed only after explicit confirm |
| Goal contribution edit/cancel | Open contribution editor | Adjust amount/date and save | Cancel after mutation | Submit invalid amount/date combination | Use discard/keep-editing branches and correction flow | Contribution list/history reflects expected state |
| Planning flow cancel/recovery | Open planning modal flow | Start critical edit and pause | Attempt dismiss mid-edit | Trigger validation failure during commit | Resolve through recovery action | Planning screen orientation/context preserved |

## 7) Enforcement and CI

- CI check (owned by Mobile Platform Team) fails PRs on forbidden iOS APIs in active paths:
  - forbidden: `NavigationView`, `.actionSheet`, `ActionSheet`.
  - scope: `ios/CryptoSavingsTracker/Views/**`, `ios/CryptoSavingsTracker/Navigation/**`.
- Parser implementation ADR is required and authoritative for CI behavior:
  - see Appendix 12.3 `CI Parser ADR`.
- Forbidden-API lint must be syntax-aware for mixed files:
  - exclude tokens inside `#Preview { ... }` blocks,
  - exclude `PreviewProvider` declarations,
  - evaluate all other declarations in the same file as active code.
- Fallback strategy if syntax parser is unavailable for a file:
  - require preview code in dedicated preview-only files (`*Preview*.swift`) before merge.
- CI output must include file/line and failed rule ID.
- Android parity CI check validates top-journey matrix coverage in `android/app/src/main/java/**/presentation/**/`.
- CI policy job IDs:
  - `policy-nav-ios-forbidden-apis`
  - `policy-nav-android-parity-matrix`
  - `policy-nav-mod02-compact-snapshots`
- Current implementation artifacts:
  - workflow: `.github/workflows/navigation-policy-gates.yml`,
  - iOS policy checker: `scripts/check_navigation_policy.py`,
  - Android parity checker: `scripts/check_android_navigation_parity_matrix.py`,
  - `MOD-02` compact artifact gate: `scripts/check_mod02_compact_artifacts.py`.
- Compact screenshot artifact gate (modal-flow changes only):
  - applies when PR touches files mapped to `MOD-02`,
  - requires both compact baseline and updated snapshot diff artifacts,
  - PR fails when artifacts are missing or diff exceeds approved threshold.
- Decision-ID mapping is machine-checkable in code:
  - every modal/dialog call-site must include nearby annotation `// NAV-MOD: MOD-xx`,
  - CI verifies annotation exists and matches a valid decision ID.
- Temporary allowlist policy (migration waves):
  - active file: `docs/testing/navigation-policy-allowlist.v1.json`,
  - each exemption must be removed when module migration reaches “Later” wave completion.
- PR template additions:
  - decision ID per new modal (`MOD-xx`),
  - parity impact (`iOS only` / `Android only` / `both`),
  - accessibility checklist confirmation.

## 8) Accessibility Contract

- Minimum tappable target for interactive controls: 44x44 pt (or platform-equivalent).
- Primary actions require explicit VoiceOver/TalkBack labels.
- Critical states must not rely on color-only differentiation.
- Dynamic type must keep primary actions visible and non-overlapping on compact devices.

## 9) Migration Governance and Rollout

Create and maintain a migration ledger with fields:
- `file`,
- `legacy API`,
- `decision ID target`,
- `owner`,
- `target release`,
- `status`.

Current ledger artifact:
- `docs/runbooks/navigation-migration-ledger.csv`
- `docs/runbooks/navigation-preview-segregation-backlog.csv` (for `NAV003` fallback cleanup)

Implementation status snapshot (2026-03-03):
- `NAV001`: 0 open findings in policy report.
- `NAV002`: 0 open findings in policy report.
- `NAV003`: 0 open findings in policy report.

Rollout waves:

1. Now (0-2 weeks)
- Build migration ledger from baseline inventory.
- Assign owners for all current legacy call-sites.
- Land CI gate + allowlist policy.
- Publish v1 modal decision matrix examples for Planning, Dashboard, Goals.

2. Next (2-6 weeks)
- Migrate iOS modules in order: `Planning` -> `Dashboard` -> `Goals`.
- Add dirty-dismiss confirmations on financial forms.
- Execute parity checklist for top 5 journeys (iOS + Android).

3. Later (6+ weeks)
- Complete remaining legacy cleanup.
- Remove temporary allowlist entries as modules migrate.
- Finalize route ownership ADR and enforce in architecture review.

Rollout safety:
- Use module-level kill switches for migration waves (`planning`, `dashboard`, `goals`).
- Chosen mechanism: local feature registry with remote override.
  - registry key namespace: `nav.migration.<module>`.
  - default behavior on startup/network failure: fail-safe to previous stable behavior (`OFF` for not-yet-validated wave).
  - override source priority: local emergency override > remote config value > compiled default.
- Ownership:
  - technical owner: Mobile Platform Team,
  - rollout go/no-go owner: Engineering Manager.
- Each wave must support tested enable/disable path in staging and documented production rollback runbook.

Burn-down targets:
| Milestone | `NavigationView` (active iOS) | `ActionSheet` (active iOS) | Decision-ID Mapping Coverage |
|---|---:|---:|---:|
| Baseline (2026-03-03) | 26 | 2 | 0% |
| End of Now | <= 18 | 0 | >= 60% |
| End of Next | <= 6 | 0 | >= 90% |
| End of Later | 0 | 0 | 100% |

## 10) Test and Observability Requirements

- UI tests must cover:
  - modal open/edit/cancel/return flow,
  - dirty-dismiss confirmation behavior,
  - compact and large device variants.
- Snapshot tests must cover:
  - modal-open and post-dismiss states for priority flows,
  - parity-reviewed journeys per platform.
- Instrument product metrics:
  - completion rate (budget edit, goal edit),
  - cancel-to-retry rate,
  - time-to-success,
  - recovery success after validation/cancel paths.

Metric guardrails (release gate):
- completion rate: no regression worse than 2 percentage points vs baseline.
- cancel-to-retry rate: no increase above 10% relative vs baseline.
- time-to-success (P50): no regression worse than 10% vs baseline.
- recovery success rate: >= 95% for guarded journeys.

Alert thresholds (release-blocking):
| Metric | Alert Threshold | Severity | Owner | Action Window |
|---|---|---|---|---|
| completion rate | drop > 2 percentage points vs baseline | High | Product Analytics | 24h |
| cancel-to-retry rate | increase > 10% relative vs baseline | Medium | Product Analytics + UX Lead | 48h |
| time-to-success (P50) | regression > 10% vs baseline | Medium | iOS Lead + Android Lead | 48h |
| recovery success rate | below 95% | High | Product Analytics + Engineering Manager | 24h |

Analytics event contract (required for guardrail gating):
| Event | Required Properties | Source Screen/Flow | Owner | Dashboard |
|---|---|---|---|---|
| `nav_flow_started` | `journey_id`, `platform`, `entry_point` | all 5 parity journeys | Product Analytics | Navigation Guardrails |
| `nav_flow_completed` | `journey_id`, `platform`, `duration_ms`, `result` | all 5 parity journeys | Product Analytics | Navigation Guardrails |
| `nav_cancelled` | `journey_id`, `platform`, `is_dirty`, `cancel_stage` | modal/dialog flows | iOS Lead + Android Lead | Navigation Guardrails |
| `nav_discard_confirmed` | `journey_id`, `platform`, `form_type` | dirty-dismiss flows | iOS Lead | Navigation Guardrails |
| `nav_recovery_completed` | `journey_id`, `platform`, `recovery_path`, `success` | validation/recovery paths | Product Analytics | Navigation Guardrails |

Guardrail release sign-off ownership:
- joint sign-off required from `Product Analytics` and `Mobile Platform Team` for every wave go/no-go.
- release-governance ceremony and artifact contract:
  - see Appendix 12.4 `Release Governance Runbook Template`,
  - escalation owner for sign-off deadlock: Engineering Manager.

## 11) Acceptance Criteria

- 100% of active iOS views use `NavigationStack` (no active `NavigationView` usage).
- 0 legacy `ActionSheet` usage in active source paths.
- 100% modal/dialog call-sites are mapped to `MOD-01...MOD-05`.
- 100% modal/dialog call-sites include machine-checkable annotation `// NAV-MOD: MOD-xx`.
- CI gate blocks new forbidden API usage with actionable file/line output and keeps false positives below 1% over one release cycle.
- Top 5 parity journeys pass iOS/Android checklist for navigation + presentation behavior.
- All `MOD-02` compact-device screenshots pass with no clipped/truncated primary controls.
- PRs touching `MOD-02` mapped flows fail if compact screenshot artifacts are missing or regressed.
- Dirty-dismiss tests pass for all targeted financial forms (no silent state loss).
- Drag-dismiss on dirty forms always bounces back and shows discard confirmation before state change.
- Accessibility checklist passes for migrated modules (touch target, labels, dynamic type, non-color cues).
- Kill-switch enable/disable path is tested in staging and documented per module.
- Navigation Guardrails dashboard is live; outcome metric guardrails from Section 10 are met for two consecutive releases.
- iPad appendix defaults (`MOD-01...MOD-05`) are published before rollout enters the “Next” wave.
- CI parser ADR is approved and linked from Section 7.
- One release-governance dry run is completed using Appendix 12.4 runbook before first “Next” wave RC.

## 12) Appendices

### 12.1 iPad Minimum Defaults (Required Before “Next” Wave)

| Decision ID | iPad Default Container | Dismiss Rule | Notes |
|---|---|---|---|
| MOD-01 | Popover preferred; fallback `.sheet` when content exceeds popover affordance | Tap outside allowed only when clean | Keep initiating context visible where possible |
| MOD-02 | `.sheet` with large-form presentation | Dirty state blocks dismiss and triggers confirmation | Keyboard + CTA must remain visible in regular width |
| MOD-03 | `.fullScreenCover` only for true multi-step commit | Explicit cancel/confirm required | Preserve progress context and confirmation state |
| MOD-04 | `confirmationDialog` anchored to invoking control | Cancel always visible | Destructive action visually isolated |
| MOD-05 | In-flow blocking panel or sheet based on severity | No silent dismiss during unresolved blocking validation | Recovery path must be explicit and testable |

Published appendix artifact:
- `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_IPAD_APPENDIX.md`

### 12.2 CI Implementation Notes

- iOS forbidden-API check uses syntax-aware parsing for mixed files.
- If syntax parsing fails, preview code must be split into dedicated preview files before merge.
- Decision-ID annotation check runs in CI and fails if missing or invalid.
- Implementation entry points:
  - `scripts/check_navigation_policy.py`
  - `.github/workflows/navigation-policy-gates.yml`

### 12.3 CI Parser ADR

ADR ID: `ADR-NAV-CI-PARSER-001`  
Status: Accepted (2026-03-03)  
Owner: Mobile Platform Team

Authoritative ADR document:
- `docs/design/ADR-NAV-CI-PARSER-001.md`

Tool choice:
- Primary parser: `SwiftSyntax`-based scanner for iOS UI source files.
- Fallback behavior: if parser fails, CI requires preview extraction to `*Preview*.swift` before merge.

Failure modes and behavior:
- Parser failure (syntax or tool crash): mark check as failed with actionable remediation hint.
- Unknown node type: treat as conservative fail and request manual review.
- Missing `NAV-MOD` annotation near modal call-site: fail with file/line and expected pattern.

Output contract:
- Always emit: `file`, `line`, `rule_id`, `suggested_fix`.
- Rule IDs: `NAV001` forbidden API, `NAV002` missing decision tag, `NAV003` preview segregation fallback.

Approval path:
- Approver group: Mobile Platform Team lead + iOS Lead.
- Change management: ADR updates require recorded rationale in PR description.

### 12.4 Release Governance Runbook Template

Runbook ID: `RUNBOOK-NAV-RELEASE-GATE-001`

Required inputs:
- Section 10 dashboard snapshot (all guardrail metrics),
- rollback drill evidence for each migrated module wave,
- compact `MOD-02` screenshot diff report,
- parity script pass/fail artifacts for top-5 journeys.

Approvers:
- Product Analytics (metrics sign-off),
- Mobile Platform Team (policy/CI sign-off),
- Engineering Manager (final go/no-go owner).

SLA:
- review window: 24h before RC cut,
- unresolved blocker decision: within 12h escalation window.

Escalation:
- if Product Analytics and Mobile Platform Team disagree, Engineering Manager is tie-break owner.

Dry-run requirement:
- at least one full rehearsal go/no-go using this runbook before first “Next” wave RC.

Published runbook artifact:
- `docs/runbooks/navigation-release-governance.md`

### 12.5 Best-Practice Sources

- [SwiftUI NavigationStack (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/10054/)
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [HIG Going Full Screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen)
- [Jetpack Compose Navigation](https://developer.android.com/develop/ui/compose/navigation)
- [Android Navigation3 Releases](https://developer.android.com/jetpack/androidx/releases/navigation3)
- [Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)
- [CFPB supervisory report harm context (2025-01-07)](https://www.consumerfinance.gov/about-us/newsroom/cfpb-highlights-harms-of-medical-and-banking-credit-products-in-new-supervisory-report/)
- [CFPB issue spotlight (2023-05-30)](https://www.consumerfinance.gov/about-us/newsroom/cfpb-issue-spotlight-highlights-financial-consequences-of-illness-and-injury/)

## 13) Definition of Green (Exit Criteria)

Proposal review status moves from Amber to Green when all are true:
1. `policy-nav-ios-forbidden-apis` is syntax-aware (or preview-file split is fully enforced) and stays below 1% false positives for one release cycle.
2. Section 10 metrics are instrumented with owners, dashboards, and alert thresholds.
3. Top-5 parity journey scripts (including validation-error paths) run on iOS and Android with reproducible artifacts.
4. Kill-switch + rollback runbook is tested in staging for every migrated module wave.
