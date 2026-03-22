# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `full-review`
- Evidence completeness: `Partial`
- Documents / repo inputs reviewed:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_TRIAD_REVIEW_R3.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/FAMILY_SHARING.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_EVIDENCE_PACK_R4.md`
- External sources reviewed:
  - [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
  - [Apple UI Design Dos and Don’ts](https://developer.apple.com/design/tips/)
  - [W3C WCAG 2.2 Understanding SC 4.1.3 Status Messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages)
- Build/run attempts:
  - `RUN-01`: fresh `xcodebuild` Debug build succeeded on `iPhone 15` simulator, iOS 18.0
  - `RUN-02`: current build installed and launched successfully via `simctl`
- Screenshots captured / reused:
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r2/screenshots/invitee-active-list.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r2/screenshots/invitee-active-detail.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r2/screenshots/invitee-stale-list.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r2/screenshots/invitee-unavailable-list.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r2/screenshots/invitee-empty-list.png`
  - `R4` reused the seeded runtime screenshots because the repeat pass materially changed the proposal, while inspected freshness-sync runtime code paths remained unchanged.
- Code areas inspected:
  - `FamilyShareServices`
  - `FamilyShareCloudKitStore`
  - `FamilyShareRollout`
  - `CloudKitHealthMonitor`
  - `GoalCalculationService`
  - `ExchangeRateService`
  - `PersistenceMutationServices`
  - `FamilySharingSupport`
  - `SharedGoalsSectionView`
- Remaining assumptions:
  - Runtime evidence is simulator-seeded rather than a live owner/invitee CloudKit loop across two devices.
  - This pass evaluates proposal readiness, not implementation completeness.
- Remaining blockers:
  - No live multi-device CloudKit publish/import timing trace for owner-device race behavior.
  - No proposed-state mockups or simulator captures for the new freshness UI, motion, dark mode, large Dynamic Type, or VoiceOver behavior.

## 1. Executive Summary
- Overall readiness: `Red`
- Confidence: `Medium`
- Release blockers:
  - The proposal still assumes that a later owner-device publish is safe because every device rebuilds from the same CloudKit-backed truth, but it does not define a reconciliation barrier that prevents a lagging owner device from publishing a semantically older snapshot with a newer server timestamp.
  - The proposal redefines `projectionVersion` around `CKRecord.modificationDate`, but the live payload/cache/CloudKit schema is still `Int`-based and the migration section still defaults missing versions to numeric `0`. That contract is not internally coherent yet.
- Top risks:
  1. A stale owner device can still win the invitee monotonic check and regress visible financial truth if it publishes later from lagging local state.
  2. The document now mixes `Date`-based ordering semantics with an `Int`-based live schema and atomic publish topology, which can break migration and rollback safety.
  3. The UI/UX contract is much better, but the compact surface still lacks proposed-state proof and the freshness copy can still misstate what is actually stale when rate age governs.
- Top opportunities:
  1. The prior `R3` blockers are materially closed: per-namespace freshness ownership, stale-cause substates, detail provenance, executor composition, clock/skew rules, rollout boundaries, and test seams are now explicit.
  2. The remaining risk has narrowed sharply into architecture correctness and a smaller number of trust-level UX details.
  3. Once the publish-source-of-truth and version-schema contracts are fixed, the document will be much closer to implementation-ready than any previous revision.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | `Amber` | `Medium` | `Partial` | 0 | 0 | 2 | 0 |
| UX | `Amber` | `Medium` | `Partial` | 0 | 2 | 1 | 0 |
| iOS Architecture | `Red` | `Medium` | `Partial` | 1 | 1 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Findings
- Finding ID: `UI-01`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `SCR-01`, `SCR-03`, `CODE-07`, `WEB-01`, `WEB-02`, `BLOCKER-02`
  Why it matters:
  The proposal now adds freshness tier, stale-cause substate, recovery action, and optional rate-age detail to each namespace header while still requiring a compact first viewport. The rules are much better than `R3`, but they are still a layout ruleset rather than a locked visual composition. Without proposed-state captures, long owner names plus warning copy plus actions can still crowd the first visible scan line and compete with row hierarchy.
  Recommended fix:
  Add one concrete header matrix for `active`, `stale`, `materiallyOutdated`, and `temporarilyUnavailable`. Keep `active` and `recentlyStale` as inline text-first states; reserve card/banner escalation for unavailable or terminal states; force secondary rate-age detail to detail-only whenever an action is present or large text is active.
  Acceptance criteria:
  Proposed-state previews or screenshots exist for iPhone 15 width, largest supported Dynamic Type, long owner-name cases, and all major freshness tiers; first row remains immediately visible and tappable; the header never renders both action and secondary rate-age detail at once.
  Confidence: `Medium`

- Finding ID: `UI-02`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `SCR-02`, `BASE-01`, `WEB-02`, `BLOCKER-02`
  Why it matters:
  The detail contract now requires the same primary freshness line plus two provenance rows with relative and exact timestamps inline. That improves trust semantics, but without visual proof it still risks making provenance the dominant visual block and weakening amount-first hierarchy on a compact finance detail view.
  Recommended fix:
  Lock provenance into a dedicated `Freshness` card below the primary financial summary, with relative time as the first read and exact timestamps in secondary text on their own lines.
  Acceptance criteria:
  Proposed-state detail captures show `Current` / `Target` remaining first-scan dominant; provenance fits at largest supported Dynamic Type without truncation or overlap; exact timestamps remain visible without pushing core financial metrics below the fold unnecessarily.
  Confidence: `Medium`

### 3.2 UX Findings
- Finding ID: `UX-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `BLOCKER-02`
  Why it matters:
  The proposal drives the list’s primary freshness line from composite age, but the example grammar still reads like a single “Updated/Last updated X ago” timestamp. When rate age, not publish age, is the governing dependency, that copy can still mislead the user about what is stale: the owner may have shared 5 minutes ago while the numbers are based on 6-hour-old rates.
  Recommended fix:
  Split primary grammar by governing dependency. If publish age governs, use share-time copy such as “Shared 5 min ago.” If rate age governs, make rate staleness explicit in the primary line and preserve actual share time as secondary provenance.
  Acceptance criteria:
  In a `projectionPublishedAt=5m` / `rateSnapshotTimestamp=6h` case, the list never renders only “Updated 6h ago”; it explicitly names rate-age staleness and preserves actual share time even in compact layouts.
  Confidence: `High`

- Finding ID: `UX-02`
  Severity: `High`
  Evidence IDs: `DOC-01`, `BASE-02`, `BLOCKER-01`
  Why it matters:
  The recovery model still does not clearly tell the invitee whether retrying can actually help. In `v1`, owner-absent staleness is a known limitation, and a manual refresh can succeed technically while returning no newer projection. The current CTA set still conflates “fetch failed,” “no newer shared update exists,” and “rates are old,” which makes the surface feel arbitrary.
  Recommended fix:
  Add a successful-but-no-new-data outcome and map CTA language to cause. Reserve `Try Again` for actual fetch failures; introduce a non-error “checked, no newer shared update yet” state with last-checked time when refresh succeeds but nothing newer exists.
  Acceptance criteria:
  After a manual refresh with no newer projection, the UI shows a distinct non-error state with last-checked time; after a failed fetch it shows failure-specific copy; users can tell whether another retry is meaningful.
  Confidence: `High`

- Finding ID: `UX-03`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `BASE-03`, `BASE-04`, `BLOCKER-02`
  Why it matters:
  `removedOrNoLongerShared` is now defined at the token/icon/string level, but the proposal still does not fully specify whether cached financial rows disappear immediately, whether the orphaned namespace is dismissible, or whether detail navigation remains possible after revocation. Leaving revoked financial values on-screen is a trust and privacy risk.
  Recommended fix:
  Add a terminal-state contract for removed/revoked namespaces: remove financial rows, replace them with a non-retry explanatory state, block navigation into revoked data, and provide a dismiss/remove affordance.
  Acceptance criteria:
  When a share is revoked, no outdated financial amounts remain visible; the list shows a clear terminal state; the user can dismiss the orphaned namespace.
  Confidence: `Medium`

### 3.3 iOS Architecture Findings
- Finding ID: `ARCH-01`
  Severity: `Critical`
  Evidence IDs: `DOC-01`, `DOC-03`, `CODE-09`, `BASE-05`
  Why it matters:
  Section 6.8 still assumes last-writer-wins is safe because every owner device rebuilds from the same CloudKit-backed truth. The live repo evidence does not support that assumption: publish payloads are rebuilt from local `Goal` state, and CloudKit sync events are observed outside the family-sharing publish path. A lagging owner device can therefore publish an older semantic snapshot after a fresher device, receive a newer server timestamp, and the invitee monotonic check will prefer the stale payload. For a financial trust surface, that is a release blocker.
  Recommended fix:
  Add an explicit pre-publish reconciliation barrier. The coordinator must only publish from a local snapshot proven to have imported the required CloudKit changes, or it must fetch canonical owner truth from the authoritative store before publish. If that barrier is not satisfied, keep the namespace dirty and suppress publish.
  Acceptance criteria:
  The proposal names the barrier source of truth, defines behavior for stale-device, offline-drain, and concurrent-device cases, and includes tests proving a lagging owner device cannot regress invitee-visible state.
  Confidence: `Medium`

- Finding ID: `ARCH-02`
  Severity: `High`
  Evidence IDs: `DOC-01`, `DOC-03`, `CODE-08`, `BASE-05`
  Why it matters:
  The live contract stores `projectionVersion` and `activeProjectionVersion` as `Int` / `Int64`, and atomic publish depends on writing child records under the next version before flipping `activeProjectionVersion`. The proposal redefines `projectionVersion` as `CKRecord.modificationDate`, but still migrates missing versions to numeric `0` and never explains how a post-write server timestamp participates in the existing atomic publish topology. As written, the version contract is internally inconsistent and not compatible with the current payload/cache/CloudKit schema.
  Recommended fix:
  Separate concerns. Keep an explicit preallocated atomic publish token for record topology, and use a separate server-assigned timestamp field for freshness/ordering, or document a full two-phase publish design that preserves atomicity. Add an explicit schema migration matrix for payload, cache, and CloudKit fields.
  Acceptance criteria:
  The proposal resolves `Int` vs `Date` semantics, defines field-level migration and rollback behavior, and proves upgrade safety from the live schema with tests for mixed-version caches and monotonic invitee comparison.
  Confidence: `High`

- Finding ID: `ARCH-03`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `DOC-03`, `CODE-04`, `CODE-05`
  Why it matters:
  The proposal now states that one serialized coordinator should own all publish-triggering actions, but the ingress map is still incomplete relative to the live system. Current repo triggers include share lifecycle and participant transitions, owner display-name changes, and legacy refresh paths; the proposal’s observer boundary is focused on mutation/rate/import events and a few manual refresh cases. Any missed ingress leaves split ownership alive and breaks the coalescing/backoff/telemetry guarantees the design depends on.
  Recommended fix:
  Add an explicit trigger-inventory table mapping every current publish trigger to one coordinator event path, and make `FamilyShareProjectionPublishCoordinator` callable only from the namespace actor/coordinator boundary.
  Acceptance criteria:
  The proposal covers all current triggers from `FAMILY_SHARING.md`, documents deprecated direct callers, and includes tests proving share lifecycle, participant changes, owner identity updates, and manual re-share all route through the same serialized path.
  Confidence: `High`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict:
  The proposal wants a compact, trustworthy freshness line, but composite age can mean “recent share, stale rates,” which a plain “Updated X ago” sentence still misrepresents.
  Tradeoff:
  One generic age grammar is simpler; dependency-specific freshness grammar is more truthful.
  Decision:
  Split primary freshness grammar by governing dependency and preserve share time as secondary provenance when rate age governs.
  Owner:
  Proposal author + UX + UI

- Conflict:
  The proposal wants server-derived monotonic ordering, but the live system still uses an `Int`-based atomic publish contract and local rebuilds from owner-device state.
  Tradeoff:
  Reusing `CKRecord.modificationDate` looks simple; a schema-safe atomic publish token plus separate freshness/order timestamp is safer.
  Decision:
  Separate topology/version token from freshness/order timestamp, or fully specify a two-phase migration that preserves atomicity and rollback safety.
  Owner:
  Proposal author + iOS architecture

- Conflict:
  The proposal centralizes publish ownership, but the live repo still has several existing triggers and legacy paths outside the currently documented observer set.
  Tradeoff:
  A smaller ingress map is simpler to describe; a full trigger inventory is needed for implementation safety.
  Decision:
  Add one authoritative trigger-inventory table and deprecate all direct publish callers outside the namespace actor boundary.
  Owner:
  Proposal author + iOS architecture

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P0 | Add a pre-publish reconciliation barrier that prevents lagging owner devices from publishing semantically older snapshots | iOS Architecture | Proposal author + iOS architecture | Now | Current owner CloudKit-backed store and family-sharing publish path | A stale owner device can no longer win invitee ordering with older semantic data | `ARCH-01` |
| P0 | Resolve the `projectionVersion` contract by separating atomic publish token from freshness/order timestamp, or specify a safe full migration | iOS Architecture | Proposal author + iOS architecture | Now | Current `Int` payload/cache/CloudKit schema | No `Int`/`Date` ambiguity remains and upgrade safety is explicitly proven | `ARCH-02` |
| P1 | Add a complete publish-trigger inventory covering share lifecycle, participant changes, owner identity updates, and legacy paths | iOS Architecture | Proposal author + iOS architecture | Before implementation | Existing family-sharing trigger surface | All publish triggers route through one serialized path | `ARCH-03` |
| P1 | Split freshness grammar by governing dependency and add a “checked, no newer update yet” outcome | UX | Proposal author + UX | Before UI implementation | Current composite-age copy examples | Users can distinguish stale rates, stale publish age, failed fetch, and successful-but-no-new-data outcomes | `UX-01`, `UX-02` |
| P2 | Lock concrete namespace-header and detail-provenance visual compositions with proposed-state captures | UI | Proposal author + UI | Pre-implementation | Existing compact-layout and provenance rules | UI hierarchy is visually proven for light/dark, large Dynamic Type, and long owner names | `UI-01`, `UI-02` |
| P2 | Define terminal removed/revoked namespace behavior | UX | Proposal author + UX | Pre-implementation | Existing removed token/copy contract | Revoked data never remains navigable or visibly stale in-place | `UX-03` |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Owner-device reconciliation safety | Whether a lagging owner device can publish a semantically older projection | Multi-device publish/import sequence tests, sync-barrier design proof | Invitee never regresses to older semantic state because of later stale-device publish | Before implementation kickoff | Hold if the proposal still assumes “same CloudKit-backed truth” without a reconciliation barrier |
| Version/schema contract | Whether the new ordering model is compatible with live payload/cache/CloudKit schema | Migration matrix, mixed-schema tests, topology diagram | No ambiguity remains between `Int` and `Date` semantics; atomic publish still works | End of design Phase 0 | Hold if `projectionVersion` remains overloaded for both topology and ordering |
| Publish ingress ownership | Whether every current publish trigger routes through one serialized path | Trigger-inventory table, deprecated direct caller list, coordinator boundary tests | No publish path bypasses namespace actor/coordinator ownership | Before implementation kickoff | Hold if share lifecycle/manual re-share/legacy refresh still have undocumented bypasses |
| Freshness copy semantics | Whether users can tell what is stale and whether retry helps | Copy table, scenario matrix, no-new-update outcome design | List copy never misstates rate-driven staleness; retry actions never imply unavailable recovery when none exists | Before UX sign-off | Hold if the primary freshness line still reads as one generic timestamp for all cases |
| Visual composition | Whether compact namespace headers and detail provenance remain readable and native-looking | Proposed-state captures for light/dark, large Dynamic Type, motion, VoiceOver | No overlap, no hidden first row, no provenance dominance over money metrics | Before visual sign-off | Hold if visual composition remains rules-only and unproven |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- `GAP-01`: No live two-owner-device CloudKit publish/import traces were captured in `R4`, so the multi-device correctness finding remains architecture-backed, not runtime-proven.
- `GAP-02`: No proposed-state mockups or simulator captures exist yet for the new freshness headers, motion transitions, detail provenance layout, dark mode, large Dynamic Type, or VoiceOver behavior.
- `GAP-03`: `R4` still reuses `R2` seeded screenshots for baseline runtime evidence, so current visual-baseline confidence remains `Medium`.

### Open Questions
- `QUESTION-01`: Will the final design keep one explicit atomic publish token and add a separate server timestamp field, or fully migrate the topology/version contract away from the current `Int` schema?
- `QUESTION-02`: What concrete reconciliation barrier proves an owner device has imported the required upstream state before it is allowed to republish?
