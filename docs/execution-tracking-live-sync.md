## Proposal: Live-Synced Monthly Tracking (Goals → Plans → Execution)

### Problem
- Execution tracking freezes a snapshot when tracking starts; later changes to goal allocations/shares or added payments in Goal Detail are not reflected until tracking is restarted.
- Users expect Goal Detail changes (allocations and payments) to flow automatically into Monthly Plans and the active Execution view without manual restart.

### Goals
- Keep a single, consistent source of truth for planned amounts and contributions.
- Make Goal Detail the primary place to add/change allocations and payments, with immediate reflection in Monthly Planning and Execution views.
- Avoid restarting tracking to pick up plan changes.
- Preserve history (final snapshot) when a month is closed.

### Proposed Architecture (Recommended: Hybrid with Baseline)
1) **Hybrid execution view (live for active, frozen baseline for closed)**
   - Active month: compute planned vs. contributed on demand from `MonthlyPlan` (effectiveAmount/requiredMonthly) + `Contribution` totals.
   - Closed months: display the frozen `ExecutionSnapshot` captured when the month was closed to preserve history.
   - Keep the original “Baseline Snapshot” from tracking start for reference/undo; show “Current Plan” live for the active month.

2) **Plan-updated event pipeline**
   - Emit a `planUpdated`/`goalUpdated` domain event when allocations/shares change or when a transaction is saved in Goal Detail.
   - `ExecutionTrackingService` listens: if there is an active record, recompute live execution data and optionally regenerate an in-progress snapshot for undo/baseline (baseline remains for reference).
   - `MonthlyExecutionViewModel` subscribes and reloads automatically; event payload should include goalId so unrelated goals can be ignored.

3) **Data model adjustments**
   - Keep snapshots for closed months and for the baseline (start-of-month). For active months, prefer live computation for display; optionally maintain an in-progress snapshot for undo but not for display.
   - Add `lastSyncedAt`/`version` to `MonthlyExecutionRecord` to guard against stale UI and enable migration/versioning.

4) **UI/UX changes**
   - Goal Detail: after saving share/allocation or adding a transaction, trigger sync and show “Synced to monthly tracking” toast; no manual restart.
   - Execution/Tracking view: show live planned vs. contributed for the active month and include a “Baseline (when tracking started)” reference; for closed months show the frozen snapshot as historical.
   - Planning view: starting tracking remains one tap; no restart needed for subsequent changes.

5) **Migration/compat**
   - On first load of an executing record, recompute live data and optionally regenerate its in-progress snapshot from current `MonthlyPlan` to clear mismatches; baseline from start remains unchanged.
   - Closed records keep their stored snapshot unchanged for historical accuracy.

### Delivery Plan (incremental, Hybrid with Baseline)
0) **Persist recalculated MonthlyPlans**: when `.monthlyPlanningAssetUpdated` fires, recalc requirements and write the new amounts to SwiftData `MonthlyPlan` records (via a `persistUpdatedPlans()` step in `MonthlyPlanningViewModel` using `MonthlyPlanService.updatePlan()`).
1) Add event emitter for plan/goal updates; emit from Goal Detail save flows (share changes, new transactions) **after** persistence succeeds; include `goalId` in payload.
2) In `ExecutionTrackingService`, on event:
   - If active record exists: recompute live execution data; optionally regenerate an in-progress snapshot for undo/baseline (do not replace the baseline snapshot).
   - Save `lastSyncedAt`/`version` for UI freshness checks.
3) Update `MonthlyExecutionViewModel` to subscribe to the event and reload live data for the active month; use snapshot only for closed months or baseline reference.
4) Execution UI: show live planned vs. contributed for active month, plus “Baseline (tracking start)” for reference; for closed months, show the frozen snapshot labeled historical. In code, branch `calculateProgress`: closed → snapshot; active → live `MonthlyPlan`.
5) On month close, persist a final snapshot for history and mark record as closed.
6) Migration: when opening an existing executing record, recompute live data (and optionally refresh its in-progress snapshot) to align with current plans without altering baseline or closed records.

### Benefits
- User changes in Goal Detail immediately reflect in Monthly Tracking for the active month.
- No restart needed; fewer support issues about “stale tracking”.
- Historical accuracy preserved for closed months; live accuracy for the current month.
- Baseline snapshot retained for reference/undo and “what was originally planned.”

### Implementation Gaps to Close (from review)
- Persist updated `MonthlyPlan` records after recalculation (currently only in-memory requirements are updated).
- Hybrid calculation in `MonthlyExecutionViewModel`: closed months use baseline snapshot; active months use live `MonthlyPlan`.
- Baseline clarity: single `snapshot` remains immutable baseline; live data is the current plan (no regenerating the baseline).
