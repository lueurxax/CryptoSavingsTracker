# Visual System Unification

> Cross-platform visual token contract, component surface policy, and CI enforcement for finance-critical flows

| Metadata | Value |
|----------|-------|
| Status | ✅ Current |
| Last Updated | 2026-04-18 |
| Platform | iOS + Android |
| Audience | Developers |

---

## Table of Contents

1. [Overview](#overview)
2. [Cross-platform token contract](#cross-platform-token-contract)
3. [Surface and elevation policy](#surface-and-elevation-policy)
4. [State taxonomy and coverage matrix](#state-taxonomy-and-coverage-matrix)
5. [Accessibility, UX, and motion contracts](#accessibility-ux-and-motion-contracts)
6. [Implementation strategy](#implementation-strategy)
7. [CI gates and job ownership](#ci-gates-and-job-ownership)
8. [Performance budgets](#performance-budgets)
9. [Rollout, rollback, and governance](#rollout-rollback-and-governance)
10. [Release certification](#release-certification)
11. [File locations](#file-locations)
12. [Related documentation](#related-documentation)

---

## Overview

The visual system enforces a governed cross-platform visual token contract with explicit parity mapping, normalizes priority components to a single surface/elevation/state system, and enforces token-only visuals through CI lint, snapshot, and accessibility gates.

### Design principles

- Governed cross-platform visual token contract with explicit parity mapping.
- Priority components use a single surface/elevation/state system.
- Token-only visuals enforced through CI lint + snapshot + accessibility gates.
- Migration by complete user-flow slices to avoid mixed-language UX.

### Non-goals

- No full rebrand or typography redesign.
- No chart-specific advanced palette redesign (see Data Viz Motion ADR).
- No retroactive rewrite of all legacy screens in one release.

### Priority flows (release-blocking)

1. Monthly Planning core flow.
2. Dashboard core flow.
3. Settings critical rows with warning/error semantics.
4. Settings and Family Access (Remediation).

### Priority components

1. `planning.header_card`
2. `planning.goal_row`
3. `dashboard.summary_card`
4. `settings.section_row`
5. `goal_detail.summary_row` (AdaptiveSummaryRow)
6. `settings.cloudkit.familyAccessRow` (Wave 4)
7. `settings.cloudkit.localBridgeSyncRow` (Wave 4)

---

## Cross-platform token contract

### Source of truth

| Artifact | Path |
|----------|------|
| Token manifest | `docs/design/visual-tokens.v1.json` |
| Schema | `docs/design/schemas/visual-tokens.schema.json` |
| Schema validator | `scripts/validate_visual_tokens.py` |
| Parity checker | `scripts/check_visual_token_parity.py` |

### Contract requirements

Each role must be machine-structured:

1. `roleType` (`color` | `surface` | `elevation`)
2. `usageScope`
3. `componentScope[]`
4. `ios` + `android` platform specs
5. `parity.status` (`aligned` | `approved_variant`)

`approved_variant` requires: `approvalTicket`, `expiresAt`, `rationale`, `preExpiryCheckpointAt`, `closureIssue`.

### Semantic role mapping

Canonical parity roles maintained in `visual-tokens.v1.json`:

1. `interactive.primary`
2. `interactive.secondary`
3. `status.success`
4. `status.warning`
5. `status.error`
6. `text.secondary`
7. `surface.base`
8. `elevation.card`
9. `elevation.raised`
10. `elevation.modal`

### Token policy

1. Presentation code must not introduce raw visual literals for color/shadow/elevation outside approved token modules.
2. Platform-specific value variance is allowed only through `approved_variant` contract entries.
3. Any expired `approved_variant` fails parity check.
4. Roles marked `aligned` must match field-level platform specs for their `roleType`.
5. Any `approved_variant` with <=30 days to expiry must include `closurePullRequest` in token parity metadata.

---

## Surface and elevation policy

| Component | Context | Allowed surface | Border | Elevation | Forbidden |
|-----------|---------|----------------|--------|-----------|-----------|
| Planning header card | Finance summary | Calm material or tokenized neutral solid | 1pt token stroke | `card` | Decorative gradients in finance core |
| Goal requirement row | Dense list | Solid neutral surface | subtle separator/stroke | `none` or `card` | Per-row hard shadow literals |
| Dashboard summary card | KPI summary | Calm surface variant | token stroke optional | `card` | Custom per-card shadow recipes |
| Dashboard empty state card | Empty/instructional | Solid neutral surface | optional | `none`/`card` | High-depth decorative glass |
| Settings section row | Config list | Flat neutral surface | separators | `none` | Color-only status communication |
| Modal/sheet container | Blocking task | Modal surface | optional | `modal` | Modal elevation in standard rows |

Decision: finance content uses calm surfaces by default; stronger glass depth is limited to navigation chrome/non-critical affordances.

---

## State taxonomy and coverage matrix

### Required states (all priority components, both platforms)

1. `default`
2. `pressed`
3. `disabled`
4. `error`
5. `loading`
6. `empty`
7. `stale`
8. `recovery`

### Coverage artifact

`docs/design/visual-state-matrix.v1.json`

### Milestone phase policy

| Milestone | Required state status | Command |
|-----------|----------------------|---------|
| `design-complete` | all required states must exist (`planned` or `captured`) | `python3 scripts/validate_visual_state_matrix.py --phase design-complete` |
| `qa-complete` | `default`, `error`, `loading`, `recovery` must be `captured` | `python3 scripts/validate_visual_state_matrix.py --phase qa-complete` |
| `release-candidate` | all 8 states must be `captured` with real artifact files | `python3 scripts/validate_visual_state_matrix.py --phase release-candidate --require-artifact-files` |

---

## Accessibility, UX, and motion contracts

### Accessibility checklist (blocking)

1. WCAG AA contrast: normal text >= 4.5:1, large text >= 3:1.
2. Non-text essential UI contrast >= 3:1.
3. No color-only status semantics.
4. Dynamic Type / large text: no clipped critical finance copy, minimum touch targets 44x44 pt (iOS), 48x48 dp (Android).
5. VoiceOver/TalkBack labels are explicit and consequence-aware.
6. Use AccessibleColors tokens in remediated views instead of drifting to standard system colors where an accessible token exists.

### UX success metrics

| Metric | Event(s) | Wave pass threshold | Sample requirement | Owner |
|--------|----------|--------------------|--------------------|-------|
| Status comprehension time | `vsu_status_card_impression` -> `vsu_status_explainer_open` | P50 time <= 12s and >=15% improvement vs baseline | >=12 participants, >=60 scenario tasks per wave | UX Research |
| Shortfall action accuracy | `vsu_shortfall_primary_action_tap` + scenario outcome | >=95% correct first action | >=12 participants, >=60 scenario tasks per wave | Product Design + UX |
| Warning misinterpretation rate | `vsu_warning_card_seen` + task response | <=5% misinterpretation | >=12 participants, >=60 scenario tasks per wave | UX Research |

Confidence requirement: report Wilson interval and 95% confidence level for binary metrics.

### Wave metric decision rubric

1. All three metrics must pass for wave promotion.
2. If exactly one metric fails by <=5% relative delta: Product Design + UX Research may request one-time exception (Mobile Platform Lead is final approver).
3. If any metric fails by >5% relative delta: wave promotion is blocked (no override).
4. Tie-break authority: Engineering Manager.

### Motion and transition contract

1. Press feedback: duration 100-150ms, no multi-axis bounce in finance-critical rows.
2. Loading -> recovery transitions: single-axis opacity/position, duration 150-250ms.
3. Sheet/dialog presentation: platform-native transitions, no custom spring overrides in release-blocking flows.
4. Reduced Motion: transition durations collapse to instant/snap, no decorative interpolation.

---

## Implementation strategy

### Wave order

1. **Wave 1**: Monthly Planning flow.
2. **Wave 2**: Dashboard flow.
3. **Wave 3**: Settings critical rows.
4. **Wave 4**: Settings and Family Access (Remediation).

No release may ship a partially migrated primary flow.

### Mixed-style timeline

1. Allowed only in feature branches during active wave migration.
2. Not allowed in release branch for release-blocking flows.
3. Maximum tolerated mixed period: one release cycle.

### Wave definition of done

Each wave promotion requires one artifact bundle:

1. `docs/release/visual-system/<wave>/token-parity-report.md`
2. `docs/release/visual-system/<wave>/state-coverage-report.md`
3. `docs/release/visual-system/<wave>/snapshot-diff-summary.md`
4. `docs/release/visual-system/<wave>/accessibility-report.md`
5. `docs/release/visual-system/<wave>/ux-metrics-report.md`
6. `docs/release/visual-system/<wave>/performance-report.md`
7. `docs/release/visual-system/<wave>/rollback-drill-report.md`
8. `docs/release/visual-system/<wave>/runtime-accessibility-assertions.json`
9. `docs/release/visual-system/<wave>/ux-metrics-report.json`
10. `docs/release/visual-system/<wave>/release-certification-report.json` (`releaseCertifiable=true`)
11. `docs/release/visual-system/<wave>/release-certification-summary.md`
12. `docs/release/visual-system/<wave>/runtime-accessibility-test-results.json`

Promotion rule: if any artifact is missing or marked `failed`, wave promotion is blocked.

---

## CI gates and job ownership

### Lint gates

iOS: `swiftlint --config ios/.swiftlint.yml`

Custom SwiftLint rules:
- `no_raw_swiftui_color_literal` (error)
- `no_raw_status_color_literals` (error)
- `no_ad_hoc_shadow_literals` (error)

Android: `bash scripts/check_android_visual_literals.sh`

### Baseline policy for legacy debt

1. Baseline files:
   - `docs/design/baselines/ios-visual-literals-baseline.txt`
   - `docs/design/baselines/android-visual-literals-baseline.txt`
2. Gates fail on any violation not present in baseline.
3. Baseline refresh allowed only with explicit review ticket.

### CI job names

| Job name | Command | Blocking scope | Owner |
|----------|---------|---------------|-------|
| `visual-contract-validate` | `python3 scripts/validate_visual_tokens.py` | all waves | Mobile Platform Team |
| `visual-token-parity` | `python3 scripts/check_visual_token_parity.py` | all waves | Mobile Platform Team |
| `visual-variant-expiry` | `python3 scripts/check_visual_variant_expiry.py` | all waves | Mobile Platform Lead |
| `visual-state-matrix` | `python3 scripts/validate_visual_state_matrix.py --phase design-complete` | all waves | QA Automation |
| `ios-visual-lint` | `swiftlint --config ios/.swiftlint.yml` | iOS wave changes | iOS Lead |
| `android-visual-lint` | `bash scripts/check_android_visual_literals.sh` | Android wave changes | Android Lead |
| `visual-literal-guard` | `bash scripts/check_ios_visual_literals.sh && bash scripts/check_android_visual_literals.sh` | all waves | Mobile Platform Team |
| `visual-literal-baseline-budget` | `python3 scripts/check_visual_literal_baseline_burndown.py --wave ${VISUAL_SYSTEM_WAVE}` | all waves | Mobile Platform Lead |
| `visual-accessibility` | `python3 scripts/run_visual_accessibility_checks.py --mode pr` | release-blocking flows | Accessibility Champion |
| `visual-snapshots` | `python3 scripts/run_visual_snapshot_checks.py --mode pr` | release-blocking flows | QA Automation |
| `visual-release-gates` | `bash scripts/run_visual_system_release_gates.sh` | release branches only | Mobile Platform Team + QA Automation |

### Local and CI entrypoints

```bash
bash scripts/run_visual_system_gates.sh          # PR branches
bash scripts/run_visual_system_release_gates.sh   # release branches
```

### CI workflow

Implemented in `.github/workflows/visual-system-gates.yml` (GitHub Actions).

### CI failure triage protocol

1. Any failed job requires an issue within 30 minutes with: failing job name, artifact link, owner, mitigation ETA.
2. Merge is allowed only after gate passes or approved temporary exception ticket with expiry date.

---

## Performance budgets

For release-blocking finance flows:

1. P95 frame-time regression <= 10% vs pre-wave baseline.
2. Jank rate (frames > 16.7ms) <= +2 percentage points vs baseline.
3. Mandatory traces before promotion:
   - iOS: Instruments on iPhone 16e and iPhone 17 Pro Max.
   - Android: Macrobenchmark on Pixel 8.

Failure on any budget blocks wave promotion.

---

## Rollout, rollback, and governance

### Ownership

1. Accountable owner: Mobile Platform Lead.
2. Co-approver: Design Lead.
3. Delegates: iOS Lead, Android Lead.

### Feature flags

1. `visual_system.wave1_planning`
2. `visual_system.wave2_dashboard`
3. `visual_system.wave3_settings`

Provider chain: `release default -> remote config -> debug override`.

### Rollback

- Rollback SLA: disable affected wave in <= 1 business day after confirmed regression.
- Sev1 emergency: <= 30 minutes.
- Runbook: `docs/runbooks/visual-system-rollback.md`.
- Rollback drill cadence: monthly while migration active.
- Telemetry schema: `docs/testing/visual-system-rollout-telemetry-schema.v1.json`.

### Observability events

- `vsu_flag_evaluated`
- `vsu_wave_rollback_triggered`
- `vsu_wave_rollback_completed`

### Escalation ladder

| Severity | Trigger | Response SLA | Primary | Fallback |
|----------|---------|-------------|---------|----------|
| `sev3` | Non-blocking visual gate issue | 240 min | Platform delegate | Mobile Platform Lead |
| `sev2` | Blocking gate issue on active wave PRs | 120 min | Mobile Platform Lead | Design Lead |
| `sev1` | Production-impacting visual regression | 30 min | Engineering Manager | Director of Engineering |

### Exception workflow

Every exception requires: reason, mapped semantic role, expiry milestone, owner + removal task. No indefinite exceptions.

### Exception audit cadence

1. Weekly review of all active exceptions.
2. Exceptions expiring in <=14 days must have closure PR linked or renewed approval.
3. Quarterly target: zero overdue exceptions.

---

## Release certification

### Readiness model

| Dimension | Definition | Source of truth |
|-----------|-----------|-----------------|
| `specCompleteness` | Contract/schema/gate definitions are present and unambiguous | This document + schemas/scripts |
| `operationalReadiness` | Latest release-gate evidence bundle is passable end-to-end | `artifacts/visual-system/release-certification-report.json` (`releaseCertifiable` field) |

Operational truth is controlled by artifacts, not prose.

### Canonical artifacts

| Artifact | Path |
|----------|------|
| Release certification report | `artifacts/visual-system/release-certification-report.json` |
| Certification freshness report | `artifacts/visual-system/release-certification-freshness-report.json` |
| UX metrics report | `artifacts/visual-system/ux-metrics-report.json` |
| Runtime accessibility test results | `artifacts/visual-system/runtime-accessibility-test-results.json` |
| Runtime accessibility assertions | `artifacts/visual-system/runtime-accessibility-assertions.json` |
| Human-readable summary | `artifacts/visual-system/release-certification-summary.md` |
| Published mirror | `docs/release/visual-system/latest/release-certification-report.json` |

### Freshness policy

1. `generatedAt` in certification report must be <=24h old.
2. `sourceCommitSha` must match current build commit.
3. Enforced by `python3 scripts/check_visual_release_certification_freshness.py`.
4. Production screenshot evidence `capturedAt` must be <=24h old.

### Release gate commands

```bash
python3 scripts/generate_visual_release_certification_report.py
python3 scripts/check_visual_release_certification_freshness.py
python3 scripts/generate_visual_release_certification_summary.py
python3 scripts/run_visual_accessibility_runtime_tests.py --mode release --required-test-mode full
python3 scripts/generate_runtime_accessibility_assertions.py --mode release --test-results artifacts/visual-system/runtime-accessibility-test-results.json
python3 scripts/validate_visual_performance_report.py --report docs/release/visual-system/${VISUAL_SYSTEM_WAVE}/performance-report.json
python3 scripts/validate_visual_rollback_drill_report.py --report docs/release/visual-system/${VISUAL_SYSTEM_WAVE}/rollback-drill-report.json
python3 scripts/validate_visual_wave_bundle.py --wave ${VISUAL_SYSTEM_WAVE}
```

---

## File locations

### iOS implementation

| Component | Path |
|-----------|------|
| Visual component tokens | `ios/CryptoSavingsTracker/Utilities/VisualComponentTokens.swift` |
| Accessible colors | `ios/CryptoSavingsTracker/Utilities/AccessibleColors.swift` |
| Visual system rollout flags | `ios/CryptoSavingsTracker/Utilities/VisualSystemRollout.swift` |
| SwiftLint config | `ios/.swiftlint.yml` |

### Android implementation

| Component | Path |
|-----------|------|
| Color tokens | `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/theme/Color.kt` |

### Design artifacts

| Artifact | Path |
|----------|------|
| Token manifest | `docs/design/visual-tokens.v1.json` |
| Token schema | `docs/design/schemas/visual-tokens.schema.json` |
| State matrix | `docs/design/visual-state-matrix.v1.json` |
| Snapshot baseline | `docs/design/visual-snapshot-baseline.v1.json` |
| iOS literal baseline | `docs/design/baselines/ios-visual-literals-baseline.txt` |
| Android literal baseline | `docs/design/baselines/android-visual-literals-baseline.txt` |

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/validate_visual_tokens.py` | Token contract validation |
| `scripts/check_visual_token_parity.py` | Cross-platform parity check |
| `scripts/check_visual_variant_expiry.py` | Variant expiry enforcement |
| `scripts/validate_visual_state_matrix.py` | State coverage validation |
| `scripts/run_visual_snapshot_checks.py` | Snapshot gate |
| `scripts/run_visual_accessibility_checks.py` | Accessibility gate |
| `scripts/run_visual_accessibility_runtime_tests.py` | Runtime accessibility tests |
| `scripts/generate_runtime_accessibility_assertions.py` | Assertion generation |
| `scripts/generate_visual_release_certification_report.py` | Release certification |
| `scripts/check_visual_release_certification_freshness.py` | Freshness enforcement |
| `scripts/generate_visual_release_certification_summary.py` | Human-readable summary |
| `scripts/check_visual_literal_baseline_burndown.py` | Literal debt burndown |
| `scripts/validate_visual_ux_metrics.py` | UX metrics validation |
| `scripts/validate_visual_performance_report.py` | Performance budget validation |
| `scripts/validate_visual_rollback_drill_report.py` | Rollback drill validation |
| `scripts/validate_visual_wave_bundle.py` | Wave bundle completeness |
| `scripts/run_visual_system_gates.sh` | PR gate entrypoint |
| `scripts/run_visual_system_release_gates.sh` | Release gate entrypoint |

### Runbooks

| Runbook | Path |
|---------|------|
| Visual system rollback | `docs/runbooks/visual-system-rollback.md` |

### CI

| Workflow | Path |
|----------|------|
| Visual system gates | `.github/workflows/visual-system-gates.yml` |

---

## Related documentation

- [Navigation Presentation Consistency](NAVIGATION_PRESENTATION_CONSISTENCY.md) - Navigation and modal policy
- [Monthly Planning Budget Health Widget](MONTHLY_PLANNING_BUDGET_HEALTH_WIDGET.md) - Budget health card visual specification
- [Architecture](ARCHITECTURE.md) - iOS system architecture
- [Data Viz Motion ADR](proposals/DATA_VIZ_MOTION_ADR.md) - Chart-specific motion semantics
- [Style Guide](STYLE_GUIDE.md) - Documentation conventions

---

*Last updated: 2026-04-18*
