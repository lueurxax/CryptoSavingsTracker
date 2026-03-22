# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `full-review`
- Evidence completeness: `Complete`
- Documents / repo inputs reviewed:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_TRIAD_REVIEW_R1.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/FAMILY_SHARING.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_EVIDENCE_PACK_R2.md`
- External sources reviewed:
  - [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
  - [Apple UI Design Dos and Don’ts](https://developer.apple.com/design/tips/)
  - [W3C WCAG 2.2 Understanding SC 4.1.3 Status Messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages)
- Build/run attempts:
  - `RUN-01`: fresh `xcodebuild` Debug build succeeded on `iPhone 15` simulator, iOS 18.0
  - `RUN-02`: fresh simulator install/launch succeeded with seeded `invitee_active`, `invitee_stale`, `invitee_unavailable`, and `invitee_empty` states
- Screenshots captured:
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r2/screenshots/invitee-active-list.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r2/screenshots/invitee-active-detail.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r2/screenshots/invitee-stale-list.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r2/screenshots/invitee-unavailable-list.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r2/screenshots/invitee-empty-list.png`
- Code areas inspected:
  - `FamilyShareServices`
  - `FamilyShareCloudKitStore`
  - `FamilyShareRollout`
  - `GoalCalculationService`
  - `ExchangeRateService`
  - `PersistenceMutationServices`
  - `FamilySharingModels`
  - `SharedGoalsSectionView`
- Remaining assumptions:
  - Runtime evidence is simulator-seeded rather than a live owner/invitee CloudKit loop across two devices.
  - This repeat pass is proposal review, not implementation audit.
- Remaining blockers:
  - No live multi-device CloudKit timing or push-delivery proof.
  - No proposed-state mockups or simulator captures for the new freshness labels, large Dynamic Type, dark mode, or VoiceOver.

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `Medium`
- Release blockers:
  - The proposal still has one unresolved timestamp-authority conflict: some sections make list freshness composite, while older wording still allows the header to derive from raw `publishedAt` / `projectionPublishedAt`.
  - The materiality threshold still does not define how `$5 equivalent` is computed for non-USD goals.
  - `GoalProgressCalculator` is now correctly required, but the proposal still does not lock a sendable input boundary for safe off-main execution.
- Top risks:
  1. An implementer can still produce a visually “fresh” header while rates are stale because the document has not fully converged on one timestamp authority.
  2. Rate-drift publish decisions can diverge across currencies if `$5 equivalent` conversion and rounding are not specified.
  3. The new pure calculator can still accidentally inherit SwiftData or view-model dependencies unless the proposal defines its input shape explicitly.
- Top opportunities:
  1. The major `R1` blockers around serialized ownership, pure calculation extraction, and cache migration are now explicitly acknowledged in the proposal.
  2. The invitee UI contract is much tighter: one primary freshness line, optional secondary rate-age detail, and cross-surface freshness-label reuse are now written down.
  3. The test plan is materially stronger and now covers composite freshness, coordinator serialization, migration, and accessibility.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | `Amber` | `Medium` | `Partial` | 0 | 1 | 1 | 0 |
| UX | `Amber` | `High` | `Partial` | 0 | 1 | 1 | 0 |
| iOS Architecture | `Amber` | `High` | `Partial` | 0 | 2 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Findings
- Finding ID: `UI-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `QUESTION-01`, `SCR-02`, `BASE-01`
  Why it matters:
  The proposal now defines a composite freshness model in Sections 5.1.1, 6.4, 6.6, and 8.2, but Section 6.3.5 and Acceptance Criterion 8 still allow the invitee header to be read as a raw `publishedAt` / `projectionPublishedAt` label. In a finance UI that can render a visually “fresh” header while rates are stale, which is a direct trust break.
  Recommended fix:
  Make `FamilyShareFreshnessLabel` the only authority for the primary header string everywhere. Remove any standalone list-header wording that derives directly from raw `publishedAt` or `projectionPublishedAt`.
  Acceptance criteria:
  List and detail use the same primary freshness grammar, no screen can display `active` when rate age is stale, and header copy is derived from the composite rule only.
  Confidence: `High`

- Finding ID: `UI-02`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `SCR-04`, `SCR-05`, `BASE-03`, `BASE-04`
  Why it matters:
  Section 8.3 now defines named tokens and VoiceOver behavior for the four freshness tiers, but it still does not specify equivalent visual semantics for `temporarilyUnavailable` and `removedOrNoLongerShared`. Those are recovery-critical states, and leaving them outside the visual contract makes the design incomplete exactly where clarity matters most.
  Recommended fix:
  Add explicit token/icon/copy/accessibility rules for `temporarilyUnavailable` and `removedOrNoLongerShared`, or explicitly state that they reuse named existing semantics.
  Acceptance criteria:
  Both states have defined copy, semantic token treatment, and accessibility behavior, and they render distinctly from freshness-tier states on compact widths and supported appearances.
  Confidence: `Medium`

### 3.2 UX Findings
- Finding ID: `UX-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `QUESTION-01`, `SCR-02`
  Why it matters:
  The proposal still contains an unresolved timestamp-authority conflict. One older rule says the invitee surface shows `publishedAt` as the relative-time indicator, while later sections define a composite trust model. That leaves room for implementation drift back to “Updated 5 min ago” even when rates are stale enough that the numbers should be treated as warning-grade.
  Recommended fix:
  Make one rule authoritative: all visible freshness copy must come from `FamilyShareFreshnessLabel` using composite effective age, while raw `projectionPublishedAt` and `rateSnapshotTimestamp` remain provenance only.
  Acceptance criteria:
  A fresh publish with stale rates never renders as `active`, list and detail always agree on the primary freshness message, and a recent-publish/stale-rate test case yields warning copy rather than “Updated {time}.”
  Confidence: `High`

- Finding ID: `UX-02`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `QUESTION-02`
  Why it matters:
  The threshold `1% of targetAmount or $5 equivalent` is still ambiguous for non-USD goals because the proposal does not define conversion source, rounding, or quote-currency policy. In a finance flow, that ambiguity leaks into when a user sees data cross from acceptable to stale.
  Recommended fix:
  Define one shared `FamilyShareMaterialityPolicy` covering quote currency, FX source, rounding, and comparison behavior. Keep UI copy threshold-agnostic if the raw math is not meant to be user-visible.
  Acceptance criteria:
  The same semantic goal state classifies identically across locales and target currencies, and threshold behavior is documented once and referenced consistently by UX copy, telemetry, and tests.
  Confidence: `High`

### 3.3 iOS Architecture Findings
- Finding ID: `ARCH-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `DOC-02`, `QUESTION-02`
  Why it matters:
  The rate-drift materiality rule is still underspecified for non-USD goals. Without a single policy for computing `$5 equivalent`, publish/no-publish decisions can diverge across currencies and exact-threshold cases, which is unacceptable in a correctness-sensitive sync pipeline.
  Recommended fix:
  Introduce a single `FamilyShareMaterialityPolicy` with an explicit quote currency, conversion source, and rounding rule, and reference it from every threshold-related section and test.
  Acceptance criteria:
  Boundary tests produce identical materiality decisions for the same semantic state across USD and non-USD goals, including exact-threshold cases.
  Confidence: `High`

- Finding ID: `ARCH-02`
  Severity: `High`
  Evidence IDs: `DOC-01`, `DOC-02`, `CODE-01`, `CODE-02`
  Why it matters:
  The proposal now correctly requires a pure, non-`@MainActor` `GoalProgressCalculator`, but it still does not specify the input shape. Without an explicit sendable snapshot boundary, implementation can still leak SwiftData managed objects or view-model state into the coordinator path and break the off-main execution requirement.
  Recommended fix:
  Define sendable value snapshots for goal, allocation, and rate inputs; require the coordinator to map managed objects into those snapshots; and keep the calculator free of SwiftData and view-model imports.
  Acceptance criteria:
  The calculator compiles without SwiftData or view-model dependencies, is callable from the coordinator actor, and has deterministic parity tests against the existing calculation path.
  Confidence: `High`

- Finding ID: `ARCH-03`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `DOC-03`
  Why it matters:
  The proposal is still internally inconsistent about which timestamp drives the invitee header. That means the same primary string can end up with three authorities: raw `publishedAt`, raw `projectionPublishedAt`, or the composite label object. For implementation, that is an avoidable ambiguity in a critical trust surface.
  Recommended fix:
  Make `FamilyShareFreshnessLabel` the sole source of primary list/detail freshness text and demote raw timestamps to provenance fields only.
  Acceptance criteria:
  No section instructs the list header to derive directly from raw `publishedAt`, and list/detail tests emit identical copy from the same label object.
  Confidence: `High`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict:
  The document now wants composite trust semantics, but older phrasing still allows the list header to behave like a simple publish-time badge.
  Tradeoff:
  Raw publish-time copy is simpler to describe; composite trust copy is more truthful for a finance surface.
  Decision:
  Make `FamilyShareFreshnessLabel` the sole owner of the primary user-facing freshness string and treat raw timestamps as provenance only.
  Owner:
  Proposal author + UX + iOS architecture

- Conflict:
  The proposal compresses list-view messaging well, but the visual contract only fully specifies the four freshness tiers and not the failure/removal states users actually recover from.
  Tradeoff:
  Keeping the token table small is simpler; including recovery states makes the contract implementation-safe.
  Decision:
  Extend the visual contract to cover `temporarilyUnavailable` and `removedOrNoLongerShared`, or explicitly bind them to named existing semantics.
  Owner:
  Proposal author + UI/UX

- Conflict:
  The document now requires a pure calculator, but not yet the value-snapshot boundary needed to keep it truly off-main and non-UI.
  Tradeoff:
  A lighter proposal leaves implementers flexibility; a stricter boundary avoids accidental dependency drift.
  Decision:
  Add a sendable snapshot contract for calculator inputs before implementation starts.
  Owner:
  iOS architecture

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P0 | Remove all `publishedAt` / `projectionPublishedAt`-only header wording and make `FamilyShareFreshnessLabel` the single freshness-string authority | UI / UX / iOS Architecture | Proposal author | Now | Current composite freshness sections | No section or acceptance criterion can be read as “header = raw publish time” | `UI-01`, `UX-01`, `ARCH-03` |
| P0 | Define a single `FamilyShareMaterialityPolicy` for `$5 equivalent`, including FX source and rounding | UX / iOS Architecture | Proposal author + iOS architecture | Now | Existing rate-drift rules | Threshold decisions are deterministic across USD and non-USD goals | `UX-02`, `ARCH-01` |
| P1 | Define sendable value snapshots for `GoalProgressCalculator` inputs and explicitly prohibit SwiftData/view-model dependencies | iOS Architecture | iOS architecture | Now | Current `GoalCalculationService` dependency shape | Calculator is safe to run off-main and test independently | `ARCH-02` |
| P1 | Extend the visual/accessibility contract to `temporarilyUnavailable` and `removedOrNoLongerShared` | UI | UI/UX | Pre-implementation | Existing freshness token table | Recovery-critical states have explicit tokens, icons, copy, and VoiceOver rules | `UI-02` |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Freshness-label authority | Which timestamp basis drives the primary list/detail string | Proposal sections and tests all point to one label object | No screen can appear `active` when rate age is stale | Before implementation kickoff | Hold if raw `publishedAt` remains a valid header authority anywhere in the proposal |
| Materiality policy | Deterministic threshold evaluation across currencies | Boundary tests for USD and non-USD goals, exact-threshold cases | No churn or suppression differences for semantically identical goal states | End of Phase 0 design | Hold if `$5 equivalent` still lacks FX and rounding rules |
| Pure calculator boundary | Off-main safety of `GoalProgressCalculator` | Calculator module compiles without SwiftData/view-model imports | No coordinator path requires `@MainActor` or managed objects | End of Phase 0 design | Hold if sendable calculator inputs are not specified |
| Failure-state UI contract | Copy/tokens/accessibility for unavailable and removed states | Visual contract table covers all recovery-critical states | Distinct semantics remain visible on compact widths and supported appearances | Before UI implementation | Hold if unavailable/removed states remain outside the documented visual contract |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- `GAP-01`: No live multi-device CloudKit publish/fetch or push-delivery evidence was captured for this repeat pass.
- `GAP-02`: No proposed-state mockups or simulator captures exist yet for the new composite freshness labels, dark mode, large Dynamic Type, or VoiceOver behavior.

### Open Questions
- `QUESTION-01`: After the proposal is corrected, should the detail view show only expanded provenance beneath the shared primary label, or is any additional warning-specific copy still needed there?
- `QUESTION-02`: Should `temporarilyUnavailable` and `removedOrNoLongerShared` get dedicated semantic tokens, or should they explicitly reuse an existing app-wide failure-state token family?
