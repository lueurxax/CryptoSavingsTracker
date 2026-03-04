# Consolidated Proposal Review (R4)

## 0. Evidence Pack Summary
- Document inputs reviewed: 11
- Internet sources reviewed: 6
- Xcode screenshots captured: 0 new; reused 4 screenshots from `review-visual-system-unification-r4`
- Remaining assumptions:
  - Review scope is proposal and gate-operability readiness, not full product-level implementation audit.
  - Existing R4 screenshot set is treated as current baseline evidence package.
  - CI behavior is evaluated from repository workflow and local script execution, not from a live GitHub Actions run log.

## 1. Executive Summary
- Overall readiness: Amber (7.1/10)
- Top 3 risks:
  1. Snapshot and accessibility gates are operational but currently validate synthetic debug captures and metadata, not real release-blocking screens.
  2. Android R4 evidence integrity is weak: 31/32 PNG state captures are binary-identical while labeled as different states/components.
  3. Gate pass signal can be misleading because snapshot/accessibility scripts do not perform visual diffing or runtime accessibility assertions on production flows.
- Top 3 opportunities:
  1. Governance maturity is strong: owners, escalation, exception cadence, and CI wiring are now explicit and repository-backed.
  2. Token contract and state matrix moved from intent to executable schema + validators.
  3. Release-mode gate orchestration exists and can become production-trustworthy with higher-fidelity evidence validation.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 7.0 | 0 | 2 | 1 | 0 |
| UX (Financial) | 7.2 | 0 | 1 | 2 | 0 |
| iOS Architecture | 7.1 | 1 | 2 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Snapshot evidence does not represent real release-blocking flows
  - Evidence: DOC-01, DOC-06, SCR-01, SCR-02
  - Why it matters: R4 screenshots show `Visual State Capture` debug surfaces, not actual planning/dashboard/settings production screens. Visual regression confidence for real flows remains unproven.
  - Recommended fix: Add capture mode that records canonical production screens for each release-blocking flow/state and keep debug capture only as supplemental.
  - Acceptance criteria: `visual-snapshots` gate includes production-screen diffs with baseline and per-flow artifact mapping.

- [High] Android state capture integrity is currently invalid for review confidence
  - Evidence: DOC-09, DOC-07, SCR-03, SCR-04
  - Why it matters: 31 Android captures are byte-identical while labeled as different components/states. This breaks trust in state-based visual verification.
  - Recommended fix: Harden `capture_android_visual_states.sh` with post-capture assertions (component/state text OCR or hash-delta checks) and fail when duplicate threshold is exceeded.
  - Acceptance criteria: Android capture job fails if identical-image ratio exceeds policy threshold (for example >20%) for distinct state/component pairs.

- [Medium] Surface/depth policy is solid on paper but not yet linked to automated visual diff rules
  - Evidence: DOC-01, DOC-02
  - Why it matters: Policy matrix is explicit, yet no rule checks card depth/material drift from baseline snapshots.
  - Recommended fix: Add policy assertions in snapshot report (for example component-level token/elevation IDs used per capture).
  - Acceptance criteria: Snapshot report contains policy conformance section with pass/fail per priority component.

### 3.2 UX Review Findings
- [High] Accessibility gate validates metadata, not user-observed accessibility behavior
  - Evidence: DOC-03, DOC-11
  - Why it matters: Current accessibility script checks token flags, matrix presence, and runbook markers; it does not verify VoiceOver/TalkBack behavior, focus order, or contrast on rendered UI.
  - Recommended fix: Add instrumentation/UI-test-backed checks for assistive-tech scenarios listed in the checklist.
  - Acceptance criteria: `visual-accessibility` gate fails on real accessibility regressions in release-blocking screens.

- [Medium] UX metric rubric is improved but remains proposal-only without capture/report pipeline linkage
  - Evidence: DOC-01, DOC-10
  - Why it matters: Thresholds and arbitration are defined, but no script or report template enforces metric ingestion into wave artifact bundles.
  - Recommended fix: Add `scripts/validate_visual_ux_metrics.py` and a machine-readable metrics report schema.
  - Acceptance criteria: Wave promotion fails when UX metrics artifact is missing or below threshold.

- [Medium] Incident communication templates exist but are not tied to escalation automation
  - Evidence: DOC-11, DOC-01
  - Why it matters: Manual communication steps risk delayed trust-repair messaging during `sev1/sev2` incidents.
  - Recommended fix: Link escalation ladder to communication checklist trigger in rollback workflow.
  - Acceptance criteria: `sev1/sev2` rollback issue template auto-includes required communication blocks.

### 3.3 Architecture Review Findings
- [Critical] Gate architecture can pass while core product visuals regress
  - Evidence: DOC-03, DOC-06, DOC-08
  - Why it matters: Snapshot/accessibility jobs currently validate state-matrix metadata + debug capture scaffolds rather than end-user production flows. This creates a false sense of release safety.
  - Recommended fix: Re-architect gates so production-screen capture + diff + accessibility assertions are mandatory for release-branch pass.
  - Acceptance criteria: Release gate cannot pass without production flow evidence for all release-blocking screens/states.

- [High] Android capture script lacks verification of intent propagation/state realization
  - Evidence: DOC-07, DOC-09
  - Why it matters: Script launches activity with `component/state` extras but does not verify resulting screen context before screenshot. This enabled large-scale mislabeled artifacts.
  - Recommended fix: Add post-launch verification step (`adb shell uiautomator dump` parse expected component/state label) before taking screenshot.
  - Acceptance criteria: Capture job aborts when requested component/state label does not match rendered output.

- [High] Snapshot and accessibility scripts do not perform true regression checks
  - Evidence: DOC-02, DOC-03
  - Why it matters: Scripts validate matrix/status/file existence and semantic flags, but do not compare snapshots against baseline nor execute accessibility scanners against rendered UI.
  - Recommended fix: Integrate image diff engine and platform accessibility test harness outputs into both scripts.
  - Acceptance criteria: Introduced visual or accessibility regressions in production screens are detected and fail CI.

- [Medium] Approved variants share near-term expiry concentration risk
  - Evidence: DOC-02
  - Why it matters: Multiple key roles expire on `2026-06-30`; missing convergence plan can create clustered failures close to release windows.
  - Recommended fix: Add per-variant removal milestones and owner checkpoints before expiry window.
  - Acceptance criteria: No approved variant reaches <=30 days to expiry without linked closure PR.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Fast deterministic checks vs high-fidelity production validation
  - Tradeoff: Lightweight metadata checks are fast but can miss real regressions.
  - Decision: Keep metadata checks for PR speed; require production capture+differential checks for release branches.
  - Owner: Mobile Platform Team + QA Automation.

- Conflict: Debug capture scaffolds vs end-user trust signal
  - Tradeoff: Scaffolds help stabilize test harnesses but are not representative of real UX.
  - Decision: Treat scaffold captures as non-blocking support artifacts only.
  - Owner: iOS Lead + Android Lead.

- Conflict: Strict exception expiry vs migration reality
  - Tradeoff: Tight expiry improves governance but may block releases if convergence lags.
  - Decision: Keep expiry strict and require explicit pre-expiry review milestones.
  - Owner: Mobile Platform Lead.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Convert release snapshot gate to production-flow capture+diff | Architecture/UI | QA Automation + Mobile Platform | Now | Capture harness updates | Release gates fail on real visual regressions in planning/dashboard/settings |
| P0 | Add capture integrity checks for Android state pipeline | Architecture | Android Lead | Now | `capture_android_visual_states.sh` upgrade | Distinct state/component requests produce verifiably distinct labeled artifacts |
| P0 | Upgrade accessibility gate from metadata checks to runtime assertions | UX/Architecture | Accessibility Champion | Now | UI test harness integration | Accessibility regressions in release-blocking screens fail CI |
| P1 | Add UX metrics artifact validator and schema | UX | UX Research + Product Design | Next | Metrics export pipeline | Wave promotion blocks on missing/failing UX metrics report |
| P1 | Wire rollback communication checklist to escalation templates | UX/Operations | Product Manager + Support Lead | Next | Incident template update | `sev1/sev2` incidents ship complete user communication package |
| P1 | Add variant-expiry burn-down tracker | Architecture | Mobile Platform Lead | Next | Governance reporting | Zero variants within 30 days of expiry without closure plan |
| P2 | Add policy-conformance section to snapshot report (surface/elevation token usage) | UI/Architecture | Design Systems Owner | Later | Token introspection hooks | Snapshot report includes per-component policy conformance pass/fail |
| P2 | Add gate quality SLO (false pass / false fail tracking) | Architecture | Mobile Platform Team | Later | Historical gate telemetry | Gate quality improves over release cycles with tracked SLO |

## 6. Execution Plan
- Now (0-2 weeks):
  - Replace release snapshot validation with production-screen diffing.
  - Harden Android capture pipeline with state verification and duplicate detection.
  - Integrate runtime accessibility assertions into release gates.
- Next (2-6 weeks):
  - Add UX metrics validator and enforce it in wave artifact bundle checks.
  - Automate rollback communication template binding to incident severity workflows.
  - Create approved-variant pre-expiry review board and tracking.
- Later (6+ weeks):
  - Expand snapshot reporting with policy conformance metrics.
  - Measure and improve gate quality SLOs (false positive/false negative rates).
  - Refine governance based on observed rollout incidents.

## 7. Open Questions
- Which concrete production screens (route IDs) are mandatory in release snapshot mode for each flow?
- What duplicate threshold is acceptable for capture integrity before failing Android artifact generation?
- Which toolchain will provide runtime accessibility assertions in CI for both platforms?

## 8. Detailed Evidence Pack

### A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 4-14 | Proposal now includes phase-based state policy, concrete CI commands, workflow wiring, and R4 evidence manifest requirement. | Evaluated as latest contract source. |
| DOC-02 | `scripts/run_visual_snapshot_checks.py` | full | Snapshot checks rely on state matrix validation + artifact extension checks; no baseline image diff logic present. | Treated as current snapshot gate implementation. |
| DOC-03 | `scripts/run_visual_accessibility_checks.py` | full | Accessibility checks validate metadata/runbook markers and matrix state presence; no runtime UI accessibility assertions. | Treated as current accessibility gate implementation. |
| DOC-04 | `.github/workflows/visual-system-gates.yml` | jobs | CI workflow exists and wires declared jobs, including release mode gate job. | Live CI execution results not available in this review. |
| DOC-05 | `scripts/run_visual_system_gates.sh`, `scripts/run_visual_system_release_gates.sh` + local run output | full | PR and release gate scripts pass locally. | Pass signal interpreted alongside gate-depth limitations. |
| DOC-06 | `android/app/src/debug/java/com/xax/CryptoSavingsTracker/debug/VisualStateCaptureActivity.kt` | 69-240 | Capture activity renders synthetic debug cards (`Visual State Capture`) instead of production screen flows. | Synthetic capture may be useful but insufficient as sole release evidence. |
| DOC-07 | `scripts/capture_android_visual_states.sh` | 68-79 | Android capture loop saves images without verifying rendered component/state after intent launch. | Missing integrity checks can mislabel artifacts. |
| DOC-08 | `docs/design/visual-state-matrix.v1.json` | full | Matrix marks all 64 state/platform entries as `captured` and points to R4 PNG files. | Accuracy of labels depends on capture integrity. |
| DOC-09 | Local artifact integrity audit (`sha256` across R4 PNGs) | command output | 31 Android PNG files are binary-identical though mapped to different state/component refs. | Indicates evidence quality regression risk. |
| DOC-10 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 7.2 + 7.2.1 | UX thresholds and arbitration rubric are now explicit. | Enforcement pipeline for UX metrics remains to be implemented. |
| DOC-11 | `docs/runbooks/visual-system-rollback.md` | 32-56 | Communication ownership and `SEV1/SEV2` templates are documented. | Trigger automation integration remains manual. |

### B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ | 2025-06-09 | Apple emphasizes clarity and familiarity alongside richer visual expression. | Supports clarity-first requirement in financial surfaces. |
| WEB-02 | https://www.w3.org/TR/WCAG22/ | 2024-12-12 | WCAG 2.2 Recommendation defines contrast and non-color signaling requirements. | Accessibility contract baseline for release gates. |
| WEB-03 | https://developer.android.com/design/ui/mobile/guides/foundations/accessibility | Last updated 2025-09-03 UTC | Android accessibility guidance reinforces non-color cues and inclusive interaction design. | Cross-platform accessibility parity benchmark. |
| WEB-04 | https://developer.android.com/develop/ui/compose/designsystems/material3 | Last updated 2026-02-10 UTC | Material 3 design-system guidance emphasizes tokenized theming and component consistency. | Relevant to token-only visual policy. |
| WEB-05 | https://developer.android.com/jetpack/androidx/releases/compose-material3 | Retrieved 2026-03-03 | Material3 release notes reflect ongoing API evolution affecting implementation details. | Supports need for robust, tool-driven parity controls. |
| WEB-06 | https://developer.apple.com/design/human-interface-guidelines/ | Retrieved 2026-03-03 | HIG remains baseline for platform trust, hierarchy, and interaction clarity. | iOS fidelity benchmark for review. |

### C. Screenshot Log (R4 reused)
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-visual-system-unification-r4/ios/planning.header_card/default.png` | iOS capture harness | default | iOS simulator artifact | Confirms debug capture surface style. |
| SCR-02 | `docs/screenshots/review-visual-system-unification-r4/ios/dashboard.summary_card/error.png` | iOS capture harness | error | iOS simulator artifact | Confirms synthetic capture context, not full production screen. |
| SCR-03 | `docs/screenshots/review-visual-system-unification-r4/android/planning.header_card/default.png` | Android capture harness | default | Android emulator artifact | Baseline for Android artifact integrity comparison. |
| SCR-04 | `docs/screenshots/review-visual-system-unification-r4/android/dashboard.summary_card/error.png` | Android capture harness | error | Android emulator artifact | Binary-identical to SCR-03 despite different mapped state/component. |

### D. Assumptions and Constraints
- ASSUMP-01: Proposal is evaluated as governance + gate system blueprint, not full feature-completeness spec.
- ASSUMP-02: R4 screenshot package is considered current evidence baseline.
- ASSUMP-03: Local script pass results are representative of gate logic, not of production UI quality.
- CONSTRAINT-01: Without production-screen snapshot diffing, visual confidence remains bounded.
