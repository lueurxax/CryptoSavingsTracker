# UI/UX Incremental Improvements Proposal

> Audit mapping: issues #4, #5, #6, #8

| Metadata | Value |
|---|---|
| Status | Draft |
| Last Updated | 2026-03-01 |
| Platform | iOS first, Android parity required |
| Scope | Copy clarity, row density, stale draft context, form feedback |

---

## 1) Goals

- Reduce financial copy confusion.
- Improve scanability in goal requirement rows.
- Make stale draft resolution understandable.
- Improve form validation feedback and save-error UX.

## 2) Workstream A — Financial Copy Clarity (issue #4)

### Problems

- Terms like `not applied`, `needs recalculation`, `close month` are internal and ambiguous.

### Proposal

- Introduce copy dictionary with user language:
  - `not applied` -> `Budget saved, not used for this month yet`
  - `needs recalculation` -> `Goals changed, review this plan`
  - `close month` -> `Finish this month`
- Add one-line explanation under each risk/health status.
- Ensure iOS and Android use the same copy keys.

## 3) Workstream B — Goal Requirement Row Simplification (issue #5)

### Problems

Rows contain too many elements and controls at once.

### Proposal

- Default row: only name, monthly amount, deadline risk, progress.
- Move lock/skip/custom amount actions into secondary sheet (`Adjust` button).
- Show details panel only on explicit expand; keep collapsed state lightweight.

## 4) Workstream C — Stale Draft Context (issue #6)

### Problems

Stale draft row may miss goal context and action consequences are not obvious.

### Proposal

- Always display goal name and month in each stale row.
- Add status chips:
  - `Unresolved`,
  - `Marked completed`,
  - `Marked skipped`.
- Add confirmation text for destructive delete with month + goal name.

## 5) Workstream D — Form Validation and Save Errors (issue #8)

### Problems

- Disabled save with unclear reason.
- Save failures are not surfaced as actionable errors.

### Proposal

- Inline validation under each failing field (not only global warning).
- Add sticky "What blocks save" summary near CTA.
- On save error: show alert with retry + diagnostics-safe message.

## 6) Delivery Plan

1. Shared copy table and keys.
2. Row simplification + adjustment sheet.
3. Stale draft contextual metadata rendering.
4. Form validation/error handling refactor.
5. Snapshot + UI tests (iOS + Android parity checklist).

## 7) Acceptance Criteria

- Users can identify required monthly action in a row within 3 seconds in UX test.
- No stale draft row rendered without goal name.
- Save errors are always visible to user (no silent fail path).
