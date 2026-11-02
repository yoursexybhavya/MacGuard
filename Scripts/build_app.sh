#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MACGUARD_DIR="$PROJECT_DIR/MacGuard"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="MacGuard.app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME"

echo "=== Building MacGuard Release Binary ==="
cd "$MACGUARD_DIR"
swift build -c release

RELEASE_BIN="$MACGUARD_DIR/.build/release/MacGuard"

echo "=== Creating macOS App Bundle Structure ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$RELEASE_BIN" "$APP_BUNDLE/Contents/MacOS/MacGuard"
cp "$MACGUARD_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$MACGUARD_DIR/Resources/MacGuard.icns" "$APP_BUNDLE/Contents/Resources/MacGuard.icns"

echo "=== Codesigning App Bundle ==="
codesign --force --deep -s - "$APP_BUNDLE"

echo "=== Verifying Bundle Signature ==="
codesign --verify --verbose "$APP_BUNDLE"

echo "=== Build Complete! ==="
echo "App bundle created at: $APP_BUNDLE"
ls -lh "$APP_BUNDLE/Contents/MacOS/MacGuard"
