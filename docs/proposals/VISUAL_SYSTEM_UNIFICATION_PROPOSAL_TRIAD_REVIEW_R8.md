# Consolidated Proposal Review (R8)

## 0. Evidence Pack Summary
- Document inputs reviewed: 12
- Internet sources reviewed: 6
- Xcode screenshots captured: 18 refreshed production-flow captures (iOS + Android, flows: `planning/dashboard/settings`, states: `default/error/recovery`)
- Remaining assumptions:
  - This review targets proposal readiness and gate operability, not full app feature parity.
  - Local and CI-like runs are representative of current repository behavior.
  - Runtime accessibility validation quality depends on the configured test command implementation.

## 1. Executive Summary
- Overall readiness: Amber-Green (8.4/10)
- Top 3 risks:
  1. Runtime accessibility test stage is still smoke-level and can overstate real accessibility confidence.
  2. Literal baseline burndown enforcement defaults to `wave1`, so stricter budgets may be skipped unless CI variable is managed correctly.
  3. Production screenshot recency is checked for validity format and commit binding, but not strict max-age freshness.
- Top 3 opportunities:
  1. End-to-end release pipeline now passes with certification, freshness, summary generation, and docs mirror sync.
  2. Commit provenance checks are materially improved for both runtime accessibility evidence and production snapshot manifest.
  3. Prior R7 gaps (source-of-truth drift, missing human-readable summary, lack of release budget gate) are addressed in implementation.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 8.5 | 0 | 1 | 1 | 0 |
| UX (Financial) | 8.2 | 1 | 0 | 1 | 0 |
| iOS Architecture | 8.4 | 1 | 1 | 0 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Wave budget gate can stay on permissive `wave1` unless CI configuration advances it
  - Evidence: DOC-03, DOC-09, DOC-10
  - Why it matters: baseline debt governance exists, but enforcement strictness is environment-driven (`${VISUAL_SYSTEM_WAVE:-wave1}`), so convergence can stall silently.
  - Recommended fix: make wave explicit and required in release workflow (fail when unset), or derive from branch/release metadata.
  - Acceptance criteria: release job fails if `VISUAL_SYSTEM_WAVE` is missing/invalid; wave2+ budgets are automatically enforced when applicable.

- [Medium] Production capture metadata lacks explicit freshness threshold
  - Evidence: DOC-06
  - Why it matters: manifest `capturedAt` is validated for format/future and commit match, but very old captures on the same commit are still accepted.
  - Recommended fix: add max-age policy for production capture metadata in release mode (for example 24h).
  - Acceptance criteria: snapshot gate fails when manifest `capturedAt` exceeds configured age threshold.

### 3.2 UX Review Findings
- [Critical] Runtime accessibility test command is still smoke fixture logic, not assistive-tech execution
  - Evidence: DOC-04, DOC-05, DOC-11
  - Why it matters: current smoke command effectively checks screenshot existence and emits uniform pass assertions; this does not validate real VoiceOver/TalkBack behavior.
  - Recommended fix: replace smoke command in release workflow with actual XCTest UI + Android instrumentation accessibility test suites and ingest their outputs.
  - Acceptance criteria: runtime test-results artifact is generated from real test frameworks and reflects per-assertion failures when UI accessibility regressions occur.

- [Medium] Summary report is useful but does not expose quality-of-evidence grade
  - Evidence: DOC-12
  - Why it matters: a PASS can hide whether assertions came from smoke vs full runtime suites.
  - Recommended fix: add evidence-quality section (`testMode=smoke|full`, test suite IDs, executed test counts).
  - Acceptance criteria: summary shows evidence-quality metadata and blocks release on `smoke` mode when policy requires `full`.

### 3.3 Architecture Review Findings
- [Critical] Accessibility pipeline correctness still depends on replacing placeholder smoke command
  - Evidence: DOC-03, DOC-04, DOC-05
  - Why it matters: architecture now has correct artifact plumbing, provenance, and checks, but the source signal quality remains low until true runtime tests are connected.
  - Recommended fix: keep current pipeline structure, swap only command provider to real test executors, and require non-zero executed test count in results schema.
  - Acceptance criteria: `run_visual_accessibility_runtime_tests.py --mode release` fails when executed test count is zero or suite outputs are missing.

- [High] Proposal claims "no unresolved open questions" while evidence quality mode remains unresolved operationally
  - Evidence: DOC-01, DOC-11
  - Why it matters: contract completeness is high, but release trust still hinges on a pending decision: smoke vs full runtime tests.
  - Recommended fix: re-open one explicit operational question in proposal section 14 until full-runtime mode is wired.
  - Acceptance criteria: section 14 tracks closure criteria and target date for replacing smoke mode.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Fast deterministic smoke checks vs trustworthy runtime accessibility proof
  - Tradeoff: smoke checks are stable/cheap; real runtime suites are slower but materially more trustworthy.
  - Decision: keep smoke mode for local/PR if needed, require full-runtime mode in release.
  - Owner: Accessibility Champion + QA Automation.

- Conflict: Flexible wave parameter vs guaranteed debt reduction
  - Tradeoff: flexible env variable simplifies experimentation; fixed wave enforcement improves governance reliability.
  - Decision: move wave selection to explicit release metadata and treat missing value as failure.
  - Owner: Mobile Platform Lead.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Replace release runtime accessibility smoke command with real XCTest + instrumentation command set | UX/Architecture | Accessibility Champion + QA Automation | Now | test suite availability | runtime test-results sourced from real frameworks |
| P0 | Enforce required `VISUAL_SYSTEM_WAVE` in release CI | UI/Architecture | Mobile Platform Team | Now | workflow update | release fails when wave is unset/invalid |
| P1 | Add max-age enforcement for production manifest `capturedAt` | UI | QA Automation | Next | snapshot checker update | snapshot release gate rejects stale captures |
| P1 | Add evidence-quality metadata to summary/report schema | UX | Engineering Manager | Next | schema + summary generator update | PASS includes `testMode` and executed test counts |
| P2 | Re-open and close operational question for smoke->full runtime transition in proposal | Architecture | Engineering Manager | Later | governance cadence | section 14 reflects real closure state |

## 6. Execution Plan
- Now (0-2 weeks):
  - Swap release runtime accessibility command from smoke to full runtime suites.
  - Make `VISUAL_SYSTEM_WAVE` mandatory in release workflow.
- Next (2-6 weeks):
  - Add manifest capture freshness threshold.
  - Add evidence-quality fields to certification summary/report.
- Later (6+ weeks):
  - Close governance loop in proposal open-questions section after full-runtime rollout proves stable.

## 7. Open Questions
- Which exact XCTest and Android instrumentation test targets will become mandatory for release runtime accessibility evidence?
- Should smoke mode remain allowed for local runs only, or also for PR CI?
- What freshness SLA should apply to production captures (`capturedAt`) in release mode?

## 8. Detailed Evidence Pack

### A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 0, 8.3, 9.2, 13, 14 | Proposal incorporates R7 updates, including runtime test-results artifact, summary generation, and baseline budget gate. | Treated as latest contract text. |
| DOC-02 | `bash scripts/run_visual_system_release_gates.sh` (CI-like run with `GITHUB_SHA/GITHUB_RUN_ID`) | output | All 17 release steps pass, including freshness and canonical publish. | Operability verified on current branch. |
| DOC-03 | `scripts/run_visual_system_release_gates.sh` | 27-44, 102-124, 153-207 | Pipeline wiring includes runtime test execution, assertions generation, provisional/final certification, and summary publish. | Source of release orchestration behavior. |
| DOC-04 | `scripts/run_visual_accessibility_runtime_test_smoke.py` | 63-84, 97-109 | Smoke script validates screenshot existence and sets assertions uniformly from one boolean outcome. | Indicates limited runtime evidence depth. |
| DOC-05 | `scripts/run_visual_accessibility_runtime_tests.py` | 131-206 | Test-results artifact pipeline and provenance normalization are implemented. | Structural quality is good; source command quality varies. |
| DOC-06 | `scripts/run_visual_snapshot_checks.py` | 324-347, 333-341 | Snapshot release checks now enforce `evidenceCommitSha` and `capturedAt` validity; commit mismatch fails when `GITHUB_SHA` is set. | Freshness threshold not yet enforced. |
| DOC-07 | `GITHUB_SHA=deadbeef... python3 scripts/run_visual_snapshot_checks.py --mode release` | output | Gate fails on commit mismatch as expected. | Confirms commit-binding control is active. |
| DOC-08 | `artifacts/visual-system/release-certification-report.json`, `release-certification-freshness-report.json` | full | `releaseCertifiable=true`, freshness `passed=true`, source commit and CI run metadata present. | Current operational readiness is green. |
| DOC-09 | `.github/workflows/visual-system-gates.yml` | 104-115, 145-166 | Wave budget job uses `${VISUAL_SYSTEM_WAVE:-wave1}`; release job runs runtime test command then release gates. | Wave strictness depends on env management. |
| DOC-10 | `artifacts/visual-system/literal-baseline-burndown-report.json` + targets file | full | Wave1 budgets pass with counts `ios=206`, `android=27`, limits `210/30`. | Shows gate works but strictness is wave-dependent. |
| DOC-11 | `artifacts/visual-system/runtime-accessibility-test-results.json` | full | Artifact is generated with `sourceMode=test-run`, but `testCommand` still points to smoke script. | Operational quality gap remains. |
| DOC-12 | `artifacts/visual-system/release-certification-summary.md` | full | Human-readable summary is now generated automatically from canonical JSON artifacts. | Improves reviewer usability. |

### B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ | 2025-06-09 | Apple emphasizes visual richness with clarity and familiarity. | Supports restraint in finance UI depth/effects. |
| WEB-02 | https://www.w3.org/TR/WCAG22/ | 2024-12-12 (Recommendation snapshot) | WCAG 2.2 remains normative baseline for contrast and non-color semantics. | Accessibility guardrail. |
| WEB-03 | https://developer.android.com/design/ui/mobile/guides/foundations/accessibility | Last updated 2023-05-08 UTC | Android accessibility foundations emphasize inclusive patterns and targets. | Cross-platform accessibility parity benchmark. |
| WEB-04 | https://developer.android.com/develop/ui/compose/designsystems/material3 | Last updated 2026-02-26 UTC | Material3 guidance reinforces tokenized design-system consistency. | Supports token/elevation governance. |
| WEB-05 | https://developer.android.com/jetpack/androidx/releases/compose-material3 | Last updated 2026-02-25 UTC | Compose Material3 evolution requires robust governance over ad-hoc visuals. | Justifies CI-enforced contract checks. |
| WEB-06 | https://developer.apple.com/design/tips/ | Accessed 2026-03-03 | Apple design tips reinforce readability, hierarchy, and touch target quality. | UX quality benchmark for financial flows. |

### C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-visual-system-unification-r4/production/ios/planning/default.png` | Planning production route | default | iOS simulator (refreshed in this review) | Confirms iOS production evidence presence. |
| SCR-02 | `docs/screenshots/review-visual-system-unification-r4/production/android/dashboard/error.png` | Dashboard production route | error | Android emulator (refreshed in this review) | Confirms Android error-state evidence presence. |
| SCR-03 | `docs/screenshots/review-visual-system-unification-r4/production/ios/settings/recovery.png` | Settings production route | recovery | iOS simulator (refreshed in this review) | Confirms recovery-state evidence requirement. |

### D. Assumptions and Open Questions
- ASSUMP-01: User requested repeated triad review, not implementation changes in this turn.
- ASSUMP-02: Release gate status in artifacts after the latest run is authoritative for this review snapshot.
- QUESTION-01: By which date should release switch from smoke-mode runtime accessibility to full-runtime suite mode?
