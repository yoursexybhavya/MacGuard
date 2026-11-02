#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Requires a Developer ID Application certificate and a notarytool keychain
# profile named "MacGuard Notary". Create the profile with:
#   xcrun notarytool store-credentials "MacGuard Notary" \
#     --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD"
#
# This script is intentionally not part of the default build. Notarization
# requires credentials that must never be committed to the repository.

if [[ ! -f dist/MacGuard.zip ]]; then
  echo "Run ./scripts/package.sh first." >&2
  exit 1
fi

xcrun notarytool submit dist/MacGuard.zip --keychain-profile "MacGuard Notary" --wait
xcrun stapler staple build/DerivedData/Build/Products/Release/MacGuard.app
xcrun stapler validate build/DerivedData/Build/Products/Release/MacGuard.app
echo "Notarization complete."
