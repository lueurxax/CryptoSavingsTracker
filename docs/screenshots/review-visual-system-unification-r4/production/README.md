# Production Flow Evidence

This folder stores release-gate production capture artifacts for mandatory routes:

1. `planning`
2. `dashboard`
3. `settings`

Each route requires these states on both platforms:

1. `default`
2. `error`
3. `recovery`

Generate artifacts with:

```bash
bash scripts/capture_ios_production_flows.sh
bash scripts/capture_android_production_flows.sh
```

Machine-readable manifest:

- `docs/screenshots/review-visual-system-unification-r4/production/manifest.v1.json`
