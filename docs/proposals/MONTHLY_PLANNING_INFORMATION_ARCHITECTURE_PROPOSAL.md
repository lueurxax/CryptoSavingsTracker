# Monthly Planning Information Architecture Proposal

> Audit mapping: issue #2 (poor discoverability of monthly planning)

| Metadata | Value |
|---|---|
| Status | Draft |
| Last Updated | 2026-03-01 |
| Platform | iOS + Android |
| Scope | Navigation structure and entry points |

---

## 1) Problem

Monthly Planning is discoverable mostly via widgets and secondary navigation. Users do not perceive it as a core app capability.

## 2) Goal

Expose Monthly Planning as first-class navigation destination with clear entry and persistent affordance.

## 3) Proposed IA

Primary app navigation should include explicit top-level destinations:

1. Goals
2. Planning
3. Execution
4. Settings

Alternative (if keeping 2-level model):

- Keep `Planning` top-level.
- Inside planning, segment by mode:
  - `Plan`
  - `Track`

## 4) Entry Point Rules

- Never rely on collapsed widget as the only path.
- Empty states must include one clear CTA to planning.
- Goal detail can deep-link into planning, but does not replace top-level route.

## 5) Migration Strategy

1. Introduce explicit `Planning` tab/section in shared navigation model.
2. Keep existing widget link for backward familiarity.
3. Add telemetry for planning entry source:
   - top-level,
   - widget,
   - deep-link from goal.

## 6) QA and Success Metrics

- New users can reach planning in <=2 taps from app launch.
- Planning screen reach rate increases from baseline by >=20%.
- Decrease in support questions around "where planning is".
