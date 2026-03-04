# Monthly Planning State Model Simplification Proposal

> Audit mapping: issue #1 (state complexity in monthly cycle)

| Metadata | Value |
|---|---|
| Status | Draft |
| Last Updated | 2026-03-02 (Arch Final aligned) |
| Platform | iOS + Android |
| Scope | Monthly Planning / Execution state transitions |

---

## 1) Problem

Monthly cycle has too many user-visible states and overlapping actions:

- `Lock Plan & Start Tracking`
- `Finish This Month`
- `Return to Planning`
- `Undo`

Users do not understand which action changes current month vs next month, and when planning is reopened automatically.

## 2) Goal

Make state machine explicit, predictable, and user-facing copy unambiguous.

## 3) Product Model (Canonical Cycle + Explicit Exception)

Single canonical cycle:

1. `Planning (month M)`
2. `Executing (month M)`
3. `Planning (month M+1)`

Rules:

- `Start Tracking` always applies to **current planning month**.
- `Finish Month` always closes **executing month** and opens planning for **next month**.
- `Undo Start Tracking` always returns to **planning of same month**.
- Closed-state normative rule:
  - while undo window is active, UI shows `closed(M)` with `Undo Finish`;
  - once undo window expires, UI shows planning for the next month.

### 3.1 Explicit exception policy: Undo Completion

To preserve existing recovery behavior and avoid regressions, `Closed -> Executing` undo remains supported as a strictly bounded exception.

Policy:

- `Undo Completion` is available only during configured undo window.
- If window expired, action is not offered.
- History keeps the completion event even when undone.

Behavior:

- `Undo Completion (month M)` returns to `Executing (month M)`.
- On success, banner and CTA must update in same render cycle.

Out of window:

- User sees explicit reason: `Undo period ended for March 2026`.

## 4) UI/Copy Contract

- Replace generic labels with month-explicit copy:
  - `Start Tracking March 2026`
  - `Finish March 2026`
  - `Back to Planning March 2026`
  - `Undo Finish March 2026` (shown only during undo window)
- Banner must always show:
  - current mode,
  - affected month,
  - next action.

### 4.1 Compact fallback and truncation rules

To keep compact layouts readable and unambiguous:

1. Primary button copy fallback order:
   - Full: `Start Tracking March 2026`
   - Compact: `Start March 2026`
   - Tight compact: `Start Mar 2026`
2. Primary action stays single-line; no ellipsis on month token alone.
3. If fallback level 3 still clips, switch to icon + short verb and move full month to accessibility label.
4. VoiceOver/TalkBack always read full action with full month.

### 4.2 State-to-visual token map (required)

| UI State | Icon | Container Token | Text Emphasis | Accessibility Announcement |
|---|---|---|---|---|
| `planning` | `doc.text` | `state.info.background` | medium | `Planning for {month}` |
| `executing` | `chart.line.uptrend.xyaxis` | `state.active.background` | high | `Tracking contributions for {month}` |
| `closed` | `checkmark.circle.fill` | `state.success.background` | medium | `Month {month} completed` |
| `conflict` | `exclamationmark.triangle.fill` | `state.warning.background` | high | `Monthly state conflict, refresh required` |

Both platforms must use the same semantic token keys and icon mapping.

## 5) Technical Contract

### 5.1 Resolver interface (shared contract)

- Introduce shared state resolver (platform parity):
  - iOS: `MonthlyCycleStateResolver` service
  - Android: `MonthlyCycleStateResolverUseCase`
- All views consume resolved `UiCycleState`, never raw record status directly.
- Remove parallel ad-hoc conditions in container + execution screens.

Resolver schema:

```swift
struct ResolverInput {
    let nowUtc: Date
    let displayTimeZone: TimeZone         // user/device timezone for UI copy formatting
    let currentStorageMonthLabelUtc: String
    let records: [ExecutionRecordSnapshot]
    let undoWindowSeconds: TimeInterval
}

struct ExecutionRecordSnapshot {
    let monthLabel: String                // yyyy-MM (UTC-canonical storage label)
    let status: ExecutionStatus           // draft/executing/closed
    let completedAt: Date?
    let startedAt: Date?
}

enum UiCycleState {
    case planning(month: String, source: PlanningSource)
    case executing(month: String, canFinish: Bool, canUndoStart: Bool)
    case closed(month: String, canUndoCompletion: Bool)
    case conflict(month: String?, reason: CycleConflictReason)
}

enum CycleConflictReason {
    case duplicateActiveRecords
    case invalidMonthLabel
    case futureRecord
}
```

### 5.2 Deterministic precedence matrix

When multiple records exist, resolver uses this order:

1. If month labels are malformed or impossible, return `conflict(month: nil, reason: .invalidMonthLabel)`.
2. If active record month is in unsupported future range, return `conflict(month: M, reason: .futureRecord)`.
3. If duplicate active `executing` records exist for same month, return `conflict(month: M, reason: .duplicateActiveRecords)`.
4. Active `executing` record for month `M` -> `executing(M)`.
5. Latest `closed` record for month `M`:
   - if undo window is active for `M`: `closed(M)` with undo affordance,
   - otherwise: `planning(currentStorageMonthLabelUtc)` with closed summary.
6. No valid executing/closed record -> `planning(currentStorageMonthLabelUtc)`.

Normative UX rule:

- `conflict` always supersedes normal states and blocks all state-changing actions until refresh/recovery.

Future-range bound:

- `futureRecord` conflict is raised when `record.monthLabel > currentStorageMonthLabelUtc + 1 month`.
- `record.monthLabel == currentStorageMonthLabelUtc + 1 month` is valid and must not trigger conflict.

### 5.3 Month label semantics

- Storage month labels are UTC-canonical `yyyy-MM` on both platforms.
- Resolver compares and transitions using UTC storage labels only.
- UI display strings are formatted in user locale/timezone from resolver output context.
- Existing historical UTC labels remain valid; no destructive relabel migration is allowed.

### 5.4 Error/recovery copy catalog (required)

Every blocked action must return user-facing reason:

- `startBlockedMissingPlan`: `Complete planning first before starting tracking.`
- `startBlockedAlreadyExecuting`: `Tracking is already active for {month}.`
- `startBlockedClosedMonth`: `This month is already closed.`
- `finishBlockedNoExecuting`: `No active month is being tracked.`
- `undoStartExpired`: `Undo period ended for {month}.`
- `undoCompletionExpired`: `Undo period ended for {month}.`
- `recordConflict`: `Monthly state is out of sync. Please refresh.`

### 5.5 `UiCycleState x Action -> CopyKey` mapping (required)

| UiCycleState | Action | Allowed | CopyKey when blocked |
|---|---|---|---|
| `planning` | `startTracking` | Yes | — |
| `planning` | `finishMonth` | No | `finishBlockedNoExecuting` |
| `planning` | `undoStart` | No | `undoStartExpired` |
| `planning` | `undoCompletion` | No | `undoCompletionExpired` |
| `executing` | `startTracking` | No | `startBlockedAlreadyExecuting` |
| `executing` | `finishMonth` | Yes | — |
| `executing` | `undoStart` | Only if undo window active | `undoStartExpired` |
| `executing` | `undoCompletion` | No | `undoCompletionExpired` |
| `closed` | `startTracking` | No | `startBlockedClosedMonth` |
| `closed` | `finishMonth` | No | `finishBlockedNoExecuting` |
| `closed` | `undoStart` | No | `undoStartExpired` |
| `closed` | `undoCompletion` | Only if undo window active | `undoCompletionExpired` |
| `conflict` | any action | No | `recordConflict` |

### 5.6 Completion-history retention model (non-destructive)

Undo completion must preserve auditability on both platforms.

Model:

1. Introduce append-only `CompletionEvent`:
   - `eventId`,
   - `executionRecordId`,
   - `sequence`,
   - `sourceDiscriminator`,
   - `monthLabel`,
   - `completedAt`,
   - `undoneAt` (nullable),
   - `undoReason` (nullable),
   - `completionSnapshotRef`.
2. `finishMonth` creates event with `completedAt`.
3. `undoCompletion` sets `undoneAt` (never deletes completion event).
4. `completionSnapshotRef` points to immutable per-goal completion snapshot artifacts already used by history UIs.
5. Execution snapshot/state may be reopened, but completion event remains immutable except `undoneAt` marker.

Uniqueness and ordering:

- `eventId` is globally unique.
- `sequence` is strict monotonic within `executionRecordId`.
- Query ordering is `(monthLabel asc, sequence asc)` for deterministic same-month complete/undo/re-complete cycles.
- Unique constraint: `(executionRecordId, sequence)`.
- Unique constraint: `(executionRecordId, sourceDiscriminator)` for idempotent backfill/replay safety.

Repository contract update:

- iOS and Android repositories must expose completion event history separately from active execution record.
- Completion-event fetch must include linked immutable snapshot details via `completionSnapshotRef`.
- Deleting completion artifacts on undo is forbidden after migration.

### 5.7 Backfill algorithm (deterministic)

Goal: build `CompletionEvent` from existing completion artifacts without duplicates.

Algorithm:

1. Load existing completed artifacts.
   - iOS source: immutable `CompletedExecution` snapshots.
   - Android source: per-goal `CompletedExecution` rows.
2. Build grouping key:
   - `executionRecordId`
   - `completedAtMillis`
   - `sourceDiscriminator`

`sourceDiscriminator` definition:

- iOS: immutable snapshot primary key (`CompletedExecution.id`).
- Android: deterministic digest for grouped per-goal rows:
  - `SHA256(sorted(row.id list) + sorted(goalId list) + rowCount + completedAtMillis)`.
3. Group rows by full key.
4. For each grouped completion batch:
   - create one `CompletionEvent`,
   - persist `sourceDiscriminator` in `CompletionEvent`,
   - set `completionSnapshotRef` to linked immutable snapshot entity (or created snapshot aggregate for Android batch),
   - preserve `completedAt` from group key.
5. Sequence assignment:
   - sort groups by `(completedAtMillis asc, sourceDiscriminator asc)`,
   - assign `sequence = 1..N` per `executionRecordId`.
6. Idempotence:
   - upsert on `(executionRecordId, sequence)` and verify stable hash,
   - re-running migration must produce identical event count/order.

### 5.8 Atomic persistence boundary (hard requirement)

Each transition must execute as a single atomic persistence transaction:

- `startTracking`
- `finishMonth`
- `undoStart`
- `undoCompletion`

Platform-specific contract:

- iOS (SwiftData): transition writes must commit in one save boundary; if any sub-step fails, whole transition is rolled back.
- Android (Room): transition writes must run under one `@Transaction`; if any sub-step fails, whole transition is rolled back.

Fault tolerance tests:

- Fault-injection tests must simulate failures between sub-steps and verify zero partial state writes.

## 6) Android Parity and Ownership Plan

Current Android has parallel execution state stacks. Resolver rollout requires one canonical owner.

Decision:

1. Canonical monthly-cycle state source: domain `MonthlyCycleStateRepository` + resolver use case.
2. `presentation/planning/*` and `presentation/execution/*` both consume this source.
3. Remove direct screen-level branching on raw `ExecutionStatus.EXECUTING`.
4. Mark legacy screen-local state derivation as deprecated in same release.

Exit criteria (measurable):

1. Repository-wide static check returns zero raw `ExecutionStatus` branching in UI layers.
2. Both planning and execution entry points read state only from resolver output.
3. CI includes guard test that fails if forbidden raw-status branch patterns appear.

## 7) Shared Fixtures and Test Contract

Parity fixtures are JSON files in `shared-test-fixtures/monthly-cycle/`.

Fixture schema:

```json
{
  "displayTimeZone": "Asia/Nicosia",
  "nowUtc": "2026-03-02T08:00:00Z",
  "currentStorageMonthLabelUtc": "2026-03",
  "undoWindowSeconds": 86400,
  "records": [
    { "monthLabel": "2026-02", "status": "closed", "completedAt": "2026-03-01T09:00:00+02:00", "startedAt": "2026-02-01T08:00:00+02:00" }
  ],
  "expected": {
    "state": "planning",
    "planning": {
      "month": "2026-03",
      "source": "nextMonthAfterClosed"
    }
  }
}
```

Expected payload is a discriminated union:

- if `state = planning` -> only `planning` object is allowed;
- if `state = executing` -> only `executing` object is allowed;
- if `state = closed` -> only `closed` object is allowed.
- if `state = conflict` -> only `conflict` object is allowed.

Fixture validator must reject mixed field/state combinations.

Required test cases on both platforms:

- `start -> executing`
- `undo start -> planning same month`
- `finish -> planning next month`
- `closed -> planning next month`
- `closed + undo window active -> undo completion available`
- conflicting records precedence
- conflict: duplicate active records
- conflict: malformed month label
- conflict: unsupported future month record
- conflict-boundary: `recordMonth == current+1` (valid, no conflict)
- conflict-boundary: `recordMonth == current+2` (must return `futureRecord`)
- month-boundary: UTC-12 display timezone edge
- month-boundary: UTC+14 display timezone edge

## 8) Migration and Backward Compatibility

Migration guardrails for existing persisted records:

1. Keep existing statuses (`draft`, `executing`, `closed`) and existing UTC month labels unchanged.
2. Add `CompletionEvent` store and backfill from existing completion timestamps where available.
3. Backfill `completionSnapshotRef` by linking to existing immutable completion snapshot rows (iOS `CompletedExecution`, Android `CompletedExecution` equivalents).
4. If multiple active `executing` records are found:
   - pick latest by `startedAt`,
   - mark others as conflicted in diagnostics log.
5. If record month label is invalid, exclude from UI and log once.
6. Existing undo windows remain valid; resolver must honor persisted timestamps.
7. During migration window, legacy delete-on-undo code paths must be feature-flagged off after data backfill.
8. Add compatibility tests for historical UTC labels near month boundaries (UTC-12/UTC+14 display contexts).

### 8.1 Release migration and cutover sequence

1. Schema add:
   - create `CompletionEvent` tables/indexes/constraints.
2. Optional dual-write phase (guarded):
   - write both legacy completion artifacts and `CompletionEvent`.
3. Deterministic backfill:
   - execute backfill with `sourceDiscriminator`.
4. Verification gate:
   - validate event count, discriminator set, and sequence ordering invariants.
5. Read-path cutover:
   - switch resolver/history queries to `CompletionEvent` + `completionSnapshotRef`.
6. Legacy cleanup:
   - permanently disable delete-on-undo logic,
   - keep temporary rollback compatibility only for release window.

## 9) Rollout Plan

1. Add resolver and unit tests for all transitions.
2. Add shared fixture pack and run parity tests in iOS + Android CI.
3. Unify Android execution state ownership and deprecate parallel raw-state derivations.
4. Migrate container/banner/actions to resolver output.
5. Update UI tests for:
   - start -> executing,
   - undo start -> planning same month,
   - finish -> planning next month,
   - closed record -> planning next month,
   - undo completion in-window and out-of-window.
6. Add screenshot evidence matrix for `planning/executing/closed` in light + dark.

## 10) Acceptance Criteria

- No screen where executing controls are visible for `closed` month.
- Transition after `Finish Month` shows planning for next month within one UI cycle.
- `Undo Completion` behavior is explicit and consistent on both platforms.
- Closed-state rule is singular and non-contradictory across all sections.
- iOS and Android state transition tests use identical fixtures and expected outputs.
- Fixture validator rejects invalid state/field combinations.
- Undo completion preserves auditable completion history (`completedAt` + optional `undoneAt`).
- Undo completion keeps full immutable snapshot detail queryable in history views.
- Same-month repeated completion cycles remain deterministic by `(executionRecordId, sequence)`.
- UTC storage month labels remain deterministic and historical records are still addressable.
- Transition fault-injection tests prove no partial writes for `start/finish/undoStart/undoCompletion`.
- Backfill reruns produce identical `CompletionEvent` count, `sourceDiscriminator` set, and sequence ordering.
- Future-range conflict boundary fixtures (`current+1`, `current+2`) pass identically on iOS and Android.
- Compact labels remain unambiguous with fallback rules and full accessibility labels.
- For every blocked action, user sees explicit reason copy.

## 11) R4 + Arch Final Decisions

1. Storage month labels remain UTC-canonical; user timezone affects display formatting and resolver UI context only.
2. Duplicate active records drive hard `conflict` UI state (not executing-with-warning).
3. Backfill grouping key is finalized as `(executionRecordId, completedAtMillis, sourceDiscriminator)`; `sourceDiscriminator` is explicitly defined per platform.
4. `conflict` is modeled as a first-class `UiCycleState` (not side metadata).
5. `CompletionEvent` references separate immutable snapshot entity via `completionSnapshotRef`; summary fields may be duplicated for list performance.
6. Same-month re-completion ordering is strict monotonic within `executionRecordId` (`sequence`) and deterministic for repeated migration runs.
7. All state transitions (`start`, `finish`, `undoStart`, `undoCompletion`) require atomic transaction boundaries with rollback on failure.
