#!/bin/sh
set -eu

: "${PROJECT_DIR:?PROJECT_DIR is required}"
: "${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}"
: "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?UNLOCALIZED_RESOURCES_FOLDER_PATH is required}"
: "${TATUM_ENVIRONMENT:?TATUM_ENVIRONMENT is required}"

case "$TATUM_ENVIRONMENT" in
    development)
        source_config="$PROJECT_DIR/Config.plist"
        ;;
    production)
        source_config="$PROJECT_DIR/Config.production.plist"
        ;;
    *)
        echo "error: Unsupported Tatum environment '$TATUM_ENVIRONMENT'" >&2
        exit 1
        ;;
esac

if [ ! -f "$source_config" ]; then
    echo "error: Missing Tatum configuration: $source_config" >&2
    exit 1
fi

if ! tatum_api_key=$(/usr/libexec/PlistBuddy -c "Print :TatumAPIKey" "$source_config" 2>/dev/null); then
    echo "error: TatumAPIKey is missing from $(basename "$source_config")" >&2
    exit 1
fi

case "$tatum_api_key" in
    ""|YOUR_TATUM_API_KEY)
        echo "error: TatumAPIKey is not configured in $(basename "$source_config")" >&2
        exit 1
        ;;
esac

destination_config="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Config.plist"
mkdir -p "$(dirname "$destination_config")"
cp "$source_config" "$destination_config"

echo "Bundled $(basename "$source_config") for Tatum $TATUM_ENVIRONMENT"
