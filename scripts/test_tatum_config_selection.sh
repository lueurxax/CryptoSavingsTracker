#!/bin/sh
set -eu

REPOSITORY_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SCRIPT_PATH="$REPOSITORY_ROOT/ios/scripts/copy-app-config.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/tatum-config-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

make_fixture() {
    fixture_dir="$1"
    mkdir -p "$fixture_dir"
    cp "$REPOSITORY_ROOT/ios/Config.example.plist" "$fixture_dir/Config.plist"
    cp "$REPOSITORY_ROOT/ios/Config.example.plist" "$fixture_dir/Config.production.plist"
    /usr/libexec/PlistBuddy -c "Set :TatumAPIKey development-test-key" "$fixture_dir/Config.plist"
    /usr/libexec/PlistBuddy -c "Set :TatumAPIKey production-test-key" "$fixture_dir/Config.production.plist"
}

run_copy() {
    environment="$1"
    fixture_dir="$2"
    target_dir="$3"

    PROJECT_DIR="$fixture_dir" \
    TARGET_BUILD_DIR="$target_dir" \
    UNLOCALIZED_RESOURCES_FOLDER_PATH="Resources" \
    TATUM_ENVIRONMENT="$environment" \
        /bin/sh "$SCRIPT_PATH"
}

assert_bundled_key() {
    expected_key="$1"
    target_dir="$2"
    actual_key=$(/usr/libexec/PlistBuddy -c "Print :TatumAPIKey" "$target_dir/Resources/Config.plist")

    if [ "$actual_key" != "$expected_key" ]; then
        echo "Expected bundled test key '$expected_key', got '$actual_key'" >&2
        exit 1
    fi
}

fixture_dir="$TEST_ROOT/valid"
make_fixture "$fixture_dir"

development_target="$TEST_ROOT/development-target"
run_copy development "$fixture_dir" "$development_target"
assert_bundled_key development-test-key "$development_target"

production_target="$TEST_ROOT/production-target"
run_copy production "$fixture_dir" "$production_target"
assert_bundled_key production-test-key "$production_target"

missing_fixture="$TEST_ROOT/missing-production"
make_fixture "$missing_fixture"
rm "$missing_fixture/Config.production.plist"
if run_copy production "$missing_fixture" "$TEST_ROOT/missing-target"; then
    echo "Production copy unexpectedly succeeded without Config.production.plist" >&2
    exit 1
fi

placeholder_fixture="$TEST_ROOT/placeholder-production"
make_fixture "$placeholder_fixture"
/usr/libexec/PlistBuddy -c "Set :TatumAPIKey YOUR_TATUM_API_KEY" "$placeholder_fixture/Config.production.plist"
if run_copy production "$placeholder_fixture" "$TEST_ROOT/placeholder-target"; then
    echo "Production copy unexpectedly accepted the placeholder Tatum key" >&2
    exit 1
fi

echo "Tatum configuration selection tests passed"
