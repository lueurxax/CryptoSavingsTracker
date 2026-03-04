# Visual System R4 Runtime Capture Manifest

## Capture Type

Runtime capture from simulator/emulator using dedicated visual state capture screens.

1. iOS: `scripts/capture_ios_visual_states.sh`
2. Android: `scripts/capture_android_visual_states.sh`

Production-flow release evidence capture (required for release gates):

1. iOS: `scripts/capture_ios_production_flows.sh`
2. Android: `scripts/capture_android_production_flows.sh`
3. Production manifest: `docs/screenshots/review-visual-system-unification-r4/production/manifest.v1.json`

Default runtime targets:

1. iOS Simulator: `iPhone 16e`
2. Android Emulator: `Medium_Phone_API_36.1`

## Matrix Coverage

Components:

1. `planning.header_card`
2. `planning.goal_row`
3. `dashboard.summary_card`
4. `settings.section_row`

States:

1. `default`
2. `pressed`
3. `disabled`
4. `error`
5. `loading`
6. `empty`
7. `stale`
8. `recovery`

Platforms:

1. `ios`
2. `android`

Total PNG artifacts: `64`.

## Location Layout

1. `docs/screenshots/review-visual-system-unification-r4/ios/<component>/<state>.png`
2. `docs/screenshots/review-visual-system-unification-r4/android/<component>/<state>.png`

## Canonical Mapping

`docs/design/visual-state-matrix.v1.json` points to this R4 package for all release-blocking component states.

Release snapshot gates additionally require production-flow evidence for routes:

1. `planning`
2. `dashboard`
3. `settings`
