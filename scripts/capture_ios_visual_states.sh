#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

IOS_SIMULATOR_NAME="${IOS_SIMULATOR_NAME:-iPhone 16e}"
DERIVED_DATA_PATH="${ROOT_DIR}/ios/DerivedDataVisualCapture"
OUTPUT_DIR="${ROOT_DIR}/docs/screenshots/review-visual-system-unification-r4/ios"
BUNDLE_ID="xax.CryptoSavingsTracker"

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

SIMULATOR_UDID="$(
  xcrun simctl list devices available --json | python3 -c '
import json,sys
name = sys.argv[1]
payload = json.load(sys.stdin)
for _, devices in payload.get("devices", {}).items():
    for device in devices:
        if device.get("isAvailable") and device.get("name") == name:
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit(1)
' "${IOS_SIMULATOR_NAME}"
)"

echo "Using iOS simulator: ${IOS_SIMULATOR_NAME} (${SIMULATOR_UDID})"

xcrun simctl boot "${SIMULATOR_UDID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${SIMULATOR_UDID}" -b

echo "Building iOS app for simulator..."
xcodebuild \
  -project ios/CryptoSavingsTracker.xcodeproj \
  -scheme CryptoSavingsTracker \
  -configuration Debug \
  -destination "id=${SIMULATOR_UDID}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build >/tmp/ios-visual-capture-build.log

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug-iphonesimulator/CryptoSavingsTracker.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: built app not found at ${APP_PATH}"
  exit 2
fi

xcrun simctl install "${SIMULATOR_UDID}" "${APP_PATH}" >/dev/null

for component in "${components[@]}"; do
  for state in "${states[@]}"; do
    target_dir="${OUTPUT_DIR}/${component}"
    mkdir -p "${target_dir}"
    target_file="${target_dir}/${state}.png"

    echo "Capturing iOS ${component} / ${state}"
    SIMCTL_CHILD_VISUAL_CAPTURE_COMPONENT="${component}" \
    SIMCTL_CHILD_VISUAL_CAPTURE_STATE="${state}" \
    xcrun simctl launch --terminate-running-process "${SIMULATOR_UDID}" "${BUNDLE_ID}" >/dev/null

    sleep 1
    xcrun simctl io "${SIMULATOR_UDID}" screenshot "${target_file}" >/dev/null
  done
done

echo "iOS visual state captures written to: ${OUTPUT_DIR}"
