# Releasing MacGuard

This repository is private. Releases are intended for the repository owner and authorized collaborators, not the public App Store.

## 1. Prerequisites

- macOS 14+ and Xcode 16+.
- A Developer ID Application certificate installed in the login keychain.
- A notarytool keychain profile (see `scripts/notarize.sh`).
- The app's bundle identifier (`com.macguard.app`) registered with the developer team.

## 2. Version

Update all three values together:

- `Sources/MacGuard/Info.plist` → `CFBundleShortVersionString` and `CFBundleVersion`.
- Project build settings → `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `scripts/generate_project.py`.
- `CHANGELOG.md`.

Regenerate the project after changing the generator:

```bash
python3 scripts/generate_project.py
```

## 3. Build and package

```bash
./scripts/build.sh
./scripts/package.sh
```

The output is `dist/MacGuard.zip`.

## 4. Notarize and staple

```bash
./scripts/notarize.sh
```

Verify:

```bash
spctl -a -vvv -t install build/DerivedData/Build/Products/Release/MacGuard.app
codesign -dv --verbose=4 build/DerivedData/Build/Products/Release/MacGuard.app
```

## 5. Smoke test

- Open the app and complete onboarding.
- Run a Smart Scan with only safe categories.
- Verify the confirmation sheet and the vault.
- Clean a small set of files, then restore them from History.
- Run the duplicate finder on a small folder.
- Preview and apply an organizer rule, then undo it.
- Check Settings → Privacy data paths.
- Verify the menu bar popover.

## 6. Distribute privately

Share the notarized zip through the private channel used for this project. Do not publish the repository or the build publicly.

## 7. Post-release

- Tag the release in the private repository.
- Record the build number and known issues in `CHANGELOG.md`.
- Keep the previous notarized build available for rollback.

## Notes

- The app has no auto-update and no network access. Updates are manual.
- The app does not use the App Store; distribution is Developer ID + notarization.
- App Sandbox is disabled intentionally. See `SECURITY.md`.
