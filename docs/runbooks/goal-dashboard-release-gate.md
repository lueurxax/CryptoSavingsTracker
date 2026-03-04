# Goal Dashboard Release Gate

## Purpose

Operational gate for `Goal Dashboard v2` rollout and rollback.

## Rollback thresholds (authoritative mirror)

Use the same thresholds defined in `docs/proposals/GOAL_DASHBOARD_REDESIGN_PROPOSAL.md` section `8.3`:

1. Crash-free rate delta <= `-0.30` percentage points vs previous stable release over rolling `24h` window with at least `2,000` dashboard sessions.
2. Duplicate-load rate > `0.50%` over rolling `6h` window with at least `500` dashboard opens.
3. CTA resolver mismatch rate > `1.00%` in QA scenario suite for `2` consecutive runs.

## Artifact prerequisites before CI dependency activation

1. `shared-test-fixtures/goal-dashboard/schemas/goal_dashboard_scene_model.v1.schema.json`
2. `shared-test-fixtures/goal-dashboard/schemas/goal_dashboard_parity.v1.schema.json`
3. `shared-test-fixtures/goal-dashboard/goal_dashboard_parity.v1.json`
4. `shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_scene_model.v1.json`
5. `shared-test-fixtures/goal-dashboard/fixtures/goal_dashboard_wire_roundtrip.v1.json`

## Validation checklist

1. Schema validation passes for scene fixture.
2. Wire-format round-trip tests pass for decimal/date fixtures.
3. iOS and Android parity checks pass against shared parity artifact.
4. Runtime snapshot suite passes for all dashboard module states.
5. Preview instability does not block release if runtime suite is green.

## Hotfix-only rollback drill (normative)

Trigger rollback immediately when any threshold from section `Rollback thresholds` is breached.

1. Prepare hotfix branch from last stable release baseline.
2. Revert dashboard rollout commits in the hotfix branch (no runtime feature-toggle fallback).
3. Run canonical route smoke suite:
   - Android: `GoalDetail -> goal/{goalId}/dashboard`,
   - iOS: `GoalDetail -> GoalDashboardScreen`.
4. Validate post-hotfix data integrity:
   - goal, asset, transaction records remain consistent,
   - no schema migration regressions.
5. Verify production graph has no runtime rollback path:
   - no `goal_dashboard_v2_enabled` route switch logic,
   - no legacy goal dashboard route reintroduced.
6. Publish rollback drill artifact:
   - `artifacts/visual-system/rollback-drill-report.json`.

## CI rollback drill artifact gates

1. `rollback-drill-report` must validate against `docs/design/schemas/visual-rollback-drill-report.schema.json`.
2. Threshold breach simulation must be present and marked as executed.
3. CI fails if rollback artifact is missing, invalid, or does not prove hotfix-only path.
