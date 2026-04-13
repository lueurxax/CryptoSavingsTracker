{
  "proposal_id": "50204E8B-319E-4CC4-8CFF-21704A25ADB1",
  "title": "Comprehensive UX Audit and Remediation",
  "type": "improvement",
  "scope": "full-app",
  "platforms": ["iOS", "macOS"],
  "revision": 4,
  "date": "2026-04-02",
  "status": "revised",
  "revision_basis": "state_5_proposal_refined.2/proposal_writer/1/proposal_current",
  "review_pass_addressed": "state_4_proposal_reviewed.3",

  "section_1_problem_statement": {
    "title": "Problem Statement",
    "content": "CryptoSavingsTracker is a finance-critical application with 156 SwiftUI view files (96 primary views + 60 preview files) across 10 feature domains (Dashboard, Planning, Goals, Charts, Components, Settings, FamilySharing, Onboarding, Shared, and root-level views). The project has undergone three incremental UI/UX reviews (R1-R3) and a Visual System Unification with four review rounds culminating in a UX metrics baseline (14 participants, 72 tasks, 2026-03-03). Navigation and presentation consistency guidelines (MOD-01 through MOD-05) and a visual token contract (visual-tokens.v1.json) are established.",
    "existing_infrastructure_acknowledgment": "The codebase has strong foundational infrastructure that this proposal builds upon: (1) AppError enum with 25 cases in Utilities/ErrorHandling.swift covering network, API, data, calculation, and platform errors, plus ErrorHandler singleton, ErrorAlertModifier, and AsyncErrorHandler with retry logic; (2) ViewState enum in Utilities/ServiceResult.swift (.idle, .loading, .loaded, .error(UserFacingError), .degraded) adopted by 4 of 9 ViewModels; (3) ServiceResult<T> enum with .fresh/.cached/.fallback/.failure states providing data-freshness metadata; (4) UserFacingError struct with ErrorTranslator pipeline for converting AppError to user-friendly messages; (5) AccessibilityManager (477 lines) with VoiceOver detection, haptic feedback, financial amount descriptions, chart accessibility labels, and audit scoring; (6) VisualComponentTokens.swift with domain-specific corner radius and fill tokens; (7) visual-tokens.v1.json cross-platform token contract (contractVersion v1, active, 8 requiredStates).",
    "genuine_gaps": [
      {
        "gap": "Zero localization infrastructure",
        "detail": "All user-facing strings across all 156 view files are hardcoded English literals. No String(localized:), NSLocalizedString, .xcstrings, or Localizable.strings exists anywhere. This blocks international release and is the single largest UX gap. NOTE: This is an internationalization gap, not a UX deficiency for current English-speaking users. It is presented as a separate scope decision (Workstream W4).",
        "severity": "critical_for_international_release",
        "verified": true
      },
      {
        "gap": "Incomplete design-token adoption for spacing and sizing",
        "detail": "Hardcoded magic numbers (padding(4), padding(8), padding(10), padding(12), padding(16), padding(24), spacing: 12, cornerRadius(8), etc.) throughout view files. VisualComponentTokens.swift defines corner radius and fill tokens but has zero spacing tokens. The visual-tokens.v1.json contract does not yet include spacing/sizing roles. NOTE: The proposal originally counted 309 occurrences using unique-value methodology. Independent verification found ~818 total instances including duplicates. Phase 0 Migration Scope Sizing Report will produce the authoritative count using per-file occurrence methodology that matches actual migration effort.",
        "severity": "major",
        "verified": true,
        "count_note": "309 (unique-value methodology) vs ~818 (total instances). Phase 0 will reconcile using migration methodology."
      },
      {
        "gap": "Limited Dynamic Type support",
        "detail": "Only 4 of 156 view files (2.6%) use @Environment(\\.dynamicTypeSize): BudgetSummaryCard, SharedGoalDetailView, FamilyShareFreshnessCardView, FamilyShareFreshnessHeaderView. The remaining 152 files have no Dynamic Type adaptation, risking layout breakage at accessibility text sizes.",
        "severity": "major",
        "verified": true
      },
      {
        "gap": "Incomplete ViewState adoption",
        "detail": "4 of 9 ViewModels (DashboardViewModel, AssetViewModel, GoalRowViewModel, GoalViewModel) use the ViewState pattern. 2 (MonthlyPlanningViewModel, MonthlyExecutionViewModel) use legacy @Published var error: Error?. 3 (GoalEditViewModel, GoalDashboardViewModel, CurrencyViewModel) use ad-hoc or no explicit error state pattern.",
        "severity": "major",
        "verified": true
      },
      {
        "gap": "Inconsistent error messaging in Charts",
        "detail": "20 chart view files use varying error/empty state messages ('No data', 'Add data first', etc.) with no standard format.",
        "severity": "major",
        "verified": true
      },
      {
        "gap": "Generic CloudKit error diagnosis in FamilySharing",
        "detail": "While FamilyShareParticipantsView has retry buttons for .pending/.failed states and FamilyShareFreshnessHeaderView has context-aware retry labels, the error messages do not diagnose specific CKError codes (quota, permission, network) — they show generic failure messages.",
        "severity": "major",
        "verified": true
      },
      {
        "gap": "Missing contextual recovery guidance in some error states",
        "detail": "ErrorStateView has isRetryable gating with Try Again button and ErrorBannerView supports onRetry callback. However, some error presentations lack contextual guidance about what specifically went wrong and what the user should do beyond retrying.",
        "severity": "major",
        "verified": true
      },
      {
        "gap": "ErrorStateView uses raw color literals for icon colors",
        "detail": "ErrorStateView uses raw .orange and .red for iconColor instead of VisualComponentTokens.statusWarning and statusError. As a reusable error component consumed by multiple screens, this token compliance gap cascades downstream.",
        "severity": "major",
        "verified": true,
        "added_in_revision": 3,
        "raised_by": "LIFT-13 (ui_designer)"
      }
    ],
    "view_count_clarification": "The idea brief estimated '96+ view files'. Verified count is 156 .swift files under ios/CryptoSavingsTracker/Views/. The discrepancy is explained: 60 of the 156 are *Preview.swift files, leaving 96 primary view files — matching the original estimate. The full audit covers all 156 files (previews are verification targets), but remediation effort concentrates on the 96 primary view files.",
    "magic_number_count_clarification": "Revision 2 reported 309 occurrences of hardcoded spacing/sizing magic numbers. Independent architect verification found ~818 instances. The discrepancy is methodological: 309 counts unique value patterns, ~818 counts every individual occurrence including duplicates across files. The actual migration effort correlates with the total instance count (~818), not the unique-value count. Phase 0 Migration Scope Sizing Report (new deliverable) will produce the authoritative per-file instance count to validate workstream estimates."
  },

  "section_2_goals": {
    "title": "Goals",
    "goals": [
      {
        "id": "G1",
        "goal": "Produce a verified UX findings inventory covering all 96 primary view files",
        "success_criteria": "Structured findings report with every finding verified against actual source code; severity classifications evidence-based; zero screens skipped; Migration Scope Sizing Report with per-file magic number counts, corner radius occurrence counts, and Dynamic Type triage",
        "workstream": "Phase 0 (shared)"
      },
      {
        "id": "G2",
        "goal": "Achieve WCAG AA accessibility compliance across all interactive screens",
        "success_criteria": "All interactive elements have accessibility labels; 44pt minimum touch target at standard text sizes; no color-only status indicators; Dynamic Type tested at AX1, AX2, AX3, and AX5 sizes; VoiceOver users can complete all core flows without sighted assistance; keyboard navigation can complete all 5 core journeys on macOS without mouse/trackpad; 100% of views categorized and all needs-adaptation views adapted",
        "workstream": "W1"
      },
      {
        "id": "G3",
        "goal": "Standardize error handling UX across all feature domains",
        "success_criteria": "Every screen with async data uses the canonical error presentation pattern (inline, full-screen, or alert per the UI Pattern Catalog); all 9 ViewModels use the ViewState pattern; per-section error state for composite views; retry-exhaustion escalation after 3 failures; existing ErrorTranslator extended with CloudKit-specific translations; plan-to-execution transition designed and implemented",
        "workstream": "W2"
      },
      {
        "id": "G4",
        "goal": "Replace all hardcoded spacing/sizing with visual token references",
        "success_criteria": "95% or more magic number literals replaced (15 or fewer documented exceptions with rationale); VisualComponentTokens extended with Spacing and CornerRadius enums; corner radius migration mapping table in place; new tokens added to visual-tokens.v1.json; reusable components (EmptyStateView, ErrorStateView) migrated first as reference implementations; preview files included in migration scope",
        "workstream": "W3"
      },
      {
        "id": "G5",
        "goal": "Establish localization infrastructure and migrate all user-facing strings (SEPARATE SCOPE DECISION)",
        "success_criteria": "String(localized:) with .xcstrings catalog adopted; all hardcoded strings in active views migrated; pluralization rules defined for count-dependent strings; currency and date formatting use locale-aware formatters",
        "workstream": "W4 (requires separate approval)"
      },
      {
        "id": "G6",
        "goal": "Validate all fixes against UX metrics baseline without regression",
        "success_criteria": "All existing tests pass; new accessibility regression assertions for high-traffic views; accessibility audit produces zero new issues; automated metrics (CI gates, accessibility assertions, preview snapshots) meet or exceed baseline",
        "workstream": "Per-workstream validation"
      }
    ]
  },

  "section_3_non_goals": {
    "title": "Non-Goals",
    "items": [
      "Full visual rebrand or typography redesign — the visual token contract is established; this effort adopts tokens, not redesigns them.",
      "Android UX remediation — Android is at ~90% feature completion; its UX audit is a separate effort.",
      "New feature development — no new screens, flows, or capabilities. This is purely quality and polish on existing functionality.",
      "SwiftData schema migration — no data model changes. If a UX fix would require schema changes, it is deferred.",
      "Chart palette redesign — per the Visual System Unification non-goals, advanced data visualization palette work is out of scope.",
      "Full iPad/macOS redesign — minimum defaults for MOD-01 through MOD-05 suffice; comprehensive iPad-optimized layouts are out of scope. Basic macOS keyboard navigation, hover feedback, and pointer interaction are verified in Phase 0 and addressed per-workstream.",
      "visionOS UI implementation — platform capabilities are defined but UI is not yet implemented; separate workstream.",
      "Comprehensive animation token system — acknowledged as a gap but deferred. State transitions will use the standard transition behavior defined in Section 7 UI Pattern Catalog (Transitions subsection) with reduce-motion support. A comprehensive animation token system is a separate design effort.",
      "Loading skeleton/shimmer patterns — acknowledged as desirable but deferred. ProgressView with contextual hint text is the interim solution for all loading durations."
    ]
  },

  "section_4_findings_summary": {
    "title": "Verified UX Findings Summary",
    "methodology_note": "All findings in this revision have been verified against the actual codebase with file paths and line numbers. Findings from revision 1 that were refuted by codebase evidence have been removed (C3, C5, M4, M12). Findings that were overstated have been downgraded and re-scoped (C4, C6, C7, M2).",
    "revision_3_note": "Revision 3 adds finding M16 (ErrorStateView raw color literals) per LIFT-13 feedback from UI designer.",
    "findings_by_severity": {
      "critical": [
        {
          "id": "C1",
          "domain": "Localization",
          "screen_area": "All screens",
          "finding": "No String(localized:) or NSLocalizedString usage in any view file. All 156 view files contain hardcoded English string literals for titles, labels, buttons, error messages, and descriptions.",
          "verified": true,
          "scope_note": "Critical for international release. For English-only users, this is a code-quality gap, not a UX deficiency. Addressed by W4 (separate approval required). Not counted in main severity distribution since W4 requires independent scope approval."
        },
        {
          "id": "C2",
          "domain": "Localization",
          "screen_area": "All screens",
          "finding": "Error messages, recovery suggestions, and user-facing text in UserFacingError struct and ErrorTranslator are hardcoded English. ViewModels and service-layer error strings are not localizable.",
          "verified": true,
          "scope_note": "Same scope note as C1. Addressed by W4. Not counted in main severity distribution since W4 requires independent scope approval."
        }
      ],
      "major": [
        {
          "id": "M1",
          "domain": "Token Compliance",
          "screen_area": "All screens",
          "finding": "Hardcoded padding, spacing, and cornerRadius magic numbers across view files instead of VisualComponentTokens references. Common values: 4, 8, 10, 12, 16, 20, 24. VisualComponentTokens has zero spacing tokens currently. Count: 309 by unique-value methodology, ~818 by total-instance methodology. Phase 0 will produce authoritative per-file count.",
          "verified": true,
          "workstream": "W3",
          "count_methodology_note": "Phase 0 Migration Scope Sizing Report will reconcile using migration-effort methodology (per-file occurrence count)."
        },
        {
          "id": "M2",
          "domain": "Dynamic Type",
          "screen_area": "152 of 156 view files",
          "finding": "Only 4 files (2.6%) use @Environment(\\.dynamicTypeSize): BudgetSummaryCard, SharedGoalDetailView, FamilyShareFreshnessCardView, FamilyShareFreshnessHeaderView. The remaining 152 files have no Dynamic Type adaptation. ViewThatFits is used in some views but coverage is limited. Layout breakage risk at accessibility text sizes.",
          "verified": true,
          "workstream": "W1"
        },
        {
          "id": "M3",
          "domain": "Error States",
          "screen_area": "Charts (20 files)",
          "finding": "Inconsistent error/empty messaging: some show 'No data', others 'Add data first'; no standard error format. ChartErrorView exists but is not consistently used across all 20 chart files.",
          "verified": true,
          "workstream": "W2"
        },
        {
          "id": "M5",
          "domain": "Context",
          "screen_area": "Goals",
          "finding": "Lifecycle action dialog title 'Update Goal Status' is generic; should include the goal name for context so users know which goal they are acting on.",
          "verified": true,
          "workstream": "W2"
        },
        {
          "id": "M6",
          "domain": "Confirmation",
          "screen_area": "Goals",
          "finding": "Swipe-to-delete triggers deletion without a preview of consequences (e.g., 'This will remove all allocations'). Design decision recorded: undo snackbar for single-item deletions (soft-delete with 10-second undo window); confirmation dialog for bulk or cascading operations. Full undo snackbar spec defined as P7a variant in Section 7. See Section 12 Q7.",
          "verified": true,
          "workstream": "W2",
          "design_decision": "Recorded in revision 3 per LIFT-12. Full P7a spec added in revision 4 per LIFT-R3-01."
        },
        {
          "id": "M7",
          "domain": "Localization",
          "screen_area": "Components",
          "finding": "EmptyStateView.swift predefined factories contain 10+ hardcoded title/description strings that should be localized.",
          "verified": true,
          "workstream": "W4"
        },
        {
          "id": "M8",
          "domain": "Token Compliance",
          "screen_area": "Components",
          "finding": "Illustration backgrounds use AccessibleColors.lightBackground directly instead of token references; button corners hardcoded to 8. EmptyStateView button uses .blue literal instead of AccessibleColors.primaryInteractive.",
          "verified": true,
          "workstream": "W3"
        },
        {
          "id": "M9",
          "domain": "Localization",
          "screen_area": "Settings",
          "finding": "Section titles ('Data', 'Sync', 'Monthly Planning'), footer descriptions, and CloudKit explanation text are not localized.",
          "verified": true,
          "workstream": "W4"
        },
        {
          "id": "M10",
          "domain": "Error Recovery",
          "screen_area": "Settings",
          "finding": "Export failure shows alert only, with no recovery suggestion or retry option. This is a dead-end error state.",
          "verified": true,
          "workstream": "W2"
        },
        {
          "id": "M11",
          "domain": "Error Recovery",
          "screen_area": "Planning",
          "finding": "'Rates unavailable' message lacks recovery instructions or explanation of when rates will be refreshed.",
          "verified": true,
          "workstream": "W2"
        },
        {
          "id": "M13",
          "domain": "Error Recovery",
          "screen_area": "FamilySharing",
          "finding": "Downgraded from C4. Retry buttons exist for .pending/.failed states, but error messages do not diagnose specific CKError codes. Users cannot distinguish network failure from quota exceeded from permission denied. Top 5 CKError cases should have specific user-facing messages.",
          "verified": true,
          "was_finding": "C4",
          "change": "Downgraded from Critical to Major — retry mechanism exists, gap is in error specificity",
          "workstream": "W2"
        },
        {
          "id": "M14",
          "domain": "Error Recovery",
          "screen_area": "Dashboard",
          "finding": "Downgraded from C6. ErrorStateView has isRetryable/Try Again and ErrorBannerView supports onRetry. Gap is in contextual recovery guidance: error diagnostics card could explain what specifically failed and suggest specific next steps beyond retry.",
          "verified": true,
          "was_finding": "C6",
          "change": "Downgraded from Critical to Major — retry mechanism exists, gap is in contextual guidance",
          "workstream": "W2"
        },
        {
          "id": "M15",
          "domain": "Error Handling",
          "screen_area": "ViewModels",
          "finding": "Downgraded from C7. 5 of 9 ViewModels do not use the ViewState pattern: MonthlyPlanningViewModel and MonthlyExecutionViewModel use legacy @Published var error: Error?; GoalEditViewModel, GoalDashboardViewModel, and CurrencyViewModel use ad-hoc or no explicit error state. The 4 ViewModels using ViewState (Dashboard, Asset, GoalRow, Goal) are well-implemented.",
          "verified": true,
          "was_finding": "C7",
          "change": "Downgraded from Critical to Major — 4/9 VMs already migrated; this is a completion task, not a systemic gap",
          "workstream": "W2"
        },
        {
          "id": "M16",
          "domain": "Token Compliance",
          "screen_area": "Components",
          "finding": "ErrorStateView uses raw .orange and .red for iconColor instead of VisualComponentTokens.statusWarning and statusError. As a reusable error component consumed by multiple screens, this token compliance gap cascades downstream. Missing from revision 2 findings.",
          "verified": true,
          "workstream": "W3",
          "added_in_revision": 3,
          "raised_by": "LIFT-13 (ui_designer)"
        }
      ],
      "minor": [
        {
          "id": "m1",
          "domain": "Accessibility",
          "finding": "Missing .accessibilityElement(children: .combine) on card groupings in Dashboard.",
          "workstream": "W1"
        },
        {
          "id": "m2",
          "domain": "Accessibility",
          "finding": "Missing accessibility hints for swipe actions in Goals (VoiceOver users cannot discover them).",
          "workstream": "W1"
        },
        {
          "id": "m3",
          "domain": "Accessibility",
          "finding": "Numeric values (percentages, amounts) not labeled with accessibility value types across multiple screens.",
          "workstream": "W1"
        },
        {
          "id": "m4",
          "domain": "Token Compliance",
          "finding": "Onboarding LinearGradient colors hardcoded instead of using design token references.",
          "workstream": "W3"
        },
        {
          "id": "m5",
          "domain": "Loading States",
          "finding": "Charts use ProgressView only; no contextual hint about what is loading.",
          "workstream": "W2"
        },
        {
          "id": "m6",
          "domain": "Context",
          "finding": "Settings 'Import Data' button has no explanation of expected format or behavior. Remediation expanded: add inline description below button, plus a pre-import confirmation step showing count of items to import, conflict detection, and Cancel/Replace All/Merge options.",
          "workstream": "W2",
          "import_confirmation_spec": "Added in revision 4 per LIFT-R3-12. After file selection, display a summary sheet listing what will be imported (N goals, N allocations) and whether conflicts exist with current data. Options: Cancel, Replace All, Merge. Merge is the default to minimize data-loss risk in a finance app."
        },
        {
          "id": "m7",
          "domain": "Context",
          "finding": "Planning timeline section hides secondary actions without explicit disclosure affordance.",
          "workstream": "W1"
        },
        {
          "id": "m8",
          "domain": "Consistency",
          "finding": "Empty state messaging varies across 20 chart files; no single pattern.",
          "workstream": "W2"
        },
        {
          "id": "m9",
          "domain": "Token Compliance",
          "finding": "Some card backgrounds use .regularMaterial directly instead of token-wrapped surface reference.",
          "workstream": "W3"
        },
        {
          "id": "m10",
          "domain": "Token Compliance",
          "finding": "Button colors in EmptyStateView use .blue literal instead of AccessibleColors.primaryInteractive.",
          "workstream": "W3"
        },
        {
          "id": "m11",
          "domain": "Platform",
          "finding": "Residual #if os(iOS) guards where PlatformCapabilities should be preferred.",
          "workstream": "W3"
        },
        {
          "id": "m12",
          "domain": "Context",
          "finding": "Family sharing row visible when feature flag is on but no explanation when disabled.",
          "workstream": "W2"
        },
        {
          "id": "m13",
          "domain": "Accessibility",
          "finding": "Chart colors lack WCAG AAA contrast validation documentation.",
          "workstream": "W1"
        },
        {
          "id": "m14",
          "domain": "Feedback",
          "finding": "Payment count calculation edge case (paymentCount == 0) UX messaging could be clearer.",
          "workstream": "W2"
        },
        {
          "id": "m15",
          "domain": "Accessibility",
          "finding": "EmptyStateView missing @Environment dynamicTypeSize — large text sizes may break illustration layouts.",
          "workstream": "W1"
        },
        {
          "id": "m16",
          "domain": "Interaction",
          "finding": "No recovery path if user dismisses onboarding mid-flow; state is unclear on re-entry. Remediation: add 'Restart Tutorial' option in Settings and user-prompted resume on next app launch.",
          "workstream": "W1",
          "recovery_mechanism": "Settings > 'Restart Tutorial' option. On premature dismissal, app persists last-completed step. On next launch, display a non-modal prompt: 'You paused setup. Continue where you left off? [Continue Setup] [Skip]'. User decides whether to resume. Changed from automatic resume to user-prompted resume in revision 4 per LIFT-R3-11 to respect user agency."
        },
        {
          "id": "m17",
          "domain": "Feedback",
          "finding": "Toast/notification timing not accessible (may disappear before VoiceOver reads them). Addressed by P7 Transient Confirmation pattern (revision 3).",
          "workstream": "W1"
        },
        {
          "id": "m18",
          "domain": "Interaction",
          "finding": "Gesture recognizers lack VoiceOver-equivalent actions.",
          "workstream": "W1"
        }
      ],
      "removed_findings": [
        {
          "id": "C3",
          "original_claim": "FamilySharing freshness badge relies on color alone without text fallback.",
          "reason_removed": "Refuted. FamilyShareFreshnessHeaderView uses tierIcon (SF Symbol) + tierColor + label.primaryMessage (text). Lines 26-37 show full compound indicator.",
          "evidence_file": "ios/CryptoSavingsTracker/Views/FamilySharing/FamilyShareFreshnessHeaderView.swift"
        },
        {
          "id": "C5",
          "original_claim": "Planning budget feasibility status icons use color-coded indicators without sufficient text context.",
          "reason_removed": "Refuted. BudgetSummaryCard uses state.iconName + state.tone.color + state.statusText in HStack at lines 422-429. Full icon+tone+text compound indicator.",
          "evidence_file": "ios/CryptoSavingsTracker/Views/Planning/BudgetSummaryCard.swift"
        },
        {
          "id": "M4",
          "original_claim": "FamilySharing participant list has no empty state view.",
          "reason_removed": "Refuted. FamilyShareParticipantsView checks participants.isEmpty at line 18 and renders a dedicated empty state card with person.3 icon, 'No Participants Yet' title, and descriptive text.",
          "evidence_file": "ios/CryptoSavingsTracker/Views/FamilySharing/FamilyShareParticipantsView.swift"
        },
        {
          "id": "M12",
          "original_claim": "No Result<Success, Error> usage; no error recovery suggestion enum.",
          "reason_removed": "Refuted. AppResult<T> typealias and ServiceResult<T> enum with .fresh/.cached/.fallback/.failure states exist in ServiceResult.swift. UserFacingError with recoverySuggestion and isRetryable fields provides recovery guidance. ErrorTranslator maps all AppError cases to user-facing messages.",
          "evidence_file": "ios/CryptoSavingsTracker/Utilities/ServiceResult.swift"
        }
      ]
    },
    "findings_by_domain_summary": {
      "localization": { "critical": 2, "major": 2, "minor": 0, "total": 4, "workstream": "W4", "note": "Not counted in main severity distribution (W4 requires separate approval)" },
      "accessibility": { "critical": 0, "major": 1, "minor": 8, "total": 9, "workstream": "W1" },
      "error_recovery": { "critical": 0, "major": 5, "minor": 2, "total": 7, "workstream": "W2" },
      "token_compliance": { "critical": 0, "major": 3, "minor": 4, "total": 7, "workstream": "W3", "note": "M16 added in revision 3" },
      "dynamic_type": { "critical": 0, "major": 1, "minor": 1, "total": 2, "workstream": "W1" },
      "error_handling": { "critical": 0, "major": 1, "minor": 0, "total": 1, "workstream": "W2" },
      "context_feedback": { "critical": 0, "major": 2, "minor": 5, "total": 7, "workstream": "W2" },
      "platform": { "critical": 0, "major": 0, "minor": 1, "total": 1, "workstream": "W3" },
      "total": { "critical": 2, "major": 14, "minor": 18, "total": 34, "note": "32 in scope (W1+W2+W3); 4 localization findings in W4 separate scope" }
    }
  },

  "section_5_user_journey_analysis": {
    "title": "User Journey Analysis",
    "description": "End-to-end analysis of the 5 core user journeys to identify friction points, dead ends, unclear transitions, and mental model mismatches that component-level audits cannot surface.",
    "journeys": [
      {
        "id": "J1",
        "name": "Onboarding to First Goal",
        "flow": "App launch -> Onboarding screens -> Dashboard (empty) -> Create Goal -> Configure target -> Dashboard (with goal)",
        "friction_points": [
          {
            "location": "Onboarding dismissal",
            "issue": "If user dismisses onboarding mid-flow, state is unclear on re-entry. No way to restart onboarding or review what was missed.",
            "finding_ref": "m16",
            "severity": "minor",
            "designed_recovery": "Add 'Restart Tutorial' option in Settings (under a 'Help & Support' section). On premature dismissal, the app persists the last-completed onboarding step; on next launch, display a non-modal prompt: 'You paused setup. Continue where you left off? [Continue Setup] [Skip]'. User decides whether to resume. This respects user agency — the user may have deliberately dismissed onboarding. Users can also trigger a full restart from Settings at any time.",
            "revision_4_change": "Changed from automatic resume to user-prompted resume per LIFT-R3-11. Automatic resume could frustrate users who deliberately dismissed onboarding."
          },
          {
            "location": "Empty dashboard -> Create goal",
            "issue": "EmptyStateView provides CTA to create first goal, which is good. However, gradient colors in onboarding are hardcoded, not token-compliant.",
            "finding_ref": "m4",
            "severity": "minor"
          }
        ],
        "dead_ends": [],
        "transition_gaps": ["Onboarding does not explicitly guide user to the 'Create Goal' action on Dashboard. The transition relies on the empty state CTA."],
        "overall_assessment": "Generally smooth. Primary issue is onboarding dismissal recovery, now addressed with user-prompted recovery mechanism."
      },
      {
        "id": "J2",
        "name": "Monthly Planning Cycle",
        "flow": "Dashboard -> Monthly Planning -> Budget review -> Set allocations -> Execute -> Track progress -> Month end",
        "friction_points": [
          {
            "location": "Rates unavailable",
            "issue": "When exchange rates are unavailable, the 'Rates unavailable' message provides no recovery instructions or timeline for when rates will refresh. Users cannot proceed with planning if rates are required.",
            "finding_ref": "M11",
            "severity": "major"
          },
          {
            "location": "Planning -> Execution transition",
            "issue": "The transition from plan creation to execution tracking is not explicitly guided. Users must navigate back to dashboard and into the execution view separately.",
            "finding_ref": null,
            "severity": "minor",
            "designed_transition": "After plan save succeeds, show an inline secondary action (Button style: .bordered, not .borderedProminent) beneath the save confirmation: 'Continue to Execution'. The action navigates to MonthlyExecutionView for the current month. If dismissed or not tapped, the save confirmation auto-dismisses after 5 seconds and returns to the plan view. The execution view remains accessible from Dashboard. This is scoped into W2 Phase B as a navigation improvement.",
            "revision_4_change": "Added visual hierarchy specification per LIFT-R3-10: secondary .bordered button, appearing after save confirmation, dismissible, auto-dismisses after 5 seconds."
          },
          {
            "location": "Payment count edge case",
            "issue": "When paymentCount == 0, the messaging could be clearer about why no payments are scheduled.",
            "finding_ref": "m14",
            "severity": "minor"
          }
        ],
        "dead_ends": ["Rates unavailable with no recovery path is a functional dead end for rate-dependent planning."],
        "transition_gaps": ["Plan-to-execution transition now designed with full visual spec: secondary .bordered CTA after save, scoped to W2 Phase B."],
        "overall_assessment": "Core flow works but has a dead end when rates are unavailable. The MonthlyPlanningViewModel and MonthlyExecutionViewModel using legacy Error? pattern (not ViewState) means error states may not be as well-structured as other flows. Plan-to-execution gap addressed with designed transition in revision 3, visual spec refined in revision 4."
      },
      {
        "id": "J3",
        "name": "Dashboard Status Check",
        "flow": "App launch -> Dashboard -> Review goal status -> Check portfolio value -> Review alerts/diagnostics",
        "friction_points": [
          {
            "location": "Error diagnostics",
            "issue": "Error diagnostics card has retry but lacks contextual guidance about what failed and specific next steps.",
            "finding_ref": "M14",
            "severity": "major"
          },
          {
            "location": "Stale data",
            "issue": "When network is unavailable, cached data is shown but there is no explicit 'Last updated X ago' indicator or stale-data communication. Users may not realize they are seeing outdated information in a finance-critical context.",
            "finding_ref": null,
            "severity": "major_new",
            "discoverability_note": "Stale data recovery relies on pull-to-refresh which has poor discoverability. A visible 'Refresh' button fallback is provided for stale states — see Section 6.6."
          }
        ],
        "dead_ends": [],
        "transition_gaps": ["Stale data state is not explicitly communicated. ServiceResult.cached(T, age:) exists at the service layer but may not surface age information in the UI."],
        "overall_assessment": "DashboardViewModel uses ViewState pattern — foundational error handling is solid. Gaps are in contextual guidance quality and stale-data communication. Pull-to-refresh discoverability addressed with visible Refresh button fallback. Dashboard uses per-section error state for composite data sources (revision 4)."
      },
      {
        "id": "J4",
        "name": "Family Sharing Setup",
        "flow": "Settings -> Enable Family Sharing -> Invite participants -> Participants view -> Shared goal list",
        "friction_points": [
          {
            "location": "CloudKit failure",
            "issue": "Generic error messages for CloudKit failures. Users cannot distinguish network issues from quota exceeded from permission denied. Specific CKError diagnosis needed for top 5 errors.",
            "finding_ref": "M13",
            "severity": "major"
          }
        ],
        "dead_ends": [],
        "transition_gaps": ["Family sharing feature flag row in Settings has no explanation when the flag is disabled."],
        "overall_assessment": "Flow is functional with retry mechanisms in place. Primary gap is error diagnosis specificity. Empty states and freshness indicators are well-implemented (verified)."
      },
      {
        "id": "J5",
        "name": "Settings and Data Export",
        "flow": "Dashboard -> Settings -> Configure preferences -> Export data -> Import data",
        "friction_points": [
          {
            "location": "Export failure",
            "issue": "Export failure shows alert only with no recovery suggestion or retry option. Dead-end error state.",
            "finding_ref": "M10",
            "severity": "major"
          },
          {
            "location": "Import data",
            "issue": "Import Data button provides no explanation of expected format, file type, or behavior. No preview of import consequences. No conflict resolution for existing data.",
            "finding_ref": "m6",
            "severity": "minor",
            "designed_guidance": "Add inline description below Import button: 'Import goals and allocations from a JSON file exported by this app.'",
            "import_confirmation_flow": "After file selection, display a summary sheet showing: (1) count of items to be imported (N goals, N allocations), (2) conflict detection against existing data (e.g., '3 goals already exist'), (3) action options: Cancel, Replace All, Merge (default). Merge is the safest default for a finance app. This is critical for data safety — importing without preview could overwrite financial data without user awareness.",
            "revision_4_change": "Added import confirmation flow with merge-vs-replace semantics per LIFT-R3-12."
          }
        ],
        "dead_ends": ["Export failure with no recovery."],
        "transition_gaps": [],
        "overall_assessment": "Settings flow has two UX gaps: export failure dead end and import format opacity with unsafe import semantics. Both addressed with designed solutions in this revision."
      }
    ]
  },

  "section_6_architecture": {
    "title": "Architecture and Technical Approach",

    "audit_methodology": {
      "title": "6.1 Audit Methodology",
      "description": "The audit uses a multi-method approach. Phase 0 validates the findings inventory from this proposal against the actual codebase before any remediation begins.",
      "methods": [
        "Static SwiftUI analysis — file-by-file review of all 96 primary view files against checklist derived from visual token contract, navigation policy (MOD-01 through MOD-05), accessibility contract, and platform HIG.",
        "Xcode Previews inspection — compile all 60 *Preview.swift files at standard, AX1, AX2, AX3, and AX5 Dynamic Type sizes, in both light and dark mode. Snapshot verification matrix: iPhone SE, iPhone 15 Pro Max, at Default/AX1/AX2/AX3/AX5 Dynamic Type, Light/Dark mode. AX1 and AX2 are included to verify smooth transitions between breakpoints, not just endpoint behavior.",
        "Accessibility audit — Xcode Accessibility Inspector against all interactive screens. Focus: VoiceOver navigation order, Dynamic Type adaptation, color contrast WCAG AA, 44pt minimum touch targets. Leverage existing AccessibilityManager.accessibilityAuditScore() as automated regression metric.",
        "User journey walkthrough — trace the 5 core journeys (Section 5) end-to-end in simulator, noting friction points, dead ends, and unclear transitions.",
        "Baseline comparison — compare findings against wave1 UX metrics baseline (14 participants, 72 tasks) and accessibility report.",
        "macOS interaction parity audit — verify keyboard navigability (Tab order, Return to activate), hover feedback on interactive elements, and right-click context menus. Ensure all 5 core journeys are completable via keyboard on macOS."
      ],
      "revision_4_change": "Preview inspection matrix expanded to include AX1 and AX2 sizes per LIFT-R3-07 and UX reviewer feedback. Touch target audit added per LIFT-R3-16."
    },

    "localization_architecture": {
      "title": "6.2 Localization Architecture (Workstream W4)",
      "scope_note": "This is the single largest scope item and was NOT part of the original user request for UX remediation. It is presented as a separate workstream requiring independent approval. If deferred, C1/C2 are reclassified as Major (code quality gap).",
      "approach": "Adopt Swift 5.9+ String(localized:) with .xcstrings string catalog. Initial language: English only. Infrastructure enables future languages without code changes.",
      "string_migration": {
        "pattern_before": "Text(\"Goal Snapshot\")",
        "pattern_after": "Text(String(localized: \"dashboard.module.snapshot.title\", defaultValue: \"Goal Snapshot\"))",
        "key_convention": "<screen>.<section>.<element>.<type> (e.g., planning.budget.save.button)",
        "scope_note": "Consider a flatter namespace if deep nesting creates maintenance burden. Evaluate during Phase 0."
      },
      "pluralization_strategy": {
        "description": "Count-dependent strings must use .xcstrings plural rules for correct localization.",
        "example": "String(localized: \"goals.count\", defaultValue: \"\\(count) goals\") with .xcstrings plural variants for zero/one/other",
        "coverage": "All strings containing numeric interpolation: goal counts, transaction counts, allocation counts, participant counts"
      },
      "currency_formatting": {
        "description": "All financial amounts must use Decimal.FormatStyle.Currency with explicit CurrencyCode from user settings.",
        "pattern": "amount.formatted(.currency(code: userCurrencyCode))",
        "never": "Never use string interpolation of raw numbers for currency display (e.g., no \"$\\(amount)\")"
      },
      "date_formatting": {
        "description": "All date displays use Date.FormatStyle with relative formatting where appropriate.",
        "pattern": "date.formatted(.relative(presentation: .named)) or date.formatted(date: .abbreviated, time: .omitted)"
      },
      "automation_strategy": {
        "description": "SwiftSyntax-based extraction tool to reduce manual effort from weeks to days of review.",
        "tool_behavior": "Scans all .swift files under Views/ for string literals in Text(), .navigationTitle(), .alert(), Button(), Label(), and similar SwiftUI constructors. Generates .xcstrings catalog entries with auto-generated keys following the naming convention. Produces a migration diff per file.",
        "tool_development_budget": "1-2 days for tool development. The tool must handle all SwiftUI string constructors including string interpolation, multi-line strings, conditional strings, and ternary expressions. This is a non-trivial engineering task, not a side-deliverable. Tool development is budgeted within W4 Phase A (see Section 9).",
        "tool_development_contingency": "If SwiftSyntax tool development exceeds 2 days (e.g., due to lack of prior SwiftSyntax experience or complex AST edge cases with ternaries and interpolation), fall back to regex-based extraction covering ~80% of cases plus manual migration for remaining edge cases. The tool is a productivity accelerator, not a correctness requirement. The regex fallback is acceptable because the manual review step will catch any missed strings regardless.",
        "execution_time": "Once developed, the tool extracts 500+ strings and generates the initial catalog in <1 hour of execution time.",
        "review_process": "Auto-generated keys and extraction reviewed by developer for correctness before applying migration diffs.",
        "revision_4_change": "Added SwiftSyntax fallback contingency per LIFT-R3-19."
      }
    },

    "accessibility_architecture": {
      "title": "6.3 Accessibility Remediation Architecture (Workstream W1)",
      "existing_infrastructure": "AccessibilityManager (477 lines) with VoiceOver detection, haptic feedback (7 types), financial amount descriptions, chart accessibility labels, animation adaptation, and accessibility audit scoring. AccessibilityViewModifiers exist for common patterns.",
      "minimum_touch_target": {
        "description": "All interactive elements must maintain a minimum 44pt touch target at standard text sizes, per Apple HIG. This applies to P1 inline retry buttons, P4 compound status indicators, P7 toast dismiss areas, and all Button, NavigationLink, and Toggle instances.",
        "standard_sizes": "44pt minimum at default Dynamic Type sizes.",
        "accessibility_sizes": "60pt minimum at AX3 and above (per Dynamic Type breakpoints below).",
        "implementation": "Use .frame(minWidth: 44, minHeight: 44) or .contentShape(Rectangle()) with adequate padding on compact interactive elements. Most SwiftUI default components already meet this, but custom interactive elements and compact indicators must be verified.",
        "added_in_revision": 4,
        "raised_by": "LIFT-R3-16"
      },
      "changes": [
        "Add .accessibilityLabel() to all interactive elements that lack them — systematic scan of all 96 primary view files.",
        "Add .accessibilityElement(children: .combine) to card groupings in Dashboard and similar composite views.",
        "Add .accessibilityHint() to gesture-based interactions (swipe actions, long press) so VoiceOver users can discover them.",
        "Add .accessibilityValue() to numeric displays (amounts, percentages) with appropriate value types.",
        "Add @Environment(\\.dynamicTypeSize) checks per the Dynamic Type Breakpoints specification (below).",
        "Apply .minimumScaleFactor where text truncation risk exists.",
        "Ensure toast/notification timing respects VoiceOver — per P7 Transient Confirmation pattern: minimum 5-second display with VoiceOver .announcement posting. P7a undo snackbar extends to 15 seconds with VoiceOver active.",
        "Add VoiceOver-equivalent .accessibilityAction() for all gesture recognizers.",
        "Add 'Restart Tutorial' option in Settings for onboarding dismissal recovery (m16) with user-prompted resume.",
        "Verify keyboard navigation completes all 5 core journeys on macOS (Tab order, Return to activate).",
        "Verify 44pt minimum touch targets on all interactive elements at standard text sizes.",
        "Add XCTest accessibility regression assertions for high-traffic views (Dashboard, Planning, Goals) — approximately 10-15 targeted assertions (new W1 deliverable)."
      ],
      "dynamic_type_breakpoints": {
        "description": "Decision table for layout adaptation at accessibility text sizes.",
        "breakpoints": [
          {
            "threshold": ".accessibility3 and above",
            "changes": [
              "HStack card layouts convert to VStack using ViewThatFits",
              "Secondary illustrations hidden",
              "Touch targets increase to minimum 60pt",
              "Decorative spacing reduced to accommodate larger text"
            ]
          },
          {
            "threshold": ".accessibility5",
            "changes": [
              "Single-column layout forced for all multi-column views",
              "Decorative elements hidden entirely",
              "Minimum font size enforced at 28pt",
              "Navigation elements simplified to essential actions only"
            ]
          }
        ],
        "implementation_mechanism": "ViewThatFits as primary mechanism. @Environment(\\.dynamicTypeSize) for conditional logic when ViewThatFits alone is insufficient.",
        "transition_verification": "Preview inspection includes AX1 and AX2 sizes (not just standard, AX3, AX5) to verify smooth layout transitions between breakpoints. The transition FROM standard TO AX3 (where HStack -> VStack occurs) must be visually smooth, not just correct at the endpoints.",
        "revision_4_change": "AX1/AX2 inspection added per LIFT-R3-07 and UX reviewer feedback."
      },
      "accessibility_regression_testing": {
        "description": "Prevent silent regression of accessibility work through targeted automated tests.",
        "xctest_assertions": "Add approximately 10-15 XCTest accessibility assertions for the three highest-traffic views (Dashboard, Planning, Goals). These assertions verify that key interactive elements retain .accessibilityLabel, .accessibilityHint, and .accessibilityValue modifiers after future refactors.",
        "swiftlint_rule_consideration": "Consider adding a SwiftLint custom rule that detects interactive SwiftUI elements (Button, NavigationLink, Toggle) without .accessibilityLabel. This provides ongoing CI-level protection beyond one-time additions. Scoped as optional W1 Phase B deliverable if time permits.",
        "macos_keyboard_test": "Add at least one XCTest UI test per core journey that exercises keyboard-only navigation on macOS to prevent regression of keyboard accessibility.",
        "added_in_revision": 4,
        "raised_by": "LIFT-R3-14"
      }
    },

    "token_compliance_architecture": {
      "title": "6.4 Token Compliance Architecture (Workstream W3)",
      "existing_infrastructure": "VisualComponentTokens.swift (41 lines) with domain-specific corner radius tokens (planning:12, dashboard:16, settings:10), fill tokens (5 variants), status color tokens (4), and stroke tokens (2). visual-tokens.v1.json exists with cross-platform color role definitions.",
      "spacing_token_scale": {
        "description": "Expand from 0 spacing tokens to a complete 6-value scale.",
        "tokens": [
          { "name": "micro", "value": 4, "usage": "Tight spacing within compound indicators, between icon and label" },
          { "name": "compact", "value": 8, "usage": "Intra-component spacing, between related elements within a card" },
          { "name": "standard", "value": 12, "usage": "Standard content spacing, list item internal padding" },
          { "name": "comfortable", "value": 16, "usage": "Section padding, card content margins, comfortable whitespace" },
          { "name": "generous", "value": 24, "usage": "Section separation, generous whitespace between distinct content groups" },
          { "name": "spacious", "value": 32, "usage": "Major section separation, page-level margins" }
        ],
        "spacing_none_note": "Spacing.none (value: 0) is intentionally omitted. Where zero spacing is required, use explicit 0 — the SwiftLint rule should allow literal 0 as an exception since it represents 'no spacing' intent. If false positives become a problem, add Spacing.none as a convenience alias.",
        "migration_mapping": [
          { "current": "padding(4)", "token": "Spacing.micro", "rule": "Always micro." },
          { "current": "padding(8) or spacing: 8", "token": "Spacing.compact", "rule": "Always compact." },
          { "current": "padding(10)", "token": "Spacing.standard(12)", "rule": "Default to Spacing.standard(12) unless the element is a tight intra-component gap (e.g., HStack spacing within a compound indicator or between icon and adjacent label inside a single row). In that case, use Spacing.compact(8). Document every compact exception in the PR description.", "default": "standard", "exception": "compact — only for tight intra-component gaps" },
          { "current": "padding(12) or spacing: 12", "token": "Spacing.standard", "rule": "Always standard." },
          { "current": "padding(16) or spacing: 16", "token": "Spacing.comfortable", "rule": "Always comfortable." },
          { "current": "padding(20)", "token": "Spacing.generous(24)", "rule": "Default to Spacing.generous(24). Use Spacing.comfortable(16) only if visual inspection confirms the original 20pt was chosen to be tighter than section-level spacing (e.g., inner card padding where 24pt would be visually excessive). Document every comfortable exception in the PR description.", "default": "generous", "exception": "comfortable — only when 24pt is visually excessive in context" },
          { "current": "padding(24) or spacing: 24", "token": "Spacing.generous", "rule": "Always generous." }
        ],
        "migration_rule_summary": "Every ambiguous migration has a concrete default. Exceptions require explicit justification in the PR description. This eliminates cross-engineer inconsistency for the ~818 migration sites."
      },
      "corner_radius_reconciliation": {
        "description": "Reconcile existing domain-specific radii with a generic scale.",
        "tokens": [
          { "name": "small", "value": 4, "usage": "Reserved for future chip/badge components. Not used in current migration — no existing values map to 4pt corner radius.", "status": "reserved_no_current_migration" },
          { "name": "compact", "value": 8, "usage": "Button corners, compact interactive elements. Maps existing cornerRadius(8) values found in codebase (e.g., M8 button corners).", "status": "new_in_revision_4" },
          { "name": "medium", "value": 10, "usage": "Settings rows (existing settingsRowCornerRadius:10), compact cards" },
          { "name": "standard", "value": 12, "usage": "Planning cards (existing planningCardCornerRadius:12), most content cards" },
          { "name": "large", "value": 16, "usage": "Dashboard cards (existing dashboardCardCornerRadius:16), prominent cards" },
          { "name": "extraLarge", "value": 20, "usage": "Full-width cards, modal sheets" }
        ],
        "note": "Existing domain-specific tokens are retained as aliases to the generic scale for backward compatibility. Implementation pattern: existing tokens become computed properties returning the new generic enum values (e.g., static var planningCardCornerRadius: CGFloat { CornerRadius.standard }), preserving call-site compatibility while centralizing the source of truth.",
        "backward_compatibility_pattern": "static var planningCardCornerRadius: CGFloat { CornerRadius.standard } // was 12, now alias",
        "revision_4_change": "Added CornerRadius.compact(8) as new 6th token (was 5-value scale) per LIFT-R3-03. Resolves cornerRadius(8) mapping gap identified by architect and UI designer."
      },
      "corner_radius_migration_mapping": {
        "description": "Migration mapping table for corner radius values, parallel to the spacing migration table. Added in revision 4 per LIFT-R3-03.",
        "mapping": [
          { "current": "cornerRadius(4)", "token": "CornerRadius.small", "rule": "Always small. Rare in current codebase." },
          { "current": "cornerRadius(8)", "token": "CornerRadius.compact", "rule": "Always compact. Most common unlisted value — found in button corners (M8) and compact interactive elements." },
          { "current": "cornerRadius(10)", "token": "CornerRadius.medium", "rule": "Always medium. Equivalent to existing settingsRowCornerRadius." },
          { "current": "cornerRadius(12)", "token": "CornerRadius.standard", "rule": "Always standard. Equivalent to existing planningCardCornerRadius." },
          { "current": "cornerRadius(16)", "token": "CornerRadius.large", "rule": "Always large. Equivalent to existing dashboardCardCornerRadius." },
          { "current": "cornerRadius(20)", "token": "CornerRadius.extraLarge", "rule": "Always extraLarge. Full-width cards and modal sheets." }
        ],
        "note": "Phase 0 Migration Scope Sizing Report will include corner radius occurrence counts alongside spacing counts to ensure W3 estimation covers both migration types."
      },
      "json_contract_update": "New spacing and corner radius token roles will be added to visual-tokens.v1.json following the existing schema pattern with iOS tokenRef + sourceFile + spec, and Android equivalents for cross-platform parity.",
      "code_pattern": {
        "before": ".padding(16).cornerRadius(8)",
        "after": ".padding(VisualComponentTokens.Spacing.comfortable).cornerRadius(VisualComponentTokens.CornerRadius.compact)"
      },
      "priority_migration_targets": "EmptyStateView.swift and ErrorStateView.swift are migrated first in W3 Phase B as reference implementations. These reusable components are consumed by multiple screens — getting their tokens right first ensures consistency in all consuming views and creates a pattern for engineers to follow.",
      "preview_file_migration": "60 preview files are explicitly included in W3 scope. Preview files likely contain their own hardcoded padding and mock data that needs token migration. Budget is negligible (preview files are small) but they must not be forgotten in the file count. Phase 0 Migration Scope Sizing Report includes preview file token counts.",
      "file_growth_note": "Adding Spacing (6 values) and CornerRadius (6 values, up from 5) enums to the currently 41-line VisualComponentTokens.swift file is appropriate. With documentation and aliases, the file may grow to ~130 lines. If future token types are added (typography, iconography), consider splitting into a VisualComponentTokens/ directory with per-concern files. Add a comment in the infrastructure PR noting this consideration.",
      "revision_4_additions": "Corner radius migration mapping table (LIFT-R3-03), preview file scope inclusion (LIFT-R3-20), CornerRadius.compact(8) token (LIFT-R3-03)."
    },

    "error_handling_architecture": {
      "title": "6.5 Error Handling UX Standardization (Workstream W2)",
      "existing_infrastructure": {
        "app_error": "AppError enum with 25 cases in Utilities/ErrorHandling.swift. Covers network (6), API (5), data (6), calculation (4), and platform (4) error domains. Includes ErrorHandler singleton with @MainActor error state, retry logic, and error recording.",
        "error_alert": "ErrorAlertModifier ViewModifier for presenting error alerts from ErrorHandler state.",
        "async_handler": "AsyncErrorHandler struct with execute() and executeWithRetry() static methods.",
        "user_facing_error": "UserFacingError struct in ServiceResult.swift with title, message, recoverySuggestion, isRetryable, and category (network/apiKey/dataCorruption/unknown).",
        "error_translator": "ErrorTranslator in ServiceResult.swift maps AppError cases to UserFacingError with specific recovery suggestions for 9 explicit cases and a default fallback.",
        "view_state": "ViewState enum (.idle, .loading, .loaded, .error(UserFacingError), .degraded(String)) in ServiceResult.swift.",
        "service_result": "ServiceResult<T> enum (.fresh, .cached(age:), .fallback(reason:), .failure) with data-freshness metadata."
      },
      "composite_view_error_granularity": {
        "description": "Design decision for views aggregating multiple async data sources (e.g., DashboardViewModel aggregating exchange rates, goal data, and portfolio values from independent services).",
        "decision": "Use per-section error state: loaded sections render normally while failed sections display P1 InlineErrorBanner. This is the natural fit given the existing ServiceResult-per-service architecture — each service call returns its own ServiceResult, and the ViewModel can track per-section state.",
        "implementation": "DashboardViewModel (and any ViewModel aggregating multiple async sources) publishes per-section ViewState rather than a single top-level ViewState. Each section in the View switches on its section-specific ViewState. A whole-screen ViewState.error is reserved for cases where the fundamental data context (e.g., ModelContext) is unavailable.",
        "example": "DashboardViewModel publishes: @Published var exchangeRateState: ViewState, @Published var goalState: ViewState, @Published var portfolioState: ViewState. If exchange rates fail but goals load, the Dashboard shows goals normally with a P1 InlineErrorBanner in the exchange rate section.",
        "added_in_revision": 4,
        "raised_by": "LIFT-R3-05"
      },
      "retry_exhaustion_escalation": {
        "description": "Behavior after N consecutive failures of the same operation.",
        "rule": "After 3 consecutive failures of the same operation (e.g., 3 CloudKit sync retries, 3 exchange rate fetches), replace the primary 'Try Again' button with a 'Get Help' button linking to a support/status page. Retain a smaller 'Try Again' as a secondary action. VoiceOver announces: 'Multiple attempts failed. Tap Get Help for assistance.'",
        "rationale": "Without escalation, persistent failures create an infinite retry loop with no exit. Users experiencing sustained service outages or account issues need a path beyond retrying.",
        "implementation": "Track consecutive failure count per operation in the ViewModel. After threshold (3), update the UserFacingError presented to include an escalation action. Reset the failure count on any successful operation.",
        "added_in_revision": 4,
        "raised_by": "LIFT-R3-09"
      },
      "planned_extensions": [
        "Add 2-3 CKError-specific cases to AppError or extend ErrorTranslator with CKError-to-UserFacingError mappings for: CKError.notAuthenticated, .networkUnavailable, .quotaExceeded, .participantMayNeedVerification, .serverRecordChanged.",
        "Migrate 5 remaining ViewModels to ViewState pattern: MonthlyPlanningViewModel, MonthlyExecutionViewModel (from Error?), GoalEditViewModel, GoalDashboardViewModel, CurrencyViewModel (from ad-hoc). Budget 0.5-1 day explicitly for test migration alongside the 5 ViewModel migrations (~15 existing test files will need updating).",
        "Standardize ChartErrorView usage across all 20 chart files for consistent error/empty messaging. Note: ChartErrorView is structurally a P2 variant (full VStack with 48pt icon), not P1. Chart files should adopt ChartErrorView for full chart failure (P2) or the new InlineErrorBanner for partial failure (P1).",
        "Add contextual recovery guidance to dashboard error diagnostics (what failed, why, specific next steps).",
        "Adopt per-section error state for DashboardViewModel and other composite views (LIFT-R3-05).",
        "Implement retry-exhaustion escalation: after 3 consecutive failures, surface Get Help action (LIFT-R3-09).",
        "Add retry + recovery suggestion to Settings export failure.",
        "Add recovery instructions to Planning rates-unavailable state.",
        "Add goal name context to Goals lifecycle action dialog.",
        "Implement undo-capable deletion pattern for single-item swipe-to-delete (M6): soft-delete with 10-second undo snackbar per P7a spec. Confirmation dialog for bulk or cascading operations (see Section 12 Q7).",
        "Add 'Continue to Execution' transition action on plan completion for J2 plan-to-execution gap, with visual spec: secondary .bordered button appearing after save confirmation (LIFT-R3-10).",
        "Add pre-import confirmation step for Import Data (m6): summary sheet with conflict detection and Cancel/Replace All/Merge options (LIFT-R3-12).",
        "Add inline description below Import Data button for format guidance (m6).",
        "Specify MVVM data-flow pattern for staleness: ViewModel translates ServiceResult.cached(age:) into ViewState.degraded with Date storage so views compute relative timestamps reactively (LIFT-R3-06)."
      ],
      "test_migration_budget": "Migrating 5 ViewModels to ViewState will change published property types. Existing tests asserting on these properties (Error?, ad-hoc patterns) will need updating. Budget 0.5-1 day explicitly for test migration within the W2 estimate. ~15 existing test files are affected."
    },

    "offline_stale_data_ux": {
      "title": "6.6 Offline and Stale Data UX",
      "description": "Specification for communicating data freshness and offline state in a finance-critical app.",
      "staleness_threshold": "Configurable constant (not hardcoded). Default: 30 minutes for exchange rates, 1 hour for portfolio data, 2 hours for goal progress. Stored in AppConfiguration and adjustable without code changes.",
      "mvvm_data_flow": "ViewModel translates ServiceResult.cached(T, age:) into ViewState.degraded with a StalenessInfo struct containing the stale Date and data severity tier. Views compute relative timestamps reactively using the stored Date, eliminating the need for ViewModel-level timers to keep 'X minutes ago' strings fresh. This maintains MVVM separation and ensures consistent staleness communication across all screens.",
      "staleness_info_struct": {
        "description": "Replace ViewState.degraded(String) with ViewState.degraded(StalenessInfo) for reactive timestamp computation.",
        "struct_definition": "struct StalenessInfo { let staleDate: Date; let severityTier: StaleSeverity; let dataDescription: String }",
        "severity_tiers": "enum StaleSeverity { case warning, informational }",
        "view_computation": "Views use staleDate to compute relative time labels via Date.RelativeFormatStyle, which automatically stays fresh without ViewModel timers. StaleSeverity determines messaging tone.",
        "added_in_revision": 4,
        "raised_by": "LIFT-R3-06, LIFT-R3-13"
      },
      "severity_tiered_messaging": {
        "description": "Differentiate staleness messaging by data type to reflect financial severity context.",
        "tiers": [
          {
            "tier": "warning",
            "applies_to": "Exchange rates, portfolio values, asset prices",
            "messaging_tone": "Warning — 'Rates are [X] old — actual values may differ from current market'",
            "rationale": "A 2-hour-old exchange rate has material financial risk implications. Users making financial decisions need to know the data may be significantly different."
          },
          {
            "tier": "informational",
            "applies_to": "Goal progress, static configuration, allocation history",
            "messaging_tone": "Informational — 'From [X] ago'",
            "rationale": "Goal progress and configuration data change slowly. Staleness is worth noting but does not carry financial risk implications."
          }
        ],
        "added_in_revision": 4,
        "raised_by": "LIFT-R3-13"
      },
      "states": [
        {
          "state": "Network unavailable, cached data available",
          "ui_behavior": "Show cached data with an inline banner. Warning tier: 'Offline — rates from [relative time]. Actual values may differ.' Informational tier: 'Offline — showing data from [relative time].' Below the banner text, show a visible 'Refresh' button (always present, not just on pull-to-refresh) for discoverability and accessibility. Use ViewState.degraded(StalenessInfo) with ServiceResult.cached(T, age:) to surface staleness reactively.",
          "location": "Dashboard summary, exchange rate displays, portfolio values",
          "accessibility": "VoiceOver proactively announces offline state change via UIAccessibility.post(notification: .announcement, argument: 'App is offline. Showing cached data.'). Refresh button is keyboard-accessible on macOS."
        },
        {
          "state": "Stale exchange rates during active session",
          "ui_behavior": "Inline notice below rate-dependent calculations: 'Rates are [X] old — actual values may differ' in .caption2 with .secondary foreground (warning tier). Visible 'Refresh' button adjacent to the staleness notice. Pull-to-refresh also triggers manual rate update.",
          "location": "Monthly Planning budget calculations, goal progress percentages"
        },
        {
          "state": "Queued CloudKit operations",
          "ui_behavior": "Pending operations shown with count badge on Family Sharing tab/row. Individual items show 'Syncing...' status.",
          "location": "Family Sharing participant list, shared goal updates"
        },
        {
          "state": "Network restored",
          "ui_behavior": "Automatic refresh triggered. Transient confirmation per P7 pattern (minimum 3 seconds, VoiceOver .announcement, reduce-motion static variant). Data indicators updated to show fresh state.",
          "location": "All screens with previously stale data"
        }
      ]
    }
  },

  "section_7_ui_pattern_catalog": {
    "title": "UI Pattern Catalog",
    "description": "Canonical visual patterns for consistent cross-screen implementation. Each pattern specifies layout, when to use, concrete implementation details, and transition behavior.",
    "dark_mode_note": "All pattern colors use semantic tokens (AccessibleColors, VisualComponentTokens) which adapt to color scheme automatically. All opacity values and semantic colors in P1-P7a are validated in both light and dark mode appearances during Phase 0 preview inspection. Any opacity value that does not meet WCAG AA contrast in either appearance is flagged and adjusted.",
    "transitions": {
      "title": "State Transition Behavior",
      "description": "All ViewState transitions between loading/loaded/error/empty use consistent animation to prevent jarring state switches and ensure cross-engineer consistency.",
      "default_transition": ".animation(.easeInOut(duration: 0.25), value: viewState) with .transition(.opacity)",
      "reduce_motion": "When @Environment(\\.accessibilityReduceMotion) is true, use .animation(.none). State changes are instant with no visual transition.",
      "applies_to": "All patterns P1-P7a. Every view that switches between ViewState cases must apply this transition behavior.",
      "implementation_example": "Group { switch viewState { case .loading: P5LoadingView() case .error(let e): P2ErrorView(error: e) case .loaded: ContentView() default: P6EmptyView() } }.animation(.easeInOut(duration: 0.25), value: viewState).transition(.opacity)"
    },
    "bottom_overlay_stacking": {
      "title": "Bottom Overlay Stacking Priority and Queuing Rules",
      "description": "P7 toast, P7a undo snackbar, and offline banner all anchor to bottom-of-screen. This subsection defines priority ordering and queuing rules for scenarios where multiple overlays compete simultaneously.",
      "priority_order": [
        { "priority": 1, "element": "P7a Undo Snackbar", "rationale": "Time-sensitive user action — 10-second window to prevent data loss. Always takes visual priority." },
        { "priority": 2, "element": "Offline/Stale Banner", "rationale": "Persistent state communication — users need to know data may be outdated. Remains visible but yields to undo snackbar." },
        { "priority": 3, "element": "P7 Transient Toast", "rationale": "Brief confirmation — can be safely delayed. Queued until higher-priority overlays dismiss." }
      ],
      "queuing_rules": {
        "behavior": "When a higher-priority overlay is visible, lower-priority overlays are queued (not dismissed). Each queued overlay gets its full display duration when it becomes visible.",
        "queue_depth": "Maximum 3 toasts in queue. If more than 3 toasts are queued while higher-priority overlays are visible, coalesce remaining into a single summary toast (e.g., '3 updates completed').",
        "concurrent_toasts": "Toasts display sequentially in FIFO order, each getting its full minimum display time. No simultaneous toast display."
      },
      "added_in_revision": 4,
      "raised_by": "LIFT-R3-02"
    },
    "patterns": [
      {
        "id": "P1",
        "name": "Inline Error Banner (InlineErrorBanner — NEW COMPONENT)",
        "when_to_use": "Partial-screen data failures where other content on the screen is still valid. Examples: a single chart failing to load, exchange rate fetch failing while cached rates are available, a section within a composite view (e.g., Dashboard) encountering an error while other sections load successfully.",
        "layout": {
          "container": "HStack(alignment: .center, spacing: Spacing.compact)",
          "icon": "Image(systemName: \"exclamationmark.triangle.fill\") in .font(.body) with .foregroundStyle(VisualComponentTokens.statusWarning)",
          "message": "Text with error description in .font(.subheadline) .foregroundStyle(.secondary), max 2 lines",
          "action": "Button(\"Retry\") or Button(\"Learn More\") in .font(.subheadline.weight(.medium)) with AccessibleColors.primaryInteractive. After 3 consecutive failures of the same section, replace Retry with 'Get Help' per retry-exhaustion rule (Section 6.5)."
        },
        "background": "RoundedRectangle with VisualComponentTokens.statusWarning.opacity(0.1) and Spacing.standard padding",
        "wide_screen_constraint": ".frame(maxWidth: 600, alignment: .center) for iPad landscape and macOS wide windows. This prevents the banner from stretching to full container width on wide form factors, matching Apple's readableContentGuide behavior.",
        "implementation_note": "This is a NEW lightweight component (InlineErrorBanner). It is NOT a generalization of ChartErrorView. ChartErrorView is a full-screen VStack with 48pt icon — structurally a P2 variant, not P1. InlineErrorBanner is listed as a W2 deliverable. Add to docs/COMPONENT_REGISTRY.md as part of W2 deliverables.",
        "transition": "Appears with .transition(.opacity) per Transitions spec.",
        "deliverable": "New InlineErrorBanner component created in W2 Phase A. Registered in docs/COMPONENT_REGISTRY.md.",
        "revision_4_changes": "Added maxWidth: 600 constraint per LIFT-R3-15. Added Component Registry update per LIFT-R3-20. Added retry-exhaustion reference per LIFT-R3-09."
      },
      {
        "id": "P2",
        "name": "Full-Screen Error with Recovery",
        "when_to_use": "When the entire screen depends on the failed data source and no meaningful content can be shown. Examples: goal detail when goal data fails to load, dashboard when model context is unavailable.",
        "layout": {
          "container": "VStack(alignment: .center, spacing: Spacing.comfortable)",
          "icon": "Image(systemName: context-appropriate symbol) in .font(.system(size: 48)) with .foregroundStyle(.secondary)",
          "title": "Text with error title in .font(.title3.weight(.semibold))",
          "description": "Text with error description in .font(.body) .foregroundStyle(.secondary) .multilineTextAlignment(.center), max 3 lines",
          "primary_action": "Button(\"Try Again\") if isRetryable, styled as .borderedProminent with AccessibleColors.primaryInteractive. After 3 consecutive failures, replace with 'Get Help' per retry-exhaustion rule (Section 6.5); retain smaller 'Try Again' as secondary.",
          "secondary_action": "Optional Button(\"Go Back\") or Button(\"Contact Support\") in .bordered style"
        },
        "implementation_note": "Implementation: use ContentUnavailableView with the described content structure. The existing ErrorStateView already uses Apple's ContentUnavailableView (iOS 17+), which provides built-in accessibility, Dynamic Type handling, and layout adaptation for free. P2's specification describes the visual intent — ContentUnavailableView is the canonical implementation. Do not rebuild with a custom VStack.",
        "existing_implementation": "ErrorStateView is the canonical P2 realization. ChartErrorView is a domain-specific P2 variant for chart-level failures.",
        "transition": "Appears with .transition(.opacity) per Transitions spec."
      },
      {
        "id": "P3",
        "name": "Alert-Style Error",
        "when_to_use": "Non-recoverable errors requiring user acknowledgment, or action confirmation errors. Examples: export failure, data corruption detection, permission denied.",
        "implementation": "Existing ErrorAlertModifier from ErrorHandler. No new pattern needed.",
        "enhancement": "Add recoverySuggestion to alert message body when available from UserFacingError.",
        "transition": "System alert presentation — no custom transition needed."
      },
      {
        "id": "P4",
        "name": "Compound Accessibility Status Indicator",
        "when_to_use": "Any status, freshness, or feasibility indicator that communicates state. Replaces any color-only indicators.",
        "layout": {
          "container": "HStack(spacing: Spacing.micro)",
          "icon": "Image(systemName: \"circle.fill\") in .font(.system(size: 8)) with .foregroundStyle(statusColor)",
          "label": "Text(localizedStatusLabel) in .font(.caption2) .foregroundStyle(.secondary)"
        },
        "size_class_behavior": {
          "regular": "Icon + text label always visible",
          "compact_at_AX3_plus": "Switch icon from 8pt circle.fill to minimum 12pt semantically recognizable SF Symbol (checkmark.circle.fill for success, exclamationmark.circle.fill for warning, xmark.circle.fill for error) with .accessibilityLabel(localizedStatusLabel). An 8pt generic dot is visually meaningless at accessibility sizes."
        },
        "touch_target": "Minimum 44pt touch target at standard sizes (per Section 6.3). Interactive P4 indicators must have adequate padding or .contentShape(Rectangle()) expansion.",
        "status_labels": {
          "examples": ["Fresh", "Stale", "On Track", "Behind", "Over Budget", "Under Budget", "Active", "Paused", "Completed"],
          "note": "All labels must be localized via String(localized:) when W4 is approved."
        },
        "note": "Most existing indicators already follow this pattern (verified: FamilyShareFreshnessHeaderView, BudgetSummaryCard). This formalizes the pattern for any future indicators and for the few that may not yet comply."
      },
      {
        "id": "P5",
        "name": "Loading Indicator with Context",
        "when_to_use": "All async loading states.",
        "implementation": "For all loading durations, use ProgressView with a contextual label: ProgressView(\"Loading rates...\") or ProgressView(\"Refreshing...\"). Spinner style. If loading exceeds 2 seconds, add a .font(.caption) hint below the spinner describing what is loading (e.g., 'Fetching portfolio data from server...').",
        "extended_loading_implementation": {
          "description": "Implementation pattern for the 2-second loading hint threshold.",
          "pattern": "ViewModel publishes @Published var isExtendedLoading: Bool = false. When a loading operation begins, start a Task that sets isExtendedLoading = true after 2 seconds if loading is still in progress (i.e., ViewState is still .loading). When loading completes (success or failure), cancel the task and reset isExtendedLoading to false. The View conditionally shows the caption hint based on this flag.",
          "code_sketch": "private var extendedLoadingTask: Task<Void, Never>? = nil\nfunc startLoading() {\n    state = .loading\n    extendedLoadingTask = Task { @MainActor in\n        try? await Task.sleep(for: .seconds(2))\n        if !Task.isCancelled && state == .loading {\n            isExtendedLoading = true\n        }\n    }\n}",
          "added_in_revision": 4,
          "raised_by": "LIFT-R3-17"
        },
        "reduce_motion": "When reduce motion is enabled, use static 'Loading...' text instead of animated spinner.",
        "note": "No skeleton/shimmer branch. Loading skeleton patterns are deferred to a future enhancement (see Section 3 Non-Goals). ProgressView with contextual label is the solution for all loading durations.",
        "transition": "Appears with .transition(.opacity) per Transitions spec."
      },
      {
        "id": "P6",
        "name": "Empty State",
        "when_to_use": "When a screen or section has no data to display and the user can take action to add data.",
        "implementation": "Use existing EmptyStateView with EmptyStateIllustration enum. Each new empty state variant needs: (a) illustration selection from existing EmptyStateIllustration cases (or new Path-based illustration if none fits), (b) title string, (c) description string, (d) CTA button label and action.",
        "note": "New illustration designs for any missing variants should follow existing EmptyStateIllustration patterns (custom Path renderers in the enum). All strings must be localized when W4 is approved.",
        "transition": "Appears with .transition(.opacity) per Transitions spec."
      },
      {
        "id": "P7",
        "name": "Transient Confirmation (Toast)",
        "when_to_use": "Brief confirmation of successful background operations. Examples: network restoration confirmation, CloudKit sync completion, data export success. NOT for errors (use P1/P2/P3), empty states (use P6), or actions requiring undo (use P7a).",
        "layout": {
          "container": "HStack(spacing: Spacing.compact) in a floating overlay anchored to bottom-safe-area with Spacing.comfortable inset",
          "icon": "Image(systemName: \"checkmark.circle.fill\") in .font(.body) with .foregroundStyle(VisualComponentTokens.statusSuccess)",
          "message": "Text with confirmation message in .font(.subheadline) .foregroundStyle(.primary), single line",
          "background": "RoundedRectangle(cornerRadius: CornerRadius.standard) with .ultraThinMaterial"
        },
        "timing": {
          "minimum_display": "3 seconds (visual users)",
          "voiceover_behavior": "Post UIAccessibility.post(notification: .announcement, argument: message) immediately on appearance. Toast remains visible until VoiceOver finishes reading (minimum 5 seconds with VoiceOver active).",
          "auto_dismiss": "Auto-dismiss after timing expires. No manual dismiss required."
        },
        "concurrent_behavior": {
          "queue_type": "queue_sequential",
          "max_queue_depth": 3,
          "overflow_strategy": "If more than 3 toasts are queued, coalesce remaining into a single summary toast.",
          "stacking_priority": "See Bottom Overlay Stacking Priority subsection. P7 has lowest priority (3); yields to P7a undo snackbar and offline banner."
        },
        "reduce_motion": "When @Environment(\\.accessibilityReduceMotion) is true, toast appears and disappears without animation (no slide-in/slide-out). Static display for the required duration.",
        "transition": "Default: slide up from bottom with .transition(.move(edge: .bottom).combined(with: .opacity)). ReduceMotion: .transition(.opacity) only."
      },
      {
        "id": "P7a",
        "name": "Undo Snackbar (P7 Variant)",
        "when_to_use": "Single-item deletions (goals, individual allocations) where a timed undo window is appropriate. NOT for bulk or cascading operations (use confirmation dialog instead per Q7).",
        "layout": {
          "container": "HStack(spacing: Spacing.compact) in a floating overlay anchored to bottom-safe-area with Spacing.comfortable inset — same anchoring as P7",
          "icon": "Image(systemName: \"trash\") in .font(.body) with .foregroundStyle(.secondary)",
          "message": "Text with deletion message (e.g., 'Goal deleted') in .font(.subheadline) .foregroundStyle(.primary)",
          "undo_action": "Button(\"Undo\") in .font(.subheadline.weight(.semibold)) with .foregroundStyle(AccessibleColors.primaryInteractive) — trailing position",
          "background": "RoundedRectangle(cornerRadius: CornerRadius.standard) with .ultraThinMaterial — same material as P7"
        },
        "timing": {
          "display_duration": "10 seconds (visual users). After 10 seconds, the soft-deleted item is permanently deleted.",
          "voiceover_duration": "15 seconds when VoiceOver is active. VoiceOver navigation to a bottom-anchored snackbar may take several swipes depending on screen content.",
          "voiceover_announcement": "UIAccessibility.post(notification: .announcement, argument: 'Item deleted. Double-tap to undo.') immediately on appearance."
        },
        "state_management": {
          "owner": "Dedicated UndoOverlayCoordinator injected via @EnvironmentObject or @Environment. This coordinator manages the pending-delete queue and timer, decoupled from individual ViewModels. It also handles P7 toast display, providing a unified overlay management layer that naturally solves concurrent-toast queuing.",
          "pending_delete_queue": "Concurrent quick-deletions (multiple items deleted in rapid succession) are handled with a FIFO queue. Each deletion gets its own undo timer. The most recent deletion's snackbar is displayed; earlier deletions continue their timers silently. If an earlier timer expires while a newer snackbar is shown, the earlier item is permanently deleted without visual interruption.",
          "optimistic_ui": "Item is visually removed from the list immediately on deletion. If undo is tapped, the item is re-inserted at its original position with .animation(.easeInOut(duration: 0.25))."
        },
        "edge_cases": {
          "navigation_away": "Undo opportunity persists for the full 10-second (or 15-second VoiceOver) window regardless of navigation. The UndoOverlayCoordinator is injected at the ContentView level, so the snackbar remains visible even if the user navigates to a different tab or screen. If the user navigates back, they see the remaining undo time.",
          "app_backgrounding": "Timer pauses when the app enters background (ScenePhase.background). Resumes when the app returns to foreground. This prevents permanent deletion while the user is not looking at the screen.",
          "last_item_deleted": "When deleting the last item in a list (triggering EmptyStateView), show a modified empty state during the undo window: replace the default 'Create your first goal' CTA with a message acknowledging the deletion and prominently displaying the Undo action. After undo expires, show the normal EmptyStateView with the creation CTA."
        },
        "stacking_priority": "Highest priority (1) among bottom overlays. Takes visual precedence over offline banner and P7 toasts. See Bottom Overlay Stacking Priority subsection.",
        "reduce_motion": "Same as P7: appears/disappears without animation when reduce motion is enabled.",
        "transition": "Same as P7: .transition(.move(edge: .bottom).combined(with: .opacity)). ReduceMotion: .transition(.opacity) only.",
        "added_in_revision": 4,
        "raised_by": "LIFT-R3-01"
      }
    ]
  },

  "section_8_resource_plan": {
    "title": "Resource Plan",
    "scenarios": [
      {
        "scenario": "1 engineer, sequential execution",
        "timeline": "17-27 working days (with W4); 10-20 without W4",
        "breakdown": {
          "phase_0_audit_validation": "2-3 days (expanded: includes Migration Scope Sizing Report with corner radius counts, test coverage assessment, macOS interaction audit). Requires minimum 2 engineers working jointly.",
          "w1_accessibility": "4-6 days (includes ~10-15 XCTest accessibility assertions as deliverable)",
          "w2_error_handling": "4-6 days (adjusted: +0.5-1 day for test migration budget, +plan-to-execution transition, +import confirmation flow, +per-section error state for composite views)",
          "w3_token_compliance": "4-8 days (range widened: low end 4 days at ~309 instances, high end 8 days at ~818 instances with visual verification per migration. Phase 0 confirms.)",
          "w4_localization_if_approved": "9-13 days (adjusted: 3-4 days infrastructure including 1-2 days SwiftSyntax tool development + 6-9 migration)",
          "per_workstream_validation": "Included in workstream estimates"
        },
        "note": "W4 timeline only applies if separately approved. W3 estimate widened per LIFT-R3-18: if Phase 0 confirms ~818 instances, high end is 7-8 days for a single engineer. The 10-20 day without-W4 range replaces previous 10-18 to reflect this scenario honestly."
      },
      {
        "scenario": "2 engineers, parallel execution",
        "timeline": "11-17 working days (with W4); 7-11 without W4",
        "parallelization": "Engineer A: W1 (Accessibility) then W2 (Error Handling). Engineer B: W3 (Token Compliance) then W4 (Localization, if approved). Phase 0 done jointly in days 1-3.",
        "note": "UI Pattern Catalog (Section 7) must be agreed upon before parallel work begins to ensure cross-screen coherence."
      },
      {
        "scenario": "3 engineers, maximum parallel",
        "timeline": "9-14 working days (with W4); 5-9 without W4",
        "parallelization": "Engineer A: W1 (Accessibility). Engineer B: W2 (Error Handling). Engineer C: W3 (Token Compliance). W4 (Localization) follows after infrastructure workstreams complete. Phase 0 done jointly in days 1-3.",
        "note": "Highest coordination overhead. All 3 engineers must align on UI Pattern Catalog before starting. PR review bandwidth may be bottleneck."
      }
    ],
    "without_w4": {
      "description": "If W4 (Localization) is deferred, timelines reduce significantly.",
      "one_engineer": "10-20 working days",
      "two_engineers": "7-11 working days",
      "three_engineers": "5-9 working days",
      "widest_variance_note": "W3 has the widest estimation variance because the magic number count discrepancy (309 vs ~818) directly affects migration effort. The high end (7-8 days for W3) is hit if the actual instance count is closer to ~818 and each migration requires individual visual verification. Phase 0 Migration Scope Sizing Report will narrow this range. Post-Phase 0 checkpoint must explicitly re-estimate W3 with the authoritative count.",
      "revision_4_change": "Timeline ranges widened to honestly reflect W3 high-end scenario per LIFT-R3-18. Previous ranges (10-18, 7-10, 5-8) assumed W3 midpoint. New ranges include the 7-8 day W3 scenario."
    },
    "minimum_viable_delivery": {
      "description": "If only 1-2 workstreams can be funded in the current cycle:",
      "priority_1": "W1 (Accessibility) — clearest user impact, compliance motivation, highest value independently. Estimated 4-6 days. Includes new accessibility regression test assertions.",
      "priority_2": "W2 (Error Handling) — directly addresses user confusion on failure paths, second-highest user impact. Estimated 4-6 days.",
      "priority_3": "W3 (Token Compliance) — code quality and drift prevention, less immediate user impact but prevents debt growth. Estimated 4-8 days (Phase 0 dependent).",
      "separate_decision": "W4 (Localization) — separate scope decision, not part of original request."
    }
  },

  "section_9_rollout_plan": {
    "title": "Rollout Plan",

    "phase_0": {
      "name": "Phase 0: Audit Validation (Shared)",
      "duration": "2-3 days",
      "staffing_requirement": "Minimum 2 engineers working jointly. Phase 0 produces 5 formal deliverables plus verification work across 156 files — this is too much for a solo engineer in 2-3 days. A solo engineer attempting all deliverables risks underdelivering or exceeding the time budget.",
      "objective": "Validate the findings inventory against the actual codebase before any remediation. Ensure no effort is wasted on phantom issues. Produce Migration Scope Sizing Report to validate workstream estimates.",
      "activities": [
        "Verify each remaining finding (34 items) against source files with line-number evidence.",
        "Run Xcode Previews for all 60 preview files at standard, AX1, AX2, AX3, and AX5 Dynamic Type sizes, in both light and dark mode.",
        "Run Accessibility Inspector against all interactive screens. Verify 44pt minimum touch targets.",
        "Execute user journey walkthroughs for all 5 core journeys (Section 5).",
        "Agree on UI Pattern Catalog (Section 7) with all participating engineers — including P7a undo snackbar spec and overlay stacking rules.",
        "Produce Migration Scope Sizing Report (includes both spacing AND corner radius occurrence counts).",
        "Assess existing test coverage against files to be modified.",
        "Audit macOS interaction parity (keyboard navigation, hover feedback, pointer cursors).",
        "Verify SwiftLint availability and configuration; if not configured, budget 0.5 day setup in W3.",
        "Categorize all 96 primary views for Dynamic Type: 'needs-adaptation' vs 'naturally-responsive' with evidence.",
        "If W4 approved: begin SwiftSyntax extraction tool development (1-2 days)."
      ],
      "deliverables": [
        {
          "name": "Validated Findings Report",
          "description": "All 34 findings verified with evidence. Any new findings discovered are triaged per scope-change policy."
        },
        {
          "name": "Migration Scope Sizing Report",
          "description": "Exact magic number counts per file using per-file occurrence methodology (resolving 309 vs ~818 discrepancy). Corner radius occurrence counts per file (resolving cornerRadius(8) mapping question). View categorization for Dynamic Type adaptation ('needs adaptation' vs 'naturally responsive' with evidence for each). SwiftLint configuration verification. Per-workstream effort confidence ratings (high/medium/low with justification). W3 re-estimation based on authoritative counts."
        },
        {
          "name": "Test Coverage Assessment",
          "description": "Identifies the 10 most-modified files across all workstreams and verifies at least one test touches their behavior. Flags zero-coverage files as elevated regression risk. Produces explicit test migration budget for W2 ViewState changes."
        },
        {
          "name": "macOS Interaction Parity Checklist",
          "description": "Keyboard navigability audit (Tab order, Return to activate) for all 5 core journeys on macOS. Hover feedback inventory on interactive elements. Right-click context menu audit where applicable."
        },
        {
          "name": "Agreed UI Pattern Catalog",
          "description": "Section 7 patterns confirmed by all participating engineers as the implementation standard. Includes P7a undo snackbar, overlay stacking rules, and all revision 4 additions."
        }
      ],
      "scope_change_policy": "If Phase 0 discovers new findings beyond the 34 currently inventoried: (1) Minor findings are deferred to a follow-up backlog and do not expand current workstream scope. (2) Major or Critical findings trigger a re-scoping checkpoint with the product owner before workstream execution begins. The checkpoint reviews impact on affected workstream estimates and produces an updated timeline if scope expands. This prevents unbounded scope growth while ensuring significant new issues are not ignored.",
      "scope_expansion_ceiling": "If new findings (minor + major + critical combined) would increase total scope by more than 25% measured in estimated engineer-days, the remediation must be re-proposed rather than expanded in-place. This prevents the 'boiling frog' problem of incremental scope additions that individually seem small but collectively transform the project.",
      "approval_checkpoint": "Findings review, Migration Scope Sizing Report review (including corner radius counts and W3 re-estimation), and workstream prioritization before proceeding. If scope expands due to major/critical new findings, updated estimates must be approved.",
      "revision_4_changes": "Added 2-engineer minimum staffing requirement per LIFT-R3-04. Added scope expansion ceiling (25% threshold) per LIFT-R3-04. Added corner radius counts to Migration Scope Sizing Report per LIFT-R3-03. Added AX1/AX2 to preview inspection per LIFT-R3-07. Added view categorization requirement per LIFT-R3-07."
    },

    "stakeholder_communication": {
      "title": "Stakeholder Communication Cadence",
      "description": "For a 3-5 week effort touching 96+ files, weekly stakeholder status reporting is required.",
      "cadence": "Weekly, delivered by end of each Friday.",
      "format": "One-paragraph status report covering: (1) Workstream progress — which workstreams are in progress, what percentage complete, (2) Risks materialized — any new risks or blockers encountered, (3) Scope changes — any Phase 0 findings or mid-workstream discoveries that affect scope, (4) Next week's plan — what will be worked on, expected deliverables.",
      "recipients": "Product owner and any designated stakeholders.",
      "supplements_not_replaces": "This weekly reporting supplements (does not replace) the three formal cross-workstream checkpoints (Post-Phase 0, After first workstream, After all workstreams).",
      "added_in_revision": 4,
      "raised_by": "LIFT-R3-08"
    },

    "workstream_w1": {
      "name": "W1: Accessibility Remediation",
      "duration": "4-6 days",
      "objective": "Achieve WCAG AA accessibility compliance across all interactive screens.",
      "priority": "Highest — clearest user impact and compliance motivation.",
      "findings_addressed": ["M2", "m1", "m2", "m3", "m7", "m13", "m15", "m16", "m17", "m18"],
      "phase_a_priority_flows": {
        "duration": "2-3 days",
        "scope": "Dashboard, Planning, Goals — highest-traffic screens",
        "activities": [
          "Add .accessibilityLabel() to all interactive elements without them.",
          "Add .accessibilityElement(children: .combine) to card groupings.",
          "Add .accessibilityHint() to gesture-based interactions.",
          "Add .accessibilityValue() to numeric displays.",
          "Implement Dynamic Type breakpoints per specification.",
          "Add VoiceOver-equivalent .accessibilityAction() for gesture recognizers.",
          "Ensure toast/notification timing respects VoiceOver (per P7 pattern; P7a undo snackbar extends to 15 seconds for VoiceOver).",
          "Verify 44pt minimum touch targets on all interactive elements."
        ],
        "deliverable": "PR per screen area with accessibility before/after evidence.",
        "approval_checkpoint": "Post priority-flow review before proceeding to secondary flows."
      },
      "phase_b_secondary_flows": {
        "duration": "2-3 days",
        "scope": "Charts, Components, Settings, FamilySharing, Onboarding, Shared",
        "activities": [
          "Same accessibility remediation pattern applied to remaining screens.",
          "Add 'Restart Tutorial' option in Settings for onboarding dismissal recovery (m16) with user-prompted resume.",
          "Verify keyboard navigation completes all 5 core journeys on macOS.",
          "Add XCTest accessibility regression assertions for Dashboard, Planning, Goals (~10-15 targeted assertions).",
          "Consider SwiftLint custom rule for interactive elements without .accessibilityLabel (optional if time permits).",
          "Add at least one XCTest UI test per core journey for keyboard-only navigation on macOS."
        ],
        "deliverable": "PR per screen area. Separate PR for accessibility test assertions."
      },
      "validation": "AccessibilityManager.accessibilityAuditScore() run as automated regression. Accessibility Inspector manual verification. Preview snapshots at AX1, AX2, AX3, AX5.",
      "acceptance_criteria": [
        "All interactive elements have accessibility labels.",
        "44pt minimum touch target verified for all interactive elements at standard text sizes.",
        "No color-only status indicators (verified: most already compliant).",
        "Dynamic Type tested at AX1, AX2, AX3 and AX5 — no layout breakage, smooth transitions between breakpoints.",
        "100% of views categorized: all needs-adaptation views adapted; naturally-responsive views documented with evidence. Zero views remain uncategorized.",
        "VoiceOver users can complete all 5 core journeys.",
        "Keyboard navigation can complete all 5 core journeys on macOS without mouse/trackpad.",
        "Onboarding dismissal recovery mechanism implemented (Settings > Restart Tutorial + user-prompted resume).",
        "10-15 XCTest accessibility regression assertions added for high-traffic views.",
        "All existing tests pass."
      ],
      "revision_4_changes": "Dynamic Type acceptance criteria made numeric and exhaustive per LIFT-R3-07. AX1/AX2 inspection added. 44pt touch target added per LIFT-R3-16. Accessibility regression tests added per LIFT-R3-14. Onboarding changed to user-prompted resume per LIFT-R3-11. macOS keyboard XCTest added per LIFT-R3-14."
    },

    "workstream_w2": {
      "name": "W2: Error Handling UX Standardization",
      "duration": "4-6 days (adjusted from 3-5: +0.5-1 day test migration, +plan-to-execution transition, +import confirmation flow)",
      "objective": "Standardize error handling UX across all feature domains using canonical patterns.",
      "priority": "High — directly addresses user confusion on failure paths.",
      "findings_addressed": ["M3", "M5", "M6", "M10", "M11", "M13", "M14", "M15", "m5", "m6", "m8", "m12", "m14"],
      "phase_a_priority_flows": {
        "duration": "2-3 days",
        "scope": "ViewState migration + canonical error pattern adoption in priority flows",
        "activities": [
          "Migrate MonthlyPlanningViewModel and MonthlyExecutionViewModel from Error? to ViewState pattern.",
          "Migrate GoalEditViewModel, GoalDashboardViewModel, CurrencyViewModel to ViewState.",
          "Adopt per-section ViewState for DashboardViewModel (exchange rate, goal, portfolio sections) per composite view error granularity design.",
          "Update ~15 existing test files to match ViewState migration (0.5-1 day budget).",
          "Create new InlineErrorBanner component (P1 pattern) with maxWidth: 600 constraint. Register in docs/COMPONENT_REGISTRY.md.",
          "Standardize ChartErrorView usage across all 20 chart files (ChartErrorView = P2 variant; InlineErrorBanner = P1 for partial failures).",
          "Add CloudKit-specific error translations to ErrorTranslator for top 5 CKError codes.",
          "Add contextual recovery guidance to dashboard error diagnostics.",
          "Implement retry-exhaustion escalation: after 3 failures, surface Get Help action.",
          "Add retry + recovery suggestion to Settings export failure.",
          "Add recovery instructions to Planning rates-unavailable state.",
          "Update ViewState.degraded to use StalenessInfo struct for reactive timestamp display."
        ],
        "vm_migration_contracts": [
          { "vm": "MonthlyPlanningViewModel", "from": "@Published var error: Error?", "to": "@Published var state: ViewState", "view_change": "View reads state instead of error", "test_change": "Assert on .error(UserFacingError) instead of Error?" },
          { "vm": "MonthlyExecutionViewModel", "from": "@Published var error: Error?", "to": "@Published var state: ViewState", "view_change": "View reads state instead of error", "test_change": "Assert on .error(UserFacingError) instead of Error?" },
          { "vm": "GoalEditViewModel", "from": "Ad-hoc error handling", "to": "@Published var state: ViewState", "view_change": "Switch on state for loading/error/loaded", "test_change": "New assertions on ViewState cases" },
          { "vm": "GoalDashboardViewModel", "from": "Ad-hoc error handling", "to": "@Published var state: ViewState", "view_change": "Switch on state for loading/error/loaded", "test_change": "New assertions on ViewState cases" },
          { "vm": "CurrencyViewModel", "from": "Ad-hoc error handling", "to": "@Published var state: ViewState", "view_change": "Switch on state for loading/error/loaded", "test_change": "New assertions on ViewState cases" },
          { "vm": "DashboardViewModel", "from": "Single ViewState", "to": "Per-section ViewState (exchangeRateState, goalState, portfolioState)", "view_change": "Dashboard renders per-section, failed sections show P1 InlineErrorBanner", "test_change": "Update assertions to test per-section states", "note": "New in revision 4 per LIFT-R3-05" }
        ],
        "deliverable": "PR for ViewModel migration (including test updates) + PR per screen area for error UX + PR for InlineErrorBanner component + Component Registry update.",
        "approval_checkpoint": "Post priority-flow review."
      },
      "phase_b_secondary_flows": {
        "duration": "2-3 days",
        "scope": "Goal name context in lifecycle dialog, undo-capable deletion (M6), import confirmation flow, plan-to-execution transition, remaining error state gaps",
        "activities": [
          "Add goal name to lifecycle action dialog title (M5).",
          "Implement P7a undo snackbar with UndoOverlayCoordinator for single-item swipe-to-delete; confirmation dialog for bulk/cascading (M6, per Q7 decision). This is the first Phase B item due to its complexity and risk — prioritized for maximum review attention.",
          "Add pre-import confirmation step for Import Data: summary sheet with count, conflict detection, Cancel/Replace All/Merge options (m6, LIFT-R3-12).",
          "Add inline description below Import Data button (m6).",
          "Add 'Continue to Execution' secondary .bordered action button on plan completion for J2 transition (LIFT-R3-10). Appears after save confirmation, dismissible, auto-dismisses after 5 seconds.",
          "Address remaining minor error state gaps."
        ],
        "deliverable": "PR per change. Undo snackbar (P7a) prioritized as first Phase B PR for early review."
      },
      "validation": "All error states exercised in previews. Error recovery paths tested. Retry-exhaustion escalation tested. Per-section error states tested for composite views. All existing tests pass (including updated tests for ViewState migration).",
      "acceptance_criteria": [
        "All 9 ViewModels use ViewState pattern (DashboardViewModel uses per-section ViewState).",
        "Every screen with async data has loading, error (with recovery), and empty states per canonical patterns.",
        "Composite views (Dashboard) render per-section error states with P1 InlineErrorBanner.",
        "Charts use consistent error/empty messaging via ChartErrorView (P2) or InlineErrorBanner (P1).",
        "CloudKit errors show specific diagnosis for top 5 CKError codes.",
        "Retry-exhaustion: after 3 consecutive failures, Get Help action surfaces.",
        "InlineErrorBanner (P1) component created, adopted, and registered in Component Registry.",
        "Plan-to-execution transition implemented for J2 with visual spec (.bordered, dismissible, auto-dismiss after 5s).",
        "Import Data includes pre-import confirmation with merge-vs-replace semantics.",
        "Staleness communication uses StalenessInfo struct with severity-tiered messaging.",
        "All existing tests pass (including ~15 updated test files)."
      ],
      "revision_4_changes": "Per-section error state for composite views (LIFT-R3-05). Retry-exhaustion escalation (LIFT-R3-09). J2 CTA visual spec (LIFT-R3-10). Import confirmation flow (LIFT-R3-12). StalenessInfo struct (LIFT-R3-06, LIFT-R3-13). P7a undo snackbar prioritized first in Phase B (LIFT-R3-01). InlineErrorBanner Component Registry update (LIFT-R3-20)."
    },

    "workstream_w3": {
      "name": "W3: Design Token Compliance",
      "duration": "4-8 days (range widened to reflect ~818 scenario; Phase 0 confirms)",
      "objective": "Replace hardcoded spacing/sizing with visual token references to 95% compliance or higher.",
      "priority": "Medium — code quality and drift prevention, less immediate user impact.",
      "findings_addressed": ["M1", "M8", "M16", "m4", "m9", "m10", "m11"],
      "phase_a_infrastructure": {
        "duration": "1 day",
        "activities": [
          "Add Spacing enum (6 values) to VisualComponentTokens.swift.",
          "Add generic CornerRadius enum (6 values including new compact(8)) to VisualComponentTokens.swift with aliases for existing domain-specific tokens (backward compatibility via computed properties).",
          "Add spacing and corner radius token roles to visual-tokens.v1.json.",
          "Add CI lint rule for magic number detection using SwiftLint custom rules. Configure to allow literal 0.",
          "Verify SwiftLint availability (from Phase 0 assessment); if not configured, add SwiftLint setup (0.5 day)."
        ],
        "deliverable": "Infrastructure PR with token extensions and lint rules. Add a comment noting VisualComponentTokens/ directory split consideration if future token types are added."
      },
      "phase_b_priority_migration": {
        "duration": "2-4 days (upper bound extended for ~818 scenario)",
        "scope": "Reusable components FIRST (EmptyStateView, ErrorStateView), then Components (45 files), Dashboard (8 files), Planning (20 files). Includes preview files for each area.",
        "priority_order": [
          "1. EmptyStateView.swift — reusable empty state component consumed by multiple screens. Reference implementation for token migration pattern.",
          "2. ErrorStateView.swift — reusable error component consumed by multiple screens. Includes iconColor migration (.orange/.red -> statusWarning/statusError per M16).",
          "3. Remaining Components directory (45 files) + their preview files",
          "4. Dashboard (8 files) + their preview files",
          "5. Planning (20 files) + their preview files"
        ],
        "activities": [
          "Replace spacing magic numbers per spacing migration mapping table (with concrete default rules for padding(10) and padding(20)).",
          "Replace corner radius magic numbers per corner radius migration mapping table (new in revision 4).",
          "Replace .blue literals with AccessibleColors.primaryInteractive.",
          "Replace .regularMaterial with token-wrapped surface references.",
          "Replace gradient color literals in Onboarding with token references.",
          "Replace #if os(iOS) guards with PlatformCapabilities where applicable.",
          "Migrate ErrorStateView.iconColor from raw .orange/.red to VisualComponentTokens.statusWarning/statusError (M16).",
          "Migrate preview files alongside their primary view files."
        ],
        "deliverable": "PR per screen area with preview verification. EmptyStateView and ErrorStateView in first PR as reference implementation.",
        "approval_checkpoint": "Post priority-migration review."
      },
      "phase_c_secondary_migration": {
        "duration": "1-3 days (upper bound extended for ~818 scenario)",
        "scope": "Goals, Charts, Settings, FamilySharing, Shared, root-level views + their preview files",
        "deliverable": "PR per screen area."
      },
      "validation": "CI SwiftLint rule reports magic number count. Preview snapshots verify no visual regression. All existing tests pass.",
      "acceptance_criteria": [
        "95% or more hardcoded spacing/sizing magic numbers replaced with token references (15 or fewer documented exceptions with explicit rationale per exception). CI lint reports remaining count.",
        "All spacing uses VisualComponentTokens.Spacing enum.",
        "All corner radii use VisualComponentTokens.CornerRadius enum (including new compact(8) for existing cornerRadius(8) values).",
        "ErrorStateView.iconColor uses VisualComponentTokens.statusWarning/statusError (not raw .orange/.red).",
        "CornerRadius.small(4) is reserved only — not adopted speculatively during migration.",
        "Preview files migrated alongside their primary view files.",
        "visual-tokens.v1.json updated with spacing/radius roles.",
        "All existing tests pass."
      ],
      "revision_4_changes": "Duration range widened to 4-8 days per LIFT-R3-18. Corner radius migration mapping table added per LIFT-R3-03. CornerRadius.compact(8) added per LIFT-R3-03. Preview files explicitly included per LIFT-R3-20. Phase B/C upper bounds extended."
    },

    "workstream_w4": {
      "name": "W4: Localization Infrastructure (SEPARATE APPROVAL REQUIRED)",
      "duration": "9-13 days (3-4 infrastructure including 1-2 days tool development + 6-9 migration)",
      "objective": "Establish localization infrastructure and migrate all user-facing strings.",
      "priority": "Separate scope decision — not part of original UX remediation request. Critical for international release, not for current English-only users.",
      "findings_addressed": ["C1", "C2", "M7", "M9"],
      "cost_benefit_analysis": {
        "cost": "9-13 engineer-days (adjusted from 7-11: SwiftSyntax tool development budgeted at 1-2 days within Phase A). Touches all 96 primary view files. Migration risk: string key typos, missed strings, interpolation errors.",
        "benefit": "Enables international release without additional code changes. Standardizes string handling. Enables future localization to any language. Prevents string-related code debt from growing further.",
        "alternative_if_deferred": "C1/C2 reclassified as Major (code quality gap). Localization infrastructure established as a separate project when international release is planned."
      },
      "phase_a_infrastructure": {
        "duration": "3-4 days (adjusted from 2-3: includes 1-2 days SwiftSyntax tool development)",
        "activities": [
          "Day 1-2: Develop SwiftSyntax-based extraction tool. Build and test against 3 representative files. Tool must handle all SwiftUI string constructors (Text, navigationTitle, alert, Button, Label, Section headers) including string interpolation, multi-line strings, conditional strings, and ternary expressions. If tool development exceeds 2 days, fall back to regex-based extraction (~80% coverage) plus manual migration for edge cases.",
          "Day 2-3: Run tool against full codebase, review output, generate initial .xcstrings catalog.",
          "Day 3-4: Review and correct auto-generated keys. Establish pluralization rules for count-dependent strings. Add CI lint rule for bare string literal detection. Migrate one representative screen (Monthly Planning) as proof of pattern."
        ],
        "deliverable": "Infrastructure PR with SwiftSyntax tool (or regex fallback), .xcstrings catalog, lint rule, and one screen migrated.",
        "approval_checkpoint": "Pattern review before committing to full migration."
      },
      "phase_b_full_migration": {
        "duration": "6-9 days (adjusted from 5-8: accounts for tool edge cases)",
        "activities": [
          "Apply migration diffs from extraction tool to all remaining view files, screen by screen.",
          "Migrate ErrorTranslator and UserFacingError strings.",
          "Migrate EmptyStateView factory strings.",
          "Migrate Settings section titles and descriptions.",
          "Add locale-aware currency formatting (Decimal.FormatStyle.Currency).",
          "Add locale-aware date formatting (Date.FormatStyle).",
          "Review all migrated strings for correctness."
        ],
        "deliverable": "PR per screen area (approximately 8 PRs)."
      },
      "validation": "CI lint detects zero bare string literals in view files. All localization keys resolve correctly. All existing tests pass. Preview with .locale override to verify string rendering.",
      "acceptance_criteria": [
        "Zero hardcoded user-facing strings in view files.",
        ".xcstrings catalog contains all strings with correct keys.",
        "Pluralization rules defined for all count-dependent strings.",
        "Currency amounts use Decimal.FormatStyle.Currency.",
        "Dates use Date.FormatStyle.",
        "All existing tests pass."
      ]
    },

    "workstream_merge_strategy": {
      "title": "Workstream Merge Ordering and Conflict Resolution",
      "recommended_merge_order": [
        "1. W3 (Token Compliance) — mechanical replacement of magic numbers with token references. Lowest structural change risk. Establishes the token vocabulary that other workstreams' code will use.",
        "2. W2 (Error Handling) — structural changes to ViewModel state management and error presentation components. Higher change complexity but scoped to error paths.",
        "3. W1 (Accessibility) — additive modifier changes (.accessibilityLabel, .accessibilityHint, Dynamic Type breakpoints). Least conflict-prone as additions rather than modifications.",
        "4. W4 (Localization) — string-level changes, mechanically applied. Merges last to avoid rebasing string changes across structural changes."
      ],
      "merge_order_enforcement": "This ordering is REQUIRED, not merely recommended. Deviating from this order without cause will create avoidable merge conflicts that waste engineering time. Any deviation must be explicitly approved at the relevant cross-workstream checkpoint with justification.",
      "conflict_resolution": {
        "rebase_cadence": "Daily rebase against main for all active workstream branches.",
        "merge_priority": "If conflicts arise between workstreams, the workstream earlier in the merge order above gets merge priority.",
        "concurrent_development": "If concurrent feature development on the same view files is unavoidable during the remediation window, designate an integration engineer responsible for resolving cross-branch conflicts. The integration engineer rebases workstream branches daily and resolves conflicts proactively rather than at PR merge time."
      },
      "revision_4_change": "Merge ordering changed from 'recommended' to 'required' per product owner feedback."
    },

    "cross_workstream_checkpoints": [
      {
        "checkpoint": "Post-Phase 0",
        "gate": "Validated findings report approved. Migration Scope Sizing Report reviewed (including corner radius counts and W3 re-estimation). Test Coverage Assessment reviewed. UI Pattern Catalog agreed (including P7a, overlay stacking). Workstream priority order confirmed. Scope-change policy applied to any new findings. Scope expansion ceiling (25%) evaluated.",
        "participants": "All engineers + product owner"
      },
      {
        "checkpoint": "After first workstream completes (recommended: post-W1)",
        "gate": "Lessons-learned review. Adjust remaining workstream scopes based on actual velocity and any issues discovered. Optional: lightweight user validation (3-5 participants, 30-minute sessions on core journeys J1-J3) to verify accessibility remediation where automated metrics cannot. This is recommended but not required — costs 0.5 days of preparation plus session time.",
        "participants": "All engineers + product owner",
        "revision_4_change": "Added optional lightweight user validation per LIFT-R3-21."
      },
      {
        "checkpoint": "After all workstreams complete",
        "gate": "Final cross-workstream validation. Run full test suite. Run full accessibility audit. Produce updated metrics report.",
        "participants": "All engineers + product owner + UI reviewer"
      }
    ],

    "rollback_strategy": "Any PR that introduces user-facing regressions not caught by CI is reverted within 24 hours and the finding is re-triaged. Each workstream produces independently revertable PRs — a regression in one workstream does not require reverting others."
  },

  "section_10_metrics": {
    "title": "Metrics and Success Criteria",
    "quantitative_metrics": [
      {
        "metric": "Magic number spacing literals",
        "baseline": "~818 total instances (to be confirmed by Phase 0 Migration Scope Sizing Report)",
        "target": "95% compliance (15 or fewer documented exceptions with explicit rationale)",
        "measurement": "CI SwiftLint custom rule reporting remaining count",
        "workstream": "W3"
      },
      {
        "metric": "Corner radius literals",
        "baseline": "To be counted by Phase 0 Migration Scope Sizing Report",
        "target": "100% migrated to CornerRadius tokens (including new compact(8) token)",
        "measurement": "CI SwiftLint custom rule",
        "workstream": "W3",
        "added_in_revision": 4
      },
      {
        "metric": "Views with Dynamic Type adaptation",
        "baseline": "4 of 156 (2.6%)",
        "target": "100% of views categorized: all needs-adaptation views adapted with evidence; naturally-responsive views documented with evidence. Zero views uncategorized. Verified at AX1, AX2, AX3, AX5.",
        "measurement": "Audit checklist + Preview inspection at AX1/AX2/AX3/AX5",
        "workstream": "W1",
        "revision_4_change": "Numeric exit threshold per LIFT-R3-07: 100% categorized, all needs-adaptation adapted, zero uncategorized."
      },
      {
        "metric": "ViewModels using ViewState pattern",
        "baseline": "4 of 9",
        "target": "9 of 9 (DashboardViewModel with per-section ViewState)",
        "measurement": "Code review",
        "workstream": "W2"
      },
      {
        "metric": "Screens with error + recovery state per canonical pattern",
        "baseline": "Partial coverage with inconsistent patterns",
        "target": "100% of screens with async data. Includes retry-exhaustion escalation after 3 failures.",
        "measurement": "Audit checklist",
        "workstream": "W2"
      },
      {
        "metric": "Hardcoded string count in views",
        "baseline": "500+ estimated",
        "target": "0 (if W4 approved)",
        "measurement": "CI lint rule",
        "workstream": "W4"
      },
      {
        "metric": "Accessibility audit score (AccessibilityManager)",
        "baseline": "Current score (measured in Phase 0)",
        "target": "Equal or higher",
        "measurement": "AccessibilityManager.accessibilityAuditScore()",
        "workstream": "W1"
      },
      {
        "metric": "Accessibility regression test assertions",
        "baseline": "0",
        "target": "10-15 targeted assertions on Dashboard, Planning, Goals views",
        "measurement": "XCTest suite count",
        "workstream": "W1",
        "added_in_revision": 4
      },
      {
        "metric": "macOS keyboard journey completion",
        "baseline": "Not currently measured",
        "target": "All 5 core journeys completable via keyboard on macOS without mouse/trackpad. At least 1 XCTest UI test per core journey.",
        "measurement": "Manual verification during Phase 0 and post-W1 + XCTest UI tests",
        "workstream": "W1"
      },
      {
        "metric": "UX metrics: no regression from wave1 baseline",
        "baseline": "Status comprehension p50: 10.8s, Shortfall action accuracy: 96.7%, Warning misinterpretation: 3.3%",
        "target": "Equal or better",
        "measurement": "Automated metrics as primary. Lightweight participant study (3-5 users, post-W1) as optional validation.",
        "workstream": "All"
      }
    ],
    "qualitative_metrics": [
      "VoiceOver users can complete all 5 core journeys without sighted assistance.",
      "All error states provide actionable, user-understandable recovery guidance per canonical patterns.",
      "After 3 consecutive failures, users see a Get Help escalation path (not an infinite retry loop).",
      "No color-only status indicators exist anywhere in the app.",
      "44pt minimum touch targets verified for all interactive elements at standard text sizes.",
      "All spacing and sizing values are semantically named tokens, not arbitrary numbers (with 15 or fewer documented exceptions).",
      "Plan-to-execution transition in Monthly Planning cycle is explicitly guided with visual hierarchy.",
      "Onboarding dismissal has a user-prompted recovery path that respects user agency.",
      "Import Data operation includes preview confirmation and merge-vs-replace semantics.",
      "Stale data messaging is severity-tiered: warning for financial data, informational for progress data.",
      "Undo snackbar for single-item deletions provides 10-second recovery window with defined edge-case behavior."
    ]
  },

  "section_11_risks": {
    "title": "Risks and Mitigations",
    "risks": [
      {
        "risk": "Large surface area (96 primary + 60 preview files) causes scope creep",
        "likelihood": "Medium",
        "impact": "Medium",
        "mitigation": "Decomposed into 4 independent workstreams with per-workstream approval gates. Each workstream is time-boxable. Phase 0 validates scope before work begins. Phase 0 scope-change policy prevents unbounded expansion: minor new findings deferred, major/critical trigger re-scoping checkpoint. Scope expansion ceiling: if new findings increase scope by >25% in engineer-days, re-propose rather than expand."
      },
      {
        "risk": "Magic number count higher than estimated (~818 vs 309) extends W3",
        "likelihood": "High",
        "impact": "Medium",
        "mitigation": "Phase 0 Migration Scope Sizing Report produces the authoritative count before W3 begins. W3 estimate range widened to 4-8 days to honestly reflect both scenarios. If count is ~818, W3 high end is 7-8 days. The primary timeline table now includes this scenario. Post-Phase 0 checkpoint must explicitly re-estimate W3.",
        "workstream": "W3",
        "revision_4_change": "Timeline range widened and primary table updated per LIFT-R3-18."
      },
      {
        "risk": "String migration (W4) introduces regressions",
        "likelihood": "Medium",
        "impact": "High",
        "mitigation": "SwiftSyntax extraction tool developed and tested against 3 representative files before full migration (1-2 day development budget). If tool development exceeds 2 days, fall back to regex-based extraction (~80% coverage) plus manual migration. Each screen area is a separate PR with full test suite run. CI lint rule catches missed strings. W4 is separately approved and can be deferred.",
        "workstream": "W4",
        "revision_4_change": "Added regex fallback contingency per LIFT-R3-19."
      },
      {
        "risk": "Magic number replacement breaks layouts",
        "likelihood": "Medium",
        "impact": "Medium",
        "mitigation": "Migration mapping tables for both spacing AND corner radius with concrete default rules (no 'context-dependent' ambiguity). Every exception requires PR-level justification. Replace one token at a time with preview verification. Existing snapshot baselines catch visual drift.",
        "workstream": "W3"
      },
      {
        "risk": "ViewState migration cascades through service layer",
        "likelihood": "Low",
        "impact": "Medium",
        "mitigation": "ViewState and ServiceResult already exist and are well-tested. Migration is adopting existing patterns, not creating new ones. Only 5 ViewModels need full migration; DashboardViewModel needs per-section split. Explicit test migration budget (0.5-1 day) and VM migration contracts defined.",
        "workstream": "W2"
      },
      {
        "risk": "Dynamic Type fixes break compact layouts",
        "likelihood": "Medium",
        "impact": "Medium",
        "mitigation": "Dynamic Type breakpoints specification provides clear decision table. ViewThatFits handles layout switching. Phase 0 categorizes views into 'needs adaptation' vs 'naturally responsive'. Test at all sizes including intermediate AX1/AX2 for smooth transitions.",
        "workstream": "W1"
      },
      {
        "risk": "Merge conflicts from touching many files across multiple PRs",
        "likelihood": "High",
        "impact": "Medium",
        "mitigation": "Required merge order: W3 (mechanical) -> W2 (structural) -> W1 (additive) -> W4 (strings). Daily rebase cadence. Designated integration engineer if concurrent development unavoidable. Workstream earlier in merge order gets merge priority on conflicts."
      },
      {
        "risk": "Parallel engineers produce inconsistent implementations",
        "likelihood": "Medium",
        "impact": "High",
        "mitigation": "UI Pattern Catalog (Section 7) with concrete rules (not 'context-dependent') agreed in Phase 0. Includes P7a undo snackbar full spec, overlay stacking rules, and all revision 4 additions. Concrete migration default rules for ambiguous values. All PRs reviewed against catalog before merge. Cross-workstream checkpoint after first workstream completes.",
        "scenario": "2+ engineers"
      },
      {
        "risk": "Existing tests fail after changes",
        "likelihood": "Medium (increased from Low due to W2 test migration scope)",
        "impact": "High",
        "mitigation": "Tests are NEVER disabled or skipped. Explicit test migration budget in W2 (0.5-1 day). Phase 0 Test Coverage Assessment identifies zero-coverage files. Any failure is fixed in test code or app code before proceeding. Each PR must pass full test suite."
      },
      {
        "risk": "SwiftLint not configured in project or CI",
        "likelihood": "Medium",
        "impact": "Low",
        "mitigation": "Phase 0 verifies SwiftLint availability. If not configured, 0.5 day infrastructure setup budgeted in W3 Phase A.",
        "workstream": "W3"
      },
      {
        "risk": "SwiftSyntax tool development takes longer than budgeted (W4)",
        "likelihood": "Medium",
        "impact": "Medium",
        "mitigation": "If SwiftSyntax tool development exceeds 2 days (e.g., complex AST edge cases with ternaries and interpolation, no prior SwiftSyntax experience), fall back to regex-based extraction covering ~80% of cases plus manual migration for remaining edge cases. The tool is a productivity accelerator, not a correctness requirement — the manual review step catches any missed strings regardless.",
        "workstream": "W4",
        "added_in_revision": 4,
        "raised_by": "LIFT-R3-19"
      },
      {
        "risk": "Phase 0 understaffed leading to incomplete deliverables",
        "likelihood": "Medium",
        "impact": "High",
        "mitigation": "Phase 0 requires minimum 2 engineers working jointly (explicit requirement, not suggestion). 5 formal deliverables plus verification of 156 files in 2-3 days is infeasible for a solo engineer. If only 1 engineer is available, Phase 0 extends to 4-5 days.",
        "added_in_revision": 4,
        "raised_by": "LIFT-R3-04"
      }
    ]
  },

  "section_12_resolved_questions": {
    "title": "Resolved Questions (formerly Open Questions)",
    "questions": [
      {
        "id": "Q1",
        "question": "Should the string catalog support multiple languages immediately?",
        "decision": "English-only + infrastructure. The .xcstrings catalog and String(localized:) pattern enable future languages without code changes. Adding actual translations is a separate workstream triggered by international release planning.",
        "impact_on_proposal": "W4 scope is infrastructure + English migration only. No translation work."
      },
      {
        "id": "Q2",
        "question": "Should AppError typed errors be adopted only in ViewModels, or also in Service layer?",
        "decision": "Moot. AppError already exists at the service layer (ErrorHandling.swift) with 25 cases. ServiceResult<T> uses .failure(AppError). ErrorTranslator converts AppError to UserFacingError for the VM/View layer. The pipeline is complete. This effort extends it, does not create it.",
        "impact_on_proposal": "No architectural decision needed. Section 6.5 documents existing pipeline."
      },
      {
        "id": "Q3",
        "question": "Should minor findings be included or deferred?",
        "decision": "Included in each workstream's Phase B (secondary flows), time-boxed. If a workstream's Phase A takes longer than estimated, Phase B minor findings can be deprioritized without blocking workstream completion.",
        "impact_on_proposal": "Each workstream includes minor findings in Phase B with explicit time-box."
      },
      {
        "id": "Q4",
        "question": "Is a post-remediation participant study feasible?",
        "decision": "Automated metrics are the primary acceptance criteria. AccessibilityManager.accessibilityAuditScore(), CI lint rules, preview snapshot verification, and full test suite passage are guaranteed-executable gates. A lightweight participant validation (3-5 users, 30-minute sessions on J1-J3) is an optional but recommended post-W1 checkpoint that can validate accessibility remediation where automated metrics cannot.",
        "impact_on_proposal": "Section 10 metrics use automated measures as primary. Lightweight participant study explicitly labeled as optional but recommended post-W1.",
        "revision_4_change": "Added specific lightweight validation format per LIFT-R3-21."
      },
      {
        "id": "Q5",
        "question": "Should spacing token values be added to visual-tokens.v1.json?",
        "decision": "Yes. Spacing and corner radius tokens will be added to the existing JSON contract following the established schema pattern (iOS tokenRef + sourceFile + spec, Android equivalent). This enables cross-platform parity — Android can adopt the same semantic spacing values.",
        "impact_on_proposal": "W3 Phase A includes JSON contract update. Token roles added per existing schema."
      },
      {
        "id": "Q6",
        "question": "Should CloudKit error recovery show generic or specific messages?",
        "decision": "Diagnose the top 5 most common CKError codes with specific user-facing messages: CKError.notAuthenticated ('Sign in to iCloud to share goals'), .networkUnavailable ('Check your internet connection — sharing will resume automatically'), .quotaExceeded ('iCloud storage is full — free up space in Settings > iCloud'), .participantMayNeedVerification ('The invited participant needs to verify their iCloud account'), .serverRecordChanged ('Another device updated this data — pull to refresh'). Fall back to generic 'Something went wrong with sharing. Try again.' for unknown errors. After 3 consecutive failures, surface Get Help action per retry-exhaustion rule.",
        "impact_on_proposal": "W2 Phase A includes ErrorTranslator extension with these 5 specific translations plus retry-exhaustion escalation."
      },
      {
        "id": "Q7",
        "question": "Should destructive deletion (M6) use undo snackbar or confirmation dialog?",
        "decision": "Use undo snackbar for single-item deletions (goals, allocations): soft-delete with 10-second undo window (15 seconds with VoiceOver active). The item is visually removed immediately (optimistic UI) and permanently deleted after the undo window expires. Full spec defined as P7a pattern in Section 7, including state management (UndoOverlayCoordinator), concurrent-deletion queue behavior, and edge cases (navigation-away, app-backgrounding, last-item-deleted). Use confirmation dialog for bulk or cascading operations (e.g., deleting a goal that has dependent allocations across multiple months). Rationale: single-item undo is less disruptive to flow than a blocking dialog. Cascading operations need explicit user awareness of consequences before proceeding.",
        "impact_on_proposal": "W2 Phase B implements P7a undo snackbar (prioritized as first Phase B item) and confirmation dialog for cascading deletions.",
        "added_in_revision": 3,
        "revised_in_revision": 4,
        "revision_4_change": "Full P7a specification added per LIFT-R3-01 including UndoOverlayCoordinator, concurrent queue, and edge cases."
      }
    ]
  },

  "section_13_dependencies": {
    "title": "Dependencies and Prerequisites",
    "items": [
      "Xcode 16+ with iOS 18 SDK (already in use).",
      "60 preview files must compile cleanly (verify in Phase 0).",
      "Existing CI gates (snapshot, accessibility) must be green before starting.",
      "No concurrent SwiftData schema changes during remediation to avoid merge conflicts.",
      "visual-tokens.v1.json (confirmed existing at docs/design/visual-tokens.v1.json) available for token role additions.",
      "UI Pattern Catalog (Section 7, including P7a and overlay stacking rules) agreed by all participating engineers before parallel work begins.",
      "W4 requires separate scope approval before infrastructure phase begins.",
      "SwiftLint availability verified in Phase 0 (if not configured, 0.5 day setup budgeted in W3).",
      "Phase 0 staffed with minimum 2 engineers (explicit requirement)."
    ]
  },

  "section_14_alternatives_considered": {
    "title": "Alternatives Considered",
    "alternatives": [
      {
        "name": "MCP-Only Automated Review",
        "description": "Use Xcode MCP review tool or Chrome DevTools MCP to automatically screenshot every screen and identify issues programmatically.",
        "why_not_chosen": "MCP tooling availability is uncertain. Automated screenshot review cannot catch interaction issues (dismissal behavior, error recovery flows, gesture accessibility). Static analysis + preview inspection provides more thorough coverage."
      },
      {
        "name": "Incremental Per-Feature Fixes",
        "description": "Address UX issues opportunistically as each feature is touched.",
        "why_not_chosen": "The project has already had 3 incremental review rounds. Systemic issues (~818 magic numbers, zero localization, 5 ViewModels without ViewState) span all views. Opportunistic fixing will never achieve full coverage. A dedicated sweep ensures nothing is missed and establishes infrastructure that prevents recurrence."
      },
      {
        "name": "Monolithic 5-Phase Plan (Revision 1 approach)",
        "description": "Bundle all workstreams into a single 13-20 day sequential effort with shared phases.",
        "why_not_chosen": "Product owner feedback correctly identified that bundling 4 independent workstreams prevents incremental value delivery, makes approval all-or-nothing, and obscures prioritization. Decomposition into independent workstreams enables shipping accessibility fixes (highest user impact) without waiting for localization infrastructure (separate scope decision)."
      },
      {
        "name": "Replace toast with persistent inline banners only",
        "description": "Instead of defining P7 Transient Confirmation pattern, replace all toast references with persistent inline banners.",
        "why_not_chosen": "Transient confirmation is the appropriate UX pattern for successful background operations (network restoration, sync completion). Persistent banners would create visual clutter for operations that need brief acknowledgment, not sustained attention. P7 addresses accessibility concerns (VoiceOver timing, reduceMotion) that made the original toast references problematic."
      },
      {
        "name": "ViewState.degraded(String) with ViewModel timers for staleness",
        "description": "Keep the existing String-based degraded state and add Timer-based refresh in ViewModels to update relative time strings.",
        "why_not_chosen": "Timer-based string refresh is an imperative pattern forced into SwiftUI's declarative model. ViewState.degraded(StalenessInfo) with Date storage lets views compute relative timestamps reactively via Date.RelativeFormatStyle, which stays current automatically. Also enables severity-tiered messaging by storing the data type alongside the stale date.",
        "added_in_revision": 4
      }
    ]
  },

  "section_15_files_affected": {
    "title": "Files and Components Affected",
    "summary": [
      {
        "area": "Views (all domains)",
        "estimated_files": "96 primary + 60 previews",
        "change_types": "Accessibility modifiers (W1), error state patterns (W2), token references (W3), string migration (W4 if approved). Preview files explicitly included in W3 migration scope."
      },
      {
        "area": "ViewModels",
        "estimated_files": 6,
        "change_types": "ViewState migration for MonthlyPlanningVM, MonthlyExecutionVM, GoalEditVM, GoalDashboardVM, CurrencyVM (W2). DashboardViewModel per-section ViewState split (W2).",
        "revision_4_change": "Count increased from 5 to 6 — DashboardViewModel per-section split per LIFT-R3-05."
      },
      {
        "area": "New: InlineErrorBanner component",
        "estimated_files": 1,
        "change_types": "New P1 pattern component with maxWidth: 600 constraint (W2). Registered in docs/COMPONENT_REGISTRY.md."
      },
      {
        "area": "New: UndoOverlayCoordinator",
        "estimated_files": 1,
        "change_types": "Overlay coordinator managing P7a undo snackbar and P7 toast display (W2 Phase B).",
        "added_in_revision": 4
      },
      {
        "area": "Utilities/VisualComponentTokens.swift",
        "estimated_files": 1,
        "change_types": "Add Spacing (6 values) and CornerRadius (6 values, including new compact(8)) enums with backward-compatible aliases (W3)"
      },
      {
        "area": "Utilities/ErrorHandling.swift",
        "estimated_files": 1,
        "change_types": "Extend AppError with CloudKit-specific cases if needed (W2)"
      },
      {
        "area": "Utilities/ServiceResult.swift",
        "estimated_files": 1,
        "change_types": "Extend ErrorTranslator with CloudKit error translations. Update ViewState.degraded to use StalenessInfo struct. Add StalenessInfo and StaleSeverity types. (W2)"
      },
      {
        "area": "docs/design/visual-tokens.v1.json",
        "estimated_files": 1,
        "change_types": "Add spacing and corner radius token roles (W3)"
      },
      {
        "area": "docs/COMPONENT_REGISTRY.md",
        "estimated_files": 1,
        "change_types": "Register InlineErrorBanner as W2 deliverable (W2)",
        "added_in_revision": 4
      },
      {
        "area": "New: Localizable.xcstrings",
        "estimated_files": 1,
        "change_types": "String catalog with all extracted strings (W4 if approved)"
      },
      {
        "area": "New: StringExtractor tool",
        "estimated_files": 1,
        "change_types": "SwiftSyntax-based extraction script (or regex fallback) — 1-2 day development budget (W4 if approved)"
      },
      {
        "area": "Existing tests",
        "estimated_files": "~15",
        "change_types": "Test updates to match ViewState migration and error type changes (W2). Budget: 0.5-1 day."
      },
      {
        "area": "New tests",
        "estimated_files": "~12-15",
        "change_types": "Accessibility regression assertions (~10-15 XCTest assertions for Dashboard/Planning/Goals, W1), macOS keyboard navigation UI tests (~5, W1), localization key completeness tests (W4), token usage lint tests (W3)",
        "revision_4_change": "Increased from ~8 to ~12-15 to account for accessibility regression tests per LIFT-R3-14."
      }
    ]
  },

  "section_16_appendix": {
    "title": "Appendix: Prior Art and Baselines",
    "previous_review_rounds": [
      "R1-R3 incremental UI/UX reviews — screenshots in docs/screenshots/review-ui-ux-incremental-r{1,2,3}/",
      "Visual System Unification (4 rounds) — docs/VISUAL_SYSTEM_UNIFICATION.md, screenshots in docs/screenshots/review-visual-system-unification-r{1,2,3,4}/",
      "Navigation Presentation reviews — docs/screenshots/review-navigation-presentation-r{1,3}/",
      "CloudKit Family Sharing reviews (4 rounds) — docs/screenshots/review-cloudkit-family-sharing-r{1,2,3,4}/",
      "Goal Dashboard redesign review — docs/screenshots/review-goal-dashboard-redesign-r1/"
    ],
    "baseline_metrics": {
      "ux_metrics_wave1": "14 participants, 72 tasks, 95% confidence. Status comprehension p50: 10.8s. Shortfall action accuracy: 96.7%. Warning misinterpretation: 3.3%.",
      "accessibility_report": "Phase release-candidate, passed=true, 0 issues. Runtime assertions: 6 tests (3 iOS, 3 Android) all passed.",
      "visual_token_contract": "v1, active, 8 required states (default, pressed, disabled, error, loading, empty, stale, recovery)."
    },
    "reference_documents": [
      "docs/ARCHITECTURE.md — System design",
      "docs/NAVIGATION_PRESENTATION_CONSISTENCY.md — Modal and navigation policy (MOD-01 through MOD-05)",
      "docs/COMPONENT_REGISTRY.md — Component catalog (to be updated with InlineErrorBanner in W2)",
      "docs/STYLE_GUIDE.md — Documentation conventions",
      "docs/design/visual-tokens.v1.json — Visual token contract (CONFIRMED EXISTING)",
      "docs/VISUAL_SYSTEM_UNIFICATION.md — Visual system unification plan and status"
    ],
    "verified_infrastructure": {
      "description": "Key codebase infrastructure verified during revision 2 preparation.",
      "items": [
        {
          "file": "Utilities/ErrorHandling.swift",
          "content": "AppError (25 cases), ErrorHandler (@MainActor singleton), ErrorAlertModifier (ViewModifier), AsyncErrorHandler (execute + executeWithRetry)",
          "lines": 405
        },
        {
          "file": "Utilities/ServiceResult.swift",
          "content": "ServiceResult<T> (4 cases with freshness metadata), ViewState (5 cases), UserFacingError (struct with recovery fields), ErrorTranslator (AppError -> UserFacingError mapping)",
          "lines": 232
        },
        {
          "file": "Utilities/VisualComponentTokens.swift",
          "content": "Domain-specific corner radius (5 tokens), fill tokens (5), status color tokens (4), stroke tokens (2). NO spacing tokens.",
          "lines": 41
        },
        {
          "file": "docs/design/visual-tokens.v1.json",
          "content": "Cross-platform token contract. contractVersion: v1, status: active, 8 requiredStates, color roles with iOS/Android refs and parity specs.",
          "status": "EXISTS ON DISK (confirmed by all reviewers)"
        }
      ]
    },
    "disputed_claims_resolution": {
      "description": "Resolution of fact-digest disputed claims in revision 3.",
      "resolutions": [
        {
          "claim_id": "CLAIM-02",
          "claim": "309 occurrences of hardcoded spacing/sizing magic numbers",
          "resolution": "Acknowledged discrepancy. 309 is unique-value count; ~818 is total-instance count. Proposal now uses ~818 as working estimate and defers authoritative count to Phase 0 Migration Scope Sizing Report. W3 estimates adjusted to 4-8 day range to account for both scenarios."
        },
        {
          "claim_id": "CLAIM-11",
          "claim": "ChartErrorView can be generalized for P1 (Inline Error) pattern",
          "resolution": "Accepted UI reviewer's finding. ChartErrorView is a full-screen VStack with 48pt icon — structurally P2, not P1. P1 is now defined as a new InlineErrorBanner component. ChartErrorView is reclassified as a domain-specific P2 variant. InlineErrorBanner listed as W2 deliverable."
        },
        {
          "claim_id": "CLAIM-12",
          "claim": "SwiftSyntax extraction tool will extract 500+ strings in <1 hour",
          "resolution": "Accepted architect's clarification. <1 hour is execution time; tool development is 1-2 days. W4 Phase A adjusted from 2-3 to 3-4 days. Total W4 adjusted from 7-11 to 9-13 days. Regex fallback contingency added if tool development exceeds 2 days."
        }
      ]
    }
  }
}