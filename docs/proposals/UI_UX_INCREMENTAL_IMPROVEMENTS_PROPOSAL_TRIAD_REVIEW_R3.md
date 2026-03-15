# Consolidated Proposal Review

## 0. Evidence Pack Summary
- Document inputs reviewed: revised proposal after `R2`, current planning/form/stale-draft code, and current preview coverage.
- Internet sources reviewed: Apple Design Tips, Apple HIG Menus, Android Compose text-input guidance, and CFPB guidance on consumer understanding.
- Xcode screenshots captured: refreshed compact planning and Edit Goal previews, with same-day stale-row evidence reused because UI code is unchanged.
- Remaining assumptions: this pass validates proposal quality, not implementation progress.

## 1. Executive Summary
- Overall readiness: Green
- Top 3 risks:
  1. Section 6 still points preview evidence at `GoalRequirementRow` instead of the new iOS-specific compact wrapper boundary defined in Workstream B.
  2. One Workstream A copy string (`Budget saved, not used for this month yet`) still reads slightly mechanical for a finance product.
  3. The proposal is now mostly execution-ready; remaining issues are consistency/polish, not structural blockers.
- Top 3 opportunities:
  1. Align Section 6 fixture naming with the new Workstream B component boundary and the proposal becomes internally consistent end to end.
  2. Tighten the one remaining awkward copy string before the copy dictionary is frozen.
  3. Keep this proposal stable now; the major design/architecture questions are resolved.

## 2. Parallel Review Scorecard
| Discipline | Score (1-10) | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|---:|
| UI (Liquid Glass) | 9.1 | 0 | 0 | 1 | 0 |
| UX (Financial) | 8.9 | 0 | 0 | 0 | 1 |
| iOS Architecture | 8.9 | 0 | 0 | 1 | 0 |

## 3. Findings by Discipline

### 3.1 UI Review Findings
- [Medium] Section 6 still names the wrong row surface for preview evidence
  - Evidence: DOC-03, DOC-04, DOC-07, SCR-01, WEB-01
  - Why it matters: Workstream B now says the compact iPhone behavior lives in an iOS-specific wrapper in `PlanningView`, but Section 6 still asks for `GoalRequirementRow` preview fixtures. That risks validating the unchanged shared row instead of the new iPhone-specific surface.
  - Recommended fix: Rename the Section 6 row preview fixtures to the iOS-specific compact wrapper surface, or explicitly require both: wrapper preview for iPhone behavior and shared-row preview for macOS continuity.
  - Acceptance criteria: Section 6 references the same row surface that Workstream B defines as the implementation boundary.

### 3.2 UX Review Findings
- [Low] One normalized copy string still sounds slightly mechanical for a finance flow
  - Evidence: DOC-02, WEB-04
  - Why it matters: `Budget saved, not used for this month yet` is directionally better than internal jargon, but `used` is still a little imprecise for a budgeting/planning state. The product is close enough now that wording quality becomes noticeable.
  - Recommended fix: Consider tightening it during the dictionary pass to something closer to `Budget saved, not yet applied to this month` if the product/content team agrees.
  - Acceptance criteria: Final approved wording for the `not applied` state is reviewed in the copy dictionary with finance-specific clarity in mind.

### 3.3 Architecture Review Findings
- [Medium] Preview evidence should align to the new component boundary before implementation starts
  - Evidence: DOC-03, DOC-04, DOC-06, DOC-07
  - Why it matters: The proposal has now done the hard architectural work of isolating iOS-only row behavior from macOS. The remaining risk is simply that the evidence contract still points at the pre-existing shared component.
  - Recommended fix: Update Section 6 and Phase 1 to reference the future iOS-specific compact wrapper explicitly.
  - Acceptance criteria: Phase 1 preview scaffolding is defined against the wrapper component or wrapper-host preview, not only against the shared `GoalRequirementRow`.

## 4. Cross-Discipline Conflicts and Resolutions
- Conflict: The proposal now defines an iOS-specific row wrapper, but the evidence contract still names the shared row.
  - Tradeoff: Reusing old preview names is faster, but it weakens validation fidelity.
  - Decision: Align preview evidence with the new wrapper boundary.
  - Owner: iOS lead + QA

- Conflict: The proposal is structurally ready, while one copy phrase still invites last-mile refinement.
  - Tradeoff: Freezing wording now is faster, but minor finance-language polish still has value before implementation.
  - Decision: Treat copy refinement as dictionary-stage polish, not as a blocker to the proposal.
  - Owner: Product + content owner

## 5. Prioritized Action Backlog
| Priority | Item | Discipline | Owner | Horizon | Dependency | Success Metric |
|---|---|---|---|---|---|---|
| P1 | Rename Section 6 row preview fixtures to the iOS-specific compact wrapper boundary (or require both wrapper + shared-row previews explicitly) | UI / Architecture | iOS lead + QA | Now | None | Preview evidence validates the actual iPhone surface being changed |
| P2 | Tighten the `not applied` copy wording during the dictionary pass if product/content agree | UX | Product + content owner | Next | Copy dictionary creation | Final state wording reads naturally in a finance context |

## 6. Execution Plan
- Now (0-2 weeks):
  - Align Section 6 preview fixture naming with the iOS-specific compact row wrapper.
- Next (2-6 weeks):
  - Polish the final `not applied` wording during the copy dictionary review if needed.
- Later (6+ weeks):
  - No structural follow-up required from this review pass; move to implementation once the minor consistency cleanup is done.

## 7. Open Questions
- Should Section 6 name only the iOS-specific compact wrapper, or should it explicitly require both the wrapper preview and the unchanged shared-row preview?
- Does the product/content owner want to keep `Budget saved, not used for this month yet`, or tighten it one more step during dictionary approval?
