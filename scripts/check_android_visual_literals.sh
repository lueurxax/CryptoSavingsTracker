#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation"
BASELINE_FILE="${ROOT_DIR}/docs/design/baselines/android-visual-literals-baseline.txt"
TMP_FILE="$(mktemp)"
trap 'rm -f "${TMP_FILE}"' EXIT
UPDATE_BASELINE=0

if [[ "${1:-}" == "--update-baseline" ]]; then
  UPDATE_BASELINE=1
fi

if [[ ! -d "${ROOT_DIR}/${TARGET_DIR}" ]]; then
  echo "Android presentation directory not found: ${ROOT_DIR}/${TARGET_DIR}"
  exit 2
fi

if [[ ! -f "${BASELINE_FILE}" ]]; then
  echo "Android baseline file not found: ${BASELINE_FILE}"
  exit 2
fi

{
  cd "${ROOT_DIR}"
  rg -n --glob '!**/theme/**' --glob '!**/preview/**' 'Color\(0x[0-9A-Fa-f]{8}\)' "${TARGET_DIR}" || true
  rg -n --glob '!**/theme/**' --glob '!**/preview/**' '(\.shadow\(|elevation\s*=\s*[0-9]+(\.[0-9]+)?\.dp)' "${TARGET_DIR}" || true
} | sort -u > "${TMP_FILE}"

if [[ ${UPDATE_BASELINE} -eq 1 ]]; then
  cp "${TMP_FILE}" "${BASELINE_FILE}"
  echo "Updated Android visual literal baseline: ${BASELINE_FILE}"
  exit 0
fi

echo "Checking Android visual literals against baseline..."
NEW_FINDINGS="$(comm -13 <(sort "${BASELINE_FILE}") <(sort "${TMP_FILE}"))"
if [[ -n "${NEW_FINDINGS}" ]]; then
  echo "error: new Android visual literal violations detected:"
  echo "${NEW_FINDINGS}"
  exit 1
fi

echo "Android visual literal checks passed (no new violations vs baseline)"
