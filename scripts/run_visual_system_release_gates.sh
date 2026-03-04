#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

overall_failed=0
CANONICAL_RELEASE_DIR="docs/release/visual-system/latest"
RUNTIME_TEST_RESULTS_ARTIFACT="artifacts/visual-system/runtime-accessibility-test-results.json"
RUNTIME_ASSERTIONS_ARTIFACT="artifacts/visual-system/runtime-accessibility-assertions.json"
UX_METRICS_SOURCE="${VISUAL_UX_METRICS_SOURCE:-docs/release/visual-system/latest/ux-metrics-report.json}"
UX_METRICS_ARTIFACT="artifacts/visual-system/ux-metrics-report.json"
required_test_mode="${VISUAL_ACCESSIBILITY_REQUIRED_TEST_MODE:-full}"
production_max_age_hours="${VISUAL_PRODUCTION_CAPTURE_MAX_AGE_HOURS:-24}"

status_validateTokens="failed"
status_tokenParity="failed"
status_variantExpiry="failed"
status_stateMatrix="failed"
status_literalBaselineBudget="failed"
status_iosLiteralGuard="failed"
status_androidLiteralGuard="failed"
status_snapshot="failed"
status_runtimeAccessibilityTests="failed"
status_accessibility="failed"
status_uxMetrics="failed"
status_certificationFreshness="failed"

allow_fixture_arg=""
if [[ "${VISUAL_ACCESSIBILITY_ALLOW_FIXTURE:-}" == "1" ]]; then
  allow_fixture_arg="--allow-fixture"
elif [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
  allow_fixture_arg="--allow-fixture"
fi

allow_smoke_release_arg=""
if [[ "${VISUAL_ACCESSIBILITY_ALLOW_SMOKE_RELEASE:-}" == "1" ]]; then
  allow_smoke_release_arg="--allow-smoke-release"
fi

if [[ -z "${VISUAL_SYSTEM_WAVE:-}" ]]; then
  echo "error: VISUAL_SYSTEM_WAVE is required in release gates (for example: wave1, wave2, wave3)"
  exit 2
fi
if [[ ! "${VISUAL_SYSTEM_WAVE}" =~ ^wave[0-9]+$ ]]; then
  echo "error: VISUAL_SYSTEM_WAVE must match ^wave[0-9]+$ (got '${VISUAL_SYSTEM_WAVE}')"
  exit 2
fi
if [[ "${required_test_mode}" != "smoke" && "${required_test_mode}" != "full" ]]; then
  echo "error: VISUAL_ACCESSIBILITY_REQUIRED_TEST_MODE must be 'smoke' or 'full'"
  exit 2
fi
if [[ "${GITHUB_ACTIONS:-}" == "true" && "${required_test_mode}" != "full" ]]; then
  echo "error: CI release requires VISUAL_ACCESSIBILITY_REQUIRED_TEST_MODE=full"
  exit 2
fi

default_runtime_test_command="python3 scripts/run_visual_accessibility_runtime_test_smoke.py --output ${RUNTIME_TEST_RESULTS_ARTIFACT}"
runtime_test_command="${VISUAL_ACCESSIBILITY_TEST_COMMAND:-}"
if [[ -z "${runtime_test_command}" ]]; then
  if [[ -n "${VISUAL_ACCESSIBILITY_TEST_RESULTS_SOURCE:-}" ]]; then
    runtime_test_command=""
  else
    runtime_test_command="${default_runtime_test_command}"
  fi
fi

echo "[1/17] Validate visual token schema"
if python3 scripts/validate_visual_tokens.py; then
  status_validateTokens="passed"
else
  overall_failed=1
fi

echo "[2/17] Check cross-platform token parity"
if python3 scripts/check_visual_token_parity.py; then
  status_tokenParity="passed"
else
  overall_failed=1
fi

echo "[3/17] Check approved variant expiry controls"
if python3 scripts/check_visual_variant_expiry.py; then
  status_variantExpiry="passed"
else
  overall_failed=1
fi

echo "[4/17] Validate visual state matrix (release-candidate strict)"
if python3 scripts/validate_visual_state_matrix.py --phase release-candidate --require-artifact-files --report-out artifacts/visual-system/state-matrix-release.json; then
  status_stateMatrix="passed"
else
  overall_failed=1
fi

echo "[5/17] Validate visual literal baseline burndown budgets"
if python3 scripts/check_visual_literal_baseline_burndown.py --wave "${VISUAL_SYSTEM_WAVE}"; then
  status_literalBaselineBudget="passed"
else
  overall_failed=1
fi

echo "[6/17] Run iOS visual literal guard"
if bash scripts/check_ios_visual_literals.sh; then
  status_iosLiteralGuard="passed"
else
  overall_failed=1
fi

echo "[7/17] Run Android visual literal guard"
if bash scripts/check_android_visual_literals.sh; then
  status_androidLiteralGuard="passed"
else
  overall_failed=1
fi

echo "[8/17] Run snapshot checks (release mode)"
if python3 scripts/run_visual_snapshot_checks.py --mode release --production-max-age-hours "${production_max_age_hours}"; then
  status_snapshot="passed"
else
  overall_failed=1
fi

echo "[9/17] Execute runtime accessibility tests"
if python3 scripts/run_visual_accessibility_runtime_tests.py \
  --mode release \
  --output "${RUNTIME_TEST_RESULTS_ARTIFACT}" \
  --source "${VISUAL_ACCESSIBILITY_TEST_RESULTS_SOURCE:-}" \
  --test-command "${runtime_test_command}" \
  --required-test-mode "${required_test_mode}" \
  --commit-sha "${GITHUB_SHA:-}" \
  --ci-job-id "github-run-${GITHUB_RUN_ID:-local}:${GITHUB_JOB:-release-gates}" \
  ${allow_smoke_release_arg:+${allow_smoke_release_arg}} \
  ${allow_fixture_arg:+${allow_fixture_arg}}; then
  status_runtimeAccessibilityTests="passed"
else
  overall_failed=1
fi

echo "[10/17] Generate runtime accessibility assertions from test-results"
if python3 scripts/generate_runtime_accessibility_assertions.py \
  --mode release \
  --test-results "${RUNTIME_TEST_RESULTS_ARTIFACT}" \
  --output "${RUNTIME_ASSERTIONS_ARTIFACT}" \
  --commit-sha "${GITHUB_SHA:-}" \
  --ci-job-id "github-run-${GITHUB_RUN_ID:-local}:${GITHUB_JOB:-release-gates}" \
  ${allow_fixture_arg:+${allow_fixture_arg}}; then
  :
else
  overall_failed=1
fi

echo "[11/17] Run accessibility checks (release mode)"
if python3 scripts/run_visual_accessibility_checks.py --mode release --runtime-assertions "${RUNTIME_ASSERTIONS_ARTIFACT}"; then
  status_accessibility="passed"
else
  overall_failed=1
fi

echo "[12/17] Validate UX metrics report (release mode)"
if [[ ! -f "${UX_METRICS_SOURCE}" ]]; then
  echo "missing UX metrics source artifact: ${UX_METRICS_SOURCE}"
  overall_failed=1
else
  mkdir -p "$(dirname "${UX_METRICS_ARTIFACT}")"
  cp "${UX_METRICS_SOURCE}" "${UX_METRICS_ARTIFACT}"
  if ! cmp -s "${UX_METRICS_SOURCE}" "${UX_METRICS_ARTIFACT}"; then
    echo "UX metrics canonicalization failed: ${UX_METRICS_SOURCE} -> ${UX_METRICS_ARTIFACT}"
    overall_failed=1
  elif python3 scripts/validate_visual_ux_metrics.py --report "${UX_METRICS_ARTIFACT}"; then
    status_uxMetrics="passed"
  else
    overall_failed=1
  fi
fi

echo "[13/17] Generate provisional release certification report"
python3 scripts/generate_visual_release_certification_report.py \
  --step-status "validateTokens=${status_validateTokens}" \
  --step-status "tokenParity=${status_tokenParity}" \
  --step-status "variantExpiry=${status_variantExpiry}" \
  --step-status "stateMatrix=${status_stateMatrix}" \
  --step-status "literalBaselineBudget=${status_literalBaselineBudget}" \
  --step-status "iosLiteralGuard=${status_iosLiteralGuard}" \
  --step-status "androidLiteralGuard=${status_androidLiteralGuard}" \
  --step-status "snapshot=${status_snapshot}" \
  --step-status "runtimeAccessibilityTests=${status_runtimeAccessibilityTests}" \
  --step-status "accessibility=${status_accessibility}" \
  --step-status "uxMetrics=${status_uxMetrics}" \
  --step-status "certificationFreshness=failed" \
  --source-commit "${GITHUB_SHA:-}" \
  --source-ci-run-id "github-run-${GITHUB_RUN_ID:-local}:${GITHUB_JOB:-release-gates}"
provisional_status=$?
if [[ ${provisional_status} -gt 1 ]]; then
  overall_failed=1
fi

echo "[14/17] Validate certification freshness and commit provenance"
if python3 scripts/check_visual_release_certification_freshness.py \
  --report artifacts/visual-system/release-certification-report.json \
  --expected-commit "${GITHUB_SHA:-}" \
  --max-age-hours 24 \
  --report-out artifacts/visual-system/release-certification-freshness-report.json; then
  status_certificationFreshness="passed"
else
  overall_failed=1
fi

echo "[15/17] Generate final release certification report"
if ! python3 scripts/generate_visual_release_certification_report.py \
  --step-status "validateTokens=${status_validateTokens}" \
  --step-status "tokenParity=${status_tokenParity}" \
  --step-status "variantExpiry=${status_variantExpiry}" \
  --step-status "stateMatrix=${status_stateMatrix}" \
  --step-status "literalBaselineBudget=${status_literalBaselineBudget}" \
  --step-status "iosLiteralGuard=${status_iosLiteralGuard}" \
  --step-status "androidLiteralGuard=${status_androidLiteralGuard}" \
  --step-status "snapshot=${status_snapshot}" \
  --step-status "runtimeAccessibilityTests=${status_runtimeAccessibilityTests}" \
  --step-status "accessibility=${status_accessibility}" \
  --step-status "uxMetrics=${status_uxMetrics}" \
  --step-status "certificationFreshness=${status_certificationFreshness}" \
  --source-commit "${GITHUB_SHA:-}" \
  --source-ci-run-id "github-run-${GITHUB_RUN_ID:-local}:${GITHUB_JOB:-release-gates}"; then
  overall_failed=1
fi

echo "[16/17] Generate human-readable certification summary"
if ! python3 scripts/generate_visual_release_certification_summary.py \
  --runtime-test-results "${RUNTIME_TEST_RESULTS_ARTIFACT}" \
  --required-test-mode "${required_test_mode}"; then
  overall_failed=1
fi

echo "[17/17] Publish canonical release artifacts to docs/release/visual-system/latest"
mkdir -p "${CANONICAL_RELEASE_DIR}"
publish_files=(
  "release-certification-report.json"
  "release-certification-freshness-report.json"
  "release-certification-summary.md"
  "snapshot-report.json"
  "accessibility-report.json"
  "ux-metrics-report.json"
  "ux-metrics-validation-report.json"
  "variant-expiry-report.json"
  "state-matrix-release.json"
  "literal-baseline-burndown-report.json"
  "runtime-accessibility-test-results.json"
  "runtime-accessibility-assertions.json"
)
for file_name in "${publish_files[@]}"; do
  source_path="artifacts/visual-system/${file_name}"
  target_path="${CANONICAL_RELEASE_DIR}/${file_name}"
  if [[ ! -f "${source_path}" ]]; then
    echo "missing artifact for publish: ${source_path}"
    overall_failed=1
    continue
  fi
  cp "${source_path}" "${target_path}"
  if ! cmp -s "${source_path}" "${target_path}"; then
    echo "publish verification failed for ${file_name}"
    overall_failed=1
  fi
done

if command -v swiftlint >/dev/null 2>&1; then
  swiftlint --config ios/.swiftlint.yml || true
fi

if [[ ${overall_failed} -ne 0 ]]; then
  exit 1
fi
