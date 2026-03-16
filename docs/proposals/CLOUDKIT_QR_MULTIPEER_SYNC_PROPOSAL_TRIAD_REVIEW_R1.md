# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed:
  - `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md`
  - `docs/CLOUDKIT_MIGRATION_PLAN.md`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift`
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift`
  - `ios/CryptoSavingsTracker/Views/ContentView.swift`
- Internet sources reviewed:
  - Apple `CKSyncEngine` documentation and WWDC23 sync guidance
  - Apple local network privacy guidance
  - Apple camera usage-description requirements
- Xcode screenshots captured:
  - `docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r1/settings-surface-current.png`
  - `docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r1/macos-main-surface-current.png`
- Remaining assumptions:
  - The review is scoped to the proposal and current repo state, not to a hidden external CloudKit implementation.
  - The bridge is intended to work with the existing macOS target in this repo, not a future separate app bundle.

## 1. Executive Summary
- Overall readiness: `Amber`
- Top 3 risks:
  1. The proposal still does not define a CloudKit convergence gate before export/apply, so snapshot validation can be locally correct but globally stale.
  2. Protocol/schema compatibility across iPhone and macOS builds is not yet negotiated early enough in the session lifecycle.
  3. Import Review is materially better now, but still too coarse for high-trust financial confirmation because it describes counts and warnings more than concrete before/after financial changes.
- Top 3 opportunities:
  1. The proposal is now narrow and disciplined enough to be implementable without creating a second sync engine.
  2. The new canonical schema appendix creates a strong foundation for deterministic testing and replay safety.
  3. The macOS transient-workspace boundary is now explicit and can become a clean implementation seam.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 7 | 0 | 0 | 1 | 1 |
| UX (Financial) | 7 | 0 | 0 | 2 | 0 |
| iOS Architecture | 8 | 0 | 1 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [Medium] Sync controls are specified, but the operator hierarchy is still not sharp enough for a high-risk workflow.
  - Evidence:
    - `DOC-01`: [cloudkit_qr_multipeer_sync_proposal.md:89](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L89)
    - `DOC-02`: [cloudkit_qr_multipeer_sync_proposal.md:140](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L140)
    - `SCR-01`: `docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r1/settings-surface-current.png`
  - Why it matters:
    - The current app Settings surface is lightweight and utility-oriented. The proposal adds pairing, trust, sync, validation, and review to the same general surface, but does not clearly separate routine settings from high-risk sync actions. In Apple-style UI terms, this risks burying a rare but consequential workflow in a form-like settings context instead of giving it an explicit operational surface.
  - Recommended fix:
    - Keep discovery in Settings, but make `Local Bridge Sync` a dedicated drill-in destination with its own screen, status header, trust list, and review entry points.
    - Treat `Import Review` as a dedicated full-screen confirmation flow, not a small inline subsection.
  - Acceptance criteria:
    - The top-level Settings page contains only a single entry row for bridge sync plus summary state.
    - Pairing, trust review, and import review happen in dedicated surfaces with explicit titles and recovery actions.

- [Low] The proposed `Enable iCloud Sync` control is visually and semantically misaligned with the document's CloudKit-only end state.
  - Evidence:
    - `DOC-03`: [cloudkit_qr_multipeer_sync_proposal.md:92](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L92)
    - `DOC-04`: [cloudkit_qr_multipeer_sync_proposal.md:30](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L30)
  - Why it matters:
    - A control labeled like an on/off setting implies durable operator choice. The proposal itself says the runtime becomes CloudKit-only before the bridge ships, so the UI language should communicate migration state, not a permanent opt-in toggle.
  - Recommended fix:
    - Rename the Phase 1 control to a transitional migration action such as `Migrate to iCloud`, then remove it once cutover completes.
  - Acceptance criteria:
    - No post-cutover product surface suggests the user can switch back to the legacy local runtime.

### 3.2 UX Review Findings
- [Medium] `Import Review` is substantially improved, but it still may not provide enough financial clarity for explicit operator confirmation.
  - Evidence:
    - `DOC-05`: [cloudkit_qr_multipeer_sync_proposal.md:140](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L140)
    - `DOC-06`: [cloudkit_qr_multipeer_sync_proposal.md:343](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L343)
  - Why it matters:
    - For a finance app, “changed entity counts” and destructive warnings are necessary but not always sufficient. A user deciding whether to overwrite authoritative savings data typically needs concrete before/after cues for meaningful financial changes, not only counts by entity type.
  - Recommended fix:
    - Add a minimum review payload contract for user-comprehensible diffs:
      - goal name + changed target/deadline if edited,
      - transaction count plus net amount delta,
      - monthly plan replacement summary with affected month labels,
      - destructive-item list for deletes and nullifications.
  - Acceptance criteria:
    - A user can identify the money-impacting changes without opening raw records or trusting entity counts alone.
    - `Import Review` always shows concrete changed objects for destructive and financially significant mutations.

- [Medium] The proposal still lacks a user-facing compatibility failure path between adjacent bridge versions.
  - Evidence:
    - `DOC-07`: [cloudkit_qr_multipeer_sync_proposal.md:283](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L283)
    - `DOC-08`: [cloudkit_qr_multipeer_sync_proposal.md:453](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L453)
  - Why it matters:
    - Right now compatibility failure shows up late as schema mismatch at validation time. For operators, that is a frustrating failure mode because the pairing/session may succeed and editing work may already have started before incompatibility becomes visible.
  - Recommended fix:
    - Move bridge compatibility checks earlier:
      - advertise supported `canonicalEncodingVersion` and schema range during handshake,
      - block export or open-in-editor when the peer is incompatible,
      - present an explicit “Update required” state in `Last Sync Status`.
  - Acceptance criteria:
    - An incompatible iPhone/macOS version pair is rejected before snapshot editing begins.
    - The operator sees a version-compatibility explanation and next action.

### 3.3 Architecture Review Findings
- [High] The proposal still does not define a CloudKit convergence checkpoint before snapshot export and before final import apply.
  - Evidence:
    - `DOC-09`: [cloudkit_qr_multipeer_sync_proposal.md:171](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L171)
    - `DOC-10`: [cloudkit_qr_multipeer_sync_proposal.md:453](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L453)
    - `DOC-11`: [CryptoSavingsTrackerApp.swift:46](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift#L46)
    - `WEB-01`: `CKSyncEngine` / WWDC23 guidance
  - Why it matters:
    - The proposal now correctly uses `baseDatasetFingerprint` and reject-on-drift. But it still assumes the local CloudKit-backed runtime dataset is sufficiently authoritative at export/apply time. `CKSyncEngine` scheduling is system-managed and not immediate by default, so without a pre-export and pre-apply sync checkpoint, the bridge can compare against a locally coherent state that still lags server truth.
  - Recommended fix:
    - Add a normative bridge precondition:
      - before export, iPhone must complete a foreground CloudKit reconciliation checkpoint,
      - before final apply, iPhone must verify there are no unresolved CloudKit fetch/send obligations or must explicitly re-check after a forced reconciliation pass,
      - if reconciliation cannot complete, export/apply is blocked with visible operator status.
  - Acceptance criteria:
    - Export cannot start while CloudKit reconciliation status is unknown or stale.
    - Apply cannot commit if the authoritative runtime has pending unresolved CloudKit drift relative to the last reconciliation checkpoint.

- [Medium] The canonical schema appendix is strong, but protocol evolution policy is still incomplete.
  - Evidence:
    - `DOC-12`: [cloudkit_qr_multipeer_sync_proposal.md:379](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L379)
    - `DOC-13`: [cloudkit_qr_multipeer_sync_proposal.md:548](/Users/user/.codex/worktrees/5d0e/CryptoSavingsTracker/docs/proposals/cloudkit_qr_multipeer_sync_proposal.md#L548)
  - Why it matters:
    - The document now defines canonical encoding and matching rules, which is a major improvement. What is still missing is a version-evolution contract: how new fields are introduced, whether older clients may read but not edit newer snapshots, and when a schema bump is considered bridge-breaking versus backward compatible.
  - Recommended fix:
    - Add a `Protocol Evolution Policy` section with:
      - compatible vs incompatible schema changes,
      - minimum supported `canonicalEncodingVersion`,
      - handshake-time negotiation rules,
      - operator-visible update-required outcomes.
  - Acceptance criteria:
    - Every future schema change can be classified as backward compatible or breaking using explicit written rules.
    - Handshake rejects unsupported version pairs before snapshot editing begins.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict:
  - Lightweight Settings integration vs explicit high-trust operational workflow.
  - Tradeoff:
    - Keeping everything inline in Settings reduces navigation steps, but increases ambiguity for pairing, trust, and import review.
  - Decision:
    - Use Settings as an entry point only; move operational sync flow into a dedicated bridge surface.
  - Owner:
    - Product + iOS/macOS design

- Conflict:
  - Fast manual export/apply vs CloudKit convergence safety.
  - Tradeoff:
    - Allowing immediate export/apply feels responsive, but risks validating against stale local state.
  - Decision:
    - Add explicit CloudKit reconciliation checkpoints before export and before apply.
  - Owner:
    - iOS architecture

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Define CloudKit reconciliation checkpoint before export/apply | Architecture | iOS tech lead | Now | CKSyncEngine operating model | Export/apply blocked when authoritative state is not reconciled |
| P0 | Add protocol evolution and handshake compatibility policy | Architecture | iOS + macOS tech leads | Now | Canonical schema appendix | Incompatible versions fail before editing starts |
| P1 | Strengthen `Import Review` with concrete money-impact diffs | UX | Product design | Next | Import review payload contract | Operator can explain financial changes before apply |
| P1 | Convert `Local Bridge Sync` into a dedicated drill-in flow instead of inline Settings operations | UI/UX | Product + design | Next | Surface map | Pair, trust, and review are no longer mixed with routine settings rows |
| P2 | Replace `Enable iCloud Sync` with explicit transitional migration wording | UI/UX | Product copy | Later | Phase 1 migration design | No UI suggests legacy/local runtime can remain active after cutover |

## 6. Execution Plan
- Now (0-2 weeks):
  - Add CloudKit reconciliation preconditions.
  - Add bridge compatibility negotiation and version policy.
- Next (2-6 weeks):
  - Expand `Import Review` into a concrete financial diff contract.
  - Refactor product surface so Settings is an entry point, not the whole sync workflow.
- Later (6+ weeks):
  - Clean up transitional migration copy and remove ambiguous opt-in wording after CloudKit cutover design is finalized.

## 7. Open Questions
- Does “authoritative dataset” mean “latest local CloudKit-backed runtime state” or “latest reconciled state after explicit `CKSyncEngine` fetch/send checkpoint”?
- Should bridge compatibility be strict exact-match on `canonicalEncodingVersion`, or a negotiated min/max supported range?
- Which changes must always appear as explicit record-level diffs in `Import Review`: deletes only, or all money-impacting edits?

## Appendix A. Evidence Pack

### A. Document Inputs
| Evidence ID | Document | Section | Key Fact | Assumption/Constraint |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Product Surface | Sync controls are defined, but as Settings-surface operations | High-risk sync flow should likely drill out of general settings |
| DOC-02 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | iPhone Import Review Boundary | Review exists and blocks apply | Review content should be concrete enough for financial trust |
| DOC-03 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Phase 1 Product Surface | `Enable iCloud Sync` is proposed | Label may conflict with CloudKit-only end state |
| DOC-04 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Sequencing / Phase 1.5 | Local backward compatibility must be removed before bridge rollout | Post-cutover UI should not imply reversible mode switching |
| DOC-05 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Import Review Boundary | Review shows counts, warnings, and explicit confirm/cancel | Money-impact summary may still be too abstract |
| DOC-06 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | ImportReviewSummary | Review payload emphasizes counts/warnings | Concrete object-level diffs are still missing |
| DOC-07 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Snapshot Protocol | Schema and encoding versions are present | Negotiation policy is not yet defined |
| DOC-08 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Import Validation | Schema mismatch handled at validation time | Better to fail incompatible versions earlier |
| DOC-09 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Manual Snapshot Edit flow | Export/apply assume current authoritative dataset is ready | CloudKit reconciliation checkpoint is not specified |
| DOC-10 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Validation Sequence | Drift is based on fresh fingerprint vs current authoritative dataset | Current-state freshness relative to CloudKit is unspecified |
| DOC-11 | `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift` | ModelConfiguration | Runtime still sets `cloudKitDatabase: .none` today | Proposal remains future-state only |
| DOC-12 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Normative Snapshot Schema Appendix | Canonical encoding rules are now explicit | Strong base, but evolution policy still absent |
| DOC-13 | `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md` | Test Matrix | Operational scenarios are much stronger than before | Version-compatibility scenario still missing |

### B. Internet Sources
| Evidence ID | URL | Date | Key Point | Relevance |
|---|---|---|---|---|
| WEB-01 | `https://developer.apple.com/documentation/CloudKit/CKSyncEngine-5sie5` and `https://developer.apple.com/videos/play/wwdc2023/10188/` | Accessed 2026-03-15 / WWDC23 | `CKSyncEngine` scheduling is system-managed; immediacy requires explicit foreground sync actions | Supports the remaining need for export/apply reconciliation checkpoints |
| WEB-02 | `https://developer.apple.com/la/videos/play/wwdc2020/10110/` | WWDC20 | Local network discovery requires privacy disclosure and Bonjour/service-type setup | Confirms that foreground Multipeer setup still needs explicit privacy contract |
| WEB-03 | `https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html` and `https://developer.apple.com/library/archive/qa/qa1937/_index.html` | Accessed 2026-03-15 | Camera access requires `NSCameraUsageDescription` and explicit purpose disclosure | Supports the manual pairing fallback requirement already added to the proposal |

### C. Xcode Screenshot Log
| Evidence ID | Screenshot File | Flow Step | State | Device/OS | Relevance |
|---|---|---|---|---|---|
| SCR-01 | `docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r1/settings-surface-current.png` | Current Settings entry surface | Existing pre-bridge state | Xcode Preview, current app | Confirms that sync controls are not present today and that new bridge UX must fit into or branch off from Settings |
| SCR-02 | `docs/review-artifacts/cloudkit-qr-multipeer-sync-review-r1/macos-main-surface-current.png` | Current macOS main surface | Existing shared macOS app state | Xcode Preview, current app | Confirms that macOS bridge scope is inside the existing app surface, not a separate companion product |

### D. Assumptions and Open Questions
- ASSUMP-01: The bridge continues to target the existing macOS app target in this repo.
- ASSUMP-02: The authoritative dataset is intended to be the CloudKit-backed runtime after explicit reconciliation, not merely whichever local snapshot happens to be mounted.
- QUESTION-01: Should protocol compatibility be exact-version only or negotiated by supported ranges?
- QUESTION-02: Which money-impacting changes must be shown as record-level diffs during `Import Review`?
