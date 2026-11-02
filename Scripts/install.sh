#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="MacGuard.app"
SOURCE_APP="$BUILD_DIR/$APP_NAME"
TARGET_DIR="/Applications"
TARGET_APP="$TARGET_DIR/$APP_NAME"

echo "=== Installing MacGuard ==="

if [ ! -d "$SOURCE_APP" ]; then
    echo "App bundle not found at $SOURCE_APP. Building now..."
    "$SCRIPT_DIR/build_app.sh"
fi

echo "Copying $APP_NAME to $TARGET_DIR..."
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

echo "=== Installation Verified ==="
echo "MacGuard installed at: $TARGET_APP"
ls -ld "$TARGET_APP"
