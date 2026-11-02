#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MacGuard.app"
if [[ ! -d "$APP" ]]; then
  APP="build/DerivedData/Build/Products/Release/MacGuard.app"
fi
if [[ ! -d "$APP" ]]; then
  echo "Release build not found. Run ./Scripts/build_app.sh first." >&2
  exit 1
fi

mkdir -p dist
rm -f dist/MacGuard.zip
ditto -c -k --keepParent "$APP" dist/MacGuard.zip
echo "Created dist/MacGuard.zip"
