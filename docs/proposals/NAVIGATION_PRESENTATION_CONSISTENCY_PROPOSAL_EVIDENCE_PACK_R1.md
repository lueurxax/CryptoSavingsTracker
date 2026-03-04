# Evidence Pack

## A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 3) iOS Policy | Proposal mandates `NavigationStack`, `confirmationDialog`, `.sheet`/`.fullScreenCover` split. | No concrete decision table per flow is provided. |
| DOC-02 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 5) Enforcement | Enforcement is phrased as “no new `NavigationView` / `ActionSheet` usage.” | Does not define migration target or grandfathering strategy for existing code. |
| DOC-03 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 6) Rollout | Rollout has 3 generic steps (replace, normalize, add tests). | No owners, order, or rollback controls are specified. |
| DOC-04 | `ios/CryptoSavingsTracker/Views` (code scan via `rg`) | Baseline inventory | Current baseline: `NavigationView` = 26 hits, `.actionSheet`/`ActionSheet` = 2 hits, `.confirmationDialog` = 4 hits, `.sheet` = 38 hits, `.fullScreenCover` = 2 hits. | Proposal scope is materially larger than indicated; migration blast radius is high. |
| DOC-05 | `ios/CryptoSavingsTracker/Views/DashboardView.swift:119` | iOS presentation | Active iOS screen still uses legacy `.actionSheet` + `ActionSheet`. | Policy and implementation are currently divergent in production code. |
| DOC-06 | `ios/CryptoSavingsTracker/Views/AddGoalView.swift:383` and `ios/CryptoSavingsTracker/Views/AddAssetView.swift:581` | Modal policy edge case | `fullScreenCover` is gated by `isUITestFlow`, with `.sheet` in non-UI-test flow for the same picker. | Modal style changes by runtime/testing mode, which violates consistency intent. |
| DOC-07 | `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/AppNavHost.kt` | Android baseline | Android already uses single `NavHost` + centralized routes. | Android side may be closer to target than iOS; parity work should focus on modal matrix/test coverage. |
| DOC-08 | `ios/CryptoSavingsTracker/Views/ContentView.swift:43` and `ios/CryptoSavingsTracker/Navigation/Coordinator.swift` | iOS architecture | App has both root `NavigationStack` usage and a coordinator path abstraction. | Proposal does not define whether coordinator strategy is canonical or optional. |

## B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://developer.apple.com/videos/play/wwdc2022/10054/ | 2022-06-08 | Apple positions `NavigationStack` as the modern SwiftUI navigation model replacing older patterns. | Supports policy decision to standardize on `NavigationStack`. |
| WEB-02 | https://developer.apple.com/videos/play/wwdc2021/10256/ | 2021-06-10 | Apple guidance emphasizes presenting controls contextually and minimizing unnecessary focus-stealing UI. | Useful for dialog/sheet trigger discipline. |
| WEB-03 | https://developer.apple.com/design/tips/ | Retrieved 2026-03-02 | Apple design tips reiterate platform expectations like minimum tappable targets and clear icon/action semantics. | Supports interaction/accessibility acceptance criteria for nav controls and modal actions. |
| WEB-04 | https://developer.android.com/develop/ui/compose/navigation | 2026-02-10 (last updated) | Jetpack Compose guidance centers app navigation around a single NavHost/navController graph. | Confirms Android policy direction and existing implementation baseline. |
| WEB-05 | https://developer.android.com/develop/ui/compose/designsystems/material3 | 2026-02-10 (last updated) | Material 3 expects consistent use of canonical components and theming semantics. | Supports parity requirement for dialog/sheet behavior on Android. |
| WEB-06 | https://www.consumerfinance.gov/about-us/newsroom/cfpb-finalizes-rule-to-remove-medical-bills-from-credit-reports/ | 2024-12-12 | CFPB framing emphasizes reducing consumer harm from opaque financial signals. | Trust framing for finance UX: presentation consistency reduces ambiguity and perceived manipulation. |
| WEB-07 | https://www.consumerfinance.gov/about-us/newsroom/cfpb-issue-spotlight-highlights-financial-consequences-of-illness-and-injury/ | 2023-03-28 | CFPB highlights that unclear or compounding financial interactions can materially harm consumers. | Reinforces need for predictable, transparent flow behavior in budgeting/planning actions. |

## C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-navigation-presentation-r1/large/monthly-budget-sheet-01-shortfall-iphone17promax-light.png` | Monthly Planning -> Budget sheet open | Budget shortfall + keyboard-up edit state | iPhone 17 Pro Max / iOS 26.2 | Shows current modal header/action density and on-screen keyboard interaction constraints. |
| SCR-02 | `docs/screenshots/review-navigation-presentation-r1/large/monthly-planning-02-after-cancel-shortfall-card-iphone17promax-light.png` | Budget sheet -> Cancel | Return to planning with at-risk card | iPhone 17 Pro Max / iOS 26.2 | Captures post-dismiss state continuity expectations in the primary planning flow. |
| SCR-03 | `docs/screenshots/review-navigation-presentation-r1/compact/monthly-budget-sheet-01-shortfall-iphone16e-light.png` | Monthly Planning -> Budget sheet open | Compact device budget edit state | iPhone 16e / iOS 26.2 | Confirms compact-size layout pressure and navigation/action truncation risk. |
| SCR-04 | `docs/screenshots/review-navigation-presentation-r1/compact/monthly-planning-02-after-cancel-shortfall-card-iphone16e-light.png` | Budget sheet -> Cancel | Compact return state | iPhone 16e / iOS 26.2 | Verifies compact flow continuity and readability after modal dismissal. |

## D. Assumptions and Open Questions
- ASSUMP-01: Scope is limited to the proposal and current repository state; no separate PRD or rollout constraints document was linked.
- ASSUMP-02: `NavigationView` references inside previews/tests should be excluded from hard-fail lint only if explicitly allowlisted.
- ASSUMP-03: This review treats iOS as primary migration risk because Android already has a centralized `NavHost` baseline.
- QUESTION-01: Should iPad regular-width flows use a separate policy (`NavigationSplitView` / popover detents) or reuse the iPhone matrix verbatim?
- QUESTION-02: Should unsaved changes on budget/planning sheets require a mandatory discard confirmation in v1?
- QUESTION-03: Who owns the cross-platform modal parity contract (product design vs mobile platform)?
