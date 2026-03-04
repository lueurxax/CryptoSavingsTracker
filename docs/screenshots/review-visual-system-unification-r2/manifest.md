# Visual System R2 Screenshot Manifest (Superseded)

Superseded by:

- `docs/screenshots/review-visual-system-unification-r3/manifest.md`

## Required Coverage

| Flow | Component | Platform | State | Artifact |
|---|---|---|---|---|
| Planning | `planning.header_card` | iOS | default | `docs/screenshots/review-visual-system-unification-r1/planning-01-main-iphone17pro-light.png` |
| Planning | `planning.goal_row` | iOS | default | `docs/screenshots/review-visual-system-unification-r1/planning-03-goalrow-normal-iphone17pro-light.png` |
| Planning | `planning.goal_row` | iOS | error | `docs/screenshots/review-visual-system-unification-r1/planning-04-goalrow-critical-iphone17pro-light.png` |
| Dashboard | `dashboard.summary_card` | iOS | default | `docs/screenshots/Simulator Screenshot - iPhone 16 Pro Max - 2025-08-26 at 20.35.14.png` |
| Dashboard | `dashboard.summary_card` | iOS | error | `planned://ios/dashboard-summary/error` |
| Dashboard | `dashboard.summary_card` | Android | default | `planned://android/dashboard-summary/default` |
| Dashboard | `dashboard.summary_card` | Android | error | `planned://android/dashboard-summary/error` |
| Settings | `settings.section_row` | iOS | default | `planned://ios/settings-row/default` |
| Settings | `settings.section_row` | iOS | error | `planned://ios/settings-row/error` |
| Settings | `settings.section_row` | Android | default | `planned://android/settings-row/default` |
| Settings | `settings.section_row` | Android | error | `planned://android/settings-row/error` |

## Completion Rules

1. `release-candidate` requires all `planned://` entries replaced by file paths.
2. Each captured screenshot must also be referenced in `docs/design/visual-state-matrix.v1.json`.
3. Any missing screenshot blocks `scripts/run_visual_system_release_gates.sh`.
