#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="ios/CryptoSavingsTracker/Views"
BASELINE_FILE="${ROOT_DIR}/docs/design/baselines/ios-visual-literals-baseline.txt"
TMP_FILE="$(mktemp)"
trap 'rm -f "${TMP_FILE}"' EXIT
UPDATE_BASELINE=0

if [[ "${1:-}" == "--update-baseline" ]]; then
  UPDATE_BASELINE=1
fi

if [[ ! -d "${ROOT_DIR}/${TARGET_DIR}" ]]; then
  echo "iOS views directory not found: ${ROOT_DIR}/${TARGET_DIR}"
  exit 2
fi

if [[ ! -f "${BASELINE_FILE}" ]]; then
  echo "iOS baseline file not found: ${BASELINE_FILE}"
  exit 2
fi

{
  cd "${ROOT_DIR}"
  rg -n --glob '!**/*Preview*.swift' --glob '!**/Previews/**' '\bColor\s*\(' "${TARGET_DIR}" || true
  rg -n --glob '!**/*Preview*.swift' --glob '!**/Previews/**' '\.(red|green|orange|yellow)\b' "${TARGET_DIR}" || true
  rg -n --glob '!**/*Preview*.swift' --glob '!**/Previews/**' '\.shadow\s*\(' "${TARGET_DIR}" || true
} | sort -u > "${TMP_FILE}"

if [[ ${UPDATE_BASELINE} -eq 1 ]]; then
  cp "${TMP_FILE}" "${BASELINE_FILE}"
  echo "Updated iOS visual literal baseline: ${BASELINE_FILE}"
  exit 0
fi

echo "Checking iOS visual literals against baseline..."
NEW_FINDINGS="$(comm -13 <(sort "${BASELINE_FILE}") <(sort "${TMP_FILE}"))"
if [[ -n "${NEW_FINDINGS}" ]]; then
  echo "error: new iOS visual literal violations detected:"
  echo "${NEW_FINDINGS}"
  exit 1
fi

echo "iOS visual literal checks passed (no new violations vs baseline)"
