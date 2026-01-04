#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_ROOT="${SCRIPT_DIR}/.."
KEYSTORE_FILE="${ANDROID_ROOT}/keystore.jks"
PROPS_FILE="${ANDROID_ROOT}/keystore.properties"

if ! command -v keytool >/dev/null 2>&1; then
    echo "keytool not found. Install a JDK and ensure keytool is on PATH."
    exit 1
fi

read -rp "Key alias [crypto-savings]: " KEY_ALIAS
KEY_ALIAS="${KEY_ALIAS:-crypto-savings}"

read -rsp "Keystore password: " STORE_PASS
echo

read -rsp "Key password (leave blank to reuse keystore password): " KEY_PASS
echo

if [[ -z "${KEY_PASS}" ]]; then
    KEY_PASS="${STORE_PASS}"
fi

if [[ -f "${KEYSTORE_FILE}" ]]; then
    echo "Keystore already exists at ${KEYSTORE_FILE}. Skipping creation."
else
    echo "Creating keystore at ${KEYSTORE_FILE}"
    keytool -genkeypair -v \
        -keystore "${KEYSTORE_FILE}" \
        -alias "${KEY_ALIAS}" \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -storepass "${STORE_PASS}" \
        -keypass "${KEY_PASS}" \
        -dname "CN=CryptoSavingsTracker, OU=Android, O=CryptoSavingsTracker, L=City, S=State, C=US"
fi

cat > "${PROPS_FILE}" <<EOF
storeFile=keystore.jks
storePassword=${STORE_PASS}
keyAlias=${KEY_ALIAS}
keyPassword=${KEY_PASS}
EOF

echo "Wrote signing config to ${PROPS_FILE} (do not commit this file)."

pushd "${ANDROID_ROOT}" >/dev/null
./gradlew :app:assembleRelease
popd >/dev/null

echo "Release APK:"
echo "${ANDROID_ROOT}/app/build/outputs/apk/release/app-release.apk"
