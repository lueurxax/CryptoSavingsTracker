#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
EMULATOR_BIN="${ANDROID_SDK_ROOT}/emulator/emulator"
ADB_BIN="${ANDROID_SDK_ROOT}/platform-tools/adb"
APP_COMPONENT="com.xax.CryptoSavingsTracker/com.xax.CryptoSavingsTracker.debug.ProductionFlowCaptureActivity"
OUTPUT_DIR="${ROOT_DIR}/docs/screenshots/review-visual-system-unification-r4/production/android"
AVD_NAME="${ANDROID_CAPTURE_AVD:-}"
REPORT_OUT="${ROOT_DIR}/artifacts/visual-system/android-production-capture-report.json"
PRODUCTION_MANIFEST="${ROOT_DIR}/docs/screenshots/review-visual-system-unification-r4/production/manifest.v1.json"

flows=(
  "planning"
  "dashboard"
  "settings"
)

states=(
  "default"
  "error"
  "recovery"
)

wait_for_capture_key() {
  local capture_key="$1"
  local timeout_seconds="${2:-10}"
  local deadline=$((SECONDS + timeout_seconds))
  while (( SECONDS < deadline )); do
    "${ADB_BIN}" shell uiautomator dump /sdcard/visual_production_capture_view.xml >/dev/null 2>&1 || true
    if "${ADB_BIN}" shell cat /sdcard/visual_production_capture_view.xml 2>/dev/null | tr -d '\r' | grep -Fq "${capture_key}"; then
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
  "${EMULATOR_BIN}" -avd "${AVD_NAME}" -no-window -no-audio -no-boot-anim >/tmp/android-production-capture-emulator.log 2>&1 &
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
(cd android && ./gradlew :app:installDebug >/tmp/android-production-capture-build.log)

captured_files=()
for flow in "${flows[@]}"; do
  for state in "${states[@]}"; do
    target_dir="${OUTPUT_DIR}/${flow}"
    mkdir -p "${target_dir}"
    target_file="${target_dir}/${state}.png"
    capture_key="PRODUCTION_CAPTURE:${flow}:${state}"

    echo "Capturing Android production flow ${flow} / ${state}"
    is_visible=0
    for attempt in 1 2 3; do
      "${ADB_BIN}" shell am force-stop com.xax.CryptoSavingsTracker >/dev/null
      "${ADB_BIN}" shell am start -W -n "${APP_COMPONENT}" --es flow "${flow}" --es state "${state}" >/dev/null
      if wait_for_capture_key "${capture_key}" 14; then
        is_visible=1
        break
      fi
      sleep 0.8
    done
    if [[ ${is_visible} -ne 1 ]]; then
      echo "error: production capture label not visible: ${capture_key}"
      exit 1
    fi

    "${ADB_BIN}" exec-out screencap -p > "${target_file}"
    captured_files+=("${target_file}")
  done
done

python3 - <<'PY' "${ROOT_DIR}" "${OUTPUT_DIR}" "${REPORT_OUT}" "${captured_files[@]}"
import hashlib
import json
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
report_path = Path(sys.argv[3])
files = [Path(p) for p in sys.argv[4:]]

rows = []
for file_path in sorted(files):
    rel = file_path.relative_to(repo_root)
    digest = hashlib.sha256(file_path.read_bytes()).hexdigest()
    rows.append({
        "artifactRef": str(rel),
        "sha256": digest,
    })

payload = {
    "reportVersion": "v1",
    "platform": "android",
    "captureMode": "production-flow",
    "artifactRoot": str(output_dir.relative_to(repo_root)),
    "artifacts": rows,
}
report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(f"wrote report: {report_path}")
PY

python3 - <<'PY' "${PRODUCTION_MANIFEST}"
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

manifest_path = Path(__import__('sys').argv[1])
if manifest_path.exists():
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip().lower()
    payload["evidenceCommitSha"] = sha
    payload["capturedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    manifest_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"updated production manifest metadata: {manifest_path}")
PY

if [[ ${emulator_started} -eq 1 ]]; then
  "${ADB_BIN}" emu kill >/dev/null 2>&1 || true
fi

echo "Android production flow captures written to: ${OUTPUT_DIR}"
echo "Android production capture report: ${REPORT_OUT}"
