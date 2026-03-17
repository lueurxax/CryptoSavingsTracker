# CloudKit Release Package Template

Archive each approved CloudKit Phase 1 release package under:

- `docs/release/cloudkit/<release-id>/`

Minimum files:

1. `README.md`
2. `go-no-go.md`
3. `cloudkit-cutover-test-report.md`
4. `device-migration-log.txt`
5. `diagnostics-report.json`
6. `cleanup-verification.md`

Repository-truth rules:

- `README.md` must reference `ADR-CK-CUTOVER-001`, the Phase 1 evidence checklist, and the CloudKit cutover release-gate runbook.
- `go-no-go.md` must reference the exact commit SHA used for approval.
- `device-migration-log.txt` must show successful staging validation and successful migration completion.
- `cleanup-verification.md` must confirm `cloud-primary` and `cloud-primary-staging` cleanup behavior and absence of sqlite API-violation warnings.
