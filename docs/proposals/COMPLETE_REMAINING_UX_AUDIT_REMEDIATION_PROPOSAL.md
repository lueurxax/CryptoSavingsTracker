# Complete Remaining UX Audit Remediation for CryptoSavingsTracker iOS

Status: Approved (Revision 4)
Approved at: 2026-04-18
Platform: iOS
Scope boundary date: 2026-04-04
Run ID: 9318de0d-9c75-40ad-9d0a-74c3610b021d

## Executive Summary

This r4 proposal incorporates the third proposal-review pass. The r2 command-matrix blocker is confirmed resolved, and the sole r3 blocker, UX-ISSUE-03, is explicitly classified as an implementation gap already covered by Wave 4. This revision makes the boundary unambiguous: the current Settings implementation must not ship to public MVP until `SettingsSyncSharingGateway` is implemented against `HiddenRuntimeMode` and public MVP Settings no longer exposes or instantiates Family Access or Local Bridge Sync.

## Problem

The approved UX audit remediation program is partially implemented, but closeout cannot proceed until the remaining public-MVP containment, evidence, and regression-test gaps are resolved.

### User Impact
- **Wave 2**: Protects users from losing entered financial data when a transaction save fails.
- **Wave 3**: Protects setup trust by preventing recoverable goal-template creation failures from being treated as completed onboarding.
- **Wave 4**: Protects public MVP users from seeing family-sharing or local bridge entry points before those trust-sensitive surfaces have passed a release gate.

## Goals

- Close all known P0 and P1 code gaps inside the approved 2026-04-04 iOS remediation scope.
- Keep public Apple MVP runtime behavior aligned with the current containment baseline: Family Access and Local Bridge Sync remain hidden until a separate release decision.
- Make W4-02 evidence executable by using the correct project, schemes, destinations, and per-test selectors (iPhone 16).
- Implement `SettingsSyncSharingGateway` as an explicit implementation gate: public MVP builds must not ship until it hides and avoids constructing Sync & Sharing destinations in `publicMVP` mode.
- Define Wave 4 runtime eligibility clearly using `HiddenRuntimeMode`.
- Preserve recovery and retry paths for empty states, failed transaction saves, and onboarding failures.

## Non-Goals

- Android remediation.
- New top-level navigation or information architecture.
- Public launch of Family Access or Local Bridge Sync in the Apple MVP build.
- CloudKit truth-model changes.
- Persistence schema redesign.

## Architecture and Implementation Approach

### Wave 2: Goals and Goal Detail
- **Implemented**: Zero-transaction empty state, context menus for actions, `AddTransactionView` input preservation on save failure.
- **New Work**: Deterministic save-failure seam using `TransactionMutationServiceProtocol`, `AdaptiveSummaryRow` for 320pt fallback, and `ErrorBannerView` for balance refresh failures.

### Wave 3: Onboarding
- **Implemented**: Completion committed only after successful goal creation or explicit skip; retry preserves step progress.
- **Acceptance**: Happy-path onboarding completes; injected recoverable failures expose retry without restart.

### Wave 4: Settings and Family Access
- **Runtime Boundary**: Separate `publicMVP` and `debugInternal` modes.
- **SettingsSyncSharingGateway**: Gates visibility and service instantiation based on `HiddenRuntimeMode.current`.
- **Containment**: Public MVP must not contain visible Family Access or Local Bridge Sync routes, and must not instantiate these services.
- **Evidence**: Captured at `/docs/release/visual-system/phase5/family-sharing-release-gate-evidence.json`.

## Success Metrics

- 100% closure of P0/P1 code gaps in approved scope.
- 100% passing public MVP containment tests.
- W4-02 evidence package exists and all tests pass.
- Remediated views use `AccessibleColors` tokens.

## Risks and Mitigations

- **Risk**: SettingsView directly constructs hidden services.
- **Mitigation**: Introduce `SettingsSyncSharingGateway` and only construct destinations after enabled eligibility.
- **Risk**: Transaction save failure regresses to dismissal.
- **Mitigation**: Add deterministic `AddTransactionViewSaveFailureTests` using protocol injection.
- **Risk**: Summary-row layout fails on 320pt screens.
- **Mitigation**: `AdaptiveSummaryRow` with vertical fallback.

---

*Last updated: 2026-04-18*
