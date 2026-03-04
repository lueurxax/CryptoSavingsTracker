# Evidence Pack

## A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | Metadata + 1-2 | Proposal now includes explicit owners, baseline snapshot date, and measurable target outcomes. | Proposal remains in Draft status and requires implementation artifacts to become release-governing. |
| DOC-02 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 3) iOS Architecture Policy | Active iOS source must use `NavigationStack`; `NavigationView`/`ActionSheet` forbidden in active paths; route ownership model is defined. | Mixed ownership exceptions still depend on ADR process not yet linked. |
| DOC-03 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 4) iOS Presentation Contract | Decision matrix `MOD-01...MOD-05` defines API choice and behavior by use case. | Matrix is policy-level; per-flow mapping artifact is not yet attached. |
| DOC-04 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 5) Dismissal and Unsaved-Change Policy | Dirty financial forms must block silent dismiss and show `Keep Editing` / `Discard`. | “Dirty” detection criteria per form are not yet specified. |
| DOC-05 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 7) Enforcement and CI | CI jobs and forbidden API scope are named; allowlist policy is documented. | Allowlist is path-based and may need syntax-aware handling for mixed production+preview files. |
| DOC-06 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 9) Migration Governance and Rollout | Rollout waves, migration ledger fields, burn-down targets, and kill-switch intent are included. | Kill-switch implementation mechanism is not specified (build flag/runtime config owner unknown). |
| DOC-07 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 10-11 | Test expectations and product guardrails are explicitly listed; acceptance criteria is now measurable. | Event schema/owner for metrics ingestion is not yet named. |
| DOC-08 | `ios/CryptoSavingsTracker/Views` (code scan via `rg`) | Baseline validation | Current baseline still matches proposal snapshot: `NavigationView=26`, `ActionSheet=2`, `confirmationDialog=4`, `.sheet=38`, `.fullScreenCover=2`. | Baseline includes preview/test references unless filtered by active-source criteria. |
| DOC-09 | `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/AppNavHost.kt` | Android baseline | Android already uses a single `NavHost` + centralized routes, consistent with policy direction. | Parity hardening remains mostly journey-contract/testing work, not structural nav rewrite. |

## B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://developer.apple.com/videos/play/wwdc2022/10054/ | 2022-06-08 | Apple introduced `NavigationStack` as modern SwiftUI navigation model. | Supports iOS policy to standardize on `NavigationStack`. |
| WEB-02 | https://developer.apple.com/videos/play/wwdc2021/10256/ | 2021-06-10 | Apple guidance emphasizes contextual actions and preserving user focus. | Supports modal/dialog discipline and dismiss behavior requirements. |
| WEB-03 | https://developer.apple.com/design/tips/ | Retrieved 2026-03-03 | Apple design tips reinforce clear hierarchy, touch target quality, and action clarity. | Supports accessibility and action hierarchy constraints in contract. |
| WEB-04 | https://developer.android.com/develop/ui/compose/navigation | 2026-02-10 (last updated) | Compose guidance recommends centralized navigation through one NavHost/controller. | Supports Android parity baseline and policy alignment. |
| WEB-05 | https://developer.android.com/develop/ui/compose/designsystems/material3 | 2026-02-10 (last updated) | Material 3 favors consistent semantic component behavior. | Supports cross-platform parity contract expectations. |
| WEB-06 | https://www.consumerfinance.gov/about-us/newsroom/cfpb-finalizes-rule-to-remove-medical-bills-from-credit-reports/ | 2024-12-12 | CFPB emphasizes reducing consumer harm from opaque financial interactions. | Supports trust/transparency lens for deterministic dismiss/save behavior. |
| WEB-07 | https://www.consumerfinance.gov/about-us/newsroom/cfpb-issue-spotlight-highlights-financial-consequences-of-illness-and-injury/ | 2023-03-28 | CFPB highlights compounding harms when financial flows are confusing. | Reinforces importance of predictable cancellation/recovery semantics. |

## C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-navigation-presentation-r1/large/monthly-budget-sheet-01-shortfall-iphone17promax-light.png` | Monthly Planning -> Budget sheet open | Budget shortfall + keyboard-up edit state | iPhone 17 Pro Max / iOS 26.2 | Validates keyboard-heavy modal constraints and toolbar/action density. |
| SCR-02 | `docs/screenshots/review-navigation-presentation-r1/large/monthly-planning-02-after-cancel-shortfall-card-iphone17promax-light.png` | Budget sheet -> Cancel | Return to planning with unresolved risk | iPhone 17 Pro Max / iOS 26.2 | Validates orientation continuity after dismiss. |
| SCR-03 | `docs/screenshots/review-navigation-presentation-r1/compact/monthly-budget-sheet-01-shortfall-iphone16e-light.png` | Monthly Planning -> Budget sheet open | Compact keyboard-heavy edit state | iPhone 16e / iOS 26.2 | Captures compact-space pressure and truncation/affordance risk. |
| SCR-04 | `docs/screenshots/review-navigation-presentation-r1/compact/monthly-planning-02-after-cancel-shortfall-card-iphone16e-light.png` | Budget sheet -> Cancel | Compact return continuity | iPhone 16e / iOS 26.2 | Confirms continuity and scanability after modal dismissal on compact device. |

## D. Assumptions and Open Questions
- ASSUMP-01: Review scope is proposal + validated code baseline + existing screenshot evidence set.
- ASSUMP-02: iPad policy remains explicitly out of scope for this revision and is treated as follow-up work.
- ASSUMP-03: “Active source” excludes previews/tests by policy, but CI filtering strategy is not yet implemented.
- QUESTION-01: What is the canonical technical mechanism for kill switches (`RemoteConfig`, build-time flags, or local feature registry)?
- QUESTION-02: Which team owns decision-ID mapping compliance per feature PR (design review vs engineering review)?
- QUESTION-03: What exact analytics event schema will back Section 10 guardrails and release-gate dashboards?
