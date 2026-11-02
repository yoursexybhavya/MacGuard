# Changelog

All notable changes to MacGuard are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-11-02

### Added

- Native macOS SwiftUI application with a committed Xcode project.
- Actor-based scan engine for ten categories: user caches, logs, developer artifacts, browser caches, Trash, Downloads, installers, large files, old files, and Mail attachments.
- Smart Scan with progress, cancellation, per-category results, per-file selection, and Finder reveal.
- Duplicate finder using a size prefilter and streaming SHA-256, with keeper protection and wasted-byte reporting.
- File organizer with user-defined rules, read-only preview, per-change inclusion, apply, and undo.
- Local vault with restore, retention, purge, and clear.
- History with restore, undo, JSON export, and a 200-operation cap.
- Settings for appearance, menu bar quick actions, launch at login, notifications, confirmation policy, removal method, vault retention, protected folders, exclusions, thresholds, schedule, and privacy.
- Menu bar popover with storage summary and quick actions.
- Three-step onboarding.
- Accessibility labels, keyboard shortcuts, and semantic controls.
- Swift Testing suite covering safety, duplicates, vault, history, settings, organizer, and storage.
- GitHub Actions workflow for build and test.
- Deterministic Xcode project generator.

### Safety

- Safe categories selected by default; review categories require explicit selection.
- Hard-protected system and privacy paths.
- Category roots, exclusions, symlink rejection, and top-level-only rules.
- Second-pass validation in the cleaner.
- Duplicate cleanup refuses to remove every copy.
- Organizer never overwrites a file.
- Vault by default; Trash clearly labeled as not automatically freeing space.

### Privacy

- No network client or server entitlement.
- No analytics, telemetry, crash upload, account, or update check.
- All data local to `~/Library/Application Support/MacGuard`.
- Local notifications only.

### Notes

- The sandbox used to author this release is Linux; the Xcode build and test run were not executed here. Run `make test` on macOS as the first verification step.
- The app is English-only in 1.0.0.
- Notarization and Developer ID signing are not automated in this release.
