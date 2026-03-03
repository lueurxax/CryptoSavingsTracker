#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

BASE_REF="${NAV_BASE_REF:-origin/main}"
if [[ -n "${1:-}" ]]; then
  BASE_REF="$1"
fi
MODE="${NAV_GATE_MODE:-pr}"
if [[ -n "${2:-}" ]]; then
  MODE="$2"
fi

echo "[1/4] iOS navigation policy gate (forbidden APIs + NAV-MOD tags)"
if [[ "${MODE}" == "release" ]]; then
  python3 scripts/check_navigation_policy.py \
    --strict-mod-tags \
    --strict-preview-segregation \
    --allowlist docs/testing/navigation-policy-allowlist.v1.json \
    --report-out artifacts/navigation/policy-report.json
else
  python3 scripts/check_navigation_policy.py \
    --changed-only \
    --base-ref "${BASE_REF}" \
    --strict-mod-tags \
    --strict-preview-segregation \
    --allowlist docs/testing/navigation-policy-allowlist.v1.json \
    --report-out artifacts/navigation/policy-report.json
fi

echo "[2/4] Hard-cutover gate (no migration runtime layer)"
if [[ "${MODE}" == "release" ]]; then
  python3 scripts/check_navigation_hard_cutover.py \
    --report-out artifacts/navigation/hard-cutover-report.json
else
  python3 scripts/check_navigation_hard_cutover.py \
    --changed-only \
    --base-ref "${BASE_REF}" \
    --report-out artifacts/navigation/hard-cutover-report.json
fi

echo "[3/4] Android top-journey parity matrix gate"
python3 scripts/check_android_navigation_parity_matrix.py \
  --report-out artifacts/navigation/android-parity-matrix-report.json

echo "[4/4] MOD-02 compact screenshot artifact gate"
python3 scripts/check_mod02_compact_artifacts.py \
  --changed-only \
  --base-ref "${BASE_REF}" \
  --report-out artifacts/navigation/mod02-compact-gate-report.json

if [[ "${MODE}" == "release" ]]; then
  echo "[5/5] Navigation release evidence package gate"
  python3 scripts/check_navigation_release_evidence.py \
    --release-dir docs/release/navigation/latest \
    --schema docs/testing/navigation-telemetry-schema.v1.json \
    --report-out artifacts/navigation/release-evidence-report.json
fi

echo "All navigation policy gates passed (mode=${MODE})."
