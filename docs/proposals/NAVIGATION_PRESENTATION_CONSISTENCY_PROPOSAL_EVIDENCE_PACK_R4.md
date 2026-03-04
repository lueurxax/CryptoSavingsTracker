# Evidence Pack

## A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 2.2, 3-4 | Proposal now includes best-practice basis, architecture policy, and executable `MOD-01...MOD-05` matrix. | Review focuses on proposal quality, not code migration completion. |
| DOC-02 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 5 | Dirty-state contract and dismiss confirmation behavior are explicitly defined. | Form-level implementation details are still downstream work. |
| DOC-03 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 6 | Top-5 parity journeys now include executable script template + scenario table. | Cross-platform parity still depends on QA artifact discipline. |
| DOC-04 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 7 | CI policy includes syntax-aware checks, fallback preview split, and machine-checkable `NAV-MOD` annotation. | Parser/tooling specifics are still implementation-owned and not attached. |
| DOC-05 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 9 | Kill-switch mechanism, owner model, and override priority are documented. | Needs operational runbook evidence during rollout. |
| DOC-06 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 10-11, 13 | Alert thresholds, analytics event contract, and Green exit criteria are explicit. | Dashboard implementation and release governance execution remain to be proven in practice. |
| DOC-07 | Code scan (`rg`) on 2026-03-03 | baseline | Current inventory still: `NavigationView=26`, `ActionSheet=2`, `confirmationDialog=4`, `.sheet=38`, `.fullScreenCover=2`. | Baseline proves migration necessity; not a proposal defect. |

## B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://developer.apple.com/videos/play/wwdc2022/10054/ | 2022-06-08 | `NavigationStack` is Apple’s modern navigation direction for SwiftUI. | Validates migration target away from `NavigationView`. |
| WEB-02 | https://developer.apple.com/design/human-interface-guidelines | Retrieved 2026-03-03 | HIG stresses predictable navigation/presentation patterns and clarity. | Supports proposal consistency goals. |
| WEB-03 | https://developer.apple.com/design/human-interface-guidelines/going-full-screen | 2025-06-09 (change log) | Full-screen guidance clarifies when immersive containers are appropriate. | Supports `sheet` vs `fullScreenCover` decisions. |
| WEB-04 | https://developer.android.com/develop/ui/compose/navigation | 2026-02-10 (last updated) | Compose guidance centers around a single navigation host/controller model. | Supports Android parity baseline. |
| WEB-05 | https://developer.android.com/jetpack/androidx/releases/navigation3 | 2026-02-11 | Navigation3 is actively evolving for Compose-first apps. | Supports explicit, version-aware parity contract. |
| WEB-06 | https://developer.android.com/develop/ui/compose/designsystems/material3 | 2026-02-10 (last updated) | Material 3 emphasizes consistent semantic behavior across states and flows. | Supports cross-platform modal/dialog semantic consistency. |
| WEB-07 | https://www.consumerfinance.gov/about-us/newsroom/cfpb-highlights-harms-of-medical-and-banking-credit-products-in-new-supervisory-report/ | 2025-01-07 | CFPB highlights consumer harm from opaque or inconsistent financial interactions. | Reinforces trust-critical cancel/recovery policy requirements. |

## C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-navigation-presentation-r3/large/monthly-budget-sheet-01-shortfall-iphone17promax-light-2026-03-03.png` | Planning -> Budget sheet | Keyboard-heavy shortfall edit | iPhone 17 Pro Max / iOS 26.2 | Verifies compact/keyboard presentation pressure in real UI. |
| SCR-02 | `docs/screenshots/review-navigation-presentation-r3/large/monthly-planning-02-after-cancel-shortfall-card-iphone17promax-light-2026-03-03.png` | Budget sheet -> Cancel | Return with unresolved risk | iPhone 17 Pro Max / iOS 26.2 | Verifies orientation continuity requirement. |
| SCR-03 | `docs/screenshots/review-navigation-presentation-r3/compact/monthly-budget-sheet-01-shortfall-iphone16e-light-reuse.png` | Planning -> Budget sheet | Compact shortfall edit | iPhone 16e / iOS 26.2 | Confirms compact constraints remain relevant. |
| SCR-04 | `docs/screenshots/review-navigation-presentation-r3/compact/monthly-planning-02-after-cancel-shortfall-card-iphone16e-light-reuse.png` | Budget sheet -> Cancel | Compact return continuity | iPhone 16e / iOS 26.2 | Confirms post-dismiss continuity in compact layout. |

## D. Assumptions and Open Questions
- ASSUMP-01: Proposal text is the primary artifact under review; implementation validation is future work.
- ASSUMP-02: Compact screenshots are reused from a previously validated capture set because current compact runs intermittently generate corrupted xcresult bundles in this environment.
- QUESTION-01: Will syntax-aware linting be implemented with SwiftSyntax or an equivalent parser?
- QUESTION-02: Which owner signs final release gate once guardrail metrics and rollback drills are complete?
