# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `full-review`
- Evidence completeness: `Complete`
- Documents / repo inputs reviewed:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/FAMILY_SHARING.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_EVIDENCE_PACK_R1.md`
- External sources reviewed:
  - [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
  - [Apple UI Design Dos and Don’ts](https://developer.apple.com/design/tips/)
  - [W3C WCAG 2.2 Understanding SC 4.1.3 Status Messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages)
- Build/run attempts:
  - `RUN-01`: initial `xcodebuild` destination failure on named simulator
  - `RUN-02`: successful Debug build, install, launch, and seeded runtime capture on `iPhone 15` simulator, iOS 18.0
- Screenshots captured:
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync/screenshots/invitee-active-list.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync/screenshots/invitee-active-detail.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync/screenshots/invitee-stale-list.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync/screenshots/invitee-unavailable-list.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync/screenshots/invitee-empty-list.png`
- Code areas inspected:
  - `FamilyShareServices`
  - `FamilyShareCloudKitStore`
  - `FamilySharingModels`
  - `SharedGoalsSectionView`
  - `SharedGoalRowView`
  - `ContentView`
  - `GoalCalculationService`
  - `PersistenceMutationServices`
  - `ExchangeRateService`
  - `FamilyShareTestSeeder`
  - `FamilySharingUITests`
- Remaining assumptions:
  - Simulator evidence reflects deterministic seeded invitee states, not a live owner/invitee CloudKit loop across two physical devices.
  - v2 push behavior was reviewed as proposal scope only, not runtime behavior.
- Remaining blockers:
  - No live multi-device CloudKit timing proof.
  - No dark-mode / large Dynamic Type evidence for the proposed new freshness surfaces.

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `Medium`
- Release blockers:
  - The proposal does not yet define a single serialized owner for the new refresh/publish event graph.
  - The proposal relies on `GoalCalculationService` without first locking a pure non-UI money-calculation boundary.
  - The proposal adds new freshness metadata and tiers without a concrete cache/schema migration contract.
- Top risks:
  1. The proposal can still ship a technically fragmented freshness pipeline even though the UX direction is correct.
  2. The user-facing trust signal can still mislead if `projectionPublishedAt` looks fresh while `rateSnapshotTimestamp` is already stale.
  3. The compact `Shared with You` surface can become visually noisy if freshness tiers, rate age, and recovery banners all render without precedence rules.
- Top opportunities:
  1. The proposal correctly targets a confirmed live correctness bug: shared projections still publish baked-in `goal.manualTotal` values instead of allocation-aware calculated totals.
  2. The app already has working active/stale/unavailable invitee states, so implementation can evolve a real runtime contract instead of inventing an entirely new surface.
  3. The v1/v2 split is sensible: automatic republish plus pull refresh first, push subscriptions later.

## 2. Discipline Scorecard
| Discipline | Readiness | Confidence | Evidence Completeness | Critical | High | Medium | Low |
|---|---|---|---|---:|---:|---:|---:|
| UI | `Amber` | `Medium` | `Partial` | 0 | 0 | 2 | 0 |
| UX | `Amber` | `Medium` | `Partial` | 0 | 1 | 2 | 0 |
| iOS Architecture | `Amber` | `Medium` | `Partial` | 0 | 2 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Findings
- Finding ID: `UI-01`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `DOC-02`, `CODE-06`, `SCR-01`, `SCR-03`
  Why it matters:
  The proposal adds `Updated {time}`, optional `Rates from {time}`, and tiered stale/unavailable copy to a section that is already compact and owner-grouped. Without explicit precedence, truncation, and collapse rules, the current list surface can become crowded and harder to scan on compact widths or larger text.
  Recommended fix:
  Define one primary freshness line for the section, one optional secondary rate-age label only when materially relevant, and explicit rules for when warning copy replaces rather than supplements the header.
  Acceptance criteria:
  At iPhone 15 width and the largest supported Dynamic Type size, the section renders without overlap or truncation, exactly one primary freshness message is visible per state, and primary shared-goal rows remain immediately scannable.
  Confidence: `Medium`

- Finding ID: `UI-02`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `DOC-02`, `WEB-01`, `WEB-02`, `WEB-03`
  Why it matters:
  Terms like `warning tone` and `prominent warning` are still design intent, not a concrete UI contract. Without named semantic tokens, iconography, and accessibility behavior, the implementation can drift into ad hoc color use, weak contrast, or overly noisy status updates during silent refresh.
  Recommended fix:
  Add named semantic tokens for informational, warning, and critical freshness states; pair them with a single icon/text pattern; and specify VoiceOver behavior for non-focus-changing status updates.
  Acceptance criteria:
  Each freshness tier maps to a documented token, passes contrast in supported appearances, and silent refresh announcements do not steal focus or double-announce.
  Confidence: `Medium`

### 3.2 UX Findings
- Finding ID: `UX-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `DOC-02`, `CODE-01`, `SCR-02`
  Why it matters:
  The proposal treats `projectionPublishedAt` as the primary freshness signal and `rateSnapshotTimestamp` as a secondary indicator, but in this product rate age is what determines whether the money values are still trustworthy. A surface can read as “Updated 5 min ago” while still showing materially stale rate-based progress, which is a trust failure for a finance workflow.
  Recommended fix:
  Make freshness a composite trust state rather than two independent time labels. When publish age and rate age diverge past threshold, expose both, and let the older dependency govern the primary warning state.
  Acceptance criteria:
  Every invitee surface answers both “when was this published?” and “how old are the rates?” at a glance, and no screen remains in a normal/active trust state when rate age is already in warning territory.
  Confidence: `Medium`

- Finding ID: `UX-02`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `CODE-06`, `SCR-01`, `SCR-03`
  Why it matters:
  The proposal introduces four visible age tiers plus rate-age warnings on top of existing unavailable and removed states. In the current compact list-first surface, this many visible distinctions can increase cognitive load and make the user decode taxonomy instead of simply deciding whether the numbers are safe to trust.
  Recommended fix:
  Keep the internal thresholds, but compress the visible UX to one primary freshness indicator and one optional secondary detail. Put richer state explanation behind the detail view or a lightweight info affordance.
  Acceptance criteria:
  In the list view, a user can determine trustworthiness at a glance without reading more than one primary freshness message and one recovery action.
  Confidence: `Medium`

- Finding ID: `UX-03`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `SCR-02`, `QUESTION-02`
  Why it matters:
  The current detail view uses an absolute update timestamp, while the proposal only locks relative freshness in the section header. If list and detail keep different timestamp grammars, the same data can look inconsistently described depending on navigation path, which creates support and user confusion.
  Recommended fix:
  Define one canonical freshness string model and reuse it across list and detail. Surfaces can vary in density, but not in timestamp meaning.
  Acceptance criteria:
  List and detail both use the same freshness basis and the same trust semantics, even if one surface shows more detail than the other.
  Confidence: `Medium`

### 3.3 iOS Architecture Findings
- Finding ID: `ARCH-01`
  Severity: `High`
  Evidence IDs: `DOC-01`, `CODE-03`, `CODE-04`, `CODE-07`
  Why it matters:
  The proposal adds a notification-driven graph across rate refresh, mutation observation, dirty events, automatic republish, and invitee refresh, but it still does not define one serialized owner for that graph. Current code already mixes service notifications with view/lifecycle refresh hooks, so this omission creates a real risk of duplicate publishes, missed updates, and racey coalescing.
  Recommended fix:
  Make the republish coordinator the sole serialized owner of freshness events and route both mutation and rate changes through one typed event stream or actor-isolated boundary. Explicitly bridge or retire legacy view-triggered refresh paths so they cannot compete with the coordinator.
  Acceptance criteria:
  All dirty events are consumed on one serialized execution context, interleaved mutation and rate events coalesce into one publish, and legacy hooks cannot trigger duplicate publishes or missed refreshes.
  Confidence: `Medium`

- Finding ID: `ARCH-02`
  Severity: `High`
  Evidence IDs: `DOC-01`, `CODE-01`, `CODE-02`
  Why it matters:
  The proposal correctly identifies that canonical projection rebuild must stop using `goal.manualTotal`, but it still treats `GoalCalculationService` as the drop-in engine. In the current repo that service is `@MainActor` and constructs presentation-layer view models, so it is not yet a safe domain calculator for background republish or rate-drift evaluation.
  Recommended fix:
  Extract a pure, non-UI calculation service in the domain/service layer and keep `GoalCalculationService` as a thin presentation wrapper if needed by views. The republish coordinator and rate-drift evaluator should depend only on the pure calculator.
  Acceptance criteria:
  Projection rebuild can run without constructing view models, calculation logic is deterministic and unit-testable, and both republish and rate-drift evaluation use the same pure computation path.
  Confidence: `High`

- Finding ID: `ARCH-03`
  Severity: `Medium`
  Evidence IDs: `DOC-01`, `CODE-05`, `QUESTION-01`, `QUESTION-02`
  Why it matters:
  The proposal introduces `rateSnapshotTimestamp`, tiered freshness states, and monotonic version semantics, but it does not define how older cached payloads or missing fields are migrated. That leaves room for upgrade-time misclassification, regressing to older snapshots, or accidentally treating unknown payloads as fresh.
  Recommended fix:
  Add an explicit schema and migration matrix for projection payloads and local caches, including safe fallback behavior when freshness metadata is absent and version handling across upgrades.
  Acceptance criteria:
  Older cached projections always resolve to a safe state, missing freshness metadata never produces a false healthy state, and upgrade tests prove version monotonicity and state preservation.
  Confidence: `Medium`

## 4. Cross-Discipline Conflicts and Decisions
- Conflict:
  `projectionPublishedAt` is easier to surface cleanly, but `rateSnapshotTimestamp` is the stronger trust signal for money values.
  Tradeoff:
  A single clean timestamp is simpler; a composite trust model is more truthful.
  Decision:
  Keep both pieces of metadata, but define one composite freshness state where stale rates can escalate the primary warning even if publish time is recent.
  Owner:
  Proposal author + UX + iOS architecture

- Conflict:
  Four internal freshness tiers improve diagnostics, but exposing every distinction in the list view increases cognitive and visual load.
  Tradeoff:
  Richer internal taxonomy helps correctness and telemetry; compact UI needs one-glance trust semantics.
  Decision:
  Preserve the tiered internal model, but collapse visible list behavior to one primary freshness message plus one optional secondary rate-age detail.
  Owner:
  Proposal author + UI/UX

- Conflict:
  Reusing `GoalCalculationService` looks cheaper, but the current implementation is presentation-bound.
  Tradeoff:
  Short-term reuse avoids a refactor; pure calculation extraction avoids threading and correctness drift.
  Decision:
  Treat pure money-calculation extraction as a prerequisite, not as an implementation detail hidden inside later phases.
  Owner:
  iOS architecture

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependencies | Success Metric | Source Findings |
|---|---|---|---|---|---|---|---|
| P0 | Lock a single serialized freshness-event owner and explicitly retire/bridge competing view-triggered refresh paths | iOS Architecture | iOS architecture | Now | Current notification and lifecycle hooks | No duplicate publish path remains in the design; coalescing and race handling are testable at document level | `ARCH-01` |
| P0 | Extract and name a pure non-UI money-calculation service for republish and rate-drift evaluation | iOS Architecture | iOS architecture | Now | Current `GoalCalculationService` contract | Proposal no longer depends on view-model-driven calculation for canonical projection rebuild | `ARCH-02` |
| P1 | Replace separate publish-age and rate-age messaging with a composite freshness contract | UX | Proposal author + UX | Now | Finalized metadata fields | User-facing trust state cannot show as healthy when rates are stale | `UX-01` |
| P1 | Add explicit cache/schema migration rules for new freshness metadata and version monotonicity | iOS Architecture | iOS architecture | Pre-implementation | Payload/version model | Upgrades and older caches always degrade safely and never regress freshness state | `ARCH-03` |
| P2 | Add viewport/accessibility rules for freshness header, warning copy, and token semantics | UI | UI/UX | Pre-implementation | Finalized UX wording | No overlap, truncation, or contrast drift in compact-width and large-text states | `UI-01`, `UI-02`, `UX-02`, `UX-03` |

## 6. Validation and Measurement Plan
| Area | What Will Be Measured | Leading Indicators | Guardrails | Review Checkpoint | Rollback / Hold Criteria |
|---|---|---|---|---|---|
| Publish graph ownership | Dirty-event coalescing, duplicate publish suppression, publish success/failure by reason | One publish per mutation burst, stable trailing publish count, no competing trigger path in logs | No missed invitee-visible update after authoritative mutation | End of Phase 1 design and unit tests | Hold if duplicate or race-prone publish paths remain unresolved |
| Rate-drift correctness | Materiality evaluation and recomputed `currentAmount` parity between owner and shared projection | Deterministic unit tests, republish only above threshold, stable `maxDeltaPct` telemetry | No use of `goal.manualTotal` in canonical projection rebuild | End of Phase 2 design and unit tests | Hold if canonical rebuild still depends on presentation-layer calculation |
| Invitee trust semantics | Freshness header, stale tiers, rate-age escalation, detail/list parity | UI tests for active/recentlyStale/stale/materiallyOutdated, relative-time header, detail/list agreement | No screen can appear healthy while rate age is in warning state | End of Phase 1 UI contract | Hold if publish age can mask stale rates or if list/detail semantics diverge |
| Migration safety | Cache upgrade behavior, missing metadata fallback, monotonic version handling | Migration/unit tests for old payloads and missing timestamps | No older payload can render as falsely healthy or overwrite newer state | Before implementation start | Hold if schema migration plan is not written and testable |

## 7. Evidence Gaps and Open Questions

### Evidence Gaps
- `GAP-01`: No live multi-device CloudKit evidence was collected for owner/invitee publish-fetch timing, multi-device owner races, or v2 push delivery.
- `GAP-02`: No dark-mode, large Dynamic Type, RTL, or VoiceOver runtime evidence was collected for the proposed new freshness/status hierarchy.
- `GAP-03`: The proposal still leaves cache/schema migration behavior for new freshness metadata partly open, so part of the architecture assessment remains inferential rather than explicit.

### Open Questions
- `QUESTION-01`: Should stale `rateSnapshotTimestamp` escalate the primary freshness state even when `projectionPublishedAt` is recent, or should the proposal keep a strictly secondary rate-age indicator?
- `QUESTION-02`: Which surface owns the canonical freshness grammar for shared goals: section header only, or both list and detail with the same semantic contract?
