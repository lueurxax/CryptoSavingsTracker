# Consolidated Proposal Review (R2)

## 0. Evidence Pack Summary
- Document inputs reviewed: 7
- Internet sources reviewed: 6
- Xcode screenshots captured: 0 new (reused 5 existing screenshots from prior evidence pack)
- Remaining assumptions:
  - Review scope is proposal readiness/governance quality, not implementation verification of all screens.
  - Existing screenshot set is sufficient for policy-level review; this R2 does not include fresh captures.
  - CI pipeline details are inferred from repository structure available on 2026-03-03.

## 1. Executive Summary
- Overall readiness: Amber (7.3/10)
- Top 3 risks:
  1. CI gate configuration paths in the proposal are currently non-existent in the repository, so merge-blocking policy is not yet executable.
  2. Token contract still includes descriptive entries that are hard to validate automatically, leaving parity drift risk.
  3. UX validation goals are directionally correct but not yet measurable enough for objective go/no-go decisions.
- Top 3 opportunities:
  1. Governance model, release-block policy, and wave-based migration are materially improved versus R1.
  2. A baseline token manifest (`docs/design/visual-tokens.v1.json`) now exists and can be hardened into strict schema validation.
  3. Performance and rollback concepts are present and can be operationalized with concrete automation and runbooks.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 7.5 | 0 | 1 | 2 | 0 |
| UX (Financial) | 7.0 | 0 | 1 | 1 | 0 |
| iOS Architecture | 7.2 | 0 | 2 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Token contract is not yet machine-verifiable end-to-end
  - Evidence: DOC-01, DOC-02, DOC-04
  - Why it matters: Visual parity promises cannot be enforced if token roles allow free-form descriptive values.
  - Recommended fix: Add strict schema fields per role (`light`, `dark`, `alpha`, `elevation`, `usageScope`, `componentScope`) and reject non-conforming entries in CI.
  - Acceptance criteria: Contract validation fails on any free-form role value for mapped parity roles.

- [Medium] Required state taxonomy is broader than explicit snapshot coverage
  - Evidence: DOC-01
  - Why it matters: Proposal requires 8 states (`default`, `pressed`, `disabled`, `error`, `loading`, `empty`, `stale`, `recovery`) but snapshot matrix does not explicitly guarantee full state coverage per priority component.
  - Recommended fix: Add a state-to-component snapshot matrix for release-blocking components.
  - Acceptance criteria: Snapshot manifest includes all required states for each priority component in both platforms.

- [Medium] Motion and transition rules remain unspecified
  - Evidence: DOC-01, WEB-01, WEB-02
  - Why it matters: Without transition policy, visual behavior can still diverge even with aligned colors/surfaces/elevation.
  - Recommended fix: Add transition contract for key states (press, loading, recovery, sheet/dialog presentation, reduced motion).
  - Acceptance criteria: Motion checklist exists and is validated in UI tests for priority flows.

### 3.2 UX Review Findings
- [High] UX success metrics are not operationalized
  - Evidence: DOC-01
  - Why it matters: "improvement vs baseline" language is not enough for release decisions in finance-critical screens.
  - Recommended fix: Define numeric thresholds, sample size, measurement event names, and sign-off owner for each metric.
  - Acceptance criteria: Each wave has objective pass/fail criteria and a published pre/post metrics report.

- [Medium] Recovery communication for visual rollback is underdefined for users
  - Evidence: DOC-01
  - Why it matters: Internal rollback toggles are defined, but user-facing clarity during visual recovery scenarios is not specified.
  - Recommended fix: Add user-visible fallback behavior guidance for critical screens (status explanation + consistent semantics).
  - Acceptance criteria: Rollback runbook includes UX copy and behavior checks for affected flows.

### 3.3 Architecture Review Findings
- [High] CI gate paths in proposal do not match repository state
  - Evidence: DOC-01, DOC-03, DOC-05
  - Why it matters: Proposed commands reference `ios/.swiftlint.yml` and `android/config/detekt/detekt.yml`, which are currently absent.
  - Recommended fix: Either create these files now or update proposal to actual config locations and owner-maintained scripts.
  - Acceptance criteria: CI runs both gates and fails on injected raw visual literal violations.

- [High] Rollback toggles are named but not operationalized
  - Evidence: DOC-01
  - Why it matters: Toggle names alone are insufficient to guarantee rollback SLA under incident pressure.
  - Recommended fix: Define flag provider, defaults, release wiring, drill cadence, and observability hooks.
  - Acceptance criteria: Rollback drill proves each wave can be disabled within SLA.

- [Medium] Parity-check mechanism is not specified as executable command/pipeline stage
  - Evidence: DOC-01, DOC-02
  - Why it matters: "zero unresolved token mismatches" is not verifiable without deterministic check tooling.
  - Recommended fix: Add a parity checker script with expected output format and CI integration.
  - Acceptance criteria: PR fails when token role mapping diverges between iOS and Android manifests.

- [Medium] Ownership is defined, but escalation path for blocked merges is incomplete
  - Evidence: DOC-01
  - Why it matters: Merge-blocking gates need explicit escalation timing and approver fallback to avoid delivery stalls.
  - Recommended fix: Define incident severity matrix and escalation ladder (platform lead -> design lead -> EM).
  - Acceptance criteria: Governance section includes response timelines and backup approvers.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Strong platform expression vs strict cross-platform parity
  - Tradeoff: Over-normalization can reduce platform-native clarity; under-normalization reintroduces inconsistency.
  - Decision: Keep semantic parity at token/state level while allowing documented platform-specific implementation nuances.
  - Owner: Mobile Platform Lead + Design Lead.

- Conflict: Fast rollout vs measurable quality gates
  - Tradeoff: Shipping quickly can bypass incomplete instrumentation and create subjective acceptance.
  - Decision: Keep wave rollout, but make release-blocking criteria strictly metric and artifact based.
  - Owner: Engineering Manager + QA Automation Lead.

- Conflict: Flexible exception policy vs enforcement integrity
  - Tradeoff: Too many exceptions erode consistency; too few can block legitimate platform constraints.
  - Decision: Allow temporary exceptions only with owner, expiry, and removal task linked to milestone.
  - Owner: Platform delegates (iOS/Android leads).

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Align proposal lint paths with real repo and create missing configs | Architecture | iOS Lead + Android Lead | Now | CI pipeline update | Both lint gates execute and fail on seeded violations |
| P0 | Harden `visual-tokens.v1.json` with strict schema and validator | UI/Architecture | Mobile Platform Lead | Now | Token schema draft | Contract validation blocks non-structured role entries |
| P0 | Define measurable UX thresholds for wave acceptance | UX | UX Research + Product Design | Now | Analytics event map | Wave reports include objective pass/fail KPI outcomes |
| P1 | Add explicit state coverage matrix (8 required states x priority components) | UI/QA | QA Automation Lead | Next | Snapshot harness | Snapshot manifest covers all required states |
| P1 | Implement parity diff checker and wire into CI | Architecture | Mobile Platform Team | Next | Token schema | CI blocks unresolved cross-platform token mismatches |
| P1 | Operationalize rollback runbook (flags, drills, observability) | Architecture/UX | Engineering Manager | Next | Flag infrastructure | Rollback drill meets SLA and checklist passes |
| P2 | Add motion/transition contract with reduced-motion behavior | UI/UX | Design Lead | Later | State matrix | UI tests validate transition consistency in critical flows |
| P2 | Define merge-block escalation matrix and backup approvers | Architecture/Governance | Mobile Platform Lead | Later | Governance update | Blocked merge incidents resolved within defined response times |

## 6. Execution Plan
- Now (0-2 weeks):
  - Fix configuration path mismatch and stand up working lint gates.
  - Formalize token schema validation and measurable UX thresholds.
  - Publish ownership and artifact expectations for wave sign-off.
- Next (2-6 weeks):
  - Implement state-complete snapshot matrix and parity diff checker.
  - Run first rollback drill with documented outcomes and remediation.
  - Apply gates to Wave 1 planning flow as hard release criteria.
- Later (6+ weeks):
  - Expand motion/transition contract and reduced-motion QA coverage.
  - Mature governance escalation process and exception audit cadence.
  - Institutionalize parity dashboards for ongoing maintenance.

## 7. Open Questions
- Which exact CI jobs own visual lint, parity diff, and snapshot state coverage checks?
- What is the minimum sample size and confidence threshold for UX metric sign-off per wave?
- Should chart motion semantics be included in this proposal or handled in a dedicated data-viz extension ADR?

## 8. Detailed Evidence Pack

### A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 1-14 | Revised proposal defines token contract, wave rollout, CI gates, performance budgets, and governance. | Review focuses on proposal operability/readiness. |
| DOC-02 | `docs/design/visual-tokens.v1.json` | roles/governance | Baseline token manifest exists with role mapping and ownership fields. | Some role values remain descriptive and need stricter schema. |
| DOC-03 | repo filesystem check | config paths | `ios/.swiftlint.yml` and `android/config/detekt/detekt.yml` are missing at specified proposal paths. | Path mismatch may be doc-only or implementation gap; treated as readiness risk. |
| DOC-04 | `ios/CryptoSavingsTracker/Utilities/AccessibleColors.swift` | token source | iOS token primitives for semantic color roles are present. | Contract should reference exact machine-validated mappings. |
| DOC-05 | `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/theme/Color.kt` and `.../Elevation.kt` | token source | Android semantic color and elevation primitives are present. | Parity checker required to ensure alignment remains stable. |
| DOC-06 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL_TRIAD_REVIEW_R1.md` | prior findings | Prior high-risk gaps were partially addressed in revised proposal. | R2 validates closure quality and identifies remaining execution gaps. |
| DOC-07 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL_TRIAD_REVIEW_R1.md` | governance pattern | Comparable proposal used actionable ledger/gate framing useful for alignment quality check. | Used as quality calibration reference, not direct scope dependency. |

### B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://developer.apple.com/documentation/technologyoverviews/liquid-glass | Retrieved 2026-03-03 | Liquid Glass emphasizes hierarchy and focus, not decorative complexity. | UI material and depth policy validation. |
| WEB-02 | https://developer.apple.com/design/human-interface-guidelines/ | Retrieved 2026-03-03 | Platform fidelity and clear interaction semantics are required for trust. | iOS presentation quality baseline. |
| WEB-03 | https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ | 2025-06-09 | New Apple design direction stresses familiarity + clarity. | Supports calm-surface approach in finance-critical flows. |
| WEB-04 | https://www.w3.org/TR/WCAG22/ | 2024-12-12 | WCAG 2.2 formal contrast and non-color semantic requirements. | Accessibility contract criteria. |
| WEB-05 | https://developer.android.com/design/ui/mobile/guides/foundations/accessibility | Retrieved 2026-03-03 | Android guidance reinforces contrast, touch target, and non-color cues. | Cross-platform accessibility parity baseline. |
| WEB-06 | https://developer.android.com/jetpack/androidx/releases/compose-material3 | Retrieved 2026-03-03 | Material 3 evolves theming/elevation APIs and expectations. | Android token/elevation contract validation. |

### C. Xcode Screenshot Log (reused)
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-visual-system-unification-r1/planning-01-main-iphone17pro-light.png` | Planning entry | Main | iPhone 17 Pro | Baseline hierarchy/depth in primary finance flow. |
| SCR-02 | `docs/screenshots/review-visual-system-unification-r1/planning-02-main-macos-light.png` | Planning desktop variant | Main | macOS preview | Cross-size consistency reference. |
| SCR-03 | `docs/screenshots/review-visual-system-unification-r1/planning-03-goalrow-normal-iphone17pro-light.png` | Goal row | Default | iPhone 17 Pro | Component-level state consistency evidence. |
| SCR-04 | `docs/screenshots/review-visual-system-unification-r1/planning-04-goalrow-critical-iphone17pro-light.png` | Goal row | Critical | iPhone 17 Pro | Critical-state emphasis and readability evidence. |
| SCR-05 | `docs/screenshots/Simulator Screenshot - iPhone 16 Pro Max - 2025-08-26 at 20.35.14.png` | Dashboard baseline | Historical | iPhone 16 Pro Max | Supplemental dashboard evidence. |

### D. Assumptions and Constraints
- ASSUMP-01: This review evaluates proposal readiness, not implementation completion.
- ASSUMP-02: Existing screenshot set is accepted as sufficient for policy-level critique in R2.
- ASSUMP-03: CI configuration mismatch is treated as unresolved until paths/scripts exist in-repo.
- CONSTRAINT-01: Cross-platform parity depends on introducing an executable validator, not only documented mapping.
