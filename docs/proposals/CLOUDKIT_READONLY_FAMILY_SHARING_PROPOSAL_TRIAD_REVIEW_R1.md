# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed:
  - `docs/proposals/CLOUDKIT_READONLY_FAMILY_SHARING_PROPOSAL.md`
  - `docs/proposals/cloudkit_qr_multipeer_sync_proposal.md`
  - `docs/CLOUDKIT_MIGRATION_PLAN.md`
  - `docs/runbooks/cloudkit-cutover-release-gate.md`
  - `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift`
  - `ios/CryptoSavingsTracker/Utilities/PersistenceController.swift`
  - `ios/CryptoSavingsTracker/Views/ContentView.swift`
  - `ios/CryptoSavingsTracker/Views/GoalDetailView.swift`
  - `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift`
  - `ios/CryptoSavingsTracker/Views/Settings/LocalBridgeSyncView.swift`
- Internet sources reviewed:
  - Apple CloudKit participant, invitation, sharing-controller, and shared-store guidance
  - Apple HIG guidance for activity views and destructive alerts
  - CFPB 2024 personal financial data rights final rule
- Xcode screenshots captured:
  - `docs/screenshots/review-cloudkit-family-sharing-r1/current-goals-root-no-shared-entry-preview-iphone-light.png`
  - `docs/screenshots/review-cloudkit-family-sharing-r1/current-goal-detail-owner-surface-preview-iphone-light.png`
  - `docs/screenshots/review-cloudkit-family-sharing-r1/current-settings-local-bridge-entry-preview-iphone-light.png`
- Remaining assumptions:
  - The first cut still targets a read-only projection layered on top of the CloudKit-only authoritative runtime.
  - macOS scope is still ambiguous.
  - Xcode Preview evidence is acceptable for this review pass because the target feature does not yet exist.

## 1. Executive Summary
- Overall readiness: `Amber`
- Top 3 risks:
  1. The proposal does not yet specify how CloudKit share acceptance and shared-database bootstrapping actually work in this app shell.
  2. The projection contract is directionally right but too abstract to guarantee privacy, freshness, and cleanup semantics.
  3. The UI and UX contract is too thin for a high-trust household finance surface and will likely devolve into "owner screens with buttons removed."
- Top 3 opportunities:
  1. The proposal is right to prioritize read-only family visibility above further bridge rollout.
  2. The projection approach is safer than exposing the live owner graph and fits the existing CloudKit-only runtime.
  3. The current bridge surface already gives the product a clean operator-vs-consumer boundary to build on.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 6 | 0 | 1 | 1 | 0 |
| UX (Financial) | 6 | 0 | 2 | 1 | 0 |
| iOS Architecture | 5 | 0 | 2 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [High] Navigation topology for `Shared Goals` and share management is not defined tightly enough against the live app shell.
  - Evidence:
    - `DOC-04`, `DOC-07`, `DOC-09`, `DOC-10`, `SCR-01`, `SCR-02`, `SCR-03`
  - Why it matters:
    - The current iOS product has a single `Goals` root, goal-detail actions in the trailing menu, and `Local Bridge Sync` already occupying the sync-facing Settings position. The proposal says `Share with Family` starts from goal detail and invitees get a `Shared Goals` entry point, but it never locks where those surfaces live on iPhone, iPad, and macOS. Without that, implementation risk is high: the team can easily bury invitee access in Settings, overload the current `Goals` root, or bolt a read-only surface onto the wrong shell.
  - Recommended fix:
    - Add a platform matrix and navigation map that names:
      - owner entry point placement on goal detail,
      - invitee entry point placement in the top-level shell,
      - whether macOS is in or out for v1,
      - how shared and owned goals coexist when the same user both owns and receives goals.
  - Acceptance criteria:
    - The proposal contains one unambiguous navigation path for owner sharing and one unambiguous navigation path for invitee consumption on every in-scope platform.
    - `Shared Goals` is not left as an abstract surface; its home in the app shell is explicit.

- [Medium] The proposal has no visual contract for a deliberately read-only household surface.
  - Evidence:
    - `DOC-03`, `DOC-04`, `SCR-02`, `WEB-07`, `WEB-08`
  - Why it matters:
    - The document correctly says invitee copy must communicate that the surface is shared and read-only, not merely missing buttons by accident. But it never defines how that happens. In the current app, goal detail is owner-first and action-heavy. If implementation simply reuses that surface and strips actions, the result will feel broken, not intentionally safe.
  - Recommended fix:
    - Add a compact UI contract for the shared-detail screen: owner identity row, read-only badge, `last updated` placement, stale/unavailable/revoked card states, and destructive revoke confirmation pattern.
  - Acceptance criteria:
    - The proposal specifies component anatomy for `active`, `stale`, `temporarilyUnavailable`, and `revokedOrRemoved` shared-detail states.
    - The shared-detail surface is visually distinguishable from owner goal detail before implementation starts.

### 3.2 UX Review Findings
- [High] Freshness and trust semantics are under-specified for a finance-adjacent read-only surface.
  - Evidence:
    - `DOC-02`, `DOC-03`, `DOC-05`, `WEB-05`, `WEB-10`
  - Why it matters:
    - The proposal shares progress, forecast state, current-month summary, and contribution summary, and it says stale data must be visible as stale. But it never defines when data becomes stale, how freshness is explained, what `temporarilyUnavailable` means to the user, or whether a shared monthly status is derived from owner planning data that may no longer be current. In a household finance context, if people cannot explain where a number came from or how current it is, trust drops fast.
  - Recommended fix:
    - Add a state matrix for `invitePendingAcceptance`, `active`, `stale`, `temporarilyUnavailable`, and `revokedOrRemoved` with:
      - trigger condition,
      - user-facing copy,
      - visible timestamp treatment,
      - allowed actions,
      - analytics event.
  - Acceptance criteria:
    - Each lifecycle state has a concrete trigger and copy contract.
    - Shared goal detail always exposes an `As of` or `Last updated` indicator.
    - The document defines the freshness SLA that moves a share from `active` to `stale`.

- [High] Authorization disclosure and revoke management are not detailed enough for a high-trust sharing flow.
  - Evidence:
    - `DOC-04`, `DOC-05`, `WEB-03`, `WEB-08`, `WEB-09`, `WEB-10`
  - Why it matters:
    - The proposal says the owner can start sharing, send an invite, see who has access, revoke access, and review what is visible. That is directionally correct, but still too loose. Owners need a clear pre-share disclosure of the exact data exposed, an obvious participant-management surface after sharing starts, and a revoke flow that is explicit about consequence. Invitees need clear identity and status after acceptance. Right now the document only sketches those moments.
  - Recommended fix:
    - Add an owner-side management flow with:
      - first-share visibility review,
      - participant list and participant states,
      - revoke confirmation copy,
      - post-revoke outcome behavior,
      - copy for invite pending and failed share creation.
  - Acceptance criteria:
    - The proposal defines the pre-share disclosure content and the post-share management screen.
    - Revoke is modeled as a deliberate management action with confirmation and explicit result state.
    - Participant states map cleanly from CloudKit/system states into product copy.

- [Medium] `Share with Family` risks promising Apple Family Sharing semantics that the proposal explicitly does not support.
  - Evidence:
    - `DOC-01`, `DOC-04`, `WEB-03`, `WEB-07`
  - Why it matters:
    - The document correctly states that this feature does not depend on Apple's Family Sharing purchase group, but the primary action label is still `Share with Family`. That is a product-risky label unless the first-use copy immediately clarifies that v1 is invite-based for specific Apple-account users, not an automatic household-group integration.
  - Recommended fix:
    - Keep the household intent, but lock the first-use copy. Example: keep `Share with Family` as the action label only if the explainer says `Invite specific Apple account users to view this goal in read-only mode.`
  - Acceptance criteria:
    - First-use copy explicitly distinguishes invite-based access from Apple Family Sharing group behavior.
    - The proposal names the first-use explainer text or its required semantic content.

### 3.3 Architecture Review Findings
- [High] Invite acceptance and shared-database bootstrapping are missing from the technical contract.
  - Evidence:
    - `DOC-02`, `DOC-05`, `DOC-12`, `WEB-01`, `WEB-02`, `WEB-04`
  - Why it matters:
    - Flow 2 says the invitee opens the invite, accepts access, and the goal appears under `Shared Goals`. Apple CloudKit sharing does not happen by magic. It requires explicit invitation acceptance and a concrete shared-database data path. The current app shell has no share-accept hook, no sharing controller, and no shared-database bootstrap code. Without this section, the proposal is not implementation-ready.
  - Recommended fix:
    - Add a dedicated `Share Acceptance and Storage Topology` section that defines:
      - the lifecycle entry points for share acceptance on each in-scope platform,
      - whether shared projections are read directly from CloudKit shared database records or mirrored into a dedicated local cache/store,
      - who owns acceptance, refresh, and revocation processing,
      - cold-start and already-running acceptance behavior,
      - failure handling for account unavailable, rejected invite, and partially loaded share states.
  - Acceptance criteria:
    - The proposal names the exact app lifecycle integration points and shared-data ingestion path.
    - The release test matrix includes cold-start invite acceptance, already-running invite acceptance, and revoked-share re-entry.

- [High] The projection contract is not executable enough to guarantee privacy, idempotency, and cleanup.
  - Evidence:
    - `DOC-02`, `DOC-03`, `DOC-05`, `WEB-05`, `WEB-06`
  - Why it matters:
    - A field allowlist/exclusion list is necessary, but it is not a full storage contract. The document still leaves `projection schema`, `publishing`, `refresh contract`, and `share-root contract` to later phases. That is too open for a decision-locked P0 proposal. Implementation still needs record types, stable identifiers, update rules, cleanup semantics for unshare/delete, multi-invitee behavior, schema versioning, and stale-threshold behavior.
  - Recommended fix:
    - Add a schema appendix that defines:
      - projection root and child record types,
      - stable IDs and version fields,
      - publish triggers and idempotent overwrite rules,
      - cleanup behavior on owner delete, unshare, and participant revoke,
      - whether one goal projection can serve multiple participants or whether projections are per participant.
  - Acceptance criteria:
    - The proposal includes enough schema detail to build fixtures and write integration tests without inventing new contracts during implementation.
    - The document explicitly proves that unshared goals cannot leak through projection reuse or cleanup lag.

- [Medium] Rollout and operability are under-specified for a feature that blocks other sync work.
  - Evidence:
    - `DOC-05`, `DOC-06`, `DOC-13`, `DOC-14`, `WEB-06`
  - Why it matters:
    - The repository already treats CloudKit cutover as a release-gated, evidence-backed change. This proposal is also a sequencing gate, but it lacks the same operational rigor: no feature flag, no kill switch, no telemetry plan, no stuck-invite runbook, and no owner for orphan-share cleanup or share-creation failure triage.
  - Recommended fix:
    - Add a rollout section with:
      - feature-flag and kill-switch ownership,
      - metrics for share create, accept, revoke, and stale/unavailable rates,
      - redaction rules for logging participant and goal-share metadata,
      - support runbook for stuck invites, revoked shares, and projection cleanup failures.
  - Acceptance criteria:
    - The proposal names its rollout guardrails, metrics, and fallback behavior before implementation starts.
    - Release gates exist at the same level of rigor already used for CloudKit cutover.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict:
  - System sharing UI vs custom family-sharing management UI.
  - Tradeoff:
    - System CloudKit sharing affordances maximize platform trust and reduce implementation risk, but custom UI is still needed for pre-share disclosure and household-specific explanation.
  - Decision:
    - Make v1 system-first: use native share-management UI for invite creation/participant management where possible, and limit custom UI to preflight explanation, visibility review, and app-specific shared-goal states.
  - Owner:
    - Product design + iOS architecture

- Conflict:
  - Reusing owner goal detail vs building a distinct shared-detail surface.
  - Tradeoff:
    - Reuse is faster, but a finance-grade read-only surface needs explicit identity, freshness, and authority boundaries.
  - Decision:
    - Build a dedicated shared projection surface and shared view models rather than hiding owner actions on the live detail screen.
  - Owner:
    - iOS product design + app architecture

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P0 | Add platform matrix plus share-accept/storage topology section | Architecture | iOS architecture lead | Now | Current proposal draft | Invite acceptance flow is executable on every in-scope platform |
| P0 | Add projection schema appendix with publish, refresh, cleanup, and idempotency rules | Architecture | iOS architecture lead | Now | Accepted projection direction | Integration tests can be designed without inventing missing storage rules |
| P0 | Add lifecycle/freshness/copy matrix for invitee and owner share states | UX | Product design | Now | Product state list already exists | Every lifecycle state has trigger, copy, CTA, and timestamp semantics |
| P1 | Lock navigation IA and shared-detail visual contract | UI | Product design | Next | P0 scope matrix | Shared goals have a clear home in the app shell and a distinct read-only visual identity |
| P1 | Define owner visibility review, participant management, and revoke flow | UX | Product design | Next | System-first share-management decision | Owners can explain exactly what is shared and revoke access without ambiguity |
| P1 | Add rollout guardrails, telemetry, and support runbook | Architecture | Eng manager + iOS lead | Next | Existing CloudKit release-gate discipline | Feature can be rolled out and paused without guesswork |
| P2 | Evaluate post-v1 macOS parity and multi-owner scaling patterns | UX + Architecture | Product + platform | Later | v1 ship data | Household sharing remains coherent as platform scope expands |

## 6. Execution Plan
- Now (0-2 weeks):
  - Decide the in-scope platform matrix.
  - Write the share-accept/storage topology and projection appendix.
  - Write the lifecycle/freshness/copy matrix.
- Next (2-6 weeks):
  - Turn the approved IA into wireframes for owner and invitee flows.
  - Define participant-management and revoke UX in detail.
  - Add rollout metrics, runbook, and feature-flag plan.
- Later (6+ weeks):
  - Expand to macOS parity or multi-owner scaling only after v1 household read-only trust metrics are stable.

## 7. Open Questions
- Does v1 include macOS invitee read-only surfaces, or is macOS explicitly out of scope despite the existing app shell?
- Is owner participant management intentionally system-first through `UICloudSharingController`, or does the team want to own a custom participant-management surface?
- What freshness SLA and failure policy define `stale` versus `temporarilyUnavailable`?
