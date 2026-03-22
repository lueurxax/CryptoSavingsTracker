# Consolidated Review

## 0. Review Mode and Evidence Summary
- Mode used: `full-review`
- Evidence completeness: `Complete`
- Review target:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md`
- Evidence baseline reused:
  - `/Users/user/Documents/CryptoSavingsTracker/artifacts/proposal-review/shared-goals-freshness-sync-r6/evidence-pack.md`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL_TRIAD_REVIEW_R6.md`
- Build/run baseline reused from same-day evidence pack:
  - `RUN-01`: Debug build succeeded for `CryptoSavingsTracker` on `iPhone 15` simulator, iOS 18.0
  - `RUN-01`: app launched successfully for seeded invitee scenarios
- Additional repo verification for this pass:
  - re-read the current proposal revision because it changed after `R6`
  - re-checked live implementation constraints in:
    - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/ExchangeRateService.swift`
    - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/FamilySharing/FamilyShareServices.swift`
    - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Utilities/NotificationNames.swift`
- Remaining blocker:
  - no live two-owner-device CloudKit trace was captured in this pass

## 1. Executive Summary
- Overall readiness: `Amber`
- Confidence: `Medium`
- Compared with `R6`, this draft closes several major blockers:
  - `contentHash` now covers invitee-visible root metadata
  - durable dirty-state persistence is now specified
  - `projectionServerTimestamp` migration now consistently defaults to `nil`
- The proposal still has five material spec issues:
  1. the ordering contract still defines two incompatible accept/reject algorithms
  2. the promised 5-minute rate-drift cadence still lacks a concrete active refresh driver
  3. provenance disclosure behavior is still contradictory across canonical sections, tests, and resolved questions
  4. VoiceOver wording is incomplete for rate-governed `materiallyOutdated`
  5. obsolete `Updated {time}` copy still survives in acceptance criteria

## 2. Findings

### ARCH-01
- Severity: `High`
- Confidence: `High`
- Evidence:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:677`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:681`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1594`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1599`
- Why it matters:
  - Section 6.8.2 says any differing `contentHash` is accepted unconditionally, which makes `projectionServerTimestamp` irrelevant for post-migration payloads. But the same document still describes the timestamp as the deciding freshness comparator when `Int` versions match. That leaves two incompatible ordering contracts in one proposal.
- Recommended fix:
  - Make one canonical ordering algorithm. Either `contentHash` is only dedup plus timestamp tiebreak, or `contentHash` is authoritative and the timestamp is explicitly pre-migration fallback only. The acceptance tests and prose need to say the same thing.
- Acceptance criteria:
  - There is exactly one invitee ordering algorithm in the document, and every test case matches it.

### ARCH-02
- Severity: `High`
- Confidence: `High`
- Evidence:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:247`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:259`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:758`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1382`
  - `/Users/user/Documents/CryptoSavingsTracker/ios/CryptoSavingsTracker/Services/ExchangeRateService.swift:12`
- Why it matters:
  - The proposal now treats `exchangeRatesDidRefresh` as if the 5-minute TTL itself guarantees a refresh every five minutes during long foreground sessions. But the proposed prerequisite only emits a notification after a successful fetch, and the live `ExchangeRateService` is still an on-demand cache/fetch service rather than a periodic refresher. Without a concrete foreground refresh driver, the only explicit guaranteed cadence in the spec is still the 15-minute guard.
- Recommended fix:
  - Add the component that actually requests rate refreshes during long foreground sessions, or weaken the SLA so it only promises reevaluation when a fetch is triggered by normal app activity.
- Acceptance criteria:
  - The proposal names the scheduler or trigger that causes rate fetches during long foreground sessions, and tests prove reevaluation cannot drift past the stated SLA.

### UX-01
- Severity: `High`
- Confidence: `High`
- Evidence:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:546`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:559`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1652`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1655`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1698`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1725`
- Why it matters:
  - The document still specifies provenance disclosure three different ways. Section 6.6 defines one canonical in-card disclosure pattern, the acceptance tests still expect `Tap for details`, and the resolved question still says exact timestamps are visible inline with no tap-through required. That guarantees implementation and test drift.
- Recommended fix:
  - Keep one canonical AX behavior and delete the other two formulations. If the final rule is in-card disclosure, remove every remaining `Tap for details` and `always inline, no tap-through` statement.
- Acceptance criteria:
  - A single provenance disclosure rule appears across the canonical section, delivery plan, tests, and resolved questions.

### UX-02
- Severity: `Medium`
- Confidence: `High`
- Evidence:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1103`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1162`
- Why it matters:
  - The visual grammar defines a rate-governed `materiallyOutdated` state, but the accessibility table only defines publish-governed VoiceOver wording for that tier. The highest-severity rate-stale case therefore has no canonical assistive phrasing.
- Recommended fix:
  - Add the rate-governed `materiallyOutdated` VoiceOver string explicitly and keep it aligned with the visible label grammar.
- Acceptance criteria:
  - The accessibility table covers both publish-governed and rate-governed wording for every tier that has distinct visual copy.

### UX-03
- Severity: `Medium`
- Confidence: `High`
- Evidence:
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:151`
  - `/Users/user/Documents/CryptoSavingsTracker/docs/proposals/SHARED_GOALS_FRESHNESS_SYNC_PROPOSAL.md:1525`
- Why it matters:
  - The canonical grammar now uses publish-governed `Shared ...` and rate-governed `Rates are ...`, but the UI-test inventory still asserts an `Updated {time}` header. That preserves a third wording contract inside the same proposal.
- Recommended fix:
  - Remove `Updated {time}` from the acceptance inventory and replace it with assertions against the canonical grammar model.
- Acceptance criteria:
  - No acceptance test or delivery-plan bullet references `Updated {time}` as supported shared-goals copy.

## 3. Closed Since R6
- `contentHash` now explicitly includes invitee-visible root metadata, including owner display name and participant data.
- `projectionServerTimestamp` migration now consistently defaults to `nil`.
- Durable dirty-state persistence is now specified via persisted dirty flags rather than memory-only pending state.

## 4. Recommended Next Pass
1. Unify the ordering contract in Section 6.8.2 and the acceptance tests.
2. Add the missing foreground rate-refresh driver or narrow the SLA language.
3. Delete stale provenance-copy variants so Section 6, Section 8, and Section 14 all say the same thing.
4. Finish the accessibility grammar by adding the missing rate-governed critical VoiceOver wording.
5. Remove the obsolete `Updated {time}` wording from the test inventory.
