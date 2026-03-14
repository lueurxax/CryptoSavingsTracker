#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

IOS_SIMULATOR_NAME="${IOS_SIMULATOR_NAME:-iPhone 16e}"
DERIVED_DATA_PATH="${ROOT_DIR}/ios/DerivedDataPresentationCapture"
OUTPUT_DIR="${ROOT_DIR}/docs/screenshots/presentation-refresh-2026-03-07/ios"

SIMULATOR_UDID="$({
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
})"

echo "Using iOS simulator: ${IOS_SIMULATOR_NAME} (${SIMULATOR_UDID})"
mkdir -p "${OUTPUT_DIR}"

xcrun simctl boot "${SIMULATOR_UDID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${SIMULATOR_UDID}" -b

PRESENTATION_SCREENSHOT_OUTPUT_DIR="${OUTPUT_DIR}" \
xcodebuild \
  -project ios/CryptoSavingsTracker.xcodeproj \
  -scheme CryptoSavingsTrackerUITests \
  -destination "id=${SIMULATOR_UDID}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -only-testing:CryptoSavingsTrackerUITests/PresentationScreenshotUITests/testCapturePresentationScreenshots \
  test

echo "Presentation screenshots written to: ${OUTPUT_DIR}"
