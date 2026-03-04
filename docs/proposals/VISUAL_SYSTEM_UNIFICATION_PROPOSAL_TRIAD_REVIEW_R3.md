# Consolidated Proposal Review (R3)

## 0. Evidence Pack Summary
- Document inputs reviewed: 9
- Internet sources reviewed: 6
- Xcode screenshots captured: 0 new, 4 reused from existing review pack
- Remaining assumptions:
  - Review scope is proposal quality and execution readiness, not full implementation delivery.
  - Existing screenshot set is sufficient for policy-level visual assessment in this pass.
  - CI provider/workflow implementation is not present in repository and is treated as open delivery work.

## 1. Executive Summary
- Overall readiness: Amber (7.8/10)
- Top 3 risks:
  1. CI jobs are specified in proposal, but no repository CI workflow wiring exists yet, so merge-blocking guarantees are not operational.
  2. Release strict state gate is defined but currently fails for most required states, which conflicts with release-gate narrative.
  3. Token parity checker is deterministic but still shallow for non-elevation roles, allowing semantic drift to pass.
- Top 3 opportunities:
  1. Proposal evolved to executable artifacts (schema, scripts, baselines, runbook), significantly reducing ambiguity from R1.
  2. Governance model (owners, escalation, exception audit cadence) is now explicit and actionable.
  3. UX metrics and rollback policies are now measurable enough to support wave-level go/no-go decisions after CI wiring.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 8.1 | 0 | 1 | 2 | 0 |
| UX (Financial) | 7.9 | 0 | 1 | 2 | 0 |
| iOS Architecture | 7.4 | 0 | 2 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Snapshot/accessibility jobs remain non-executable in contract table
  - Evidence: DOC-01, DOC-08
  - Why it matters: `visual-accessibility` and `visual-snapshots` are declared as blocking jobs, but commands are still abstract placeholders, so visual quality can regress without deterministic CI enforcement.
  - Recommended fix: Replace placeholders with concrete command entrypoints (or scripts) and artifact output paths.
  - Acceptance criteria: Both jobs can be executed locally and in CI with deterministic pass/fail outputs.

- [Medium] Strict state coverage is specified but not realistically staged in wave policy
  - Evidence: DOC-01, DOC-03
  - Why it matters: Proposal asks for strict state capture at release gate, but matrix shows mostly `planned` status; governance should explicitly separate design-complete vs release-complete phases.
  - Recommended fix: Add phased state requirements per wave milestone (`design-complete`, `qa-complete`, `release-candidate`).
  - Acceptance criteria: For each wave milestone, required state statuses are explicit and validated by script.

- [Medium] Component visual examples are still planning-heavy and dashboard/settings-light
  - Evidence: SCR-01, SCR-02, SCR-03, SCR-04
  - Why it matters: UI policy confidence is strongest for planning flow; dashboard/settings risk remains relatively less evidenced.
  - Recommended fix: Add representative dashboard/settings screenshots for default+error states in both platforms.
  - Acceptance criteria: Screenshot pack contains state evidence for all release-blocking flows, not only planning-focused views.

### 3.2 UX Review Findings
- [High] Metric instrumentation is defined, but decision protocol is incomplete
  - Evidence: DOC-01, DOC-09
  - Why it matters: Metrics have thresholds and sample sizes, but proposal does not define who has final authority when one metric passes and another fails.
  - Recommended fix: Add wave decision rubric (`all must pass` vs weighted policy), tie-break ownership, and exception path.
  - Acceptance criteria: Wave signoff template includes deterministic metric decision logic and approver list.

- [Medium] Rollback UX runbook lacks communication templates for user-facing incidents
  - Evidence: DOC-06
  - Why it matters: Runbook defines technical rollback checks, but customer-facing communication (release note/banner/support script) is not defined for trust-critical finance regressions.
  - Recommended fix: Add incident communication templates and trigger conditions to rollback runbook.
  - Acceptance criteria: Runbook includes pre-approved copy patterns and channel owner for `sev1/sev2` incidents.

- [Medium] Motion contract lacks explicit assistive-tech verification steps
  - Evidence: DOC-01, WEB-02, WEB-05
  - Why it matters: Reduced Motion is specified, but no explicit VoiceOver/TalkBack motion-related test protocol is attached.
  - Recommended fix: Extend motion validation with accessibility test cases per platform.
  - Acceptance criteria: Accessibility suite includes reduced-motion + screen reader combined scenarios for release-blocking screens.

### 3.3 Architecture Review Findings
- [High] CI governance is documented without actual CI workflow implementation in repo
  - Evidence: DOC-01, DOC-04
  - Why it matters: Contract-level enforcement remains aspirational until jobs are wired into real pipeline definitions.
  - Recommended fix: Add CI workflow configs (or equivalent) implementing section 9.3 jobs with required artifacts.
  - Acceptance criteria: PR pipeline visibly runs declared visual jobs and blocks merges on failure.

- [High] Parity checker under-validates `aligned` color/surface semantics
  - Evidence: DOC-07
  - Why it matters: Current checker validates kind and expiry logic, but does not compare many semantic fields for aligned roles, allowing subtle drift.
  - Recommended fix: Expand parity script to compare required fields by `roleType` when `parity.status == aligned`.
  - Acceptance criteria: Introduced mismatch in aligned role spec fails parity job.

- [Medium] Local gate entrypoint does not run strict state mode by default
  - Evidence: DOC-05, DOC-03
  - Why it matters: Local/CI parity between intended release strictness and default command behavior is weak.
  - Recommended fix: Add explicit release-mode entrypoint (`--strict`) and document when each mode is mandatory.
  - Acceptance criteria: Release pipeline always runs strict state gate; non-release branches may run non-strict mode.

- [Medium] Literal guard currently confirms live drift in iOS planning view
  - Evidence: DOC-05
  - Why it matters: Governance is working (it catches violations), but active violations indicate migration debt in release-blocking domain.
  - Recommended fix: Prioritize tokenization cleanup of current violations before claiming gate stability.
  - Acceptance criteria: `scripts/run_visual_system_gates.sh` passes with no new literal violations.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Strict quality gates vs delivery velocity
  - Tradeoff: Immediate hard enforcement may block active migration throughput.
  - Decision: Keep hard merge blocks for release branches; allow controlled non-release staging with explicit debt burn-down.
  - Owner: Engineering Manager + Mobile Platform Lead.

- Conflict: Platform-native nuance vs strict parity
  - Tradeoff: Over-constraining platform expression can hurt native feel; under-constraining reintroduces inconsistency.
  - Decision: Keep `approved_variant` path with expiry and weekly audits; strengthen aligned-role comparisons.
  - Owner: Mobile Platform Lead + Design Lead.

- Conflict: UX metric rigor vs research bandwidth
  - Tradeoff: High confidence thresholds can slow waves if research throughput is limited.
  - Decision: Preserve thresholds, but pre-plan participant/task capacity per wave milestone.
  - Owner: UX Research Lead.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Implement real CI workflows for section 9.3 jobs | Architecture | Mobile Platform Team | Now | CI provider setup | Declared visual jobs run on PRs and block on failures |
| P0 | Expand parity checker for aligned role field-level comparison | Architecture/UI | Mobile Platform Team | Now | `visual-tokens.v1.json` contract | Injected aligned-role mismatch fails parity check |
| P0 | Define wave metric decision protocol (pass/fail arbitration) | UX/Governance | Product Design + UX Research | Now | Existing metric table | Wave signoff no longer requires subjective tie-breaks |
| P1 | Add release-mode strict gate command and enforce in release pipeline | Architecture | QA Automation + Platform | Next | CI workflow wiring | Release branch cannot merge if strict state gate fails |
| P1 | Add dashboard/settings state screenshot evidence pack | UI/QA | QA Automation | Next | Screenshot harness | All release-blocking flows have state evidence coverage |
| P1 | Add rollback communication templates to runbook | UX/Operations | Product + Support | Next | Runbook ownership | `sev1/sev2` rollback includes approved user messaging |
| P2 | Extend motion validation with assistive-tech scenarios | UX/UI | Accessibility Champion | Later | Accessibility suite updates | Reduced-motion + VO/TalkBack tests pass in release flows |
| P2 | Continue literal debt burn-down to stabilize guard signal | UI Architecture | iOS Lead | Later | Tokenized replacements | No recurring literal violations in release-blocking screens |

## 6. Execution Plan
- Now (0-2 weeks):
  - Wire proposal-declared jobs into actual CI workflows.
  - Harden parity script semantics for aligned roles.
  - Add deterministic metric decision rubric for wave signoff.
- Next (2-6 weeks):
  - Enforce strict state mode in release pipeline.
  - Close screenshot evidence gaps for dashboard/settings.
  - Extend rollback runbook with user communication protocol.
- Later (6+ weeks):
  - Add assistive-tech motion validation.
  - Complete remaining tokenization debt in release-blocking flows.
  - Track long-term gate signal stability and false-positive rate.

## 7. Open Questions
- Which CI platform will host section 9.3 jobs and own maintenance SLA?
- Should strict state gate be required for every release-candidate commit or only final pre-cut gate?
- What is the accepted override policy if UX metric thresholds miss by narrow confidence margins?

## 8. Detailed Evidence Pack

### A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 1-15 | Proposal now includes token schema, state matrix, UX thresholds, CI table, rollback/escalation, and DoD artifacts. | Review targets execution readiness of this revision. |
| DOC-02 | `docs/design/visual-tokens.v1.json` | roles/parity/governance | Contract is now structured with roleType/spec/parity metadata and expiry on variants. | Variants are temporary and require expiry discipline. |
| DOC-03 | `docs/design/visual-state-matrix.v1.json` | component states | Matrix covers required states but many entries remain `planned`, not `captured`. | Strict release gate currently not satisfied. |
| DOC-04 | repo root (`.github` absent) | CI wiring | No repository CI workflow definitions found for declared job names. | CI job table currently documents intent, not implemented pipeline. |
| DOC-05 | `scripts/run_visual_system_gates.sh` + run output | gates execution | Local gate run fails on new iOS visual literal violations. | Guard is effective but indicates active migration drift. |
| DOC-06 | `docs/runbooks/visual-system-rollback.md` | rollback process | Technical rollback procedure and SLA are documented. | User communication protocol remains minimal. |
| DOC-07 | `scripts/check_visual_token_parity.py` | parity logic | Parity checker validates expiry/kind and limited elevation deltas; aligned role deep compare is limited. | Additional semantic checks are needed for stronger drift protection. |
| DOC-08 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 9.3 job table | `visual-accessibility` and `visual-snapshots` commands remain abstract placeholders. | Requires command-level concretization for deterministic CI. |
| DOC-09 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 7.2 metrics | UX thresholds and sample sizes are specified. | Arbitration logic for mixed metric outcomes is still needed. |

### B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ | 2025-06-09 | Apple emphasizes clarity/familiarity while introducing richer materials. | Supports calm, trust-oriented finance UI direction. |
| WEB-02 | https://www.w3.org/TR/WCAG22/ | 2024-12-12 | WCAG 2.2 Recommendation formalizes contrast and non-color semantic requirements. | Basis for accessibility gate thresholds. |
| WEB-03 | https://developer.android.com/design/ui/mobile/guides/foundations/accessibility | Last updated 2023-09-26 | Android guidance reinforces contrast, touch targets, and semantic accessibility cues. | Cross-platform accessibility parity baseline. |
| WEB-04 | https://developer.android.com/jetpack/androidx/releases/compose-material3 | Last updated 2026-02-25 | Compose Material3 evolves themed components and platform conventions. | Relevant for Android token/elevation enforcement approach. |
| WEB-05 | https://developer.android.com/develop/ui/compose/designsystems/material3 | Last updated 2025-10-10 | Material 3 docs emphasize design-system token usage and theming consistency. | Supports token-only visual policy for Compose UI. |
| WEB-06 | https://developer.apple.com/design/human-interface-guidelines/ | Retrieved 2026-03-03 | HIG remains platform trust/fidelity baseline for iOS interaction semantics. | UI fidelity reference for iOS side of contract. |

### C. Xcode Screenshot Log (reused)
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-visual-system-unification-r1/planning-01-main-iphone17pro-light.png` | Planning entry | Main | iPhone 17 Pro | Baseline hierarchy and CTA emphasis evidence. |
| SCR-02 | `docs/screenshots/review-visual-system-unification-r1/planning-02-main-macos-light.png` | Planning desktop variant | Main | macOS preview | Cross-size consistency reference. |
| SCR-03 | `docs/screenshots/review-visual-system-unification-r1/planning-03-goalrow-normal-iphone17pro-light.png` | Goal row | Default | iPhone 17 Pro | Default state row semantics evidence. |
| SCR-04 | `docs/screenshots/review-visual-system-unification-r1/planning-04-goalrow-critical-iphone17pro-light.png` | Goal row | Critical/error-like | iPhone 17 Pro | Critical state prominence and readability evidence. |

### D. Assumptions and Constraints
- ASSUMP-01: This review evaluates policy/architecture readiness, not full product rollout completion.
- ASSUMP-02: Existing screenshot corpus is sufficient for this proposal-level pass.
- ASSUMP-03: CI workflow absence is considered an execution risk even if external CI setup may be planned.
- CONSTRAINT-01: Strict state coverage expectations depend on screenshot generation capacity across both platforms.
