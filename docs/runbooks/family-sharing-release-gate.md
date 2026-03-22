# Family Sharing Release Gate

Operational release gate for `CloudKit Read-Only Family Sharing` on iPhone/iPad.

This runbook also gates the `Shared Goals Freshness Sync` rollout. Treat freshness regressions as trust regressions, not cosmetic issues.

## Rollout thresholds

Trigger rollback investigation immediately when any of the following are breached:

1. Rolling 6h `family_share_create_failed` rate exceeds `5.0%` with at least `100` create attempts.
2. Rolling 6h `family_share_accept_failed` rate exceeds `5.0%` with at least `100` accept attempts.
3. Rolling 24h `family_share_temporarily_unavailable` rate exceeds `10.0%` with at least `500` shared-goal opens.
4. Rolling 24h `family_share_namespace_migration_failed` count exceeds `10` unique namespaces.
5. Rolling 24h `family_share_publish_suppressed_stale_local` count exceeds `25` unique namespaces.
6. Rolling 24h `family_share_refresh_failed` rate exceeds `10.0%` with at least `250` refresh attempts.
7. Any sustained `family_share_clock_skew_detected` spike above `20` unique namespaces after a rollout.

## Pre-release gates

Before shipping or promoting the build:

1. `FamilyShareAcceptanceCoordinatorTests` must pass.
2. `PersistenceMutationServicesTests` must pass.
3. Freshness unit gates must pass:
   - `FamilyShareFreshnessLabelTests`
   - `FamilyShareFreshnessPolicyTests`
   - `FamilyShareForegroundRateRefreshDriverTests`
   - `FamilyShareInviteeRefreshSchedulerTests`
   - `FamilyShareRateDriftEvaluatorTests`
   - `FamilyShareReconciliationBarrierTests`
   - `FamilyShareProjectionAutoRepublishCoordinatorTests`
   - `FamilyShareInviteeOrderingTests`
   - `FamilyShareMaterialityPolicyTests`
   - `GoalProgressCalculatorTests`
4. Family-sharing redesign UI evidence must pass as deterministic per-test invocations, not as one class-level run:
   - `testSettingsShowsFamilyAccessBeforeLocalBridgeSync`
   - `testInviteeScenarioShowsSharedWithYouAndReadOnlyDetail`
   - `testInviteeScenarioShowsMultiOwnerGroupingAndStickyOwnerHeaders`
   - `testInviteeScenarioShowsNonActiveStateBannerAndPrimaryAction`
   - `testInviteeScenarioSuppressesBlockedDeviceOwnerLabels`
   - `testInviteeScenarioUsesLockedOwnershipLineAndSuppressesHealthyLifecycleChip`
   - `testScopePreviewKeepsPersistentCTAVisibleAtAccessibilitySize`
   - `testInviteeEmptyNamespaceShowsFreshnessHeaderButNoRows`
   - `testInviteeUnavailableNamespaceShowsRetryWithoutRows`
   - `testInviteeDetailFreshnessCardCollapsesExactTimestampAtAccessibilitySize`
5. Manual smoke on two Apple IDs must confirm:
   - owner can create a share from `Settings -> Family Access`,
   - invitee can accept and see `Shared with You`,
   - shared detail remains read-only,
   - invitee foreground refresh updates stale data after owner mutation,
   - invitee manual refresh can surface `Checked just now — no newer update yet`,
   - rate-driven freshness degrades to rate-governed copy when rates are old,
   - revoke or removal degrades into a reason-specific unavailable state.

## Stuck invite acceptance

Symptoms:

1. Invitee taps the share link but never sees `Shared Goals`.
2. Owner sees pending participant state that never changes.
3. Logs contain repeated `family_share_accept_failed` or invitee remains in `invite_pending`.

Response:

1. Confirm the invite was accepted on a different Apple ID than the owner.
2. Confirm the invitee app build contains the latest family-sharing fixes and relaunch the app once.
3. Check device logs for `family_share_accept_failed`; capture only redacted payloads.
4. Retry acceptance from the original share link once.
5. If still stuck, owner should `Stop Sharing` and create a fresh share from the current build.

## Shared root missing or projection cleanup failure

Symptoms:

1. Invitee sees `The shared projection root record could not be found`.
2. Owner share opens, but invitee list is empty after acceptance.
3. Cleanup or re-share leaves a stale namespace visible locally.

Response:

1. Verify owner re-created the share after the latest hierarchy fixes.
2. Confirm family-share records exist in the expected custom zone.
3. Run a manual invitee refresh once.
4. If the root is still missing, owner must `Stop Sharing`, then re-share.
5. If cleanup failure leaves stale data locally, purge the affected namespace on next successful refresh or app relaunch.

## Shared-database unavailable incident

Symptoms:

1. Invitee enters `temporarilyUnavailable`.
2. Logs emit `family_share_temporarily_unavailable` or `family_share_refresh_failed`.
3. Manual refresh does not restore data.

Response:

1. Check Apple system status for CloudKit availability.
2. Confirm the owner share still exists and was not revoked.
3. Retry refresh once after network recovers.
4. If CloudKit remains unavailable, keep the incident in degraded read-only posture and do not advise local destructive cleanup.

## Freshness incident triage

Symptoms:

1. Owner updates goals/assets, but invitee still sees old amounts or titles.
2. Invitee refresh succeeds but data remains unchanged.
3. Namespace header shows stale copy longer than the expected SLA.

Response:

1. Separate the failure domain first:
   - owner publish never happened,
   - publish happened but invitee fetch failed,
   - invitee fetched successfully but there was no newer projection,
   - rates are stale and now govern freshness.
2. Check telemetry in this order:
   - `family_share_auto_publish_requested`
   - `family_share_auto_publish_succeeded` or `family_share_auto_publish_failed`
   - `family_share_invitee_foreground_refresh_requested` / manual refresh trigger
   - `family_share_invitee_refresh_succeeded` or `family_share_invitee_refresh_failed`
   - `family_share_invitee_checked_no_new_data`
3. If owner-side publish is missing, inspect trigger ingress:
   - goal mutation
   - asset mutation
   - transaction mutation
   - import or repair
   - participant change
4. If publish is suppressed, capture redacted `family_share_publish_suppressed_stale_local` and `family_share_reconciliation_barrier_waited` payloads.
5. If invitee refresh succeeds with no new data, do not classify as a fetch failure. It means the owner has not published a newer semantic snapshot yet.

## Rate-drift incident

Symptoms:

1. Invitee values drift materially from owner-expected amounts without a recent explicit goal edit.
2. Freshness header says rates are stale, or values remain unchanged after a long foreground owner session.

Response:

1. Check whether the owner foreground session started the rate driver.
2. Inspect:
   - `family_share_rate_drift_evaluated`
   - `family_share_rate_drift_below_threshold`
   - `family_share_rate_snapshot_age_at_publish`
3. If rates refreshed but no publish followed, confirm the materiality threshold did not suppress a semantically meaningful change.
4. If the guard timer path fired, verify no namespace exceeded the 5-minute TTL without an evaluation attempt.

## Clock-skew diagnostics

Symptoms:

1. Freshness labels show impossible future or excessively old timestamps.
2. Telemetry emits `family_share_clock_skew_detected`.

Response:

1. Capture the redacted namespace and `timestampSource`.
2. Distinguish minor tolerance behavior from real skew:
   - under 60 seconds future skew is tolerated and should not page,
   - repeated future timestamps beyond tolerance are actionable.
3. Treat clock-skew spikes as telemetry/diagnostic incidents first, not as a reason to mutate or purge shared data.

## Namespace corruption, migration failure, or rebuild

Symptoms:

1. Logs emit `family_share_namespace_migration_failed`.
2. A namespace enters quarantine or rebuild.
3. Invitee sees unavailable state immediately after upgrade.

Response:

1. Confirm the app version and cache schema version involved.
2. Capture the redacted namespace identifier and coarse reason code.
3. Allow one rebuild attempt from CloudKit shared data.
4. If rebuild succeeds, verify the namespace returns to `active` or the correct empty state.
5. If rebuild fails again, keep the namespace fail-closed and escalate with the redacted namespace identifier.

## Rollback teardown verification

Symptoms:

1. Rollout flag is disabled but freshness timers or observer-driven publishes continue.
2. Invitee UI flashes into a new error state immediately after disablement.

Response:

1. Verify one and only one `family_share_freshness_rollback` event for the disable transition.
2. Confirm the rollback payload contains discarded dirty-event and active-timer counts.
3. Confirm cached invitee UI remains stable after disablement; it must not flash or clear.
4. If new auto-publishes or refresh timers still fire after disablement, treat it as release-blocking.

## Revoked share still visible locally

Symptoms:

1. Owner revoked access, but invitee still sees old goals.
2. Refresh leaves the section visible as active instead of revoked or removed.

Response:

1. Trigger invitee refresh from `Shared Goals`.
2. Relaunch the app once to force namespace reload.
3. If the root is gone, expect `removedOrNoLongerShared`.
4. If permissions are gone but metadata remains, expect `revoked`.
5. Any stale active state after successful refresh is a release-blocking regression.

## Rollback posture

1. Kill-switch semantics are unchanged in this release train; disabling the entry point only blocks new entry.
2. Existing accepted shares must be evaluated against the current release behavior before deciding on rollback.
3. If thresholds remain breached after entry-point disablement, prepare and ship a hotfix.
4. Capture only redacted namespace identifiers, lifecycle states, and coarse reason codes in incident notes.
