# Accessibility and Dynamic Type Hardening Proposal

> Audit mapping: issue #9 (accessibility and scaling gaps)

| Metadata | Value |
|---|---|
| Status | Draft |
| Last Updated | 2026-03-01 |
| Platform | iOS + Android |
| Scope | Dynamic Type, touch targets, VoiceOver/TalkBack semantics |

---

## 1) Problem

Critical controls and data labels may truncate or become hard to use under larger accessibility text sizes.

## 2) Goal

Guarantee usability for large text, screen readers, and reduced motion users without losing financial clarity.

## 3) Requirements

- Minimum tap target 44x44pt (iOS) / 48dp (Android).
- Avoid `fixedSize`/forced small controls on primary CTAs.
- No critical value should become unreadable at large text categories.
- Every status card and CTA must have explicit accessibility labels/hints.

## 4) Proposed Changes

1. Replace fragile layout constraints with adaptive stacks.
2. Introduce `AccessibilityLayoutMode` for dense rows:
   - `compact` (default),
   - `expandedForAX` (large text categories).
3. Define one semantic pattern for financial values:
   - amount,
   - currency,
   - context (planned/contributed/remaining).
4. Add automated accessibility test matrix:
   - text sizes: default, XL, XXXL, AX5,
   - light/dark,
   - VoiceOver focus order.

## 5) Rollout

1. Refactor planning and execution rows first.
2. Refactor settings and forms.
3. Add accessibility snapshots and UI assertions to CI.

## 6) Acceptance Criteria

- No clipped primary action buttons at AX sizes.
- VoiceOver reads monetary context correctly in planning and execution screens.
- All major user flows are operable without precision loss at large text sizes.
