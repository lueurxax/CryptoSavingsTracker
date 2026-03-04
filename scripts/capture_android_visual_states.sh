#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
EMULATOR_BIN="${ANDROID_SDK_ROOT}/emulator/emulator"
ADB_BIN="${ANDROID_SDK_ROOT}/platform-tools/adb"
APP_COMPONENT="com.xax.CryptoSavingsTracker/com.xax.CryptoSavingsTracker.debug.VisualStateCaptureActivity"
OUTPUT_DIR="${ROOT_DIR}/docs/screenshots/review-visual-system-unification-r4/android"
AVD_NAME="${ANDROID_CAPTURE_AVD:-}"
DUPLICATE_THRESHOLD="${ANDROID_CAPTURE_DUPLICATE_THRESHOLD:-0.20}"
INTEGRITY_REPORT="${ROOT_DIR}/artifacts/visual-system/android-capture-integrity.json"

components=(
  "planning.header_card"
  "planning.goal_row"
  "dashboard.summary_card"
  "settings.section_row"
)

states=(
  "default"
  "pressed"
  "disabled"
  "error"
  "loading"
  "empty"
  "stale"
  "recovery"
)

wait_for_capture_key() {
  local capture_key="$1"
  local timeout_seconds="${2:-10}"
  local deadline=$((SECONDS + timeout_seconds))
  while (( SECONDS < deadline )); do
    "${ADB_BIN}" shell uiautomator dump /sdcard/visual_capture_view.xml >/dev/null 2>&1 || true
    if "${ADB_BIN}" shell cat /sdcard/visual_capture_view.xml 2>/dev/null | tr -d '\r' | grep -Fq "${capture_key}"; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

if [[ ! -x "${EMULATOR_BIN}" ]]; then
  echo "error: emulator binary not found: ${EMULATOR_BIN}"
  exit 2
fi
if [[ ! -x "${ADB_BIN}" ]]; then
  echo "error: adb binary not found: ${ADB_BIN}"
  exit 2
fi

if [[ -z "${AVD_NAME}" ]]; then
  AVD_NAME="$("${EMULATOR_BIN}" -list-avds | head -n 1)"
fi
if [[ -z "${AVD_NAME}" ]]; then
  echo "error: no Android AVD found. Set ANDROID_CAPTURE_AVD."
  exit 2
fi

emulator_started=0
if ! "${ADB_BIN}" get-state >/dev/null 2>&1; then
  echo "Starting Android emulator: ${AVD_NAME}"
  "${EMULATOR_BIN}" -avd "${AVD_NAME}" -no-window -no-audio -no-boot-anim >/tmp/android-visual-capture-emulator.log 2>&1 &
  emulator_started=1
fi

"${ADB_BIN}" wait-for-device
until [[ "$("${ADB_BIN}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
  sleep 1
done

"${ADB_BIN}" shell settings put global window_animation_scale 0 >/dev/null 2>&1 || true
"${ADB_BIN}" shell settings put global transition_animation_scale 0 >/dev/null 2>&1 || true
"${ADB_BIN}" shell settings put global animator_duration_scale 0 >/dev/null 2>&1 || true

echo "Installing Android debug build..."
(cd android && ./gradlew :app:installDebug >/tmp/android-visual-capture-build.log)

for component in "${components[@]}"; do
  for state in "${states[@]}"; do
    target_dir="${OUTPUT_DIR}/${component}"
    mkdir -p "${target_dir}"
    target_file="${target_dir}/${state}.png"
    capture_key="CAPTURE:${component}:${state}"

    echo "Capturing Android ${component} / ${state}"
    is_visible=0
    for attempt in 1 2 3; do
      "${ADB_BIN}" shell am force-stop com.xax.CryptoSavingsTracker >/dev/null
      "${ADB_BIN}" shell am start -W -n "${APP_COMPONENT}" --es component "${component}" --es state "${state}" >/dev/null
      if wait_for_capture_key "${capture_key}" 12; then
        is_visible=1
        break
      fi
      sleep 0.8
    done
    if [[ ${is_visible} -ne 1 ]]; then
      echo "error: capture key not visible after launch: ${capture_key}"
      exit 1
    fi
    "${ADB_BIN}" exec-out screencap -p > "${target_file}"
  done
done

python3 - <<'PY' "${OUTPUT_DIR}" "${DUPLICATE_THRESHOLD}" "${INTEGRITY_REPORT}"
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
threshold = float(sys.argv[2])
report_path = Path(sys.argv[3])
files = sorted(root.rglob("*.png"))
groups = {}
for path in files:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    groups.setdefault(digest, []).append(str(path.relative_to(root)))

total = len(files)
duplicates = total - len(groups)
ratio = (duplicates / total) if total else 0.0
largest_group = max((len(v) for v in groups.values()), default=0)

report = {
    "totalFiles": total,
    "uniqueHashes": len(groups),
    "duplicateFiles": duplicates,
    "duplicateRatio": ratio,
    "largestDuplicateGroup": largest_group,
    "threshold": threshold,
    "groups": groups,
}
report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
if ratio > threshold:
    print(
        f"error: duplicate ratio {ratio:.3f} exceeds threshold {threshold:.3f} "
        f"(largest group: {largest_group}, report: {report_path})"
    )
    sys.exit(1)
print(
    f"Android capture integrity passed: duplicate ratio {ratio:.3f} "
    f"(report: {report_path})"
)
PY

if [[ ${emulator_started} -eq 1 ]]; then
  "${ADB_BIN}" emu kill >/dev/null 2>&1 || true
fi

echo "Android visual state captures written to: ${OUTPUT_DIR}"
