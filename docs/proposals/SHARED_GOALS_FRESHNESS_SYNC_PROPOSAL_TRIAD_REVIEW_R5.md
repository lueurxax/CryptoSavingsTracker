# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `full-review`
- Evidence completeness: `Partial`
- Documents / repo inputs reviewed:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_TRIAD_REVIEW_R4.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_EVIDENCE_PACK_R5.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/FAMILY_SHARING.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/runbooks/family-sharing-release-gate.md`
- External sources reviewed:
  - [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
  - [Apple UI Design Tips](https://developer.apple.com/design/tips/)
  - [W3C WCAG 2.2 Understanding SC 4.1.3 Status Messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages)
- Build/run attempts:
  - `RUN-01`: fresh `xcodebuild` Debug build succeeded on `iPhone 15` simulator, iOS 18.0
  - `RUN-02`: app installed and launched successfully via `simctl` with seeded invitee state
- Screenshots captured:
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r5/screenshots/invitee-active-list-r5.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r5/screenshots/invitee_stale-r5.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r5/screenshots/invitee_unavailable-r5.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r5/screenshots/invitee_empty-r5.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r5/screenshots/invitee_removed-r5.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r5/screenshots/invitee_multi_owner-r5.png`
- Code areas inspected:
  - `SharedGoalsSectionView`
  - `SharedGoalDetailView`
  - `FamilySharingModels`
  - `SharedGoalsReputationRedesignPreview`
  - `UITestFlags`
  - `CryptoSavingsTrackerApp`
  - `ContentView`
  - `FAMILY_SHARING.md`
- Remaining assumptions:
  - Simulator evidence is seeded through repo-local UITest flags rather than a live owner/invitee CloudKit session.
  - This pass evaluates proposal readiness against the current repository and runtime baseline; it does not claim implementation completeness.
- Remaining blockers:
  - No live two-owner-device CloudKit publish/import trace was captured for this pass.
  - No proposal-specific mockups or simulator captures exist yet for the new freshness header and detail `Freshness` card across dark mode, large Dynamic Type, VoiceOver, or reduce-motion.

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `Medium`
- Release blockers:
  - The proposal still defines `contentHash` too narrowly for the invitee-visible projection contract, so metadata-only publishes such as owner display-name changes can be deduplicated away.
  - The freshness timing contract is still internally inconsistent: the owner-side rate TTL is 5 minutes, but the periodic foreground guard only reevaluates every 15 minutes.
- Top risks:
  1. Invitees can miss legitimate shared-state updates if `contentHash` ignores invitee-visible root metadata while dedup remains authoritative.
  2. The list/detail freshness contract still has unresolved copy and provenance contradictions, especially for `checkedNoNewData`, rate-governed `materiallyOutdated`, and accessibility-size provenance collapse.
  3. The new header/card visual system is still text-only; the repo has only older banner-first previews, not proof for the final freshness-specific UI.
- Top opportunities:
  1. The `R4` architectural blockers are materially closed: the reconciliation barrier, trigger inventory, separate `projectionVersion` vs `projectionServerTimestamp`, and terminal removed-state contract are now explicit.
  2. The remaining issues are spec-hardening problems, not a full rewrite of the proposal direction.
  3. The repo already has seeded invitee scenarios and preview infrastructure, so the remaining visual-proof and scenario-proof work is cheap to produce before implementation.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | `Amber` | `Medium` | `Partial` | 0 | 1 | 2 | 0 |
| UX | `Amber` | `Medium` | `Partial` | 0 | 2 | 0 | 0 |
| iOS Architecture | `Amber` | `Medium` | `Partial` | 0 | 2 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Findings
- Finding ID: `UI-01`
  Severity: `High`
  Evidence IDs: `BLOCKER-02`, `CODE-02`, `CODE-07`, `SCR-01`, `SCR-02`, `SCR-03`, `SCR-05`, `SCR-06`, `BASE-04`
  Why it matters:
  The proposal adds a new per-namespace freshness header and a dedicated detail `Freshness` card, but the evidence pack only proves current runtime states and an older banner-first preview gallery. That leaves the final compact header hierarchy, material treatment, dark-mode contrast, fold safety, and Dynamic Type behavior unvalidated for the exact UI this proposal wants to ship.
  Recommended fix:
  Add proposal-specific mockups or simulator captures for `active`, `stale`, `temporarilyUnavailable`, `removedOrNoLongerShared`, and `checkedNoNewData` states on iPhone 15 at default and largest supported Dynamic Type, in light and dark appearance, with the intended material treatment.
  Acceptance criteria:
  The evidence pack includes proposal-specific visuals for the new header/card system; no clipping, overlap, or unreadable translucency appears; and the financial summary remains dominant above the detail `Freshness` card.
  Confidence: `High`

- Finding ID: `UI-02`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `SCR-01`, `SCR-06`, `BASE-01`, `BASE-05`, `WEB-02`
  Why it matters:
  The compact-layout contract says the namespace title, primary freshness message, recovery action, and sometimes secondary provenance must all survive iPhone 15 at the largest supported Dynamic Type, but the fallback rules only describe collapsing secondary provenance. There is still no explicit rule for long owner names plus two-line freshness copy plus a trailing action, so header height and truncation behavior remain under-specified.
  Recommended fix:
  Extend the header priority matrix to define what collapses first when the owner name is long, when freshness wraps, and when the action must stay tappable. Do not leave header growth to implementation-time guesswork.
  Acceptance criteria:
  Long owner names render cleanly at iPhone 15 width and largest supported Dynamic Type; no header overlaps rows; and trailing actions remain at least 44x44pt.
  Confidence: `Medium`

- Finding ID: `UI-03`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `CODE-02`, `BASE-04`
  Why it matters:
  The detail contract promises both exact timestamps inline, an optional stale explanation affordance, and a guarantee that `Current` / `Target` stay above the fold. Once localized timestamps or accessibility sizes expand, those constraints can conflict because the proposal still does not define a hard line budget or a collapse order inside the card.
  Recommended fix:
  Define a line budget by Dynamic Type tier and a deterministic collapse order inside the detail card: secondary provenance first, then exact timestamp density, then the info affordance if needed.
  Acceptance criteria:
  On iPhone 15 at the largest supported Dynamic Type, the primary financial summary stays above the fold and the detail card degrades predictably without clipping.
  Confidence: `Medium`

### 3.2 UX Findings
- Finding ID: `UX-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `WEB-03`, `BASE-04`
  Why it matters:
  The proposal is still internally inconsistent on provenance visibility. Section 6.6 says detail provenance rows keep exact local timestamps visible inline, but Section 8.2 later allows those rows to collapse into a `Tap for details` affordance at the largest supported Dynamic Type. That means the most accessibility-sensitive users can lose the exact trust proof the contract earlier said would stay visible.
  Recommended fix:
  Pick one rule and make it canonical. Either keep both exact timestamps visible at all supported sizes in a compact accessible format, or explicitly replace the always-visible rule with a disclosure pattern and define its accessibility semantics.
  Acceptance criteria:
  At the largest supported Dynamic Type on iPhone 15, the detail view still exposes both provenance timestamps without a contradictory spec path; if disclosure is required, the proposal says so explicitly and defines VoiceOver behavior.
  Confidence: `High`

- Finding ID: `UX-02`
  Severity: `High`
  Evidence IDs: `DOC-01`, `WEB-03`
  Why it matters:
  The freshness-copy contract still has competing canonical sources. Section 6.4.2 says `checkedNoNewData` appends to the primary age-based message and does not replace it, but the concrete header matrix lists `Checked — no newer update yet` as a standalone line. Earlier in Section 8.2, rate-governed `materiallyOutdated` uses `Rates are 3 days old...`, but the final matrix collapses that to one `either` row that says only `Last shared 3d ago...`. Those contradictions are enough to produce materially different list behavior in implementation.
  Recommended fix:
  Make the concrete header matrix authoritative and align all earlier prose to it. Split `materiallyOutdated` into publish-governed and rate-governed rows, and define `checkedNoNewData` as a secondary note that never hides the underlying age-based severity.
  Acceptance criteria:
  One canonical matrix remains after revision; rate-governed `materiallyOutdated` always names rate staleness explicitly; `checkedNoNewData` never erases the underlying freshness tier; and VoiceOver copy matches the same semantics.
  Confidence: `High`

### 3.3 iOS Architecture Findings
- Finding ID: `ARCH-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `DOC-03`, `CODE-06`
  Why it matters:
  `contentHash` is currently defined only over canonical goal data plus the rate snapshot timestamp, but the same proposal also routes owner display-name changes and participant changes through `.participantChange`, and the current projection contract includes owner display name as invitee-visible shared data. Because invitee dedup treats equal `contentHash` as a no-op regardless of ordering, metadata-only publishes can be suppressed and invitees can miss real shared-state changes.
  Recommended fix:
  Define `contentHash` over the full invitee-visible canonical projection payload, or split data-hash and metadata-hash semantics so any invitee-visible root metadata change still produces an update.
  Acceptance criteria:
  Owner display-name change, participant membership change, and any other invitee-visible metadata-only publish produce a distinct invitee update even when goal amounts and rates are unchanged; exact no-op publishes still deduplicate.
  Confidence: `High`

- Finding ID: `ARCH-02`
  Severity: `High`
  Evidence IDs: `DOC-01`
  Why it matters:
  The owner-side rate contract is still internally inconsistent. Foreground entry checks a 5-minute rate TTL, but the long-session periodic guard only reevaluates every 15 minutes. In a long foreground session, the app can therefore exceed its own freshness TTL by up to 10 minutes before reevaluation, which weakens the proposal’s rate-drift trust claim.
  Recommended fix:
  Align the periodic reevaluation cadence with the 5-minute TTL, or compute the next foreground refresh from the exact TTL-expiry boundary instead of a fixed 15-minute poll.
  Acceptance criteria:
  In a continuously foregrounded owner session, no namespace remains past the 5-minute TTL without a refresh/evaluation attempt; tests prove reevaluation happens on or before the TTL boundary.
  Confidence: `High`

- Finding ID: `ARCH-03`
  Severity: `Medium`
  Evidence IDs: `DOC-01`
  Why it matters:
  `FamilyShareLastPublishedSnapshot` is introduced as the baseline for rate-drift comparison, but the proposal never defines where that snapshot is stored durably, how it survives relaunch, or how it is rebuilt during cache migration. Without that contract, rate-drift detection can become non-deterministic across cold starts and migrations.
  Recommended fix:
  Specify persistence and bootstrap semantics for `FamilyShareLastPublishedSnapshot`, or explicitly rebuild it from the cached projection before enabling rate-drift evaluation.
  Acceptance criteria:
  Cold launch, reinstall, and cache-migration scenarios either restore the last-published baseline deterministically or suppress rate-drift evaluation until the baseline is rebuilt; tests cover both paths.
  Confidence: `Medium`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict:
  The proposal wants aggressive semantic deduplication to avoid churn, but the shared projection contract includes invitee-visible metadata outside the current `contentHash` definition.
  Tradeoff:
  A goal-data-only hash is simpler; a full invitee-visible payload hash is safer and preserves correctness for metadata-only publishes.
  Decision:
  Make the dedup contract reflect the full invitee-visible payload, or split metadata and data hashes explicitly.
  Owner:
  Proposal author + iOS architecture

- Conflict:
  The proposal wants exact freshness provenance visible inline, but it also wants the detail card to collapse for accessibility sizes without pushing financial summary below the fold.
  Tradeoff:
  Always-visible provenance improves trust; aggressive collapse improves compactness.
  Decision:
  Pick one canonical AX behavior and document the line budget and collapse order explicitly.
  Owner:
  Proposal author + UX + UI

- Conflict:
  The proposal sets a 5-minute rate TTL but uses a 15-minute periodic reevaluation loop for long foreground sessions.
  Tradeoff:
  A slower poll is cheaper; a TTL-aligned cadence is required if the freshness promise is literal.
  Decision:
  Align reevaluation with TTL expiry rather than keeping a fixed 15-minute guard.
  Owner:
  Proposal author + iOS architecture

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P0 | Redefine `contentHash` so invitee-visible metadata-only publishes cannot be deduplicated away | iOS Architecture | Proposal author + iOS architecture | Now | Current shared projection field contract in `/Users/user/Documents/CryptoSavingsTracker/docs/FAMILY_SHARING.md` | Owner display-name and participant changes produce visible invitee updates without breaking no-op dedup | `ARCH-01` |
| P0 | Align the long-session rate reevaluation cadence with the 5-minute freshness TTL | iOS Architecture | Proposal author + iOS architecture | Now | Owner foreground refresh design | No owner session can exceed the stated TTL without a refresh/evaluation attempt | `ARCH-02` |
| P1 | Make one canonical freshness-copy matrix and resolve `checkedNoNewData` / rate-governed `materiallyOutdated` contradictions | UX | Proposal author + UX | Before implementation | Current Sections 6.4.2 and 8.2 | Engineers cannot derive conflicting list/header copy from different sections | `UX-02` |
| P1 | Resolve the exact-provenance visibility contract for accessibility sizes | UX + UI | Proposal author + UX + UI | Before implementation | Detail `Freshness` card design | AX behavior is explicit, consistent, and testable | `UX-01`, `UI-03` |
| P1 | Add proposal-specific visual proof for the new freshness header and detail card | UI | Proposal author + UI | Before implementation | Seeded simulator flows and preview infrastructure | Light/dark, large Dynamic Type, VoiceOver, and reduce-motion proofs exist for the final design | `UI-01`, `UI-02` |
| P2 | Define durable persistence and bootstrap rules for `FamilyShareLastPublishedSnapshot` | iOS Architecture | Proposal author + iOS architecture | Pre-build hardening | Cache migration and rate-drift evaluator | Cold-start and migration behavior are deterministic | `ARCH-03` |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Dedup correctness | Whether invitee-visible metadata-only publishes still reach the invitee surface | Metadata-only mutation tests, hash diff tests, invitee cache-update tests | No owner-name or participant update is dropped when shared rows are otherwise unchanged | Before implementation kickoff | Hold if `contentHash` still ignores invitee-visible root metadata |
| Rate-freshness cadence | Whether the owner-side reevaluation cadence respects the stated 5-minute TTL | Foreground-session timing tests, scheduler design proof | No namespace exceeds TTL without a refresh/evaluation attempt | Before architecture sign-off | Hold if the proposal keeps a fixed 15-minute loop with a 5-minute TTL |
| Copy truthfulness | Whether list/header copy always tells the user what is stale and whether refresh can help | Scenario matrix for publish-governed, rate-governed, `refreshFailed`, and `checkedNoNewData` | One canonical header matrix drives list, detail, and VoiceOver text | Before UX sign-off | Hold if Section 6 and Section 8 still permit conflicting implementations |
| Visual proof | Whether the new freshness header/card system survives compact widths, AX text, dark mode, and motion/accessibility constraints | Proposal-specific previews or simulator captures | No overlap, clipped actions, or unreadable materials; money-first hierarchy remains intact | Before UI sign-off | Hold if only current-state screenshots or old banner previews exist |
| Snapshot durability | Whether `FamilyShareLastPublishedSnapshot` survives relaunch and migration without noisy or missing republish behavior | Cold-start and migration tests | Rate-drift evaluation stays deterministic across relaunch and migration | Before Phase 2 implementation | Hold if snapshot bootstrap remains undefined |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- `GAP-01`: No live two-owner-device CloudKit publish/import trace was captured in `R5`, so the multi-device ordering/reconciliation path remains architecture-validated rather than runtime-replayed.
- `GAP-02`: No proposal-specific mockups or simulator captures exist yet for the new freshness header and detail `Freshness` card in light/dark mode, large Dynamic Type, VoiceOver, or reduce-motion.
- `GAP-03`: The repo contains older banner-first redesign previews, but not visual proof for this proposal’s final freshness-specific list header and detail card.

### Open Questions
- `QUESTION-01`: Should `contentHash` cover the entire invitee-visible canonical projection payload, or should the proposal define separate metadata and data hash semantics?
- `QUESTION-02`: At the largest supported Dynamic Type, are exact provenance timestamps still always visible, or is an accessible disclosure affordance the intended final behavior?
- `QUESTION-03`: Should `checkedNoNewData` remain a secondary note that preserves the underlying age-based freshness tier, and should `materiallyOutdated` split publish-governed vs rate-governed rows explicitly in the canonical matrix?
