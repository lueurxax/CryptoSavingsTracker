# Evidence Pack

## A. Implementation Evidence
| Evidence ID | Artifact | Scope | Key Fact | Relevance |
|---|---|---|---|---|
| DOC-01 | `docs/proposals/UI_UX_INCREMENTAL_IMPROVEMENTS_PROPOSAL.md` | Workstream A | Proposal wording now uses the locked month-explicit contract `Finish {month}`. | Keeps proposal text aligned with the implemented shared copy contract. |
| DOC-02 | `docs/copy/FINANCIAL_COPY_DICTIONARY.md` | Workstream A | Dictionary remains the normative source for targeted planning/form strings, including `Finish {month}` and the iOS goal save error copy. | Confirms approved wording after implementation. |
| DOC-03 | `scripts/validate_copy_contracts.py` | Workstream A | Validator now checks dictionary shape, declared path presence, wording presence, and unmanaged inline literals in audited planning/form surfaces. | Provides the strengthened contract gate required by the proposal. |
| DOC-04 | `.github/workflows/planning-form-copy-gates.yml` | Workstream A | CI runs the dedicated planning/form copy validator and uploads the JSON report artifact. | Keeps release-gate ownership aligned with proposal scope. |
| DOC-05 | `ios/CryptoSavingsTracker/Views/Planning/StaleDraftBanner.swift` | Workstream C | Runtime stale-draft flow now exposes one visible `Resolve` entry point plus explicit delete confirmation including goal name and month. | Confirms the stale-draft resolution contract implemented in UI. |
| DOC-06 | `ios/CryptoSavingsTracker/Views/Goals/GoalFormSupport.swift` | Workstream D | Shared bottom action region exposes validation summary, save error, retry CTA, and test hooks for focused field assertions. | Anchors the fixed-bottom form contract and UI-testability. |
| DOC-07 | `ios/CryptoSavingsTracker/Views/AddGoalViewPreview.swift` | Workstream D | Preview set now includes invalid state, persistence error, and Dynamic Type coverage for the form flow. | Closes the preview/evidence gap for form accessibility. |
| DOC-08 | `ios/CryptoSavingsTrackerUITests/CryptoSavingsTrackerUITests.swift` | Workstream D | UI tests cover invalid-submit focus movement and persistence failure -> retry success on Add Goal. | Provides runtime evidence for the form recovery contract. |
| DOC-09 | `ios/CryptoSavingsTrackerUITests/MonthlyPlanningUITests.swift` | Workstreams B/C | UI tests cover stale-draft delete confirmation plus compact above-the-fold visibility with and without stale drafts. | Provides runtime evidence for stale context and compact layout assertions. |

## B. Runtime and Preview Evidence
| Evidence ID | Artifact | Flow Step | State | Source | Relevance |
|---|---|---|---|---|---|
| RUN-01 | `CryptoSavingsTrackerUITests.testAddGoalInvalidSaveFocusesFirstInvalidField` | Add Goal | Invalid submit | XCTest UI test | Verifies first invalid field focus and validation summary visibility. |
| RUN-02 | `CryptoSavingsTrackerUITests.testGoalFormPersistenceFailureRetryFlow` | Add Goal | Save failure -> retry | XCTest UI test | Verifies blocking persistence error, visible `Retry`, and successful retry path. |
| RUN-03 | `MonthlyPlanningUITests.testStaleDraftDeleteConfirmationShowsGoalAndMonthAtRuntime` | Monthly Planning | Stale draft delete confirmation | XCTest UI test | Verifies destructive confirmation wording includes goal and month context. |
| RUN-04 | `MonthlyPlanningUITests.testCompactPlanningShowsFirstGoalRowAboveFoldWithoutStaleDrafts` | Monthly Planning | Compact iPhone, no stale drafts | XCTest UI test | Verifies first goal row stays above the fold without scrolling. |
| RUN-05 | `MonthlyPlanningUITests.testCompactPlanningShowsStaleBannerAndFirstGoalRowAboveFold` | Monthly Planning | Compact iPhone, stale drafts present | XCTest UI test | Verifies stale banner and first goal row remain visible together above the fold. |
| PRE-01 | `AddGoalViewPreview` (`Add Goal Dynamic Type`) | Add Goal | Accessibility Dynamic Type | Xcode Preview | Verifies fixed bottom action area and validation summary under large text. |
| PRE-02 | `CompactGoalRequirementRowPreview` (`Compact Goal Row Dynamic Type`) | Monthly Planning | Accessibility Dynamic Type | Xcode Preview | Preserves the compact-row Dynamic Type evidence required for Workstream B. |
| PRE-03 | `GoalRequirementRowPreview` | Monthly Planning | Shared macOS row continuity | Xcode Preview | Keeps continuity evidence for the unchanged shared row contract. |

## C. Validator Artifact
| Evidence ID | Artifact | Expected Output | Relevance |
|---|---|---|---|
| VAL-01 | `artifacts/copy-contracts/planning-form-copy-report.json` | PASS for `COPY-DICT-001`, `COPY-PATH-001`, `COPY-LITERAL-001`, `COPY-LITERAL-002` | Provides machine-readable evidence for the strengthened planning/form copy gate. |

## D. Assumptions and Defaults
- ASSUMP-01: Runtime delete-confirmation evidence is satisfied by deterministic UI tests; no static preview is required for that interaction.
- ASSUMP-02: The month-explicit copy contract remains authoritative, so proposal wording is updated to match code and dictionary rather than changing the implementation back to generic copy.
- ASSUMP-03: Form focus evidence is validated through test hooks plus visible validation state, not through private platform APIs.
