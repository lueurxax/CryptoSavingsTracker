# Evidence Pack

## A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 0-2 | Proposal now explicitly states R2 revision and keeps clear decision-first IA/module ordering. | Scope remains proposal quality, not implementation completion. |
| DOC-02 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 3.2-3.6 | `GoalDashboardSceneModel` + recompute triggers + slice schema appendix are now present. | Shared JSON schema files are referenced but currently not yet present in repo. |
| DOC-03 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 4.1-4.4 | Resolver matrix is deterministic and includes diagnostics payload contract for `hard_error`. | CTA correctness depends on exact state parity across resolver/acceptance/tests. |
| DOC-04 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 5-7 | Forecast explainability, token/chip/motion contracts, and UI enforcement map are explicitly defined. | CI gate IDs are defined at proposal level; implementation mapping remains future work. |
| DOC-05 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 8.3 | Rollback thresholds now include numeric deltas + windows. | Operational source mirrored to runbook path that does not yet exist. |
| DOC-06 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 9.1, 12.4, 13 | Parity governance/versioning policy and CI checks are explicitly defined. | Referenced parity artifact and schema files are currently absent in repo. |
| DOC-07 | `ios/CryptoSavingsTracker/Views/DashboardViewPreview.swift` + `ios/CryptoSavingsTracker/Views/Components/DetailContainerView.swift` | 248-257; 20-35 | Current code still reflects legacy coupling that proposal intends to remove. | Confirms proposal still addresses an active architectural debt. |
| DOC-08 | Repository check (`test -f`) | runbooks + shared fixtures | `docs/runbooks/goal-dashboard-release-gate.md` missing; parity/schema artifacts missing. | Proposal is ahead of implementation; bootstrap plan should be explicit. |
| DOC-09 | Xcode preview execution + diagnostic crash logs | 2026-03-04 | Goal-related previews have recent crash evidence in this workspace session. | Indicates implementation risk that proposal does not yet explicitly mitigate. |

## B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ | 2025-06-09 | Apple emphasizes clarity/familiarity while introducing richer visual system. | Supports proposal focus on hierarchy and anti-noise dashboard structure. |
| WEB-02 | https://www.w3.org/TR/WCAG22/ | 2024-12-12 | WCAG 2.2 defines non-color and contrast requirements for status communication. | Supports chip accessibility and recovery-state clarity contracts. |
| WEB-03 | https://developer.android.com/develop/ui/compose/designsystems/material3 | Last updated 2026-02-26 UTC | Material3 promotes tokenized, system-driven UI consistency. | Supports shared parity artifact + token contract for iOS/Android alignment. |

## C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-visual-system-unification-r4/production/ios/dashboard/default.png` | Production dashboard route | default | iOS Simulator iPhone 16e (capture refreshed 2026-03-04) | Confirms current dashboard production baseline and CTA prominence in empty state. |
| SCR-02 | `docs/screenshots/review-visual-system-unification-r4/production/ios/dashboard/error.png` | Production dashboard route | error | iOS Simulator iPhone 16e (capture refreshed 2026-03-04) | Confirms explicit error-state route capture exists for dashboard flow. |
| SCR-03 | `docs/screenshots/review-visual-system-unification-r4/production/ios/dashboard/recovery.png` | Production dashboard route | recovery | iOS Simulator iPhone 16e (capture refreshed 2026-03-04) | Confirms recovery state capture and continuity with dashboard route. |
| SCR-04 | `docs/screenshots/review-goal-dashboard-redesign-r1/dashboard-preview-main-iphone-light.png` | Goal dashboard preview | empty/default | Xcode Preview | Shows current visual hierarchy for goal dashboard shell in preview path. |

## D. Assumptions and Open Questions
- ASSUMP-01: Proposal review evaluates contract readiness; implementation artifacts can be pending but must have clear bootstrap path.
- ASSUMP-02: Production capture harness screens are representative for dashboard route state evaluation in this review.
- QUESTION-01: What canonical wire format is required for `Decimal`/`Date` fields in shared JSON schemas?
- QUESTION-02: Which phase owns creation of missing runbook and parity/schema artifacts referenced as normative in the proposal?
