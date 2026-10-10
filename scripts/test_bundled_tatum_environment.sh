#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <app-bundle> <development|production> <source-config>" >&2
    exit 2
fi

app_bundle="$1"
expected_environment="$2"
source_config="$3"
bundled_config="$app_bundle/Config.plist"

actual_environment=$(/usr/libexec/PlistBuddy -c "Print :TatumEnvironment" "$app_bundle/Info.plist")
if [ "$actual_environment" != "$expected_environment" ]; then
    echo "Expected TatumEnvironment '$expected_environment', got '$actual_environment'" >&2
    exit 1
fi

if [ ! -f "$bundled_config" ]; then
    echo "Config.plist is missing from $app_bundle" >&2
    exit 1
fi

if [ -e "$app_bundle/Config.example.plist" ] || [ -e "$app_bundle/Config.production.plist" ]; then
    echo "An unselected configuration file was bundled" >&2
    exit 1
fi

if ! cmp -s "$source_config" "$bundled_config"; then
    echo "Bundled Config.plist does not match the selected source" >&2
    exit 1
fi

echo "Bundled Tatum environment '$expected_environment' is correct"
