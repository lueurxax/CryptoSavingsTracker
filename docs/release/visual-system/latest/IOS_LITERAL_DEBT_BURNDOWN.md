# iOS Visual Literal Debt Burndown

| Field | Value |
|---|---|
| Owner | iOS Lead |
| Review Cadence | Weekly |
| Target | Zero new literal violations at wave signoff |
| Enforcement | `bash scripts/check_ios_visual_literals.sh` |

## Current State (2026-03-03)

1. New violations vs baseline: `0`
2. Release-blocking flow status: `pass`
3. Release gate status: `pass`

## Cleanup SLA

1. Zero new iOS visual literal violations is mandatory at wave signoff.
2. Any newly introduced violation must be remediated before merge to release branch.
3. Exceptions require documented ticket + expiry and cannot bypass release certification.

## Weekly Tracking

| Week | New Violations | Closed | Net | Owner Note |
|---|---:|---:|---:|---|
| 2026-W10 | 0 | 0 | 0 | Baseline stable after R5 remediation. |
