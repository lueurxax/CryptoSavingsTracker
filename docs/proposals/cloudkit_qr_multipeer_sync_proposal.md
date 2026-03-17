# CloudKit-Only Signed File Bridge for Mac Snapshot Sync

## Status
Draft (Phase 2 design track; hard-cutover storage prerequisite already satisfied; read-only family sharing is now a required higher-priority prerequisite before further bridge rollout)

## Goal
Enable a CloudKit-only iPhone app to exchange editable snapshots with the existing macOS surface of CryptoSavingsTracker through a signed file-based manual bridge, without introducing backend infrastructure and without building a second replication engine on top of CloudKit.

## Priority and Sequencing Override
This document no longer treats `Local Bridge Sync` as the next highest-priority family-facing sync capability.

Before further bridge rollout, the product must first ship read-only family access to goals through the dedicated proposal:

- [CloudKit Read-Only Family Sharing Proposal](CLOUDKIT_READONLY_FAMILY_SHARING_PROPOSAL.md)

Normative sequencing rule:

1. Read-only family sharing is higher priority than bridge expansion.
2. A bridge baseline may exist in the runtime, but new rollout scope, expansion, or user-facing prioritization must not bypass the family-sharing gap.
3. The bridge is not the primary answer for spouse/family visibility.

## Current State
- CloudKit migration has been completed on all supported devices. The app no longer supports the legacy local primary database for authoritative data.
- Production runtime is now CloudKit-only for main application data. Any residual legacy local-primary store files are deleted on launch. Local persistence is allowed only for non-authoritative caches and scratch data.
- The implemented cutover contract does not copy directly into a live CloudKit-backed container. It now uses a CloudKit-disabled staging store, validates the copied dataset locally, promotes the validated sqlite files into `cloud-primary.store`, persists `cloudKitPrimary`, and requires an app relaunch before the CloudKit-backed runtime becomes active.
- Migration is fail-closed on source-data blockers. Real local stores can contain unresolved `AllocationHistory` references or similar integrity problems, so diagnostics and repair are now part of the Phase 1 operator contract rather than optional tooling.
- Phase 1.5 hard cutover decision is now accepted and in force: local backward compatibility is retired, bridge work may assume CloudKit-only durable state.
- The current macOS experience is not a separate companion product. The same app already ships a macOS surface with its own main window and Settings window in `CryptoSavingsTrackerApp.swift`.
- The current app now implements the signed file-based manual bridge contract: trusted-device storage, signed snapshot export, import-package storage, import review, signature verification, and apply all exist in the product runtime. QR scanning and Multipeer transport are later hardening, not part of the minimum Phase 2A bridge contract.

## Sequencing
This proposal is valid only with the following delivery order:

### Phase 0: CloudKit Readiness
- Close all SwiftData and CloudKit compatibility blockers from `docs/CLOUDKIT_MIGRATION_PLAN.md`.
- Validate schema deployment in the CloudKit development container.
- Prove that migration from the existing local store to CloudKit can complete without data loss.
- Keep destructive wipe-on-failure behavior removed from the CloudKit path.

### Phase 1: CloudKit Cutover
- Ship the iPhone app with CloudKit as the primary persistence layer.
- Complete production migration from local-only storage to CloudKit-backed storage.
- Prove that all user-visible data flows operate correctly with CloudKit enabled.

### Phase 1.5: Remove Local Backward Compatibility
- Status: completed for production runtime.
- Runtime support for the pre-CloudKit local primary storage path is removed.
- Residual legacy local-primary store files are deleted on launch instead of being preserved as a supported fallback.
- The runtime model is locked to CloudKit-only semantics for all authoritative application data. Local persistence is allowed only for local caches and scratch data.

### Implemented Phase 1 Contract
The current codebase converged on the following Phase 1 cutover contract; after completed Phase 1.5, this remains as historical implementation context and repository truth for how cutover was achieved:
- Create a local backup before migration.
- Run local-only diagnostics and repair classification before any CloudKit-backed container is opened.
- Block migration on unresolved or low-confidence source-data issues rather than guessing or silently dropping records.
- Copy data into a CloudKit-disabled staging store first.
- Validate exact entity presence and integrity in staging before touching the final CloudKit-backed store.
- Promote the validated staging sqlite files into the final `cloud-primary` location only after validation succeeds.
- Persist `cloudKitPrimary` for the next launch, but do not hot-swap the live runtime container in-session.
- Treat app relaunch as the activation boundary for the CloudKit-backed runtime.
- Use deferred cleanup for failed `cloud-primary` residue and for `cloud-primary-staging` residue, rather than unlinking live sqlite files.

### Phase 2: Signed File Bridge and Transport Hardening
- Only after Phases 0, 1, and 1.5 are complete, and after read-only family sharing has shipped, may the app prioritize further bridge rollout, bridge expansion, or transport hardening described in this document.
- The bridge is a file-based import/apply workflow layered around CloudKit, not an alternative storage regime.
- QR scanning and Multipeer transport are Phase 2B hardening items, not the minimum shipping contract for Phase 2A.

## Product Requirements
- CloudKit remains the only durable source of truth for all authoritative application data.
- New feature work must store authoritative user data in CloudKit-backed runtime paths, not in a legacy local primary database.
- Local persistent storage may be used only for non-authoritative caches, scratch workspaces, and ephemeral helper artifacts.
- Family-member iPhone and iPad devices continue using CloudKit sharing for read-only access to the owner's full goal set in v1.
- That read-only family access is governed by `CLOUDKIT_READONLY_FAMILY_SHARING_PROPOSAL.md` and is higher priority than further bridge rollout.
- The existing macOS app surface can perform read/write editing through exported snapshots.
- No backend infrastructure is introduced.
- Bridge sessions operate over signed file artifacts and trusted local review surfaces for Phase 2A.
- The bridge must remain safe to operate manually by a single user through a dedicated bridge surface launched from Settings.

## Authority Model
### Durable Authorities
- CloudKit is the only durable source of truth for multi-device state after Phase 1 is complete.
- The iPhone app is the only component allowed to import edited data into the authoritative CloudKit-backed dataset.
- The macOS app is not a parallel sync authority and not a long-lived replica with independent version history.

### What This Proposal Explicitly Does Not Build
- No custom `lastKnownChangeID` layer.
- No app-defined `SyncState` ledger separate from CloudKit state.
- No `baseVersion` or per-record version graph.
- No `ChangeSetEnvelope`.
- No persistent bridge-side change log.
- No custom conflict queue or per-field merge engine.
- No delta sync phase.
- No background bridge sync or auto reconnect.

The bridge works by moving full snapshots between two trusted app surfaces. If the authoritative dataset changes while a snapshot is being edited on macOS, the import is rejected and a fresh export is required.

## Architecture
```
              CloudKit
                 |
                 |
         durable source of truth
                 |
                 |
             iPhone App
   bridge session host + import validator
                 |
    signed file handoff / package review
                 |
             macOS App
     offline snapshot editor only
```

Key rules:
1. The Mac never writes directly to CloudKit.
2. The iPhone never accepts incremental bridge deltas.
3. Every bridge session starts from a full snapshot exported from the current authoritative dataset.
4. Every bridge import is validated against the current authoritative dataset before apply.
5. Drift is handled by rejecting the import, not by merging two independent histories.

## Product Surface
The bridge lives inside the existing CryptoSavingsTracker macOS app surface, not in a separate companion app or distribution artifact.

### Phase 1 Product Surface (Historical)
During migration rollout, Settings temporarily hosted CloudKit migration controls, status, and repair tooling.
That transitional surface is no longer part of the supported steady-state product contract after the accepted Phase 1.5 hard cutover.
Any remaining references to migration tooling are cleanup debt, not a supported long-term feature surface.

No QR, trust, or bridge controls ship before the runtime is CloudKit-only. This prerequisite is now considered satisfied for authoritative data storage.

### Phase 2 Product Surface
After the CloudKit-only cutover is complete, the top-level Settings page gains a single `Local Bridge Sync` entry row with compact summary state only.

Selecting that row opens a dedicated `Local Bridge Sync` destination on iPhone or macOS. Pairing, trust review, sync execution, compatibility failures, and import review do not run inline inside the general Settings form.

Minimum operator-visible controls:
- `Pair Mac`
- `Trusted Devices`
- `Revoke Trust`
- `Last Sync Status`
- `Sync Now`
- `Import Review`
- `Import Validation Result`

Required summary state shown in the top-level entry row:
- current bridge availability
- last sync outcome
- pending action state such as `Update Required`, `Review Required`, or `Trust Revoked`

### Sync Now States
- `idle`
- `pairingRequired`
- `exportingSnapshot`
- `waitingForEditedSnapshot`
- `validatingImport`
- `awaitingImportReview`
- `importCancelledByUser`
- `importRejectedDueToDrift`
- `importApplied`
- `trustRevoked`
- `trustExpired`

### Platform Surfaces
- iPhone Settings hosts discovery only; operational bridge flows run inside a dedicated iPhone `Local Bridge Sync` destination.
- macOS Settings or a dedicated Sync window inside the current macOS app hosts the bridge destination and manual return of edited snapshots.
- The bridge editor on macOS must not bind directly to the app's live persistent store. Even though the existing macOS app uses shared windows today, the bridge edit surface is a separate transient workspace.
- The current `SettingsView.swift` implementation already exposes the dedicated `Local Bridge Sync` destination and compact top-level summary row. The current implementation now includes trust storage, bootstrap-token modeling, authoritative snapshot export DTOs, file-backed signed import package storage, structural import-review validation, cryptographic signature verification, and signed import apply. QR scanning and Multipeer transport remain later hardening beyond the minimum Phase 2A contract.

### macOS Snapshot Workspace Boundary
- The macOS bridge editor operates on a transient snapshot workspace created from `SnapshotEnvelope`, not on the live app-backed `ModelContainer`.
- The transient workspace may be implemented as an in-memory store or a scratch document package under app-controlled temporary storage, but it must be isolated from the live persistent store used by normal macOS windows.
- Opening a bridge snapshot must never mount that snapshot into the regular shared macOS runtime container.
- Editing, autosave, undo, preview rendering, and validation inside the bridge editor must affect only the transient workspace.
- The only bridge output permitted from macOS is a `SignedImportPackage`.
- Closing or discarding the bridge editor destroys the transient workspace unless the user explicitly exports a new signed package.
- The authoritative live store changes only after the iPhone validates and accepts the returned import package.

### iPhone Import Review Boundary
- Successful signature and schema validation do not immediately mutate the authoritative dataset.
- After validation, iPhone must present a dedicated blocking full-screen `Import Review` flow before apply.
- The review screen must show:
  - signed package origin device
  - trust status for the sending device
  - `snapshotID`
  - changed-entity counts by type
  - concrete money-impacting diffs for changed goals, transactions, allocations, and monthly plans
  - destructive warnings for deletes, relationship nullification, or replacement of existing planning/execution records
  - schema or version warnings relevant to the operator
- The review screen must support explicit `Apply` and `Cancel`.
- Choosing `Cancel` closes the review without mutating the authoritative dataset.
- The operator must be able to explain what will change from the review summary before committing apply.

### CloudKit Reconciliation Boundary
- For bridge purposes, the authoritative dataset means the CloudKit-backed runtime state after a successful foreground reconciliation checkpoint, not merely whatever local snapshot is currently mounted.
- iPhone must complete a foreground CloudKit reconciliation checkpoint before snapshot export.
- iPhone must complete a second reconciliation checkpoint, or prove there are no unresolved fetch/send obligations since the last checkpoint, immediately before final import apply.
- If reconciliation status is `unknown`, `stale`, `reconciling`, or `blockedPendingCloudSync`, export and apply are blocked.
- Blocked reconciliation must surface a visible operator status and recovery action inside the dedicated bridge destination.

## User Flows
### Flow 1: Prepare for Phase 2
1. User updates to a build where CloudKit migration is already complete.
2. User sees a single `Local Bridge Sync` entry row in Settings with compact summary state.
3. That row remains unavailable until the runtime is fully CloudKit-only and reports migration readiness as complete.

### Flow 2: Sign and Load File Bridge Package
1. User opens `Local Bridge Sync` on macOS and exports a snapshot from the CloudKit-backed dataset into an isolated transient workspace.
2. User edits only the transient workspace.
3. macOS signs and exports a `SignedImportPackage` from that workspace and writes it to a shareable file artifact.
4. User moves that package artifact to iPhone through the supported file handoff path for the current build.
5. iPhone loads the package artifact, validates its signature, and either rejects it or opens `Import Review`.
6. During `Import Review`, iPhone shows signed-package summary, concrete money-impact diffs, changed-entity counts, and destructive warnings before any mutation.
7. If the operator cancels review, the authoritative dataset remains unchanged.
8. Immediately before apply, iPhone reruns the CloudKit reconciliation checkpoint or proves there are no unresolved CloudKit obligations since the last successful checkpoint.
9. If the operator confirms apply and the transaction succeeds, the change is written into the CloudKit-backed runtime dataset and the sync status is updated.
10. Until iPhone accept, no live persistent macOS store is mutated by the bridge edit session.

### Flow 3: Trust Bootstrap
1. User opens `Trusted Devices`.
2. User sees trusted Mac devices, last successful sync time, and last validation outcome.
3. User selects `Revoke Trust`.
4. The local trust record is deleted and any unconsumed import packages from that device become invalid.
5. The peer must re-pair from scratch before any later snapshot exchange.

### Flow 4: Transport Hardening (Phase 2B)
1. User opens `Local Bridge Sync`.
2. User opts into QR or Multipeer transport hardening for a future build.
3. The app negotiates the foreground transport session and confirms the trusted peer.
4. The local trust record is persisted and later revocation invalidates any unconsumed packages from that device.
5. The peer must re-pair from scratch before any later snapshot exchange.

## Pairing and Trust Model
### Pairing Token
The QR code contains only short-lived bootstrap material:
- `pairingID`
- `deviceName`
- `ephemeralPublicKey`
- `expiresAt`
- `oneTimeSecretReference`

The QR code must not contain:
- long-term private keys
- reusable long-term secrets
- CloudKit credentials
- snapshot payloads

`oneTimeSecretReference` is a session bootstrap value that is single-use, expiry-bound, and redacted from UI logs, analytics, screenshots used in docs, and debug logging.

### Mutual Authentication
- macOS generates an ephemeral key pair for the pairing session.
- iPhone generates its own ephemeral key pair after scanning.
- The handshake verifies:
  - QR bootstrap authenticity,
  - possession of the ephemeral private keys,
  - the one-time secret reference,
  - peer identity confirmation by the user on iPhone.
- Long-term trusted-device credentials are minted only after handshake success.

### Secure Storage
- Trusted-device material is persisted in Keychain, using the existing `KeychainManager` abstraction or a bridge-specific sibling wrapper built on the same secure storage layer.
- Device trust records must not be stored in `UserDefaults`, plain files, or the bridge snapshot itself.
- Stored trust data includes:
  - stable device identifier
  - device display name
  - long-term public key or trust certificate material
  - creation time
  - last successful sync time
  - revocation flag or deletion state

### Revocation Rules
- Revocation deletes the local trust record.
- Revocation invalidates pending import packages from that device.
- Revoked or expired peers must re-pair before a new session can begin.

### Camera Permission and Pairing Fallback
- Phase 2 shipping requirements include `NSCameraUsageDescription` for QR scanning on iPhone.
- The app requests camera access only when the operator explicitly taps `Scan QR`, never at launch and never as a prerequisite for opening Settings.
- If camera permission is denied, restricted, or unavailable, pairing must remain possible through:
  - manual short-code entry, or
  - pasting the full bootstrap token
- The manual bootstrap path carries the same short-lived bootstrap payload as the QR path and expires on the same schedule.
- Camera denial must not disable trust management, manual pairing, or later re-pair flows.

### Protocol Evolution Policy
- Every bridge build publishes a `BridgeCapabilityManifest` during handshake with:
  - `bridgeProtocolVersion`
  - `minimumSupportedCanonicalEncodingVersion`
  - `maximumSupportedCanonicalEncodingVersion`
  - `minimumSupportedSnapshotSchemaVersion`
  - `maximumSupportedSnapshotSchemaVersion`
- Export and editing are allowed only when the iPhone and macOS peers can negotiate a single compatible `canonicalEncodingVersion` and snapshot schema version before snapshot transfer begins.
- `appModelSchemaVersion` is not a negotiation field. It is emitted only for diagnostics, support, and operator/debug visibility, and it must never override handshake decisions driven by `canonicalEncodingVersion` and `snapshotSchemaVersion`.
- If no compatible intersection exists, the session ends in `Update Required` and no editable snapshot is exported.
- Backward-compatible changes are limited to additive fields or enum cases that do not change canonical ordering, hashing, matching, dedupe, or semantic meaning for existing fields.
- Breaking changes include:
  - any change to canonical ordering or hashing inputs,
  - any change to matching or dedupe semantics,
  - any newly required field,
  - any semantic reinterpretation of an existing field,
  - any snapshot schema change that older peers cannot round-trip safely
- A breaking change requires a new supported version range and handshake-time rejection for older peers.

## Transport Layer
Phase 2A is implemented as a signed file-based manual bridge. The QR + Multipeer details in this section describe later transport hardening (Phase 2B), not the minimum shipping bridge contract.

Transport hardening uses `MultipeerConnectivity` in the foreground only.

Session primitives:
- `MCSession`
- `MCNearbyServiceAdvertiser`
- `MCNearbyServiceBrowser`

Why the bridge is foreground-only:
- The current app only declares `remote-notification` under `UIBackgroundModes`.
- The current app now declares the required foreground bridge privacy strings and Bonjour service type in `Info.plist`.
- The current app still has no existing lifecycle design for background Multipeer transport.
- The current app still has no implemented Multipeer session manager, advertiser, browser, or background reconnect contract.

Phase 2 implementation no longer needs to add the privacy declarations themselves, but it still needs to build the actual foreground discovery and session-establishment runtime around those declarations. That does not change the manual, foreground-only execution contract.

Therefore this proposal does not promise:
- auto reconnect
- periodic background bridge sync
- opportunistic import/export while the app is suspended
- immediate CloudKit propagation after apply

CloudKit system sync remains Apple-managed and nondeterministic. If immediacy is needed, the app must rely on explicit foreground sync actions in the CloudKit layer, not on the bridge layer.

## Snapshot Protocol
### PairingToken
Session bootstrap metadata exchanged through the QR code and handshake:

```json
{
  "pairingID": "uuid",
  "deviceName": "MacBook-Andrey",
  "ephemeralPublicKey": "base64",
  "expiresAt": "ISO-8601 timestamp",
  "oneTimeSecretReference": "opaque-short-lived-token"
}
```

### SnapshotManifest
Session-scoped validation metadata:

```json
{
  "snapshotID": "uuid",
  "canonicalEncodingVersion": "bridge-snapshot-v1",
  "snapshotSchemaVersion": 1,
  "exportedAt": 1773504000000,
  "appModelSchemaVersion": "cloudkit-model-v1",
  "entityCounts": {
    "goals": 4,
    "assets": 8,
    "transactions": 142
  },
  "baseDatasetFingerprint": "sha256-of-canonical-authoritative-export"
}
```

Field semantics:
- `canonicalEncodingVersion` defines canonical serialization, hashing, and package-shape rules.
- `snapshotSchemaVersion` defines the bridge snapshot schema used for compatibility negotiation and validation.
- `appModelSchemaVersion` is app-model revision metadata for operator/debug visibility only. It does not participate in handshake compatibility negotiation and does not override `snapshotSchemaVersion`.

### SnapshotEnvelope
Full export package transferred from iPhone to macOS:

```json
{
  "manifest": {},
  "goals": [],
  "assets": [],
  "transactions": [],
  "assetAllocations": [],
  "allocationHistories": [],
  "monthlyPlans": [],
  "monthlyExecutionRecords": []
}
```

### SignedImportPackage
Edited snapshot returned to iPhone:

```json
{
  "packageID": "sha256-of-canonical-package-body",
  "snapshotID": "uuid",
  "canonicalEncodingVersion": "bridge-snapshot-v1",
  "baseDatasetFingerprint": "sha256-of-original-export",
  "editedDatasetFingerprint": "sha256-of-canonical-edited-snapshot",
  "snapshotEnvelope": {},
  "signingKeyID": "trusted-device-key-id",
  "signedAt": 1773507600000,
  "signature": "base64-signature"
}
```

### BridgeSessionState
macOS editor/session state reported to the operator:

```json
{
  "sessionID": "uuid",
  "workspaceState": "empty | loadedTransientWorkspace | edited | exported | discarded",
  "workspaceIsolation": "transientOnly",
  "liveStoreMutationAllowed": false,
  "compatibilityState": "unknown | compatible | updateRequired",
  "cloudKitReconciliationState": "unknown | reconciling | reconciled | stale | blockedPendingCloudSync"
}
```

### ImportReviewSummary
Operator-facing summary generated on iPhone after validation and before apply:

```json
{
  "snapshotID": "uuid",
  "sourceDeviceName": "MacBook-Andrey",
  "trustState": "trusted",
  "changedEntityCounts": {
    "goals": 1,
    "assets": 0,
    "transactions": 4,
    "assetAllocations": 2,
    "allocationHistories": 2,
    "monthlyPlans": 1,
    "monthlyExecutionRecords": 0
  },
  "goalDiffs": [
    {
      "goalName": "Emergency Fund",
      "targetAmountBefore": "15000",
      "targetAmountAfter": "18000",
      "deadlineBeforeMs": 1773504000000,
      "deadlineAfterMs": 1781280000000
    }
  ],
  "allocationDiffs": [
    {
      "assetDisplayName": "BTC Wallet",
      "goalName": "Emergency Fund",
      "amountBefore": "0.35",
      "amountAfter": "0.50",
      "shareBeforePct": "35",
      "shareAfterPct": "50"
    }
  ],
  "transactionDiffs": [
    {
      "changeType": "added",
      "assetDisplayName": "BTC Wallet",
      "transactionDateMs": 1773504000000,
      "amountBefore": null,
      "amountAfter": "250",
      "currency": "USD",
      "counterpartyBefore": null,
      "counterpartyAfter": "Kraken",
      "commentBefore": null,
      "commentAfter": "Monthly top-up"
    },
    {
      "changeType": "deleted",
      "assetDisplayName": "BTC Wallet",
      "transactionDateMs": 1773417600000,
      "amountBefore": "50",
      "amountAfter": null,
      "currency": "USD",
      "counterpartyBefore": "Manual",
      "counterpartyAfter": null,
      "commentBefore": "Fee correction",
      "commentAfter": null
    }
  ],
  "transactionDeltaSummary": {
    "addedCount": 3,
    "editedCount": 1,
    "deletedCount": 1,
    "netAmountDeltaByCurrency": {
      "USD": "450",
      "BTC": "0.015"
    }
  },
  "monthlyPlanDiffs": [
    {
      "monthLabel": "2026-03",
      "goalName": "Emergency Fund",
      "changeType": "replaced",
      "requiredMonthlyBefore": "900",
      "requiredMonthlyAfter": "1200",
      "effectiveAmountBefore": "900",
      "effectiveAmountAfter": "1100",
      "flexStateBefore": "flexible",
      "flexStateAfter": "protected",
      "isSkippedBefore": false,
      "isSkippedAfter": false
    }
  ],
  "monthlyPlanReplacementSummary": {
    "affectedMonths": ["2026-03"],
    "replacedPlanCount": 1
  },
  "destructiveWarnings": [
    "1 transaction will be deleted",
    "1 monthly plan will be replaced"
  ],
  "requiresExplicitConfirmation": true
}
```

`transactionDeltaSummary` and `monthlyPlanReplacementSummary` are supplemental scan aids only. They do not replace the required concrete `transactionDiffs` and `monthlyPlanDiffs` contract used for operator review before apply.

### ImportValidationResult
Result shown to the operator after validation:

```json
{
  "snapshotID": "uuid",
  "status": "accepted | acceptedAlreadyApplied | rejectedDueToDrift | rejectedDueToSignature | rejectedDueToSchemaMismatch | rejectedDueToAmbiguousMatch | rejectedDueToOrphanReference | rejectedDueToVersionMismatch | blockedPendingCloudSync",
  "reason": "string"
}
```

### BridgeCapabilityManifest
Handshake-time compatibility contract:

```json
{
  "bridgeProtocolVersion": 1,
  "minimumSupportedCanonicalEncodingVersion": "bridge-snapshot-v1",
  "maximumSupportedCanonicalEncodingVersion": "bridge-snapshot-v1",
  "minimumSupportedSnapshotSchemaVersion": 1,
  "maximumSupportedSnapshotSchemaVersion": 1
}
```

## Normative Snapshot Schema Appendix
This appendix is mandatory for any implementation of the bridge. The bridge must not invent alternate serializers, ad hoc hashes, or entity-specific import rules outside this contract.

### Canonical Encoding Rules
- Snapshot fingerprints are computed from the canonical UTF-8 JSON bytes of `SnapshotEnvelope` only. Signature material, `packageID`, transport metadata, and UI state are excluded from the hash.
- The root field order of `SnapshotEnvelope` and `SignedImportPackage` is fixed exactly as shown in this appendix. All nested object keys are serialized in lexicographic order.
- All top-level arrays use the fixed key order shown in `SnapshotEnvelope`: `goals`, `assets`, `transactions`, `assetAllocations`, `allocationHistories`, `monthlyPlans`, `monthlyExecutionRecords`.
- Every entity row must contain explicit `id`, `recordState`, and relationship reference fields. `recordState` is `active` or `deleted`. Delete-by-omission is invalid.
- Optional fields are encoded explicitly as `null`. Missing optional keys are not allowed in canonical snapshots.
- UUIDs are serialized as lowercase canonical strings.
- Dates are serialized as UTC Unix epoch milliseconds, never locale-formatted strings.
- Numeric values are serialized as canonical decimal strings with `.` as the decimal separator, no exponent notation, no thousands separators, and trailing zeros stripped. `-0` is normalized to `0`.
- Enum values are serialized as their persisted raw values.
- Blob-backed SwiftData fields are exported as decoded structured JSON, never as raw `Data` bytes:
  - `MonthlyExecutionRecord.trackedGoalIds` becomes a sorted UUID array.
  - `CompletedExecution.exchangeRatesSnapshotData` becomes an object with lexicographically sorted keys.
  - `CompletedExecution.goalSnapshotsData`, `CompletedExecution.contributionSnapshotsData`, and `ExecutionSnapshot.snapshotData` become canonical nested arrays sorted by their own identity rules.

### Canonical Ordering Rules
- `goals`: sort by `id`.
- `assets`: sort by `(currency, chainId, address, id)` after normalization of `currency` to uppercase and `chainId` / `address` to lowercase.
- `transactions`: sort by `(assetId, dateMs, amount, sourceRawValue, externalId, id)`.
- `assetAllocations`: sort by `(goalId, assetId, id)`.
- `allocationHistories`: sort by `(timestampMs, assetId, goalId, createdAtMs, id)`.
- `monthlyPlans`: sort by `(monthLabel, goalId, id)`.
- `monthlyExecutionRecords`: sort by `(monthLabel, id)`.
- Nested `trackedGoalIds`: sort lexicographically by UUID string.
- Nested `ExecutionGoalSnapshot` arrays: sort by `goalId`.
- Nested `CompletionEvent` arrays: sort by `(sequence, eventId)`.
- Nested exchange-rate maps: sort by currency-pair key.

### Fingerprint and Replay Rules
- `baseDatasetFingerprint` is the SHA-256 of the canonical `SnapshotEnvelope` exported from the current authoritative dataset.
- `editedDatasetFingerprint` is the SHA-256 of the canonical edited `SnapshotEnvelope` returned by the trusted Mac.
- `packageID` is the SHA-256 of the canonical package body before signature attachment.
- The iPhone stores an authoritative import receipt keyed by `packageID`.
- If the same signed package is replayed and a receipt already exists for the same `packageID` and `editedDatasetFingerprint`, the import result is `acceptedAlreadyApplied` and no writes occur.
- If a replayed package reuses `packageID` but fails signature or fingerprint verification, the import is rejected.

### Per-Entity Matching and Dedupe Policy
Import matching always follows the same sequence:
1. Match by stable app `id` if exactly one authoritative record exists with that `id`.
2. If there is no `id` match, try exactly one logical-key match using the table below.
3. If multiple authoritative records satisfy the logical key, reject the entire import as `rejectedDueToAmbiguousMatch`.
4. If no authoritative record matches, insert a new record.
5. If `id` match and logical-key match disagree, reject the entire import.
6. Relationship references are resolved only after parent upserts succeed; unresolved references reject the import as `rejectedDueToOrphanReference`.

Logical-key table:
- `Goal`: `(normalizedName, currency, targetAmount, deadlineMs)`
- `Asset`: `(currency, normalizedChainId, normalizedAddress)`
- `Transaction`: if `externalId` is present, `(assetId, externalId)`; otherwise `(assetId, dateMs, amount, sourceRawValue, normalizedCounterparty, normalizedComment)`
- `AssetAllocation`: `(assetId, goalId)`
- `AllocationHistory`: `(assetId, goalId, timestampMs, createdAtMs, amount)`
- `MonthlyPlan`: `(monthLabel, goalId)`
- `MonthlyExecutionRecord`: `(monthLabel)`
- `CompletedExecution`: `(monthLabel)` nested under its matched `MonthlyExecutionRecord`
- `ExecutionSnapshot`: nested under its matched `MonthlyExecutionRecord`
- `CompletionEvent`: `(executionRecordMonthLabel, sequence)` nested under its matched `MonthlyExecutionRecord`

Normalization used by logical keys:
- `normalizedName`, `normalizedCounterparty`, and `normalizedComment` use Unicode NFC and trim only leading/trailing whitespace.
- `currency` is uppercased.
- `chainId` and `address` are lowercased when present.

### Apply Rules
- Import is all-or-nothing.
- Upserts preserve the authoritative `id` whenever a logical-key match is used.
- The bridge must never create duplicate logical entities in the authoritative dataset.
- The bridge must never create orphaned relationships; any unresolved parent reference aborts the import.
- A `deleted` record may only delete a uniquely matched authoritative record. Ambiguous deletes are rejected.
- After apply, re-exporting the authoritative dataset without additional edits must reproduce `editedDatasetFingerprint`.
- macOS bridge editing must remain side-effect free against the live persistent store until iPhone import acceptance.

## Import Validation
### Validation Sequence
1. Verify that the sending device is still trusted.
2. Verify `packageID`, signature, and canonical package integrity.
3. Verify that the package schema, negotiated snapshot schema version, and negotiated `canonicalEncodingVersion` match the current session contract.
4. Check the import-receipt ledger for `packageID`. If the same package was already applied, return `acceptedAlreadyApplied`.
5. Verify that the latest CloudKit reconciliation checkpoint is still valid; if unresolved fetch/send work exists, return `blockedPendingCloudSync`.
6. Compare `baseDatasetFingerprint` with a fresh fingerprint of the current authoritative dataset.
7. If the authoritative dataset has changed since export, reject the import.
8. Build an import plan using the appendix matching and dedupe rules, rejecting ambiguous matches and orphan references.
9. Build `ImportReviewSummary` from the validated import plan and present it to the operator.
10. Only after explicit operator confirmation and a final CloudKit reconciliation checkpoint may the app apply the imported snapshot as a single controlled operation and persist the import receipt.

### Drift Handling
- Drift means the authoritative CloudKit-backed dataset changed after the snapshot was exported and before the edited snapshot returned.
- Drift is not merged automatically.
- Drift is surfaced to the user as `Import Rejected: Authoritative Data Changed`.
- The operator must export a fresh snapshot and repeat the edit flow.

### Apply Semantics
- Import apply is all-or-nothing.
- Partial apply is not allowed.
- If apply fails after validation, the runtime rolls back the attempted import transaction and preserves the current authoritative dataset.
- Replaying the same signed package after a successful apply must be a no-op.
- Cancelling `Import Review` must be a no-op against the authoritative dataset.

## Failure Handling
Possible failures:
- peer discovery failure
- camera permission denied, restricted, or unavailable
- expired pairing token
- revoked trust
- replayed package
- signature validation failure
- schema mismatch
- version mismatch
- ambiguous entity match
- orphan relationship reference
- authoritative dataset drift
- CloudKit reconciliation blocked or stale
- operator cancelled import review
- CloudKit save failure after import validation

Required operator behavior:
- Every failure updates `Last Sync Status` and `Import Validation Result`.
- No failure silently falls back to an older local-only runtime.
- No failure creates a second source of truth on macOS.
- No failure wipes the authoritative dataset.
- Permission-denied flows expose the manual pairing path instead of dead-ending pairing.
- Apply-time failures roll back the transaction and keep the authoritative dataset unchanged.
- Incompatible bridge versions fail before snapshot editing begins and surface `Update Required`.
- CloudKit reconciliation failures block export/apply and surface a visible recovery action.

### Fallback Scope
This proposal does not include AirDrop snapshot or generic manual file import.

Those fallback paths are out of scope until the app defines:
- a signed export format,
- the same canonical encoding rules as this appendix,
- replay protection,
- an operator entry point in Settings,
- all-or-nothing apply,
- rollback-on-failure guarantees.

Until those additional fallback paths are specified, only the dedicated signed bridge artifact flow defined by this proposal is in scope.

## Implementation Phases
### Phase 0: CloudKit Readiness (Completed)
- Close all items in `docs/CLOUDKIT_MIGRATION_PLAN.md`.
- Validate CloudKit model compatibility.
- Validate safe migration from the current local runtime.

### Phase 1: CloudKit Cutover (Completed)
- Enable CloudKit-backed persistence in production through the staging-based cutover path.
- Complete migration of existing users using the contract `backup -> diagnostics/repair -> staging copy -> validation -> promotion -> persist mode -> relaunch`.
- Expose migration controls, diagnostics, and repair tooling in Settings during migration rollout (historical rollout requirement).
- Treat relaunch, not in-session hot-swap, as the boundary where CloudKit-backed runtime becomes active.

### Phase 1.5: Remove Local Backward Compatibility (Completed)
- Remove runtime compatibility paths for the legacy local-only storage mode.
- Remove transitional migration and repair UI from the active product surface once the CloudKit runtime is proven stable.
- Remove local fallback logic from active runtime code.
- Production runtime is CloudKit-only, so bridge work is storage-unblocked, but user-facing rollout remains gated by read-only family sharing.

### Phase 1.6: Read-Only Family Sharing (Required Before Further Bridge Rollout)
- Implement `CLOUDKIT_READONLY_FAMILY_SHARING_PROPOSAL.md`.
- Ship owner-managed read-only sharing for the owner's full goal set.
- Ship iPhone/iPad invitee read-only goal surfaces with no edit authority.
- Validate revoke, invite acceptance, and owner-only write authority.

### Phase 2A: Signed File Bridge
- maintain current bridge baseline without elevating it above read-only family sharing in rollout priority
- isolated transient snapshot workspace on macOS
- trusted-device storage
- trusted-device revocation
- full snapshot export/import via signed file artifacts
- cryptographic signature verification
- CloudKit reconciliation checkpoint before export/apply
- iPhone import review before apply, including concrete goal, transaction, allocation, and monthly-plan diffs
- manual `Sync Now`
- import validation status
- all-or-nothing import apply into the CloudKit-backed runtime

### Phase 2B: Transport Hardening
- local-network privacy and Bonjour declarations for foreground bridge transport
- camera permission prompt + manual bootstrap fallback
- QR pairing
- MultipeerConnectivity transport
- resumable foreground transfer
- richer operator diagnostics
- better trust review UX
- stronger validation and error presentation
- visual grouping and scanability improvements for the already-required financial diff presentation in `Import Review`

## Phase 2 Test Matrix and Acceptance Criteria
| Scenario | Required operator-visible outcome |
| --- | --- |
| Export signed package to file artifact | macOS produces a signed import package artifact, snapshot remains isolated from the live store, and the artifact is available for operator handoff |
| Load signed package artifact on iPhone | package signature is verified, import review opens, and concrete diffs are visible before apply |
| Replay previously accepted package | result is `acceptedAlreadyApplied`, no authoritative write occurs, operator sees no duplicate import |
| Schema mismatch package | package is rejected before review/apply, operator sees schema mismatch outcome |
| Export attempted while CloudKit reconciliation is stale or unresolved | export is blocked, operator sees reconciliation status and recovery action |
| Drift between export and import | package is rejected with drift outcome, operator is instructed to export a fresh snapshot |
| Ambiguous logical match or orphan reference | package is rejected with explicit validation outcome, authoritative dataset remains unchanged |
| Operator cancels `Import Review` | authoritative dataset remains unchanged and the operator returns to idle state |
| Import Review for money-impacting changes | operator sees concrete before/after goal, transaction, and monthly-plan diffs rather than counts alone |
| Import Review for allocation changes | operator sees concrete before/after allocation amounts and percentage/share changes before apply |
| Apply attempted after review while CloudKit reconciliation is stale or unresolved | apply is blocked before mutation, operator sees reconciliation status and recovery action |
| Apply failure after explicit confirmation | runtime rolls back the import transaction, authoritative dataset remains unchanged, failure state is visible in status |
| QR pairing with camera permission granted | pairing succeeds and trust confirmation is shown in the Phase 2B transport hardening flow |
| QR pairing with camera permission denied/restricted/unavailable | `Scan QR` fails gracefully, manual bootstrap remains available, pairing can still complete |
| Deterministic fingerprint validation | the same semantic dataset produces the same fingerprint regardless of source ordering or field insertion order |
| Duplicate-prevention validation | importing a valid package never creates duplicate logical entities in the authoritative dataset |

Document-level gates:
- The document states that CloudKit migration is complete on supported devices and the authoritative runtime is CloudKit-only.
- The document states that bridge work is storage-unblocked by hard cutover, but still sequencing-blocked until read-only family sharing ships.
- The document states that backward compatibility with the pre-CloudKit local runtime has been removed from supported authoritative paths.
- The document states that read-only family sharing has higher product priority than further bridge rollout.
- The document allows bridge-baseline maintenance, but not bridge reprioritization above read-only family sharing.
- No runtime path in the proposal describes local-store fallback once Phase 2 ships.
- The authority model names CloudKit as the only durable source of truth.
- The proposal no longer defines a second replication engine or independent sync ledger.
- The proposal defines Settings as an entry point only and moves operational bridge work into dedicated bridge surfaces.
- The proposal defines iPhone and macOS product surfaces for pairing, trust review, import review, revocation, status, and manual sync.
- The proposal defines an isolated transient snapshot workspace on macOS and forbids bridge edits from mutating the live persistent store before iPhone acceptance.
- The proposal defines the bridge as manual and foreground-only.
- The proposal defines secure storage of trust records through Keychain-backed storage.
- The proposal defines handshake-time protocol/version negotiation and update-required behavior before editing begins.
- The proposal assigns one unambiguous meaning to each manifest version field and distinguishes compatibility-gating fields from operator/debug metadata.
- The proposal defines CloudKit reconciliation checkpoints before export and before final apply.
- The proposal defines drift handling as reject-and-re-export, not merge.
- The proposal defines concrete `ImportReviewSummary` diff payloads for goals, transactions, allocations, and monthly plans, with summaries used only as supplemental scan aids.
- The proposal defines a normative canonical snapshot schema, deterministic fingerprint rules, replay idempotency, and per-entity dedupe/matching rules.
- The proposal guarantees that the same semantic dataset hashes to the same fingerprint and that import never creates duplicate logical entities.
- The proposal keeps AirDrop/manual file import out of scope until signed-package and validation requirements are specified.

## Non-Goals
- Re-enabling the old local-only runtime after CloudKit cutover.
- Shipping a second sync engine parallel to CloudKit.
- Building per-record merge or conflict-queue UX.
- Running Multipeer sync in the background.
- Introducing a separate Mac companion distribution artifact.

## Summary
The bridge proposed here is intentionally narrow:

- CloudKit is the only durable source of truth.
- The iPhone is the bridge session host and import validator.
- The macOS surface edits exported snapshots, not an independent replica history.
- The bridge ships on top of an already-finished CloudKit migration and removed local-runtime backward compatibility.
- Safety is achieved by trusted pairing, signed packages, Keychain-backed trust storage, CloudKit reconciliation checkpoints, early compatibility negotiation, and reject-on-drift import validation.
