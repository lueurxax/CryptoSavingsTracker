# ADR-NAV-CI-PARSER-001: Navigation Policy CI Parser and Fallback

## Status

Accepted (2026-03-03)

## Context

`docs/NAVIGATION_PRESENTATION_CONSISTENCY.md` requires a CI gate that:

1. blocks forbidden iOS APIs in active source,
2. validates machine-checkable modal decision annotations,
3. remains robust for mixed files containing active code and previews.

The proposal defines rule IDs `NAV001`, `NAV002`, and `NAV003`, and requires file/line actionable output.

## Decision

Use a two-stage parser strategy for CI policy enforcement:

1. Stage A (current, repository-native):
   - Script: `scripts/check_navigation_policy.py`
   - Approach: lightweight line scanner with preview-aware exclusion.
   - Rules:
     - `NAV001`: forbidden APIs (`NavigationView`, `.actionSheet`, `ActionSheet`).
     - `NAV002`: missing or invalid `// NAV-MOD: MOD-0x` annotation near modal call-sites.
     - `NAV003`: preview segregation fallback signal when active + preview declarations are mixed.
2. Stage B (planned hardening):
   - Replace/augment Stage A with `SwiftSyntax` scanner for precise Swift AST ownership.
   - Keep the same rule IDs and report contract for CI continuity.

## Report Contract

All findings emitted by policy jobs must include:

- `file`
- `line`
- `rule_id`
- `message`
- `suggested_fix`

Current report artifact:

- `artifacts/navigation/policy-report.json`

## Failure Modes and Handling

1. Parsing ambiguity in mixed source:
   - Behavior: emit `NAV003` with remediation to extract preview code into `*Preview*.swift`.
   - Severity: warning by default, fail when strict preview segregation is enabled.
2. Missing decision tag:
   - Behavior: emit `NAV002` with exact line and expected tag format.
3. Invalid decision tag:
   - Behavior: emit `NAV002` with allowed ID list `MOD-01...MOD-05`.
4. Forbidden API usage in active code:
   - Behavior: emit blocking `NAV001`.

## Ownership

- Technical owner: Mobile Platform Team
- CI policy approvers: Mobile Platform Team Lead + iOS Lead
- Rollout sign-off stakeholder: Engineering Manager

## Consequences

- Immediate enforcement available without external parser toolchain.
- Rule IDs remain stable for downstream dashboards and PR automation.
- Preview extraction fallback prevents silent false negatives until AST parser stage is finalized.
