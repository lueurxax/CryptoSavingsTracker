#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[1/9] Validate visual token schema"
python3 scripts/validate_visual_tokens.py

echo "[2/9] Check cross-platform token parity"
python3 scripts/check_visual_token_parity.py

echo "[3/9] Check approved variant expiry controls"
python3 scripts/check_visual_variant_expiry.py

echo "[4/9] Validate visual state matrix (design-complete)"
python3 scripts/validate_visual_state_matrix.py --phase design-complete

echo "[5/9] Validate visual literal baseline burndown budgets"
python3 scripts/check_visual_literal_baseline_burndown.py --wave "${VISUAL_SYSTEM_WAVE:-wave1}"

echo "[6/9] Run iOS visual literal guard"
bash scripts/check_ios_visual_literals.sh

echo "[7/9] Run Android visual literal guard"
bash scripts/check_android_visual_literals.sh

echo "[8/9] Run snapshot checks (PR mode)"
python3 scripts/run_visual_snapshot_checks.py --mode pr

echo "[9/9] Run accessibility checks (PR mode)"
python3 scripts/run_visual_accessibility_checks.py --mode pr

echo "Optional lint tools (non-blocking for local run):"
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint --config ios/.swiftlint.yml
else
  echo "- swiftlint not installed; skipped."
fi

if [[ "${RUN_ANDROID_DETEKT:-0}" == "1" ]]; then
  if [[ -x "android/gradlew" ]] && (cd android && ./gradlew -q tasks --all | rg -q '(^|:)detekt($| )'); then
    (cd android && ./gradlew app:detekt --config config/detekt/detekt.yml)
  else
    echo "- RUN_ANDROID_DETEKT=1, but detekt task is unavailable; skipped."
  fi
else
  echo "- Android detekt skipped (set RUN_ANDROID_DETEKT=1 to enable)."
fi
