# ADR: Data Visualization Motion Semantics

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-03-03 |
| Scope | Chart-specific motion semantics |
| Related Proposal | `docs/proposals/VISUAL_SYSTEM_UNIFICATION_PROPOSAL.md` |

## Context

The visual system proposal governs app-wide finance UI semantics. Chart interactions need separate motion rules to avoid conflating dense data animation with core status/action surfaces.

## Decision

1. Chart motion is managed independently from core UI motion tokens.
2. Critical thresholds in charts still map to shared semantic status roles (`success`, `warning`, `error`).
3. Reduced-motion behavior remains mandatory and inherits platform accessibility settings.

## Consequences

1. Core proposal remains focused and enforceable for release-blocking flows.
2. Data-viz teams can evolve chart interactions without destabilizing core finance UI contracts.
3. Cross-platform parity still applies at semantic threshold level.
