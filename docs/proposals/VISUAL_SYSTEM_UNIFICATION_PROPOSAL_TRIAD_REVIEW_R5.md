# Consolidated Proposal Review (R5)

## 0. Evidence Pack Summary
- Document inputs reviewed: 11
- Internet sources reviewed: 6
- Xcode screenshots captured: 0 new; reused repository artifacts and release reports
- Remaining assumptions:
  - Scope is proposal-and-gate readiness for visual unification, not full product parity audit.
  - Local script runs are representative of current gate behavior.
  - Missing production screenshot artifacts indicate pipeline not yet executed successfully in this workspace.

## 1. Executive Summary
- Overall readiness: Amber-Red (6.2/10)
- Top 3 risks:
  1. Release gate is not passable in current state due iOS visual literal violations.
  2. Release snapshot evidence is incomplete (missing required production flow artifacts).
  3. Android state screenshot set has extreme duplication (0.9375), reducing confidence in state coverage evidence.
- Top 3 opportunities:
  1. Governance and enforcement are now concrete: token, parity, variant-expiry, state, accessibility, UX validators are implemented.
  2. Proposal now contains clearer operational contracts (manifest, schema, runtime assertion artifact, CI workflow binding).
  3. Most non-visual governance checks already pass, so remediation can focus on a narrow set of blocking gaps.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 6.0 | 1 | 2 | 1 | 0 |
| UX (Financial) | 6.8 | 0 | 1 | 2 | 0 |
| iOS Architecture | 5.9 | 1 | 2 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [Critical] Release visual evidence set is incomplete and non-certifiable
  - Evidence: DOC-04, DOC-05, DOC-06
  - Why it matters: release-mode snapshot checks fail because required production artifacts for planning/dashboard/settings are missing, so visual readiness for money-critical surfaces cannot be certified.
  - Recommended fix: execute both production capture scripts and commit generated artifacts to manifest paths; ensure route-level screenshots exist before release gate run.
  - Acceptance criteria: `python3 scripts/run_visual_snapshot_checks.py --mode release` passes with zero missing production artifact issues.

- [High] iOS token/literal guard regressed across multiple finance-critical screens
  - Evidence: DOC-02, DOC-03
  - Why it matters: raw `.red/.green/.orange`, direct `Color(...)`, and ad-hoc shadows bypass token contract and directly violate policy in section 4.4.
  - Recommended fix: replace literals with approved semantic token roles and update affected components (`AddAssetView`, `AddGoalView`, `MonthlyExecutionView`, `PlanningView`, `MonthlyPlanningSettingsView`, `DashboardView`, shared components).
  - Acceptance criteria: `bash scripts/check_ios_visual_literals.sh` passes with no new violations.

- [High] Android state evidence integrity is still weak
  - Evidence: DOC-04, DOC-10
  - Why it matters: duplicate ratio 0.9375 implies most distinct state images are visually identical, weakening the confidence of the state matrix as evidence.
  - Recommended fix: verify state realization before capture (already partially addressed in script), then regenerate state artifacts and audit hash diversity.
  - Acceptance criteria: Android duplicate ratio <= 0.20 and no duplicate group suggests mass state-capture collapse.

- [Medium] Policy conformance checks are role-scope based, not rendered-surface verified
  - Evidence: DOC-07
  - Why it matters: a role can be scoped correctly while rendered UI still drifts visually due local modifiers.
  - Recommended fix: augment snapshot checks with per-component rendered-token trace (surface/elevation token IDs used at runtime).
  - Acceptance criteria: snapshot report includes runtime-render conformance section per release-blocking component.

### 3.2 UX Review Findings
- [High] Current release confidence can be misread because critical user-facing evidence is absent while some validators pass
  - Evidence: DOC-04, DOC-09
  - Why it matters: accessibility/UX validators passing can be interpreted as full readiness, but missing production screenshots still block user-trust verification in real flows.
  - Recommended fix: add a consolidated gate summary artifact with explicit "release-certifiable" boolean that requires all release evidence classes.
  - Acceptance criteria: a single release report marks build as failed unless literal guard + production snapshots + accessibility + UX metrics all pass.

- [Medium] Runtime accessibility assertions rely on artifact trust, not provenance
  - Evidence: DOC-08, DOC-09
  - Why it matters: JSON can pass schema without proving it was produced by the expected CI test run.
  - Recommended fix: include run metadata (commit SHA, CI job ID, timestamp, test bundle hash) and verify in gate script.
  - Acceptance criteria: release gate fails when runtime assertion artifact provenance does not match current build context.

- [Medium] Production-flow capture currently enforces only `default` state per flow
  - Evidence: DOC-11, DOC-05
  - Why it matters: route-level defaults are useful, but high-risk UX errors often appear in warning/error/recovery states.
  - Recommended fix: expand production manifest to include `error` and `recovery` captures for each release-blocking flow.
  - Acceptance criteria: release manifest includes minimum `{default,error,recovery}` per flow/platform, and snapshot gate validates all.

### 3.3 Architecture Review Findings
- [Critical] End-to-end release gate is not operationally green in repository state
  - Evidence: DOC-03, DOC-02
  - Why it matters: proposal claims concrete blocking gates, but current pipeline stops at step 5 due iOS literal debt; effective release readiness is therefore blocked.
  - Recommended fix: treat literal-guard cleanup as P0 remediation branch before any additional proposal expansion.
  - Acceptance criteria: `bash scripts/run_visual_system_release_gates.sh` exits 0 on a clean branch.

- [High] Proposal marks R4 open questions as fully resolved, but execution readiness gaps remain
  - Evidence: DOC-01, DOC-04, DOC-06
  - Why it matters: “No unresolved open questions” is true for contract definition, but not for operational closure; missing required artifacts proves remaining execution risk.
  - Recommended fix: split status into `spec completeness` and `operational readiness` sections with independent criteria.
  - Acceptance criteria: proposal status table shows both dimensions and current value for each.

- [High] Release snapshot gate includes strong checks but lacks successful baseline evidence cycle in repo
  - Evidence: DOC-07, DOC-04
  - Why it matters: baseline + duplicate + production checks are good, but until all pass once on real artifacts, the system is designed but not validated.
  - Recommended fix: add mandatory “first green release rehearsal” milestone with archived evidence package.
  - Acceptance criteria: one full green rehearsal report exists under `docs/release/visual-system/latest/`.

- [Medium] iOS literal guard debt concentration increases merge friction
  - Evidence: DOC-02
  - Why it matters: many violations in high-churn files raise probability of repeated gate failures and developer bypass pressure.
  - Recommended fix: execute per-file remediation in small PRs with dedicated owner and deadline.
  - Acceptance criteria: literal debt burndown tracker reaches zero new violations and trend is stable for 2 weeks.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Strict gates vs team velocity
  - Tradeoff: strict literal + snapshot gates block faster merges, but prevent visual debt growth.
  - Decision: keep strict blocking policy; add remediation sprint and debt burndown dashboard.
  - Owner: Mobile Platform Lead.

- Conflict: Metadata validation speed vs runtime fidelity
  - Tradeoff: metadata checks are cheap and deterministic; runtime proof is slower but trustworthy.
  - Decision: keep both layers, but classify metadata-only pass as insufficient for release certification.
  - Owner: QA Automation + Accessibility Champion.

- Conflict: Proposal closure language vs operational truth
  - Tradeoff: “resolved” language improves readability but can hide remaining delivery risk.
  - Decision: publish dual-status model (`Spec`, `Operational`).
  - Owner: Engineering Manager.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Eliminate iOS visual literal violations in release-blocking flows | UI/Architecture | iOS Lead | Now | token mapping table | iOS literal guard passes |
| P0 | Generate and validate required production flow screenshots | UI/Architecture | QA Automation | Now | capture scripts + simulator/emulator | release snapshot check has zero missing artifact errors |
| P0 | Regenerate Android state captures to satisfy duplicate threshold | UI | Android Lead | Now | capture pipeline verification | Android duplicate ratio <= 0.20 |
| P1 | Add consolidated release-certification report | UX/Architecture | Mobile Platform Team | Next | gate report merger | single certifiable boolean produced in CI |
| P1 | Add runtime assertion provenance validation | UX/Architecture | Accessibility Champion | Next | CI metadata integration | gate rejects stale/forged artifacts |
| P2 | Extend production manifest to error/recovery states | UX/UI | Product Design + QA | Later | capture runtime support | manifest coverage includes default/error/recovery |
| P2 | Split proposal status into spec vs operational readiness | Architecture | Engineering Manager | Later | proposal doc update | status reflects real gate health |

## 6. Execution Plan
- Now (0-2 weeks):
  - Fix iOS literal guard violations.
  - Run production capture scripts for both platforms and commit artifacts.
  - Regenerate Android state snapshots until duplicate threshold passes.
- Next (2-6 weeks):
  - Implement consolidated release certification report.
  - Add provenance validation for runtime accessibility assertions.
  - Perform one full green release rehearsal and archive report.
- Later (6+ weeks):
  - Expand production-state capture beyond default.
  - Improve runtime conformance checks for surface/elevation token usage.
  - Keep weekly exception and debt burndown audit cadence.

## 7. Open Questions
- Should release production manifest minimum coverage remain `default` only, or move to `default+error+recovery` immediately?
- Do we enforce a hard SLA for literal debt cleanup per wave (e.g., zero debt by wave signoff)?
- Which artifact should be treated as the single source for release-certifiable visual readiness in CI dashboards?

## 8. Detailed Evidence Pack

### A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 1-15 | Proposal now includes strengthened contracts, gates, and governance details. | Used as primary scope and acceptance reference. |
| DOC-02 | `bash scripts/run_visual_system_gates.sh` local run (2026-03-03) | output | Fails at iOS literal guard with new violations across multiple files. | Local run considered current operational signal. |
| DOC-03 | `bash scripts/run_visual_system_release_gates.sh` local run (2026-03-03) | output | Release gate fails at step 5 (`check_ios_visual_literals.sh`). | Release readiness blocked until literal debt cleanup. |
| DOC-04 | `artifacts/visual-system/snapshot-report.json` | full | Release snapshot check failed with 7 issues: Android duplicate ratio + 6 missing production artifacts. | Snapshot report treated as authoritative gate output. |
| DOC-05 | `docs/screenshots/review-visual-system-unification-r4/production/manifest.v1.json` | full | Manifest requires production screenshots for planning/dashboard/settings on iOS and Android. | Missing files are direct contract breach. |
| DOC-06 | `docs/screenshots/review-visual-system-unification-r4/production/` listing | folder | Only `README.md` and `manifest.v1.json` present; required PNG files absent. | Confirms production evidence not generated/committed. |
| DOC-07 | `scripts/run_visual_snapshot_checks.py` | 359-481 | Release mode enforces baseline diff, duplicate threshold, and production manifest artifact existence. | Gate logic is robust but currently failing on evidence. |
| DOC-08 | `scripts/run_visual_accessibility_checks.py` | 114-284 | Accessibility gate validates runtime assertions artifact structure and required flow assertions. | Pass signal depends on artifact correctness/provenance. |
| DOC-09 | `artifacts/visual-system/accessibility-report.json`, `ux-metrics-validation-report.json`, `variant-expiry-report.json` | full | Accessibility, UX metrics, and variant-expiry validators all pass. | These do not override snapshot/literal failures. |
| DOC-10 | Hash audit of state artifacts | command output | Android has one dominant duplicate group of 31 captures (ratio 0.9375). | Indicates evidence quality issue in captured state set. |
| DOC-11 | `scripts/capture_ios_production_flows.sh`, `scripts/capture_android_production_flows.sh` | full | Production capture scripts exist with defined flows and output paths. | Pipeline exists but has not produced required committed files. |

### B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ | 2025-06-09 | Apple positions Liquid Glass as expressive but content-focused and familiar. | Supports clarity-first visual hierarchy in finance surfaces. |
| WEB-02 | https://www.w3.org/TR/WCAG22/ | 2024-12-12 (Recommendation update) | WCAG 2.2 contrast and non-color semantics remain normative baseline. | Accessibility contract benchmark. |
| WEB-03 | https://developer.android.com/design/ui/mobile/guides/foundations/accessibility | Last updated 2023-05-08 UTC | Android guidance reiterates 4.5:1 text contrast, 3:1 non-text, 48dp targets. | Cross-platform accessibility parity baseline. |
| WEB-04 | https://developer.android.com/develop/ui/compose/designsystems/material3 | Crawled 2026-03; page recently updated | Material3 in Compose emphasizes tokenized theming, elevation, and accessibility-first design system usage. | Supports token contract and elevation policy rationale. |
| WEB-05 | https://developer.android.com/jetpack/androidx/releases/compose-material3 | Latest update listed: 2026-01-28 | Compose Material3 APIs continue to evolve; governance must be tool-enforced, not manual. | Supports need for continuous parity checks. |
| WEB-06 | https://developer.apple.com/design/human-interface-guidelines/ | Accessed 2026-03-03 | HIG principles: hierarchy, harmony, consistency. | Core rubric for iOS visual quality and system fit. |

### C. Screenshot/Artifact Log
| Evidence ID | Artifact | Result | Relevance |
|---|---|---|---|
| SCR-01 | `artifacts/visual-system/snapshot-report.json` | failed (issueCount=7) | Primary release visual evidence status. |
| SCR-02 | `docs/screenshots/review-visual-system-unification-r4/production/manifest.v1.json` | present | Required production artifacts contract. |
| SCR-03 | `docs/screenshots/review-visual-system-unification-r4/production/` | missing required PNG files | Blocking release evidence gap. |
| SCR-04 | Android hash audit over state captures | duplicate ratio 0.9375 | Integrity risk for state evidence set. |

### D. Assumptions and Constraints
- ASSUMP-01: This review scores readiness of proposal execution in current repository state.
- ASSUMP-02: No live GitHub Actions run log was used; local execution is the evidence source.
- CONSTRAINT-01: Without committed production captures, release visual certification cannot pass by design.
