# Visual System Unification Proposal

> Audit mapping: issue #10 (inconsistent visual language)

| Metadata | Value |
|---|---|
| Status | Revised after triad reviews R1 + R2 + R3 + R4 + R5 + R6 + R7 + R8 |
| Last Updated | 2026-03-03 |
| Platform | iOS + Android |
| Scope | Visual tokens, component surfaces, depth/emphasis rules, enforcement gates |
| Review Inputs | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL_TRIAD_REVIEW_R1.md`, `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL_TRIAD_REVIEW_R2.md`, `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL_TRIAD_REVIEW_R3.md`, `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL_TRIAD_REVIEW_R4.md`, `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL_TRIAD_REVIEW_R5.md`, `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL_TRIAD_REVIEW_R6.md`, `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL_TRIAD_REVIEW_R7.md`, `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL_TRIAD_REVIEW_R8.md` |

---

## 0) Readiness Model (Spec vs Operational)

Dual-status model is mandatory to prevent "document complete" from being read as "release ready".

| Dimension | Definition | Current Status (2026-03-03) | Source of Truth |
|---|---|---|---|
| `specCompleteness` | Contract/schema/gate definitions are present and unambiguous in repository docs/scripts. | `green` | This proposal + schemas/scripts in sections 4-12 |
| `operationalReadiness` | Latest release-gate evidence bundle is passable end-to-end for release-blocking flows. | `derived` (do not hardcode) | `artifacts/visual-system/release-certification-report.json` (`releaseCertifiable` field) |

Operational truth is controlled by artifacts, not prose:

1. Canonical run output: `artifacts/visual-system/release-certification-report.json`
2. Canonical freshness report: `artifacts/visual-system/release-certification-freshness-report.json`
3. Canonical UX metrics input for release validation: `artifacts/visual-system/ux-metrics-report.json`
4. Canonical runtime accessibility evidence:
   - `artifacts/visual-system/runtime-accessibility-test-results.json`
   - `artifacts/visual-system/runtime-accessibility-assertions.json`
5. Repository mirror (published from artifacts, non-authoritative): `docs/release/visual-system/latest/release-certification-report.json`
6. First-green reference: `docs/release/visual-system/latest/FIRST_GREEN_RELEASE_REHEARSAL.md`
7. Human-readable status snapshot: `artifacts/visual-system/release-certification-summary.md`

Freshness policy for operational readiness:

1. `generatedAt` in certification report must be <=24h old.
2. `sourceCommitSha` must match current build commit.
3. Freshness is enforced by `python3 scripts/check_visual_release_certification_freshness.py`.
4. Summary markdown is generated from canonical JSON artifacts (no manual edits):
   - `python3 scripts/generate_visual_release_certification_summary.py`.
5. Production screenshot evidence freshness in release mode:
   - `capturedAt` in production manifest must be <=24h old.

## 1) Problem

Current finance-critical flows use mixed visual primitives across screens:

- mixed material usage and card depth,
- raw color literals and repeated shadow constants,
- inconsistent emphasis for equivalent actions/states between iOS and Android,
- broad acceptance language without measurable CI gates.

This creates avoidable trust and comprehension risk in money flows.

## 2) Goals and Non-Goals

### 2.1 Goals

1. Define a governed cross-platform visual token contract with explicit parity mapping.
2. Normalize priority components to a single surface/elevation/state system.
3. Enforce token-only visuals through CI lint + snapshot + accessibility gates.
4. Migrate by complete user-flow slices to avoid mixed-language UX.

### 2.2 Non-Goals

1. No full rebrand or typography redesign in this proposal.
2. No chart-specific advanced palette redesign in this document.
3. No retroactive rewrite of all legacy screens in one release.

---

## 3) Priority Flows and Components

### 3.1 Release-blocking flows

If visual snapshot/accessibility checks fail, release is blocked for:

1. Monthly Planning core flow.
2. Dashboard core flow.
3. Settings critical rows with warning/error semantics.

### 3.2 Priority components

1. `planning.header_card`
2. `planning.goal_row`
3. `dashboard.summary_card`
4. `settings.section_row`

---

## 4) Cross-Platform Token Contract

### 4.1 Source of truth

Contract artifacts:

1. Token manifest: `docs/design/visual-tokens.v1.json`
2. Schema: `docs/design/schemas/visual-tokens.schema.json`
3. Schema validator: `scripts/validate_visual_tokens.py`
4. Parity checker: `scripts/check_visual_token_parity.py`

Executable checks:

```bash
python3 scripts/validate_visual_tokens.py
python3 scripts/check_visual_token_parity.py
```

### 4.2 Contract requirements

Each role must be machine-structured (no free-form semantic mapping):

1. `roleType` (`color`|`surface`|`elevation`)
2. `usageScope`
3. `componentScope[]`
4. `ios` + `android` platform specs
5. `parity.status` (`aligned`|`approved_variant`)

`approved_variant` requires:

1. `approvalTicket`
2. `expiresAt`
3. `rationale`
4. `preExpiryCheckpointAt`
5. `closureIssue`

### 4.3 Semantic role mapping

Canonical parity roles are maintained in `visual-tokens.v1.json`:

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

### 4.4 Token policy

1. Presentation code must not introduce raw visual literals for color/shadow/elevation outside approved token modules.
2. Platform-specific value variance is allowed only through `approved_variant` contract entries.
3. Any expired `approved_variant` fails parity check.
4. Roles marked `aligned` must match field-level platform specs for their `roleType` (color/surface/elevation).
5. Any `approved_variant` with <=30 days to expiry must include `closurePullRequest` in token parity metadata.

---

## 5) Surface and Elevation Policy Matrix

| Component | Context | Allowed surface | Border | Elevation | Forbidden |
|---|---|---|---|---|---|
| Planning header card | Finance summary | Calm material or tokenized neutral solid | 1pt token stroke | `card` | Decorative gradients in finance core |
| Goal requirement row | Dense list | Solid neutral surface | subtle separator/stroke | `none` or `card` | Per-row hard shadow literals |
| Dashboard summary card | KPI summary | Calm surface variant | token stroke optional | `card` | Custom per-card shadow recipes |
| Dashboard empty state card | Empty/instructional | Solid neutral surface | optional | `none`/`card` | High-depth decorative glass |
| Settings section row | Config list | Flat neutral surface | separators | `none` | Color-only status communication |
| Modal/sheet container | Blocking task | Modal surface | optional | `modal` | Modal elevation in standard rows |

Decision: finance content uses calm surfaces by default; stronger glass depth is limited to navigation chrome/non-critical affordances.

---

## 6) State Taxonomy and Coverage Matrix

Required states (all priority components, both platforms):

1. `default`
2. `pressed`
3. `disabled`
4. `error`
5. `loading`
6. `empty`
7. `stale`
8. `recovery`

Coverage artifact:

- `docs/design/visual-state-matrix.v1.json`

Validator (default `design-complete` phase):

```bash
python3 scripts/validate_visual_state_matrix.py
```

Release strict mode:

```bash
python3 scripts/validate_visual_state_matrix.py --phase release-candidate --require-artifact-files
```

### 6.1 Milestone phase policy

| Milestone | Required state status | Command |
|---|---|---|
| `design-complete` | all required states must exist (`planned` or `captured`) | `python3 scripts/validate_visual_state_matrix.py --phase design-complete` |
| `qa-complete` | `default`, `error`, `loading`, `recovery` must be `captured` | `python3 scripts/validate_visual_state_matrix.py --phase qa-complete` |
| `release-candidate` | all 8 states must be `captured` with real artifact files | `python3 scripts/validate_visual_state_matrix.py --phase release-candidate --require-artifact-files` |

---

## 7) Accessibility, UX, and Motion Contracts

### 7.1 Accessibility checklist (blocking)

1. WCAG AA contrast:
   - normal text >= 4.5:1,
   - large text >= 3:1.
2. Non-text essential UI contrast >= 3:1.
3. No color-only status semantics.
4. Dynamic Type / large text:
   - no clipped critical finance copy,
   - minimum touch targets 44x44 pt (iOS), 48x48 dp (Android).
5. VoiceOver/TalkBack labels are explicit and consequence-aware.

### 7.2 UX success metrics (operationalized)

| Metric | Event(s) | Wave pass threshold | Sample requirement | Owner |
|---|---|---|---|---|
| Status comprehension time | `vsu_status_card_impression` -> `vsu_status_explainer_open` | P50 time <= 12s and >=15% improvement vs baseline | >=12 participants and >=60 scenario tasks per wave | UX Research |
| Shortfall action accuracy | `vsu_shortfall_primary_action_tap` + scenario outcome | >=95% correct first action | >=12 participants and >=60 scenario tasks per wave | Product Design + UX |
| Warning misinterpretation rate | `vsu_warning_card_seen` + task response | <=5% misinterpretation | >=12 participants and >=60 scenario tasks per wave | UX Research |

Confidence requirement: report Wilson interval and 95% confidence level for binary metrics.

Machine validator (release gate):

```bash
python3 scripts/validate_visual_ux_metrics.py
```

Schema:

- `docs/design/schemas/visual-ux-metrics-report.schema.json`

### 7.2.1 Wave metric decision rubric

1. Default policy: all three metrics must pass for wave promotion.
2. If exactly one metric fails by <=5% relative delta:
   - Product Design + UX Research may request one-time exception,
   - Mobile Platform Lead is final approver,
   - exception must include remediation task and expiry milestone.
3. If any metric fails by >5% relative delta, wave promotion is blocked (no override).
4. Tie-break authority for interpretation disputes: Engineering Manager.

### 7.3 Motion and transition contract

1. Press feedback:
   - duration 100-150ms,
   - no multi-axis bounce in finance-critical rows.
2. Loading -> recovery transitions:
   - single-axis opacity/position,
   - duration 150-250ms.
3. Sheet/dialog presentation:
   - platform-native transitions,
   - no custom spring overrides in release-blocking flows.
4. Reduced Motion:
   - transition durations collapse to instant/snap,
   - no decorative interpolation.

Validation:

1. Motion checklist is attached to each wave signoff:
   - `docs/testing/visual-motion-accessibility-checklist.md`
2. UI tests assert reduced-motion behavior on release-blocking flows.
3. Accessibility suite includes reduced-motion + VoiceOver/TalkBack combined scenarios.
4. Runtime assertions artifact is required in release mode:
   - `artifacts/visual-system/runtime-accessibility-assertions.json`
5. Runtime assertion schema:
   - `docs/design/schemas/visual-runtime-accessibility-assertions.schema.json`
6. Runtime test-results source artifact and schema:
   - `artifacts/visual-system/runtime-accessibility-test-results.json`
   - `docs/design/schemas/visual-runtime-accessibility-test-results.schema.json`

---

## 8) Implementation Strategy (Flow Slices)

### 8.1 Wave order

1. Wave 1: Monthly Planning flow.
2. Wave 2: Dashboard flow.
3. Wave 3: Settings critical rows.

No release may ship a partially migrated primary flow.

### 8.2 Mixed-style timeline

1. Allowed only in feature branches during active wave migration.
2. Not allowed in release branch for release-blocking flows.
3. Maximum tolerated mixed period: one release cycle.

### 8.3 Wave Definition of Done (required)

Each wave promotion requires one artifact bundle:

1. `docs/release/visual-system/<wave>/token-parity-report.md`
2. `docs/release/visual-system/<wave>/state-coverage-report.md`
3. `docs/release/visual-system/<wave>/snapshot-diff-summary.md`
4. `docs/release/visual-system/<wave>/accessibility-report.md`
5. `docs/release/visual-system/<wave>/ux-metrics-report.md`
6. `docs/release/visual-system/<wave>/performance-report.md`
7. `docs/release/visual-system/<wave>/rollback-drill-report.md`
8. `docs/screenshots/review-visual-system-unification-r4/manifest.md` updated with wave evidence coverage.
9. `docs/screenshots/review-visual-system-unification-r4/production/manifest.v1.json` updated for route-level production evidence.
10. `docs/release/visual-system/<wave>/runtime-accessibility-assertions.json` attached.
11. `docs/release/visual-system/<wave>/ux-metrics-report.json` attached.
12. `docs/release/visual-system/<wave>/release-certification-report.json` attached with `releaseCertifiable=true`.
13. `docs/release/visual-system/<wave>/release-certification-summary.md` attached.
14. `docs/release/visual-system/<wave>/runtime-accessibility-test-results.json` attached (source for runtime assertions generation).

Promotion rule: if any artifact is missing or marked `failed`, wave promotion is blocked.

---

## 9) CI Gates and Job Ownership

### 9.1 Lint gates (executable)

iOS config path now exists: `ios/.swiftlint.yml`

```bash
swiftlint --config ios/.swiftlint.yml
```

Android rule config path now exists: `android/config/detekt/detekt.yml` (reserved for Detekt integration).
Current executable Android gate is repository-owned guard script:

```bash
bash scripts/check_android_visual_literals.sh
```

Guard scripts for literal checks:

```bash
bash scripts/check_ios_visual_literals.sh
bash scripts/check_android_visual_literals.sh
```

Baseline policy for legacy debt containment:

1. Baseline files:
   - `docs/design/baselines/ios-visual-literals-baseline.txt`
   - `docs/design/baselines/android-visual-literals-baseline.txt`
2. Gates fail on any violation not present in baseline.
3. Baseline refresh is allowed only with explicit review ticket and justification:

```bash
bash scripts/check_ios_visual_literals.sh --update-baseline
bash scripts/check_android_visual_literals.sh --update-baseline
```

### 9.2 Snapshot and state gates

1. State coverage gate (PR): `python3 scripts/validate_visual_state_matrix.py --phase design-complete`
2. Snapshot gate (PR): `python3 scripts/run_visual_snapshot_checks.py --mode pr`
3. Accessibility gate (PR): `python3 scripts/run_visual_accessibility_checks.py --mode pr`
4. Variant expiry gate (PR/release): `python3 scripts/check_visual_variant_expiry.py`
5. Release strict state capture: `python3 scripts/validate_visual_state_matrix.py --phase release-candidate --require-artifact-files`
6. Snapshot gate (release): `python3 scripts/run_visual_snapshot_checks.py --mode release`
7. Accessibility gate (release): `python3 scripts/run_visual_accessibility_checks.py --mode release`
8. UX metrics gate (release): `python3 scripts/validate_visual_ux_metrics.py`
9. Snapshot matrix dimensions:
   - themes: light/dark,
   - size classes: compact/regular,
   - text size: default/large,
   - states: all 8 required states.
10. Runtime capture entrypoints for state artifacts:
   - `bash scripts/capture_ios_visual_states.sh`
   - `bash scripts/capture_android_visual_states.sh`
11. Runtime capture entrypoints for production-flow evidence:
   - `bash scripts/capture_ios_production_flows.sh`
   - `bash scripts/capture_android_production_flows.sh`
12. Release snapshot gate requires:
   - baseline hash diff (`docs/design/visual-snapshot-baseline.v1.json`),
   - production-flow manifest (`docs/screenshots/review-visual-system-unification-r4/production/manifest.v1.json`),
   - production-flow manifest schema (`docs/design/schemas/visual-production-capture-manifest.schema.json`),
   - production manifest metadata: `evidenceCommitSha` + `capturedAt`,
   - required production states per flow: `default`, `error`, `recovery`,
   - duplicate ratio threshold (`<=0.20`) per platform,
   - commit binding in CI release mode: `evidenceCommitSha` must match `GITHUB_SHA`,
   - manifest freshness: `capturedAt` age must be <=24h (`--production-max-age-hours`).
13. Snapshot baseline refresh command (explicit review required):
   - `python3 scripts/run_visual_snapshot_checks.py --mode pr --update-baseline`
14. Runtime accessibility test execution + artifact materialization command:
   - `python3 scripts/run_visual_accessibility_runtime_tests.py --mode release --required-test-mode full`
   - release policy requires:
     - `testMode=full`,
     - `sourceMode=test-run`,
     - non-zero executed tests (`executedTests.total > 0` and per-platform `executedTestCount > 0`).
15. Runtime accessibility assertions generation command (source = test-results artifact):
   - `python3 scripts/generate_runtime_accessibility_assertions.py --mode release --test-results artifacts/visual-system/runtime-accessibility-test-results.json`
16. Consolidated release certification report command:
   - `python3 scripts/generate_visual_release_certification_report.py`
17. Certification freshness gate command:
   - `python3 scripts/check_visual_release_certification_freshness.py`
18. Human-readable certification summary command:
   - `python3 scripts/generate_visual_release_certification_summary.py`
19. Baseline burndown budget gate command:
   - `python3 scripts/check_visual_literal_baseline_burndown.py --wave ${VISUAL_SYSTEM_WAVE}`
   - release mode fails when `VISUAL_SYSTEM_WAVE` is missing/invalid.

### 9.3 CI job names (resolved)

| Job Name | Command | Blocking Scope | Owner |
|---|---|---|---|
| `visual-contract-validate` | `python3 scripts/validate_visual_tokens.py` | all waves | Mobile Platform Team |
| `visual-token-parity` | `python3 scripts/check_visual_token_parity.py` | all waves | Mobile Platform Team |
| `visual-variant-expiry` | `python3 scripts/check_visual_variant_expiry.py` | all waves | Mobile Platform Lead |
| `visual-state-matrix` | `python3 scripts/validate_visual_state_matrix.py --phase design-complete` | all waves | QA Automation |
| `ios-visual-lint` | `swiftlint --config ios/.swiftlint.yml` | iOS wave changes | iOS Lead |
| `android-visual-lint` | `bash scripts/check_android_visual_literals.sh` | Android wave changes | Android Lead |
| `visual-literal-guard` | `bash scripts/check_ios_visual_literals.sh && bash scripts/check_android_visual_literals.sh` | all waves | Mobile Platform Team |
| `visual-accessibility` | `python3 scripts/run_visual_accessibility_checks.py --mode pr` | release-blocking flows | Accessibility Champion |
| `visual-snapshots` | `python3 scripts/run_visual_snapshot_checks.py --mode pr` | release-blocking flows | QA Automation |
| `visual-literal-baseline-budget` | `python3 scripts/check_visual_literal_baseline_burndown.py --wave ${VISUAL_SYSTEM_WAVE}` | all waves | Mobile Platform Lead |
| `visual-release-gates` | `bash scripts/run_visual_system_release_gates.sh` | release branches only | Mobile Platform Team + QA Automation |

### 9.4 Local and CI entrypoints

```bash
bash scripts/run_visual_system_gates.sh
bash scripts/run_visual_system_release_gates.sh
bash scripts/capture_ios_production_flows.sh
bash scripts/capture_android_production_flows.sh
```

`run_visual_system_gates.sh` is mandatory for PR branches.
`run_visual_system_release_gates.sh` is mandatory for release branches and pre-cut verification.

### 9.5 CI failure triage protocol

1. Any failed job in section 9.3 requires an issue within 30 minutes, with:
   - failing job name,
   - artifact link,
   - owner,
   - mitigation ETA.
2. If failure affects release-blocking flow PRs, escalation follows section 11.5 severity table.
3. Merge is allowed only after:
   - gate passes, or
   - approved temporary exception ticket with expiry date is linked.

### 9.6 CI workflow wiring

Implemented workflow:

- `.github/workflows/visual-system-gates.yml`

CI platform: GitHub Actions.

---

## 10) Performance Budgets

For release-blocking finance flows:

1. P95 frame-time regression <= 10% vs pre-wave baseline.
2. Jank rate (frames > 16.7ms) <= +2 percentage points vs baseline.
3. Mandatory traces before promotion:
   - iOS: Instruments on iPhone 16e and iPhone 17 Pro Max.
   - Android: Macrobenchmark on Pixel 8.

Failure on any budget blocks wave promotion.

---

## 11) Rollout, Rollback, and Governance

### 11.1 Ownership

1. Accountable owner: Mobile Platform Lead.
2. Co-approver: Design Lead.
3. Delegates: iOS Lead, Android Lead.

### 11.2 Rollback operationalization

Required flags:

1. `visual_system.wave1_planning`
2. `visual_system.wave2_dashboard`
3. `visual_system.wave3_settings`

Operational rules:

1. Provider chain: `release default -> remote config -> debug override`.
2. Release defaults are `false` until wave signoff artifacts pass.
3. Rollback drill cadence: monthly while migration active.
4. Rollback SLA: disable affected wave in <= 1 business day after confirmed regression.
5. Observability events:
   - `vsu_flag_evaluated`,
   - `vsu_wave_rollback_triggered`,
   - `vsu_wave_rollback_completed`.

### 11.3 User-facing recovery behavior

Runbook: `docs/runbooks/visual-system-rollback.md`

Requirements:

1. Fallback visuals preserve status semantics and non-color cues.
2. Critical cards keep explanation copy visible during rollback.
3. No user-facing ambiguity between warning and error states.

### 11.4 Exception workflow

Every exception requires:

1. reason,
2. mapped semantic role,
3. expiry milestone,
4. owner + removal task.

No indefinite exceptions.

### 11.5 Escalation ladder (resolved)

| Severity | Trigger | Response SLA | Primary | Fallback |
|---|---|---:|---|---|
| `sev3` | Non-blocking visual gate issue | 240 min | Platform delegate | Mobile Platform Lead |
| `sev2` | Blocking gate issue on active wave PRs | 120 min | Mobile Platform Lead | Design Lead |
| `sev1` | Production-impacting visual regression | 30 min | Engineering Manager | Director of Engineering |

### 11.6 Exception audit cadence

1. Weekly review of all active exceptions (`approved_variant` + lint/snapshot bypasses).
2. Any exception expiring in <=14 days must have:
   - closure PR linked, or
   - renewed approval with new expiry and rationale.
3. Quarterly target: zero overdue exceptions.

---

## 12) Data-Viz Boundary and Motion Semantics

Chart palette remains a dedicated data-viz extension layer, but semantic thresholds must map back to shared status roles.

Chart motion semantics are tracked in dedicated ADR:

- `docs/proposals/DATA_VIZ_MOTION_ADR.md`

This proposal owns app-wide finance UI motion; chart-specific animation semantics are delegated to the ADR above.

---

## 13) Acceptance Criteria (Measurable)

1. `visual-tokens.v1.json` passes schema validation with zero errors.
2. Parity checker reports zero unresolved mismatches and zero expired variants.
3. State matrix contains all 8 states for each release-blocking component on both platforms.
4. Lint + literal guards fail on injected/new raw visual literals not in approved baseline.
5. Snapshot + accessibility gates pass for release-blocking flows.
6. UX metrics meet wave thresholds with required sample size and confidence reporting.
7. Performance budgets pass on representative device traces.
8. Rollback drill passes SLA and runbook checklist.
9. Wave artifact bundle in section 8.3 is complete and approved by listed owners.
10. Consolidated certification report marks release as certifiable:
    - `artifacts/visual-system/release-certification-report.json` has `releaseCertifiable=true`.
11. Certification freshness report passes:
    - `artifacts/visual-system/release-certification-freshness-report.json` has `passed=true`.
12. Canonical docs mirror is synchronized from artifacts during release gate run:
    - `docs/release/visual-system/latest/release-certification-report.json` matches artifact hash.
13. Runtime assertions are generated from runtime test-results artifact (not from static assertion template):
    - `artifacts/visual-system/runtime-accessibility-assertions.json` has `source.testResultsPath`.
14. Human-readable certification summary is generated from JSON artifacts:
    - `artifacts/visual-system/release-certification-summary.md`,
    - includes evidence-quality metadata (`testMode`, `requiredTestMode`, executed test counts, suite IDs).
15. Baseline burndown budget gate passes for active wave:
    - `artifacts/visual-system/literal-baseline-burndown-report.json` has `passed=true`.
    - release mode fails if `VISUAL_SYSTEM_WAVE` is missing or invalid.
16. Snapshot release gate enforces production manifest commit metadata:
    - `manifest.v1.json` contains `evidenceCommitSha` and `capturedAt`, CI release fails on commit mismatch, and `capturedAt` age exceeds max threshold.
17. Runtime accessibility release quality is full-mode and test-backed:
    - `artifacts/visual-system/runtime-accessibility-test-results.json` has `testMode=full`,
    - `requiredTestMode=full`,
    - `executedTests.total > 0`.

---

## 14) Open Questions Status (R8)

Resolved in this revision:

1. Exact CI platform and workflow wiring: section 9.6.
2. Strict state gate policy by milestone phase: section 6.1 + section 9.2.
3. UX metric arbitration and override policy: section 7.2.1.
4. Snapshot/accessibility jobs now have concrete commands and reports: section 9.2 + section 9.3.
5. Chart motion semantics ownership: section 12.
6. Mandatory production release routes are fixed to `planning`, `dashboard`, `settings` via production manifest.
7. Android duplicate threshold is fixed to `0.20` and enforced in release snapshot checks.
8. Runtime accessibility toolchain is fixed to:
   - iOS: `xctest-ui`,
   - Android: `android-instrumentation`,
   with machine-readable assertions artifact.
9. Production manifest minimum coverage is fixed to `default`, `error`, `recovery` per route and per platform.
10. Release-certifiable source of truth is fixed to:
    - canonical: `artifacts/visual-system/release-certification-report.json`,
    - published mirror: `docs/release/visual-system/latest/release-certification-report.json`.
11. Hard literal debt policy for signoff is fixed to zero new violations above baseline via:
    - `bash scripts/check_ios_visual_literals.sh`
    - `bash scripts/check_android_visual_literals.sh`
12. Runtime accessibility provenance generation is release-wired via:
    - `python3 scripts/generate_runtime_accessibility_assertions.py`,
    executed in `scripts/run_visual_system_release_gates.sh` before release accessibility checks.
13. Operational freshness policy is enforced via:
    - `python3 scripts/check_visual_release_certification_freshness.py` (age + commit match).
14. Runtime accessibility assertions source is fixed to executed runtime test-results artifact:
    - `artifacts/visual-system/runtime-accessibility-test-results.json`,
    produced by `python3 scripts/run_visual_accessibility_runtime_tests.py --mode release`.
15. Release workflow now includes explicit runtime accessibility test execution command before release gates.
16. Snapshot production manifest commit provenance is enforced via:
    - `evidenceCommitSha` + `capturedAt` checks in `scripts/run_visual_snapshot_checks.py`.
17. Human-readable certification summary is generated from canonical JSON artifacts via:
    - `python3 scripts/generate_visual_release_certification_summary.py`.
18. Baseline debt governance includes explicit per-wave budget gate with mandatory release wave:
    - `python3 scripts/check_visual_literal_baseline_burndown.py --wave ${VISUAL_SYSTEM_WAVE}`.
19. Runtime accessibility evidence quality policy is operationalized:
    - release-mode test results must satisfy `testMode=full`,
    - summary artifact exposes evidence-quality metadata,
    - smoke command is blocked in release workflow.
20. Snapshot production manifest freshness SLA is enforced:
    - `python3 scripts/run_visual_snapshot_checks.py --mode release --production-max-age-hours 24`.

No unresolved R8 open questions remain in this proposal.

---

## 15) Best-Practice References

1. Apple HIG (hierarchy, clarity, platform-consistent interaction)
2. Apple Liquid Glass technology overview (focus-first depth usage)
3. WCAG 2.2 (contrast, non-color semantics)
4. Android accessibility foundations
5. Material 3 theming/elevation guidance

These sources define guardrails for the contracts and thresholds in sections 4-12.
