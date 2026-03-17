# Evidence Pack

## A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `/Users/user/Documents/CryptoSavingsTracker/docs/README.md` | iOS/macOS documentation index | `docs/VISUAL_SYSTEM_UNIFICATION.md` is the current visual-system source-of-truth in the repo index. | The requested file path `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` does not exist, so the review targets the current source-of-truth doc instead. |
| DOC-02 | `/Users/user/Documents/CryptoSavingsTracker/docs/VISUAL_SYSTEM_UNIFICATION.md` | Overview, state taxonomy, accessibility, performance budgets, rollout, release certification | Governs token-only visuals, priority flows (`planning`, `dashboard`, `settings`), 8 required component states, release-blocking accessibility checks, and performance budgets (`<=10%` P95 regression, `<=2pp` jank delta). | Proposal scope is finance-critical visual unification, not a full rebrand or chart-specific motion redesign. |
| DOC-03 | `/Users/user/Documents/CryptoSavingsTracker/docs/release/visual-system/wave1/release-certification-summary.md` | Whole document | Wave 1 certification is marked `PASS`, `releaseCertifiable=true`, and evidence quality passed with full test mode. | Release evidence reflects the current implementation baseline, not a future design target. |
| DOC-04 | `/Users/user/Documents/CryptoSavingsTracker/docs/release/visual-system/wave1/performance-report.json` | Performance report | Wave 1 performance is within budget but close to the ceiling: `8.04%` P95 regression vs `10%` max, `1.6pp` jank delta vs `2.0pp` max. | Headroom matters because the proposal relies on repeated visual and runtime validation across multiple flows. |
| DOC-05 | `/Users/user/Documents/CryptoSavingsTracker/docs/release/visual-system/wave1/state-coverage-report.md` | State coverage report | Report is `passed`, but `Required states` and `Release components` fields are empty. | Artifact generation quality is part of release operability, even when the pass/fail flag is green. |
| DOC-06 | `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/VisualComponentTokens.swift` | Token definitions | iOS already centralizes some surface, stroke, and status colors into a token enum. | The proposal must preserve this direction and avoid reintroducing ad hoc literals. |
| DOC-07 | `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/VisualSystemRollout.swift` | Flow flags and telemetry | Rollout is organized by `planning`, `dashboard`, and `settings`, with release-default/remote-config/debug override resolution and rollback telemetry hooks. | Any proposal change must fit the existing wave/flag model rather than invent a second rollout mechanism. |

## B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | https://developer.apple.com/documentation/technologyoverviews/liquid-glass | Last month (crawled) | Apple’s Liquid Glass overview says system components adopt the material automatically and advises adapting existing apps without a ground-up rewrite. | Supports the proposal’s emphasis on system-consistent materials, but also warns against over-customization. |
| WEB-02 | https://developer.apple.com/design/human-interface-guidelines/accessibility | Change log updated June 9, 2025 | Apple’s accessibility guidance emphasizes Dynamic Type, contrast, VoiceOver, and not relying on color alone. | Supports the proposal’s accessibility and status-communication requirements. |
| WEB-03 | https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria/ | Crawled 5 days ago | Apple’s VoiceOver criteria call for concise, consequence-aware labels and accessible complex behaviors. | Relevant to financial flows where labels and actions must be unambiguous. |
| WEB-04 | https://developer.apple.com/help/app-store-connect/manage-app-accessibility/larger-text-accessibility-evaluation-criteria/ | Crawled 4 months ago | Apple’s Larger Text criteria note that supporting at least 200% text enlargement is a common baseline and favor Dynamic Type. | Relevant to finance screens with dense copy and numerical values. |
| WEB-05 | https://www.w3.org/TR/WCAG22/ | Published 5 October 2023; update 12 December 2024 | WCAG 2.2 recommends 4.5:1 contrast for normal text, 3:1 for large text, and includes `Target Size (Minimum)` guidance. | Backs the proposal’s contrast and target-size requirements with current accessibility standards. |
| WEB-06 | https://www.w3.org/WAI/WCAG20/Understanding/contrast-minimum | Published 2023; crawled 5 days ago | WCAG contrast guidance explicitly states 4.5:1 for normal text and 3:1 for large text. | Useful for validating whether proposed surfaces and status colors can remain legible over materials. |

## C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `/Users/user/Documents/CryptoSavingsTracker/docs/screenshots/review-visual-system-unification-r4/ios/planning.header_card/default.png` | Planning header card baseline | default | iPhone simulator capture from R4 bundle | Confirms the current calm surface baseline for a release-blocking planning component. |
| SCR-02 | `/Users/user/Documents/CryptoSavingsTracker/docs/screenshots/review-visual-system-unification-r4/ios/planning.goal_row/error.png` | Planning goal row error state | error | iPhone simulator capture from R4 bundle | Confirms error semantics are explicit and not color-only. |
| SCR-03 | `/Users/user/Documents/CryptoSavingsTracker/docs/review-artifacts/proposal-review-triad/planning-preview.png` | Planning screen preview | default / mixed content | Xcode Preview, iOS canvas | Shows the live planning screen and its current visual density in the app shell. |
| SCR-04 | `/Users/user/Documents/CryptoSavingsTracker/docs/review-artifacts/proposal-review-triad/dashboard-preview.png` | Dashboard screen preview | default | Xcode Preview, iOS canvas | Shows the dashboard shell still labeled as legacy visual style. |
| SCR-05 | `/Users/user/Documents/CryptoSavingsTracker/docs/review-artifacts/proposal-review-triad/budget-preview.png` | Budget health card preview | default / no budget | Xcode Preview, iOS canvas | Shows the budget card and CTA treatment used for monthly planning. |
| SCR-06 | `/Users/user/Documents/CryptoSavingsTracker/docs/review-artifacts/proposal-review-triad/settings-preview.png` | Settings screen preview | default | Xcode Preview, iOS canvas | Shows the settings hierarchy and local bridge sync messaging. |

## D. Assumptions and Open Questions
- ASSUMP-01: The requested proposal file path is stale; `docs/VISUAL_SYSTEM_UNIFICATION.md` is the canonical source-of-truth used for review.
- ASSUMP-02: The evidence pack uses the repo’s checked-in simulator/emulator bundle plus live Xcode previews because both are deterministic and tied to the current codebase.
- QUESTION-01: Is the empty `Required states` / `Release components` output in `docs/release/visual-system/wave1/state-coverage-report.md` intentional, or is the report generator dropping fields?
- QUESTION-02: Should the dashboard and settings shells be considered in-scope for the visual-system unification proposal, or only the named release-blocking components?
- QUESTION-03: Is the 8.04% P95 regression close enough to the 10% ceiling that the proposal should require explicit performance headroom, not just pass/fail gating?
