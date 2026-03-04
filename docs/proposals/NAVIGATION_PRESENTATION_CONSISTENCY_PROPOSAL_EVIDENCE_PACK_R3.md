# Evidence Pack

## A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | Metadata, 1-2 | Proposal now has explicit owners, baseline snapshot date, scope boundaries, and measurable outcomes. | Status remains `Draft`; implementation artifacts are still required before release governance. |
| DOC-02 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 3) iOS Architecture Policy | `NavigationStack` only in active iOS views; `NavigationView`/`ActionSheet` forbidden in active paths; route ownership model is defined. | Exception path depends on future ADR process not yet linked. |
| DOC-03 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 4) iOS Presentation Contract | Decision IDs `MOD-01...MOD-05` define API + behavior by intent/risk category. | Decision-ID mapping is not yet machine-auditable in CI. |
| DOC-04 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 5) Dismissal and Unsaved-Change Policy | Dirty forms must block dismiss and show `Keep Editing` / `Discard`; no silent data loss allowed. | Dirty-state detection rules are not formalized per flow/form. |
| DOC-05 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 7) Enforcement and CI | CI jobs are named and include forbidden API policy + allowlist patterns. | Allowlist is path-pattern based (`*Preview*`, `*Tests*`) and may be insufficient for mixed files. |
| DOC-06 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 9) Migration Governance and Rollout | Wave plan, migration ledger schema, burn-down targets, and kill-switch intent are defined. | Kill-switch mechanism (runtime/config ownership) is not yet concretely specified. |
| DOC-07 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md` | 10-11 | Test matrix + product guardrails + measurable acceptance criteria are now included. | Telemetry event schema, ownership, and dashboard contract are not yet documented. |
| DOC-08 | Code scan (`rg`) in `ios/CryptoSavingsTracker/Views/**` | Baseline verification (2026-03-03) | Current baseline remains: `NavigationView=26`, `ActionSheet=2`, `confirmationDialog=4`, `.sheet=38`, `.fullScreenCover=2`. | Inventory still includes references that may later be excluded by active-source filtering policy. |
| DOC-09 | `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/navigation/AppNavHost.kt` | Android baseline | Android remains aligned with single `NavHost` architecture. | Android work is primarily parity hardening + validation, not structural nav rewrite. |
| DOC-10 | `docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL_TRIAD_REVIEW_R2.md` | 7) Definition of Green | R2 established explicit blockers to Green: CI fidelity, telemetry readiness, parity scripts, rollback runbook. | R3 evaluates whether blockers were fully closed in proposal artifacts. |

## B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://developer.apple.com/videos/play/wwdc2022/10054/ | 2022-06-08 | Apple introduced `NavigationStack` as the modern navigation model for SwiftUI apps. | Supports iOS migration away from `NavigationView`. |
| WEB-02 | https://developer.apple.com/design/human-interface-guidelines | Retrieved 2026-03-03 | HIG emphasizes platform-consistent navigation, clarity, and predictable presentation behavior. | Supports standardization and platform fidelity criteria. |
| WEB-03 | https://developer.apple.com/design/human-interface-guidelines/going-full-screen | 2025-06-09 (change log) | HIG full-screen guidance frames when immersive presentation is appropriate vs standard overlays. | Supports `sheet` vs `fullScreenCover` decision contract. |
| WEB-04 | https://developer.android.com/develop/ui/compose/navigation | 2026-02-10 (last updated) | Compose guidance centers app navigation around a single `NavHost`/controller graph. | Supports Android policy alignment and parity framing. |
| WEB-05 | https://developer.android.com/jetpack/androidx/releases/navigation3 | 2026-02-11 (latest updates listed) | Navigation3 updates highlight active evolution of Compose navigation contracts and testability. | Supports keeping Android parity contract explicit and version-aware. |
| WEB-06 | https://developer.android.com/develop/ui/compose/designsystems/material3 | 2026-02-10 (last updated) | Material 3 expects consistent semantic component behavior across flows/states. | Supports modal/dialog parity semantics across platforms. |
| WEB-07 | https://www.consumerfinance.gov/about-us/newsroom/cfpb-highlights-harms-of-medical-and-banking-credit-products-in-new-supervisory-report/ | 2025-01-07 | CFPB messaging emphasizes consumer harm when financial experiences are opaque or inconsistent. | Supports trust-oriented UX requirement for deterministic save/cancel behavior. |
| WEB-08 | https://www.consumerfinance.gov/about-us/newsroom/cfpb-issue-spotlight-highlights-financial-consequences-of-illness-and-injury/ | 2023-05-30 | CFPB issue spotlight ties unclear financial processes to user harm and confusion. | Reinforces requirement for transparent recovery and confirmation flows. |

## C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/screenshots/review-navigation-presentation-r3/large/monthly-budget-sheet-01-shortfall-iphone17promax-light-2026-03-03.png` | Monthly Planning -> Budget sheet open | Keyboard-heavy budget shortfall state | iPhone 17 Pro Max / iOS 26.2 | Validates `MOD-02` density and action hierarchy in current implementation. |
| SCR-02 | `docs/screenshots/review-navigation-presentation-r3/large/monthly-planning-02-after-cancel-shortfall-card-iphone17promax-light-2026-03-03.png` | Budget sheet -> Cancel | Return state with unresolved risk card | iPhone 17 Pro Max / iOS 26.2 | Verifies dismiss/return continuity requirements in proposal. |
| SCR-03 | `docs/screenshots/review-navigation-presentation-r3/compact/monthly-budget-sheet-01-shortfall-iphone16e-light-reuse.png` | Monthly Planning -> Budget sheet open | Compact keyboard-heavy state | iPhone 16e / iOS 26.2 | Confirms compact constraints and toolbar truncation pressure. |
| SCR-04 | `docs/screenshots/review-navigation-presentation-r3/compact/monthly-planning-02-after-cancel-shortfall-card-iphone16e-light-reuse.png` | Budget sheet -> Cancel | Compact return continuity | iPhone 16e / iOS 26.2 | Confirms post-dismiss readability on compact size class. |

## D. Assumptions and Open Questions
- ASSUMP-01: R3 evaluates proposal maturity and governance readiness, not code implementation progress.
- ASSUMP-02: Compact screenshots were reused from the prior validated capture set due repeated compact-run xcresult corruption in this pass; large-device screenshots were freshly captured on 2026-03-03.
- ASSUMP-03: iPad regular-width policy remains intentionally out of scope and is treated as scheduled follow-up.
- QUESTION-01: Will CI parse source AST/SwiftSyntax to ignore `#Preview` blocks, or enforce preview-only file segregation?
- QUESTION-02: Which owner is accountable for kill-switch infrastructure and rollback drill execution per wave?
- QUESTION-03: What exact telemetry event contract will operationalize Section 10 guardrails and release gates?
