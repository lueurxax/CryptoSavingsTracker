# Consolidated Proposal Review (R7)

## 0. Evidence Pack Summary
- Document inputs reviewed: 11
- Internet sources reviewed: 6
- Xcode screenshots captured: 18 refreshed captures (iOS + Android production flows) in `docs/screenshots/review-visual-system-unification-r4/production/`
- Remaining assumptions:
  - This review evaluates proposal + gate operational readiness, not full app implementation parity.
  - Local gate runs and CI-like env runs are representative for current branch state.
  - Screenshot evidence was refreshed in this review cycle, but commit-bound capture provenance for snapshot gate remains a design decision (see findings).

## 1. Executive Summary
- Overall readiness: Amber-Green (8.1/10)
- Top 3 risks:
  1. Runtime accessibility assertions are generated from a template, not from executed UI/instrumentation test outputs.
  2. Snapshot evidence is validated for presence/hash baseline but not strongly bound to current commit provenance.
  3. Literal guard policy still permits substantial legacy baseline debt (especially iOS), which can slow long-term convergence.
- Top 3 opportunities:
  1. End-to-end release pipeline is now operationally passable with certification + freshness + mirror sync.
  2. Previously unresolved R6 gaps (status drift, provenance wiring, freshness checks) are concretely addressed.
  3. Production-flow coverage is upgraded to `default/error/recovery` for all three release-blocking flows across both platforms.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 8.2 | 0 | 1 | 1 | 0 |
| UX (Financial) | 8.0 | 1 | 0 | 1 | 0 |
| iOS Architecture | 8.1 | 1 | 1 | 0 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Snapshot gate still accepts commit-stale visual evidence
  - Evidence: DOC-05, DOC-09, DOC-10
  - Why it matters: visual regressions can slip if committed screenshots are not regenerated per commit/run; baseline diff alone compares image hashes to a stored baseline, not to current UI render from test run.
  - Recommended fix: add `evidenceCommitSha` + `capturedAt` fields to production manifest and enforce match with current commit (or require capture job in release workflow).
  - Acceptance criteria: release snapshot check fails when manifest commit SHA differs from `GITHUB_SHA`.

- [Medium] Legacy literal baseline remains large on iOS
  - Evidence: DOC-11
  - Why it matters: policy blocks only new literals, while 200+ existing baseline entries remain; this limits true token-only convergence.
  - Recommended fix: add explicit baseline burndown targets per wave and cap allowed baseline count by milestone.
  - Acceptance criteria: baseline count decreases each wave and cannot increase without approved exception ticket.

### 3.2 UX Review Findings
- [Critical] Runtime accessibility assertions are provenance-correct but still template-seeded
  - Evidence: DOC-03, DOC-04, DOC-07
  - Why it matters: report can be syntactically valid and provenance-matched while semantically detached from real runtime accessibility behavior if assertion booleans are inherited from static template.
  - Recommended fix: replace template seeding with ingestion from actual XCTest/Instrumentation outputs (or generate template from test result artifacts in CI).
  - Acceptance criteria: runtime assertion artifact is produced from test run artifacts and fails when corresponding test assertions fail.

- [Medium] Operational status is now derived correctly, but reviewer UX still depends on artifact literacy
  - Evidence: DOC-01, DOC-02, DOC-06
  - Why it matters: proposal avoids hardcoded green state, but consumers still need to inspect artifacts to interpret pass/fail and freshness.
  - Recommended fix: add one human-readable summary markdown generated from certification + freshness JSON.
  - Acceptance criteria: generated summary clearly states pass/fail, freshness age, source commit, and failed steps when any.

### 3.3 Architecture Review Findings
- [Critical] Accessibility release gate lacks hard coupling to executed test commands in workflow
  - Evidence: DOC-03, DOC-08
  - Why it matters: `visual-release-gates` runs shell orchestration only; no explicit UI-test execution step exists to feed assertions. This creates a correctness gap between “gate green” and “tests actually ran”.
  - Recommended fix: add explicit test execution stage before assertion generation and fail generation when test outputs are absent.
  - Acceptance criteria: workflow includes mandatory XCTest/UIAutomator (or instrumentation) command and uses those outputs as assertions source.

- [High] Certification pipeline is now robust, but depends on file-copy mirror sync
  - Evidence: DOC-03, DOC-06
  - Why it matters: docs mirror accuracy depends on copy step at end of release script; if script is bypassed, docs may go stale.
  - Recommended fix: enforce proposal/source-of-truth strictly to `artifacts/visual-system/*` and treat `docs/release/...` as optional published mirror with generated timestamp.
  - Acceptance criteria: proposal references canonical artifact path for gating decisions; mirror mismatch becomes non-authoritative warning, not truth source.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Deterministic fast checks vs runtime truth of accessibility
  - Tradeoff: template-seeded assertions are fast and stable; test-derived assertions are slower but trustworthy.
  - Decision: keep deterministic schema checks, but make runtime assertions test-derived for release mode.
  - Owner: Accessibility Champion + QA Automation.

- Conflict: Repo-stored screenshot evidence vs per-run capture cost
  - Tradeoff: stored artifacts simplify reviews; per-run capture increases infra/time cost.
  - Decision: keep stored artifacts for PR mode, require commit-bound capture/provenance in release mode.
  - Owner: Mobile Platform Team.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Replace template-seeded runtime assertions with test-derived assertions | UX/Architecture | Accessibility Champion + QA Automation | Now | XCTest/Instrumentation outputs | assertion artifact fails when tests fail |
| P0 | Add explicit accessibility test execution command to release workflow | Architecture | Mobile Platform Team | Now | CI runner configuration | release job fails if test step missing/fails |
| P1 | Add snapshot evidence commit binding in production manifest checks | UI/Architecture | QA Automation | Next | manifest schema update | snapshot gate fails on commit mismatch |
| P1 | Generate human-readable certification summary from JSON artifacts | UX | Engineering Manager | Next | report generator | one-click operational status interpretation |
| P2 | Introduce wave-based baseline debt reduction targets | UI | iOS Lead + Android Lead | Later | governance cadence | baseline counts trend down each wave |

## 6. Execution Plan
- Now (0-2 weeks):
  - Wire real UI/instrumentation test outputs into runtime accessibility assertions.
  - Add explicit release workflow test execution before assertion generation.
- Next (2-6 weeks):
  - Extend production manifest/schema with capture commit provenance.
  - Add generated markdown certification summary.
- Later (6+ weeks):
  - Run baseline debt burndown by wave and tighten allowed literal exceptions.

## 7. Open Questions
- Which concrete XCTest/Instrumentation artifacts are designated as canonical inputs for runtime assertions generation?
- Will release-mode snapshot evidence be generated in CI, or remain repo-stored with strict commit provenance checks?
- What baseline debt threshold is acceptable per wave for iOS and Android?

## 8. Detailed Evidence Pack

### A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 0, 9.2, 13, 14 | Proposal now marks operational readiness as derived from artifacts and adds freshness policy + commands. | Treated as current contract. |
| DOC-02 | `artifacts/visual-system/release-certification-report.json` | full | Current artifact reports `releaseCertifiable=true`, includes `generatedAt`, `sourceCommitSha`, `sourceCiRunId`. | Used as canonical runtime status. |
| DOC-03 | `scripts/run_visual_system_release_gates.sh` | 72-85, 117-170 | Release script generates runtime assertions, runs freshness check, and publishes docs mirror from artifacts. | Main release orchestration path. |
| DOC-04 | `scripts/generate_runtime_accessibility_assertions.py` | 97-132 | Generator copies `platforms` assertions from template and overlays provenance metadata. | Indicates assertions are template-seeded. |
| DOC-05 | `scripts/run_visual_snapshot_checks.py` | 447-459 | Release snapshot gate validates baseline diff, duplicate ratio, and production manifest coverage. | No commit provenance enforcement for captures yet. |
| DOC-06 | `docs/release/visual-system/latest/*` vs `artifacts/visual-system/*` diff check | full | After release script run, canonical docs mirror is synchronized (no file diffs). | Sync correctness depends on script execution. |
| DOC-07 | `docs/release/visual-system/latest/runtime-accessibility-assertions.json` | full | Assertions currently all `true`, with generated provenance metadata. | Semantic correctness depends on template truthfulness. |
| DOC-08 | `.github/workflows/visual-system-gates.yml` | 132-145 | Release workflow triggers shell gate script; no explicit accessibility test command shown in workflow job itself. | Test execution coupling relies on script internals/additional steps. |
| DOC-09 | `artifacts/visual-system/snapshot-report.json` | full | Release snapshot passed: production states covered for all required flows; Android duplicate ratio is `0.0`. | Confirms earlier capture-integrity gap improved. |
| DOC-10 | `docs/screenshots/review-visual-system-unification-r4/production/manifest.v1.json` + refreshed capture run outputs | full | Production manifest includes `default/error/recovery` per flow/platform and refreshed files are present for all required entries. | Evidence coverage complete for defined states in current review cycle. |
| DOC-11 | `docs/design/baselines/ios-visual-literals-baseline.txt` | full | iOS literal baseline still contains 206 entries (legacy debt). | Policy currently controls new debt, not full elimination. |

### B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ | 2025-06-09 | Apple positions Liquid Glass as expressive but content-focused and familiar. | UI hierarchy and restraint benchmark. |
| WEB-02 | https://www.w3.org/standards/history/WCAG22/ | 2024-12-12 (latest Recommendation entry) | WCAG 2.2 publication history confirms current Recommendation status chronology. | Accessibility baseline stability. |
| WEB-03 | https://developer.android.com/design/ui/mobile/guides/foundations/accessibility | Last updated 2023-05-08 UTC | Android accessibility fundamentals emphasize contrast, non-color cues, and touch target quality. | Cross-platform accessibility parity guidance. |
| WEB-04 | https://developer.android.com/develop/ui/compose/designsystems/material3 | Last updated 2026-02-26 UTC | Material 3 Compose guidance emphasizes tokenized, systemized design implementation. | Supports token contract governance. |
| WEB-05 | https://developer.android.com/jetpack/androidx/releases/compose-material3 | Last updated 2026-02-25 UTC | Compose Material 3 evolves continuously; governance needs enforced checks over ad-hoc styling. | Operability rationale for CI guards. |
| WEB-06 | https://developer.apple.com/design/tips/ | Accessed 2026-03-03 | Apple UI design guidance reiterates readability, contrast, and 44pt hit targets. | UX/accessibility consistency benchmark. |

### C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-visual-system-unification-r4/production/ios/planning/default.png` | Planning production route | default | iOS simulator capture set | Confirms required iOS planning evidence exists. |
| SCR-02 | `docs/screenshots/review-visual-system-unification-r4/production/android/dashboard/error.png` | Dashboard production route | error | Android emulator capture set | Confirms Android error-state evidence exists. |
| SCR-03 | `docs/screenshots/review-visual-system-unification-r4/production/ios/settings/recovery.png` | Settings production route | recovery | iOS simulator capture set | Confirms recovery-state requirement is implemented. |

### D. Assumptions and Open Questions
- ASSUMP-01: Review intent is quality assessment; no code modifications requested in this turn.
- ASSUMP-02: Artifact set generated during this session reflects current repository status.
- QUESTION-01: Should release certification gate require runtime assertion inputs to be generated from executed test logs only?
