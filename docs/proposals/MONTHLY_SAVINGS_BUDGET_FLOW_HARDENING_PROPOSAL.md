# Monthly Savings Budget Flow Hardening Proposal

> Goal: remove precision confusion, stabilize Save behavior, and make the Budget Plan sheet professional, harmonious, and trustworthy.

| Metadata | Value |
|----------|-------|
| Status | Ready for Implementation |
| Last Updated | 2026-03-01 |
| Platform | iOS |
| Scope | Budget Plan sheet (`Monthly Savings Budget` flow) |

---

## 1) Problem Summary

Users can hit a trust-breaking state where:

- Entered budget looks equal to `Use Minimum` (or visually equal after rounding).
- Save remains disabled.
- Editing "insignificant" characters (for example adding `0`) suddenly changes eligibility.

This makes financial outcomes feel random. For money flows, that is unacceptable.

---

## 2) Consolidated Issue Inventory (Current Code)

### A. Precision mismatches (P0)

1. Displayed minimum can hide precision while validation uses exact floating-point values.
2. Equality tolerance differs across feasibility/leveling/shortfall checks.
3. `Double` is used as the effective money type in critical gating paths.

### B. Input and locale gaps (P0)

4. Parser is not locale-safe (`.` only path).
5. String formatting is hard-coded in places (`String(format: "%.2f", ...)`), bypassing locale and currency rules.
6. Paste behavior is undefined for symbols/grouping/non-breaking spaces.

### C. Async determinism gaps (P1)

7. Each edit starts a new `Task` without explicit cancel/debounce policy.
8. Feasibility and schedule are computed separately, so UI can combine mixed snapshots.
9. Latest-wins behavior is not formally enforced by request identity.

### D. UX/state clarity gaps (P1)

10. Disabled Save reasons are generic and sometimes not numerically explicit.
11. No strict finite-state contract for invalid/calculating/blocked states.
12. Keyboard completion/focus transitions are not explicitly specified.

### E. Visual consistency gaps (P2)

13. Raw colors are still used in this sheet.
14. No explicit token mapping table by element.

---

## 3) Product Requirements

1. If UI shows `Minimum required: X`, entering `X` must always be accepted under the same rounding policy.
2. Save eligibility must be deterministic and never depend on hidden sub-cent precision.
3. All user-visible states must have one clear reason string.
4. Locale input and paste must behave predictably.
5. UI must align with planning design tokens in light and dark mode.
6. Async calculations must be latest-input deterministic.

---

## 4) Proposed Solution

### 4.1 Domain money boundary (mandatory)

Introduce a domain type boundary and stop using raw `Double` for gating decisions.

```swift
struct MoneyAmount: Equatable {
    let value: Decimal
    let currency: String
}
```

Rules:

- All comparisons in this flow use `MoneyAmount`.
- Canonicalization occurs immediately after parse and after every service result.
- `Double` may exist only at external adapters (legacy APIs, chart display), never in feasibility/save-gating logic.

New utility:

- `MoneyQuantizer` in `Utilities`:
  - `minorUnits(for currency: String) -> Int`
  - `normalize(_ value: Decimal, currency: String, mode: RoundingMode) -> MoneyAmount`
  - `compare(_ lhs: MoneyAmount, _ rhs: MoneyAmount) -> ComparisonResult`
  - `difference(_ lhs: MoneyAmount, _ rhs: MoneyAmount) -> MoneyAmount`

Currency minor-unit policy for v1:

- `USD/EUR/GBP`: 2
- `JPY/KRW`: 0
- `KWD/BHD/OMR`: 3 (enabled only when present in app-supported fiat list)
- fallback: ISO-4217 metadata default, then 2

### 4.2 One-pass computation snapshot API

Replace split feasibility/schedule calls with one atomic call:

```swift
BudgetComputationResult computeBudgetSnapshot(
    requestId: UUID,
    enteredBudget: MoneyAmount,
    goalsSignature: String,
    rateSnapshotId: String?
)
```

Result shape:

- `requestId`
- `enteredBudgetCanonical`
- `minimumRequiredCanonical`
- `isFeasible`
- `shortfallCanonical`
- `plan`
- `timeline`
- `rateSnapshotTimestamp`
- `rateSnapshotId`
- `state` (`readyFeasible` | `blockedInfeasible` | `blockedRates`)

Contract:

- ViewModel applies results only when `result.requestId == latestRequestId`.
- Feasibility + plan + timeline come from the same snapshot.

Deterministic key contract:

- `goalsSignature` generation:
  - sort goals by `goalId` ascending
  - canonical goal item: `goalId|currency|targetCanonical|deadlineISO8601|isSkipped`
  - join with `;`
  - hash as `SHA256(utf8(canonicalString))`
- `rateSnapshotId` generation:
  - canonical rate item: `from->to=rateCanonical@timestampISO8601`
  - sort canonical rate items ascending
  - join with `;`
  - hash as `SHA256(utf8(canonicalRatesString))`
- Locale must not affect canonical serialization.

### 4.3 Deterministic async policy

- Debounce input edits by 300ms.
- Cancel previous compute task before starting next.
- Maintain `latestRequestId`.
- Ignore stale results.
- Keep last stable result visible during recalculation.

### 4.4 Input/focus/parser specification

State model:

- `budgetRawText`
- `budgetParsed` (`MoneyAmount?`)
- `budgetCanonicalDisplayText`

Parser behavior:

| Input Pattern | Behavior |
|---|---|
| Currency symbol (`$2,500.50`) | Strip symbol, parse number |
| Group separators (`2,500.50`, `2 500,50`) | Normalize via locale-aware parser |
| Non-breaking spaces | Normalize and parse |
| Ambiguous separators (`2.500,50` under unexpected locale) | Fail with explicit validation message |
| More fraction digits than allowed | Canonicalize by currency rule and show helper |

Parser failure copy catalog (standardized):

| Failure Class | Copy | Recovery Example |
|---|---|---|
| Invalid number format | `Enter a valid amount.` | `Example: 2500.50` |
| Ambiguous separators | `Couldn't read this amount for your locale.` | `Use 2,500.50 or 2500.50` |
| Too many decimal digits | `Too many decimal places for this currency.` | `Use max {minorUnits} decimals` |
| Unsupported characters | `Remove unsupported characters and try again.` | `Keep only amount and separators` |

Focus/keyboard behavior:

- Decimal pad includes accessory `Done`.
- Tapping `Done` dismisses keyboard and keeps current parsed state.
- No aggressive reformat while typing.
- Normalize display on:
  - focus loss,
  - `Done`,
  - `Use Minimum` tap.

Touch/accessibility baseline:

- All actionable controls meet 44x44pt minimum.

### 4.5 Explicit UI state machine

| UI State | Save | Primary Status | Helper / Reason | Primary Action |
|---|---|---|---|---|
| `invalidInput` | Disabled | Invalid amount | `Enter a valid amount` | None |
| `calculatingLatest` | Disabled | Calculating | `Calculating latest amount...` | None |
| `readyFeasible` | Enabled | On track | `All deadlines achievable` | Save |
| `blockedInfeasible` | Disabled | At risk | `Short by X. Tap Use Minimum or increase budget.` | `Use Minimum` |
| `blockedRates` | Disabled | Rates unavailable | `Rates unavailable for conversion. Refresh rates to validate this budget.` | `Refresh Rates` |

Rule: Save cannot be disabled without a visible reason string.

`blockedRates` policy (locked for v1):

- Hard-block Save for mixed-currency budgets when required rates are missing or stale beyond freshness policy.
- No override in v1.

State-region layout stability contract:

- Status/reason/action region uses fixed container.
- Minimum height: `132pt` on compact iPhone.
- Transition behavior:
  - cross-fade (`.opacity`) for content changes
  - avoid structural insert/remove that shifts surrounding layout
- Allowed vertical movement during state transition: <= 8pt.

### 4.6 Visual token mapping (sheet-level)

All sheet elements must use semantic tokens (no raw color literals).

| Element | Token / Style |
|---|---|
| Status icon feasible | `AccessibleColors.success` |
| Status icon warning | `AccessibleColors.warning` |
| Status icon blocked/error | `AccessibleColors.error` |
| Primary CTA tint | `AccessibleColors.primaryInteractive` (feasible) / state tone when blocked action is primary |
| Disabled reason text | `.secondary` or state semantic token (no raw `.orange`) |
| Informational strip background | `.regularMaterial` + baseline stroke |
| Timeline accents | fixed semantic palette from design token set (not raw hardcoded colors) |
| Card/sheet subcontainers | `.regularMaterial` or semantic grouped background + 12 radius |

Visual hierarchy:

- Show numeric shortfall and one corrective action before detailed goal list.
- Affected-goal list is collapsed by default (`Show affected goals (N)`).

### 4.7 Canonical save-gating policy

`canApply` is true only when all are true:

1. `latestSnapshot.requestId == latestRequestId`
2. `latestSnapshot.state == .readyFeasible`
3. Parsed and canonical amount is valid for selected currency
4. Apply action not in progress

No gating by stale loading flags or stale snapshots.

### 4.8 Cache and equality policy

- Cache key uses canonical integer minor units:
  - `(goalSignature, currency, amountMinorUnits, rateSnapshotId)`
- Remove fixed `0.01` epsilon checks from feasibility/save code paths.
- Currency-aware tolerance derives strictly from minor units.

### 4.9 Phased `MoneyAmount` migration plan

Phase 0 (adapter boundary, no behavior change):

- Introduce `MoneyAmount` and `MoneyQuantizer`.
- Add explicit adapters at boundaries only.

Phase 1 (sheet + ViewModel migration):

- Move parse/canonical/gating in budget sheet and ViewModel to `MoneyAmount`.
- Keep service internals bridged through temporary adapters.

Phase 2 (service migration):

- Refactor `BudgetCalculatorService` feasibility/comparison/cache to `MoneyAmount`.
- Remove fixed epsilon usage in migrated paths.

Phase 3 (cleanup/enforcement):

- Remove temporary adapters from core paths.
- Add regression check to prevent raw `Double` gating in this flow.

---

## 5) Verification Matrix

### 5.1 Locale x Currency trust matrix (mandatory)

| Locale | Currency | Minor Units | Input Example | Expected |
|---|---|---:|---|---|
| `en_US` | USD | 2 | `2500.00` | Equals minimum when shown, Save enabled |
| `de_DE` | EUR | 2 | `2500,00` | Parsed correctly, same gating as display |
| `ja_JP` | JPY | 0 | `2500` | No fractional UI, deterministic save gating |
| `ar_KW` (or supported equivalent) | KWD | 3 | `2500.001` | 3-decimal precision honored when currency is enabled |

### 5.2 Edge flows

1. Exact minimum.
2. Minimum minus one minor unit.
3. Minimum plus one minor unit.
4. Mixed-currency with stale rates.
5. Paste with symbols and grouping.
6. Fast typing causing out-of-order async completions.

---

## 6) Test Plan

### Unit tests

1. `MoneyQuantizer` normalization/comparison by minor units.
2. Parser normalization for locale/paste edge cases.
3. Snapshot latest-wins application (stale results ignored).
4. Cache key behavior across USD/JPY/KWD precision.
5. No raw `Double` epsilon gating in feasibility/save paths.
6. Deterministic `goalsSignature`/`rateSnapshotId` generation across locales.

### UI tests

1. Reproduce reported mismatch bug and assert fixed behavior.
2. `Use Minimum` always transitions to `readyFeasible` when rates are valid.
3. Disabled Save always shows explicit reason message.
4. Keyboard Done closes keyboard and keeps controls visible.
5. Dark mode and Dynamic Type snapshots for all core states.
6. VoiceOver flow reads status + reason + action coherently.
7. Reduce Motion does not introduce hidden/ambiguous state transitions.
8. State transitions keep vertical movement <= 8pt.

---

## 7) Rollout, Telemetry, and Rollback

1. Implement domain money boundary and snapshot API.
2. Ship behind internal runtime flag for dogfood.
3. Run matrix tests and screenshot QA signoff.
4. Enable for 10% internal/TestFlight cohort.
5. Expand after thresholds remain healthy for 7 days.

Runtime evidence gate:

- If workspace is not build-green, runtime screenshot signoff is blocked and rollout cannot expand.
- Required fresh captures before expansion:
  - `invalidInput`, `calculatingLatest`, `readyFeasible`, `blockedInfeasible`, `blockedRates`
  - light and dark mode
  - compact iPhone with keyboard open

Telemetry (required):

- `budget_snapshot_stale_result_dropped`
- `budget_parse_failure`
- `budget_parse_failure_type`
- `budget_save_blocked_reason_shown`
- `budget_use_minimum_tap`
- `budget_blocked_rates_impression`
- `budget_display_validation_mismatch_detected` (must remain zero)

Go/No-Go thresholds:

- `budget_display_validation_mismatch_detected > 0` in rollout cohort => stop rollout.
- parse failure rate > 1% of budget edits => hold rollout.
- stale result drop rate > 5% with user-visible flicker reports => hold and investigate.

Rollback playbook:

1. Disable hardening flag.
2. Revert to previous stable budget sheet behavior.
3. Keep telemetry active to capture repro context.
4. Assign owner and hotfix ETA within 24h.

Stop/Go owner:

- Single accountable owner: iOS Tech Lead (Monthly Planning area).
- Product manager is required approver for expand-to-100% decision.

---

## 8) Acceptance Criteria

1. No case where displayed minimum equals entered amount but Save is disabled.
2. No raw color literals in modified budget sheet files.
3. Save is never disabled without explicit reason copy.
4. Locale/currency matrix passes for supported minor-unit variants.
5. Out-of-order async responses cannot overwrite latest state.
6. `Use Minimum` reliably yields a feasible canonical amount (when rates are available).
7. Keyboard completion and focus behavior are deterministic and test-covered.
8. `blockedRates` hard-block policy is enforced and test-covered.
9. State transitions keep layout movement within <= 8pt in compact layout.
10. `goalsSignature` and `rateSnapshotId` determinism tests pass across locales.

---

## 9) Files Expected to Change (Implementation Phase)

- `ios/CryptoSavingsTracker/Views/Planning/BudgetCalculatorSheet.swift`
- `ios/CryptoSavingsTracker/ViewModels/MonthlyPlanningViewModel.swift`
- `ios/CryptoSavingsTracker/Services/BudgetCalculatorService.swift`
- `ios/CryptoSavingsTracker/Models/BudgetCalculatorModels.swift`
- `ios/CryptoSavingsTracker/Utilities/CurrencyFormatter.swift`
- `ios/CryptoSavingsTracker/Utilities/` (new `MoneyQuantizer` + money domain support)
- `ios/CryptoSavingsTrackerUITests/MonthlyPlanningUITests.swift`
- `ios/CryptoSavingsTrackerTests/` (precision/locale/ordering/cache tests)

---

## 10) Locked Decisions

1. `blockedRates` is hard-block (no override) in v1.
2. Stop/go owner is iOS Tech Lead (Monthly Planning area), with Product approval for full rollout.
3. 3-decimal currencies are enabled when present in app-supported fiat list; otherwise hidden in this flow.

---

## 11) Review Questions Closure (R1 + R2)

All review open questions are now explicitly closed for v1.

| Question | Final Answer | Enforcement Point |
|---|---|---|
| Is KWD/BHD/OMR support confirmed in the actual enabled fiat list? | Source of truth is runtime fiat list from `CoinGeckoService.supportedCurrencies` filtered by ISO fiat in `SearchableCurrencyPicker`. As of 2026-03-01 endpoint check: `KWD=true`, `BHD=true`, `OMR=false`. v1 enables 3-decimal handling only for currencies present in that list at runtime. | `4.1` minor-unit policy + `10.3` locked decision |
| For stale rates, allow override or fully block? | Fully block in v1. No override path. Save stays disabled until rates are refreshed and snapshot is valid. | `4.5` state machine + `10.1` locked decision + tests `6.2`, `8.8` |
| Who is single accountable stop/go owner? | iOS Tech Lead (Monthly Planning area). Product manager is required approver for 100% rollout expansion. | `7` rollout ownership + `10.2` locked decision |
| What mismatch threshold triggers rollback? | Any non-zero `budget_display_validation_mismatch_detected` in rollout cohort is an immediate stop/rollback trigger. | `7` go/no-go thresholds |

Closure rule for this proposal:

- No unresolved product/architecture questions remain for v1 scope.
- Any new question discovered during implementation must be logged as a change request and cannot silently alter locked decisions above.
