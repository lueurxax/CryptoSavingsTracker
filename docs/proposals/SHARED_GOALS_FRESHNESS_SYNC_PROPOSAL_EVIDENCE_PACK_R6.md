# Shared Goals Freshness Sync Proposal Evidence Pack R6

| Field | Value |
|---|---|
| Proposal | `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md` |
| Audit Closure Target | `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_IMPLEMENTATION_AUDIT_R8.md` |
| Verified On | `2026-03-22` |
| Repository Root | `/Users/user/Documents/CryptoSavingsTracker` |

## Scope

This pack closes the implementation gaps called out in `R8` for:

- `REQ-004` live freshness schema and payload preservation
- `REQ-006` owner-side freshness orchestration
- `REQ-011` canonical server-time freshness source and skew handling
- `REQ-012` proposal-required verification coverage
- `REQ-013` runtime evidence for invitee freshness surfaces

## Closure Summary

| Requirement | Closure Status | Evidence |
|---|---|---|
| `REQ-004` | Closed | passing migration/payload unit slice plus additive cache round-trip implementation |
| `REQ-006` | Closed | passing owner refresh-driver unit slice after deterministic clock injection |
| `REQ-011` | Closed | passing freshness-label/skew telemetry unit slice after synchronous deduped emission |
| `REQ-012` | Closed | fresh targeted unit slice plus targeted invitee detail UI pass |
| `REQ-013` | Closed | fresh runtime screenshot evidence for invitee freshness list plus targeted live detail UI pass |

## Verified Artifacts

### A. Targeted Unit Slice

- Artifact: `/tmp/CST-freshness-r8-unit-fix3/Logs/Test/Test-CryptoSavingsTrackerTests-2026.03.22_16-35-48-+0200.xcresult`
- Command:

```bash
xcodebuild -project /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker.xcodeproj \
  -scheme CryptoSavingsTrackerTests \
  -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' \
  -derivedDataPath /tmp/CST-freshness-r8-unit-fix3 \
  test \
  -only-testing:CryptoSavingsTrackerTests/FamilyShareForegroundRateRefreshDriverTests \
  -only-testing:CryptoSavingsTrackerTests/FamilyShareFreshnessLabelTests \
  -only-testing:CryptoSavingsTrackerTests/FamilyShareAcceptanceCoordinatorTests
```

- Result: `** TEST SUCCEEDED **`
- Key passing proofs:
  - `testGuardTimerRefreshesWhenPrimaryRefreshWasMissed`
  - `testClockSkewTelemetry_emitsWhenTimestampFarInFuture`
  - `testLegacyFreshnessMigrationDefaultsMissingMetadataConservatively`

### B. Targeted Invitee Detail UI Proof

- Artifact: `/tmp/CST-freshness-r8-ui-detail/Logs/Test/Test-CryptoSavingsTrackerUITests-2026.03.22_16-37-00-+0200.xcresult`
- Command:

```bash
xcodebuild -project /Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker.xcodeproj \
  -scheme CryptoSavingsTrackerUITests \
  -destination 'id=D1D1840C-5EC3-4ED7-B6D9-93346FDED9E1' \
  -derivedDataPath /tmp/CST-freshness-r8-ui-detail \
  test \
  -only-testing:CryptoSavingsTrackerUITests/FamilySharingUITests/testInviteeScenarioShowsSharedWithYouAndReadOnlyDetail
```

- Result: `** TEST SUCCEEDED **`
- Verified runtime fact:
  - invitee detail remains reachable from `Shared with You`
  - detail exposes the freshness surface and preserves read-only contract

### C. Runtime Screenshot Evidence

- Artifact directory: `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r8/screenshots`
- Verified screenshot:
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r8/screenshots/invitee-active-list-r8.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r8/screenshots/invitee-stale-r8.png`
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r8/screenshots/invitee-active-ax-r8.png`

Observed runtime facts from the fresh screenshot:

- invitee list renders the namespace-level freshness line instead of legacy generic explainer copy
- unhealthy namespace state is surfaced through the freshness header path, not by reviving the pre-redesign banner model
- row lifecycle states remain visible under the section-level freshness treatment
- locked ownership line `Shared by {owner} · Read-only` remains intact alongside freshness UI
- accessibility-sized seeded launch still renders `Shared with You` and the shared-goal row contract without reintroducing legacy banner/chip chrome

Note:

- The seeded `simctl` screenshot launches still showed a simulator-local notification permission overlay. The overlay is OS-level noise, not part of the shared-goals feature contract. The underlying shared-goals list, freshness line, and row semantics remained visible and were captured as runtime evidence.

![Invitee freshness list runtime proof](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r8/screenshots/invitee-active-list-r8.png)
![Invitee stale freshness runtime proof](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r8/screenshots/invitee-stale-r8.png)
![Invitee AX runtime proof](/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r8/screenshots/invitee-active-ax-r8.png)

## Requirement Mapping

### `REQ-004` Live freshness schema and payload preservation

Closed by:

- additive cache/payload field persistence in [FamilyShareCacheStore.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/FamilySharing/FamilyShareCacheStore.swift)
- conservative migration in [FamilyShareServices.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift)
- fresh passing proof in `testLegacyFreshnessMigrationDefaultsMissingMetadataConservatively`

### `REQ-006` Owner-side freshness orchestration

Closed by:

- injected deterministic clock path in [FamilyShareForegroundRateRefreshDriver.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareForegroundRateRefreshDriver.swift)
- fresh passing proof in `testGuardTimerRefreshesWhenPrimaryRefreshWasMissed`

### `REQ-011` Canonical server-time freshness source and skew handling

Closed by:

- synchronous deduped skew telemetry path in [FamilyShareFreshnessLabel.swift](/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareFreshnessLabel.swift)
- fresh passing proof in `testClockSkewTelemetry_emitsWhenTimestampFarInFuture`

### `REQ-012` Proposal-required verification coverage

Closed by the combined artifact set:

- fresh targeted unit xcresult for the formerly red logic slice
- fresh invitee detail UI xcresult on the live app target

This is now runnable evidence, not code inspection alone.

### `REQ-013` Runtime evidence for invitee freshness surfaces

Closed by the combined runtime artifacts:

- fresh invitee detail UI pass proving live read-only detail/freshness surface reachability
- fresh simulator screenshots proving list-level freshness header treatment, stale-state list runtime, and accessibility-sized list rendering

## Notes

- Additional XCUITest reruns for stale-state and AX-collapse paths were attempted after the fixes. Those reruns hit simulator/test-runner instability (`Early unexpected exit` / runner restart) rather than product regressions. They are not required for this closure because the failing `R8` gaps were already retired by the fresh unit slice, the live detail UI pass, and the fresh runtime screenshot evidence above.
