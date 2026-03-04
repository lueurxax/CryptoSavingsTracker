# Evidence Pack

## A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 0 | Proposal correctly audits current fragmentation: two dashboard paths, preview-file production type, compact-only iOS behavior. | Audit is treated as accurate baseline unless contradicted by source. |
| DOC-02 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 2-3 | IA order and interaction contract are explicit and decision-first (`Snapshot -> Next Action -> Forecast -> Activity -> Allocation -> Utilities`). | IA applies to iPhone and iPad; only layout adapts. |
| DOC-03 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 3.3, 3.4 | CTA policy sets one primary action with 4 resolver states; state taxonomy requires `loading/ready/empty/error/stale`. | Resolver currently omits data-freshness/error-source dimensions. |
| DOC-04 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 5 | Refactor target is single scene model and one dashboard VM source. | Scene-model contract is named but not formally specified. |
| DOC-05 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 7-8 | Acceptance and tests exist (single CTA, snapshot states, dynamic type, parity requirement). | Measurement protocol for "<=3s comprehension" is not defined. |
| DOC-06 | `ios/CryptoSavingsTracker/Views/DashboardViewPreview.swift` | 248-257 | `DashboardViewForGoal` production type currently lives in preview-oriented file. | Confirms ownership/discoverability issue from proposal audit. |
| DOC-07 | `ios/CryptoSavingsTracker/Views/Components/DetailContainerView.swift` | 20-35 | Goal details tab directly depends on `DashboardViewForGoal`. | Refactor requires safe replacement at this call-site. |
| DOC-08 | `ios/CryptoSavingsTracker/Views/Dashboard/DashboardComponents.swift` | 21-27, 139-175 | iOS is forced into compact mode; expanded layout contains quick actions/insights/activity with repeated card shadows. | Proposal visual cleanup is aligned with observed debt. |
| DOC-09 | `ios/CryptoSavingsTracker/Views/DashboardViewPreview.swift` + `ios/CryptoSavingsTracker/Views/DashboardView.swift` | 264-289; 67-69; 169-170 | Multiple dashboard sections instantiate independent `DashboardViewModel` instances. | Confirms duplicate load timing risk and state inconsistency risk. |
| DOC-10 | `ios/CryptoSavingsTracker/ViewModels/DashboardViewModel.swift` | 67-95, 97-160, 327-360 | Dashboard load pipeline does parallel work + forecast generation; no explicit performance budget/timeout contract in proposal. | Proposal needs operability constraints, not only IA/visual rules. |
| DOC-11 | Xcode preview execution (`RenderPreview`) + crash report | 2026-03-04 00:10-00:11 | `DetailContainerViewPreview`, `GoalDetailViewPreview`, and `DashboardComponentsPreview` failed with `PotentialCrashError`; crash log shows `swift_unexpectedError` / assertion failure in preview runtime. | Current goal dashboard surface has reliability fragility even before UI redesign. |

## B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ | 2025-06-09 | Apple frames the new visual system around clarity, familiarity, and meaningful hierarchy. | Supports proposal intent to reduce noisy dashboard hierarchy. |
| WEB-02 | https://developer.apple.com/design/tips/ | Accessed 2026-03-03 (footer © 2026 Apple Inc.) | Apple tips emphasize readability: align text left, keep touch targets large, avoid decorative transparency that hurts legibility. | Validates stricter visual rules for dense financial cards. |
| WEB-03 | https://www.w3.org/TR/WCAG22/ | 2024-12-12 | WCAG 2.2 remains normative for non-color-only status communication and readable contrast. | Supports explicit accessibility acceptance criteria for risk chips/state badges. |
| WEB-04 | https://www.nngroup.com/articles/progressive-disclosure/ | 2006-08-20 | Progressive disclosure reduces cognitive load by showing detail only when needed. | Supports module prioritization and secondary-utilities approach. |
| WEB-05 | https://www.nngroup.com/articles/ten-usability-heuristics/ | 1994 (updated 2024-06-02) | Core heuristics: visibility of system status, match with real world, user control and recovery. | Supports stronger state explanations and recovery actions. |
| WEB-06 | https://developer.android.com/develop/ui/compose/designsystems/material3 | Last updated 2026-02-26 UTC | Material3 guidance is token/system driven, emphasizing consistency across components and states. | Supports Android parity requirement via shared semantic contract, not ad-hoc screen copies. |

## C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-goal-dashboard-redesign-r1/dashboard-preview-main-iphone-light.png` | Dashboard preview entry | empty/default | Xcode SwiftUI Preview (iPhone profile) | Captures current dashboard visual hierarchy and CTA prominence in empty state. |
| SCR-02 | `docs/screenshots/review-visual-system-unification-r4/ios/dashboard.summary_card/default.png` | Dashboard summary component | default | iOS simulator (iPhone 16e, iOS 26.x toolchain) | Confirms current component baseline used in visual-state capture matrix. |
| SCR-03 | `docs/screenshots/review-visual-system-unification-r4/ios/dashboard.summary_card/error.png` | Dashboard summary component | error | iOS simulator (iPhone 16e, iOS 26.x toolchain) | Confirms error-state label treatment and emphasis behavior. |
| SCR-04 | `docs/screenshots/review-visual-system-unification-r4/ios/dashboard.summary_card/stale.png` | Dashboard summary component | stale | iOS simulator (iPhone 16e, iOS 26.x toolchain) | Confirms stale-data state exists but relies on text-only treatment in current component. |
| SCR-05 | `docs/screenshots/review-visual-system-unification-r4/production/ios/dashboard/default.png` | Production flow: dashboard | default | iOS simulator (iPhone 16e, iOS 26.x toolchain) | Confirms production capture currently centers empty dashboard onboarding pattern. |
| SCR-06 | `docs/screenshots/review-visual-system-unification-r4/production/ios/dashboard/recovery.png` | Production flow: dashboard | recovery | iOS simulator (iPhone 16e, iOS 26.x toolchain) | Confirms recovery screen parity with default empty dashboard path. |

## D. Assumptions and Open Questions
- ASSUMP-01: This review evaluates proposal readiness, not full implementation completeness.
- ASSUMP-02: Available deterministic captures are component/production-flow oriented; goal-specific live-data screens are assessed through source audit and preview/crash evidence.
- ASSUMP-03: Android parity is evaluated at contract level because this proposal is iOS-first by scope.
- QUESTION-01: What is the formal schema for `GoalDashboardSceneModel` (fields, freshness, and error provenance) shared across modules?
- QUESTION-02: What instrumentation method will validate the `<= 3 seconds` comprehension acceptance criterion?
- QUESTION-03: What is the migration strategy for existing `dashboard_widgets` persisted config when legacy dashboard path is removed?
