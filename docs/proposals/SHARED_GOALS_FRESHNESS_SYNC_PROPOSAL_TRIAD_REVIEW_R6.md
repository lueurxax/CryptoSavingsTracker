# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `full-review`
- Evidence completeness: `Complete`
- Documents / repo inputs reviewed:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/FAMILY_SHARING.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_TRIAD_REVIEW_R5.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/runbooks/family-sharing-release-gate.md`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r6/evidence-pack.md`
- External sources reviewed:
  - none
- Build/run attempts:
  - `RUN-01`: `xcodebuild` Debug build succeeded for `CryptoSavingsTracker` on `iPhone 15` simulator, iOS 18.0
  - `RUN-01`: app installed and launched successfully for seeded scenarios `invitee_active`, `invitee_stale`, `invitee_unavailable`, `invitee_empty`, `invitee_removed`, and `invitee_multi_owner`
- Screenshots captured:
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r6/screenshots/invitee_active.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r6/screenshots/invitee_stale.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r6/screenshots/invitee_unavailable.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r6/screenshots/invitee_empty.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r6/screenshots/invitee_removed.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r6/screenshots/invitee_multi_owner.png`
- Code areas inspected:
  - `FamilyShareServices`
  - `FamilyShareCloudKitStore`
  - `FamilyShareCacheStore`
  - `FamilyShareRollout`
  - `GoalCalculationService`
  - `ExchangeRateService`
  - `PersistenceMutationServices`
  - `SharedGoalsSectionView`
  - `FamilySharingModels`
  - `ContentView`
- Remaining assumptions:
  - Seeded UITest family-sharing scenarios are representative enough for current invitee-surface baseline review.
  - This pass evaluates proposal readiness against current repo reality, not implementation completeness.
- Remaining blockers:
  - No live two-owner-device CloudKit publish/import trace was captured in this pass.
  - No proposal-specific rendered proof exists yet for the new freshness header/detail-card system in dark mode, large Dynamic Type, or VoiceOver.

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `Medium`
- Release blockers:
  - `contentHash` still ignores invitee-visible root metadata, so metadata-only publishes can be deduplicated away.
  - The 5-minute rate freshness promise is still incompatible with the 15-minute long-session reevaluation cadence.
  - Version/ordering semantics remain internally contradictory, and the current draft still permits stale semantic state to win behind a newer server timestamp.
  - The freshness copy/provenance contract is still contradictory across Section 6 and Section 8, especially for accessibility-size behavior and rate-governed copy.
- Top risks:
  1. Invitees can miss legitimate updates when owner display-name or participant metadata changes without goal-level changes.
  2. The implemented copy can mislead users about what is stale, especially when rates govern freshness but the headline starts with `Shared X ago`.
  3. Multi-device owner publishing can still regress fresher semantic state unless the proposal strengthens semantic ordering beyond timestamp wins.
- Top opportunities:
  1. The proposal still targets a confirmed live correctness gap: current shared projections are built from `goal.manualTotal`, not a pure allocation-aware domain calculator.
  2. The repo already has rollout controls, seeded invitee states, and a repeatable simulator capture path, so most remaining work is spec-hardening rather than discovery.
  3. The terminal removed-state purge rule is justified by fresh runtime evidence: current removed state still leaves stale financial rows visible.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | `Amber` | `Medium` | `Complete` | 0 | 1 | 1 | 0 |
| UX | `Amber` | `Medium` | `Complete` | 0 | 1 | 2 | 1 |
| iOS Architecture | `Amber` | `Medium` | `Complete` | 0 | 3 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Findings
- Finding ID: `UI-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `SCR-01`, `SCR-02`, `BASE-01`
  Why it matters:
  The detail-view freshness contract is still internally inconsistent. Section 6.6 says exact `Last shared` and `Rates as of` timestamps are always visible inline and never hidden, but Section 8.2 allows those rows to collapse into a `Tap for details` affordance at the largest supported Dynamic Type size. That removes trust-critical provenance exactly in the accessibility case the proposal is trying to define.
  Recommended fix:
  Make one canonical accessibility rule. Either exact timestamps remain visible inline at all supported sizes, or the proposal explicitly moves them behind one disclosure pattern with defined accessibility semantics and summary text.
  Acceptance criteria:
  On iPhone 15 at the largest supported Dynamic Type size, both provenance timestamps remain deterministically discoverable, and the document no longer contains contradictory inline-vs-disclosure paths.
  Confidence: `High`

- Finding ID: `UI-02`
  Severity: `Medium`
  Evidence IDs: `RUN-01`, `SCR-01`, `SCR-02`, `SCR-06`, `BASE-01`
  Why it matters:
  Fresh runtime screenshots prove only the current banner-first shared-goals surface. They do not validate the proposal’s new header/detail-card system under dark mode, large Dynamic Type, or tokenized stale-state rendering. That leaves color, overflow, and hierarchy claims unproven for the UI the proposal actually wants to ship.
  Recommended fix:
  Add proposal-specific previews or simulator renders for `active`, `stale`, `temporarilyUnavailable`, `removedOrNoLongerShared`, and rate-governed states in light/dark mode and at the largest supported Dynamic Type size.
  Acceptance criteria:
  The evidence pack includes final-form renders for the new freshness header/card system; no overlap, clipping, or unreadable state-token combinations appear across the validated states.
  Confidence: `Medium`

### 3.2 UX Findings
- Finding ID: `UX-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `SCR-01`, `SCR-06`, `BASE-01`, `BASE-05`
  Why it matters:
  The canonical freshness grammar is still misleading in rate-governed cases. The proposal says the primary message must reflect the governing dependency, but the `recentlyStale` rate-governed line still starts with `Shared 5 min ago`. In a finance surface, that foregrounds apparent freshness instead of the stale dependency affecting the money values.
  Recommended fix:
  For every rate-governed stale tier, lead with rate age first and demote publish age to secondary provenance or detail-only context.
  Acceptance criteria:
  No rate-governed stale header begins with `Shared X ago`; a user can tell in one glance that stale rates, not share recency, are the governing problem.
  Confidence: `High`

- Finding ID: `UX-02`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `SCR-06`, `BASE-05`
  Why it matters:
  The multi-namespace list can become status-heavy before the user reaches actual goal rows. The current runtime already groups shared goals per owner namespace, and the proposal adds freshness copy, recovery actions, and sometimes secondary provenance to every namespace header. Without a density cap, the shared-goals list risks turning into stacked status chrome instead of a scannable finance list.
  Recommended fix:
  Add a compactness policy for multi-namespace states: collapse provenance first, restrict header height, and move secondary context to detail when more than one namespace is visible or Dynamic Type is large.
  Acceptance criteria:
  On iPhone 15 with three namespaces, the first goal row remains visible without extra scrolling, and per-namespace freshness chrome does not dominate the first viewport.
  Confidence: `Medium`

- Finding ID: `UX-03`
  Severity: `Medium`
  Evidence IDs: `DOC-01`
  Why it matters:
  The freshness-copy contract is still contradictory across sections. Section 6.4.2 says `checkedNoNewData` is appended to the age-based message and does not replace it, while the concrete header matrix makes `Checked — no newer update yet` the only visible line. The same problem exists for rate-governed `materiallyOutdated`, which earlier names stale rates explicitly but later collapses back to `Last shared 3d ago`.
  Recommended fix:
  Make the concrete header matrix authoritative and align all earlier prose to it. Split publish-governed vs rate-governed `materiallyOutdated`, and define `checkedNoNewData` as a secondary note that never erases the underlying freshness tier.
  Acceptance criteria:
  One canonical freshness matrix remains after revision; `checkedNoNewData` preserves the underlying age tier; rate-governed `materiallyOutdated` always names rate staleness explicitly.
  Confidence: `High`

- Finding ID: `UX-04`
  Severity: `Low`
  Evidence IDs: `DOC-01`
  Why it matters:
  The detail-view contract requires exact local timestamps inline, but it still does not specify locale-aware formatting or a fallback for long strings. Non-English date formats can easily overflow the line budget the proposal is trying to protect.
  Recommended fix:
  Specify locale-aware formatting and define when provenance rows wrap or degrade independently from the rest of the card.
  Acceptance criteria:
  Long-format locales and RTL layouts render both timestamps without truncation or undefined overflow behavior, or degrade according to an explicit rule.
  Confidence: `Low`

### 3.3 iOS Architecture Findings
- Finding ID: `ARCH-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `DOC-02`, `CODE-07`
  Why it matters:
  `contentHash` is still defined only over goal-level canonical data plus rate timing, while the proposal also routes owner display-name and participant changes through `.participantChange`. Because invitee dedup treats matching hashes as a no-op, metadata-only publishes can be dropped even though invitee-visible state changed.
  Recommended fix:
  Define `contentHash` over the full invitee-visible payload, or explicitly split metadata-hash and goal-data-hash semantics so metadata-only changes still produce invitee updates.
  Acceptance criteria:
  Owner display-name changes, participant membership changes, and other invitee-visible root metadata changes always propagate even when goal amounts and rates are unchanged.
  Confidence: `High`

- Finding ID: `ARCH-02`
  Severity: `High`
  Evidence IDs: `DOC-01`
  Why it matters:
  The rate-freshness contract is still internally inconsistent. The owner pipeline says freshness is governed by a 5-minute TTL, but the long-session periodic guard only reevaluates every 15 minutes. That allows the system to exceed its own promised freshness window while remaining in foreground.
  Recommended fix:
  Align long-session reevaluation with the 5-minute TTL, or compute the next refresh from the actual TTL-expiry boundary instead of a fixed 15-minute poll.
  Acceptance criteria:
  In a continuously foregrounded owner session, no namespace exceeds the stated 5-minute TTL without a refresh/evaluation attempt, and tests prove the boundary behavior.
  Confidence: `High`

- Finding ID: `ARCH-03`
  Severity: `High`
  Evidence IDs: `DOC-01`, `CODE-01`, `CODE-07`, `BLOCKER-01`
  Why it matters:
  The ordering/version contract is still self-contradictory and vulnerable to stale semantic regression. Section 6.8.2 introduces `projectionServerTimestamp` while preserving `projectionVersion` as `Int`, but later acceptance tests still say `projectionVersion` is set from `CKRecord.modificationDate`. Combined with the current repo’s local-state payload generation, that leaves room for a lagging owner device to publish an older semantic snapshot that still wins with a newer timestamp or misimplemented version rule.
  Recommended fix:
  Make one canonical ordering contract: keep topology and freshness ordering fully separated, remove contradictory `projectionVersion` wording, and require a stronger semantic barrier than timestamp wins alone when local state may lag behind imported owner truth.
  Acceptance criteria:
  The document has one unambiguous definition for `projectionVersion`, `projectionServerTimestamp`, and migration defaults; two-device race tests prove a stale semantic snapshot cannot replace fresher invitee-visible state.
  Confidence: `Medium`

- Finding ID: `ARCH-04`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `CODE-09`
  Why it matters:
  Dirty/trailing republish durability is still not defined strongly enough. The proposal depends on `dirty-pending` retry and trailing publishes after in-flight completion, but the current coordinator keeps `pendingItems` in memory only, and namespace stores are LRU-evicted with a maximum of two open stores. Without an explicit persisted replay path, crash/relaunch or store eviction can strand the share in stale state until a future unrelated mutation occurs.
  Recommended fix:
  Persist the dirty/republish queue or derive it deterministically from authoritative local state on launch/foreground so relaunch and namespace eviction cannot drop a needed republish.
  Acceptance criteria:
  Killing and relaunching the app between mutation and publish still yields exactly one eventual republish without user intervention; tests cover process death and namespace-store eviction recovery.
  Confidence: `High`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict:
  The proposal wants exact freshness provenance always visible, but it also wants the detail card to collapse under accessibility pressure.
  Tradeoff:
  Always-visible provenance maximizes trust; aggressive collapse protects layout compactness.
  Decision:
  Choose one canonical disclosure rule and define it explicitly for AX sizes instead of allowing both inline and hidden behaviors.
  Owner:
  Proposal author + UX + UI

- Conflict:
  The proposal wants copy that stays compact in list headers, but it also wants rate-governed freshness to remain truthful in one glance.
  Tradeoff:
  Leading with `Shared X ago` is shorter; leading with rate age is more truthful for money values.
  Decision:
  Rate-governed stale states should lead with rate age, with share time demoted to secondary provenance.
  Owner:
  Proposal author + UX + UI

- Conflict:
  The proposal wants simple semantic deduplication, but the live projection contract includes invitee-visible root metadata outside the current hash scope.
  Tradeoff:
  Goal-only hashing is simpler; full invitee-visible payload hashing preserves correctness.
  Decision:
  Expand hash semantics or split metadata/data hashes explicitly; do not let metadata-only publishes vanish.
  Owner:
  Proposal author + iOS architecture

- Conflict:
  The proposal wants local `Int` topology plus server timestamp ordering, but it still leaves room for stale semantic publishes to win.
  Tradeoff:
  Timestamp ordering is simple; semantic ordering is safer under multi-device lag.
  Decision:
  Separate topology, freshness ordering, and semantic freshness explicitly, and fail closed when reconciliation proof is missing.
  Owner:
  Proposal author + iOS architecture

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P0 | Redefine `contentHash` so metadata-only invitee-visible changes cannot be deduplicated away | iOS Architecture | Proposal author + iOS architecture | Now | Existing projection field contract in `FAMILY_SHARING.md` | Owner-name and participant changes always propagate without breaking no-op dedup | `ARCH-01` |
| P0 | Align long-session reevaluation with the stated 5-minute TTL | iOS Architecture | Proposal author + iOS architecture | Now | Owner foreground refresh design | No foreground session exceeds the stated freshness window without reevaluation | `ARCH-02` |
| P0 | Remove contradictory version/timestamp wording and strengthen semantic ordering against stale-device publishes | iOS Architecture | Proposal author + iOS architecture | Now | Multi-device publish contract | Two-device race tests prove stale semantic state cannot replace fresher invitee-visible state | `ARCH-03` |
| P1 | Make one canonical freshness-copy matrix and keep rate-governed staleness truthful at first read | UX + UI | Proposal author + UX + UI | Before implementation | Sections 6.4, 6.6, 8.2 | Engineers cannot derive conflicting list/detail/header copy from different sections | `UX-01`, `UX-03`, `UI-01` |
| P1 | Add proposal-specific visual proof for the new freshness header/card system | UI | Proposal author + UI | Before implementation | Seeded simulator flows and preview infrastructure | Dark mode, large Dynamic Type, and final token rendering are validated for the new UI, not only the current baseline | `UI-02` |
| P2 | Define durable replay rules for `dirty-pending` republish across relaunch and namespace eviction | iOS Architecture | Proposal author + iOS architecture | Pre-build hardening | Queue durability / namespace lifecycle | Relaunch and eviction recovery do not strand stale shared projections | `ARCH-04` |
| P2 | Add a compactness policy for multi-namespace freshness headers and locale-aware timestamp formatting | UX | Proposal author + UX | Pre-build hardening | Final header/card design | Multi-namespace and long-locale scenarios remain scannable without undefined overflow | `UX-02`, `UX-04` |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Metadata dedup correctness | Whether metadata-only publishes still reach invitee UI | Hash diff tests, invitee cache-update tests, participant/owner-name change tests | No invitee-visible root metadata change is lost when goal data is unchanged | Before implementation kickoff | Hold if `contentHash` still ignores invitee-visible root metadata |
| Freshness cadence | Whether owner reevaluation respects the stated 5-minute TTL | Foreground timing tests, scheduler proofs | No namespace exceeds TTL without a refresh/evaluation attempt | Before architecture sign-off | Hold if 15-minute polling remains with a 5-minute promise |
| Copy truthfulness | Whether users can tell what is stale from the primary message alone | Scenario matrix for publish-governed, rate-governed, `checkedNoNewData`, and `refreshFailed` | No rate-governed stale state leads with `Shared X ago` | Before UX sign-off | Hold if Sections 6 and 8 still allow conflicting copy |
| Visual proof | Whether the new list-header/detail-card system survives real AX and appearance constraints | Proposal-specific previews or simulator captures | No clipping, overlap, unreadable tokens, or ambiguous disclosure patterns | Before UI sign-off | Hold if only current-state screenshots exist |
| Multi-device ordering | Whether stale owner devices can regress fresher shared state | Two-device publish/import race tests, reconciliation-barrier tests | No stale semantic publish replaces fresher invitee-visible truth | Before architecture sign-off | Hold if timestamp-only wins remain possible |
| Queue durability | Whether republish survives relaunch and namespace eviction | Crash/relaunch tests, LRU eviction tests | Exactly one eventual republish occurs without user intervention | Before Phase 2 implementation | Hold if `dirty-pending` replay remains undefined |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- `GAP-01`: No live two-owner-device CloudKit publish/import trace was captured in `R6`; multi-device ordering remains validated from code and proposal logic, not runtime replay.
- `GAP-02`: No proposal-specific dark-mode, large-Dynamic-Type, or VoiceOver renders exist yet for the final freshness header/detail-card system.
- `GAP-03`: Fresh simulator captures prove the current runtime baseline only; they do not validate the proposed final UI chrome.

### Open Questions
- `QUESTION-01`: Should `contentHash` cover the full invitee-visible payload, or should the proposal define separate metadata and goal-data hash semantics?
- `QUESTION-02`: Which migration rule is canonical for missing `projectionServerTimestamp`: default to `projectionPublishedAt` or default to `nil`?
- `QUESTION-03`: At the largest supported Dynamic Type size, are exact provenance timestamps still always visible inline, or is a disclosure pattern the intended final behavior?
