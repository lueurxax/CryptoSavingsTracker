# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `full-review`
- Evidence completeness: `Partial`
- Documents / repo inputs reviewed:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_TRIAD_REVIEW_R2.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/FAMILY_SHARING.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_EVIDENCE_PACK_R3.md`
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
  - `R3` reused the `R2` seeded runtime screenshots because the repeat pass materially changed the proposal, while inspected freshness-sync runtime code paths did not materially change.
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
  - This pass evaluates proposal readiness, not implementation completeness.
- Remaining blockers:
  - No live multi-device CloudKit timing or push-delivery proof.
  - No proposed-state mockups or simulator captures for composite freshness labels, dark mode, large Dynamic Type, VoiceOver, or transition behavior.

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `Medium`
- Release blockers:
  - The proposal still does not explicitly define freshness ownership at the namespace/section level, even though the live product groups invitee data per owner namespace.
  - The new auto-republish design still does not specify one authoritative per-namespace executor and one globally monotonic version-allocation contract across owner devices.
- Top risks:
  1. A single visible freshness line can still misstate mixed-freshness shared datasets unless the document explicitly binds freshness semantics to namespace-group boundaries.
  2. Multi-device owner publishes can still race or regress invitee truth if `projectionVersion` remains locally inferred rather than authoritatively allocated.
  3. Operability is still underdefined: rollout disable, timer teardown, push quiescing, offline drain, and time-skew handling are not yet written as one rollback-safe contract.
- Top opportunities:
  1. The prior `R2` blockers are materially closed: composite freshness authority, non-USD materiality policy, sendable calculator inputs, and unavailable/removed token semantics are now explicitly documented.
  2. The proposal is now much closer to implementation-ready than `R2`; remaining issues are mostly distributed-systems and compact-state contract details, not baseline freshness wording.
  3. The test plan is stronger, but it can still become implementation-safe with explicit clock/scheduler seams and clearer stale-cause semantics.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | `Amber` | `Medium` | `Partial` | 0 | 0 | 2 | 0 |
| UX | `Amber` | `Medium` | `Partial` | 0 | 2 | 1 | 1 |
| iOS Architecture | `Amber` | `Medium` | `Partial` | 0 | 2 | 3 | 0 |

## 3. Findings by Discipline

### 3.1 UI Findings
- Finding ID: `UI-01`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `SCR-01`, `SCR-03`, `BASE-01`, `BASE-02`, `WEB-01`, `WEB-02`, `BLOCKER-02`
  Why it matters:
  The proposal now correctly limits the list to one primary freshness message, but the compact header composition is still under-specified. The baseline already has owner grouping, row chips, and recovery states, while the new design adds primary freshness copy, optional secondary rate-age detail, and retry actions. Without an explicit collapse order, crowded iPhone-width implementations are still plausible.
  Recommended fix:
  Add a compact-layout contract for the invitee header. Primary freshness copy must always win; secondary rate-age detail must collapse or move behind the detail/info affordance before row truncation; recovery action placement must be fixed and mutually exclusive with secondary detail.
  Acceptance criteria:
  On iPhone 15 width at the largest supported Dynamic Type size, the list shows the title plus exactly one primary freshness line with no overlap or stacked status copy, row content remains immediately scannable, and stale/unavailable actions stay tappable without competing with row hierarchy.
  Confidence: `Medium`

- Finding ID: `UI-02`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `WEB-01`, `WEB-03`, `BLOCKER-02`
  Why it matters:
  The proposal says refresh updates in place and silent updates must not steal VoiceOver focus, but it still does not define how freshness-tier changes, value refreshes, or unavailable-to-recovered transitions animate. In a finance UI, ad hoc list diffing or banner motion can read as flicker and reduce trust when values change silently.
  Recommended fix:
  Add a minimal motion contract: preserve row order and scroll position, use a subtle content transition for freshness-label changes, avoid success-banner choreography on silent refresh, use one native transition for unavailable recovery, and honor `Reduce Motion` by removing nonessential animation.
  Acceptance criteria:
  Silent refresh changes freshness and values without scroll jump, focus loss, or double announcement; `Reduce Motion` suppresses nonessential motion; UI tests cover `active -> stale`, `stale -> active`, and `temporarilyUnavailable -> recovered`.
  Confidence: `Medium`

### 3.2 UX Findings
- Finding ID: `UX-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `SCR-01`, `BASE-01`
  Why it matters:
  The live product is namespace-grouped, but the proposal still reads as if one visible `Shared with You` freshness line can describe the whole shared surface. In a mixed-owner or mixed-freshness scenario, that can misstate which rows are stale and directly undermine financial trust.
  Recommended fix:
  Define freshness ownership explicitly at the namespace/owner-group level, or define an aggregate pattern that cannot imply uniform freshness across all shared datasets.
  Acceptance criteria:
  With two shared groups at different freshness tiers, users can identify which rows are stale without opening detail, and no single header implies all rows share the same freshness.
  Confidence: `High`

- Finding ID: `UX-02`
  Severity: `High`
  Evidence IDs: `DOC-01`, `SCR-03`, `BASE-02`
  Why it matters:
  The proposal says invitees should understand whether staleness comes from a technical issue or from the owner not having opened the app, but the final UX contract still resolves to age-based copy plus a generic retry action for stale cached data. That leaves the user unable to tell whether refresh is currently failing, whether the app is simply waiting for a newer publish, or whether retry can help.
  Recommended fix:
  Add explicit stale-cause and recovery substates for `checking`, `couldn’t refresh`, `showing last shared update`, and cooldown or in-flight retry states, while keeping owner-blame out of copy.
  Acceptance criteria:
  Cached stale data clearly distinguishes “latest available data is old” from “we could not fetch the latest data,” and the retry control has defined in-flight and cooldown feedback.
  Confidence: `Medium`

- Finding ID: `UX-03`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `SCR-02`, `BASE-01`
  Why it matters:
  The provenance contract is still internally ambiguous: the proposal promises richer timestamp detail, then later specifies relative times for both detail timestamps. In a finance surface, that ambiguity risks regressing from the current absolute `Updated` timestamp baseline and weakens support/debug trust.
  Recommended fix:
  Make the detail provenance contract explicit: relative time may stay primary, but exact local publish and rate-snapshot timestamps must remain visible or one tap away.
  Acceptance criteria:
  The document specifies one exact detail pattern for both timestamps, and users/support can verify precise last publish and rate snapshot times without inference.
  Confidence: `High`

- Finding ID: `UX-04`
  Severity: `Low`
  Evidence IDs: `SCR-05`, `BASE-04`, `DOC-01`
  Why it matters:
  The proposal defines stale, unavailable, and removed states, but it does not explicitly state how the existing empty/no-shares state participates in freshness precedence. That creates regression risk for users who have no current shares.
  Recommended fix:
  Add an explicit `empty/noSharedGoals` state and a precedence rule that suppresses freshness messaging unless at least one shared dataset exists.
  Acceptance criteria:
  When no shares exist, the UI shows only the empty-state explanation and never a stale/unavailable freshness label unless there is an actual fetch failure.
  Confidence: `High`

### 3.3 iOS Architecture Findings
- Finding ID: `ARCH-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `DOC-03`, `CODE-05`, `BASE-05`
  Why it matters:
  The proposal declares `FamilyShareProjectionAutoRepublishCoordinator` the sole serialized owner, but the live baseline already has per-namespace serialization and atomic publish ownership, and still exposes a direct legacy refresh path. The document does not yet state whether the new coordinator lives inside `FamilyShareNamespaceActor`, replaces `FamilyShareProjectionPublishCoordinator`, or delegates into the existing outbox and atomic publish path. That leaves split-ownership risk over dirty state, version allocation, and CloudKit writes.
  Recommended fix:
  Amend Sections 6.1, 7.1, and Phase 0 to name one authoritative per-namespace executor and state exactly how it composes with `FamilyShareNamespaceActor`, `FamilyShareProjectionPublishCoordinator`, and legacy/manual refresh entry points.
  Acceptance criteria:
  The design shows one per-namespace execution owner for accept, refresh, revoke, publish, and republish; manual and legacy refresh cannot publish except through that owner; atomic publish/outbox semantics remain intact after the refactor.
  Confidence: `High`

- Finding ID: `ARCH-02`
  Severity: `High`
  Evidence IDs: `DOC-01`, `DOC-03`
  Why it matters:
  Multi-device coordination now requires monotonic invitee version checks, but the proposal still does not define how `projectionVersion` becomes globally monotonic across owner devices. If versioning stays locally inferred, a stale owner device can still mint an equal or older version and conflict with invitee monotonic-reject logic.
  Recommended fix:
  Add an explicit authoritative version-allocation contract, preferably server-backed at the atomic publish step rather than derived from local cache state.
  Acceptance criteria:
  Two owner devices with divergent local caches cannot collide on version numbers, regress invitee-visible state, or strand a newer payload behind an older `activeProjectionVersion`; tests cover stale-device, equal-version, and concurrent-publish cases.
  Confidence: `Medium`

- Finding ID: `ARCH-03`
  Severity: `Medium`
  Evidence IDs: `DOC-01`
  Why it matters:
  The composite freshness model is semantically improved, but the document still does not define the canonical clock source for `projectionPublishedAt` and `rateSnapshotTimestamp`, or how future timestamps and owner/invitee clock skew are handled. Bad device time can make stale data look fresh or vice versa.
  Recommended fix:
  Specify freshness time provenance explicitly. Prefer a server-aligned publish timestamp, define skew tolerance or clamping for future timestamps, and add telemetry for anomalous skew rather than silently trusting device clocks.
  Acceptance criteria:
  The spec names the canonical time source, defines future-timestamp handling, and covers owner-fast, owner-slow, and invitee-skew test cases without ever showing a false `active` state.
  Confidence: `Medium`

- Finding ID: `ARCH-04`
  Severity: `Medium`
  Evidence IDs: `DOC-01`
  Why it matters:
  The proposal defines many time-based behaviors and expects deterministic coverage, but it still does not introduce clock, scheduler, or failure-injection seams for publish, refresh, and backoff. That makes the required debounce, cooldown, threshold, periodic-check, and retry tests hard to implement without flaky sleeps.
  Recommended fix:
  Add injected `Clock`/`DateProvider`, scheduler, publish transport, and rate-refresh interfaces to the coordinator, evaluator, and invitee scheduler contracts.
  Acceptance criteria:
  Time-based tests run against virtual time, not real sleeps; publish/rate-refresh failures can be injected deterministically; backoff and cooldown behavior is unit-testable without simulator timing.
  Confidence: `High`

- Finding ID: `ARCH-05`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `CODE-06`, `BASE-05`
  Why it matters:
  The repo already has rollout fail-closed behavior at the CloudKit boundary, but the proposal’s new observers, timers, periodic rate checks, push handlers, and offline queue are not explicitly tied to the same rollback contract. With only store-level gating, rollback can still leave local dirty-state churn, timer activity, or misleading UI and telemetry side effects.
  Recommended fix:
  Add a rollout/rollback boundary section stating that rollout is checked at event ingress, scheduler activation, publish execution, push handling, and offline queue drain, and that disable tears down subscriptions/timers and stabilizes cached UI state.
  Acceptance criteria:
  A flag-off scenario proves no observer enqueue, no timer or push refresh, no publish attempt, and stable cached invitee behavior after rollback.
  Confidence: `High`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict:
  The proposal optimizes for one compact freshness line, but the live invitee model is namespace-grouped and may carry different freshness states at the same time.
  Tradeoff:
  One shared line is simpler to scan; namespace-level freshness is more truthful.
  Decision:
  Bind freshness ownership explicitly to namespace/owner sections, or define an aggregate pattern that cannot imply uniform freshness across all shared datasets.
  Owner:
  Proposal author + UX + iOS architecture

- Conflict:
  The proposal introduces a new serialized coordinator, while the repo already has namespace actors, atomic publish semantics, rollout gating, and a legacy refresh path.
  Tradeoff:
  A cleaner new coordinator is appealing; parallel ownership paths are unsafe.
  Decision:
  Name one authoritative per-namespace executor, define how it composes with the existing publish path, and tie it to the same rollback contract.
  Owner:
  Proposal author + iOS architecture

- Conflict:
  The list wants compact, user-friendly age copy, while users/support still need precise provenance and actionable recovery semantics.
  Tradeoff:
  Minimal copy reduces clutter; precise provenance and stale-cause detail increase trust.
  Decision:
  Keep one compact primary freshness line on list, but define exact detail provenance and explicit stale/retry substates.
  Owner:
  UX + UI + iOS architecture

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P0 | Define freshness ownership explicitly at the namespace/owner-section level and remove any implication that one line describes all shared datasets | UX / iOS Architecture | Proposal author | Now | Current shared-goals section model | Mixed-freshness shared groups are unambiguous on the list surface | `UX-01` |
| P0 | Specify one authoritative per-namespace executor and one globally monotonic version-allocation contract | iOS Architecture | Proposal author + iOS architecture | Now | Existing namespace actor and publish path | No split ownership remains over dirty state, publish execution, or versioning | `ARCH-01`, `ARCH-02` |
| P1 | Add stale-cause and retry substates, including in-flight/cooldown semantics | UX | Proposal author + UX | Before implementation | Current stale/unavailable state model | Users can tell whether retry can help and whether the dataset is merely old or currently unreachable | `UX-02` |
| P1 | Define rollout/rollback boundary, canonical time source, and test seams for time-based behavior | iOS Architecture | Proposal author + iOS architecture | Before implementation | Existing rollout gating and telemetry model | Rollback is quiescent, skew-safe, and deterministic to test | `ARCH-03`, `ARCH-04`, `ARCH-05` |
| P2 | Add compact-layout rules, motion contract, and proposed-state visuals for light/dark, large Dynamic Type, and VoiceOver | UI | Proposal author + UI | Pre-implementation | Current compact list hierarchy | Header remains readable and transitions remain trustworthy in all supported states | `UI-01`, `UI-02` |
| P2 | Clarify detail provenance format and empty-state freshness precedence | UX | Proposal author + UX | Pre-implementation | Existing detail timestamp baseline | Detail view remains supportable and empty state never inherits misleading freshness chrome | `UX-03`, `UX-04` |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Freshness ownership | Which dataset each visible freshness line describes | Multi-namespace screenshots/tests show distinct freshness at section level | No single visible label implies all shared groups share one freshness state | Before implementation kickoff | Hold if mixed-freshness scenarios are still semantically ambiguous |
| Publish ownership and versioning | Single executor behavior and monotonic projection versions across devices | Concurrent-publish tests, stale-device tests, outbox sequencing proofs | No equal-version collision or invitee regression under multi-device owner races | End of design Phase 0 | Hold if authoritative version allocation is still unspecified |
| Stale-cause recovery UX | User understanding of “old data” vs “refresh failed” vs “checking” | State diagrams, copy table, retry/cooldown behavior tests | Retry never promises impossible recovery and never blames the owner | Before UI implementation | Hold if stale and failed-refresh remain collapsed into one generic retry message |
| Rollout and time correctness | Kill-switch behavior, time provenance, and clock-skew handling | Flag-off tests, future-timestamp/skew tests, quiescing checks | No observer/timer/push churn when rollout is disabled; no false `active` from skew | Before implementation kickoff | Hold if rollback-safe ingress and canonical time source are not documented |
| Compact accessibility behavior | Large Dynamic Type, VoiceOver, and Reduce Motion quality | Proposed-state mockups or simulator captures, UI/accessibility tests | No overlap, no stacked status noise, no focus theft on silent refresh | Before visual sign-off | Hold if compact-header and transition rules remain implicit |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- `GAP-01`: No live multi-device CloudKit publish/fetch or push-delivery evidence was captured in `R3`, so SLA, monotonic versioning, and skew behavior remain proposal-only.
- `GAP-02`: No proposed-state mockups or simulator captures exist yet for the new freshness labels, light/dark mode, largest supported Dynamic Type, VoiceOver, or silent-refresh transitions.
- `GAP-03`: `R3` reused the `R2` seeded screenshots because the repeat pass focused on proposal changes; current visual-baseline confidence is therefore `Medium`, not `High`.

### Open Questions
- `QUESTION-01`: Should the visible freshness line live on each namespace/owner section header, or is there an approved aggregate pattern for mixed-freshness shared datasets?
- `QUESTION-02`: For detail provenance, should exact timestamps always be visible inline, or available behind a single info affordance while relative time remains primary?
