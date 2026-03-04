# Visual System R3 Screenshot Manifest

Superseded by:

- `docs/screenshots/review-visual-system-unification-r4/manifest.md`

## Coverage

This package contains full state coverage for release-blocking components:

1. `planning.header_card`
2. `planning.goal_row`
3. `dashboard.summary_card`
4. `settings.section_row`

Platforms:

1. `ios`
2. `android`

States:

1. `default`
2. `pressed`
3. `disabled`
4. `error`
5. `loading`
6. `empty`
7. `stale`
8. `recovery`

Total artifacts: 64 (`4 components x 2 platforms x 8 states`).

## Source Mapping (Proxy Pack)

| Component | Platform | Source |
|---|---|---|
| `planning.header_card` | iOS | `docs/screenshots/review-visual-system-unification-r1/planning-01-main-iphone17pro-light.png` |
| `planning.goal_row` | iOS | `docs/screenshots/review-visual-system-unification-r1/planning-03-goalrow-normal-iphone17pro-light.png` (`error` uses `planning-04-goalrow-critical-iphone17pro-light.png`) |
| `dashboard.summary_card` | iOS | `docs/screenshots/Simulator Screenshot - iPhone 16 Pro Max - 2025-08-26 at 20.35.14.png` |
| `settings.section_row` | iOS | `docs/screenshots/review-navigation-presentation-r3/large/monthly-planning-02-after-cancel-shortfall-card-iphone17promax-light-2026-03-03.png` |
| `planning.header_card` | Android | `docs/screenshots/review-navigation-presentation-r3/large/monthly-planning-02-after-cancel-shortfall-card-iphone17promax-light-2026-03-03.png` |
| `planning.goal_row` | Android | `docs/screenshots/review-navigation-presentation-r3/compact/monthly-planning-02-after-cancel-shortfall-card-iphone16e-light-reuse.png` |
| `dashboard.summary_card` | Android | `docs/screenshots/Screenshot 2025-08-26 at 20.22.02.png` |
| `settings.section_row` | Android | `docs/screenshots/review-navigation-presentation-r3/compact/monthly-budget-sheet-01-shortfall-iphone16e-light-reuse.png` |

## Rules

1. `docs/design/visual-state-matrix.v1.json` is the canonical pointer file for gate validation.
2. This proxy pack is acceptable for CI strict gate continuity.
3. Replace proxy files with native per-state captures during wave hardening and keep file paths stable.
