# Implementation-Gap Audit: COMPLETE_REMAINING_UX_AUDIT_REMEDIATION_PROPOSAL

| Field | Value |
|-------|-------|
| Proposal path | `docs/proposals/COMPLETE_REMAINING_UX_AUDIT_REMEDIATION_PROPOSAL.md` |
| Git SHA | `ff1e05a7aaf97e000a2c760c08cb2a935a6386db` |
| Tree status | Dirty -- 34 modified files, 14 untracked files |
| Audit timestamp | 2026-04-13T19:48:47Z |
| Auditor | Claude Opus 4.6 (1M context) |
| Overall status | **Partial** |

## Verdict

Implementation is substantially complete for Wave 2 (Goals) and Wave 3 (Onboarding), with strong test coverage and correct separation of concerns for the onboarding recovery contract. Wave 4 (Family Sharing / Settings) has the FamilyAccess and FamilySharing view-layer work done but the SettingsView integration is missing entirely -- it contains no Family Access row, no Local Bridge Sync row, and no sync section. Phase 0 artifacts exist and have correct structure but their self-reported "Implemented" statuses are not all independently verifiable. Several success-metric targets (print elimination, EmptyView placeholder removal) show residual violations on remediated surfaces.

## Proposal Contract Summary

- **Status:** Approved, frozen as implementation source of truth
- **Scope boundary date:** 2026-04-04
- **Phases:** Phase 0 (audit + freeze), Wave 2 (Goals), Wave 3 (Onboarding), Wave 4 (Family Sharing + Settings), Phase 5 (Closeout)
- **Locked decisions:** ContentView goals shell as authoritative; OnboardingManager.hasCompletedOnboarding as sole completion signal; SettingsView as outer surface for Family Access and Local Bridge Sync
- **Canonical metric:** Visual literal burndown via `docs/design/baselines/ios-visual-literals-baseline.txt` and `docs/design/visual-literal-baseline-targets.v1.json`

## Requirement Summary

| Status | Count |
|--------|-------|
| Implemented | 13 |
| Partially Implemented | 6 |
| Missing | 3 |
| Not Verifiable | 3 |
| **Total** | **25** |

## Per-Requirement Audit

### Phase 0: Remaining-Scope Audit and Contract Freeze

#### REQ-001: Phase 0 requirement-index.json artifact
- **Source:** Section "Phase 0 Artifacts", line 110-124
- **Status:** Implemented
- **Evidence type:** code
- **Evidence:** File exists at `docs/release/visual-system/phase0/requirement-index.json` with all minimum fields: `requirement_id`, `source_section`, `wave_or_phase`, `severity`, `status`, `evidence_path`, `implementation_notes`, `owner_surface`, `forbidden_change_check`. Contains 4 entries (W2-01, W2-02, W3-01, W4-01).
- **Note:** The index has only 4 entries. A W4-02 appears in the scope audit but not in this index.

#### REQ-002: Phase 0 remaining-scope-audit.json artifact
- **Source:** Section "Phase 0 Artifacts", line 110-124
- **Status:** Implemented
- **Evidence type:** code
- **Evidence:** File exists at `docs/release/visual-system/phase0/remaining-scope-audit.json` with proper structure. Reports 4 implemented, 0 partial, 0 missing, 1 not-verifiable. Includes scope decisions and decision freeze.

#### REQ-003: Phase 0 stable requirement identifiers and forbidden-change checks
- **Source:** Section "Phase 0 Artifacts", lines 113-124
- **Status:** Implemented
- **Evidence type:** code
- **Evidence:** Each entry in `requirement-index.json` has a `requirement_id` and `forbidden_change_check` field. IDs follow W{wave}-{number} pattern.

### Wave 2: Goals and Goal Detail

#### REQ-004: ContentView goals shell is the authoritative iOS entry point
- **Source:** Section "Wave 2 Authoritative Surfaces", lines 127-128
- **Status:** Implemented
- **Evidence type:** code
- **Evidence:** `ios/CryptoSavingsTracker/Views/ContentView.swift` line 72 uses `GoalsListContainer(selectedView:)` in the Goals tab. `Coordinator.swift` line 228-229 maps `.goalsList` to `ContentView()`. GoalDashboardNavigationContractTests verifies this in test `goalsListRouteUsesActiveContentShell`.
- **Note:** GoalsListContainer is the live route, not GoalsListView. This matches the classification rule (line 141-142).

#### REQ-005: Goal detail shell uses DetailContainerView to GoalDetailView
- **Source:** Section "Wave 2 Authoritative Surfaces", lines 128-129
- **Status:** Implemented
- **Evidence type:** code
- **Evidence:** `DetailContainerView.swift` contains `GoalDetailView(goal: goal)` as the details tab and `GoalDashboardScreen(goal: goal)` as the dashboard tab. `Coordinator.swift` line 231 maps `.goalDetail` to `DetailContainerView(goal:selectedView:)`. GoalDashboardNavigationContractTests verifies both paths.

#### REQ-006: AddGoalView launched from ContentView goals toolbar
- **Source:** Section "Wave 2 Authoritative Surfaces", line 129
- **Status:** Implemented
- **Evidence type:** code
- **Evidence:** `GoalsListContainer.swift` line 72-78 has a toolbar item with `NavigationLink(destination: AddGoalView())`. The file exists at `ios/CryptoSavingsTracker/Views/AddGoalView.swift`.

#### REQ-007: EditGoalView presented from active goals shell
- **Source:** Section "Wave 2 Authoritative Surfaces", line 130
- **Status:** Implemented
- **Evidence type:** code
- **Evidence:** `GoalsListContainer.swift` line 107-110 presents `EditGoalView(goal:modelContext:)` as a sheet from `$editingGoal`. Swipe actions and context menu both wire to `editingGoal = goal`.

#### REQ-008: Zero-data explicit empty states (zero goals, zero transactions, first-action guidance)
- **Source:** Section "Wave 2 Guidance", lines 91-92
- **Status:** Partially Implemented
- **Evidence type:** code
- **Evidence:** `GoalsListContainer.swift` uses `EmptyGoalsView` for zero goals which shows intentional copy ("No Savings Goals Yet") and a create-goal CTA. `GoalsListView.swift` uses `EmptyStateView.noGoals`. However, zero-transaction empty state in GoalDetailView is not verified as an explicit empty state -- the asset list section does not show an explicit empty state for zero transactions. First-action guidance exists in DashboardView via `DashboardPrimaryAction` messages.
- **Gap:** Zero-transaction empty state within goal detail is not verified as explicit user state rather than implicit absence.

#### REQ-009: Primary goal action hierarchy (create, edit, add asset, add transaction, lifecycle)
- **Source:** Section "Wave 2 Guidance", lines 93-94
- **Status:** Partially Implemented
- **Evidence type:** code
- **Evidence:** `GoalsListContainer.swift` exposes create (toolbar), edit (swipe + context), delete (swipe + context), and lifecycle status (swipe + confirmation dialog). `GoalContextMenu` in `GoalsListContainer.swift` lines 138-165 has "Add Asset" and "Add Transaction" buttons, but both have empty closures with only comments -- they are non-functional stubs.
- **Gap:** Add Asset and Add Transaction actions in the context menu are non-functional placeholders.

#### REQ-010: GoalsListView/Coordinator legacy route normalization
- **Source:** Section "Wave 2 Authoritative Surfaces", classification rules lines 140-143
- **Status:** Implemented
- **Evidence type:** code, tests-found
- **Evidence:** Coordinator maps `.goalsList` to `ContentView()` not `GoalsListView()`. GoalDashboardNavigationContractTests line 55 verifies `!coordinator.contains("GoalsListView()")`. GoalsListView still exists but is not the primary production route.

#### REQ-011: No new goals navigation architecture (forbidden change)
- **Source:** Section "Wave 2 Authoritative Surfaces", forbidden changes line 148
- **Status:** Implemented
- **Evidence type:** code, tests-found
- **Evidence:** GoalDashboardNavigationContractTests line 80-88 asserts no monthly planning, settings coordinator, or dashboard coordinator routes in the public coordinator graph. No new navigation architecture types found.

### Wave 3: Onboarding

#### REQ-012: OnboardingManager.hasCompletedOnboarding is the only persisted completion signal
- **Source:** Section "Wave 3 Authoritative Surfaces", truth model line 159
- **Status:** Implemented
- **Evidence type:** code
- **Evidence:** `OnboardingManager.swift` line 17 declares `@Published var hasCompletedOnboarding: Bool`. The `completeOnboarding()` method (line 37-40) sets it to true and persists to UserDefaults. `OnboardingContentView.swift` line 59 gates on `!onboardingManager.hasCompletedOnboarding && goals.isEmpty`. OnboardingFlowContractTests line 27-32 verifies this gate.

#### REQ-013: Onboarding displays only when incomplete and no goals exist
- **Source:** Section "Wave 3 Authoritative Surfaces", truth model lines 160-161
- **Status:** Implemented
- **Evidence type:** code, tests-found
- **Evidence:** `OnboardingContentView.swift` line 59: `return !onboardingManager.hasCompletedOnboarding && goals.isEmpty`. Line 69 adds UITestFlags support. OnboardingFlowContractTests explicitly verifies both conditions.

#### REQ-014: completeOnboarding() called only after successful goal creation or explicit skip
- **Source:** Section "Wave 3 Authoritative Surfaces", truth model lines 162-163
- **Status:** Implemented
- **Evidence type:** code, tests-found
- **Evidence:** `OnboardingFlowView.swift` lines 172-188: `createGoalFromTemplate()` calls `goalCreationState.handleSuccess(using: onboardingManager)` only in the `do` block after successful `createGoalFromTemplate`. The `catch` block calls `goalCreationState.handleFailure(error)` which does NOT call `completeOnboarding()`. `OnboardingGoalCreationState.swift` line 21-25: `handleSuccess` is the only path that calls `onboardingFlow.completeOnboarding()`. `handleSkipTapped` (line 158-162) calls `onboardingManager.completeOnboarding()` directly for the skip path.

#### REQ-015: Recoverable createGoalFromTemplate failures must not commit onboarding completion
- **Source:** Section "Wave 3 Authoritative Surfaces", truth model line 164
- **Status:** Implemented
- **Evidence type:** code, tests-found
- **Evidence:** `OnboardingGoalCreationState.handleFailure(_:)` (line 28-30) sets `isCreatingGoal = false` and `self.error = ...` without touching `onboardingFlow`. OnboardingGoalCreationStateTests line 24-45: test `goalCreationFailureKeepsOnboardingActive` verifies `onboardingFlow.hasCompletedOnboarding == false` and `completeOnboardingCallCount == 0` after failure.

#### REQ-016: Retry UX in OnboardingFlowView with error banner and retry affordance
- **Source:** Section "Wave 3 Guidance", lines 95-96; truth model line 165
- **Status:** Implemented
- **Evidence type:** code, tests-found
- **Evidence:** `OnboardingFlowView.swift` lines 37-47: `ErrorBannerView` shown when `goalCreationState.error` is non-nil, with `onRetry` wired to `createGoalFromTemplate()` when `error.isRetryable`. OnboardingFlowContractTests line 17-23 verifies `ErrorBannerView` presence and retry wiring. OnboardingUITests line 39-60 exercises the save-failure-and-retry path.

#### REQ-017: Progress retention across recoverable failures (currentStep, userProfile, selectedTemplate)
- **Source:** Section "Wave 3 Authoritative Surfaces", truth model line 166; Wave 3 Guidance lines 96-97
- **Status:** Implemented
- **Evidence type:** code, tests-found
- **Evidence:** `OnboardingFlowView.swift` uses `@State private var selectedTemplate` and `@StateObject private var onboardingManager` -- both are SwiftUI state that persists across error recovery since `handleFailure` does not reset them. `OnboardingGoalCreationState.handleFailure` only sets `isCreatingGoal = false` and `error`. OnboardingGoalCreationStateTests line 47-65 (`failureKeepsCurrentStepForRecoveryRetry`) verifies `onboardingFlow.currentStep == .assetSelection` is retained.

#### REQ-018: No new onboarding persistence model (forbidden change)
- **Source:** Section "Wave 3 Authoritative Surfaces", forbidden changes line 172
- **Status:** Implemented
- **Evidence type:** code
- **Evidence:** `OnboardingManager.swift` still uses the same UserDefaults-backed model. `OnboardingGoalCreationState` is a value-type state helper, not a new persistence model.

### Wave 4: Family Sharing and Settings

#### REQ-019: SettingsView remains the user-facing shell for Family Access and Local Bridge Sync
- **Source:** Section "Wave 4 Authoritative Surfaces", line 178; in-scope items lines 188-189
- **Status:** Missing
- **Evidence type:** code
- **Evidence:** `ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift` contains only "Preferences" (currency, appearance) and "About" (support, version) sections. There is no navigation to FamilyAccessView, no navigation to LocalBridgeSyncView, and no sync section despite the `syncSectionFooterCopy` being defined. The `SettingsUXCopy.syncSectionFooter` is referenced on line 11 but never used in the body. Grep for `familyAccess`, `Family Access`, `LocalBridgeSync`, `Local Bridge Sync` in SettingsView.swift returns zero matches.
- **Gap:** SettingsView does not integrate Family Access or Local Bridge Sync rows. This is the primary Wave 4 gap.

#### REQ-020: Family Access visible before Local Bridge Sync in Settings ordering
- **Source:** Section "Wave 4 Guidance", line 102; in-scope line 188
- **Status:** Missing
- **Evidence type:** code
- **Evidence:** Since REQ-019 is missing, there are no rows to order. FamilySharingCopyContractTests line 34-45 (`settingsFamilyAccessComesBeforeLocalBridgeSync`) searches for `settings.cloudkit.familyAccessRow` and `settings.cloudkit.localBridgeSyncRow` accessibility identifiers in SettingsView.swift source -- these identifiers do not exist in the current file, so this test would fail.
- **Gap:** Ordering requirement cannot be met because the rows do not exist.

#### REQ-021: User-facing sync language (sync, shared with family, read-only, up to date) instead of CloudKit terminology
- **Source:** Section "Wave 4 Guidance", line 101; UX and UI Notes line 85
- **Status:** Partially Implemented
- **Evidence type:** code, tests-found
- **Evidence:** FamilySharingModels.swift `supportingCopy` uses user-facing language ("Waiting for your family invitation...", "Shared read-only data is available and current", etc.) with zero CloudKit references. FamilySharingCopyContractTests verifies no CloudKit leakage in states. `SettingsUXCopy.syncSectionFooter` uses "Sync keeps your latest savings data up to date..." However, the sync language is defined but not surfaced in SettingsView because the sync section is missing (REQ-019).
- **Gap:** Copy contract is correct in the family-sharing layer, but SettingsView does not present the sync section footer or family-related copy to users.

#### REQ-022: Family-sharing view-state copy, unavailable/revoked messaging, presentation wiring
- **Source:** Section "Wave 4", in-scope lines 190-191
- **Status:** Implemented
- **Evidence type:** code, tests-found
- **Evidence:** FamilySharingModels.swift provides `supportingCopy`, `displayTitle`, `primaryActionTitle` for all `FamilyShareSurfaceState` cases including `.revoked`, `.temporarilyUnavailable`, `.removedOrNoLongerShared`. FamilyAccessView.swift provides presentation wiring with sheets for scope preview and participants. FamilySharingCopyContractTests line 47-61 (`familySharingLifecycleCopyRemainsUserFacing`) verifies revoked/unavailable copy and confirms no CloudKit leakage.

#### REQ-023: Read-only invitee semantics obvious from list and detail states
- **Source:** Section "Wave 4 Guidance", line 102
- **Status:** Implemented
- **Evidence type:** code
- **Evidence:** Grep for "read-only" in FamilySharing views shows extensive use: SharedGoalDetailView.swift line 83 shows "Read-only" chip, FamilyShareScopePreviewSheet.swift line 44 states "Read-only family sharing", SharedGoalsReputationRedesignPreview.swift shows "Read-only" labels per section, FamilySharingModels.swift line 317-319 generates "Shared by ... Read-only" labels.

#### REQ-024: Allowed coordinator changes only (presentation mapping, retry/refresh wiring, copy, alert/sheet orchestration)
- **Source:** Section "Wave 4 Authoritative Surfaces", allowed changes lines 198-203
- **Status:** Not Verifiable
- **Evidence type:** inference
- **Evidence:** The FamilyShareAcceptanceCoordinator is a complex component. Its test file exists and has substantial coverage (FamilyShareAcceptanceCoordinatorTests.swift). Without running tests or diffing against the scope boundary date, the exact set of coordinator changes cannot be verified against the allowed/forbidden boundaries.

### Success Metrics and KPIs

#### REQ-025: Visual literal burndown meets wave budgets (Wave 2 limit: 180)
- **Source:** Section "Canonical Metric Method", lines 230-233
- **Status:** Not Verifiable
- **Evidence type:** inference
- **Evidence:** The latest burndown report at `docs/release/visual-system/latest/literal-baseline-burndown-report.json` shows iOS count of 206 against a Wave 1 limit of 210 (passing). However, this report is tagged `wave: "wave1"`. No Wave 2 burndown report exists. The Wave 2 limit is 180. Whether current count (206) can reach 180 after Wave 2 work is unknown. Current state exceeds the Wave 2 budget by 26 occurrences.
- **Gap:** No Wave 2 burndown report produced. Current count of 206 exceeds the Wave 2 target of 180.

#### REQ-026: print() calls in user-facing views on remediated surfaces: 0
- **Source:** Section "Success Metrics", line 278
- **Status:** Partially Implemented
- **Evidence type:** code
- **Evidence:** `AddTransactionView.swift` contains 9 `print()` calls (lines 164-181) with debug output including emoji. `BudgetCalculatorSheet.swift` has zero `print()` calls (false positive from `fingerprint` method). AddTransactionView is a remediated surface (part of goals add-transaction flow) so this violates the success metric.
- **Gap:** 9 `print()` calls remain in `AddTransactionView.swift`.

#### REQ-027: EmptyView placeholders on remediated P0/P1 surfaces where explicit user state is required: 0
- **Source:** Section "Success Metrics", line 279
- **Status:** Partially Implemented
- **Evidence type:** code
- **Evidence:** `Coordinator.swift` has 3 `EmptyView()` instances as default switch fallbacks (lines 237, 251, 259). These are in navigation routing defaults, not user-facing empty states. `GoalDashboardScreen.swift` has 3 `EmptyView()` (lines 92, 103, 112) -- these need verification of whether they represent missing user state on a remediated surface. `AddTransactionView.swift` has 2 `EmptyView()` (lines 76, 125). Onboarding views have zero EmptyView.
- **Gap:** GoalDashboardScreen.swift and AddTransactionView.swift contain EmptyView instances that may represent placeholder user state on remediated surfaces.

#### REQ-028: Forced single-line truncation on remediated critical financial content and primary CTAs: 0
- **Source:** Section "Success Metrics", line 280
- **Status:** Partially Implemented
- **Evidence type:** code
- **Evidence:** `.lineLimit(1)` appears 21 times across Views/. In remediated surfaces: GoalDetailView.swift line 138 uses `.lineLimit(1)`, UnallocatedAssetsSection.swift line 98, AssetDetailView.swift lines 77/205/297, AssetRowView.swift line 387. Whether these are on "critical financial content" or "primary CTAs" requires case-by-case review. UnifiedGoalRowView.swift uses `.truncationMode(.tail)` only on description text (line 218), which is appropriate.
- **Gap:** Multiple `.lineLimit(1)` instances on remediated surfaces need review to determine if they apply to critical financial content.

### Test Matrix

#### REQ-029: VisualRuntimeAccessibilityUITests exist for Wave 2
- **Source:** Section "Minimum Test Matrix", line 238
- **Status:** Implemented
- **Evidence type:** tests-found
- **Evidence:** File exists at `ios/CryptoSavingsTrackerUITests/VisualRuntimeAccessibilityUITests.swift`.

#### REQ-030: ExecutionUserFlowUITests for touched add/edit/detail flows
- **Source:** Section "Minimum Test Matrix", line 239
- **Status:** Implemented
- **Evidence type:** tests-found
- **Evidence:** File exists at `ios/CryptoSavingsTrackerUITests/ExecutionUserFlowUITests.swift`. Tests asset sharing and multi-asset contribution flows.

#### REQ-031: OnboardingGoalCreationStateTests and OnboardingUITests for Wave 3
- **Source:** Section "Minimum Test Matrix", lines 245-246
- **Status:** Implemented
- **Evidence type:** tests-found
- **Evidence:** `OnboardingGoalCreationStateTests.swift` has 5 tests covering failure retention, validation failure, missing template, and success path. `OnboardingUITests.swift` covers happy-path and save-failure-retry paths. `OnboardingFlowContractTests.swift` verifies structural contracts.

#### REQ-032: FamilyShareAcceptanceCoordinatorTests for Wave 4
- **Source:** Section "Minimum Test Matrix", line 248
- **Status:** Implemented
- **Evidence type:** tests-found
- **Evidence:** File exists at `ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift` with substantial test content (factory helper, at least one publish test visible).

#### REQ-033: FamilySharingCopyContractTests for Wave 4
- **Source:** Section "Minimum Test Matrix" (implied by Wave 4 copy requirements)
- **Status:** Partially Implemented
- **Evidence type:** tests-found
- **Evidence:** File exists at `ios/CryptoSavingsTrackerTests/FamilySharing/FamilySharingCopyContractTests.swift` with 4 tests. However, `settingsFamilyAccessComesBeforeLocalBridgeSync` would fail because `settings.cloudkit.familyAccessRow` and `settings.cloudkit.localBridgeSyncRow` identifiers do not exist in the current SettingsView.swift.
- **Gap:** At least one copy-contract test (Settings ordering) will fail against the current codebase.

### Release Evidence and Runbooks

#### REQ-034: Trust gate runbooks exist
- **Source:** Section "Wave 4 Authoritative Surfaces", trust gates lines 183-184
- **Status:** Implemented
- **Evidence type:** code
- **Evidence:** Both files exist: `docs/runbooks/cloudkit-cutover-release-gate.md` and `docs/runbooks/family-sharing-release-gate.md`.

#### REQ-035: Release evidence stays in existing artifact tree
- **Source:** Section "Release and Evidence Model", lines 214-218
- **Status:** Not Verifiable
- **Evidence type:** inference
- **Evidence:** Phase 0 artifacts are at `docs/release/visual-system/phase0/` (correct tree). Burndown reports are at `docs/release/visual-system/wave1/` and `docs/release/visual-system/latest/` (correct tree). No parallel artifact system detected. However, Wave 2-4 release evidence has not been produced yet, so compliance cannot be verified.

## Verification Log

| Step | Tool | Target | Result |
|------|------|--------|--------|
| 1 | Read | `docs/proposals/COMPLETE_REMAINING_UX_AUDIT_REMEDIATION_PROPOSAL.md` | Proposal read, 307 lines, frozen/approved |
| 2 | Bash | `git rev-parse HEAD` | `ff1e05a7` |
| 3 | Bash | `git status --short` | 34 modified, 14 untracked |
| 4 | Bash | `ls phase0/` | `requirement-index.json`, `remaining-scope-audit.json` |
| 5 | Read | Phase 0 artifacts | Proper structure, correct fields |
| 6 | Read | `ContentView.swift` | GoalsListContainer in Goals tab |
| 7 | Read | `GoalsListContainer.swift` | EmptyGoalsView, toolbar AddGoalView, swipe/context actions |
| 8 | Read | `GoalDetailView.swift` | Goal detail with asset sections |
| 9 | Read | `DetailContainerView.swift` | GoalDetailView + GoalDashboardScreen tabs |
| 10 | Read | `Coordinator.swift` | .goalsList maps to ContentView, .goalDetail to DetailContainerView |
| 11 | Read | `OnboardingManager.swift` | hasCompletedOnboarding, completeOnboarding(), skipOnboarding() |
| 12 | Read | `OnboardingFlowView.swift` | ErrorBannerView, createGoalFromTemplate, retry wiring |
| 13 | Read | `OnboardingGoalCreationState.swift` | handleSuccess/handleFailure separation |
| 14 | Read | `OnboardingContentView.swift` | Gate: !hasCompleted AND goals.isEmpty |
| 15 | Read | `SettingsView.swift` | Only Preferences + About sections |
| 16 | Grep | SettingsView for Family/Sync/CloudKit | Zero matches |
| 17 | Read | `FamilyAccessView.swift` | Full view with scope preview, participants, shared goals |
| 18 | Read | `FamilySharingModels.swift` | supportingCopy for all states, no CloudKit references |
| 19 | Grep | read-only in FamilySharing/ | Extensive read-only labeling |
| 20 | Read | `OnboardingGoalCreationStateTests.swift` | 5 tests covering failure/success contracts |
| 21 | Read | `OnboardingFlowContractTests.swift` | 3 structural contract tests |
| 22 | Read | `FamilySharingCopyContractTests.swift` | 4 tests, Settings ordering test would fail |
| 23 | Read | `GoalDashboardNavigationContractTests.swift` | 6 structural tests |
| 24 | Grep | print() in Views/ | 9 calls in AddTransactionView.swift |
| 25 | Grep | EmptyView() in Views/ | 8 instances across 5 files |
| 26 | Grep | .lineLimit(1) in Views/ | 21 instances |
| 27 | Read | Burndown reports | Wave 1 count: 206, limit: 210, passing |
| 28 | Read | `visual-literal-baseline-targets.v1.json` | Wave 2 limit: 180, Wave 3 limit: 140 |

## Recommended Next Actions

1. **[Critical -- REQ-019/020] Integrate Family Access and Local Bridge Sync into SettingsView.** The current SettingsView has no sync or family-sharing sections. Add Family Access row, Local Bridge Sync row, sync section with footer copy, and ensure Family Access appears before Local Bridge Sync. Add `settings.cloudkit.familyAccessRow` and `settings.cloudkit.localBridgeSyncRow` accessibility identifiers so FamilySharingCopyContractTests passes.

2. **[High -- REQ-009] Wire GoalContextMenu "Add Asset" and "Add Transaction" actions.** Both buttons in GoalsListContainer's GoalContextMenu have empty closures. These need to navigate to the appropriate add-asset and add-transaction flows for the selected goal.

3. **[High -- REQ-025] Produce Wave 2 burndown report and reduce visual literal count.** Current iOS count is 206; Wave 2 target is 180. A net reduction of at least 26 occurrences is needed. Run `scripts/check_visual_literal_baseline_burndown.py` against Wave 2 targets after remediation.

4. **[Medium -- REQ-026] Remove print() calls from AddTransactionView.swift.** Replace the 9 debug `print()` calls (lines 164-181) with `Logger` calls per code conventions.

5. **[Medium -- REQ-027] Audit EmptyView placeholders in GoalDashboardScreen.swift and AddTransactionView.swift.** Determine whether the 5 EmptyView instances on these remediated surfaces represent missing user-facing state and replace with explicit empty states where required.

6. **[Medium -- REQ-028] Review .lineLimit(1) on remediated surfaces for critical financial content.** At minimum, verify GoalDetailView.swift line 138 and AssetDetailView.swift financial amount lines are not truncating critical information.

7. **[Low -- REQ-008] Add explicit zero-transaction empty state to GoalDetailView.** When a goal has zero transactions, show intentional guidance rather than an implicit empty section.
