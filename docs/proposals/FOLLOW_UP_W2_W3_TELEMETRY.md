# Follow-up: Wave 2 and Wave 3 Telemetry Proposal

> Proposed telemetry coverage for Wave 2 transaction save-failures and Wave 3 onboarding retry regressions

| Metadata | Value |
|----------|-------|
| Status | 📋 Planning |
| Last Updated | 2026-04-18 |
| Platform | iOS |
| Audience | Developers / Product |

---

## Overview

This document serves as the follow-on tracking artifact (**FOLLOW-UP-W2-W3-TELEMETRY**) required by the Phase 5 closeout criteria of the 2026-04-18 UX Remediation Program.

While Waves 2 and 3 addressed critical UX gaps through improved error handling and recovery UI, production observability is currently limited to scripted QA and manual evidence. This proposal outlines the telemetry required to detect regressions in these flows in the wild.

## Scope

### Wave 2: Transaction Save Failures
- **Goal**: Detect when users encounter save failures in `AddTransactionView` and whether they successfully recover.
- **Events**:
    - `transaction_save_attempted`: Triggered when "Save" is tapped.
    - `transaction_save_failed`: Triggered on mutation service error. Must include coarse error code (e.g., `persistence_error`, `validation_error`).
    - `transaction_save_retried`: Triggered when "Retry" is tapped on the recovery alert.
    - `transaction_save_recovered`: Triggered when a retry results in a successful save.
    - `transaction_save_abandoned`: Triggered if the user cancels or dismisses after a failure.

### Wave 3: Onboarding Goal Creation
- **Goal**: Detect regressions in the onboarding completion contract where goal creation fails.
- **Events**:
    - `onboarding_goal_creation_attempted`: Triggered at the final step of onboarding.
    - `onboarding_goal_creation_failed`: Triggered on goal-save failure.
    - `onboarding_goal_creation_retried`: Triggered when the user retries from the error banner.
    - `onboarding_goal_creation_succeeded`: Triggered when retry (or first attempt) succeeds.
    - `onboarding_complete_committed`: Triggered only after successful goal creation or skip.

## Implementation Details

- **Redaction**: No financial amounts, goal names, or transaction comments may be included in telemetry payloads.
- **Service**: Integrated with existing `AppLog` and a future production telemetry provider.
- **Trigger**: Implementation is deferred to the next release cycle after Wave 4 closeout.

## Related Documentation

- [COMPLETE_REMAINING_UX_AUDIT_REMEDIATION_PROPOSAL.md](COMPLETE_REMAINING_UX_AUDIT_REMEDIATION_PROPOSAL.md)
- [PHASE_5_CLOSEOUT_CHECKLIST.md](../release/visual-system/phase5/PHASE_5_CLOSEOUT_CHECKLIST.md)

---

*Last updated: 2026-04-18*
