# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `full-review`
- Evidence completeness: `Complete`
- Review target:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
- Evidence baseline reused:
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r6/evidence-pack.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_TRIAD_REVIEW_R7.md`
- Same-day runtime baseline reused:
  - `RUN-01` from the `R6` evidence pack: Debug build succeeded for `CryptoSavingsTracker` on `iPhone 15` simulator, iOS 18.0
  - seeded invitee scenarios still remain the runtime baseline for current shared-goals UI
- Additional verification for this pass:
  - re-read the latest proposal revision because it changed after `R7`
  - re-checked current shared-service constraints in:
    - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/ExchangeRateService.swift`
    - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/Protocols/ServiceProtocols.swift`
    - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/NotificationNames.swift`
- Remaining blocker:
  - no live two-owner-device CloudKit trace was captured in this pass

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `Medium`
- Compared with `R7`, the proposal is materially better:
  - the 5-minute cadence now has an explicit `FamilyShareForegroundRateRefreshDriver`
  - provenance disclosure is now internally consistent
  - rate-governed `materiallyOutdated` now has explicit VoiceOver wording
  - the obsolete `Updated {time}` acceptance-test wording is gone
- Remaining findings are narrower and mostly architectural:
  1. residual stale wording still leaves two competing version/ordering contracts in the doc
  2. the new foreground refresh driver depends on a shared-service API that is not actually scoped in the prerequisite surface
  3. the `Set Automatically` diagnostic requirement is still not tied to a concrete, testable implementation contract

## 2. Findings

### ARCH-01
- Severity: `High`
- Confidence: `High`
- Evidence:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:681`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:703`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:706`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1608`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1615`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1749`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1750`
- Why it matters:
  - The canonical ordering section now says `projectionServerTimestamp` is only a pre-migration fallback and is never consulted when `contentHash` is present. But the earlier test-coverage block still says invitee ordering uses `projectionServerTimestamp` when `Int` versions match, and a later resolved-question answer still says the clean separation is topology = `Int`, ordering = `Date`, dedup = hash. That leaves two different implementations "supported" by the same proposal.
- Recommended fix:
  - Align every tail section with the new canonical contract: `projectionServerTimestamp` is pre-migration fallback only, while `contentHash` is authoritative for post-migration accept/no-op behavior.
- Acceptance criteria:
  - No section, test plan, or resolved question says `projectionServerTimestamp` remains the normal freshness-ordering comparator once `contentHash` is present on both sides.

### ARCH-02
- Severity: `Medium`
- Confidence: `High`
- Evidence:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:259`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:260`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:865`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1308`
  - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/Protocols/ServiceProtocols.swift:35`
  - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/ExchangeRateService.swift:87`
- Why it matters:
  - The proposal now correctly introduces `FamilyShareForegroundRateRefreshDriver`, but it relies on `ExchangeRateService.refreshRatesIfStale()`. That API does not exist in the live `ExchangeRateServiceProtocol`, and the prerequisite list still scopes only the new notification, not the service/protocol change needed to let a shared driver invoke a no-op-safe refresh. This is now a hidden infrastructure dependency rather than an explicit prerequisite.
- Recommended fix:
  - Add the `refreshRatesIfStale()` contract, or equivalent shared-service entry point, to the prerequisite scope and to the protocol boundary that the driver will use.
- Acceptance criteria:
  - Phase 0 or Section 7.0 explicitly defines the shared-service API change required by the foreground refresh driver, including protocol impact and test seam expectations.

### ARCH-03
- Severity: `Medium`
- Confidence: `Medium`
- Evidence:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:528`
  - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/NotificationNames.swift:1`
  - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/ExchangeRateService.swift:1`
- Why it matters:
  - The clock-skew section still promises a diagnostic warning when `Settings > General > Date & Time > Set Automatically` is disabled, specifically via `NSSystemClockDidChangeNotification` observation. But the proposal does not define any concrete app-side mechanism for inferring that settings state, and the repo has no existing clock-change diagnostic surface to build from. As written, this reads like a product requirement without a testable implementation contract.
- Recommended fix:
  - Reframe this as best-effort skew telemetry based on observed timestamp anomalies, or cite the concrete supported mechanism the app will use to infer and test this setting-specific warning.
- Acceptance criteria:
  - The clock-skew diagnostics section either removes the unsupported setting-specific warning or defines a concrete, testable implementation contract for it.

## 3. Closed Since R7
- The proposal now includes an explicit `FamilyShareForegroundRateRefreshDriver`, so the prior 5-minute cadence finding is closed.
- Provenance disclosure is now consistent around the in-card disclosure-chevron rule.
- VoiceOver wording now covers rate-governed `materiallyOutdated`.
- The old `Updated {time}` acceptance-test wording has been replaced with canonical grammar.

## 4. Residual Evidence Gaps
- The runtime evidence pack still validates current-state seeded invitee surfaces, not proposal-specific final renders for the new freshness card/header in dark mode and large Dynamic Type.
- No live two-owner-device CloudKit trace was captured for the revised post-`R7` ordering contract.

## 5. Recommended Next Pass
1. Delete the stale version-ordering wording from test coverage and resolved questions.
2. Promote `ExchangeRateService.refreshRatesIfStale()` from implied dependency to explicit prerequisite API.
3. Simplify the clock-skew diagnostics section so every promised warning is tied to a real, testable implementation path.
