# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed: 10
- Internet sources reviewed: 5
- Xcode screenshots captured: 5 (4 fresh preview captures, 1 existing baseline screenshot)
- Remaining assumptions:
  - Dashboard and Settings previews were partially blocked by active concurrent simulator/build processes and preview runtime crashes during this review window.
  - No linked PRD/KPI artifact was provided beyond the proposal itself.

## 1. Executive Summary
- Overall readiness: Amber
- Top 3 risks:
  1. The proposal defines direction but not enforceable visual specifications (token numbers, elevation values, motion rules, ownership), so implementation can drift.
  2. Cross-platform parity is declared (`iOS + Android`) but not operationalized with a shared contract and validation gates.
  3. Acceptance criteria are too broad to verify consistently in CI (contrast/hierarchy review is not measurable as written).
- Top 3 opportunities:
  1. The proposal correctly identifies fragmentation and the highest-impact components first.
  2. Existing code already has token foundations (`AccessibleColors`, Android theme/elevation objects), so convergence can be accelerated.
  3. A strict migration + lint + visual-regression pipeline can turn this into a low-regression system-level improvement.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 5 | 0 | 2 | 2 | 0 |
| UX (Financial) | 5 | 0 | 2 | 2 | 0 |
| iOS Architecture | 4 | 1 | 2 | 2 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Visual system decisions are not implementation-grade
  - Evidence: DOC-02, DOC-04, DOC-05, WEB-03
  - Why it matters: The proposal says “canonical tokens” and “single elevation model” but does not define concrete token sets (role names, values, allowed alpha/blur/elevation per component state), so design consistency cannot be enforced.
  - Recommended fix: Add a token contract table per platform with parity mapping (`role`, iOS token, Android token, light/dark values, allowed usage scope).
  - Acceptance criteria: 100% of priority components reference only approved tokens; no component ships with undocumented color/shadow/material parameters.

- [High] Material usage policy is ambiguous for finance-critical surfaces
  - Evidence: DOC-02, DOC-06, DOC-07, SCR-01, SCR-03, WEB-01
  - Why it matters: Current code mixes `.regularMaterial`, hard shadows, and gray overlays. Without explicit “when to use glass vs solid surfaces,” visual depth can add noise where users need precision and trust.
  - Recommended fix: Define a surface policy matrix for each component type (header card, row, summary card, settings row): `surface style`, `border`, `shadow/elevation`, and `interaction state`.
  - Acceptance criteria: Component specs include one allowed surface pattern per context; design QA rejects any unapproved depth treatment.

- [Medium] Component state coverage is incomplete
  - Evidence: DOC-03, DOC-04, DOC-05, DOC-07
  - Why it matters: Proposal includes `default/pressed/disabled/error`, but finance flows also require `loading`, `empty`, `stale`, and `recovering` states; these currently show style variance.
  - Recommended fix: Expand state taxonomy and require each priority component to ship full state visual specs.
  - Acceptance criteria: Every priority component has approved visuals for `default/pressed/disabled/error/loading/empty/recovery`.

- [Medium] “Ban ad-hoc colors/shadows” has no enforcement mechanism
  - Evidence: DOC-05, DOC-06, DOC-07
  - Why it matters: Existing files still contain raw colors (`Color.gray`, `.red`, `.orange`, `.green`) and repeated shadow literals. A policy without static checks will regress quickly.
  - Recommended fix: Add SwiftLint/Detekt custom rules for raw color and shadow literals in presentation code, with allowlists for design-token files only.
  - Acceptance criteria: CI fails on new ad-hoc visual literals outside token modules.

### 3.2 UX Review Findings
- [High] Success criteria miss user trust and comprehension outcomes
  - Evidence: DOC-05, WEB-01
  - Why it matters: “Same visual weight” and “no ad-hoc colors/shadows” do not prove better financial decision support; users still need to quickly explain numbers, urgency, and required actions.
  - Recommended fix: Add UX success metrics tied to financial tasks (time-to-understand status, action accuracy, misinterpretation rate in usability sessions).
  - Acceptance criteria: Pre/post usability benchmarks show measurable improvement on planning and dashboard interpretation tasks.

- [High] Accessibility criteria are under-specified for finance workflows
  - Evidence: DOC-05, WEB-02, WEB-04
  - Why it matters: Proposal mentions “contrast and hierarchy review,” but no explicit criteria for non-color cues, dynamic type behavior, touch target thresholds, or VoiceOver labeling.
  - Recommended fix: Attach an accessibility checklist to the proposal: WCAG contrast thresholds, non-color redundancy for status, dynamic type layouts, and screen-reader narration rules.
  - Acceptance criteria: Priority screens pass documented accessibility checks in light/dark at default and large text sizes.

- [Medium] Migration sequencing may create temporary cognitive inconsistency
  - Evidence: DOC-03, DOC-04, SCR-01, SCR-05
  - Why it matters: Rolling components one-by-one without user-facing guardrails can produce mixed visual language, reducing confidence in money-related screens.
  - Recommended fix: Sequence migration by complete user journeys (Planning flow first, then Dashboard, then Settings), not by isolated component type only.
  - Acceptance criteria: No primary flow contains mixed old/new visual grammar in the same release wave.

- [Medium] Error and recovery visual patterns are not defined for the system itself
  - Evidence: DOC-03, DOC-05
  - Why it matters: Visual system updates can introduce low-contrast or misread states. The proposal lacks rollback cues and fallback styling in case of detected readability regressions.
  - Recommended fix: Define “safe fallback” styles and an incident response playbook for visual regressions.
  - Acceptance criteria: Teams can toggle affected visual tokens/components back to baseline within one release cycle.

### 3.3 Architecture Review Findings
- [Critical] Cross-platform parity is declared but not modeled as a governed contract
  - Evidence: DOC-04, DOC-08, DOC-09, DOC-10
  - Why it matters: iOS and Android both have token foundations, but naming/value scopes and raw-color exceptions still diverge. Without a versioned parity map, “iOS + Android” unification is not reliable.
  - Recommended fix: Introduce a versioned `visual-tokens.json` (or equivalent) as source-of-truth, with platform generators/adapters and parity diff checks.
  - Acceptance criteria: Automated parity check reports zero unresolved token mismatches for migrated components.

- [High] No operable compliance gates for “no ad-hoc visuals”
  - Evidence: DOC-05, DOC-06, DOC-07, DOC-08
  - Why it matters: The proposal depends on manual review; this is not scalable across many view files and future contributors.
  - Recommended fix: Add static analysis gates in both platforms plus PR templates requiring evidence of token-only usage.
  - Acceptance criteria: CI includes lint gates and blocks merges on ad-hoc visual literals.

- [High] Visual regression strategy lacks executable test matrix
  - Evidence: DOC-04, SCR-01, SCR-02, SCR-03, SCR-04
  - Why it matters: “Add visual regression snapshots” is directionally right but missing canonical scenarios, devices, themes, tolerance thresholds, and ownership.
  - Recommended fix: Define snapshot matrix (screens x states x light/dark x compact/regular), baseline governance, and failure triage owner.
  - Acceptance criteria: Snapshot pipeline runs on every PR for priority screens; failures include diff artifacts and clear owner routing.

- [Medium] Performance risk of layered materials in dense lists is not addressed
  - Evidence: DOC-02, DOC-06, DOC-07, SCR-01
  - Why it matters: Material + blur + shadow combinations can increase render cost on long scrolling financial lists.
  - Recommended fix: Add performance budgets (scroll FPS, frame drops, CPU/GPU targets) and run trace checks before/after migration.
  - Acceptance criteria: Key flows meet agreed frame-time budgets on representative devices.

- [Medium] Rollout/rollback mechanics are missing
  - Evidence: DOC-04, DOC-05
  - Why it matters: A broad visual system migration needs blast-radius control and rollback path, especially for finance-critical flows.
  - Recommended fix: Add feature flags per component group and phased rollout plan with observability checkpoints.
  - Acceptance criteria: Each migration wave can be disabled independently without app update rollback.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: Rich Liquid Glass styling vs finance readability/performance.
  - Tradeoff: Visual vitality can reduce clarity and increase rendering cost on dense data screens.
  - Decision: Use “calm surfaces by default” in core finance flows; reserve stronger glass effects for navigation chrome and non-critical affordances.
  - Owner: Design Lead + iOS/Android Leads.

- Conflict: Fast migration vs consistency guarantees.
  - Tradeoff: Rapid component-by-component changes can create mixed-language UX.
  - Decision: Migrate by complete flow slices and block partial slices from release.
  - Owner: Product Manager + Engineering Manager.

- Conflict: Manual design review vs CI enforcement.
  - Tradeoff: Manual checks are flexible but brittle at scale.
  - Decision: Add lint + snapshot gates; keep manual review for exceptions only.
  - Owner: Mobile Platform Team.

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Define versioned cross-platform token contract and parity map | Architecture | Mobile Platform Lead | Now | Design token workshop | 0 unresolved parity diffs on migrated components |
| P0 | Add lint rules to block ad-hoc color/shadow literals | Architecture/UI | iOS + Android Leads | Now | Token contract | CI blocks all new ad-hoc visual literals |
| P0 | Publish component surface/elevation policy matrix for priority components | UI | Design Lead | Now | Token contract draft | 100% priority specs approved |
| P1 | Implement snapshot regression matrix (light/dark, compact/regular, critical states) | Architecture/UI | QA Automation Lead | Next | Stable preview/runtime harness | Snapshot suite passes on all priority screens |
| P1 | Add UX trust/comprehension metrics to acceptance criteria | UX | Product Designer + UX Research | Next | Usability plan | Measurable pre/post improvement on planning/dashboard comprehension |
| P1 | Add accessibility compliance checklist (contrast, non-color cues, dynamic type, VoiceOver) | UX/UI | Accessibility Champion | Next | Token/state specs | Checklist pass rate 100% for priority flow |
| P2 | Add performance budgets and profiling gates for material-heavy views | Architecture | Mobile Performance Owner | Later | Snapshot matrix + profiling scripts | Frame-time and drop-rate budgets met |
| P2 | Introduce feature-flagged rollout and rollback playbook | Architecture/UX | Engineering Manager | Later | Flag infrastructure | Component wave can be disabled within one release cycle |

## 6. Execution Plan
- Now (0-2 weeks):
  - Finalize token schema, parity mapping, and component surface matrix.
  - Add lint rules and fail-fast CI gates.
  - Re-baseline preview/snapshot infrastructure to remove runtime instability.
- Next (2-6 weeks):
  - Migrate priority components by full user-flow slices.
  - Stand up visual regression matrix and accessibility checklist automation.
  - Run targeted UX validation for planning and dashboard comprehension.
- Later (6+ weeks):
  - Expand system to remaining modules.
  - Add performance budgets and rollout flags for long-term operability.
  - Institutionalize token versioning and change governance.

## 7. Open Questions
- Who owns token governance when iOS and Android need platform-specific exceptions?
- Which flows are release-blocking if snapshot/accessibility checks fail?
- What is the allowed timeline for mixed old/new visual styles during migration?
- Should chart palettes be unified under the same token contract or treated as a separate data-viz system?

## 8. Detailed Evidence Pack

### A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | Metadata | Status is `Draft`; scope is `iOS + Android`. | Review assumes proposal is pre-implementation governance doc. |
| DOC-02 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 3) Design System Decisions | Calls for canonical semantic tokens, single elevation model, gradient restrictions. | No numeric token/elevation values are specified yet. |
| DOC-03 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 4) Component Normalization | Priority components listed: planning header cards, goal rows, dashboard cards, settings rows. | Full state definitions are only partially listed. |
| DOC-04 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 5) Implementation Strategy | Mentions token map, style guide, priority migration, snapshot regression. | Lacks ownership, tooling, and exact test matrix. |
| DOC-05 | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` | 6) Acceptance Criteria | Requires no ad-hoc colors/shadows and contrast/hierarchy pass. | Not yet measurable as written. |
| DOC-06 | `ios/CryptoSavingsTracker/Views/Planning/GoalRequirementRow.swift` | code refs | `.regularMaterial`, `.shadow(.black.opacity(...))`, `Color.gray` fallback exist (e.g., lines 53, 55, 673). | Current implementation shows mixed visual primitives. |
| DOC-07 | `ios/CryptoSavingsTracker/Views/Dashboard/DashboardComponents.swift` | code refs | Repeated hard shadow and gray stroke literals (e.g., lines 143, 158-174, 263, 449, 562). | Dashboard still relies on ad-hoc effects. |
| DOC-08 | `ios/CryptoSavingsTracker/Views/Settings/MonthlyPlanningSettingsView.swift` | code refs | Direct `.red/.orange/.green/.blue` and `Color.gray.opacity` usage (e.g., lines 324-325, 433-442, 632, 688, 698). | Settings semantics are partly color-literal driven. |
| DOC-09 | `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/theme/Color.kt` and `.../theme/Elevation.kt` | theme | Android has color/elevation tokens (`Color(...)`, `Elevation.card = 2.dp`, etc.). | Token layer exists but parity governance is not defined. |
| DOC-10 | `android/app/src/main/res/values/colors.xml` and presentation files | resources/code refs | Legacy palette entries (purple/teal) still exist; multiple screens still use raw `Color(0x...)`. | Token adoption is incomplete across Android presentation code. |

### B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ | 2025-06-09 | Apple positions Liquid Glass as increasing focus on content while preserving familiarity. | Anchors UI direction for “calm clarity + depth”. |
| WEB-02 | https://www.w3.org/TR/WCAG22/ | 2024-12-12 (W3C Recommendation) | WCAG 2.2 includes contrast and use-of-color requirements relevant to finance-critical UI. | Baseline accessibility standard for acceptance criteria. |
| WEB-03 | https://developer.android.com/develop/ui/compose/designsystems/material3 | 2026-02-26 (page last updated) | Material 3 emphasizes theme color systems and tonal/shadow elevation modeling. | Cross-platform parity reference for Android implementation. |
| WEB-04 | https://developer.android.com/design/ui/mobile/guides/foundations/accessibility | 2023-05-08 (page last updated) | Reiterates 4.5:1 text contrast, 3:1 non-text contrast, and non-color-only affordances. | Concrete criteria for proposal accessibility hardening. |
| WEB-05 | https://developer.apple.com/design/human-interface-guidelines/ | Retrieved 2026-03-02 (no explicit publish date on page) | HIG frames platform-consistent hierarchy and clarity expectations. | Apple platform fidelity reference for iOS-first surfaces. |

### C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-visual-system-unification-r1/planning-01-main-iphone17pro-light.png` | Planning entry | Normal/main | Xcode Preview, iPhone 17 Pro simulator | Baseline hierarchy/depth in core planning flow. |
| SCR-02 | `docs/screenshots/review-visual-system-unification-r1/planning-02-main-macos-light.png` | Planning desktop variant | Normal/main | Xcode Preview, macOS canvas | Cross-size/platform consistency check. |
| SCR-03 | `docs/screenshots/review-visual-system-unification-r1/planning-03-goalrow-normal-iphone17pro-light.png` | Goal row | Default/normal | Xcode Preview, iPhone 17 Pro simulator | Evaluates row card surface and status semantics. |
| SCR-04 | `docs/screenshots/review-visual-system-unification-r1/planning-04-goalrow-critical-iphone17pro-light.png` | Goal row | Critical/at-risk | Xcode Preview, iPhone 17 Pro simulator | Evaluates urgency treatment and contrast emphasis. |
| SCR-05 | `docs/screenshots/Simulator Screenshot - iPhone 16 Pro Max - 2025-08-26 at 20.35.14.png` | Dashboard/goal detail baseline | Historical baseline | iPhone 16 Pro Max simulator (archived) | Supplemental dashboard evidence while current dashboard preview runtime was unstable. |

### D. Assumptions and Open Questions
- ASSUMP-01: Review scope is limited to proposal + currently accessible code/screens, without additional PRD/research docs.
- ASSUMP-02: Dashboard/Settings preview evidence is partial due concurrent build/simulator contention and preview runtime crashes during review.
- ASSUMP-03: No runtime profiling data was provided; performance findings are risk-based, not benchmark-confirmed.
- QUESTION-01: Who is accountable for approving token exceptions across iOS and Android?
- QUESTION-02: What CI policy blocks release when visual/accessibility regressions are detected?
