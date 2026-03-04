# Evidence Pack

## A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 0, 2 | Proposal is revised after R1 and now defines canonical module IDs/order across size classes. | Review targets proposal readiness, not implementation completion. |
| DOC-02 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 3 | `GoalDashboardSceneModel` contract is now explicit with freshness and lifecycle fields plus recompute triggers. | Slice subtypes are referenced but not fully specified in this proposal. |
| DOC-03 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 4 | Deterministic `Next Action` resolver matrix and priority ordering are now defined. | Acceptance criteria coverage must match resolver state list exactly. |
| DOC-04 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 5-7 | Forecast trust copy, token map, motion policy, and state recovery table are now explicit. | Compliance depends on enforcement in CI/snapshot/a11y checks. |
| DOC-05 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 8 | Migration/rollback contract added (feature flag, widget compatibility handling, rollback conditions). | Baseline thresholds for rollback metrics are not numerically pinned in this document. |
| DOC-06 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 9-12 | Shared parity artifact path and release drift gate are defined, with unit/integration/UI/UX validation plans. | Governance owner and change-control process for parity artifact are implicit. |
| DOC-07 | `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` | 11, 13 | Open questions from R1 are explicitly marked resolved with concrete decisions. | Resolutions require implementation verification to become operational truth. |
| DOC-08 | `ios/CryptoSavingsTracker/Views/DashboardViewPreview.swift` + `ios/CryptoSavingsTracker/Views/Components/DetailContainerView.swift` | 248-257; 20-35 | Current code still has preview-coupled production type and old route dependency. | Proposal scope includes refactor to remove this coupling. |
| DOC-09 | Xcode preview execution + crash logs | 2026-03-04 00:10-00:11 | Rendering `DetailContainerViewPreview`/`GoalDetailViewPreview` fails with `PotentialCrashError`; crash report shows assertion path in preview runtime. | Preview reliability remains an immediate implementation risk even with stronger proposal text. |

## B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ | 2025-06-09 | Apple emphasizes visual vitality with content focus and cross-platform harmony. | Supports proposal's decision-first hierarchy and anti-noise direction. |
| WEB-02 | https://www.w3.org/TR/WCAG22/ | W3C Recommendation 2024-12-12 | WCAG 2.2 remains normative baseline for contrast and non-color semantics. | Supports status-chip accessibility and state communication requirements. |
| WEB-03 | https://developer.android.com/develop/ui/compose/designsystems/material3 | Last updated 2026-02-26 UTC | Material3 guidance is token/system driven for consistent component behavior. | Supports parity artifact and tokenized visual contract across platforms. |

## C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-goal-dashboard-redesign-r1/dashboard-preview-main-iphone-light.png` | Dashboard preview entry | empty/default | Xcode Preview iPhone profile | Baseline visual hierarchy and empty-state CTA emphasis. |
| SCR-02 | `docs/screenshots/review-visual-system-unification-r4/ios/dashboard.summary_card/default.png` | Dashboard summary component | default | iOS simulator iPhone 16e | Demonstrates canonical component baseline for ready/default state. |
| SCR-03 | `docs/screenshots/review-visual-system-unification-r4/ios/dashboard.summary_card/error.png` | Dashboard summary component | error | iOS simulator iPhone 16e | Demonstrates error status treatment. |
| SCR-04 | `docs/screenshots/review-visual-system-unification-r4/ios/dashboard.summary_card/stale.png` | Dashboard summary component | stale | iOS simulator iPhone 16e | Demonstrates stale-data messaging state. |
| SCR-05 | `docs/screenshots/review-visual-system-unification-r4/production/ios/dashboard/default.png` | Production flow dashboard | default | iOS simulator iPhone 16e | Production-flow capture traceability for dashboard route. |
| SCR-06 | `docs/screenshots/review-visual-system-unification-r4/production/ios/dashboard/recovery.png` | Production flow dashboard | recovery | iOS simulator iPhone 16e | Production-flow recovery state evidence. |

## D. Assumptions and Open Questions
- ASSUMP-01: Review compares R2 proposal quality against R1 findings and current source structure.
- ASSUMP-02: Existing captures are sufficient to evaluate empty/error/stale/recovery behavior at proposal stage.
- QUESTION-01: Who owns schema governance/version bumps for `goal_dashboard_parity.v1.json`?
- QUESTION-02: Should rollback condition "crash-free rate below baseline" be tied to explicit numeric threshold in proposal or release runbook?
