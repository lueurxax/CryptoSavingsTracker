#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

IOS_SIMULATOR_NAME="${IOS_SIMULATOR_NAME:-iPhone 16e}"
DERIVED_DATA_PATH="${ROOT_DIR}/ios/DerivedDataVisualCapture"
OUTPUT_DIR="${ROOT_DIR}/docs/screenshots/review-visual-system-unification-r4/production/ios"
BUNDLE_ID="xax.CryptoSavingsTracker"
REPORT_OUT="${ROOT_DIR}/artifacts/visual-system/ios-production-capture-report.json"
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

xcrun simctl boot "${SIMULATOR_UDID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${SIMULATOR_UDID}" -b

echo "Building iOS app for simulator..."
xcodebuild \
  -project ios/CryptoSavingsTracker.xcodeproj \
  -scheme CryptoSavingsTracker \
  -configuration Debug \
  -destination "id=${SIMULATOR_UDID}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build >/tmp/ios-production-capture-build.log

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug-iphonesimulator/CryptoSavingsTracker.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: built app not found at ${APP_PATH}"
  exit 2
fi

xcrun simctl install "${SIMULATOR_UDID}" "${APP_PATH}" >/dev/null

captured_files=()
for flow in "${flows[@]}"; do
  for state in "${states[@]}"; do
    target_dir="${OUTPUT_DIR}/${flow}"
    mkdir -p "${target_dir}"
    target_file="${target_dir}/${state}.png"

    echo "Capturing iOS production flow ${flow} / ${state}"
    SIMCTL_CHILD_VISUAL_CAPTURE_MODE="production" \
    SIMCTL_CHILD_VISUAL_PRODUCTION_FLOW="${flow}" \
    SIMCTL_CHILD_VISUAL_PRODUCTION_STATE="${state}" \
    xcrun simctl launch --terminate-running-process "${SIMULATOR_UDID}" "${BUNDLE_ID}" >/dev/null

    sleep 1.2
    xcrun simctl io "${SIMULATOR_UDID}" screenshot "${target_file}" >/dev/null
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
    "platform": "ios",
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

echo "iOS production flow captures written to: ${OUTPUT_DIR}"
echo "iOS production capture report: ${REPORT_OUT}"
