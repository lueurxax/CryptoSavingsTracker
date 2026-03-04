# Visual System Rollback Runbook

## Scope

Rollback procedure for `visual_system.wave1_planning`, `visual_system.wave2_dashboard`, `visual_system.wave3_settings`.

## Trigger Conditions

1. Release-blocking visual regression confirmed by QA or production telemetry.
2. Accessibility regression on release-blocking flows.
3. Snapshot drift with broken semantics (warning/error ambiguity).

## Steps

1. Confirm incident severity (`sev3`, `sev2`, `sev1`) and assign incident owner.
2. Disable affected wave flag(s) through remote config.
3. Verify fallback rendering on release-blocking flows:
   - Planning,
   - Dashboard,
   - Settings critical rows.
4. Validate user-visible semantics:
   - warning/error distinction preserved,
   - non-color cue still present,
   - explanatory copy remains visible.
5. Publish incident update with ETA for fix-forward.

## SLA

- Flag disable target: <= 1 business day after confirmed regression.
- `sev1` response target: <= 30 minutes.

## Communication Ownership

| Severity | Channel | Owner | Backup |
|---|---|---|---|
| `sev1` | In-app banner + release notes + support macro | Product Manager | Support Lead |
| `sev2` | Release notes + support macro | Product Manager | Support Lead |

Escalation template binding:

- GitHub issue template: `.github/ISSUE_TEMPLATE/visual-system-rollback.yml`
- `SEV1/SEV2` incidents must complete the `User Communication` block before closure.

## Incident Communication Templates

### SEV1 User Communication Template

Trigger: confirmed production-impacting visual regression on release-blocking finance flow.

Template:

> We identified a visual issue affecting parts of planning/dashboard/settings. Your data and transactions are safe. We reverted the affected visual update and are preparing a verified fix. If something still looks incorrect, contact support and mention code `VSU-SEV1`.

### SEV2 User Communication Template

Trigger: blocking visual regression caught before broad rollout or in limited exposure cohort.

Template:

> We rolled back a recent visual update to keep planning and dashboard behavior consistent. No financial data was affected. We will re-enable the update after additional validation.

## Evidence Required

1. Before/after screenshots.
2. Gate failure links.
3. Telemetry marker `vsu_wave_rollback_completed`.

## Exit Criteria

1. Regression no longer reproducible on release-blocking flows.
2. Accessibility checks pass.
3. Snapshot checks pass.
4. Incident postmortem includes prevention action.
