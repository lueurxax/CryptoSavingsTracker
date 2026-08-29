# Source-Aware Settlement for Finished Goal Allocations

Date: 2026-08-29

Status: Product design approved; implementation pending

Initial implementation scope: iOS

Product contract scope: Platform-neutral

## Summary

Finishing a goal must settle each allocation according to the source of truth for the asset balance.

- Manual assets keep the allocation reserved as spent because the balance does not decrease automatically.
- On-chain assets release the allocation because the tracked wallet balance already reflects the purchase.
- Mixed assets require one explicit user choice at goal completion.
- Existing finished allocations require a one-time review and are never released automatically.

The settlement decision is final. A correction flow is intentionally excluded until user feedback proves that it is needed.

## Problem

The current runtime retains every allocation when a goal is marked Finished. This was intentional for fiat and manually tracked crypto: completing a purchase does not automatically add a negative transaction, so retaining the allocation virtually marks those funds as spent.

The same rule is incorrect for assets whose balance is read from a wallet. The external purchase already reduces the tracked balance. Retaining the finished allocation subtracts the same money a second time and can produce an apparent over-allocation.

Example from the reported state:

- Current wallet balance: `5,873.6673 USDT`.
- Allocations retained by finished goals: `4,456 USDT`.
- The wallet balance has already decreased after the purchases.
- Treating the finished allocations as unavailable again creates a false shortfall.

The current universal rule is documented in `docs/CONTRIBUTION_TRACKING_REDESIGN.md` and implemented by `GoalLifecycleService.finishGoal`. The implementation must not change until this design is translated into a tested implementation plan.

## Goals

- Count completed spending exactly once.
- Preserve the intentional virtual-spend behavior for manual balances.
- Release finished allocations automatically when an external wallet is the sole balance source.
- Ask the user only when the balance source is genuinely ambiguous.
- Preserve an immutable record of how a finished goal was funded even when current allocations are released.
- Repair legacy finished allocations without destructive automatic migration.
- Replace generic over-allocation messaging with an actionable legacy-review state where applicable.

## Non-Goals

- Automatically attributing a specific blockchain transaction to a goal purchase.
- Editing a settlement after it has been applied.
- Reopening finished goals or restoring released allocations.
- Implementing the Android UI in the first delivery.
- Reworking monthly planning, execution snapshots, or contribution tracking.
- Inferring whether a user manually recorded a purchase as a negative transaction.

## Balance Accounting Modes

`AssetBalanceAccountingMode` is a computed domain value. It is not persisted.

| Mode | Classification | Meaning |
|---|---|---|
| `manual` | No pair of non-empty wallet address and chain identifier | The app ledger is the only balance source. |
| `onChain` | Valid wallet tracking and no manual transactions | The external wallet is the only balance source. |
| `mixed` | Valid wallet tracking and at least one manual transaction | The asset total combines external and manual sources, so allocation provenance is ambiguous. |

Classification uses the existence of manual transactions, not the current net manual balance. A zero net balance can still represent manual accounting history and must therefore remain `mixed`.

Stale or failed wallet refreshes do not change the mode. The configured balance source is the policy input; network availability is not.

## Settlement Rules

| Goal state | Asset mode | Required action | Current allocation after completion |
|---|---|---|---|
| New completion | `manual` | Automatic `keepAsSpent` | Retained and unavailable to active goals |
| New completion | `onChain` | Automatic `balanceAlreadyDecreased` | Released |
| New completion | `mixed` | User chooses once | Retained or released according to the choice |
| Legacy finished goal without a completion snapshot | Any | One-time review | Retained until review is applied |

For a goal funded by multiple assets, the rule is evaluated independently for every allocation. The finish action cannot be applied until every mixed allocation has a decision.

## Approaches Considered

### Retain every finished allocation

This is the current behavior. It is correct for manual balances but double-counts spending for live wallet balances.

### Release every allocation attached to an asset with a wallet address

This fixes pure on-chain assets but is unsafe for mixed assets. It also removes the only current record of the amount associated with the completed goal.

### Source-aware settlement with a completion snapshot

This is the selected approach. It automates unambiguous cases, asks only for mixed assets, and separates immutable goal history from mutable current allocations.

## Domain Design

### `AssetBalanceAccountingModeResolver`

A pure resolver classifies an asset as `manual`, `onChain`, or `mixed` using its configured wallet tracking and transaction sources. UI and lifecycle code must use the resolver instead of duplicating address checks.

### `GoalCompletionSnapshot`

Before any allocation is retained or released, the app records a Codable immutable snapshot on the goal in a new optional `completionSnapshotData` field.

Snapshot schema version 1 contains:

- Snapshot identifier and schema version.
- Goal identifier, name, currency, and target amount at completion.
- Goal completion timestamp and snapshot creation timestamp. These are equal for new completions but can differ for legacy review.
- One entry per allocation with:
  - asset identifier and currency;
  - allocation amount in asset currency;
  - accounting mode at completion;
  - final settlement: `keepAsSpent` or `balanceAlreadyDecreased`;
  - best-known asset balance when the snapshot is created, when available.

Raw allocation quantities are authoritative. Any optional balance or converted display value must be labeled best-known and must not block completion when exchange rates or wallet refreshes are unavailable. A legacy snapshot must never present its review-time balance as the balance at the earlier goal-completion time.

The snapshot is created once. A goal with a snapshot cannot be settled again.

### `GoalCompletionSettlementPlanner`

The planner is pure and returns one of two outcomes:

- `ready`: every allocation has an automatic settlement.
- `requiresDecision`: one or more mixed allocations need a user choice.

The planner also detects legacy finished goals whose allocations exist but whose completion snapshot is absent.

### `GoalCompletionSettlementService`

The service applies an approved plan in one persistence commit:

1. Revalidate that the goal is still active for a new completion, or finished without a snapshot for legacy review.
2. Recompute the accounting mode for each current allocation.
3. Reject missing mixed decisions or changed allocation inputs.
4. Encode and attach the immutable completion snapshot.
5. Retain `keepAsSpent` allocations.
6. Remove `balanceAlreadyDecreased` allocations and append zero-value `AllocationHistory` entries.
7. Mark a new goal as Finished and remove it from active execution tracking.
8. Save once.
9. Publish lifecycle notifications and perform reminder cleanup only after the persistence commit.

The current save-per-asset allocation path cannot provide this atomicity. Implementation must introduce a batch mutation seam that does not save or publish intermediate state.

## New Goal Completion Flow

### Manual-only goal

The user chooses Finish. The app snapshots the goal, retains the allocations as spent, and completes without an additional prompt.

### On-chain-only goal

The user chooses Finish. The app snapshots the goal, releases the allocations, and completes without an additional prompt.

### Goal with mixed allocations

The app presents a Finish Goal sheet containing each mixed allocation and two choices:

- `Balance already decreased`: release the allocation; completed funding remains in history.
- `Keep as spent`: retain the allocation because the balance did not update automatically.

The sheet explains the accounting effect and shows the total amount that will become available. The final button applies the settlement and finishes the goal once.

Automatic manual and on-chain settlements may be summarized in the sheet when the same goal also contains mixed assets, but they do not require input.

## Legacy Review Flow

A finished goal with current allocations and no completion snapshot is a legacy pending-review record.

- No legacy allocation is released automatically.
- The Asset Allocation editor shows `Review finished allocations` instead of presenting the state only as a generic over-allocation error.
- The review lists each finished goal, amount, accounting-mode-based recommendation, and the same two settlement choices.
- Opening review from one asset still loads every unresolved allocation for the affected goal. A completion snapshot is never created from a partial goal view.
- `Later` performs no mutation. Pending allocations remain unavailable until review.
- `Apply Review` snapshots every reviewed goal and applies all chosen settlements in one commit.
- After successful application, the review is final and cannot be reopened.

For the reported example, the screen would show the `4,456 USDT` legacy total and the amount that will become available after the selected resolutions.

## Allocation Editor States

Finished allocations are separated into two groups:

- `Pending review`: legacy records without a completion snapshot. The primary action is Review.
- `Reserved as spent`: allocations confirmed by a completion snapshot with `keepAsSpent`. These remain read-only and unavailable.

Released allocations are absent from current allocation totals and appear only in the finished goal snapshot/history.

If pending legacy allocations cause the total to exceed the live balance, the editor explains that historical allocations need review. It must not instruct the user to reduce active allocations when active allocations are not the cause.

## Failure Handling and Consistency

- A missing mixed decision blocks Finish before any mutation.
- If allocations change while the decision sheet is open, the plan is rejected and regenerated.
- Snapshot encoding or persistence failure leaves the goal and allocations unchanged.
- A failed wallet refresh does not block completion or legacy review.
- Applying the same completion or review command again is idempotent: an existing completion snapshot prevents a second settlement.
- Reminder cancellation is best-effort after commit and cannot roll back financial state.
- Notifications are published only after the successful commit, preventing views from observing partial state.

## Historical Presentation

Finished goal views read their completion allocation breakdown from `GoalCompletionSnapshot`, not from current `AssetAllocation` rows or live wallet balances.

This preserves the exact raw quantities associated with the goal while allowing released money to fund new goals. The snapshot does not claim transaction-level attribution and does not change after later price or exchange-rate movement.

## Platform Scope

The rules, snapshot format, settlement vocabulary, and acceptance tests are platform-neutral.

The first implementation is iOS because the current production issue is reproduced there. Android must consume the same contract in a separate implementation pass; it must not invent different finish semantics.

## Testing Strategy

### Unit tests

- Mode resolver: manual, on-chain, mixed, empty address, zero net manual balance, stale wallet state.
- Planner: automatic manual/on-chain results, mixed decision requirements, and multi-asset goals.
- Snapshot encoding/decoding and schema-version rejection.
- Settlement service: retain, release, mixed choices, history insertion, and idempotency.
- Legacy detection and final review application.

### Persistence tests

- One save produces the snapshot, goal lifecycle change, allocation mutations, and history rows together.
- A forced save failure rolls all in-memory mutations back.
- Existing finished goals without snapshot data remain readable and pending review.
- Optional snapshot data migrates existing SwiftData stores without destructive changes.

### UI tests

- Manual and on-chain goals finish without an additional decision sheet.
- Mixed goals cannot finish until every mixed allocation has a choice.
- The summary matches the amount to be released.
- Legacy review supports Later without mutation and Apply Review with final results.
- Allocation editor distinguishes pending review, reserved as spent, and active over-allocation.

## Rollout

1. Add the optional snapshot field and pure mode/planning types.
2. Add atomic settlement application and tests while keeping the existing UI entry point.
3. Route new goal completion through the planner and mixed decision sheet.
4. Add legacy review and the allocation-editor state split.
5. Update `docs/CONTRIBUTION_TRACKING_REDESIGN.md` so Finish is no longer described as universally retained.
6. Ship iOS behind a local rollout flag only if store migration or legacy detection needs staged validation; otherwise ship directly after migration and regression gates pass.
7. Evaluate Android parity separately.

No background migration releases funds. Legacy resolution requires a visible user action.

## Acceptance Criteria

- A pure manual asset preserves its finished allocation as spent.
- A pure on-chain asset releases its finished allocation exactly once.
- A mixed asset cannot be settled without an explicit user choice.
- Every newly finished goal has a completion snapshot before current allocations change.
- Existing finished allocations are never released before one-time review.
- Finished goal history remains available after released allocations are removed.
- Applying a completion or review twice cannot duplicate releases or history.
- A failed persistence commit leaves the pre-action state intact.
- The allocation editor never blames active allocations when pending legacy allocations are the cause of the displayed shortfall.
- The first implementation changes iOS behavior only while preserving a platform-neutral contract.

## Explicit Product Decisions

- Automatic behavior is preferred over prompts for unambiguous assets.
- Mixed and legacy cases require a visible user decision.
- Legacy review is safe-by-default and deferrable.
- Settlement is final after application; no correction UI is included.
- Negative feedback, if observed after release, will drive a separately designed correction flow.
