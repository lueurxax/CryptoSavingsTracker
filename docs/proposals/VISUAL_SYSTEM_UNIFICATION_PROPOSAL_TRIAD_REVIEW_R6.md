# Consolidated Proposal Review (R6)

## 0. Evidence Pack Summary
- Document inputs reviewed: 10
- Internet sources reviewed: 6
- Xcode screenshots captured: 0 new captures; reused latest production-flow set (`planning`, `dashboard`, `settings`, states `default/error/recovery` on iOS+Android)
- Remaining assumptions:
  - Scope is proposal execution-readiness, not full product redesign audit.
  - Local gate runs represent current repository state at review time.
  - CI feasibility risks are evaluated from workflow/scripts (not from a live release-branch GitHub run log).

## 1. Executive Summary
- Overall readiness: Amber (7.0/10)
- Top 3 risks:
  1. Operational status in proposal is currently stale (`green`) while latest release certification artifact is `false`.
  2. iOS literal guard regressed again (new `AddGoalView` shadow literals), blocking release certification.
  3. Runtime accessibility provenance check is CI-coupled but generation pipeline for run-specific metadata is not wired in workflow.
- Top 3 opportunities:
  1. Core governance stack is now strong: parity, expiry, state matrix, snapshot, accessibility, UX, and release certification gates are all implemented.
  2. Production manifest is upgraded to route-level states (`default`, `error`, `recovery`) and artifacts exist for both platforms.
  3. Android evidence integrity improved materially (duplicate ratio now `0.000` in release snapshot report).

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 7.2 | 0 | 1 | 1 | 0 |
| UX (Financial) | 6.9 | 0 | 1 | 1 | 0 |
| iOS Architecture | 6.8 | 1 | 1 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] New iOS shadow literals reintroduced in release-blocking path
  - Evidence: DOC-02, DOC-03
  - Why it matters: Token policy (section 4.4) requires tokenized visual semantics. Raw `.shadow(...)` in `AddGoalView` causes release gate failure and visual drift risk.
  - Recommended fix: Replace ad-hoc shadows with approved elevation/surface token primitives (or component style wrappers) and update baseline only if governance exception is approved.
  - Acceptance criteria: `bash scripts/check_ios_visual_literals.sh` passes with zero new violations.

- [Medium] Proposal status communicates "green" certainty despite current failing gate run
  - Evidence: DOC-01, DOC-04
  - Why it matters: UI governance is partially about trust language; stale green claims reduce confidence in review artifacts.
  - Recommended fix: Convert status row from hardcoded value to generated status snapshot or explicitly mark as "example/status at last certified run".
  - Acceptance criteria: Proposal status is always traceable to current artifact timestamp and value.

### 3.2 UX Review Findings
- [High] Source-of-truth split can mislead operational decision-making
  - Evidence: DOC-04, DOC-05, DOC-06
  - Why it matters: `docs/release/.../release-certification-report.json` still says `true` while latest generated artifact says `false`; reviewers can read opposite outcomes.
  - Recommended fix: Add single publish step that atomically syncs/updates canonical release report after gate run, then reference only that canonical path.
  - Acceptance criteria: No divergence between canonical cert report and latest generated cert report.

- [Medium] Recovery/process messaging is strong, but certification freshness is weakly signaled
  - Evidence: DOC-01, DOC-09
  - Why it matters: Teams need immediate clarity if reports are stale; currently there is no explicit freshness SLA indicator in proposal status table.
  - Recommended fix: Add freshness field (`generatedAt`, max age, commit SHA) in section 0 and enforce by validator.
  - Acceptance criteria: Status marked non-certifiable when certification artifact age/commit mismatches policy.

### 3.3 Architecture Review Findings
- [Critical] Runtime accessibility provenance checks are CI-bound, but runtime assertion generation is not CI-wired
  - Evidence: DOC-07, DOC-08, DOC-09
  - Why it matters: `run_visual_accessibility_checks.py` validates `GITHUB_RUN_ID/GITHUB_SHA` provenance in release mode; current runtime assertions file uses static seed metadata and workflow does not generate per-run assertion artifacts. This creates predictable CI release failure or encourages bypass behavior.
  - Recommended fix: Add explicit CI step to generate runtime accessibility assertions with current run metadata before release accessibility check, or temporarily gate provenance validation behind a generation-ready flag.
  - Acceptance criteria: Release workflow passes with provenance checks enabled on real GitHub run metadata (no static seed dependence).

- [High] Snapshot gate still validates committed artifacts, not freshly rendered CI captures
  - Evidence: DOC-09, DOC-10
  - Why it matters: Visual regressions in code may not be detected if evidence images are not regenerated in the same pipeline.
  - Recommended fix: Introduce capture job (or signed freshness manifest) that binds screenshots to current commit and blocks stale evidence usage.
  - Acceptance criteria: Release snapshot validation fails when evidence commit SHA differs from current build SHA.

- [Medium] Operational readiness in proposal can drift from actual artifact state
  - Evidence: DOC-01, DOC-04, DOC-05
  - Why it matters: Architecture governance requires deterministic truth. Manual status text is inherently drift-prone.
  - Recommended fix: Treat section 0 status as generated output snippet, not hand-maintained prose.
  - Acceptance criteria: Automated update process keeps section 0 status synchronized with certification artifact.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Strict provenance validation vs practicality of static checked-in artifacts
  - Tradeoff: Strong provenance raises trust but fails without artifact-generation plumbing.
  - Decision: Keep strict provenance; add generation plumbing as release prerequisite.
  - Owner: Mobile Platform Team + QA Automation.

- Conflict: Human-readable proposal status vs machine-truth artifacts
  - Tradeoff: Embedded status is easy to read but easy to stale.
  - Decision: Use machine-generated status snapshot references, not fixed green labels.
  - Owner: Engineering Manager.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Remove new iOS literal shadow violations in `AddGoalView` | UI | iOS Lead | Now | token/elevation wrappers | iOS literal guard passes |
| P0 | Wire runtime accessibility assertion generation into release workflow | Architecture/UX | QA Automation + Accessibility Champion | Now | CI runner + test harness | release-mode accessibility check passes with real `GITHUB_RUN_ID` |
| P1 | Canonicalize certification report publish path and sync step | UX/Architecture | Mobile Platform Lead | Next | report publish script | no diff between canonical and generated cert report |
| P1 | Add certification freshness gate (age + commit match) | Architecture | Mobile Platform Team | Next | metadata injection | stale report cannot mark operational readiness green |
| P2 | Add CI capture freshness binding for production screenshots | UI/Architecture | QA Automation | Later | capture infra on runners | snapshot evidence tied to current commit |

## 6. Execution Plan
- Now (0-2 weeks):
  - Fix `AddGoalView` literal guard regressions.
  - Add CI step to produce runtime accessibility assertions with current run metadata.
  - Re-run release gates and regenerate certification artifact.
- Next (2-6 weeks):
  - Implement canonical certification report publish/sync.
  - Add freshness validation to prevent stale green status.
- Later (6+ weeks):
  - Add commit-bound screenshot freshness enforcement in CI.
  - Expand operational telemetry around certification drift incidents.

## 7. Open Questions
- Which path is canonical long-term source of truth: `artifacts/visual-system/*` or `docs/release/visual-system/latest/*`?
- Should provenance validation be hard-blocking in all release runs immediately, or staged behind a temporary rollout flag until generator lands?
- What freshness SLA is acceptable for operational readiness status (e.g., max 24h or same-commit only)?

## 8. Detailed Evidence Pack

### A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 0, 8.3, 9.2, 13 | Proposal now includes dual readiness model and cert-report requirement, but hardcodes current status `green`. | Used as primary contract for review. |
| DOC-02 | `bash scripts/run_visual_system_release_gates.sh` (local run, 2026-03-03) | output | Release run fails at iOS literal guard due 3 new `AddGoalView` shadow violations. | Represents latest local operational signal. |
| DOC-03 | `ios/CryptoSavingsTracker/Views/AddGoalView.swift` | lines 151, 215, 235 | Raw `.shadow(...)` calls are present in form sections. | Violations are outside preview files and guarded paths. |
| DOC-04 | `artifacts/visual-system/release-certification-report.json` | full | Latest generated cert report shows `releaseCertifiable=false` (`iosLiteralGuard` failed). | Treated as latest generated truth artifact. |
| DOC-05 | `docs/release/visual-system/latest/release-certification-report.json` | full | Docs copy still shows `releaseCertifiable=true`. | Conflicts with latest generated artifact. |
| DOC-06 | diff between DOC-04 and DOC-05 | full | Operational status drift exists between canonical-looking paths. | Demonstrates trust gap in status communication. |
| DOC-07 | `GITHUB_RUN_ID=12345 GITHUB_SHA=... python3 scripts/run_visual_accessibility_checks.py --mode release` | output | Fails with `provenance.ciJobId must include current GITHUB_RUN_ID`. | CI-like env check proves provenance coupling. |
| DOC-08 | `scripts/run_visual_accessibility_checks.py` | lines 157-168 | Release mode enforces `GITHUB_SHA` and `GITHUB_RUN_ID` provenance matching. | Strict check is correct but requires generation pipeline. |
| DOC-09 | `.github/workflows/visual-system-gates.yml` | lines 132-145 | Release job runs `run_visual_system_release_gates.sh` on Ubuntu, no step generates runtime assertions artifact per run. | CI integration gap remains. |
| DOC-10 | `artifacts/visual-system/snapshot-report.json` + production screenshot tree | full | Snapshot gate passes with production states (`default/error/recovery`) and Android duplicate ratio `0.000`. | Confirms major R5 gap was closed. |

### B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ | 2025-06-09 | Apple emphasizes expressive visuals while preserving familiarity and focus. | Supports “clarity before decoration” in finance flows. |
| WEB-02 | https://www.w3.org/TR/WCAG22/ | 2024-12-12 (W3C Recommendation snapshot) | WCAG 2.2 defines contrast and non-color requirements used in proposal checklist. | Accessibility baseline. |
| WEB-03 | https://developer.android.com/design/ui/mobile/guides/foundations/accessibility | Last updated 2023-05-08 UTC | Android accessibility guidance reinforces inclusive semantics and target sizing. | Android parity benchmark. |
| WEB-04 | https://developer.android.com/develop/ui/compose/designsystems/material3 | Last updated 2026-02-26 UTC | Material 3 guidance anchors tokenized, system-driven visual consistency. | Token/elevation governance relevance. |
| WEB-05 | https://developer.android.com/jetpack/androidx/releases/compose-material3 | Last updated 2026-02-25 UTC | Ongoing library evolution supports need for guardrails over ad-hoc styling. | Operational enforcement rationale. |
| WEB-06 | https://developer.apple.com/design/tips/ | Accessed 2026-03-03 | Apple design tips reinforce clarity, hierarchy, and interface consistency. | UI rubric alignment for iOS behavior. |

### C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-visual-system-unification-r4/production/ios/planning/default.png` | Planning route | default | iOS simulator artifact (captured 2026-03-03) | Confirms production-flow evidence exists for iOS planning. |
| SCR-02 | `docs/screenshots/review-visual-system-unification-r4/production/android/dashboard/error.png` | Dashboard route | error | Android emulator artifact (captured 2026-03-03) | Confirms Android error-state production evidence coverage. |
| SCR-03 | `docs/screenshots/review-visual-system-unification-r4/production/ios/settings/recovery.png` | Settings route | recovery | iOS simulator artifact (captured 2026-03-03) | Confirms recovery-state requirement is populated. |

### D. Assumptions and Constraints
- ASSUMP-01: User requested proposal readiness reassessment, not implementation patching in this turn.
- ASSUMP-02: Latest local gate run is authoritative for current operational status snapshot.
- CONSTRAINT-01: CI behavior inference is based on workflow/script analysis and CI-like env simulation, not a live GitHub release run log.
