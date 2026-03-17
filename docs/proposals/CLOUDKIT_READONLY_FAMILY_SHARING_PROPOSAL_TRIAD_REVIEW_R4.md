# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/CLOUDKIT_READONLY_FAMILY_SHARING_PROPOSAL.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/runbooks/cloudkit-cutover-release-gate.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/CLOUDKIT_MIGRATION_PLAN.md`
  - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift`
  - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift`
  - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/ContentView.swift`
  - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Views/GoalDetailView.swift`
  - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/PersistenceController.swift`
- Internet sources reviewed:
  - [CKShare.Participant](https://developer.apple.com/documentation/cloudkit/ckshare/participant) (Apple Developer Documentation, crawled 2026-03-17)
  - [UIApplicationDelegate application(_:userDidAcceptCloudKitShareWith:)](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:userdidacceptcloudkitsharewith:)) (Apple Developer Documentation, crawled 2026-03-17)
  - [UIWindowSceneDelegate windowScene(_:userDidAcceptCloudKitShareWith:)](https://developer.apple.com/documentation/uikit/uiwindowscenedelegate/windowscene(_:userdidacceptcloudkitsharewith:)) (Apple Developer Documentation, crawled 2026-03-17)
  - [Accepting share invitations in a SwiftUI app](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/accepting_share_invitations_in_a_swiftui_app) (Apple Developer Documentation, crawled 2026-03-17)
  - [UICloudSharingController](https://developer.apple.com/documentation/uikit/uicloudsharingcontroller) (Apple Developer Documentation, crawled 2026-03-17)
  - [WWDC21: Sharing Core Data objects between iCloud users](https://developer.apple.com/videos/play/wwdc2021/10015/) (WWDC21)
  - [Apple HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) (Apple HIG, crawled 2026-03-17)
  - [Apple App Store Connect Help: Reduced Motion evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria/) (Apple, crawled 2026-03-17)
  - [Apple HIG Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) (Apple HIG, 2024-02-02)
  - [CFPB final rule on personal financial data rights](https://www.consumerfinance.gov/rules-policy/final-rules/required-rulemaking-on-personal-financial-data-rights/) (CFPB, 2024-10-22)
  - [WWDC25 Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) (WWDC25, crawled 2026-03-17)
- Xcode screenshots captured:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/screenshots/review-cloudkit-family-sharing-r4/current-goals-root-no-shared-entry-preview-iphone-light.png`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/screenshots/review-cloudkit-family-sharing-r4/current-goal-detail-owner-surface-preview-iphone-light.png`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/screenshots/review-cloudkit-family-sharing-r4/current-settings-local-bridge-entry-preview-iphone-light.png`
- Remaining assumptions:
  - Full-goal-set sharing remains the intended v1 scope simplification.
  - The proposal text is normative for implementation, not illustrative.
  - Current-state previews are sufficient evidence because runtime feature code does not exist yet.

## 1. Executive Summary
- Overall readiness: Amber-Green
- Top 3 risks:
  1. The mandatory pre-share disclosure is still under-specified at the layout level and can degrade into a dense, trust-eroding sheet on small iPhones or large Dynamic Type (`DOC-06`, `DOC-07`, `WEB-07`, `WEB-11`).
  2. The per-`ownerID/shareID` cache model is directionally correct, but schema migration, rollback, and namespace lifecycle are still not explicit enough for implementation safety (`DOC-03`, `DOC-04`, `DOC-07`).
  3. The proposal says operations are serialized per namespace, but it still needs a concrete actor/executor contract for accept, refresh, revoke, and publish flows (`DOC-03`, `DOC-04`, `DOC-09`).
- Top 3 opportunities:
  1. The proposal is now close to a first-class Apple-native sharing surface: scene-based acceptance, system sharing UI, and clear owner/invitee IA are materially stronger than prior revisions (`DOC-01`, `DOC-02`, `DOC-03`).
  2. A tighter visual contract can make shared finance surfaces feel premium instead of ornamental by reserving glass for chrome and keeping numeric content on stable opaque surfaces (`DOC-06`, `WEB-11`).
  3. Explicit recovery-state and ownership cues can turn a potentially confusing shared-data flow into a low-support, high-trust family experience (`DOC-05`, `DOC-06`, `DOC-07`).

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 8.4 | 0 | 1 | 2 | 0 |
| UX (Financial) | 8.5 | 0 | 1 | 1 | 1 |
| iOS Architecture | 8.3 | 0 | 2 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Pre-share scope preview needs an explicit hierarchy, not only required content.
  - Evidence: `DOC-06`, `DOC-07`, `WEB-11`, `WEB-07`
  - Why it matters: The proposal makes first-invite acknowledgment mandatory, but it does not define the presentation hierarchy. Without a layout contract, the disclosure can collapse into a dense text sheet that hides the confirm action and weakens informed consent on small phones, large text sizes, and Reduce Motion.
  - Recommended fix: Specify a staged preview sheet with a top summary card, grouped disclosure sections, and a sticky primary confirm action. Keep the stack visually simple: one glass chrome layer, content on stable surfaces, no competing cards.
  - Acceptance criteria: The owner can understand the three core consent points in the first viewport or after one obvious expansion; the confirm action remains persistently discoverable; the preview stays readable in Reduced Motion, Increased Contrast, and large Dynamic Type.

- [Medium] Shared financial cards need a stricter glass-to-opaque boundary.
  - Evidence: `DOC-06`, `WEB-11`, `WEB-07`
  - Why it matters: The proposal now references semantic surfaces and contrast rules, but it still does not say where glass is allowed versus prohibited. If metric cards, freshness labels, or recovery banners use blur/translucency, the interface will look decorative instead of precise.
  - Recommended fix: Define a material hierarchy that reserves glass for chrome and headers, and requires opaque or near-opaque surfaces for all numeric cards, banners, and recovery states, with explicit reduced-transparency fallbacks.
  - Acceptance criteria: Key values, timestamps, and status labels remain legible without relying on background texture; the shared detail screen passes light, dark, increased-contrast, and reduced-transparency checks; no critical metric sits on a blurred surface.

- [Medium] Multi-owner browsing needs stronger ownership cues after section headers scroll away.
  - Evidence: `DOC-06`, `DOC-07`
  - Why it matters: The proposal requires owner grouping and row markers, but it does not define their behavior once headers collapse or the list scrolls. In long family lists, users can still lose track of ownership.
  - Recommended fix: Add explicit UI rules for sticky owner headers, inline ownership chips on every shared row, and a shared-row chrome token that cannot be mistaken for an owned goal.
  - Acceptance criteria: From any scroll position, the user can identify the owner of a shared goal without opening it; shared rows never visually match owned rows; ownership remains obvious at large text sizes.

### 3.2 UX Review Findings
- [High] First-invite disclosure is too dense for a mobile financial flow.
  - Evidence: `DOC-06`, `DOC-07`
  - Why it matters: The owner must acknowledge scope, future auto-sharing, exclusions, and revoke behavior before the first value moment. On a small screen, a long mandatory disclosure is easy to skim and hard to trust.
  - Recommended fix: Convert the preview into a compact summary sheet with expandable detail sections. Keep the acknowledgment requirement, but make the default view short, scannable, and CTA-first.
  - Acceptance criteria: The default preview fits within one iPhone viewport, keeps the primary action visible, and exposes current scope, future-goal auto-sharing, exclusions, and revoke behavior without forcing a long read.

- [Medium] Invitee end states need distinct recovery paths, not one terminal card.
  - Evidence: `QUESTION-01`, `DOC-05`, `DOC-07`
  - Why it matters: The state model names several lifecycle states, but it still does not force reason-specific recovery. In a finance app, ambiguous dead ends reduce trust and increase support burden.
  - Recommended fix: Split invitee recovery into explicit states for pending, empty/no-shared-data, revoked, and removed/unavailable, each with reason-specific copy, owner identity, and one primary next action.
  - Acceptance criteria: Invitees never land on a blank shared-goals shell; revoked, removed, and unavailable cases render different copy; every end state shows one clear next step such as `retry`, `accept`, `ask owner to re-share`, or `dismiss`.

- [Low] Alphabetical owner grouping is stable but not task-oriented.
  - Evidence: `DOC-02`, `DOC-06`, `DOC-07`
  - Why it matters: Alphabetical grouping is deterministic, but in multi-owner households it can bury the most relevant owner and make the user scan.
  - Recommended fix: Keep deterministic ordering as the fallback, but add a recency- or pin-based top slot, or a one-tap owner switcher in `Shared Goals`.
  - Acceptance criteria: The currently relevant owner group is reachable in one tap from the shared entry screen, and the active owner context is always obvious.

### 3.3 Architecture Review Findings
- [High] Add an explicit cache schema migration and rollback contract for the per-`ownerID/shareID` SwiftData stores.
  - Evidence: `DOC-03`, `DOC-04`, `DOC-07`
  - Why it matters: The cache boundary is now explicit, but the proposal still does not define how existing namespaces migrate, rebuild, or fail closed across app versions. Without that, an app update can strand invitee data or produce undefined recovery behavior.
  - Recommended fix: Define a versioned cache migration coordinator with forward migration, incompatible-schema rebuild, and downgrade fallback behavior per namespace. State whether migration is in-place or rebuild-based and who owns it.
  - Acceptance criteria: A v1 namespace opens on v2 without data loss; a v2 namespace on a v1 build either remains readable or fails closed into an explicit unavailable/stale state; tests cover upgrade, rollback, and corrupted-namespace rebuild paths.

- [High] Make the accept/refresh/revoke/publish concurrency model concrete instead of only “serial per namespace.”
  - Evidence: `DOC-03`, `DOC-04`, `DOC-09`
  - Why it matters: Scene acceptance, CloudKit refresh, owner-side mutation, revocation, bootstrap, and publish all touch the same shared state. Without an explicit actor or serial-executor boundary, the implementation can still race, double-publish, or block the main thread.
  - Recommended fix: Define one serialized ownership model per namespace, with explicit actor isolation for CloudKit I/O, SwiftData writes, outbox draining, and UI state projection. Keep the SwiftUI shell on a separate main-actor adapter.
  - Acceptance criteria: Overlapping accept/refresh/revoke/publish operations are deterministic in tests; only one publish pipeline can run per namespace; no CloudKit or SwiftData write runs on the main actor; race tests cannot produce duplicate projection versions or crashes.

- [Medium] Bound the lifecycle and resource cost of the per-namespace store strategy.
  - Evidence: `DOC-03`, `DOC-04`, `DOC-07`
  - Why it matters: Isolating each shared dataset into its own SQLite-backed container is a clean boundary, but the proposal does not define when stores are opened, compacted, or purged. Over time, share churn can increase file count, startup cost, and memory use.
  - Recommended fix: Specify lazy-open behavior, deterministic close/compact/purge rules, and measured upper bounds for active and retained namespaces.
  - Acceptance criteria: Stress tests with multiple active and revoked shares remain within declared startup and memory budgets; revoked namespaces are removed or compacted on schedule; reopening the same namespace is idempotent and does not leak store instances.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: UX wants a short, CTA-first pre-share disclosure while UI requires stronger hierarchy and architecture requires the sheet to remain normative for scope/legal correctness.
  - Tradeoff: A dense legal-style sheet satisfies completeness but harms comprehension and conversion; an oversimplified sheet improves flow but can weaken informed consent.
  - Decision: Use a staged summary sheet with a first-viewport summary, expandable sections for details, and a sticky primary action. Keep the mandatory acknowledgment but reduce initial density.
  - Owner: Product + Design + iOS

- Conflict: UI wants strict opaque surfaces for data cards, while the proposal is framed within a Liquid Glass design language.
  - Tradeoff: More glass can feel premium in screenshots but weakens financial readability and accessibility in motion/contrast edge cases.
  - Decision: Reserve glass for navigation chrome and section containers only; all monetary cards, freshness banners, and recovery cards must use opaque or near-opaque surfaces.
  - Owner: Design + iOS

- Conflict: UX prefers task-oriented owner access, while architecture values deterministic ordering for stable diffs and predictable tests.
  - Tradeoff: Pure alphabetical ordering is test-friendly but can slow user access; dynamic ordering improves usability but risks nondeterminism.
  - Decision: Keep deterministic alphabetical ordering as the default canonical order, then add a lightweight recency/pinned shortcut that does not change the underlying canonical grouping order.
  - Owner: Product + iOS

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Add explicit pre-share scope preview layout contract with staged hierarchy and sticky primary CTA | UI + UX | Design + Product | Now | None | Preview fits one iPhone viewport and passes Dynamic Type/Reduce Motion checks |
| P0 | Specify namespace actor/executor model for accept, refresh, revoke, publish, and outbox drain | Architecture | iOS | Now | None | Race tests show deterministic outcomes with no duplicate publishes or main-thread storage writes |
| P0 | Define cache migration, rebuild, and rollback contract for per-namespace SwiftData stores | Architecture | iOS | Now | Namespace storage design | Upgrade/rollback tests pass for shared-cache namespaces |
| P1 | Expand invitee lifecycle into distinct pending, empty, revoked, and unavailable recovery states | UX | Product + Design + iOS | Next | P0 disclosure/state model alignment | No blank shared-goals shell; each terminal state has one primary next action |
| P1 | Define material hierarchy and reduced-transparency rules for shared finance surfaces | UI | Design + iOS | Next | P0 preview visual contract | Contrast and legibility pass in light/dark/increased-contrast/reduced-transparency modes |
| P1 | Define sticky owner headers, inline owner chips, and shared-row chrome token | UI + UX | Design + iOS | Next | Shared-goals IA | Owner is identifiable from any scroll position without opening a row |
| P2 | Add recency/pinned owner shortcut without breaking deterministic canonical ordering | UX | Product + iOS | Later | Shared-goals usage data | Active owner is reachable in one tap in multi-owner households |
| P2 | Add namespace retention budget, compaction cadence, and purge telemetry | Architecture | iOS | Later | P0 namespace lifecycle contract | Startup time, memory, and orphaned-store counts remain within rollout budget |

## 6. Execution Plan
- Now (0-2 weeks):
  - Update the proposal with a staged pre-share disclosure layout, sticky CTA behavior, and first-viewport readability requirements.
  - Add explicit actor/executor ownership for namespace operations and document main-actor boundaries.
  - Lock cache schema migration and rollback rules for per-namespace stores, including downgrade/fail-closed behavior.
- Next (2-6 weeks):
  - Expand lifecycle/recovery states for invitees and wire them into the visual/state matrix.
  - Finalize material hierarchy, reduced-transparency behavior, sticky owner headers, and inline ownership cues.
  - Add proposal-level acceptance tests for Dynamic Type, Reduce Motion, and multi-owner list identity.
- Later (6+ weeks):
  - Add usage-informed owner shortcutting or pinning if multi-owner usage justifies it.
  - Add operational budgets and telemetry for namespace churn, compaction, and purge.
  - Revisit any remaining polish after first runtime prototypes exist and real screenshots replace preview-only evidence.

## 7. Open Questions
- Does v1 need the recency/pinned owner shortcut, or is deterministic grouping sufficient for first release if ownership cues are strong enough?
- Should cache rollback be fail-closed only, or does the team want a limited backward-readable namespace format for one-version rollback tolerance?
- Does the rollout gate need an explicit namespace-count budget per account before implementation begins, or is that acceptable as an implementation-phase benchmark?
